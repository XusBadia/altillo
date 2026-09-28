import EventKit
import Foundation
import Testing
@testable import Altillo

@MainActor
struct RemindersTests {
    private actor Source: RemindersDataSource {
        var items: [RemindersStore.Item]
        var requests = 0
        var completed: [String] = []

        init(items: [RemindersStore.Item] = []) { self.items = items }

        func requestAccess() -> Bool {
            requests += 1
            return true
        }

        func incomplete() -> [RemindersStore.Item] { items }

        func complete(identifier: String) {
            completed.append(identifier)
            items.removeAll { $0.id == identifier }
        }

        func counts() -> (Int, [String]) { (requests, completed) }
    }

    private let madrid: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 9) -> Date {
        madrid.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    @Test func sectionIsOptIn() {
        #expect(NotchModule.reminders.isOptIn)
        #expect(!NotchModule.reminders.isAlwaysOn)
    }

    @Test func groupsOverdueAndTodayApartFromFutureAndUndated() {
        let items = [
            RemindersStore.Item(id: "future", title: "Future", due: date(29), listName: "Home"),
            RemindersStore.Item(id: "none", title: "Someday", due: nil, listName: "Home"),
            RemindersStore.Item(id: "today", title: "Today", due: date(28, 18), listName: "Work"),
            RemindersStore.Item(id: "overdue", title: "Overdue", due: date(27), listName: "Work"),
        ]
        let groups = RemindersGrouping.split(items, now: date(28, 12), calendar: madrid)
        #expect(groups.today.map(\.id) == ["overdue", "today"])
        #expect(groups.upcoming.map(\.id) == ["future", "none"])
    }

    @Test func openingWithoutPermissionDoesNotAsk() async {
        let source = Source()
        let store = RemindersStore(source: source, calendar: madrid, authorizationStatus: { .notDetermined })
        store.start()
        await Task.yield()
        #expect(store.access == .unknown)
        let counts = await source.counts()
        #expect(counts.0 == 0)
        store.stop()
    }

    @Test func explicitAccessLoadsAndCompletionUpdatesImmediately() async throws {
        let item = RemindersStore.Item(id: "one", title: "Pay rent", due: date(28, 18), listName: "Home")
        let source = Source(items: [item])
        let store = RemindersStore(source: source, calendar: madrid, authorizationStatus: { .notDetermined })
        store.start()
        await store.requestAccess()
        for _ in 0..<20 {
            if store.hasLoaded { break }
            await Task.yield()
        }
        #expect(store.today == [item])
        var counts = await source.counts()
        #expect(counts.0 == 1)

        store.complete(item)
        #expect(store.today.isEmpty)
        for _ in 0..<20 {
            counts = await source.counts()
            if !counts.1.isEmpty { break }
            await Task.yield()
        }
        #expect(counts.1 == ["one"])
        store.stop()
    }
}
