import AppKit
import EventKit
import Foundation
import Observation

/// The small slice of Reminders that belongs in the notch: incomplete items for today and what comes after.
/// Creation deliberately stays in Ask; this store only reads, completes and opens the native app.
@MainActor
@Observable
final class RemindersStore {
    struct Item: Identifiable, Hashable, Sendable {
        let id: String
        var title: String
        var due: Date?
        var dueHasTime = false
        var listName: String
    }

    enum Access: Equatable, Sendable { case unknown, granted, denied }

    private(set) var access: Access
    private(set) var today: [Item] = []
    private(set) var upcoming: [Item] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var problem: String?

    @ObservationIgnored private let source: any RemindersDataSource
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let authorizationStatus: @Sendable () -> EKAuthorizationStatus
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var generation = 0

    init(source: any RemindersDataSource = EventKitRemindersSource(), calendar: Calendar = .autoupdatingCurrent,
         authorizationStatus: @escaping @Sendable () -> EKAuthorizationStatus = {
             EKEventStore.authorizationStatus(for: .reminder)
         }) {
        self.source = source
        self.calendar = calendar
        self.authorizationStatus = authorizationStatus
        access = Self.access(for: authorizationStatus())
    }

    /// Starts listening only while the section is visible. Merely opening the section never asks for permission.
    func start() {
        viewers += 1
        guard viewers == 1 else { return }
        access = Self.access(for: authorizationStatus())
        guard access == .granted else { return }
        beginObserving()
        refresh()
    }

    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        generation += 1
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        isLoading = false
    }

    /// The only path that can display the Reminders permission sheet; called by the explicit button in the view.
    func requestAccess() async {
        let granted = await source.requestAccess()
        access = granted ? .granted : Self.access(for: authorizationStatus())
        guard access == .granted, viewers > 0 else { return }
        beginObserving()
        refresh()
    }

    func refresh() {
        guard viewers > 0, access == .granted else { return }
        generation += 1
        let requestedGeneration = generation
        isLoading = true
        problem = nil
        Task {
            do {
                let items = try await source.incomplete()
                guard requestedGeneration == generation, viewers > 0 else { return }
                let groups = RemindersGrouping.split(items, now: .now, calendar: calendar)
                today = groups.today
                upcoming = groups.upcoming
                hasLoaded = true
                isLoading = false
            } catch {
                guard requestedGeneration == generation, viewers > 0 else { return }
                problem = String(localized: "Reminders couldn't be loaded. Try again.")
                hasLoaded = true
                isLoading = false
            }
        }
    }

    func complete(_ item: Item) {
        // Remove at once; put it back by refreshing if EventKit rejects the save.
        today.removeAll { $0.id == item.id }
        upcoming.removeAll { $0.id == item.id }
        Task {
            do {
                try await source.complete(identifier: item.id)
            } catch {
                problem = String(localized: "That reminder couldn't be completed.")
                refresh()
            }
        }
    }

    func openReminders() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }

    private func beginObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    static func access(for status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess, .authorized: .granted
        case .notDetermined: .unknown
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }
}

struct ReminderGroups: Equatable, Sendable {
    var today: [RemindersStore.Item]
    var upcoming: [RemindersStore.Item]
}

enum RemindersGrouping {
    static func split(_ items: [RemindersStore.Item], now: Date, calendar: Calendar) -> ReminderGroups {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let sorted = items.sorted { lhs, rhs in
            switch (lhs.due, rhs.due) {
            case let (left?, right?) where left != right: left < right
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
        return ReminderGroups(
            today: sorted.filter { $0.due.map { $0 < tomorrow } ?? false },
            upcoming: sorted.filter { $0.due.map { $0 >= tomorrow } ?? true }
        )
    }
}

protocol RemindersDataSource: Sendable {
    func requestAccess() async -> Bool
    func incomplete() async throws -> [RemindersStore.Item]
    func complete(identifier: String) async throws
}

/// Keeps EventKit's non-Sendable objects inside one actor; only plain values cross back to the main actor.
actor EventKitRemindersSource: RemindersDataSource {
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    func incomplete() async throws -> [RemindersStore.Item] {
        store.reset()
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil
            )) { reminders in
                // Convert inside EventKit's callback: its non-Sendable objects never cross an isolation boundary.
                continuation.resume(returning: (reminders ?? []).map(Self.item(from:)))
            }
        }
    }

    func complete(identifier: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        reminder.isCompleted = true
        reminder.completionDate = .now
        try store.save(reminder, commit: true)
    }

    nonisolated private static func item(from reminder: EKReminder) -> RemindersStore.Item {
        let dueComponents = reminder.dueDateComponents
        return RemindersStore.Item(
            id: reminder.calendarItemIdentifier,
            title: reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? String(localized: "Untitled"),
            due: dueComponents.flatMap { Calendar.autoupdatingCurrent.date(from: $0) },
            dueHasTime: dueComponents?.hour != nil || dueComponents?.minute != nil,
            listName: reminder.calendar?.title ?? String(localized: "Reminders")
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
