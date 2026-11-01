import Foundation

public struct NativeMailSyncResult: Sendable {
    public let messages: [NativeMailSummary]
    public let arrivals: [NativeMailSummary]
    public let hasMore: Bool

    public init(messages: [NativeMailSummary], arrivals: [NativeMailSummary], hasMore: Bool) {
        self.messages = messages
        self.arrivals = arrivals
        self.hasMore = hasMore
    }
}

/// A process-local body budget shared by all accounts. Session epochs and message versions reject
/// late writes after disconnect, lock, deletion or an identifier being removed and later re-added.
public actor NativeMailBodyCache {
    private let limit: Int
    private var accountEpochs: [UUID: UInt64] = [:]
    private var windows: [UUID: [NativeMailMessageKey: UUID]] = [:]
    private var entries: [NativeMailMessageKey: Entry] = [:]
    private var bytes = 0
    private var counter: UInt64 = 0

    private struct Entry {
        let content: NativeMailContent
        let bytes: Int
        var access: UInt64
    }

    public init(limit: Int = 10 << 20) { self.limit = min(max(0, limit), 10 << 20) }

    fileprivate func epoch(for accountID: UUID) -> UInt64 { accountEpochs[accountID] ?? 0 }

    fileprivate func invalidate(accountID: UUID, expectedEpoch: UInt64?) -> UInt64 {
        let current = accountEpochs[accountID] ?? 0
        // A delayed older reset must not advance the epoch past a newer session's returned value.
        let next = expectedEpoch == current ? current &+ 1 : current
        accountEpochs[accountID] = next
        windows[accountID] = nil
        for key in Array(entries.keys) where key.accountID == accountID { remove(key) }
        return next
    }

    fileprivate func setWindow(accountID: UUID, epoch: UInt64, versions: [NativeMailMessageKey: UUID]) -> Bool {
        guard self.epoch(for: accountID) == epoch, versions.count <= 50,
              versions.keys.allSatisfy({ $0.accountID == accountID }) else { return false }
        let previous = windows[accountID] ?? [:]
        windows[accountID] = versions
        for key in Array(entries.keys) where key.accountID == accountID {
            if versions[key] == nil || previous[key] != versions[key] { remove(key) }
        }
        return true
    }

    fileprivate func value(for key: NativeMailMessageKey, epoch: UInt64, version: UUID) -> NativeMailContent? {
        guard valid(key, epoch: epoch, version: version), var entry = entries[key] else { return nil }
        counter &+= 1
        entry.access = counter
        entries[key] = entry
        return entry.content
    }

    /// false means a stale session or message, not simply that an entry exceeds this cache's budget.
    fileprivate func store(_ content: NativeMailContent, epoch: UInt64, version: UUID) -> Bool {
        guard valid(content.key, epoch: epoch, version: version) else { return false }
        let size = content.text.utf8.count
        guard size <= 1 << 20 else { return false }
        remove(content.key)
        guard size <= limit else { return true }
        counter &+= 1
        entries[content.key] = Entry(content: content, bytes: size, access: counter)
        bytes += size
        while bytes > limit, let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key { remove(oldest) }
        return true
    }

    private func valid(_ key: NativeMailMessageKey, epoch: UInt64, version: UUID) -> Bool {
        self.epoch(for: key.accountID) == epoch && windows[key.accountID]?[key] == version
    }

    private func remove(_ key: NativeMailMessageKey) {
        if let old = entries.removeValue(forKey: key) { bytes -= old.bytes }
    }
}

/// One account's bounded, in-memory Inbox. The initial list and cursor recovery establish a silent
/// baseline; an inbox item is not inherently a new-mail notification.
public actor NativeMailSynchronizer {
    private let provider: any NativeMailProvider
    private let now: @Sendable () -> Date
    private let bodyCache: NativeMailBodyCache
    private var sharedEpoch: UInt64?
    private var resetInProgress = false
    private var generation: UInt64 = 0
    private var contentGeneration: UInt64 = 0
    private var baselineDate: Date
    private var bootstrapping = true
    private var rows: [String: NativeMailSummary] = [:]
    private var cursor: String?
    private var nextPage: String?
    private var stagedCursor: String?
    private var snapshotRows: [String: NativeMailSummary]?
    private var visitedPages = Set<String>()
    private var seen: [String: Date] = [:]
    private var seenOrder: [String] = []
    // Under extreme traffic, suppress older arrivals rather than replaying identifiers evicted from
    // the bounded deduplication window. Inbox visibility is independent of this notification cutoff.
    private var notificationFloor = Date.distantPast
    private var syncFlight: SyncFlight?
    private var contentFlights: [NativeMailMessageKey: ContentFlight] = [:]
    private var contentVersions: [NativeMailMessageKey: UUID] = [:]

    private static let messageLimit = 50
    private static let seenLimit = 2_048
    private static let pageLimit = 4
    private static let contentLimit = 1 << 20

    private struct SyncFlight {
        let id: UUID
        let task: Task<NativeMailSyncResult, Error>
    }
    private struct ContentFlight {
        let id: UUID
        let task: Task<NativeMailContent, Error>
    }
    public init(provider: any NativeMailProvider, cache: NativeMailBodyCache = NativeMailBodyCache(),
                now: @escaping @Sendable () -> Date = Date.init) {
        self.provider = provider
        self.bodyCache = cache
        self.now = now
        baselineDate = now()
    }

    /// Concurrent refreshes join the same request, but only its original caller receives arrivals.
    /// Reset invalidates responses even when an underlying provider does not honor cancellation.
    public func synchronize() async throws -> NativeMailSyncResult {
        guard !resetInProgress else { throw CancellationError() }
        let expectedGeneration = generation
        if let flight = syncFlight {
            _ = try await flight.task.value
            try checkGeneration(expectedGeneration)
            return NativeMailSyncResult(messages: ordered(rows.values), arrivals: [], hasMore: nextPage != nil)
        }
        let id = UUID()
        let task = Task { try await self.performSynchronization(generation: expectedGeneration) }
        syncFlight = SyncFlight(id: id, task: task)
        defer { if syncFlight?.id == id { syncFlight = nil } }
        let result = try await task.value
        try checkGeneration(expectedGeneration)
        return result
    }

    public func fetchContent(for key: NativeMailMessageKey) async throws -> NativeMailContent {
        guard key.accountID == provider.account.id, rows[key.remoteID]?.key == key else {
            throw NativeMailFailure.messageMissing
        }
        guard !resetInProgress, let epoch = sharedEpoch, let version = contentVersions[key] else { throw CancellationError() }
        let expectedGeneration = contentGeneration
        let cached = await bodyCache.value(for: key, epoch: epoch, version: version)
        try checkContent(key, generation: expectedGeneration, version: version)
        if let cached { return cached }
        let flight: ContentFlight
        if let existing = contentFlights[key] {
            flight = existing
        } else {
            let provider = self.provider
            flight = ContentFlight(id: UUID(), task: Task { try await provider.fetchContent(for: key) })
            contentFlights[key] = flight
        }
        defer { if contentFlights[key]?.id == flight.id { contentFlights[key] = nil } }
        let result: NativeMailContent
        do { result = try await flight.task.value }
        catch { throw Self.publicFailure(error) }
        try checkContent(key, generation: expectedGeneration, version: version)
        guard result.key == key else { throw NativeMailFailure.invalidResponse }
        let size = result.text.utf8.count
        guard size <= Self.contentLimit else { throw NativeMailFailure.contentTooLarge }
        let stored = await bodyCache.store(result, epoch: epoch, version: version)
        try checkContent(key, generation: expectedGeneration, version: version)
        guard stored else { throw CancellationError() }
        return result
    }

    /// Call on disconnect, pause, lock, sleep, or a new unlocked session. No content is persisted.
    public func reset() async {
        generation &+= 1
        let current = generation
        resetInProgress = true
        let previousEpoch = sharedEpoch
        syncFlight?.task.cancel()
        syncFlight = nil
        beginBaseline()
        let epoch = await bodyCache.invalidate(accountID: provider.account.id, expectedEpoch: previousEpoch)
        if generation == current {
            sharedEpoch = epoch
            resetInProgress = false
        }
    }

    private func performSynchronization(generation expectedGeneration: UInt64) async throws -> NativeMailSyncResult {
        var arrivals: [String: NativeMailSummary] = [:]
        var recoveredCursor = false
        var pages = 0
        if sharedEpoch == nil {
            let value = await bodyCache.epoch(for: provider.account.id)
            try checkGeneration(expectedGeneration)
            sharedEpoch = value
        }
        while pages < Self.pageLimit {
            try checkGeneration(expectedGeneration)
            let requestedPage = nextPage
            let page: NativeMailPage
            do {
                if bootstrapping || cursor == nil {
                    page = try await provider.bootstrap(pageToken: requestedPage)
                } else {
                    page = try await provider.changes(cursor: cursor!, pageToken: requestedPage)
                }
            } catch NativeMailFailure.cursorExpired {
                try checkGeneration(expectedGeneration)
                guard !recoveredCursor else { throw NativeMailFailure.cursorExpired }
                recoveredCursor = true
                try await recoverBaseline(generation: expectedGeneration)
                arrivals.removeAll()
                continue
            } catch {
                try checkGeneration(expectedGeneration)
                throw Self.publicFailure(error)
            }
            try checkGeneration(expectedGeneration)
            try validate(page, requestedPage: requestedPage)
            if page.resetBaseline {
                try await recoverBaseline(generation: expectedGeneration)
                arrivals.removeAll()
            }
            let suppressArrivals = bootstrapping
            let moment = now()
            if page.isFullSnapshot, requestedPage == nil { snapshotRows = [:] }
            for id in page.removedIDs {
                rows[id] = nil
                snapshotRows?[id] = nil
                arrivals[id] = nil
                invalidateContent(for: NativeMailMessageKey(accountID: provider.account.id, remoteID: id))
            }
            for message in page.messages {
                let wasSeen = seen[message.key.remoteID] != nil
                let age = moment.timeIntervalSince(message.receivedAt)
                if !suppressArrivals, !wasSeen, message.receivedAt >= baselineDate,
                   message.receivedAt > notificationFloor, age >= -30, age <= 300 {
                    arrivals[message.key.remoteID] = message
                }
                remember(message)
                rows[message.key.remoteID] = message
                if contentVersions[message.key] == nil { contentVersions[message.key] = UUID() }
                if snapshotRows != nil { snapshotRows?[message.key.remoteID] = message }
            }
            trim(&rows)
            if var staging = snapshotRows { trim(&staging); snapshotRows = staging }
            if let value = page.cursor { stagedCursor = value }
            nextPage = page.nextPage
            pages += 1
            if let value = nextPage {
                visitedPages.insert(value)
            } else {
                guard let completedCursor = stagedCursor ?? cursor, !completedCursor.isEmpty else {
                    throw NativeMailFailure.invalidResponse
                }
                if let staging = snapshotRows { rows = staging }
                snapshotRows = nil
                cursor = completedCursor
                stagedCursor = nil
                visitedPages.removeAll(keepingCapacity: true)
                bootstrapping = false
                invalidateInvisibleContent()
                try await publishWindow(generation: expectedGeneration)
                break
            }
            invalidateInvisibleContent()
            try await publishWindow(generation: expectedGeneration)
        }
        try checkGeneration(expectedGeneration)
        let retainedArrivals = arrivals.values.filter { rows[$0.key.remoteID]?.key == $0.key }
        return NativeMailSyncResult(messages: ordered(rows.values), arrivals: ordered(retainedArrivals), hasMore: nextPage != nil)
    }

    private func validate(_ page: NativeMailPage, requestedPage: String?) throws {
        guard page.messages.count <= 1_000, page.removedIDs.count <= Self.seenLimit,
              page.removedIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 2_048 }),
              page.messages.allSatisfy({
                  $0.key.accountID == provider.account.id && !$0.key.remoteID.isEmpty
                      && $0.key.remoteID.utf8.count <= 2_048 && $0.sender.utf8.count <= 4_096
                      && $0.subject.utf8.count <= 4_096 && $0.preview.utf8.count <= 8_192
                      && $0.receivedAt.timeIntervalSince1970.isFinite
              }) else { throw NativeMailFailure.invalidResponse }
        for value in [page.nextPage, page.cursor].compactMap({ $0 }) {
            guard !value.isEmpty, value.utf8.count <= 16_384 else { throw NativeMailFailure.invalidResponse }
        }
        if let next = page.nextPage {
            guard page.resetBaseline || (next != requestedPage && !visitedPages.contains(next) && visitedPages.count < 256) else {
                throw NativeMailFailure.invalidResponse
            }
        }
    }

    private func checkGeneration(_ expected: UInt64) throws {
        guard generation == expected, !Task.isCancelled else { throw CancellationError() }
    }

    private func beginBaseline() {
        baselineDate = now()
        bootstrapping = true
        rows.removeAll()
        cursor = nil
        nextPage = nil
        stagedCursor = nil
        snapshotRows = nil
        visitedPages.removeAll()
        seen.removeAll()
        seenOrder.removeAll()
        notificationFloor = .distantPast
        contentGeneration &+= 1
        contentFlights.values.forEach { $0.task.cancel() }
        contentFlights.removeAll()
        contentVersions.removeAll()
        sharedEpoch = nil
    }

    private func remember(_ message: NativeMailSummary) {
        let id = message.key.remoteID
        guard seen[id] == nil else { return }
        seen[id] = message.receivedAt
        seenOrder.append(id)
        while seenOrder.count > Self.seenLimit {
            let oldest = seenOrder.removeFirst()
            if let date = seen.removeValue(forKey: oldest) { notificationFloor = max(notificationFloor, date) }
        }
    }

    private func ordered<S: Sequence>(_ values: S) -> [NativeMailSummary] where S.Element == NativeMailSummary {
        values.sorted {
            if $0.receivedAt != $1.receivedAt { return $0.receivedAt > $1.receivedAt }
            return $0.key.remoteID < $1.key.remoteID
        }
    }

    private func trim(_ values: inout [String: NativeMailSummary]) {
        guard values.count > Self.messageLimit else { return }
        let retained = Set(ordered(values.values).prefix(Self.messageLimit).map { $0.key.remoteID })
        values = values.filter { retained.contains($0.key) }
    }

    private func invalidateInvisibleContent() {
        let keys = Set(contentVersions.keys).union(contentFlights.keys)
        for key in keys where rows[key.remoteID]?.key != key { invalidateContent(for: key) }
    }

    private func invalidateContent(for key: NativeMailMessageKey) {
        contentVersions[key] = nil
        contentFlights.removeValue(forKey: key)?.task.cancel()
    }

    private static func publicFailure(_ error: Error) -> any Error {
        if error is CancellationError { return CancellationError() }
        guard let failure = error as? NativeMailFailure else { return NativeMailFailure.unavailable }
        if case .rateLimited(let delay) = failure {
            guard delay.isFinite, delay >= 0 else { return NativeMailFailure.invalidResponse }
            return NativeMailFailure.rateLimited(min(delay, 86_400))
        }
        return failure
    }

    private func checkContent(_ key: NativeMailMessageKey, generation expected: UInt64, version: UUID) throws {
        guard expected == contentGeneration, contentVersions[key] == version, !resetInProgress,
              !Task.isCancelled else { throw CancellationError() }
        guard rows[key.remoteID]?.key == key else { throw NativeMailFailure.messageMissing }
    }

    private func recoverBaseline(generation expected: UInt64) async throws {
        let previousEpoch = sharedEpoch
        beginBaseline()
        let epoch = await bodyCache.invalidate(accountID: provider.account.id, expectedEpoch: previousEpoch)
        try checkGeneration(expected)
        sharedEpoch = epoch
    }

    private func publishWindow(generation expected: UInt64) async throws {
        guard let epoch = sharedEpoch else { throw CancellationError() }
        let accepted = await bodyCache.setWindow(accountID: provider.account.id, epoch: epoch, versions: contentVersions)
        try checkGeneration(expected)
        guard accepted else { throw CancellationError() }
    }
}
