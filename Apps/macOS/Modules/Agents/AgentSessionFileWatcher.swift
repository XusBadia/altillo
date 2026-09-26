import AltilloAgents
import CoreServices
import Foundation

/// Passive detection: follows Claude Code transcripts (`~/.claude/projects/<folder>/<session>.jsonl`), Codex
/// rollouts (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`) and Gemini CLI chats
/// (`~/.gemini/tmp/<project>/chats/session-*.jsonl`, phase 14) with FSEvents, so sessions show up even before hooks
/// are installed. Read-only. Only the tail of a file that changed is read, on a background queue; when nothing
/// is written there is no work at all (no polling).
final class AgentSessionFileWatcher: @unchecked Sendable {
    struct Roots: Sendable {
        var claudeProjects: URL
        var codexSessions: URL
        /// `~/.gemini/tmp`; nil leaves Gemini out (tests).
        var geminiTemp: URL? = nil

        static var standard: Roots {
            let home = URL(fileURLWithPath: NSHomeDirectory())
            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".codex")
            return Roots(claudeProjects: home.appendingPathComponent(".claude/projects"),
                         codexSessions: codexHome.appendingPathComponent("sessions"),
                         geminiTemp: home.appendingPathComponent(".gemini/tmp"))
        }

        /// `~/.gemini/projects.json`, next to `tmp`: which project path each chat folder belongs to.
        var geminiRegistry: URL? {
            geminiTemp?.deletingLastPathComponent().appendingPathComponent("projects.json")
        }
    }

    /// Called on the watcher's queue. `initial` is true for what the startup scan found (already there before
    /// Altillo looked, so it shouldn't peek).
    var onSnapshot: @Sendable (SessionFileSnapshot, _ initial: Bool) -> Void = { _, _ in }

    let roots: Roots
    /// Files quiet for longer than this are ignored.
    let window: TimeInterval
    private let queue = DispatchQueue(label: "me.badia.altillo.agents.files", qos: .utility)
    private var stream: FSEventStreamRef?
    /// Size at the last read, per file: FSEvents also fires for metadata changes.
    private var lastSize: [String: UInt64] = [:]
    private var codexMeta: [String: CodexRollout.Meta] = [:]
    private var geminiMeta: [String: GeminiChat.Meta] = [:]
    /// Gemini project id → path, and the registry's modification date when read.
    private var geminiProjects: [String: String] = [:]
    private var geminiRegistryDate: Date?

    init(roots: Roots = .standard, window: TimeInterval = AgentSessionAging.dropAfter) {
        self.roots = roots
        self.window = window
    }

    func start() {
        queue.async { [self] in
            guard stream == nil else { return }
            // Stream first, so nothing written during the scan is missed (a file read twice is harmless).
            startStream()
            scanRecent()
        }
    }

    func stop() {
        queue.sync {
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
            stream = nil
            lastSize.removeAll()
            codexMeta.removeAll()
            geminiMeta.removeAll()
        }
    }

    /// Reads one file now (tests; a hook pointing at a transcript).
    func refresh(_ url: URL, initial: Bool = false) {
        queue.async { [self] in read(url, initial: initial, force: true) }
    }

    /// The last assistant message of a Claude transcript (for a `Stop` hook without one). Off the main actor.
    static func lastClaudeMessage(transcript: URL) -> String? {
        guard let tail = SessionFileTail.read(transcript, maxBytes: 128 << 10) else { return nil }
        return ClaudeTranscript.lastAssistantMessage(tail: tail.lines)
    }

    // MARK: - Queue-confined

    private func scanRecent() {
        let manager = FileManager.default
        let cutoff = Date().addingTimeInterval(-window)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]

        if let folders = try? manager.contentsOfDirectory(at: roots.claudeProjects, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) {
            for folder in folders {
                guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles]) else { continue }
                for file in files where file.pathExtension == "jsonl" {
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    if modified >= cutoff { read(file, initial: true, force: true) }
                }
            }
        }

        // Rollouts live in day folders; a session started yesterday can still be writing today.
        let calendar = Calendar.current
        for daysAgo in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = roots.codexSessions
                .appendingPathComponent(String(format: "%04d", parts.year ?? 0))
                .appendingPathComponent(String(format: "%02d", parts.month ?? 0))
                .appendingPathComponent(String(format: "%02d", parts.day ?? 0))
            guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                               options: [.skipsHiddenFiles]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if modified >= cutoff { read(file, initial: true, force: true) }
            }
        }
        scanGemini(cutoff: cutoff)
    }

    private func scanGemini(cutoff: Date) {
        guard let root = roots.geminiTemp else { return }
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) else { return }
        for project in projects {
            let chats = project.appendingPathComponent("chats")
            guard let files = try? manager.contentsOfDirectory(at: chats, includingPropertiesForKeys: [.contentModificationDateKey],
                                                               options: [.skipsHiddenFiles]) else { continue }
            for file in files where GeminiChat.isChatFile(file) {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if modified >= cutoff { read(file, initial: true, force: true) }
            }
        }
    }

    private func geminiCWD(projectID: String) -> String? {
        guard let registry = roots.geminiRegistry else { return nil }
        let modified = (try? registry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if modified != geminiRegistryDate || (geminiProjects[projectID] == nil && modified != nil) {
            geminiRegistryDate = modified
            geminiProjects = (try? Data(contentsOf: registry)).map(GeminiChat.projectPaths(registry:)) ?? [:]
        }
        return geminiProjects[projectID]
    }

    private func startStream() {
        let paths = ([roots.claudeProjects, roots.codexSessions] + [roots.geminiTemp].compactMap { $0 })
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<AgentSessionFileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as? [String] ?? []
            watcher.changed(paths.prefix(count))
        }
        // No IgnoreSelf: Altillo never writes there, and the hosted tests do.
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags) else {
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func changed(_ paths: ArraySlice<String>) {
        var seen = Set<String>()
        for path in paths where path.hasSuffix(".jsonl") && seen.insert(path).inserted {
            read(URL(fileURLWithPath: path), initial: false, force: false)
        }
    }

    private func read(_ url: URL, initial: Bool, force: Bool) {
        // FSEvents reports real paths (/private/var/…) while Foundation often drops /private: compare both ways.
        let path = Self.canonical(url.path)
        let claudeRoot = Self.canonical(roots.claudeProjects.path)
        let isClaude = path.hasPrefix(claudeRoot + "/")
        let isCodex = path.hasPrefix(Self.canonical(roots.codexSessions.path) + "/")
        let isGemini = roots.geminiTemp.map { path.hasPrefix(Self.canonical($0.path) + "/") } ?? false
        guard isClaude || isCodex || isGemini else { return }

        let snapshot: SessionFileSnapshot?
        if isGemini {
            guard GeminiChat.isChatFile(url) else { return }
            if geminiMeta[path] == nil, let line = SessionFileTail.firstLine(url), let meta = GeminiChat.meta(firstLine: line) {
                geminiMeta[path] = meta
            }
            guard let meta = geminiMeta[path], !meta.isSubagent, let tail = tail(url, force: force) else { return }
            let projectID = GeminiChat.projectID(for: url)
            snapshot = GeminiChat.snapshot(tail: tail.lines, meta: meta, cwd: geminiCWD(projectID: projectID),
                                           projectID: projectID, modified: tail.modified)
        } else if isClaude {
            // Only `<folder>/<session>.jsonl`; subagent transcripts sit deeper.
            let relative = path.dropFirst(claudeRoot.count + 1)
            guard relative.split(separator: "/").count == 2, let sessionID = ClaudeTranscript.sessionID(for: url),
                  let tail = tail(url, force: force) else { return }
            snapshot = ClaudeTranscript.snapshot(tail: tail.lines, sessionID: sessionID, modified: tail.modified,
                                                 projectFolder: url.deletingLastPathComponent().lastPathComponent)
        } else {
            guard let sessionID = CodexRollout.sessionID(for: url) else { return }
            if codexMeta[path] == nil, let line = SessionFileTail.firstLine(url), let meta = CodexRollout.meta(firstLine: line) {
                codexMeta[path] = meta
            }
            let meta = codexMeta[path]
            if meta?.isSubagent == true || meta?.isAutomation == true { return }
            guard let tail = tail(url, force: force) else { return }
            snapshot = CodexRollout.snapshot(tail: tail.lines, meta: meta, sessionID: sessionID, modified: tail.modified)
        }
        guard let snapshot, Date().timeIntervalSince(snapshot.lastActivity) < window else { return }
        onSnapshot(snapshot, initial)
    }

    static func canonical(_ path: String) -> String {
        for prefix in ["/private/var/", "/private/tmp/", "/private/etc/"] where path.hasPrefix(prefix) {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    private func tail(_ url: URL, force: Bool) -> SessionFileTail.Tail? {
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            lastSize[Self.canonical(url.path)] = nil
            return nil
        }
        let size = UInt64(info.st_size)
        if !force, lastSize[Self.canonical(url.path)] == size { return nil }
        if lastSize.count > 4096 { lastSize.removeAll() }
        lastSize[Self.canonical(url.path)] = size
        return SessionFileTail.read(url)
    }
}
