import Foundation
import Testing
@testable import Altillo

@MainActor
struct KeepAwakeTests {
    private final class Token: NSObject {}

    private final class Backend: KeepAwakeActivityBackend {
        private(set) var begins = 0
        private(set) var ends = 0
        private(set) var active = Set<ObjectIdentifier>()

        func begin(reason: String) -> NSObjectProtocol {
            begins += 1
            let token = Token()
            active.insert(ObjectIdentifier(token))
            return token
        }

        func end(_ token: NSObjectProtocol) {
            ends += 1
            active.remove(ObjectIdentifier(token as AnyObject))
        }
    }

    private final class Clock {
        var value = Date(timeIntervalSince1970: 2_000_000_000)
        func advance(_ seconds: TimeInterval) { value.addTimeInterval(seconds) }
    }

    private func makeStore() -> (KeepAwakeStore, Backend, Clock) {
        let backend = Backend()
        let clock = Clock()
        let store = KeepAwakeStore(backend: backend)
        store.now = { clock.value }
        // Tests drive boundaries through `wake`; no task waits on wall time.
        store.sleep = { _ in try await Task.sleep(for: .seconds(86_400)) }
        return (store, backend, clock)
    }

    @Test func sectionIsOptInOnAFreshInstall() {
        let name = "me.badia.altillo.tests.keep-awake-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AltilloSettings(defaults: defaults)
        #expect(NotchModule.keepAwake.isOptIn)
        #expect(!settings.isEnabled(.keepAwake))
    }

    @Test func startsExactlyOneAssertionAndStopBalancesIt() {
        let (store, backend, _) = makeStore()
        store.start()
        #expect(!store.isActive, "lifecycle start must never opt the user in")
        store.begin(.thirtyMinutes)
        #expect(store.isActive)
        #expect(backend.begins == 1 && backend.ends == 0 && backend.active.count == 1)
        store.end()
        store.end()
        #expect(!store.isActive)
        #expect(backend.begins == 1 && backend.ends == 1 && backend.active.isEmpty)
        store.stop()
    }

    @Test func beginningAgainRetimesWithoutStackingAssertions() {
        let (store, backend, clock) = makeStore()
        store.begin(.thirtyMinutes)
        let firstEnd = store.endsAt
        clock.advance(10)
        store.begin(.twoHours)
        #expect(backend.begins == 1 && backend.ends == 0)
        #expect(store.duration == .twoHours)
        #expect(store.endsAt == clock.value.addingTimeInterval(7_200))
        #expect(store.endsAt != firstEnd)
        store.end()
    }

    @Test func expiryReleasesTheAssertion() {
        let (store, backend, clock) = makeStore()
        store.begin(.oneHour)
        clock.advance(3_599)
        store.wake()
        #expect(store.isActive && backend.ends == 0)
        clock.advance(1)
        store.wake()
        #expect(!store.isActive)
        #expect(backend.ends == 1 && backend.active.isEmpty)
    }

    @Test func indefiniteSessionHasNoDeadlineButStillStops() {
        let (store, backend, clock) = makeStore()
        store.begin(.untilStopped)
        #expect(store.endsAt == nil && store.isActive)
        clock.advance(365 * 24 * 60 * 60)
        store.wake()
        #expect(store.isActive && backend.ends == 0)
        store.stop()
        #expect(!store.isActive && backend.ends == 1)
    }

    @Test func lifecycleStopAndModuleDisableReleaseExactlyOnce() {
        let (store, backend, _) = makeStore()
        store.start()
        store.begin(.twoHours)
        store.setModuleEnabled(false)
        store.stop() // normal app termination may follow
        #expect(backend.begins == 1 && backend.ends == 1 && backend.active.isEmpty)
    }

    @Test func aFreshStoreNeverRestoresThePreviousSession() {
        let backend = Backend()
        let first = KeepAwakeStore(backend: backend)
        first.begin(.untilStopped)
        first.stop()
        let relaunched = KeepAwakeStore(backend: backend)
        relaunched.start()
        #expect(!relaunched.isActive && relaunched.duration == nil && relaunched.endsAt == nil)
        #expect(backend.begins == 1 && backend.ends == 1)
        relaunched.stop()
    }
}
