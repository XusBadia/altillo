import Foundation
import Testing
@testable import Altillo

@MainActor
struct MailIntegrationSettingsTests {
    private func makeDefaults() -> (String, UserDefaults) {
        let name = "me.badia.altillo.tests.mail-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (name, defaults)
    }

    @Test func mailIsOptInOnFreshInstall() {
        let (name, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AltilloSettings(defaults: defaults)
        #expect(NotchModule.mail.isOptIn)
        #expect(!AltilloSettings.defaultModules.contains(.mail))
        #expect(!settings.isEnabled(.mail))
        #expect(settings.mailAllowedSenders.isEmpty && settings.mailAllowedAccounts.isEmpty)
    }

    @Test func upgradeDoesNotEnableMailOrChangeExistingModuleChoice() {
        let (name, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let previousKnown = NotchModule.allCases.filter { $0 != .mail }.map(\.rawValue)
        defaults.set(previousKnown, forKey: "knownModules")
        defaults.set(["shelf", "calendar"], forKey: "modules")
        let settings = AltilloSettings(defaults: defaults)
        #expect(!settings.isEnabled(.mail))
        #expect(settings.modules == [.shelf, .calendar])
        #expect(defaults.stringArray(forKey: "knownModules")?.contains("mail") == true)
    }

    @Test func legacyModuleMigrationStillLeavesMailOff() {
        let (name, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["shelf", "calendar"], forKey: "modules")
        let settings = AltilloSettings(defaults: defaults)
        #expect(!settings.isEnabled(.mail))
        #expect(settings.modules.first == .shelf)
        #expect(settings.modules.contains(.calendar))
    }

    @Test func explicitMailChoiceAndFiltersSurviveRelaunch() {
        let (name, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AltilloSettings(defaults: defaults)
        settings.setEnabled(.mail, true)
        settings.alertsForMail = false
        settings.mailAllowedSenders = "work@example.invalid, @other.invalid"
        settings.mailAllowedAccounts = "Work\nPersonal"
        let restored = AltilloSettings(defaults: defaults)
        #expect(restored.isEnabled(.mail))
        #expect(!restored.alertsForMail)
        #expect(restored.mailAllowedSenders == "work@example.invalid, @other.invalid")
        #expect(restored.mailAllowedAccounts == "Work\nPersonal")
        restored.setEnabled(.mail, false)
        #expect(!AltilloSettings(defaults: defaults).isEnabled(.mail))
    }
}
