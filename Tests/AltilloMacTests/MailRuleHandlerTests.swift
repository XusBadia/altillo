import Darwin
import Foundation
import Testing
@testable import Altillo

/// Executes the compiled production handler against local script objects. No Apple Mail messages or rules
/// are queried: Mail is used only as the compile-time terminology dictionary.
@MainActor
struct MailRuleHandlerTests {
    private enum HarnessFailure: Error { case compilerTimedOut, compilerFailed, executionTimedOut }

    @Test func aMissingBodyStillDeliversTheMessageMetadata() async throws {
        let result = try await runFixture(bodyDeclaration: "property content : missing value")
        #expect(result == "delivered|")
    }

    @Test func aBodyReadErrorStillDeliversTheMessageMetadata() async throws {
        // Omitting the property makes `content of fixture` raise -1728 rather than return missing value.
        let result = try await runFixture(bodyDeclaration: "", verifyBodyError: true)
        #expect(result == "delivered|")
    }

    @Test func anAvailableBodyReachesTheBridgeUnchanged() async throws {
        let result = try await runFixture(bodyDeclaration: "property content : \"Synthetic verification code: 482913\"")
        #expect(result == "delivered|Synthetic verification code: 482913")
    }

    @Test(arguments: ["subject", "sender", "message id"])
    func missingEssentialMetadataDoesNotDeliver(_ missingProperty: String) async throws {
        let result = try await runFixture(bodyDeclaration: "property content : \"Synthetic body\"", missingProperty: missingProperty)
        #expect(result == nil)
    }

    @Test func anExpiredMessageDoesNotDeliver() async throws {
        let result = try await runFixture(bodyDeclaration: "property content : \"Synthetic body\"", ageSeconds: 301)
        #expect(result == nil)
    }

    private func runFixture(bodyDeclaration: String, missingProperty: String? = nil,
                            ageSeconds: Int = 0, verifyBodyError: Bool = false) async throws -> String? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("altillo-mail-handler-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = root.appendingPathComponent("Synthetic Bridge.applescript")
        let receipt = root.appendingPathComponent("receipt.txt")
        let source = root.appendingPathComponent("handler.applescript")
        let compiled = root.appendingPathComponent("handler.scpt")
        let paths = MailRuleInstaller.Paths(scriptsDirectory: root, stateDirectory: root,
                                            helper: root.appendingPathComponent("unused-helper"), socketPath: root.appendingPathComponent("unused.sock").path)
        // render() supplies the production bridge filename; keep the stub at that exact path.
        let renderedBridge = paths.bridge
        let stub = """
        on run arguments
            set outputFile to open for access POSIX file \(MailRuleInstaller.quote(receipt.path)) with write permission
            try
                set eof outputFile to 0
                write ("delivered|" & item 4 of arguments) to outputFile as «class utf8»
                close access outputFile
            on error errorText number errorNumber
                close access outputFile
                error errorText number errorNumber
            end try
        end run
        """
        try stub.write(to: bridge, atomically: true, encoding: .utf8)
        try compile(bridge, to: renderedBridge)
        // Exercise the actual bundled template without reading a protected Documents checkout.
        let templateURL = try #require(Bundle.main.url(forResource: "AltilloMailRule", withExtension: "txt"))
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        try MailRuleInstaller.render(template, paths: paths).write(to: source, atomically: true, encoding: .utf8)
        try compile(source, to: compiled)

        func value(_ property: String, _ defaultValue: String) -> String {
            property == missingProperty ? "missing value" : defaultValue
        }
        let verifyError = verifyBodyError ? """
        set bodyReadFailed to false
        try
            set ignoredBody to content of fixture
        on error number -1728
            set bodyReadFailed to true
        end try
        if not bodyReadFailed then error "The fixture must raise -1728 for its body"
        """ : ""
        let harness = """
        using terms from application "Mail"
            script fixture
                property subject : \(value("subject", "\"Synthetic Altillo message\""))
                property sender : \(value("sender", "\"test@example.invalid\""))
                property message id : \(value("message id", "\"fixture@example.invalid\""))
                property date received : (current date) - \(ageSeconds)
                property mailbox : missing value
                \(bodyDeclaration)
            end script
            \(verifyError)
            set candidate to load script POSIX file \(MailRuleInstaller.quote(compiled.path))
            tell candidate to perform mail action with messages {fixture} for rule missing value
        end using terms from
        """
        _ = try await runHarness(harness)
        guard FileManager.default.fileExists(atPath: receipt.path) else { return nil }
        return try String(contentsOf: receipt, encoding: .utf8)
    }

    private func runHarness(_ source: String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await AppleScriptRunner.run(source) }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw HarnessFailure.executionTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw HarnessFailure.executionTimedOut }
            return result
        }
    }

    private func compile(_ source: URL, to output: URL) throws {
        let process = Process()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-o", output.path, source.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            if finished.wait(timeout: .now() + 1) != .success, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            throw HarnessFailure.compilerTimedOut
        }
        guard process.terminationStatus == 0 else { throw HarnessFailure.compilerFailed }
    }
}
