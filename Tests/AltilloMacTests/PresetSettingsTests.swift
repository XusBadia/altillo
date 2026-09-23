import Foundation
import Testing
@testable import Altillo

/// Phase 2: presets, ears and screens — defaults that stay out of the way and survive a relaunch.
@MainActor
struct PresetSettingsTests {
    private static func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "me.badia.altillo.tests.presets.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test func newSettingsDefaultToAQuietNotch() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        #expect(settings.displayMode == .notch)
        #expect(settings.fullScreenBehaviour == .dragOnly)
        #expect(settings.leftEar == .none)
        #expect(settings.rightEar == .shelf, "the shelf count is what the ears showed before phase 2")
        #expect(settings.earsVisibility == .withActivity)
    }

    @Test func screensAndEarsSurviveARelaunch() {
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        settings.displayMode = .all
        settings.fullScreenBehaviour = .hide
        settings.leftEar = .nextEvent
        settings.rightEar = .nowPlaying
        settings.earsVisibility = .always

        let relaunched = AltilloSettings(defaults: defaults)
        #expect(relaunched.displayMode == .all)
        #expect(relaunched.fullScreenBehaviour == .hide)
        #expect(relaunched.leftEar == .nextEvent)
        #expect(relaunched.rightEar == .nowPlaying)
        #expect(relaunched.earsVisibility == .always)
    }

    @Test func aPresetSetsSectionsAndEarsOnly() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.openWidth = 680
        settings.apply(.minimal)
        #expect(settings.modules == [.shelf])
        #expect(settings.leftEar == .none && settings.rightEar == .shelf)
        #expect(settings.openWidth == 680, "a preset never touches size or behaviour")
        #expect(settings.matchingPreset == .minimal)

        settings.apply(.developer)
        #expect(settings.modules == [.shelf, .assistant, .usage, .agents])
        #expect(settings.matchingPreset == .developer)

        settings.setEnabled(.calendar, true)
        #expect(settings.matchingPreset == nil, "adjusting after a preset leaves it")
    }

    @Test func everyPresetKeepsTheShelfFirstAndExplainsItself() {
        for preset in NotchPreset.allCases {
            #expect(preset.modules.first == .shelf)
            #expect(!preset.title.isEmpty && !preset.explanation.isEmpty)
        }
        #expect(NotchPreset.everything.modules == NotchModule.allCases)
    }

    @Test func earsThatArentReadyYetAreMarked() {
        #expect(!EarContent.usage.isAvailable)
        #expect(!EarContent.agents.isAvailable)
        #expect(EarContent.allCases.filter(\.isAvailable) == [.none, .shelf, .nextEvent, .nowPlaying])
    }
}
