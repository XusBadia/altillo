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
    private(set) var isStarting = false
    private(set) var failure: Failure?
    enum Failure: Error, Sendable { case input, startup }
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
            guard viewers > 0, access == .granted, isRunning else { return }
            run()
        }
    }

    /// Session to attach to a preview layer, created on first use.
    private(set) var session: AVCaptureSession?

    private let engine: any MirrorCaptureEngine
    private let authorizationStatus: () -> AVAuthorizationStatus
    private let availableCameras: () -> [Camera]
    private let requestCameraAccess: () async -> Bool
    private var viewers = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var deviceObservers: [NSObjectProtocol] = []
    private var requestInFlight = false
    private var runGeneration = 0

    init(
        engine: any MirrorCaptureEngine = CaptureEngine(),
        authorizationStatus: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) },
        availableCameras: @escaping () -> [Camera] = {
            MirrorStore.discovery.devices.map { Camera(id: $0.uniqueID, name: $0.localizedName) }
        },
        requestCameraAccess: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .video) }
    ) {
        self.engine = engine
        self.authorizationStatus = authorizationStatus
        self.availableCameras = availableCameras
        self.requestCameraAccess = requestCameraAccess
        access = Self.access(for: authorizationStatus())
    }

    private func watchSystem() {
        // The camera must never outlive the moment you are looking at it.
        let center = NSWorkspace.shared.notificationCenter
        let appCenter = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        }))
        observers.append((center, center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }))
        observers.append((appCenter, appCenter.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutDown() }
        }))
        observers.append((appCenter, appCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
        }))
    }

    /// Called by the view when the module appears.
    func start() {
        viewers += 1
        guard viewers == 1 else { return }
        watchSystem()
        watchDevices()
        refreshAccess()
        refreshCameras()
        // A Mac mini has no camera: asking for one would be denied instantly and we'd blame the permission.
        guard !cameras.isEmpty else { return }
        switch access {
        case .granted: run()
        case .unknown: break
        case .denied: break
        }
    }

    /// Called by the view when the module goes away: the camera light goes out.
    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        suspend()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        for observer in deviceObservers { NotificationCenter.default.removeObserver(observer) }
        deviceObservers.removeAll()
    }

    /// Called only by the permission CTA; opening the module never triggers the system prompt.
    func requestAccess() async {
        guard !requestInFlight else { return }
        requestInFlight = true
        defer { requestInFlight = false }
        let granted = await requestCameraAccess()
        // As with the calendar: only call it denied when the system says so. A `false` with the status still
        // `notDetermined` means macOS never asked, and the invitation stays up so the user can try again.
        access = granted ? .granted : Self.access(for: authorizationStatus())
        refreshCameras()
        guard access == .granted, viewers > 0 else { return }
        run()
    }

    func flip() { isMirrored.toggle() }

    /// The Mac has no camera at all (not a permission problem).
    var hasNoCamera: Bool { didLookForCameras && cameras.isEmpty }

    // MARK: - Session

    private func run() {
        guard viewers > 0, access == .granted, let cameraID = selectedCameraID else { return }
        runGeneration += 1
        let generation = runGeneration
        session = engine.session
        isStarting = true
        isRunning = false
        failure = nil
        engine.start(cameraID: cameraID) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, generation == self.runGeneration, self.viewers > 0 else { return }
                self.isStarting = false
                switch result {
                case .success(let actualID):
                    self.isRunning = true
                    if self.selectedCameraID != actualID { self.run() }
                case .failure(let error):
                    self.isRunning = false
                    self.failure = error
                    self.engine.stop()
                }
            }
        }
    }

    func retry() {
        refreshAccess()
        refreshCameras()
        if access == .granted { run() }
    }

    /// Stops the camera but remembers that the view still wants it (sleep, or the module going away).
    private func suspend() {
        runGeneration += 1
        engine.stop()
        isRunning = false
        isStarting = false
    }

    private func resume() {
        guard viewers > 0 else { return }
        refreshAccess()
        if access != .granted { suspend(); return }
        refreshCameras()
        if access == .granted, !isRunning, !isStarting { run() }
    }

    private func shutDown() {
        viewers = 0
        suspend()
    }

    private func refreshCameras() {
        cameras = availableCameras()
        didLookForCameras = true
        if let selectedCameraID, !cameras.contains(where: { $0.id == selectedCameraID }) {
            self.selectedCameraID = cameras.first?.id
        } else if selectedCameraID == nil {
            selectedCameraID = cameras.first?.id
        }
    }

    private func refreshAccess() {
        access = Self.access(for: authorizationStatus())
    }

    private func watchDevices() {
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.viewers > 0 else { return }
                    self.refreshCameras()
                    if self.cameras.isEmpty { self.suspend() }
                    else if self.access == .granted, !self.isRunning, !self.isStarting { self.run() }
                }
            })
        }
        deviceObservers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: engine.session, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.viewers > 0 else { return }
                self.suspend()
                self.failure = .startup
            }
        })
    }

    /// Built-in, external (USB) and iPhone Continuity cameras.
    static let discovery = AVCaptureDevice.DiscoverySession(
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
protocol MirrorCaptureEngine: Sendable {
    var session: AVCaptureSession { get }
    func start(cameraID: String, completion: @escaping @Sendable (Result<String, MirrorStore.Failure>) -> Void)
    func stop()
}

final class CaptureEngine: MirrorCaptureEngine, @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "me.badia.altillo.mirror", qos: .userInitiated)
    private var input: AVCaptureDeviceInput?

    func start(cameraID: String, completion: @escaping @Sendable (Result<String, MirrorStore.Failure>) -> Void) {
        queue.async { [self] in
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                mediaType: .video,
                position: .unspecified
            )
            guard let device = discovery.devices.first(where: { $0.uniqueID == cameraID }) else {
                completion(.failure(.input))
                return
            }
            session.beginConfiguration()
            // The notch preview is tiny: the low preset keeps the camera cool and the CPU quiet.
            if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
            let attached = attach(device)
            session.commitConfiguration()
            guard attached else { completion(.failure(.input)); return }
            if !session.isRunning { session.startRunning() }
            completion(session.isRunning ? .success(device.uniqueID) : .failure(.startup))
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Must be called between `beginConfiguration()` and `commitConfiguration()`, on `queue`.
    private func attach(_ device: AVCaptureDevice) -> Bool {
        if let input, input.device.uniqueID == device.uniqueID { return true }
        guard let new = try? AVCaptureDeviceInput(device: device) else { return false }
        if let input { session.removeInput(input) }
        guard session.canAddInput(new) else {
            if let input, session.canAddInput(input) { session.addInput(input) }
            return false
        }
        session.addInput(new)
        input = new
        return true
    }
}
