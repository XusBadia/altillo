import Testing
@testable import AltilloCore

struct NotchStateMachineTests {
    @Test func hoverPeeksThenOpens() {
        var machine = NotchStateMachine()
        machine.handle(.hoverIntent)
        #expect(machine.state == .peek)
        machine.handle(.hoverSustained)
        #expect(machine.state == .open)
    }

    @Test func hoverOnlyPeeksWhenOpeningRequiresClick() {
        var machine = NotchStateMachine(opensOnHover: false)
        machine.handle(.hoverIntent)
        machine.handle(.hoverSustained)
        #expect(machine.state == .peek)
        machine.handle(.click)
        #expect(machine.state == .open)
    }

    @Test func leavingPeekClosesImmediately() {
        var machine = NotchStateMachine()
        machine.handle(.hoverIntent)
        machine.handle(.pointerLeft)
        #expect(machine.state == .idle)
    }

    @Test func openClosesOnlyAfterGracePeriodOutside() {
        var machine = NotchStateMachine()
        machine.handle(.click)
        machine.handle(.pointerLeft)
        #expect(machine.state == .open)
        machine.handle(.closeGraceElapsed)
        #expect(machine.state == .idle)
    }

    @Test func returningDuringGracePeriodKeepsItOpen() {
        var machine = NotchStateMachine()
        machine.handle(.click)
        machine.handle(.pointerLeft)
        machine.handle(.hoverIntent)
        machine.handle(.closeGraceElapsed)
        #expect(machine.state == .open)
    }

    @Test func dragFlowEndsOpenAfterDrop() {
        var machine = NotchStateMachine()
        machine.handle(.dragBegan)
        #expect(machine.state == .dragArmed)
        machine.handle(.dragMoved(near: true))
        #expect(machine.state == .dropTarget)
        machine.handle(.dragMoved(near: false))
        #expect(machine.state == .dragArmed)
        machine.handle(.dragMoved(near: true))
        machine.handle(.dragEnded(dropped: true))
        #expect(machine.state == .open)
    }

    @Test func dragDroppedElsewhereReturnsToIdle() {
        var machine = NotchStateMachine()
        machine.handle(.dragBegan)
        machine.handle(.dragMoved(near: true))
        machine.handle(.dragEnded(dropped: false))
        #expect(machine.state == .idle)
    }

    @Test func alertPeekExpiresUnlessHovered() {
        var machine = NotchStateMachine()
        machine.handle(.alert)
        #expect(machine.state == .peek)
        machine.handle(.alertExpired)
        #expect(machine.state == .idle)

        machine.handle(.alert)
        machine.handle(.hoverIntent)
        machine.handle(.alertExpired)
        #expect(machine.state == .peek)
    }

    @Test func escapeAlwaysCloses() {
        for start in NotchState.allCases {
            var machine = NotchStateMachine(state: start)
            machine.handle(.escape)
            #expect(machine.state == .idle)
        }
    }
}
