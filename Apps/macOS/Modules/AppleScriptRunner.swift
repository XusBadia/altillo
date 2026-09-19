import Foundation

/// Runs AppleScript through `/usr/bin/osascript`, always off the main thread.
///
/// A child process instead of `NSAppleScript` on purpose: `NSAppleScript` is documented as main-thread-only and a
/// blocked Apple Event would freeze the notch. `osascript` can be killed, can't take the UI down with it, and the
/// Apple Events permission prompt is still attributed to Altillo (`NSAppleEventsUsageDescription` in project.yml).
enum AppleScriptRunner {
    enum Failure: Error, Equatable {
        /// The user said no (or hasn't been asked) in System Settings › Privacy › Automation.
        case notAuthorised
        /// The app isn't running, so there is nothing to ask.
        case notRunning
        /// Anything else: a missing property, a renamed app, a script error.
        case failed(String)
    }

    /// Runs `source` and returns its standard output, trimmed.
    static func run(_ source: String) async throws -> String {
        let job = Job(source: source)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: job.run())
                }
            }
        } onCancel: {
            job.cancel()
        }
    }

    /// Reads an osascript failure. The numeric Apple Event codes are the only reliable part: the wording is
    /// localised and changes between releases.
    static func failure(status: Int32, stderr: String) -> Failure {
        guard status != 0 else { return .failed(stderr) }
        if stderr.contains("-1743") || stderr.contains("errAEEventNotPermitted") { return .notAuthorised }
        if stderr.contains("-600") || stderr.contains("-609") { return .notRunning }
        return .failed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// One `osascript` invocation. `Process` is not `Sendable`; it is confined to this box, whose only two entry
    /// points (`run` once, `cancel` any number of times) are serialised by `lock`.
    private final class Job: @unchecked Sendable {
        private let source: String
        private let process = Process()
        private let lock = NSLock()
        private var isCancelled = false

        init(source: String) { self.source = source }

        func cancel() {
            lock.lock()
            isCancelled = true
            let running = process.isRunning
            lock.unlock()
            if running { process.terminate() }
        }

        func run() -> Result<String, Error> {
            let input = Pipe(), output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            // Reading the script from stdin keeps multi-line sources out of the argument list.
            process.arguments = ["-"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            lock.lock()
            let cancelledBeforeStart = isCancelled
            lock.unlock()
            if cancelledBeforeStart { return .failure(CancellationError()) }

            do {
                try process.run()
            } catch {
                return .failure(Failure.failed("no se ha podido ejecutar osascript: \(error.localizedDescription)"))
            }
            try? input.fileHandleForWriting.write(contentsOf: Data(source.utf8))
            try? input.fileHandleForWriting.close()
            // Both streams are a few hundred bytes at most, so reading them in turn cannot deadlock.
            let out = (try? output.fileHandleForReading.readToEnd()) ?? Data()
            let err = (try? errors.fileHandleForReading.readToEnd()) ?? Data()
            process.waitUntilExit()

            let status = process.terminationStatus
            guard status == 0 else {
                return .failure(AppleScriptRunner.failure(status: status, stderr: String(decoding: err, as: UTF8.self)))
            }
            let text = String(decoding: out, as: UTF8.self)
            return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
