import AppKit
import Foundation

/// The universal provider: the system's Now Playing (any app) through the vendored `mediaremote-adapter`.
///
/// Since macOS 15.4 the private MediaRemote framework only answers entitled Apple processes. `/usr/bin/perl` is one
/// of them, so the adapter's script runs in it and loads `MediaRemoteAdapter.framework` (built from the vendored
/// source in `Vendor/mediaremote-adapter`, embedded in Altillo.app, never linked). Altillo itself stays a normal,
/// notarisable app with no private entitlements, and nothing needs installing.
///
/// - **Streaming, not polling:** one long-lived `perl … stream` that prints a line only when something changes
///   (MediaRemote's own notifications). Idle, it sleeps in a run loop: 0 % CPU.
/// - **Only while needed:** the store starts it when something wants playback (the section on screen, an ear, the
///   new-song alert) and stops it when nothing does.
/// - **Dies with Altillo:** terminated on stop and on quit; on a crash or force quit the framework notices its
///   parent is gone (a kqueue process source added in `src/altillo/parent_watch.m`) and exits.
/// - **Breaks quietly:** if the helper keeps crashing it is given up on (`NowPlayingProviderChoice`) and the store
///   falls back to AppleScript for Music and Spotify.
@MainActor
final class MediaRemoteNowPlayingProvider: NowPlayingProvider {
    struct Paths: Sendable, Equatable {
        var perl: URL
        var script: URL
        var framework: URL
    }

    /// The helper inside Altillo.app, or `nil` when it isn't there (a build without it) or perl is gone.
    static func bundledPaths(in bundle: Bundle = .main, fileManager: FileManager = .default) -> Paths? {
        guard let frameworks = bundle.privateFrameworksURL else { return nil }
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        let script = framework.appendingPathComponent("Resources/mediaremote-adapter.pl")
        let perl = URL(fileURLWithPath: "/usr/bin/perl")
        guard fileManager.isExecutableFile(atPath: perl.path),
              fileManager.fileExists(atPath: script.path),
              fileManager.fileExists(atPath: framework.appendingPathComponent("MediaRemoteAdapter").path)
        else { return nil }
        return Paths(perl: perl, script: script, framework: framework)
    }

    /// Arguments for the stream: microsecond times (plain numbers, no date strings) and a short debounce so a track
    /// change (title, then artist, then artwork) arrives as one update instead of three.
    static func streamArguments(_ paths: Paths) -> [String] {
        [paths.script.path, paths.framework.path, "stream", "--micros", "--debounce=150"]
    }

    /// Arguments for a one-off command. MediaRemote's command IDs: 2 toggle play/pause, 4 next, 5 previous.
    static func commandArguments(_ command: NowPlayingCommand, paths: Paths) -> [String] {
        let base = [paths.script.path, paths.framework.path]
        switch command {
        case .playPause: return base + ["send", "2"]
        case .next: return base + ["send", "4"]
        case .previous: return base + ["send", "5"]
        case let .seek(seconds): return base + ["seek", String(NowPlayingSeek.micros(seconds))]
        }
    }

    private let paths: Paths
    private var handler: (@MainActor (NowPlayingProviderEvent) -> Void)?
    private var process: Process?
    /// Bumped on every launch, so a late line or exit from an old helper is ignored.
    private var generation = 0
    private var wantsRunning = false
    private var failures: [Date] = []
    private var hasFailed = false
    private var restartTask: Task<Void, Never>?
    private var quitObserver: NSObjectProtocol?

    init(paths: Paths) {
        self.paths = paths
    }

    func start(_ handler: @escaping @MainActor (NowPlayingProviderEvent) -> Void) {
        self.handler = handler
        guard !wantsRunning, !hasFailed else { return }
        wantsRunning = true
        observeQuit()
        launch()
    }

    func stop() {
        wantsRunning = false
        restartTask?.cancel()
        restartTask = nil
        terminate()
    }

    func perform(_ command: NowPlayingCommand) {
        let perl = paths.perl
        let arguments = Self.commandArguments(command, paths: paths)
        DispatchQueue.global(qos: .userInitiated).async {
            Self.runOnce(perl, arguments: arguments)
        }
    }

    // MARK: - The stream

    private func launch() {
        guard wantsRunning, process == nil else { return }
        generation += 1
        let generation = generation
        let process = Process()
        process.executableURL = paths.perl
        process.arguments = Self.streamArguments(paths)
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output

        let reader = StreamReader { [weak self] snapshot in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.deliver(snapshot, generation: generation) }
            }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            reader.consume(chunk)
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.exited(generation: generation, status: status, reason: reason)
                }
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            giveUp()
        }
    }

    private func deliver(_ snapshot: NowPlayingSnapshot?, generation: Int) {
        guard generation == self.generation, wantsRunning else { return }
        handler?(.changed(snapshot))
    }

    private func exited(generation: Int, status: Int32, reason: Process.TerminationReason) {
        guard generation == self.generation else { return }
        process = nil
        // Asked to stop: that's not a failure.
        guard wantsRunning else { return }
        let now = Date.now
        failures.append(now)
        guard let delay = NowPlayingProviderChoice.restartDelay(failures: failures, now: now) else {
            giveUp()
            return
        }
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.launch()
        }
    }

    private func giveUp() {
        hasFailed = true
        wantsRunning = false
        terminate()
        handler?(.failed)
    }

    private func terminate() {
        generation += 1
        guard let process else { return }
        self.process = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    private func observeQuit() {
        guard quitObserver == nil else { return }
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// A short-lived command (`send`, `seek`). Never on the main thread; killed if it hangs.
    nonisolated private static func runOnce(_ executable: URL, arguments: [String]) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        guard (try? process.run()) != nil else { return }
        if done.wait(timeout: .now() + 5) == .timedOut { process.terminate() }
    }
}

/// Owns the line buffer and the diff state for one helper. The pipe's readability handler calls `consume` from
/// one serial queue at a time; the lock keeps it honest if that ever changes.
private final class StreamReader: @unchecked Sendable {
    private let lock = NSLock()
    private var lines = LineSplitter()
    private var stream = MediaRemoteAdapterStream()
    private let emit: @Sendable (NowPlayingSnapshot?) -> Void

    init(emit: @escaping @Sendable (NowPlayingSnapshot?) -> Void) {
        self.emit = emit
    }

    func consume(_ chunk: Data) {
        lock.lock()
        var latest: NowPlayingSnapshot??
        for line in lines.append(chunk) {
            if let snapshot = stream.consume(line: line) { latest = snapshot }
        }
        lock.unlock()
        // Several lines in one chunk: only the last state matters.
        if let latest { emit(latest) }
    }
}
