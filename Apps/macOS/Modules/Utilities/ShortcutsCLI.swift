import Foundation

/// One of the user's Shortcuts, as `shortcuts list --show-identifiers` names it.
struct ShortcutInfo: Identifiable, Hashable, Sendable {
    var name: String
    /// The shortcut's UUID. Running by identifier is exact even when two shortcuts share a name.
    var identifier: String?
    /// The folder it lives in, if any.
    var folder: String?

    var id: String { identifier ?? name }
}

/// The `shortcuts` command-line tool that ships with macOS: listing and running, always as a child process off the
/// main thread, with arguments passed as an array (never through a shell), so names with quotes, spaces or emoji
/// need no escaping.
enum ShortcutsCLI {
    static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")

    static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    // MARK: - Arguments

    /// `shortcuts list --show-identifiers [--folder-name <folder>]`, or the folders themselves.
    static func listArguments(folder: String? = nil, folders: Bool = false) -> [String] {
        var arguments = ["list", "--show-identifiers"]
        if folders { arguments.append("--folders") }
        if let folder { arguments += ["--folder-name", folder] }
        return arguments
    }

    /// `shortcuts run [--input-path <file>] -- <identifier or name>`. The `--` ends the options, so a shortcut
    /// called "-h" or "--output-path" is still just a name.
    static func runArguments(for shortcut: ShortcutInfo, inputPath: URL? = nil) -> [String] {
        var arguments = ["run"]
        if let inputPath { arguments += ["--input-path", inputPath.path] }
        arguments += ["--", shortcut.identifier ?? shortcut.name]
        return arguments
    }

    /// The command as a shell would need it, for the log only (it's never run through a shell).
    static func displayCommand(_ arguments: [String]) -> String {
        ([executable.path] + arguments).map(shellQuoted).joined(separator: " ")
    }

    static func shellQuoted(_ argument: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:@%+,"))
        if !argument.isEmpty, argument.unicodeScalars.allSatisfy(safe.contains) { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Parsing

    /// Lines of `shortcuts list --show-identifiers`: "Name (UUID)". The identifier is the last parenthesised
    /// UUID, so names with their own parentheses survive; a line without one is just a name.
    static func parseList(_ output: String, folder: String? = nil) -> [ShortcutInfo] {
        output.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if let match = line.wholeMatch(of: identifiedLine) {
                let name = String(match.1).trimmingCharacters(in: .whitespaces)
                return ShortcutInfo(name: name.isEmpty ? line : name, identifier: String(match.2), folder: folder)
            }
            return ShortcutInfo(name: line, identifier: nil, folder: folder)
        }
    }

    nonisolated(unsafe) private static let identifiedLine =
        /(.*) \(([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\)/

    // MARK: - Running

    struct Output: Sendable, Equatable {
        var status: Int32
        var standardOutput: String
        var standardError: String
        var succeeded: Bool { status == 0 }
    }

    enum Failure: Error, Equatable {
        /// `/usr/bin/shortcuts` isn't there (or can't be run).
        case missing
        /// It ran for longer than allowed and was stopped.
        case timedOut
    }

    /// Runs `shortcuts` with `arguments` and waits for it, off the main thread. With a `timeout`, a run that takes
    /// longer is terminated. Cancelling the task terminates it too.
    static func execute(_ arguments: [String], timeout: Duration? = nil) async throws -> Output {
        guard isAvailable else { throw Failure.missing }
        let job = Job(arguments: arguments)
        let timer = timeout.map { limit in
            Task.detached {
                try? await Task.sleep(for: limit)
                if !Task.isCancelled { job.stop(timedOut: true) }
            }
        }
        defer { timer?.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: job.run())
                }
            }
        } onCancel: {
            job.stop(timedOut: false)
        }
    }

    /// One `shortcuts` invocation. `Process` isn't `Sendable`; it stays inside this box, whose entry points are
    /// serialised by `lock`.
    private final class Job: @unchecked Sendable {
        private let arguments: [String]
        private let process = Process()
        private let lock = NSLock()
        private var stopped = false
        private var timedOut = false

        init(arguments: [String]) { self.arguments = arguments }

        func stop(timedOut: Bool) {
            lock.lock()
            stopped = true
            if timedOut { self.timedOut = true }
            let running = process.isRunning
            lock.unlock()
            if running { process.terminate() }
        }

        func run() -> Result<Output, Error> {
            let output = Pipe(), errors = Pipe()
            process.executableURL = ShortcutsCLI.executable
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = errors
            lock.lock()
            if stopped {
                lock.unlock()
                return .failure(CancellationError())
            }
            do {
                try process.run()
            } catch {
                lock.unlock()
                return .failure(Failure.missing)
            }
            lock.unlock()
            // Drain both pipes at once so a chatty shortcut can't fill one and stall.
            let group = DispatchGroup()
            nonisolated(unsafe) var errorData = Data()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                errorData = errors.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            process.waitUntilExit()
            lock.lock()
            let wasTimedOut = timedOut, wasStopped = stopped
            lock.unlock()
            if wasTimedOut { return .failure(Failure.timedOut) }
            if wasStopped { return .failure(CancellationError()) }
            return .success(Output(
                status: process.terminationStatus,
                standardOutput: String(decoding: outputData, as: UTF8.self),
                standardError: String(decoding: errorData, as: UTF8.self)
            ))
        }
    }

    /// A short, readable reason from a failed run's error output ("Couldn't find shortcut", …).
    static func failureMessage(_ output: Output) -> String {
        let text = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = text.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        var trimmed = line
        for noise in ["Error: ", "The operation couldn’t be completed. ", "The operation couldn't be completed. "] {
            trimmed = trimmed.replacingOccurrences(of: noise, with: "")
        }
        guard !trimmed.isEmpty else { return String(localized: "It stopped with an error (\(output.status)).") }
        return trimmed.count > 120 ? String(trimmed.prefix(119)) + "…" : trimmed
    }

    // MARK: - Matching a spoken name

    /// Folds a name for comparing what someone typed with a shortcut's name: lowercase, no accents, letters and
    /// digits only ("☕️ Coffee time" and "coffee-time" match).
    static func fold(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    enum Match: Equatable, Sendable {
        case found(ShortcutInfo)
        case ambiguous([ShortcutInfo])
        case none
    }

    /// The shortcut someone named: an exact (folded) match first; otherwise the only one whose name contains the
    /// words (or is contained in them). Two candidates is a question back, never a guess.
    static func match(_ requested: String, in shortcuts: [ShortcutInfo]) -> Match {
        let wanted = fold(requested)
        guard !wanted.isEmpty else { return .none }
        let exact = shortcuts.filter { fold($0.name) == wanted }
        if exact.count == 1 { return .found(exact[0]) }
        if exact.count > 1 { return .ambiguous(exact) }
        let partial = shortcuts.filter { shortcut in
            let name = fold(shortcut.name)
            guard !name.isEmpty else { return false }
            return (wanted.count >= 3 && contains(name, words: wanted)) || (name.count >= 3 && contains(wanted, words: name))
        }
        if partial.count == 1 { return .found(partial[0]) }
        return partial.isEmpty ? .none : .ambiguous(partial)
    }

    /// True when `phrase` appears in `text` on word boundaries.
    private static func contains(_ text: String, words phrase: String) -> Bool {
        (" " + text + " ").contains(" " + phrase + " ")
    }
}
