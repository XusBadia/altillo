import AltilloMail
import Foundation
import Testing
@testable import Altillo

@MainActor
struct MailStoreTests {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 2_000_000_000)
    }

    private func makeStore() -> (MailStore, Clock) {
        let clock = Clock()
        let store = MailStore(startsServer: false)
        store.now = { clock.date }
        store.sleep = { _ in try await Task.sleep(for: .seconds(86_400)) }
        return (store, clock)
    }

    private func envelope(_ id: String = "fixture@example.invalid", at date: Date,
                          sender: String = "Fixture <fixture@example.invalid>", account: String = "Work") -> MailEnvelope {
        MailEnvelope(version: 1, messageID: id, sender: sender, subject: "Verification code",
                     body: "Your verification code is 482913", account: account, receivedAt: date.timeIntervalSince1970)
    }

    @Test func disabledStoreNeverCollectsAndEnablingDoesNotReplayHistory() {
        let (store, clock) = makeStore()
        store.ingest(envelope(at: clock.date))
        #expect(store.messages.isEmpty)
        store.update(enabled: true)
        store.ingest(envelope("old@example.invalid", at: clock.date.addingTimeInterval(-1)))
        #expect(store.messages.isEmpty)
        store.ingest(envelope(at: clock.date))
        #expect(store.messages.count == 1)
        store.stop()
    }

    @Test func newMessagesNotifyOnceAndAreBoundedToTwenty() {
        let (store, clock) = makeStore()
        var received = 0
        store.onMessage = { _ in received += 1 }
        store.update(enabled: true)
        for index in 0..<25 { store.ingest(envelope("\(index)@example.invalid", at: clock.date)) }
        store.ingest(envelope("24@example.invalid", at: clock.date))
        #expect(store.messages.count == 20)
        #expect(received == 25)
        #expect(store.messages.first?.messageID == "24@example.invalid")
        store.stop()
    }

    @Test func expiryClearAndDisablePurgeStoredPayloads() {
        let (store, clock) = makeStore()
        store.update(enabled: true)
        store.ingest(envelope(at: clock.date))
        clock.date.addTimeInterval(300)
        store.expire()
        #expect(store.messages.isEmpty)
        store.ingest(envelope("next@example.invalid", at: clock.date))
        store.clear()
        #expect(store.messages.isEmpty && store.lastReceivedAt == nil)
        store.ingest(envelope("new@example.invalid", at: clock.date))
        store.update(enabled: false)
        #expect(!store.enabled && store.messages.isEmpty)
    }

    @Test func dismissalInvalidatesActionsAndDoesNotAffectOtherMessages() {
        let (store, clock) = makeStore()
        store.update(enabled: true)
        let first = envelope(at: clock.date)
        let other = envelope("other@example.invalid", at: clock.date)
        store.ingest(first)
        store.ingest(other)
        store.dismiss(first)
        #expect(store.messages.map(\.messageID) == [other.messageID])
        #expect(!store.copyCode(for: first))
        #expect(!store.openLink(for: first))
        #expect(!store.openMessage(for: first))
        store.stop()
    }

    @Test func suspensionDoesNotCollectWhileLockedOrReplayOnResume() {
        let (store, clock) = makeStore()
        store.update(enabled: true)
        store.ingest(envelope(at: clock.date))
        store.setSuspended(true)
        #expect(store.messages.isEmpty)
        store.ingest(envelope("locked@example.invalid", at: clock.date))
        #expect(store.messages.isEmpty)
        clock.date.addTimeInterval(10)
        store.setSuspended(false)
        store.ingest(envelope("locked@example.invalid", at: clock.date.addingTimeInterval(-1)))
        #expect(store.messages.isEmpty)
        store.ingest(envelope("unlocked@example.invalid", at: clock.date))
        #expect(store.messages.count == 1)
        store.stop()
    }

    @Test func senderAndAccountFiltersAreExactAndCanBeChangedWithoutKeepingHiddenMessages() {
        let (store, clock) = makeStore()
        store.configure(senders: "@example.invalid", accounts: "work")
        store.update(enabled: true)
        store.ingest(envelope(at: clock.date))
        store.ingest(envelope("other@example.invalid", at: clock.date, sender: "evil@notexample.invalid"))
        store.ingest(envelope("personal@example.invalid", at: clock.date, account: "Personal"))
        #expect(store.messages.count == 1)
        store.configure(senders: "someone@else.invalid", accounts: "")
        #expect(store.messages.isEmpty)
        store.stop()
    }

    @Test func senderDomainMatchingDoesNotAcceptSubstrings() {
        #expect(MailFilters.matchesSender("Name <user@example.com>", allowed: ["@example.com"]))
        #expect(!MailFilters.matchesSender("user@notexample.com", allowed: ["@example.com"]))
        #expect(!MailFilters.matchesSender("user@example.com.evil", allowed: ["@example.com"]))
        #expect(MailFilters.matchesSender("Name <user@example.com>", allowed: ["user@example.com"]))
        #expect(MailFilters.tokens(" A@B.COM, a@b.com\n @Example.com ") == ["@example.com", "a@b.com"])
    }
}
