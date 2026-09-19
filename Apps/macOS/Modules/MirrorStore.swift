import AVFoundation
import Observation

/// The mirror module: the Mac's camera, only running while the module is visible.
/// STUB: implemented by the modules work. Keep this API.
@MainActor
@Observable
final class MirrorStore {
    enum Access: Sendable { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var isRunning = false
    /// Mirrored horizontally, like a real mirror.
    var isMirrored = true

    /// Session to attach to a preview layer, created on first use.
    var session: AVCaptureSession? { nil }

    func start() {}
    func stop() {}
    func requestAccess() async {}
}
