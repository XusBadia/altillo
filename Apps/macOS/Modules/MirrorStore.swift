import AppKit
import AVFoundation
import Observation

/// The mirror module: the Mac's camera, only running while the module is visible.
///
/// The capture session is expensive (the camera light comes on), so it is started by the view when it appears and
/// stopped the moment it goes away, the Mac sleeps or the app quits. `start()` / `stop()` are reference counted:
/// SwiftUI inserts the new view before removing the old one when the notch reopens on the same tab.
@MainActor
@Observable
final class MirrorStore {
    enum Access: Sendable { case unknown, granted, denied }

    /// A camera the user can pick.
    struct Camera: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    private(set) var access: Access = .unknown
    private(set) var isRunning = false
    /// Mirrored horizontally, like a real mirror.
    var isMirrored = true

    /// Cameras attached right now. Empty after `didLookForCameras` means "this Mac has no camera".
    private(set) var cameras: [Camera] = []
    /// Set the first time we look, so an empty list before that isn't read as "no camera".
    private(set) var didLookForCameras = false
    /// Which one is showing. Changing it swaps the input without tearing the session down.
    var selectedCameraID: String? {
        didSet {
            guard selectedCameraID != oldValue else { return }
            engine.use(device: device(for: selectedCameraID))
        }
    }

    /// Session to attach to a preview layer, created on first use.
    private(set) var session: AVCaptureSession?

    private let engine = CaptureEngine()
    private var viewers = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        access = Self.access(for: AVCaptureDevice.authorizationStatus(for: .video))
        // The camera must never outlive the moment you are looking at it.
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutDown() }
        })
    }

    /// Called by the view when the module appears.
    func start() {
        viewers += 1
        guard viewers == 1 else { return }
        refreshCameras()
        // A Mac mini has no camera: asking for one would be denied instantly and we'd blame the permission.
        guard !cameras.isEmpty else { return }
        switch access {
        case .granted: run()
        case .unknown: Task { await requestAccess() }
        case .denied: break
        }
    }

    /// Called by the view when the module goes away: the camera light goes out.
    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        suspend()
    }

    /// Asks for the camera once, the first time the mirror is opened.
    func requestAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        // As with the calendar: only call it denied when the system says so. A `false` with the status still
        // `notDetermined` means macOS never asked, and the invitation stays up so the user can try again.
        access = granted ? .granted : Self.access(for: AVCaptureDevice.authorizationStatus(for: .video))
        refreshCameras()
        guard access == .granted, viewers > 0 else { return }
        run()
    }

    func flip() { isMirrored.toggle() }

    /// The Mac has no camera at all (not a permission problem).
    var hasNoCamera: Bool { didLookForCameras && cameras.isEmpty }

    // MARK: - Session

    private func run() {
        guard let camera = device(for: selectedCameraID) else { return }
        if selectedCameraID == nil { selectedCameraID = camera.uniqueID }
        session = engine.session
        engine.start(device: camera)
        isRunning = true
    }

    /// Stops the camera but remembers that the view still wants it (sleep, or the module going away).
    private func suspend() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    private func resume() {
        guard viewers > 0, access == .granted, !isRunning else { return }
        refreshCameras()
        run()
    }

    private func shutDown() {
        viewers = 0
        suspend()
    }

    private func refreshCameras() {
        cameras = Self.discovery.devices.map { Camera(id: $0.uniqueID, name: $0.localizedName) }
        didLookForCameras = true
        if let selectedCameraID, !cameras.contains(where: { $0.id == selectedCameraID }) {
            self.selectedCameraID = cameras.first?.id
        }
    }

    private func device(for id: String?) -> AVCaptureDevice? {
        let devices = Self.discovery.devices
        if let id, let match = devices.first(where: { $0.uniqueID == id }) { return match }
        return AVCaptureDevice.default(for: .video) ?? devices.first
    }

    /// Built-in, external (USB) and iPhone Continuity cameras.
    private static let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
        mediaType: .video,
        position: .unspecified
    )

    static func access(for status: AVAuthorizationStatus) -> Access {
        switch status {
        case .authorized: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }
}

// MARK: - Capture engine

/// Owns the `AVCaptureSession`.
///
/// `AVCaptureSession` is not `Sendable`, but every call we make on it goes through `queue`, one private serial
/// queue, so only one thread ever configures it. The preview layer reads it from the main thread, which is exactly
/// what `AVCaptureVideoPreviewLayer` is designed for. Starting a session blocks for a moment, hence the queue.
private final class CaptureEngine: @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "me.badia.altillo.mirror", qos: .userInitiated)
    private var input: AVCaptureDeviceInput?

    func start(device: AVCaptureDevice) {
        queue.async { [self] in
            session.beginConfiguration()
            // The notch preview is tiny: the low preset keeps the camera cool and the CPU quiet.
            if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
            attach(device)
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
    }

    func use(device: AVCaptureDevice?) {
        guard let device else { return }
        queue.async { [self] in
            guard session.isRunning || input != nil else { return }
            session.beginConfiguration()
            attach(device)
            session.commitConfiguration()
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Must be called between `beginConfiguration()` and `commitConfiguration()`, on `queue`.
    private func attach(_ device: AVCaptureDevice) {
        if let input, input.device.uniqueID == device.uniqueID { return }
        if let input { session.removeInput(input) }
        input = nil
        guard let new = try? AVCaptureDeviceInput(device: device), session.canAddInput(new) else { return }
        session.addInput(new)
        input = new
    }
}
