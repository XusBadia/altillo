import Foundation
import Testing
@testable import Altillo

/// Edit mode's rules (PLAN §4): the shelf stays first, sections go into the box and come back, ears swap instead of
/// repeating, presets apply and undo, and a whole drag is a single undo step.
@MainActor
struct EditModeTests {
    private static func makeSettings(_ name: String = #function) -> AltilloSettings {
        let suite = "me.badia.altillo.tests.edit.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return AltilloSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    // MARK: - Reordering

    @Test func sectionsMoveButNeverPastTheShelf() {
        let settings = Self.makeSettings()
        settings.modules = [.shelf, .assistant, .usage, .calendar]
        let session = NotchEditSession()
        #expect(session.move(.calendar, to: 0, in: settings), "asking for first place lands right after the shelf")
        #expect(settings.modules == [.shelf, .calendar, .assistant, .usage])
        #expect(!session.move(.calendar, by: -1, in: settings))
        #expect(settings.modules.first == .shelf)
    }

    @Test func theShelfItselfNeverMoves() {
        let settings = Self.makeSettings()
        settings.modules = [.shelf, .assistant, .usage]
        let session = NotchEditSession()
        #expect(!session.move(.shelf, by: 1, in: settings))
        #expect(!session.canMove(.shelf, by: 1, in: settings))
        #expect(!session.canMove(.assistant, by: -1, in: settings), "the shelf's place is taken")
        #expect(session.canMove(.assistant, by: 1, in: settings))
        #expect(!session.canMove(.usage, by: 1, in: settings), "already last")
        #expect(settings.modules == [.shelf, .assistant, .usage])
    }

    @Test func movingRightAndPastTheEndClamps() {
        let settings = Self.makeSettings()
        settings.modules = [.shelf, .assistant, .usage, .calendar]
        let session = NotchEditSession()
        #expect(session.move(.assistant, by: 1, in: settings))
        #expect(settings.modules == [.shelf, .usage, .assistant, .calendar])
        #expect(session.move(.usage, to: 99, in: settings))
        #expect(settings.modules == [.shelf, .assistant, .calendar, .usage])
    }

    // MARK: - Put away and add back

    @Test func sectionsGoIntoTheBoxAndComeBackAtTheEnd() {
        let settings = Self.makeSettings()
        settings.modules = [.shelf, .assistant, .usage, .calendar]
        let session = NotchEditSession()
        #expect(session.putAway(.assistant, in: settings))
        #expect(settings.modules == [.shelf, .usage, .calendar])
        #expect(!session.putAway(.assistant, in: settings), "already away")
        #expect(session.addBack(.assistant, in: settings))
        #expect(settings.modules == [.shelf, .usage, .calendar, .assistant])
        #expect(!session.addBack(.assistant, in: settings), "already there")
    }

    @Test func aSectionCanComeBackAtAPlaceButNeverBeforeTheShelf() {
        let settings = Self.makeSettings()
        settings.modules = [.shelf, .usage]
        let session = NotchEditSession()
        #expect(session.addBack(.mirror, at: 0, in: settings))
        #expect(settings.modules == [.shelf, .mirror, .usage])
    }

    @Test func theShelfCanNeverBePutAway() {
        let settings = Self.makeSettings()
        let session = NotchEditSession()
        #expect(!session.putAway(.shelf, in: settings))
        #expect(settings.modules.first == .shelf)
        #expect(!session.canUndo, "nothing happened, so nothing to undo")
    }

    // MARK: - Ears

    @Test func aChipFillsAnEarAndTheSameThingMovesRatherThanShowingTwice() {
        let settings = Self.makeSettings()
        settings.leftEar = .none
        settings.rightEar = .shelf
        let session = NotchEditSession()
        #expect(session.assign(.nextEvent, to: .left, in: settings))
        #expect(settings.leftEar == .nextEvent && settings.rightEar == .shelf)
        // The shelf goes left: the ears swap.
        #expect(session.assign(.shelf, to: .left, in: settings))
        #expect(settings.leftEar == .shelf && settings.rightEar == .nextEvent)
        #expect(session.selectedEar == .left, "the ear just filled stays selected")
    }

    @Test func comingSoonEarsAreRefused() {
        let settings = Self.makeSettings()
        let session = NotchEditSession()
        #expect(!session.assign(.usage, to: .left, in: settings))
        #expect(!session.assign(.agents, to: .right, in: settings))
        #expect(settings.leftEar == .none && settings.rightEar == .shelf)
    }

    @Test func aTabDroppedOnAnEarShowsWhatItMeans() {
        #expect(NotchEditSession.earContent(for: .calendar) == .nextEvent)
        #expect(NotchEditSession.earContent(for: .nowPlaying) == .nowPlaying)
        #expect(NotchEditSession.earContent(for: .shelf) == .shelf)
        #expect(NotchEditSession.earContent(for: .mirror) == nil)
    }

    @Test func aNewVisitPointsTheChipsAtTheEmptyEar() {
        let settings = Self.makeSettings()
        settings.leftEar = .none
        settings.rightEar = .shelf
        let session = NotchEditSession()
        session.begin(with: settings)
        #expect(session.selectedEar == .left)
        settings.leftEar = .nextEvent
        session.begin(with: settings)
        #expect(session.selectedEar == .right)
    }

    // MARK: - Presets and undo

    @Test func aPresetAppliesAndUndoBringsBackWhatWasThere() {
        let settings = Self.makeSettings()
        settings.modules = [.shelf, .calendar, .mirror]
        settings.leftEar = .nowPlaying
        settings.rightEar = .shelf
        let before = NotchEditSession.Snapshot(settings)
        let session = NotchEditSession()
        #expect(session.apply(.minimal, in: settings))
        #expect(settings.matchingPreset == .minimal)
        #expect(session.justApplied == .minimal)
        #expect(!session.apply(.minimal, in: settings), "already there: no second undo step")
        #expect(session.undo(in: settings))
        #expect(NotchEditSession.Snapshot(settings) == before)
        #expect(session.justApplied == nil)
        #expect(!session.canUndo)
    }

    @Test func undoWalksBackEveryChangeInOrder() {
        let settings = Self.makeSettings()
        settings.modules = [.shelf, .assistant, .usage]
        let session = NotchEditSession()
        session.putAway(.assistant, in: settings)
        session.setVisibility(.always, in: settings)
        session.assign(.nowPlaying, to: .left, in: settings)
        #expect(session.undoStack.count == 3)
        session.undo(in: settings)
        #expect(settings.leftEar == .none)
        session.undo(in: settings)
        #expect(settings.earsVisibility == .withActivity)
        session.undo(in: settings)
        #expect(settings.modules == [.shelf, .assistant, .usage])
        #expect(!session.undo(in: settings))
    }

    @Test func aWholeDragIsOneUndoStep() {
        let settings = Self.makeSettings()
        settings.modules = [.shelf, .assistant, .usage, .calendar]
        let session = NotchEditSession()
        session.beginGesture(in: settings)
        session.move(.assistant, by: 1, in: settings)
        session.move(.assistant, by: 1, in: settings)
        session.endGesture(in: settings)
        #expect(settings.modules == [.shelf, .usage, .calendar, .assistant])
        #expect(session.undoStack.count == 1)
        session.undo(in: settings)
        #expect(settings.modules == [.shelf, .assistant, .usage, .calendar])
    }

    @Test func aDragThatEndsWhereItStartedLeavesNothingToUndo() {
        let settings = Self.makeSettings()
        settings.modules = [.shelf, .assistant, .usage]
        let session = NotchEditSession()
        session.beginGesture(in: settings)
        session.move(.assistant, by: 1, in: settings)
        session.move(.assistant, by: -1, in: settings)
        session.endGesture(in: settings)
        #expect(!session.canUndo)
    }

    @Test func aNewVisitStartsWithNothingToUndo() {
        let settings = Self.makeSettings()
        let session = NotchEditSession()
        session.apply(.developer, in: settings)
        session.begin(with: settings)
        #expect(!session.canUndo)
        #expect(session.justApplied == nil)
    }

    // MARK: - Drop targets

    @Test func dropsFindTheEarsGenerouslyAndTheBoxExactly() {
        let session = NotchEditSession()
        session.targetFrames = [
            .ear(.left): CGRect(x: 100, y: 4, width: 44, height: 24),
            .ear(.right): CGRect(x: 330, y: 4, width: 44, height: 24),
            .tray: CGRect(x: 80, y: 90, width: 300, height: 26),
        ]
        #expect(session.target(at: CGPoint(x: 95, y: 30)) == .ear(.left), "a few points off still counts")
        #expect(session.target(at: CGPoint(x: 350, y: 10)) == .ear(.right))
        #expect(session.target(at: CGPoint(x: 200, y: 100)) == .tray)
        #expect(session.target(at: CGPoint(x: 200, y: 60)) == nil)
    }
}
