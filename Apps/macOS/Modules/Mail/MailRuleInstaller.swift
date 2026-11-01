import AppKit
import CryptoKit
import Darwin
import Foundation
import Observation

/// Owns Altillo's two generated scripts. Every user-created Mail rule is preserved for manual removal.
@MainActor
@Observable
final class MailRuleInstaller {
    enum Status: String, Sendable {
        case notPrepared, prepared, configured, changed, unavailable, manualRemovalRequired

        var title: String {
            switch self {
            case .notPrepared: String(localized: "Mail setup hasn't started.")
            case .prepared: String(localized: "Scripts are ready. Add the rule in Apple Mail.")
            case .configured: String(localized: "Apple Mail's rule is connected.")
            case .changed: String(localized: "Mail setup was changed. Your files have been left untouched.")
            case .unavailable: String(localized: "Open Apple Mail to check its rule.")
            case .manualRemovalRequired: String(localized: "Remove rules that use Altillo Mail in Apple Mail Settings, then try again. Your scripts have been kept.")
            }
        }
    }

    nonisolated static let ruleName = "Altillo Mail"
    nonisolated static let handlerName = "Altillo Mail.scpt"
    nonisolated static let bridgeName = "Altillo Mail Bridge.scpt"
    nonisolated static let resourceNames = ["AltilloMailRule", "AltilloMailBridge"]
    nonisolated static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Altillo/Mail/mail.sock").path
    }

    struct Paths: Sendable {
        var scriptsDirectory: URL
        var stateDirectory: URL
        var helper: URL
        var socketPath: String
        var handler: URL { scriptsDirectory.appendingPathComponent(MailRuleInstaller.handlerName) }
        var bridge: URL { scriptsDirectory.appendingPathComponent(MailRuleInstaller.bridgeName) }
        var manifest: URL { stateDirectory.appendingPathComponent("mail-scripts.json") }

        static var live: Self {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let executable = Bundle.main.executableURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Altillo")
            return Self(scriptsDirectory: home.appendingPathComponent("Library/Application Scripts/com.apple.mail"),
                        stateDirectory: home.appendingPathComponent("Library/Application Support/Altillo/Mail"),
                        helper: executable.deletingLastPathComponent().appendingPathComponent("altillo-mail"),
                        socketPath: MailRuleInstaller.defaultSocketPath)
        }
    }

    struct Templates: Sendable {
        var handler: String
        var bridge: String
    }

    enum Failure: Error, Equatable { case unsafeDirectory, missingResources, missingHelper, changedFiles, invalidManifest, compilerFailed, inspectionTimedOut }

    private(set) var status: Status = .notPrepared
    private(set) var problem: String?
    private(set) var isWorking = false
    var scriptsDirectory: URL { paths.scriptsDirectory }

    @ObservationIgnored private let paths: Paths
    @ObservationIgnored private let templates: Templates?
    @ObservationIgnored private let compiler: @Sendable (URL, URL) throws -> Void
    @ObservationIgnored private let runScript: @MainActor (String) async throws -> String

    init(paths: Paths = .live, templates: Templates? = nil,
         compiler: @escaping @Sendable (URL, URL) throws -> Void = MailRuleInstaller.compile,
         runScript: @escaping @MainActor (String) async throws -> String = { try await MailRuleInstaller.runInspection($0) }) {
        self.paths = paths
        self.templates = templates
        self.compiler = compiler
        self.runScript = runScript
    }

    func prepare() async {
        guard !isWorking else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            let sources = try templates ?? Self.bundledTemplates()
            let paths = self.paths, compiler = self.compiler
            try await Task.detached(priority: .utility) {
                try Self.prepareFiles(paths: paths, templates: sources, compiler: compiler)
            }.value
            status = .prepared
        } catch {
            status = .changed
            problem = Self.explanation(error)
        }
    }

    func refresh() async {
        guard !isWorking else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            guard try Self.verifyOwnedFiles(paths: paths) != nil else { status = .notPrepared; return }
            let answer = try await runScript(Self.inspectionScript(paths: paths, remove: false))
            switch answer {
            case "configured": status = .configured
            case "absent": status = .prepared
            case "closed": status = .unavailable
            default: status = .changed
            }
        } catch {
            status = error is AppleScriptRunner.Failure || (error as? Failure) == .inspectionTimedOut ? .unavailable : .changed
            problem = Self.explanation(error)
        }
    }

    func uninstall() async {
        guard !isWorking else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            guard try Self.verifyOwnedFiles(paths: paths, allowMissing: true) != nil else { status = .notPrepared; return }
            let answer = try await runScript(Self.inspectionScript(paths: paths, remove: true))
            guard answer == "absent" else {
                status = answer == "closed" ? .unavailable : .manualRemovalRequired
                problem = String(localized: "Remove rules that use Altillo Mail in Apple Mail Settings, then try again. Your scripts have been kept.")
                return
            }
            // Recheck after the Apple Event: don't delete a file that changed while Mail was answering.
            _ = try Self.verifyOwnedFiles(paths: paths, allowMissing: true)
            for file in [paths.handler, paths.bridge, paths.manifest] where FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            status = .notPrepared
        } catch {
            status = error is AppleScriptRunner.Failure || (error as? Failure) == .inspectionTimedOut ? .unavailable : .changed
            problem = Self.explanation(error)
        }
    }

    func revealScripts() { NSWorkspace.shared.open(paths.scriptsDirectory) }
    func openMailSettings() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app")) }

    nonisolated static func ensurePrivateDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw Failure.unsafeDirectory }
    }

    nonisolated static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    nonisolated static func render(_ text: String, paths: Paths) -> String {
        let replacements = ["__HELPER_PATH__": paths.helper.path, "__SOCKET_PATH__": paths.socketPath,
                            "__BRIDGE_PATH__": paths.bridge.path]
        return replacements.reduce(text) { result, pair in
            result.replacingOccurrences(of: quote(pair.key), with: quote(pair.value))
        }
    }

    private struct Manifest: Codable {
        var version: Int
        var handlerHash: String
        var bridgeHash: String
    }

    nonisolated private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    nonisolated static func verifyOwnedFiles(paths: Paths, allowMissing: Bool = false) throws -> Bool? {
        var manifestInfo = stat()
        guard lstat(paths.manifest.path, &manifestInfo) == 0 else {
            var otherInfo = stat()
            if lstat(paths.handler.path, &otherInfo) == 0 || lstat(paths.bridge.path, &otherInfo) == 0 {
                throw Failure.changedFiles
            }
            return nil
        }
        guard manifestInfo.st_mode & S_IFMT == S_IFREG, manifestInfo.st_uid == getuid(),
              manifestInfo.st_size <= 4_096 else { throw Failure.invalidManifest }
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: paths.manifest)) }
        catch { throw Failure.invalidManifest }
        guard manifest.version == 1 else { throw Failure.invalidManifest }
        for (url, expected) in [(paths.handler, manifest.handlerHash), (paths.bridge, manifest.bridgeHash)] {
            var info = stat()
            let exists = lstat(url.path, &info) == 0
            if !exists, errno == ENOENT, allowMissing { continue }
            guard exists, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_size <= 4 << 20,
                  let data = try? Data(contentsOf: url), digest(data) == expected else { throw Failure.changedFiles }
        }
        return true
    }

    nonisolated static func prepareFiles(paths: Paths, templates: Templates,
                                        compiler: @Sendable (URL, URL) throws -> Void) throws {
        let manager = FileManager.default
        try ensurePrivateDirectory(paths.stateDirectory)
        guard manager.isExecutableFile(atPath: paths.helper.path) else { throw Failure.missingHelper }
        _ = try verifyOwnedFiles(paths: paths)
        try manager.createDirectory(at: paths.scriptsDirectory, withIntermediateDirectories: true)
        var scriptsInfo = stat()
        guard lstat(paths.scriptsDirectory.path, &scriptsInfo) == 0, scriptsInfo.st_mode & S_IFMT == S_IFDIR,
              scriptsInfo.st_uid == getuid() else { throw Failure.unsafeDirectory }
        let staging = paths.stateDirectory.appendingPathComponent("compile-\(UUID().uuidString)")
        try ensurePrivateDirectory(staging)
        defer { try? manager.removeItem(at: staging) }
        var compiled: [URL: Data] = [:]
        for (name, template, destination) in [("handler", templates.handler, paths.handler), ("bridge", templates.bridge, paths.bridge)] {
            let source = staging.appendingPathComponent(name + ".applescript")
            let target = staging.appendingPathComponent(name + ".scpt")
            try render(template, paths: paths).write(to: source, atomically: true, encoding: .utf8)
            try compiler(source, target)
            compiled[destination] = try Data(contentsOf: target)
        }
        // This failure must not enter rollback: files introduced by somebody else during compilation aren't ours.
        _ = try verifyOwnedFiles(paths: paths)
        let previous = [paths.handler, paths.bridge, paths.manifest].reduce(into: [URL: Data]()) { result, file in
            if let data = try? Data(contentsOf: file) { result[file] = data }
        }
        do {
            // Compilation and the ownership recheck completed before replacing anything.
            for file in [paths.handler, paths.bridge] { try compiled[file]!.write(to: file, options: .atomic) }
            let manifest = Manifest(version: 1, handlerHash: digest(compiled[paths.handler]!), bridgeHash: digest(compiled[paths.bridge]!))
            try JSONEncoder().encode(manifest).write(to: paths.manifest, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.manifest.path)
        } catch {
            for file in [paths.handler, paths.bridge, paths.manifest] {
                if let old = previous[file] { try? old.write(to: file, options: .atomic) }
                else { try? manager.removeItem(at: file) }
            }
            throw error
        }
    }

    /// Bound the whole process, including permission/app lookup before AppleScript's own timeout begins.
    nonisolated static func runInspection(_ source: String, timeout: Duration = .seconds(12)) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await AppleScriptRunner.run(source) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.inspectionTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw Failure.inspectionTimedOut }
            return result
        }
    }

    nonisolated static func inspectionScript(paths: Paths, remove: Bool) -> String {
        if remove {
            // Mail's public rule dictionary cannot expose every possible action. Do not infer ownership from
            // a name/condition and delete a user-created rule; preserve even renamed references to our scripts.
            return """
            if not (application id "com.apple.mail" is running) then return "closed"
            with timeout of 5 seconds
                tell application id "com.apple.mail"
                    repeat with candidate in every rule
                        if name of candidate is \(quote(ruleName)) then return "present"
                        try
                            set attachedPath to POSIX path of (run script of candidate)
                            if attachedPath is \(quote(paths.handler.path)) or attachedPath is \(quote(paths.bridge.path)) then return "present"
                        end try
                    end repeat
                    return "absent"
                end tell
            end timeout
            """
        }
        return """
        if not (application id "com.apple.mail" is running) then return "closed"
        with timeout of 5 seconds
            tell application id "com.apple.mail"
                -- Filter names locally: Mail can stall resolving an Apple Event `whose` predicate.
                set ruleNames to get name of every rule
                set candidateIndex to 0
                set matchCount to 0
                repeat with ruleIndex from 1 to count of ruleNames
                    if item ruleIndex of ruleNames is \(quote(ruleName)) then
                        set candidateIndex to ruleIndex
                        set matchCount to matchCount + 1
                    end if
                end repeat
                if matchCount is 0 then return "absent"
                if matchCount is not 1 then return "changed"
                set candidate to rule candidateIndex
                try
                    set attachedPath to POSIX path of (run script of candidate)
                    if attachedPath is not \(quote(paths.handler.path)) then return "changed"
                    if (count of rule conditions of candidate) is not 1 then return "changed"
                    if rule type of first rule condition of candidate is not matches every message then return "changed"
                    if not (enabled of candidate) then return "changed"
                    return "configured"
                on error
                    return "changed"
                end try
            end tell
        end timeout
        """
    }

    nonisolated private static func bundledTemplates() throws -> Templates {
        guard let handler = Bundle.main.url(forResource: resourceNames[0], withExtension: "txt"),
              let bridge = Bundle.main.url(forResource: resourceNames[1], withExtension: "txt") else { throw Failure.missingResources }
        return try Templates(handler: String(contentsOf: handler, encoding: .utf8), bridge: String(contentsOf: bridge, encoding: .utf8))
    }

    nonisolated private static func compile(_ source: URL, _ output: URL) throws {
        let process = Process()
        let done = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-o", output.path, source.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        guard done.wait(timeout: .now() + 10) == .success else { process.terminate(); throw Failure.compilerFailed }
        guard process.terminationStatus == 0 else { throw Failure.compilerFailed }
    }

    private static func explanation(_ error: Error) -> String {
        switch error {
        case Failure.inspectionTimedOut:
            String(localized: "Mail didn't answer. Check that Mail is open and Altillo can control it in System Settings → Privacy & Security → Automation, then try again. Your scripts have been kept.")
        case AppleScriptRunner.Failure.failed(let message) where message.contains("(-1712)"):
            String(localized: "Mail didn't answer. Check that Mail is open and Altillo can control it in System Settings → Privacy & Security → Automation, then try again. Your scripts have been kept.")
        case AppleScriptRunner.Failure.notAuthorised:
            String(localized: "Allow Altillo to control Apple Mail in System Settings → Privacy & Security → Automation, then check the rule again.")
        case Failure.changedFiles, Failure.invalidManifest:
            String(localized: "The Mail scripts were changed or aren't owned by Altillo. They have been left untouched.")
        case Failure.missingHelper, Failure.missingResources:
            String(localized: "This copy of Altillo is missing its Mail helper. Install a complete copy of the app.")
        default:
            String(localized: "Mail setup couldn't finish. Your existing rules and messages have been left untouched.")
        }
    }
}
