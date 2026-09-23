import Foundation
import Testing
@testable import Altillo

/// Settings are the whole of PLAN §4: defaults that already work, nothing lost between launches.
@MainActor
struct AltilloSettingsTests {
    /// A private `UserDefaults` per test, emptied before and after.
    private static func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "me.badia.altillo.tests.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test func defaultsAreTheOnesWeShip() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        #expect(settings.openWidth == 560)
        #expect(settings.modules == AltilloSettings.defaultModules)
        #expect(settings.opensOnHover)
        #expect(settings.showHintOnEmptyShelf)
        #expect(settings.shelfExpiry == .never)
        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginProblem == nil)
    }

    @Test func widthIsClampedToTheAllowedRange() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.openWidth = 10_000
        #expect(settings.openWidth == AltilloSettings.widthRange.upperBound)
        settings.openWidth = 0
        #expect(settings.openWidth == AltilloSettings.widthRange.lowerBound)
        settings.openWidth = 600
        #expect(settings.openWidth == 600)
    }

    @Test func storedWidthOutsideTheRangeIsClampedOnLaunch() {
        let defaults = Self.makeDefaults()
        defaults.set(2_000, forKey: "openWidth")
        #expect(AltilloSettings(defaults: defaults).openWidth == AltilloSettings.widthRange.upperBound)
    }

    @Test func everyPresetFitsTheSlider() {
        for preset in AltilloSettings.widthPresets {
            #expect(AltilloSettings.widthRange.contains(preset.value))
        }
    }

    @Test func modulesAreEnabledAndDisabled() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        #expect(settings.isEnabled(.calendar), "every section is on by default")
        settings.setEnabled(.calendar, false)
        #expect(!settings.isEnabled(.calendar))
        settings.setEnabled(.calendar, true)
        #expect(settings.isEnabled(.calendar))
        #expect(settings.modules.last == .calendar)

        settings.setEnabled(.calendar, true)  // idempotent: never twice in the list
        #expect(settings.modules.filter { $0 == .calendar }.count == 1)

        settings.setEnabled(.usage, false)
        #expect(!settings.isEnabled(.usage))
    }

    @Test func theShelfCanNeverBeTurnedOff() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.setEnabled(.shelf, false)
        #expect(settings.isEnabled(.shelf))
        #expect(settings.modules.first == .shelf)
    }

    @Test func reorderingKeepsTheShelfFirst() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.modules = [.shelf, .usage, .agents]
        // Drag "agents" to the very top: it can only land behind the shelf.
        settings.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(settings.modules == [.shelf, .agents, .usage])

        // And the shelf itself can't be dragged away from the front.
        settings.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(settings.modules.first == .shelf)
    }

    @Test func settingsSurviveARelaunch() {
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        settings.openWidth = 680
        settings.modules = [.shelf, .nowPlaying, .calendar]
        settings.opensOnHover = false
        settings.showHintOnEmptyShelf = false
        settings.shelfExpiry = .week
        settings.launchAtLogin = true

        let relaunched = AltilloSettings(defaults: defaults)
        #expect(relaunched.openWidth == 680)
        #expect(relaunched.modules == [.shelf, .nowPlaying, .calendar])
        #expect(!relaunched.opensOnHover)
        #expect(!relaunched.showHintOnEmptyShelf)
        #expect(relaunched.shelfExpiry == .week)
        #expect(relaunched.launchAtLogin)
    }

    @Test func rubbishOnDiskFallsBackToTheDefaults() {
        let defaults = Self.makeDefaults()
        defaults.set(["shelf", "unicornio", "drawer", "usage", "usage"], forKey: "modules")
        defaults.set("cada martes", forKey: "shelfExpiry")

        let settings = AltilloSettings(defaults: defaults)
        // A list from before `knownModules` existed: Ask is new to this user, so it arrives switched on.
        #expect(settings.modules == [.shelf, .assistant, .usage])
        #expect(settings.shelfExpiry == .never)
    }

    @Test func aFailingLoginItemRevertsTheToggleAndExplainsItself() {
        struct Failure: Error {}
        let settings = AltilloSettings(
            defaults: Self.makeDefaults(),
            loginItem: LoginItem(isManaged: true, isRegistered: { false }, setRegistered: { _ in throw Failure() })
        )
        settings.launchAtLogin = true
        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginProblem != nil)
    }

    @Test func theSystemIsTheTruthAboutOpeningAtLogin() {
        let defaults = Self.makeDefaults()
        defaults.set(false, forKey: "launchAtLogin")
        let settings = AltilloSettings(
            defaults: defaults,
            loginItem: LoginItem(isManaged: true, isRegistered: { true }, setRegistered: { _ in })
        )
        // The user switched it on in System Settings while Altillo was closed.
        #expect(settings.launchAtLogin)
        #expect(settings.launchAtLoginProblem == nil)
    }

    @Test func refreshingLoginStatusMirrorsBothDirectionsWithoutWritingBack() {
        final class State: @unchecked Sendable {
            var registered = false
            var writes: [Bool] = []
        }
        let state = State()
        let settings = AltilloSettings(
            defaults: Self.makeDefaults(),
            loginItem: LoginItem(
                isManaged: true,
                isRegistered: { state.registered },
                setRegistered: { state.writes.append($0) }
            )
        )

        state.registered = true
        settings.refreshLaunchAtLogin()
        #expect(settings.launchAtLogin)
        state.registered = false
        settings.refreshLaunchAtLogin()
        #expect(!settings.launchAtLogin)
        #expect(state.writes.isEmpty)
    }

    @Test func shelfExpiryKnowsHowLongThingsLast() {
        let day: TimeInterval = 24 * 60 * 60
        #expect(ShelfExpiry.never.duration == nil)
        #expect(ShelfExpiry.day.duration == day)
        #expect(ShelfExpiry.week.duration == 7 * day)
        #expect(ShelfExpiry.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test func everyModuleExplainsItselfInSettings() {
        for module in NotchModule.allCases {
            #expect(!module.title.isEmpty)
            #expect(!module.explanation.isEmpty)
            #expect(!module.symbol.isEmpty)
        }
    }

    @Test func settingsTabsAreAllNamed() {
        #expect(SettingsTab.allCases.count == 5)
        #expect(SettingsTab.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    }
}
