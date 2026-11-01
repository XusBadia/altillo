import AltilloCore
import AltilloMail
import Foundation
import Testing
@testable import Altillo

@MainActor
struct MailAlertRetentionTests {
    private func alert(_ source: NotchAlert.Source = .mail) -> NotchAlert {
        NotchAlert(source: source, symbol: "envelope", title: "Private subject", detail: "Private sender")
    }

    @Test func revocationDropsCopiedMailEvenWhenOrdinaryExpiryWouldKeepTheHoveredPeek() {
        var machine = NotchStateMachine(state: .peek)
        machine.handle(.hoverIntent)
        machine.handle(.alertExpired)
        #expect(machine.state == .peek)
        var visible: NotchAlert? = alert()
        var tracked: String? = "visible@example.invalid"
        let shouldClose = MailAlertRetention.revoke(alert: &visible, trackedMessageID: &tracked,
                                                    revokedMessageID: "visible@example.invalid")
        #expect(shouldClose && visible == nil && tracked == nil)
        if shouldClose { machine = NotchStateMachine() }
        #expect(machine.state == .idle)
    }

    @Test func revokingAnotherMessageDoesNotRemoveTheVisibleMailAlert() {
        var visible: NotchAlert? = alert()
        let originalID = visible?.id
        var tracked: String? = "visible@example.invalid"
        #expect(!MailAlertRetention.revoke(alert: &visible, trackedMessageID: &tracked,
                                           revokedMessageID: "older@example.invalid"))
        #expect(visible?.id == originalID && tracked == "visible@example.invalid")
    }

    @Test func privacyResetNeverDismissesAnotherSourceThatReplacedMail() {
        var visible: NotchAlert? = alert(.agents)
        let originalID = visible?.id
        var tracked: String? = "old-mail@example.invalid"
        #expect(!MailAlertRetention.revoke(alert: &visible, trackedMessageID: &tracked, revokedMessageID: nil))
        #expect(visible?.id == originalID && tracked == nil)
    }

    @Test func clearingRevokesAnUntrackedCopiedMailAlertToo() {
        var visible: NotchAlert? = alert()
        var tracked: String?
        #expect(MailAlertRetention.revoke(alert: &visible, trackedMessageID: &tracked, revokedMessageID: nil))
        #expect(visible == nil)
    }

    @Test func storeRevokesPresentationsForDismissExpiryFiltersAndPrivacyReset() {
        var moment = Date(timeIntervalSince1970: 2_000_000_000)
        let store = MailStore(startsServer: false)
        store.now = { moment }
        store.sleep = { _ in try await Task.sleep(for: .seconds(86_400)) }
        var revocations: [String?] = []
        store.onRevocation = { revocations.append($0) }
        store.update(enabled: true)
        func message(_ id: String, sender: String = "a@example.invalid") -> MailEnvelope {
            MailEnvelope(messageID: id, sender: sender, subject: "Private", body: "", receivedAt: moment.timeIntervalSince1970)
        }
        let dismissed = message("dismiss@example.invalid")
        store.ingest(dismissed)
        store.dismiss(dismissed)
        #expect(revocations == [dismissed.messageID])
        store.ingest(message("expire@example.invalid"))
        moment.addTimeInterval(300)
        store.expire()
        #expect(revocations.last == "expire@example.invalid")
        store.ingest(message("filter@example.invalid"))
        store.configure(senders: "other@example.invalid", accounts: "")
        #expect(revocations.last == "filter@example.invalid")
        store.clear()
        #expect(revocations.count == 4 && revocations[3] == nil)
        store.setSuspended(true)
        #expect(revocations.count == 5 && revocations[4] == nil)
        store.stop()
    }
}
