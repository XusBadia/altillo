import Foundation

// The hook installer (PLAN §5.3, risk table §9): puts Altillo's hooks into Claude Code's `settings.json` and Codex's
// `hooks.json`, and takes them out again. It only ever touches Altillo's own entries (recognised by their command,
// which runs `altillo-hook`), shows the exact diff before writing, backs the file up, writes atomically and refuses
// to touch a file it can't parse.

/// Where things live. `live` is the real Mac; tests point everything at a temporary directory.
struct AgentHookEnvironment: Sendable {
    var home: URL
    var variables: [String: String]
    /// `~/Library/Application Support/Altillo`: the stable hook link, backups and the install record.
    var supportDirectory: URL

    static var live: AgentHookEnvironment {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return AgentHookEnvironment(home: fileManager.homeDirectoryForCurrentUser,
                                    variables: ProcessInfo.processInfo.environment,
                                    supportDirectory: support.appending(path: "Altillo", directoryHint: .isDirectory))
    }

    /// `$CLAUDE_CONFIG_DIR` / `$CODEX_HOME` when set, otherwise `~/.claude` / `~/.codex`.
    func configDirectory(for target: AgentHookTarget) -> URL {
        if let custom = variables[target.configDirectoryVariable]?.trimmingCharacters(in: .whitespaces),
           !custom.isEmpty {
            let expanded = custom.hasPrefix("~/") ? home.path + custom.dropFirst() : custom
            return URL(filePath: expanded, directoryHint: .isDirectory)
        }
        return home.appending(path: target.defaultConfigDirectoryName, directoryHint: .isDirectory)
    }

    func configFile(for target: AgentHookTarget) -> URL {
        configDirectory(for: target).appending(path: target.configFileName)
    }

    /// The path every installed hook runs: a link to the running app's embedded `altillo-hook`, refreshed at each
    /// launch, so the hooks keep working when the app moves or updates.
    var hookLink: URL { supportDirectory.appending(path: "bin/\(AgentHookCommand.executableName)") }
    var backupsDirectory: URL { supportDirectory.appending(path: "Backups", directoryHint: .isDirectory) }
    var recordFile: URL { supportDirectory.appending(path: "AgentHooks/installs.json") }

    /// A path for people: the home as `~`.
    func displayPath(_ url: URL) -> String {
        let path = url.path
        let home = home.path.hasSuffix("/") ? String(home.path.dropLast()) : home.path
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// How an agent's hooks stand.
enum AgentHookStatus: Equatable, Sendable {
    /// No Altillo hooks in the file (or no file yet).
    case notInstalled
    /// Exactly the hooks this version writes, and the hook they run is there.
    case installed
    /// Altillo's hooks are there but need an update (see the reason).
    case needsRepair(AgentHookRepairReason)
    /// The agent's config directory doesn't exist: it isn't set up on this Mac.
    case agentNotFound
    /// The file exists but Altillo can't safely edit it (not valid JSON, unexpected shape, unreadable).
    case unreadable(String)
}

enum AgentHookRepairReason: Equatable, Sendable {
    /// The hooks run a path that no longer leads to `altillo-hook` (the app moved or was deleted).
    case hookMissing
    /// Written by another version, or with another wait for your answer: some entries differ from this version's.
    case outdated
}

/// Everything Settings shows for one agent.
struct AgentHookReport: Equatable, Sendable {
    let target: AgentHookTarget
    let status: AgentHookStatus
    let configFile: URL
    /// Things worth knowing that don't change the status ("hooks are turned off in Codex's config").
    let notes: [String]
}

/// What an install or removal will write, computed before anything is touched so the user can review it.
struct AgentHookPlan: Equatable, Sendable, Identifiable {
    enum Action: Equatable, Sendable { case install, uninstall }

    let target: AgentHookTarget
    let action: Action
    /// The file as the user sees it (`~/.claude/settings.json`); `writeURL` is where it really lives if it's a link.
    let fileURL: URL
    let writeURL: URL
    /// The bytes the plan was computed from (nil: no file). Applying refuses if the file changed since.
    let originalData: Data?
    /// The new contents; nil deletes the file (only one Altillo created and that is empty again).
    let newText: String?
    let diff: UnifiedDiff
    let record: AgentHookInstallRecord?

    var id: String { "\(target.rawValue)-\(action)" }
    var changesNothing: Bool { diff.isEmpty && (newText != nil || originalData == nil) }
}

/// What Altillo remembers about an install, so removing it leaves the file as it was: containers it created are
/// removed again once empty, containers the user had are left even if empty. Stored in Altillo's own support
/// directory; nothing is ever added to the agent's file beyond the hook entries.
struct AgentHookInstallRecord: Codable, Equatable, Sendable {
    /// Altillo created the file.
    var createdFile: Bool
    /// `"hooks"` and `"hooks.<Event>"` keys Altillo created.
    var createdKeys: [String]
}

enum AgentHookError: Error, Equatable, Sendable, LocalizedError {
    case agentNotFound(AgentHookTarget)
    case unreadable(String)
    case changedSinceReview
    case writeFailed(String)
    case verificationFailed(String)
    case hookUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .agentNotFound(let target):
            String(localized: "\(target.displayName) isn't set up on this Mac.")
        case .unreadable(let reason):
            String(localized: "Altillo left the file alone: \(reason)")
        case .changedSinceReview:
            String(localized: "The file changed since you reviewed it. Nothing was written; review the new changes.")
        case .writeFailed(let reason):
            String(localized: "Couldn't write the file: \(reason)")
        case .verificationFailed(let reason):
            String(localized: "Altillo stopped before writing: \(reason)")
        case .hookUnavailable(let reason):
            String(localized: "Altillo's hook isn't available: \(reason)")
        }
    }
}

/// Installs, updates and removes Altillo's hooks. Stateless apart from the environment; every write goes through a
/// plan the user has seen.
struct AgentHookInstaller: Sendable {
    var environment: AgentHookEnvironment
    /// How long a PermissionRequest waits for the user's answer, in seconds.
    var wait: Int

    init(environment: AgentHookEnvironment = .live, wait: Int = AgentHookCommand.defaultWait) {
        self.environment = environment
        self.wait = wait
    }

    // MARK: Status

    func report(for target: AgentHookTarget) -> AgentHookReport {
        let file = environment.configFile(for: target)
        return AgentHookReport(target: target, status: status(for: target), configFile: file,
                               notes: notes(for: target))
    }

    func status(for target: AgentHookTarget) -> AgentHookStatus {
        let loaded: Loaded
        do {
            loaded = try load(target)
        } catch .agentNotFound {
            return .agentNotFound
        } catch .unreadable(let reason) {
            return .unreadable(reason)
        } catch {
            return .unreadable(error.localizedDescription)
        }
        guard let document = loaded.document, Self.containsAltilloHooks(document) else { return .notInstalled }
        let desired: OrderedJSON
        do {
            desired = try Self.installing(entries(for: target), into: document).document
        } catch {
            return .unreadable(error.localizedDescription)
        }
        guard desired == document else { return .needsRepair(.outdated) }
        return FileManager.default.isExecutableFile(atPath: environment.hookLink.path)
            ? .installed : .needsRepair(.hookMissing)
    }

    private func notes(for target: AgentHookTarget) -> [String] {
        switch target {
        case .claude:
            guard let loaded = try? load(target), let document = loaded.document,
                  document["disableAllHooks"] == .bool(true) else { return [] }
            return [String(localized: "Claude Code has every hook turned off (\"disableAllHooks\" in settings.json).")]
        case .codex:
            let config = environment.configDirectory(for: target).appending(path: "config.toml")
            guard let text = try? String(contentsOf: config, encoding: .utf8),
                  Self.codexHooksDisabled(configTOML: text) else { return [] }
            return [String(localized: "Hooks are turned off in Codex's config.toml ([features] hooks = false).")]
        }
    }

    /// Whether Codex's `config.toml` switches hooks off (`hooks = false`, or the older `codex_hooks = false`, under
    /// `[features]`, or `features.hooks = false` at the top level). A light line scan: enough to warn, never to edit.
    static func codexHooksDisabled(configTOML text: String) -> Bool {
        var table = ""
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if line.hasPrefix("[") {
                table = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[1] == "false" else { continue }
            let key = table.isEmpty ? parts[0] : "\(table).\(parts[0])"
            if key == "features.hooks" || key == "features.codex_hooks" { return true }
        }
        return false
    }

    // MARK: Plans

    func planInstall(_ target: AgentHookTarget) throws(AgentHookError) -> AgentHookPlan {
        let loaded = try load(target)
        let original = loaded.document ?? .object([])
        let result = try Self.installing(entries(for: target), into: original)
        var record = loaded.record ?? AgentHookInstallRecord(createdFile: loaded.document == nil, createdKeys: [])
        if loaded.document == nil { record.createdFile = true }
        // Keys created now, plus keys created by an earlier install that are still there.
        record.createdKeys = Array(Set(record.createdKeys.filter { Self.exists($0, in: result.document) })
            .union(result.createdKeys)).sorted()
        let style = loaded.text.map(OrderedJSON.Style.detect(in:)) ?? .standard
        let newText = result.document.serialized(style: style)
        try Self.verify(old: original, new: result.document, newText: newText, installed: true)
        return plan(target, .install, loaded, newText: newText, record: record)
    }

    func planUninstall(_ target: AgentHookTarget) throws(AgentHookError) -> AgentHookPlan {
        let loaded = try load(target)
        guard let original = loaded.document else {
            return plan(target, .uninstall, loaded, newText: nil, record: nil)
        }
        let record = loaded.record
        var document = Self.removingAltilloHooks(from: original, createdKeys: record.map { Set($0.createdKeys) })
        let deletesFile = record?.createdFile == true && document == .object([])
        if deletesFile { document = .object([]) }
        let newText = deletesFile ? nil : document.serialized(style: loaded.text.map(OrderedJSON.Style.detect(in:))
            ?? .standard)
        try Self.verify(old: original, new: document, newText: newText ?? "{}", installed: false)
        return plan(target, .uninstall, loaded, newText: newText, record: nil)
    }

    private func plan(_ target: AgentHookTarget, _ action: AgentHookPlan.Action, _ loaded: Loaded,
                      newText: String?, record: AgentHookInstallRecord?) -> AgentHookPlan {
        let name = environment.displayPath(loaded.fileURL)
        let diff = UnifiedDiff(old: loaded.text ?? "", new: newText ?? "",
                               oldName: loaded.text == nil ? "/dev/null" : name,
                               newName: newText == nil ? "/dev/null" : name)
        return AgentHookPlan(target: target, action: action, fileURL: loaded.fileURL, writeURL: loaded.writeURL,
                             originalData: loaded.data, newText: newText, diff: diff, record: record)
    }

    // MARK: Applying

    struct Outcome: Equatable, Sendable {
        /// The copy of the file taken before writing (nil when there was no file).
        let backup: URL?
    }

    /// Writes a reviewed plan: re-checks the file is still the one reviewed, backs it up, writes atomically keeping
    /// its permissions (or deletes a file Altillo created and emptied), reads it back to check, then remembers
    /// what it created for a clean removal later.
    @discardableResult
    func apply(_ plan: AgentHookPlan) throws(AgentHookError) -> Outcome {
        let fileManager = FileManager.default
        let current = fileManager.fileExists(atPath: plan.writeURL.path)
            ? try? Data(contentsOf: plan.writeURL) : nil
        guard current == plan.originalData else { throw .changedSinceReview }
        guard !plan.changesNothing else {
            try saveRecord(plan.record, for: plan.target)
            return Outcome(backup: nil)
        }

        var backup: URL?
        if let original = plan.originalData {
            backup = try makeBackup(original, for: plan.target)
        }

        do {
            if let newText = plan.newText {
                try Self.atomicWrite(Data(newText.utf8), to: plan.writeURL)
                let written = try Data(contentsOf: plan.writeURL)
                guard written == Data(newText.utf8) else {
                    throw AgentHookError.verificationFailed(String(localized: "the file didn't read back as written"))
                }
            } else {
                try fileManager.removeItem(at: plan.writeURL)
            }
        } catch let error as AgentHookError {
            throw error
        } catch {
            throw .writeFailed(error.localizedDescription)
        }

        try saveRecord(plan.record, for: plan.target)
        return Outcome(backup: backup)
    }

    private func makeBackup(_ data: Data, for target: AgentHookTarget) throws(AgentHookError) -> URL {
        let fileManager = FileManager.default
        let directory = environment.backupsDirectory
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = formatter.string(from: Date())
            var url = directory.appending(path: "\(target.rawValue)-\(stamp).json")
            var counter = 2
            while fileManager.fileExists(atPath: url.path) {
                url = directory.appending(path: "\(target.rawValue)-\(stamp)-\(counter).json")
                counter += 1
            }
            // Settings files can hold tokens: the backup is private to the user.
            guard fileManager.createFile(atPath: url.path, contents: data,
                                         attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return url
        } catch {
            throw .writeFailed(String(localized: "the backup couldn't be saved (\(error.localizedDescription))"))
        }
    }

    /// Writes next to the file and renames over it, so the agent never reads half a file. Keeps the old file's
    /// permissions (a new file gets 0600, like Claude Code's own).
    static func atomicWrite(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let permissions = (try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?
            .int16Value ?? 0o600
        let temporary = directory.appending(path: ".\(url.lastPathComponent).altillo-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporary.path, contents: data,
                                     attributes: [.posixPermissions: permissions]) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        guard rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? fileManager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    // MARK: Loading

    private struct Loaded {
        let fileURL: URL
        let writeURL: URL
        let data: Data?
        let text: String?
        let document: OrderedJSON?
        let record: AgentHookInstallRecord?
    }

    private func load(_ target: AgentHookTarget) throws(AgentHookError) -> Loaded {
        let fileManager = FileManager.default
        let directory = environment.configDirectory(for: target)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .agentNotFound(target)
        }
        let fileURL = environment.configFile(for: target)
        // A dotfiles setup may link the file elsewhere: edit the real file, keep the link.
        let writeURL = fileURL.resolvingSymlinksInPath()
        let record = loadRecords()[target.rawValue]
        guard fileManager.fileExists(atPath: writeURL.path) else {
            return Loaded(fileURL: fileURL, writeURL: writeURL, data: nil, text: nil, document: nil, record: nil)
        }
        let data: Data
        do {
            data = try Data(contentsOf: writeURL)
        } catch {
            throw .unreadable(String(localized: "it can't be read (\(error.localizedDescription))."))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw .unreadable(String(localized: "it isn't UTF-8 text."))
        }
        let document: OrderedJSON
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // An empty file is the same as no settings.
            document = .object([])
        } else {
            do {
                document = try OrderedJSON.parse(data)
            } catch {
                throw .unreadable(String(localized: "it isn't valid JSON (\(error.description))."))
            }
        }
        guard document.members != nil else {
            throw .unreadable(String(localized: "it doesn't hold a JSON object."))
        }
        if let hooks = document["hooks"], hooks.members == nil {
            throw .unreadable(String(localized: "its \"hooks\" isn't an object."))
        }
        return Loaded(fileURL: fileURL, writeURL: writeURL, data: data, text: text, document: document,
                      record: record)
    }

    private func loadRecords() -> [String: AgentHookInstallRecord] {
        guard let data = try? Data(contentsOf: environment.recordFile) else { return [:] }
        return (try? JSONDecoder().decode([String: AgentHookInstallRecord].self, from: data)) ?? [:]
    }

    private func saveRecord(_ record: AgentHookInstallRecord?, for target: AgentHookTarget) throws(AgentHookError) {
        var records = loadRecords()
        records[target.rawValue] = record
        do {
            try FileManager.default.createDirectory(at: environment.recordFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try Self.atomicWrite(try encoder.encode(records), to: environment.recordFile)
        } catch {
            throw .writeFailed(String(localized: "Altillo's install record couldn't be saved (\(error.localizedDescription))"))
        }
    }

    // MARK: Entries

    /// Altillo's handler for each event, as it goes in the file.
    func entries(for target: AgentHookTarget) -> [(event: String, handler: OrderedJSON)] {
        target.events.map { event in
            var members: [OrderedJSON.Member] = [
                .init(key: "type", value: .string("command")),
                .init(key: "command", value: .string(AgentHookCommand.command(
                    hookPath: environment.hookLink.path, agent: target, event: event, wait: wait))),
            ]
            if let timeout = AgentHookCommand.timeout(for: event, wait: wait) {
                members.append(.init(key: "timeout", value: .number(String(timeout))))
            }
            return (event.name, .object(members))
        }
    }

    // MARK: Document edits (pure)

    static func isAltilloHandler(_ handler: OrderedJSON) -> Bool {
        guard let command = handler["command"]?.stringValue else { return false }
        return AgentHookCommand.isAltilloCommand(command)
    }

    static func containsAltilloHooks(_ document: OrderedJSON) -> Bool {
        guard let events = document["hooks"]?.members else { return false }
        return events.contains { event in
            event.value.elements?.contains { group in
                group["hooks"]?.elements?.contains(where: isAltilloHandler) ?? false
            } ?? false
        }
    }

    /// Takes Altillo's handlers out of one event's matcher groups. Returns the remaining groups and where the first
    /// group that held only Altillo's handlers was, so a reinstall puts the new one back in the same place.
    private static func strippingAltillo(from groups: [OrderedJSON]) -> (groups: [OrderedJSON], slot: Int?,
                                                                          changed: Bool) {
        var kept: [OrderedJSON] = []
        var slot: Int?
        var changed = false
        for group in groups {
            guard let handlers = group["hooks"]?.elements, handlers.contains(where: isAltilloHandler) else {
                kept.append(group)
                continue
            }
            changed = true
            let remaining = handlers.filter { !isAltilloHandler($0) }
            if remaining.isEmpty {
                slot = slot ?? kept.count
            } else {
                var trimmed = group
                trimmed.set("hooks", .array(remaining))
                kept.append(trimmed)
            }
        }
        return (kept, slot, changed)
    }

    /// The document with exactly this version's Altillo handlers: older or duplicate ones are replaced in place,
    /// new events are added at the end, everything else is left exactly as it was.
    static func installing(_ entries: [(event: String, handler: OrderedJSON)],
                           into document: OrderedJSON) throws(AgentHookError) -> (document: OrderedJSON,
                                                                                  createdKeys: [String]) {
        var document = document
        var createdKeys: [String] = []
        var hooks: OrderedJSON
        if let existing = document["hooks"] {
            guard existing.members != nil else {
                throw .unreadable(String(localized: "its \"hooks\" isn't an object."))
            }
            hooks = existing
        } else {
            hooks = .object([])
            createdKeys.append("hooks")
        }
        let wanted = Dictionary(entries.map { ($0.event, $0.handler) }, uniquingKeysWith: { first, _ in first })

        // Events already in the file, in their order: strip Altillo's handlers, put the current one back.
        for member in hooks.members ?? [] where wanted[member.key] != nil || member.value.elements != nil {
            let event = member.key
            guard let groups = member.value.elements else {
                throw .unreadable(String(localized: "its hooks for \(event) aren't a list."))
            }
            let stripped = strippingAltillo(from: groups)
            var updated = stripped.groups
            if let handler = wanted[event] {
                updated.insert(group(handler), at: stripped.slot ?? updated.count)
            }
            if stripped.changed || wanted[event] != nil {
                if updated.isEmpty { hooks.remove(event) } else { hooks.set(event, .array(updated)) }
            }
        }
        // Events not there yet, in Altillo's order.
        for entry in entries where hooks[entry.event] == nil {
            hooks.set(entry.event, .array([group(entry.handler)]))
            createdKeys.append("hooks.\(entry.event)")
        }
        document.set("hooks", hooks)
        return (document, createdKeys)
    }

    private static func group(_ handler: OrderedJSON) -> OrderedJSON {
        // No matcher: every event Altillo uses fires for everything when the matcher is left out.
        .object([.init(key: "hooks", value: .array([handler]))])
    }

    /// The document without any Altillo handler. Event lists and the `hooks` object that end up empty are removed
    /// only if Altillo created them (`createdKeys`). Without a record (an install from another Mac or a lost
    /// record), emptied event lists go (an empty list does nothing) and an emptied `hooks` stays.
    static func removingAltilloHooks(from document: OrderedJSON, createdKeys: Set<String>?) -> OrderedJSON {
        guard var hooks = document["hooks"], let events = hooks.members else { return document }
        var document = document
        for member in events {
            guard let groups = member.value.elements else { continue }
            let stripped = strippingAltillo(from: groups)
            guard stripped.changed else { continue }
            if stripped.groups.isEmpty, createdKeys?.contains("hooks.\(member.key)") ?? true {
                hooks.remove(member.key)
            } else {
                hooks.set(member.key, .array(stripped.groups))
            }
        }
        if hooks.members?.isEmpty == true, createdKeys?.contains("hooks") == true {
            document.remove("hooks")
        } else {
            document.set("hooks", hooks)
        }
        return document
    }

    private static func exists(_ key: String, in document: OrderedJSON) -> Bool {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        guard let hooks = document[parts[0]] else { return false }
        return parts.count == 1 || hooks[parts[1]] != nil
    }

    /// The last line of defence before anything is written: the new text must be valid JSON that says the same as
    /// the old document apart from Altillo's handlers (and empty containers), and install must leave Altillo's
    /// hooks in while uninstall must leave none.
    static func verify(old: OrderedJSON, new: OrderedJSON, newText: String,
                       installed: Bool) throws(AgentHookError) {
        guard (try? JSONSerialization.jsonObject(with: Data(newText.utf8))) != nil,
              (try? OrderedJSON.parse(newText)) == new else {
            throw .verificationFailed(String(localized: "the new file wouldn't be valid JSON."))
        }
        guard normalized(old) == normalized(new) else {
            throw .verificationFailed(String(localized: "the change would touch more than Altillo's hooks."))
        }
        guard containsAltilloHooks(new) == installed else {
            throw .verificationFailed(String(localized: "the change wouldn't do what it says."))
        }
    }

    /// Without Altillo's handlers, empty matcher groups it emptied, empty event lists and an empty `hooks`.
    private static func normalized(_ document: OrderedJSON) -> OrderedJSON {
        var document = removingAltilloHooks(from: document, createdKeys: nil)
        guard var hooks = document["hooks"], let events = hooks.members else { return document }
        for member in events where member.value.elements?.isEmpty == true {
            hooks.remove(member.key)
        }
        if hooks.members?.isEmpty == true { document.remove("hooks") } else { document.set("hooks", hooks) }
        return document
    }
}

// MARK: - The stable hook path

extension AgentHookInstaller {
    enum LinkResult: Equatable, Sendable {
        case unchanged
        case linked(to: String)
        case unavailable(String)
    }

    /// (Re)points `~/Library/Application Support/Altillo/bin/altillo-hook` at the running app's embedded
    /// `altillo-hook`, so hooks installed by any version keep working after the app moves or updates. Call once at
    /// launch; cheap and idempotent. A translocated copy (an app run straight from Downloads) is left out: its
    /// path disappears when it quits.
    @discardableResult
    static func refreshStableHookPath(environment: AgentHookEnvironment = .live,
                                      bundle: Bundle = .main) -> LinkResult {
        let target = bundle.url(forAuxiliaryExecutable: AgentHookCommand.executableName)
            ?? bundle.bundleURL.appending(path: "Contents/MacOS/\(AgentHookCommand.executableName)")
        guard FileManager.default.isExecutableFile(atPath: target.path) else {
            return .unavailable(String(localized: "this copy of Altillo has no altillo-hook inside."))
        }
        // A development build launching (Xcode, tests, reviews) must not steal the link from the installed app:
        // its build folder comes and goes, and the user's installed hooks would break with it.
        if isDevelopmentBuild(target.path),
           let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: environment.hookLink.path),
           FileManager.default.isExecutableFile(atPath: existing), !isDevelopmentBuild(existing) {
            return .unchanged
        }
        return linkStableHook(to: target, environment: environment)
    }

    /// A copy built by Xcode or `xcodebuild` (derived data), not an installed app.
    static func isDevelopmentBuild(_ path: String) -> Bool {
        path.contains("/Build/Products/") || path.contains("/DerivedData/")
    }

    static func linkStableHook(to target: URL, environment: AgentHookEnvironment) -> LinkResult {
        let fileManager = FileManager.default
        let path = target.standardizedFileURL.path
        guard !path.contains("/AppTranslocation/") else {
            return .unavailable(String(localized: "Altillo is running from a temporary copy. Move it to Applications."))
        }
        let link = environment.hookLink
        if let existing = try? fileManager.destinationOfSymbolicLink(atPath: link.path), existing == path {
            return .unchanged
        }
        do {
            try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            // A new link beside the old one, renamed over it: the hook path never goes missing in between.
            let temporary = link.deletingLastPathComponent().appending(path: ".altillo-hook-\(UUID().uuidString)")
            try fileManager.createSymbolicLink(atPath: temporary.path, withDestinationPath: path)
            guard rename(temporary.path, link.path) == 0 else {
                let code = errno
                try? fileManager.removeItem(at: temporary)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            return .linked(to: path)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }
}
