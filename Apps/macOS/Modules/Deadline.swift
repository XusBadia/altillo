import Foundation
import os

/// Waits for work that is nice to have but must never hold up what comes next (a system framework that can stall
/// on a pending permission prompt, for example). The work keeps running after the deadline; only the wait ends.
enum Deadline {
    /// The value of `operation`, or nil when it doesn't finish within `limit` or the caller is cancelled.
    @MainActor
    static func value<T>(within limit: Duration,
                         _ operation: @escaping @MainActor () async -> T?) async -> T? {
        let gate = OSAllocatedUnfairLock<CheckedContinuation<T?, Never>?>(initialState: nil)
        let work = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
                gate.withLock { $0 = continuation }
                if Task.isCancelled {
                    gate.withLock { $0.take() }?.resume(returning: nil)
                    return
                }
                let timer = Task {
                    try? await Task.sleep(for: limit)
                    gate.withLock { $0.take() }?.resume(returning: nil)
                }
                work.withLock {
                    $0 = Task { @MainActor in
                        let value = await operation()
                        timer.cancel()
                        gate.withLock { $0.take() }?.resume(returning: value)
                    }
                }
            }
        } onCancel: {
            work.withLock { $0 }?.cancel()
            gate.withLock { $0.take() }?.resume(returning: nil)
        }
    }

    /// Waits for `operation` at most `limit`. Returns whether it finished in time.
    @MainActor @discardableResult
    static func wait(atMost limit: Duration, for operation: @escaping @MainActor () async -> Void) async -> Bool {
        await value(within: limit) { await operation(); return true } ?? false
    }
}
