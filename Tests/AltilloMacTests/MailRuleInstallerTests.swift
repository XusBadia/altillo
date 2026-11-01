import Foundation
import Testing
@testable import Altillo

@MainActor
struct MailRuleInstallerTests {
    private func makePaths() throws -> (URL, MailRuleInstaller.Paths) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("altillo-mail-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let helper = root.appendingPathComponent("Altillo \"test\".app/Contents/MacOS/altillo-mail")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test executable".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let state = root.appendingPathComponent("state")
        return (root, MailRuleInstaller.Paths(scriptsDirectory: root.appendingPathComponent("scripts"), stateDirectory: state,
                                              helper: helper, socketPath: state.appendingPathComponent("mail.sock").path))
    }

    private var templates: MailRuleInstaller.Templates {
        .init(handler: "property bridgePath : \"__BRIDGE_PATH__\"", bridge: "property helperPath : \"__HELPER_PATH__\"\nproperty socketPath : \"__SOCKET_PATH__\"")
    }

    private var copyCompiler: @Sendable (URL, URL) throws -> Void {
        { source, target in try Data(contentsOf: source).write(to: target) }
    }

    @Test func renderingKeepsQuotesAndBackslashesInsideAppleScriptStrings() throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let rendered = MailRuleInstaller.render(templates.bridge, paths: paths)
        #expect(rendered.contains("Altillo \\\"test\\\".app"))
        #expect(!rendered.contains("__HELPER_PATH__"))
        #expect(rendered.contains(MailRuleInstaller.quote(paths.socketPath)))
    }

    @Test func publicOrSymlinkDirectoriesAreRefusedWithoutChangingPermissions() throws {
        let (root, _) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let publicDirectory = root.appendingPathComponent("public")
        try FileManager.default.createDirectory(at: publicDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        #expect(throws: MailRuleInstaller.Failure.self) { try MailRuleInstaller.ensurePrivateDirectory(publicDirectory) }
        let attributes = try FileManager.default.attributesOfItem(atPath: publicDirectory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o755)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        #expect(throws: MailRuleInstaller.Failure.self) { try MailRuleInstaller.ensurePrivateDirectory(link) }
    }

    @Test func unownedSameNameScriptIsNotReplaced() throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: paths.scriptsDirectory, withIntermediateDirectories: true)
        let original = Data("somebody else's script".utf8)
        try original.write(to: paths.handler)
        #expect(throws: MailRuleInstaller.Failure.self) {
            try MailRuleInstaller.prepareFiles(paths: paths, templates: templates, compiler: copyCompiler)
        }
        #expect(try Data(contentsOf: paths.handler) == original)
        #expect(!FileManager.default.fileExists(atPath: paths.manifest.path))
    }

    @Test func prepareAndRefreshOnlyInspectMailAfterOwnedScriptsExist() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        var inspections = 0
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler, runScript: { _ in
            inspections += 1
            return "configured"
        })
        await installer.refresh()
        #expect(installer.status == .notPrepared && inspections == 0)
        await installer.prepare()
        #expect(installer.status == .prepared && inspections == 0)
        #expect(try MailRuleInstaller.verifyOwnedFiles(paths: paths) == true)
        await installer.refresh()
        #expect(installer.status == .configured && inspections == 1)
        #expect(!installer.isWorking && installer.problem == nil)
    }

    @Test func changedScriptPreventsInspectionAndRemoval() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        var events = 0
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler, runScript: { _ in
            events += 1
            return "absent"
        })
        await installer.prepare()
        let changed = Data("user changed this".utf8)
        try changed.write(to: paths.handler)
        await installer.uninstall()
        #expect(installer.status == .changed && events == 0)
        #expect(try Data(contentsOf: paths.handler) == changed)
        #expect(FileManager.default.fileExists(atPath: paths.bridge.path))
    }

    @Test func uninstallOnlyRemovesOwnedFilesAfterMailConfirmsNoRuleReferencesThem() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler, runScript: { source in
            #expect(source.contains(MailRuleInstaller.quote(paths.handler.path)))
            #expect(source.contains(MailRuleInstaller.quote(paths.bridge.path)))
            #expect(!source.contains("delete candidate"))
            return "absent"
        })
        await installer.prepare()
        let unrelated = paths.scriptsDirectory.appendingPathComponent("Unrelated.scpt")
        try Data("keep".utf8).write(to: unrelated)
        await installer.uninstall()
        #expect(installer.status == .notPrepared)
        #expect(!FileManager.default.fileExists(atPath: paths.handler.path))
        #expect(!FileManager.default.fileExists(atPath: paths.bridge.path))
        #expect(!FileManager.default.fileExists(atPath: paths.manifest.path))
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
    }

    @Test func anExistingOrRenamedMailRuleIsNeverRemovedAndKeepsItsScripts() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler, runScript: { source in
            #expect(source.contains("repeat with candidate in every rule"))
            #expect(!source.contains("delete "))
            return "present"
        })
        await installer.prepare()
        await installer.uninstall()
        #expect(installer.status == .manualRemovalRequired)
        #expect(installer.problem != nil)
        #expect(try MailRuleInstaller.verifyOwnedFiles(paths: paths) == true)
    }

    @Test func compilationFailurePreservesPreviousOwnedInstallation() throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        try MailRuleInstaller.prepareFiles(paths: paths, templates: templates, compiler: copyCompiler)
        let previous = try Data(contentsOf: paths.handler)
        #expect(throws: MailRuleInstaller.Failure.self) {
            try MailRuleInstaller.prepareFiles(paths: paths, templates: templates, compiler: { _, _ in
                throw MailRuleInstaller.Failure.compilerFailed
            })
        }
        #expect(try Data(contentsOf: paths.handler) == previous)
        #expect(try MailRuleInstaller.verifyOwnedFiles(paths: paths) == true)
    }

    @Test func aFileIntroducedDuringCompilationIsNotRemovedByRollback() throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let intruder = Data("user added a same-name script".utf8)
        #expect(throws: MailRuleInstaller.Failure.self) {
            try MailRuleInstaller.prepareFiles(paths: paths, templates: templates, compiler: { source, target in
                try Data(contentsOf: source).write(to: target)
                try intruder.write(to: paths.handler)
            })
        }
        #expect(try Data(contentsOf: paths.handler) == intruder)
        #expect(!FileManager.default.fileExists(atPath: paths.manifest.path))
    }

    @Test func corruptOrSymlinkManifestDoesNotAuthorizeFileDeletion() throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        try MailRuleInstaller.prepareFiles(paths: paths, templates: templates, compiler: copyCompiler)
        try Data("{}".utf8).write(to: paths.manifest)
        #expect(throws: MailRuleInstaller.Failure.self) { try MailRuleInstaller.verifyOwnedFiles(paths: paths) }
        try FileManager.default.removeItem(at: paths.manifest)
        let other = root.appendingPathComponent("unrelated.json")
        try Data("{}".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: paths.manifest, withDestinationURL: other)
        #expect(throws: MailRuleInstaller.Failure.self) { try MailRuleInstaller.verifyOwnedFiles(paths: paths) }
        #expect(FileManager.default.fileExists(atPath: paths.handler.path))
    }
    @Test func automationDenialExplainsHowToReconnectWithoutChangingFiles() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler,
                                          runScript: { _ in throw AppleScriptRunner.Failure.notAuthorised })
        await installer.prepare()
        await installer.refresh()
        #expect(installer.status == .unavailable)
        #expect(installer.problem == String(localized: "Allow Altillo to control Apple Mail in System Settings → Privacy & Security → Automation, then check the rule again."))
        #expect(try MailRuleInstaller.verifyOwnedFiles(paths: paths) == true)
    }

    @Test func inspectionDeadlineTerminatesAStalledScript() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: MailRuleInstaller.Failure.inspectionTimedOut) {
            _ = try await MailRuleInstaller.runInspection("delay 30\nreturn 1", timeout: .milliseconds(100))
        }
        #expect(start.duration(to: clock.now) < .seconds(3))
    }

    @Test func inspectionScriptsCompileAgainstThePublicMailDictionary() throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        for removing in [false, true] {
            let source = root.appendingPathComponent("inspection.applescript")
            let output = root.appendingPathComponent("inspection.scpt")
            try MailRuleInstaller.inspectionScript(paths: paths, remove: removing).write(to: source, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
            process.arguments = ["-o", output.path, source.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
    }

    @Test func mailTimeoutDoesNotBlameChangedFilesOrExposeScriptErrorContent() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler,
                                          runScript: { _ in throw AppleScriptRunner.Failure.failed("private script detail (-1712)") })
        await installer.prepare()
        await installer.refresh()
        #expect(installer.status == .unavailable)
        #expect(installer.problem?.contains("private script detail") == false)
        #expect(try MailRuleInstaller.verifyOwnedFiles(paths: paths) == true)
    }

}
