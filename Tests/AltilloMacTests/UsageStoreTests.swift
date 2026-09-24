import AltilloCore
import AltilloUsage
import Foundation
import Testing
@testable import Altillo

/// Phase 3: the usage store. Refreshes on its own 5-minute rhythm (and never while asleep), keeps the last numbers
/// when a read fails, has numbers at launch from disk, publishes every batch, and turns what changed into one peek,
/// never on the first reading. No network anywhere: collectors and the clock are fakes.
@MainActor
struct UsageStoreTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "me.badia.altillo.tests.usage.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    private static func archiveURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "altillo-usage-tests-\(UUID().uuidString)/usage.json")
    }

    private func makeStore(
        _ collectors: [any UsageCollector],
        clock: FakeUsageClock,
        settings: AltilloSettings? = nil,
        defaults: UserDefaults = makeDefaults(),
        archive: URL? = archiveURL(),
        external: (any UsageExternalSource)? = nil
    ) -> UsageStore {
        UsageStore(settings: settings ?? AltilloSettings(defaults: defaults), collectors: { collectors },
                   externalSource: external, clock: clock, archiveURL: archive, defaults: defaults,
                   timeout: .seconds(30))
    }

    // MARK: - Refreshing

    @Test func aRefreshReadsTheProvidersThatAreOnAndPublishesTheBatch() async {
        let clock = FakeUsageClock(now: start)
        let claude = ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.4, at: now) }
        let codex = ScriptedCollector(.codex, "Codex") { _, now in .sample(.codex, used: 0.2, at: now) }
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        settings.setUsageProvider(.codex, enabled: false)
        let store = makeStore([claude, codex], clock: clock, settings: settings, defaults: defaults)
        let publisher = RecordingPublisher()
        let off = RecordingPublisher()
        off.isEnabled = false
        store.publishers = [publisher, off]

        await store.refresh()

        #expect(claude.calls == 1)
        #expect(codex.calls == 0, "a provider switched off is never read")
        #expect(store.providers.map(\.id) == [.claude])
        #expect(store.entries.map(\.id) == [.claude, .codex], "Settings still lists it, with its switch off")
        #expect(store.lastAttempt == start)
        #expect(publisher.published.count == 1)
        #expect(off.published.isEmpty, "a publisher that can't publish is skipped")
        let snapshot = publisher.published[0]
        #expect(snapshot.providers.map(\.id) == [.claude])
        #expect(snapshot.updatedAt == start)
        #expect(snapshot.deviceID == store.deviceID)
        #expect(store.deviceID == defaults.string(forKey: UsageStore.deviceIDKey), "made once and kept")
        #expect(UUID(uuidString: store.deviceID) != nil)
    }

    @Test func aProviderSignedOutSinceTheLastRefreshLeavesTheNotch() async {
        let clock = FakeUsageClock(now: start)
        let claude = ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.4, at: now) }
        let store = makeStore([claude], clock: clock)
        await store.refresh()
        #expect(store.providers.count == 1)
        claude.setAvailable(false)
        await store.refresh()
        #expect(store.providers.isEmpty)
        #expect(store.readings[.claude] != nil, "its numbers are kept for when it's back")
    }

    @Test func providersThatAreNotSetUpStayOutOfTheNotch() async {
        let clock = FakeUsageClock(now: start)
        let claude = ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.4, at: now) }
        let codex = ScriptedCollector(.codex, "Codex", available: false) { _, now in .sample(.codex, used: 0.2, at: now) }
        let store = makeStore([claude, codex], clock: clock)

        await store.refresh()

        #expect(codex.calls == 0, "nothing to read without a sign-in")
        #expect(store.providers.map(\.id) == [.claude])
        #expect(store.entries.first { $0.id == .codex }?.isAvailable == false)
        #expect(UsageText.status(for: store.entries[1]) == "Not signed in on this Mac")
    }

    @Test func aFailedReadKeepsTheLastNumbersAndGoesStale() async {
        let clock = FakeUsageClock(now: start)
        let claude = ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.4, at: now) }
        let store = makeStore([claude], clock: clock)
        await store.refresh()

        clock.advance(by: 5 * 60)
        claude.respond { _, now in
            ProviderUsage(id: .claude, displayName: "Claude", plan: nil, windows: [], fetchedAt: now,
                          problem: .unreachable("offline"))
        }
        await store.refresh()

        let kept = try? #require(store.providers.first)
        #expect(kept?.session?.used == 0.4, "the last good numbers stay on screen")
        #expect(kept?.plan == "Max 20×")
        #expect(kept?.fetchedAt == start, "and say when they were read, not when the read failed")
        #expect(kept?.problem == .unreachable("offline"))
        #expect(store.freshness(now: clock.now) == .upToDate(since: start))
        #expect(store.freshness(now: start.addingTimeInterval(16 * 60)) == .stale(since: start))
        #expect(kept?.isStale(now: start.addingTimeInterval(16 * 60), limit: UsageStore.staleAfter) == true)

        // Back online: fresh numbers replace them.
        claude.respond { _, now in .sample(.claude, used: 0.5, at: now) }
        clock.advance(by: 5 * 60)
        await store.refresh()
        #expect(store.providers.first?.problem == nil)
        #expect(store.providers.first?.fetchedAt == clock.now)
    }

    @Test func mergeOnlyStepsInWhenThereIsSomethingToKeep() {
        let good = ProviderUsage.sample(.claude, used: 0.3, at: start)
        var failed = ProviderUsage(id: .claude, displayName: "Claude", plan: nil, windows: [],
                                   fetchedAt: start.addingTimeInterval(300), problem: .sessionExpired)
        #expect(UsageMerge.merge(good, previous: nil) == good)
        #expect(UsageMerge.merge(failed, previous: nil) == failed, "nothing to keep")
        let merged = UsageMerge.merge(failed, previous: good)
        #expect(merged.windows == good.windows && merged.fetchedAt == start && merged.problem == .sessionExpired)
        failed.problem = nil
        #expect(UsageMerge.merge(failed, previous: good) == failed, "a good read always wins, even an empty one")
    }

    @Test func aCollectorThatHangsTimesOutWithoutHoldingUpTheOthers() async {
        let clock = FakeUsageClock(now: start)
        let slow = ScriptedCollector(.claude, "Claude", hangs: true) { _, now in .sample(.claude, used: 0.4, at: now) }
        let codex = ScriptedCollector(.codex, "Codex") { _, now in .sample(.codex, used: 0.2, at: now) }
        let store = makeStore([slow, codex], clock: clock)

        let refresh = Task { await store.refresh() }
        await waitUntil { slow.calls == 1 && codex.calls == 1 }
        await settle()
        #expect(clock.pendingSleeps == 1, "only the slow one's time limit is still running")
        clock.advance(by: 30)
        await refresh.value

        #expect(store.entries.first { $0.id == .claude }?.usage?.problem == .unreachable("timed out"))
        #expect(store.providers.map(\.id).contains(.codex))
    }

    @Test func aRateLimitedProviderIsLeftAloneUntilItMayBeAskedAgain() async {
        let clock = FakeUsageClock(now: start)
        let claude = ScriptedCollector(.claude, "Claude") { previous, now in
            var usage = ProviderUsage.sample(.claude, used: 0.4, at: now)
            usage.problem = .rateLimited(retryAfter: now.addingTimeInterval(20 * 60))
            return usage
        }
        let store = makeStore([claude], clock: clock)
        await store.refresh()
        clock.advance(by: 5 * 60)
        await store.refresh()
        #expect(claude.calls == 1, "asked to wait 20 min: the next refresh doesn't ask")
        clock.advance(by: 16 * 60)
        await store.refresh()
        #expect(claude.calls == 2)
    }

    @Test func theOpenUsageSourceOnlyFillsInProvidersAltilloDoesNotRead() async {
        let clock = FakeUsageClock(now: start)
        let claude = ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.4, at: now) }
        let cursor = UsageProviderID(rawValue: "cursor")
        let external = FakeExternalSource { known, now in
            [ProviderUsage.sample(.claude, used: 0.99, at: now), ProviderUsage.sample(cursor, used: 0.1, at: now)]
                .filter { !known.contains($0.id) }
        }
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        let store = makeStore([claude], clock: clock, settings: settings, defaults: defaults, external: external)

        await store.refresh()
        #expect(store.providers.map(\.id) == [.claude, cursor])
        #expect(store.providers.first?.session?.used == 0.4, "Altillo's own reading wins")
        #expect(store.entries.last?.isExternal == true)
        #expect(external.lastExcluded == [.claude])

        settings.usageShowsOpenUsageSource = false
        store.providersMayHaveChanged()
        #expect(store.providers.map(\.id) == [.claude], "its providers leave at once")
        await store.refresh()
        #expect(external.calls == 1, "switched off: not asked")
    }

    // MARK: - Scheduling

    @Test func itRefreshesAtLaunchThenEveryFiveMinutesAndNeverWhileAsleep() async {
        let clock = FakeUsageClock(now: start)
        let claude = ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.4, at: now) }
        let store = makeStore([claude], clock: clock)
        store.start()
        defer { store.stop() }

        await waitUntil { store.lastAttempt == start && clock.pendingSleeps == 1 }
        #expect(claude.calls == 1, "one refresh at launch")

        clock.advance(by: 4 * 60)
        await settle()
        #expect(claude.calls == 1, "nothing between refreshes")
        clock.advance(by: 60)
        await waitUntil { store.lastAttempt == clock.now && clock.pendingSleeps == 1 }
        #expect(claude.calls == 2)

        store.sleep()
        await waitUntil { clock.pendingSleeps == 0 }
        clock.advance(by: 60 * 60)
        await settle()
        #expect(claude.calls == 2, "asleep: no refresh at all")

        store.wake()
        await waitUntil { clock.pendingSleeps == 1 }
        clock.advance(by: 5)
        await waitUntil { store.lastAttempt == clock.now }
        #expect(claude.calls == 3, "waking brings a refresh once the network is back")
    }

    @Test func turningTheSectionOffStopsRefreshing() async {
        let clock = FakeUsageClock(now: start)
        let claude = ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.4, at: now) }
        let store = makeStore([claude], clock: clock)
        store.start()
        defer { store.stop() }
        await waitUntil { store.lastAttempt == start && clock.pendingSleeps == 1 }

        store.setSectionEnabled(false)
        await waitUntil { clock.pendingSleeps == 0 }
        clock.advance(by: 30 * 60)
        await settle()
        #expect(claude.calls == 1)
        #expect(!store.providers.isEmpty, "the last numbers stay")

        // Something that sends the numbers to the iPhone keeps them coming, even with the section off.
        store.publishers = [RecordingPublisher()]
        await waitUntil { store.lastAttempt == clock.now }
        #expect(claude.calls == 2)
        store.publishers = []
        await waitUntil { clock.pendingSleeps == 0 }

        // Back on with numbers from a moment ago: the rhythm picks up, no extra refresh.
        store.setSectionEnabled(true)
        await waitUntil { clock.pendingSleeps == 1 }
        #expect(claude.calls == 2)
        clock.advance(by: 5 * 60)
        await waitUntil { claude.calls == 3 }
    }

    @Test func theTabOnlyRefreshesNumbersOlderThanAMinute() async {
        let clock = FakeUsageClock(now: start)
        let claude = ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.4, at: now) }
        let store = makeStore([claude], clock: clock)
        store.start()
        defer { store.stop() }
        await waitUntil { store.lastAttempt == start && clock.pendingSleeps == 1 }

        clock.advance(by: 30)
        store.refreshIfOlder(than: 60)
        await settle()
        #expect(claude.calls == 1)

        clock.advance(by: 45)
        store.refreshIfOlder(than: 60)
        await waitUntil { claude.calls == 2 }
    }

    // MARK: - Persistence

    @Test func theLastSnapshotIsOnScreenAtLaunchBeforeAnyRefresh() async throws {
        let clock = FakeUsageClock(now: start)
        let archive = Self.archiveURL()
        let first = makeStore([ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.63, at: now) }],
                              clock: clock, archive: archive)
        await first.refresh()
        let saved = try #require(first.snapshot)
        #expect(FileManager.default.fileExists(atPath: archive.path(percentEncoded: false)))

        let later = ScriptedCollector(.claude, "Claude") { _, now in .sample(.claude, used: 0.1, at: now) }
        let relaunched = makeStore([later], clock: clock, archive: archive)
        relaunched.start()
        defer { relaunched.stop() }
        // Checked before yielding: the launch refresh hasn't had a chance to run yet.
        #expect(relaunched.providers == saved.providers, "numbers straight from disk, exactly as saved")
        #expect(relaunched.snapshot == saved)
        #expect(relaunched.primary?.session?.used == 0.63)

        let decoded = try UsageArchive.decoder.decode(UsageSnapshot.self, from: Data(contentsOf: archive))
        #expect(decoded == saved)
        #expect(decoded.schema == UsageSnapshot.schema)
    }

    @Test func aDamagedArchiveIsIgnored() throws {
        let archive = Self.archiveURL()
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: archive)
        let store = makeStore([], clock: FakeUsageClock(now: start), archive: archive)
        store.start()
        defer { store.stop() }
        #expect(store.providers.isEmpty)
        #expect(store.snapshot == nil)
    }

    // MARK: - Alerts

    @Test func theFirstReadingIsABaselineAndEachLevelPeeksOncePerWindow() async throws {
        let clock = FakeUsageClock(now: start)
        let reading = Reading(used: 0.85, resetsAt: start.addingTimeInterval(3 * 3600))
        let claude = ScriptedCollector(.claude, "Claude") { _, now in reading.usage(at: now) }
        let store = makeStore([claude], clock: clock)
        var posted: [NotchAlert] = []
        store.postAlert = { posted.append($0) }

        await store.refresh()
        #expect(posted.isEmpty, "85 % at launch is a baseline, not news")

        reading.used = 0.9
        await store.refresh()
        #expect(posted.isEmpty, "90 % isn't one of the levels (80 and 95)")

        reading.used = 0.96
        await store.refresh()
        let alert = try #require(posted.last)
        #expect(posted.count == 1)
        #expect(alert.title == "Claude is at 96% of the session")
        #expect(alert.trailing == UsageText.refillsAt(reading.usage(at: start).session!, now: start))
        #expect(alert.source == .usage && alert.module == .usage && alert.isUrgent)
        #expect(alert.symbol == "gauge.with.needle")

        reading.used = 0.97
        await store.refresh()
        #expect(posted.count == 1, "once per window")

        // A new window: it refilled.
        reading.used = 0.02
        reading.resetsAt = start.addingTimeInterval(8 * 3600)
        await store.refresh()
        #expect(posted.count == 2)
        #expect(posted.last?.title == "Claude is ready again")
        #expect(posted.last?.detail == "Session refilled")
    }

    @Test func alertsFollowTheSettings() async {
        let clock = FakeUsageClock(now: start)
        let reading = Reading(used: 0.5, resetsAt: start.addingTimeInterval(3 * 3600))
        let claude = ScriptedCollector(.claude, "Claude") { _, now in reading.usage(at: now) }
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        let store = makeStore([claude], clock: clock, settings: settings, defaults: defaults)
        var posted: [NotchAlert] = []
        store.postAlert = { posted.append($0) }
        await store.refresh()

        settings.alertsForUsage = false
        reading.used = 0.85
        await store.refresh()
        #expect(posted.isEmpty, "alerts off")

        settings.alertsForUsage = true
        reading.used = 0.88
        await store.refresh()
        #expect(posted.isEmpty, "80 % was already crossed while alerts were off: it doesn't peek late")

        settings.setEnabled(.usage, false)
        reading.used = 0.96
        await store.refresh()
        #expect(posted.isEmpty, "the section is off")

        settings.setEnabled(.usage, true)
        settings.usageAlertsWhenRefilled = false
        reading.used = 0.01
        reading.resetsAt = start.addingTimeInterval(9 * 3600)
        await store.refresh()
        #expect(posted.isEmpty, "refills don't peek when switched off")
    }

    @Test func staleNumbersNeverRaiseAnAlert() async {
        let clock = FakeUsageClock(now: start)
        let reading = Reading(used: 0.5, resetsAt: start.addingTimeInterval(3 * 3600))
        let claude = ScriptedCollector(.claude, "Claude") { _, now in reading.usage(at: now) }
        let store = makeStore([claude], clock: clock)
        var posted: [NotchAlert] = []
        store.postAlert = { posted.append($0) }
        await store.refresh()
        claude.respond { _, now in
            var usage = reading.usage(at: now)
            usage.windows[0].used = 0.99
            usage.problem = .unreachable("offline")
            return usage
        }
        await store.refresh()
        #expect(posted.isEmpty)
    }

    @Test func aBatchPeeksAboutWhatMattersMost() throws {
        let now = start
        let claude = ProviderUsage.sample(.claude, used: 1, at: now)
        let codex = ProviderUsage.sample(.codex, used: 0.96, at: now)
        func event(_ provider: ProviderUsage, _ kind: UsageAlertEvent.Kind, window: String = "session") -> UsageAlertEvent {
            UsageAlertEvent(provider: provider.id, providerName: provider.displayName, windowID: window,
                            windowLabel: "Session", kind: kind)
        }
        let events = [event(codex, .threshold(95)), event(claude, .refilled, window: "weekly"), event(claude, .limitReached)]
        let alert = try #require(UsageAlertPresenter.alert(for: events, providers: [claude, codex], now: now))
        #expect(alert.title == "Claude has used all of the session")
        #expect(alert.isUrgent)

        let week = try #require(claude.weekly)
        let runsOut = now.addingTimeInterval(2 * 3600)
        let early = UsageAlertPresenter.alert(for: event(claude, .runningOutEarly(runsOutAt: runsOut), window: "weekly"),
                                              window: week, now: now)
        #expect(early.title == "At this pace Claude runs out at \(UsageText.moment(runsOut, now: now))")
        #expect(early.detail == "the week")
        #expect(!early.isUrgent)
        #expect(UsageAlertPresenter.alert(for: [], providers: [claude], now: now) == nil)
    }

    // MARK: - Ears

    @Test func theContextualEarOnlyHearsAboutUsageWhenItRunsHigh() {
        let now = start
        let calm = ProviderUsage.sample(.claude, used: 0.3, at: now)
        let high = ProviderUsage.sample(.claude, used: 0.86, at: now)
        #expect(UsageStore.contextualSignal(primary: calm, thresholds: [80, 95], now: now) == nil)
        #expect(UsageStore.contextualSignal(primary: high, thresholds: [80, 95], now: now)
            == UsageSignal(providerName: "Claude", fraction: 0.86))
        #expect(UsageStore.contextualSignal(primary: calm, thresholds: [25], now: now) != nil,
                "the lowest alert level decides")
        #expect(UsageStore.contextualSignal(primary: high, thresholds: [80], now: now.addingTimeInterval(20 * 60)) == nil,
                "stale numbers aren't what matters now")
        #expect(UsageStore.contextualSignal(primary: nil, thresholds: [80], now: now) == nil)
    }

    @Test func realUsageFeedsTheEarsAndTheContextualEar() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.leftEar = .automatic
        settings.rightEar = .usage
        settings.earsVisibility = .withActivity
        let model = NotchModel(settings: settings)
        model.nowPlaying.permission = { _ in .undetermined }
        model.ears.fetchEvents = { [] }
        model.ears.update(left: settings.leftEar, right: settings.rightEar, modules: settings.modules)
        #expect(!model.ears.hasActivity(.usage, in: model))
        #expect(model.contextualActivity == .rest)

        model.usage.replaceReadings(with: [.sample(.claude, used: 0.9, at: .now)], at: .now)
        #expect(model.ears.hasActivity(.usage, in: model))
        #expect(model.ears.showsEars(for: model))
        #expect(model.contextualActivity == .usage(UsageSignal(providerName: "Claude", fraction: 0.9)))

        settings.setEnabled(.usage, false)
        #expect(model.contextualActivity == .rest, "only sections that are on take part")

        settings.setEnabled(.usage, true)
        settings.setUsageProvider(.claude, enabled: false)
        #expect(!model.ears.hasActivity(.usage, in: model), "a provider switched off leaves the ear")
    }

    // MARK: - Words

    @Test func thePaceAndProblemsAreOneClearSentence() {
        let now = start
        func window(used: Double, elapsed hours: Double) -> UsageWindow {
            UsageWindow(id: "session", kind: .session, label: "Session", used: used,
                        resetsAt: now.addingTimeInterval((5 - hours) * 3600), duration: 5 * 3600)
        }
        #expect(UsageText.pace(for: window(used: 0.1, elapsed: 2.5), now: now)?.text == "Plenty left")
        #expect(UsageText.pace(for: window(used: 0.47, elapsed: 2.5), now: now)?.text == "On track")
        let behind = UsageText.pace(for: window(used: 0.75, elapsed: 2.5), now: now)
        #expect(behind?.text.hasPrefix("Runs out at") == true && behind?.tone == .warning)
        #expect(UsageText.pace(for: window(used: 1, elapsed: 2.5), now: now)?.text == "Limit reached")
        let unstarted = UsageWindow(id: "session", kind: .session, label: "Session", used: 0, resetsAt: nil, duration: 5 * 3600)
        #expect(UsageText.refillsIn(unstarted, now: now) == "starts with your next message")
        #expect(UsageText.length(of: unstarted) == "5 h")

        #expect(UsageText.sentence(for: .sessionExpired, provider: .claude, displayName: "Claude")
            == "The sign-in expired. Open Claude Code once and it's back.")
        #expect(UsageText.canRetry(.unreachable("x")) && !UsageText.canRetry(.rateLimited(retryAfter: nil)))
        let expired = UsageStore.Entry(id: .claude, displayName: "Claude", isAvailable: true, isExternal: false,
                                       usage: ProviderUsage(id: .claude, displayName: "Claude", plan: nil, windows: [],
                                                            fetchedAt: now, problem: .sessionExpired))
        #expect(UsageText.status(for: expired) == "Sign-in expired: open Claude Code once")
        let connected = UsageStore.Entry(id: .claude, displayName: "Claude", isAvailable: true, isExternal: false,
                                         usage: .sample(.claude, used: 0.2, at: now))
        #expect(UsageText.status(for: connected) == "Connected · Max 20×")
    }

    // MARK: - Settings

    @Test func usageSettingsHaveGoodDefaultsAndSurviveARelaunch() {
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        #expect(settings.usageDisabledProviders.isEmpty, "every provider that's set up is on")
        #expect(settings.usageAlertThresholds == [80, 95])
        #expect(settings.usageAlertsWhenRefilled && settings.alertsForUsage && settings.usageShowsOpenUsageSource)
        #expect(settings.usageAlertConfiguration == UsageAlertConfiguration(thresholds: [80, 95]))

        settings.setUsageProvider(.codex, enabled: false)
        settings.usageAlertThresholds = [95, 50, 50, 120, 0]
        settings.setUsageAlertThreshold(90, enabled: true)
        settings.setUsageAlertThreshold(95, enabled: false)
        settings.usageAlertsWhenRefilled = false
        settings.usageShowsOpenUsageSource = false
        settings.alertsForUsage = false
        #expect(settings.usageAlertThresholds == [50, 90], "sorted, unique, 1…99")

        let relaunched = AltilloSettings(defaults: defaults)
        #expect(!relaunched.isUsageProviderEnabled(.codex) && relaunched.isUsageProviderEnabled(.claude))
        #expect(relaunched.usageAlertThresholds == [50, 90])
        #expect(!relaunched.usageAlertsWhenRefilled && !relaunched.usageShowsOpenUsageSource && !relaunched.alertsForUsage)
        #expect(relaunched.usageAlertConfiguration.refilled == false)
    }

    // MARK: - Ask

    @Test func askReadsTheLatestNumbersWithoutTheNetwork() {
        let now = start
        let reading = AssistantUsage.Reading(isEnabled: true, providers: [
            .sample(.claude, used: 0.85, at: now.addingTimeInterval(-120)),
            .sample(.codex, used: 0.2, at: now.addingTimeInterval(-120)),
        ])
        let all = AssistantUsage.answer(reading, provider: nil, now: now)
        #expect(all.contains("Claude (Max 20× plan):"))
        #expect(all.contains("- Session: 85% used, 15% left, refills in"))
        #expect(all.contains("Codex"))
        #expect(all.contains("Read 2 min ago."))

        let one = AssistantUsage.answer(reading, provider: "codex", now: now)
        #expect(one.contains("Codex") && !one.contains("Claude"))
        #expect(AssistantUsage.answer(reading, provider: "Gemini", now: now).contains("doesn't read Gemini"))
        #expect(AssistantUsage.answer(.init(isEnabled: true, providers: []), provider: nil, now: now)
            .contains("isn't reading any AI limits"))
        #expect(AssistantUsage.answer(.init(isEnabled: false, providers: []), provider: nil, now: now)
            .contains("turned off"))
    }

    @Test func questionsAboutWhatIsLeftGoToTheLocalTools() {
        for question in ["¿Cuánto me queda de Claude?", "How much Codex do I have left?", "Is Codex close to its limit?",
                         "¿Cómo voy de Claude?", "Show my AI usage", "When does my Claude session reset?"] {
            #expect(AssistantRouter.route(question, now: start) == .context, "\(question)")
        }
        #expect(AssistantRouter.route("Who founded Anthropic?", now: start) == .chat)
    }

    // MARK: - Helpers

    /// Lets tasks on other executors (the collectors) run until `condition` holds, for up to 2 s.
    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("condition never became true", sourceLocation: sourceLocation)
    }

    /// Gives anything that would (wrongly) run a moment to do so.
    private func settle() async {
        for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(5)) }
    }
}

// MARK: - Fakes

extension ProviderUsage {
    static func sample(_ id: UsageProviderID, used: Double, at date: Date) -> ProviderUsage {
        let name = id == .claude ? "Claude" : id == .codex ? "Codex" : id.rawValue.capitalized
        return ProviderUsage(
            id: id, displayName: name, plan: id == .claude ? "Max 20×" : "Pro",
            windows: [
                UsageWindow(id: "session", kind: .session, label: "Session", used: used,
                            resetsAt: date.addingTimeInterval(3 * 3600), duration: 5 * 3600),
                UsageWindow(id: "weekly", kind: .weekly, label: "Week", used: used / 2,
                            resetsAt: date.addingTimeInterval(4 * 86_400), duration: 7 * 86_400),
            ],
            fetchedAt: date
        )
    }
}

/// A session reading the test moves by hand. No duration, so pace never adds its own alerts.
private final class Reading: @unchecked Sendable {
    private let lock = NSLock()
    private var _used: Double
    private var _resetsAt: Date

    init(used: Double, resetsAt: Date) {
        _used = used
        _resetsAt = resetsAt
    }

    var used: Double {
        get { lock.withLock { _used } }
        set { lock.withLock { _used = newValue } }
    }

    var resetsAt: Date {
        get { lock.withLock { _resetsAt } }
        set { lock.withLock { _resetsAt = newValue } }
    }

    func usage(at date: Date) -> ProviderUsage {
        ProviderUsage(id: .claude, displayName: "Claude", plan: "Max 20×",
                      windows: [UsageWindow(id: "session", kind: .session, label: "Session", used: used,
                                            resetsAt: resetsAt, duration: nil)],
                      fetchedAt: date)
    }
}

final class ScriptedCollector: UsageCollector, @unchecked Sendable {
    typealias Response = @Sendable (ProviderUsage?, Date) -> ProviderUsage

    let providerID: UsageProviderID
    let displayName: String
    private let lock = NSLock()
    private var response: Response
    private var count = 0
    private var available: Bool
    private let hangs: Bool

    init(_ id: UsageProviderID, _ name: String, available: Bool = true, hangs: Bool = false,
         response: @escaping Response) {
        providerID = id
        displayName = name
        self.available = available
        self.hangs = hangs
        self.response = response
    }

    var calls: Int { lock.withLock { count } }

    func respond(_ response: @escaping Response) { lock.withLock { self.response = response } }

    func setAvailable(_ value: Bool) { lock.withLock { available = value } }

    func isAvailable() async -> Bool { lock.withLock { available } }

    func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        let response = lock.withLock { () -> Response in
            count += 1
            return self.response
        }
        if hangs { try? await Task.sleep(for: .seconds(3600)) }
        return response(previous, now)
    }
}

final class FakeExternalSource: UsageExternalSource, @unchecked Sendable {
    typealias Response = @Sendable (Set<UsageProviderID>, Date) -> [ProviderUsage]
    private let lock = NSLock()
    private let response: Response
    private var count = 0
    private var excluded: Set<UsageProviderID> = []

    init(_ response: @escaping Response) { self.response = response }

    var calls: Int { lock.withLock { count } }
    var lastExcluded: Set<UsageProviderID> { lock.withLock { excluded } }

    func fetch(excluding known: Set<UsageProviderID>, previous: [ProviderUsage], now: Date) async -> [ProviderUsage] {
        lock.withLock {
            count += 1
            excluded = known
        }
        return response(known, now)
    }
}

@MainActor
final class RecordingPublisher: UsageSnapshotPublisher {
    var isEnabled = true
    private(set) var published: [UsageSnapshot] = []
    func publish(_ snapshot: UsageSnapshot) { published.append(snapshot) }
}

/// A clock whose time only moves when the test says so. Sleepers wake when it passes their deadline, and a
/// cancelled sleep throws like `Task.sleep`.
final class FakeUsageClock: UsageClock, @unchecked Sendable {
    private struct Sleeper {
        var id: UUID
        var deadline: Date
        var continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current: Date
    private var sleepers: [Sleeper] = []
    private var cancelled: Set<UUID> = []

    init(now: Date) { current = now }

    var now: Date { lock.withLock { current } }
    var pendingSleeps: Int { lock.withLock { sleepers.count } }

    func sleep(for duration: Duration) async throws {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        guard seconds > 0 else { return try Task.checkCancellation() }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let early = lock.withLock { () -> Bool in
                    if cancelled.remove(id) != nil { return true }
                    sleepers.append(Sleeper(id: id, deadline: current.addingTimeInterval(seconds),
                                            continuation: continuation))
                    return false
                }
                if early { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let sleeper = lock.withLock { () -> Sleeper? in
                if let index = sleepers.firstIndex(where: { $0.id == id }) { return sleepers.remove(at: index) }
                cancelled.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by seconds: TimeInterval) {
        let due = lock.withLock { () -> [Sleeper] in
            current = current.addingTimeInterval(seconds)
            let due = sleepers.filter { $0.deadline <= current }
            sleepers.removeAll { $0.deadline <= current }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }
}
