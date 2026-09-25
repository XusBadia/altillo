import Foundation
import Testing
@testable import Altillo

/// The hook installer (PLAN §5.3, §9): it edits other apps' config files, so every promise is pinned here: other
/// settings and hooks untouched, idempotent, a removal that gives the original back, broken files refused, a backup
/// before every write, atomic writes that keep permissions and links. Everything runs in a temporary directory;
/// the real ~/.claude and ~/.codex are never touched.
struct AgentHookInstallerTests {
    /// A fake home with `~/.claude` and `~/.codex`, Altillo's support directory and an executable stand-in for the
    /// embedded `altillo-hook`.
    struct Sandbox {
        let root: URL
        let environment: AgentHookEnvironment
        let fakeHook: URL

        init(claude: Bool = true, codex: Bool = true, linkHook: Bool = true) throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "altillo-hook-installer-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            let home = root.appending(path: "home", directoryHint: .isDirectory)
            environment = AgentHookEnvironment(
                home: home, variables: [:],
                supportDirectory: home.appending(path: "Library/Application Support/Altillo", directoryHint: .isDirectory)
            )
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
            if claude { try fileManager.createDirectory(at: home.appending(path: ".claude"), withIntermediateDirectories: true) }
            if codex { try fileManager.createDirectory(at: home.appending(path: ".codex"), withIntermediateDirectories: true) }
            fakeHook = root.appending(path: "Altillo.app/Contents/MacOS/altillo-hook")
            try fileManager.createDirectory(at: fakeHook.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: fakeHook)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHook.path)
            if linkHook { _ = AgentHookInstaller.linkStableHook(to: fakeHook, environment: environment) }
        }

        func installer(wait: Int = 120) -> AgentHookInstaller {
            AgentHookInstaller(environment: environment, wait: wait)
        }

        func file(_ target: AgentHookTarget) -> URL { environment.configFile(for: target) }

        func write(_ text: String, to target: AgentHookTarget, permissions: Int = 0o600) throws {
            try Data(text.utf8).write(to: file(target))
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file(target).path)
        }

        func read(_ target: AgentHookTarget) throws -> String {
            try String(contentsOf: file(target), encoding: .utf8)
        }

        func permissions(_ url: URL) throws -> Int {
            (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
        }

        @discardableResult
        func install(_ target: AgentHookTarget, wait: Int = 120) throws -> AgentHookInstaller.Outcome {
            let installer = installer(wait: wait)
            return try installer.apply(installer.planInstall(target))
        }

        @discardableResult
        func uninstall(_ target: AgentHookTarget) throws -> AgentHookInstaller.Outcome {
            let installer = installer()
            return try installer.apply(installer.planUninstall(target))
        }
    }

    /// A settings file like a real one: user hooks on an event Altillo also uses (with a matcher), on one it
    /// doesn't, and settings on both sides of `hooks`.
    static let userSettings = """
    {
      "model": "opus",
      "permissions": {
        "allow": [
          "Bash(git status)"
        ],
        "defaultMode": "default"
      },
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Bash",
            "hooks": [
              {
                "type": "command",
                "command": "~/bin/guard.sh",
                "timeout": 30
              }
            ]
          }
        ],
        "PreCompact": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "echo compacting"
              }
            ]
          }
        ]
      },
      "cleanupPeriodDays": 30.0,
      "statusLine": {
        "type": "command",
        "command": "~/.claude/statusline.sh"
      }
    }

    """

    private static func object(_ text: String) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
    }

    private static func altilloHandlers(in text: String) throws -> [(event: String, handler: [String: Any])] {
        let root = try object(text)
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        var found: [(String, [String: Any])] = []
        for (event, groups) in hooks {
            for group in groups as? [[String: Any]] ?? [] {
                for handler in group["hooks"] as? [[String: Any]] ?? []
                where AgentHookCommand.isAltilloCommand(handler["command"] as? String ?? "") {
                    found.append((event, handler))
                }
            }
        }
        return found
    }

    // MARK: - Installing

    @Test func installIntoAMissingFileCreatesItWithEveryEventPrivately() throws {
        let sandbox = try Sandbox()
        #expect(sandbox.installer().status(for: .claude) == .notInstalled)

        let outcome = try sandbox.install(.claude)

        #expect(outcome.backup == nil, "nothing to back up")
        let text = try sandbox.read(.claude)
        let handlers = try Self.altilloHandlers(in: text)
        #expect(Set(handlers.map(\.event)) == Set(AgentHookTarget.claude.events.map(\.name)))
        #expect(handlers.count == AgentHookTarget.claude.events.count)
        #expect(try sandbox.permissions(sandbox.file(.claude)) == 0o600)
        #expect(sandbox.installer().status(for: .claude) == .installed)
    }

    @Test func installWritesTheVerifiedSchema() throws {
        let sandbox = try Sandbox()
        try sandbox.install(.claude)
        let root = try Self.object(sandbox.read(.claude))
        let hooks = try #require(root["hooks"] as? [String: Any])
        let permission = try #require(hooks["PermissionRequest"] as? [[String: Any]])
        #expect(permission.count == 1)
        #expect(permission[0]["matcher"] == nil, "no matcher: matches every tool")
        let handler = try #require((permission[0]["hooks"] as? [[String: Any]])?.first)
        #expect(handler["type"] as? String == "command")
        #expect(handler["timeout"] as? Int == 150, "the wait plus the margin")
        let link = sandbox.environment.hookLink.path
        #expect(handler["command"] as? String == "\"\(link)\" claude PermissionRequest --timeout 120")
        let stop = try #require((hooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
        #expect(stop[0]["command"] as? String == "\"\(link)\" claude Stop")
        #expect(stop[0]["timeout"] as? Int == AgentHookCommand.quickTimeout)
        let end = try #require((hooks["SessionEnd"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
        #expect(end[0]["timeout"] == nil, "SessionEnd keeps the agent's own short budget")
        #expect(Set(handler.keys) == ["type", "command", "timeout"], "no keys the CLI doesn't know")
    }

    @Test func installIntoAnEmptyFileWorks() throws {
        let sandbox = try Sandbox()
        try sandbox.write("", to: .claude)
        try sandbox.install(.claude)
        #expect(sandbox.installer().status(for: .claude) == .installed)
    }

    @Test func installLeavesTheUsersSettingsAndHooksExactlyAsTheyWere() throws {
        let sandbox = try Sandbox()
        try sandbox.write(Self.userSettings, to: .claude)

        try sandbox.install(.claude)
        let text = try sandbox.read(.claude)

        // The user's own PreToolUse group is still first and unchanged; Altillo's comes after it.
        let root = try Self.object(text)
        let hooks = try #require(root["hooks"] as? [String: Any])
        let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(preToolUse.count == 2)
        let original = try #require((try Self.object(Self.userSettings)["hooks"] as? [String: Any])?["PreToolUse"]
            as? [[String: Any]])
        #expect(preToolUse[0] as NSDictionary == original[0] as NSDictionary)
        #expect(hooks["PreCompact"] != nil)
        // Everything but "hooks" is byte-for-byte where it was: the diff only adds lines.
        let diff = UnifiedDiff(old: Self.userSettings, new: text)
        #expect(diff.removedCount == 0)
        #expect(text.contains("\"cleanupPeriodDays\": 30.0"), "numbers keep their spelling")
        // Semantically: take Altillo's handlers out again and it's the original.
        let stripped = AgentHookInstaller.removingAltilloHooks(from: try OrderedJSON.parse(text), createdKeys: nil)
        #expect(try Self.object(stripped.serialized()) == Self.object(Self.userSettings))
        // Key order is kept too.
        #expect(stripped == (try OrderedJSON.parse(Self.userSettings)))
    }

    @Test func installingTwiceIsTheSameAsOnce() throws {
        let sandbox = try Sandbox()
        try sandbox.write(Self.userSettings, to: .claude)
        try sandbox.install(.claude)
        let once = try sandbox.read(.claude)

        let plan = try sandbox.installer().planInstall(.claude)
        #expect(plan.changesNothing)
        #expect(plan.diff.isEmpty)
        let outcome = try sandbox.installer().apply(plan)
        #expect(outcome.backup == nil, "no write, no backup")
        #expect(try sandbox.read(.claude) == once)
    }

    @Test func installBacksUpTheFileFirst() throws {
        let sandbox = try Sandbox()
        try sandbox.write(Self.userSettings, to: .claude)

        let outcome = try sandbox.install(.claude)

        let backup = try #require(outcome.backup)
        #expect(backup.deletingLastPathComponent().standardizedFileURL
            == sandbox.environment.backupsDirectory.standardizedFileURL)
        #expect(backup.lastPathComponent.hasPrefix("claude-"))
        #expect(backup.pathExtension == "json")
        #expect(try String(contentsOf: backup, encoding: .utf8) == Self.userSettings)
        #expect(try sandbox.permissions(backup) == 0o600)
    }

    @Test func writesKeepTheFilesPermissions() throws {
        let sandbox = try Sandbox()
        try sandbox.write(Self.userSettings, to: .claude, permissions: 0o644)
        try sandbox.install(.claude)
        #expect(try sandbox.permissions(sandbox.file(.claude)) == 0o644)
    }

    @Test func aLinkedSettingsFileIsEditedWhereItLivesAndStaysALink() throws {
        let sandbox = try Sandbox()
        let dotfiles = sandbox.root.appending(path: "dotfiles/settings.json")
        try FileManager.default.createDirectory(at: dotfiles.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.userSettings.utf8).write(to: dotfiles)
        try FileManager.default.createSymbolicLink(at: sandbox.file(.claude), withDestinationURL: dotfiles)

        try sandbox.install(.claude)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: sandbox.file(.claude).path) == dotfiles.path)
        #expect(try Self.altilloHandlers(in: String(contentsOf: dotfiles, encoding: .utf8)).count
            == AgentHookTarget.claude.events.count)
    }

    // MARK: - Removing

    @Test func uninstallGivesTheOriginalFileBack() throws {
        let sandbox = try Sandbox()
        try sandbox.write(Self.userSettings, to: .claude)
        try sandbox.install(.claude)

        let outcome = try sandbox.uninstall(.claude)

        #expect(outcome.backup != nil)
        #expect(try sandbox.read(.claude) == Self.userSettings, "byte for byte")
        #expect(sandbox.installer().status(for: .claude) == .notInstalled)
    }

    @Test func uninstallRemovesTheHooksKeyOnlyIfAltilloAddedIt() throws {
        let sandbox = try Sandbox()
        let without = "{\n  \"model\": \"opus\"\n}\n"
        try sandbox.write(without, to: .claude)
        try sandbox.install(.claude)
        try sandbox.uninstall(.claude)
        #expect(try sandbox.read(.claude) == without)

        let emptyHooks = "{\n  \"model\": \"opus\",\n  \"hooks\": {}\n}\n"
        try sandbox.write(emptyHooks, to: .claude)
        try sandbox.install(.claude)
        try sandbox.uninstall(.claude)
        #expect(try sandbox.read(.claude) == emptyHooks, "the user's own empty hooks stay")
    }

    @Test func uninstallDeletesAFileAltilloCreatedAndLeftEmpty() throws {
        let sandbox = try Sandbox()
        try sandbox.install(.codex)
        #expect(FileManager.default.fileExists(atPath: sandbox.file(.codex).path))

        let plan = try sandbox.installer().planUninstall(.codex)
        #expect(plan.newText == nil)
        try sandbox.installer().apply(plan)

        #expect(!FileManager.default.fileExists(atPath: sandbox.file(.codex).path))
    }

    @Test func uninstallKeepsAFileAltilloCreatedOnceTheUserAddedToIt() throws {
        let sandbox = try Sandbox()
        try sandbox.install(.codex)
        var document = try OrderedJSON.parse(sandbox.read(.codex))
        document.set("description", .string("mine"))
        try sandbox.write(document.serialized(), to: .codex)

        try sandbox.uninstall(.codex)

        #expect(try sandbox.read(.codex) == "{\n  \"description\": \"mine\"\n}\n")
    }

    @Test func uninstallWithoutAnythingInstalledChangesNothing() throws {
        let sandbox = try Sandbox()
        try sandbox.write(Self.userSettings, to: .claude)
        let plan = try sandbox.installer().planUninstall(.claude)
        #expect(plan.diff.isEmpty)
        try sandbox.installer().apply(plan)
        #expect(try sandbox.read(.claude) == Self.userSettings)
    }

    // MARK: - Refusing

    @Test func aBrokenFileIsRefusedAndLeftAlone() throws {
        let sandbox = try Sandbox()
        let broken = "{\n  \"model\": \"opus\",\n  \"hooks\": {\n}\n"
        try sandbox.write(broken, to: .claude)

        guard case .unreadable(let reason) = sandbox.installer().status(for: .claude) else {
            Issue.record("expected unreadable"); return
        }
        #expect(reason.contains("JSON"))
        #expect(throws: AgentHookError.self) { try sandbox.installer().planInstall(.claude) }
        #expect(throws: AgentHookError.self) { try sandbox.installer().planUninstall(.claude) }
        #expect(try sandbox.read(.claude) == broken)
        #expect(!FileManager.default.fileExists(atPath: sandbox.environment.backupsDirectory.path))
    }

    @Test func trailingCommasAndCommentsAreRefused() throws {
        let sandbox = try Sandbox()
        for text in ["{\"a\": 1,}", "{\n  // note\n  \"a\": 1\n}", "[1, 2]", "{\"hooks\": []}"] {
            try sandbox.write(text, to: .claude)
            guard case .unreadable = sandbox.installer().status(for: .claude) else {
                Issue.record("expected unreadable for \(text)"); continue
            }
        }
    }

    @Test func aFileChangedAfterReviewIsNotOverwritten() throws {
        let sandbox = try Sandbox()
        try sandbox.write(Self.userSettings, to: .claude)
        let plan = try sandbox.installer().planInstall(.claude)
        let changed = Self.userSettings.replacingOccurrences(of: "opus", with: "sonnet")
        try sandbox.write(changed, to: .claude)

        #expect(throws: AgentHookError.changedSinceReview) { try sandbox.installer().apply(plan) }
        #expect(try sandbox.read(.claude) == changed)
    }

    @Test func aMissingAgentIsReported() throws {
        let sandbox = try Sandbox(claude: false, codex: false)
        #expect(sandbox.installer().status(for: .claude) == .agentNotFound)
        #expect(sandbox.installer().status(for: .codex) == .agentNotFound)
        #expect(throws: AgentHookError.agentNotFound(.codex)) { try sandbox.installer().planInstall(.codex) }
    }

    // MARK: - Repair

    @Test func aMissingHookNeedsRepair() throws {
        let sandbox = try Sandbox()
        try sandbox.install(.claude)
        try FileManager.default.removeItem(at: sandbox.fakeHook)

        #expect(sandbox.installer().status(for: .claude) == .needsRepair(.hookMissing))

        // Relinking to the app's new place fixes it without touching the file.
        let moved = sandbox.root.appending(path: "Applications/Altillo.app/Contents/MacOS/altillo-hook")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: moved)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: moved.path)
        #expect(AgentHookInstaller.linkStableHook(to: moved, environment: sandbox.environment) == .linked(to: moved.path))
        #expect(sandbox.installer().status(for: .claude) == .installed)
    }

    @Test func anotherWaitNeedsAnUpdateThatOnlyTouchesPermissionRequest() throws {
        let sandbox = try Sandbox()
        try sandbox.write(Self.userSettings, to: .claude)
        try sandbox.install(.claude, wait: 120)

        #expect(sandbox.installer(wait: 300).status(for: .claude) == .needsRepair(.outdated))
        let plan = try sandbox.installer(wait: 300).planInstall(.claude)
        #expect(plan.diff.removedCount == 2)
        #expect(plan.diff.addedCount == 2)
        #expect(plan.diff.text.contains("+            \"timeout\": 330"))
        try sandbox.installer(wait: 300).apply(plan)
        #expect(sandbox.installer(wait: 300).status(for: .claude) == .installed)
    }

    @Test func hooksFromAnOlderVersionAreReplacedInPlace() throws {
        let sandbox = try Sandbox()
        // An older build pointed straight into the app bundle and had a Stop hook in a group of its own, between
        // two of the user's.
        let old = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo first"
                  }
                ]
              },
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/Applications/Altillo.app/Contents/MacOS/altillo-hook claude Stop"
                  }
                ]
              },
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo last"
                  }
                ]
              }
            ]
          }
        }

        """
        try sandbox.write(old, to: .claude)
        #expect(sandbox.installer().status(for: .claude) == .needsRepair(.outdated))

        try sandbox.install(.claude)

        let root = try Self.object(sandbox.read(.claude))
        let stop = try #require((root["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        let commands = stop.compactMap { ($0["hooks"] as? [[String: Any]])?.first?["command"] as? String }
        #expect(commands == ["echo first", "\"\(sandbox.environment.hookLink.path)\" claude Stop", "echo last"])
        #expect(sandbox.installer().status(for: .claude) == .installed)
    }

    @Test func anAltilloHookSharingAGroupWithTheUsersIsTakenOutAlone() throws {
        let shared = OrderedJSON.object([
            .init(key: "hooks", value: .object([
                .init(key: "Stop", value: .array([.object([
                    .init(key: "matcher", value: .string("")),
                    .init(key: "hooks", value: .array([
                        .object([.init(key: "type", value: .string("command")),
                                 .init(key: "command", value: .string("say done"))]),
                        .object([.init(key: "type", value: .string("command")),
                                 .init(key: "command", value: .string("'/x/altillo-hook' claude Stop"))]),
                    ])),
                ])])),
            ])),
        ])
        let removed = AgentHookInstaller.removingAltilloHooks(from: shared, createdKeys: nil)
        let handlers = removed["hooks"]?["Stop"]?.elements?.first?["hooks"]?.elements
        #expect(handlers?.count == 1)
        #expect(handlers?.first?["command"] == .string("say done"))
        #expect(removed["hooks"]?["Stop"]?.elements?.first?["matcher"] == .string(""))
    }

    // MARK: - Codex

    @Test func codexGetsItsOwnEventsInHooksJSON() throws {
        let sandbox = try Sandbox()
        try sandbox.install(.codex)
        #expect(sandbox.file(.codex).lastPathComponent == "hooks.json")
        let handlers = try Self.altilloHandlers(in: sandbox.read(.codex))
        let events = Set(handlers.map(\.event))
        #expect(events == Set(AgentHookTarget.codex.events.map(\.name)))
        #expect(events.contains("Interrupt"))
        #expect(!events.contains("Notification"), "Codex has no Notification event")
        #expect(handlers.allSatisfy { ($0.handler["command"] as? String)?.contains(" codex ") == true })
        #expect(sandbox.installer().status(for: .codex) == .installed)
    }

    @Test func codexHooksSwitchedOffInConfigTOMLAreNoticed() {
        #expect(AgentHookInstaller.codexHooksDisabled(configTOML: "[features]\nhooks = false\n"))
        #expect(AgentHookInstaller.codexHooksDisabled(configTOML: "model = \"x\"\n[features]\ncodex_hooks = false # old\n"))
        #expect(AgentHookInstaller.codexHooksDisabled(configTOML: "features.hooks = false\n"))
        #expect(!AgentHookInstaller.codexHooksDisabled(configTOML: "[features]\nhooks = true\njs_repl = false\n"))
        #expect(!AgentHookInstaller.codexHooksDisabled(configTOML: "[mcp_servers.x]\nhooks = false\n"))
    }

    @Test func codexNotesReadConfigTOML() throws {
        let sandbox = try Sandbox()
        try Data("[features]\nhooks = false\n".utf8)
            .write(to: sandbox.environment.configDirectory(for: .codex).appending(path: "config.toml"))
        #expect(sandbox.installer().report(for: .codex).notes.count == 1)
    }

    // MARK: - Paths

    @Test func configDirectoriesFollowTheAgentsVariables() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        var environment = AgentHookEnvironment(home: home, variables: [:], supportDirectory: home)
        #expect(environment.configFile(for: .claude).path == "/Users/someone/.claude/settings.json")
        #expect(environment.configFile(for: .codex).path == "/Users/someone/.codex/hooks.json")
        environment.variables = ["CLAUDE_CONFIG_DIR": "/tmp/claude-alt", "CODEX_HOME": "~/codex-home"]
        #expect(environment.configFile(for: .claude).path == "/tmp/claude-alt/settings.json")
        #expect(environment.configFile(for: .codex).path == "/Users/someone/codex-home/hooks.json")
        #expect(environment.displayPath(environment.configFile(for: .codex)) == "~/codex-home/hooks.json")
    }

    @Test func theStableHookLinkIsCreatedKeptAndMoved() throws {
        let sandbox = try Sandbox(linkHook: false)
        let link = sandbox.environment.hookLink

        #expect(AgentHookInstaller.linkStableHook(to: sandbox.fakeHook, environment: sandbox.environment)
            == .linked(to: sandbox.fakeHook.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == sandbox.fakeHook.path)
        #expect(FileManager.default.isExecutableFile(atPath: link.path))
        #expect(AgentHookInstaller.linkStableHook(to: sandbox.fakeHook, environment: sandbox.environment) == .unchanged)

        let other = sandbox.root.appending(path: "Other.app/Contents/MacOS/altillo-hook")
        #expect(AgentHookInstaller.linkStableHook(to: other, environment: sandbox.environment) == .linked(to: other.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == other.path)

        let translocated = URL(filePath: "/private/var/folders/x/AppTranslocation/ABC/d/Altillo.app/Contents/MacOS/altillo-hook")
        guard case .unavailable = AgentHookInstaller.linkStableHook(to: translocated, environment: sandbox.environment) else {
            Issue.record("a translocated copy must not be linked"); return
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == other.path)
    }

    @Test func aBundleWithoutTheHookIsReported() throws {
        let sandbox = try Sandbox(linkHook: false)
        let empty = sandbox.root.appending(path: "Empty.bundle", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let bundle = try #require(Bundle(url: empty))
        guard case .unavailable = AgentHookInstaller.refreshStableHookPath(environment: sandbox.environment,
                                                                           bundle: bundle) else {
            Issue.record("expected unavailable"); return
        }
    }

    // MARK: - The command line

    @Test func commandsAreQuotedAndRecognised() {
        let path = "/Users/a b/Library/Application Support/Altillo/bin/altillo-hook"
        let event = AgentHookEvent("PermissionRequest", waitsForDecision: true)
        let command = AgentHookCommand.command(hookPath: path, agent: .codex, event: event, wait: 60)
        #expect(command == "\"\(path)\" codex PermissionRequest --timeout 60")
        #expect(AgentHookCommand.executable(of: command) == path)
        #expect(AgentHookCommand.timeout(for: event, wait: 60) == 90)
        #expect(AgentHookCommand.shellQuoted("a\"b$c`d\\e") == "\"a\\\"b\\$c\\`d\\\\e\"")

        #expect(AgentHookCommand.isAltilloCommand(command))
        #expect(AgentHookCommand.isAltilloCommand("/Applications/Altillo.app/Contents/MacOS/altillo-hook claude Stop"))
        #expect(AgentHookCommand.isAltilloCommand("'/tmp/x y/altillo-hook' claude Stop"))
        #expect(AgentHookCommand.isAltilloCommand("/tmp/x\\ y/altillo-hook claude Stop"))
        #expect(!AgentHookCommand.isAltilloCommand("echo altillo-hook"))
        #expect(!AgentHookCommand.isAltilloCommand("/usr/local/bin/altillo-hook-helper"))
        #expect(!AgentHookCommand.isAltilloCommand(""))
    }
}

/// The pieces under the installer: the order-keeping JSON and the diff shown before writing.
struct AgentHookInstallerPartsTests {
    @Test func jsonRoundTripsTheWayTheAgentsWriteIt() throws {
        let text = """
        {
          "z": 1,
          "a": [],
          "m": {},
          "n": [
            1.50,
            -2e10,
            true,
            null,
            "é \\" \\\\ \\n /"
          ],
          "dup": 1,
          "dup": 2
        }

        """
        let document = try OrderedJSON.parse(text)
        #expect(document.serialized(style: .detect(in: text)) == text)
        #expect(document.members?.map(\.key) == ["z", "a", "m", "n", "dup", "dup"])
    }

    @Test func jsonKeepsTheIndentAndTheMissingFinalNewline() throws {
        let text = "{\n    \"a\": {\n        \"b\": 1\n    }\n}"
        #expect(try OrderedJSON.parse(text).serialized(style: .detect(in: text)) == text)
        let tabs = "{\n\t\"a\": [\n\t\t1\n\t]\n}\n"
        #expect(try OrderedJSON.parse(tabs).serialized(style: .detect(in: tabs)) == tabs)
    }

    @Test func jsonDecodesEscapesAndSurrogates() throws {
        let document = try OrderedJSON.parse(#"{"s": "é😀\t"}"#)
        #expect(document["s"] == .string("é😀\t"))
    }

    @Test func jsonErrorsSayWhere() {
        do {
            _ = try OrderedJSON.parse("{\n  \"a\": 1\n  \"b\": 2\n}")
            Issue.record("expected an error")
        } catch {
            #expect(error.line == 3)
        }
    }

    @Test func diffIsAStandardUnifiedDiff() {
        let old = "{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3,\n  \"d\": 4,\n  \"e\": 5\n}\n"
        let new = "{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3,\n  \"d\": 4,\n  \"e\": 5,\n  \"f\": 6\n}\n"
        let diff = UnifiedDiff(old: old, new: new, oldName: "settings.json", newName: "settings.json")
        #expect(diff.text == """
        --- settings.json
        +++ settings.json
        @@ -3,5 +3,6 @@
           "b": 2,
           "c": 3,
           "d": 4,
        -  "e": 5
        +  "e": 5,
        +  "f": 6
         }

        """)
        #expect(diff.addedCount == 2)
        #expect(diff.removedCount == 1)
    }

    @Test func diffOfANewFileAndOfNothing() {
        let created = UnifiedDiff(old: "", new: "{\n}\n", oldName: "/dev/null", newName: "hooks.json")
        #expect(created.text == "--- /dev/null\n+++ hooks.json\n@@ -0,0 +1,2 @@\n+{\n+}\n")
        let deleted = UnifiedDiff(old: "{\n}\n", new: "", oldName: "hooks.json", newName: "/dev/null")
        #expect(deleted.text == "--- hooks.json\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-{\n-}\n")
        #expect(UnifiedDiff(old: "same\n", new: "same\n").isEmpty)
    }

    @Test func farApartChangesMakeSeparateHunks() {
        let old = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"
        var lines = (1...20).map { "line \($0)" }
        lines[1] = "changed 2"
        lines[18] = "changed 19"
        let diff = UnifiedDiff(old: old, new: lines.joined(separator: "\n") + "\n")
        #expect(diff.hunks.count == 2)
        #expect(diff.hunks[0].header == "@@ -1,5 +1,5 @@")
        #expect(diff.hunks[1].header == "@@ -16,5 +16,5 @@")
    }
}

@Test func developmentBuildsAreRecognisedSoTheyNeverStealTheHookLink() {
    #expect(AgentHookInstaller.isDevelopmentBuild("/Users/x/altillo/build/dd/Build/Products/Debug/Altillo.app/Contents/MacOS/altillo-hook"))
    #expect(AgentHookInstaller.isDevelopmentBuild("/Users/x/Library/Developer/Xcode/DerivedData/Altillo-abc/Build/Products/Debug/Altillo.app"))
    #expect(!AgentHookInstaller.isDevelopmentBuild("/Applications/Altillo.app/Contents/MacOS/altillo-hook"))
}
