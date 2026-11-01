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

    @Test func prepareAndRefreshValidateOnlyTheTemporaryOwnedFiles() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        // The entire installation is under a fresh temporary directory. Refresh requires no real Mail setup.
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler)
        await installer.refresh()
        #expect(installer.status == .notPrepared)
        await installer.prepare()
        #expect(installer.status == .prepared)
        #expect(try MailRuleInstaller.verifyOwnedFiles(paths: paths) == true)
        let manifest = try Data(contentsOf: paths.manifest)
        await installer.refresh()
        #expect(installer.status == .prepared)
        #expect(!installer.isWorking && installer.problem == nil)
        #expect(try Data(contentsOf: paths.manifest) == manifest)
    }

    @Test func changedScriptIsReportedWithoutChangingItDuringRefreshOrRemoval() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler)
        await installer.prepare()
        let changed = Data("user changed this".utf8)
        try changed.write(to: paths.handler)
        await installer.refresh()
        #expect(installer.status == .changed)
        #expect(try Data(contentsOf: paths.handler) == changed)
        await installer.uninstall()
        #expect(installer.status == .changed)
        #expect(try Data(contentsOf: paths.handler) == changed)
        #expect(FileManager.default.fileExists(atPath: paths.bridge.path))
        #expect(FileManager.default.fileExists(atPath: paths.manifest.path))
    }

    @Test func uninstallPreservesEveryOwnedFileAndUnrelatedScriptsForManualRemoval() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler)
        await installer.prepare()
        let unrelated = paths.scriptsDirectory.appendingPathComponent("Unrelated.scpt")
        try Data("keep".utf8).write(to: unrelated)
        let files = [paths.handler, paths.bridge, paths.manifest, unrelated]
        let before = try files.map { try Data(contentsOf: $0) }
        await installer.uninstall()
        #expect(installer.status == .manualRemovalRequired)
        #expect(installer.problem == nil)
        #expect(!installer.isWorking)
        #expect(try files.map { try Data(contentsOf: $0) } == before)
        #expect(try MailRuleInstaller.verifyOwnedFiles(paths: paths) == true)
    }

    @Test func uninstallWithoutAnInstallationDoesNotCreateFilesOrRequireManualRemoval() async throws {
        let (root, paths) = try makePaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = MailRuleInstaller(paths: paths, templates: templates, compiler: copyCompiler)
        await installer.uninstall()
        #expect(installer.status == .notPrepared)
        #expect(installer.problem == nil)
        #expect(!FileManager.default.fileExists(atPath: paths.scriptsDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: paths.manifest.path))
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
}
