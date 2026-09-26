import AVFoundation
import Testing
@testable import Altillo

private final class FakeMirrorEngine: MirrorCaptureEngine, @unchecked Sendable {
    let session = AVCaptureSession()
    private(set) var starts: [String] = []
    private(set) var stopCount = 0
    private var completions: [(@Sendable (Result<String, MirrorStore.Failure>) -> Void)] = []

    func start(cameraID: String, completion: @escaping @Sendable (Result<String, MirrorStore.Failure>) -> Void) {
        starts.append(cameraID)
        completions.append(completion)
    }

    func stop() { stopCount += 1 }

    func finish(_ result: Result<String, MirrorStore.Failure>, at index: Int) {
        completions[index](result)
    }
}

struct UXUtilitiesMirrorTests {
    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async {
        for _ in 0..<50 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor
    @Test func firstLookExplainsAccessBeforeRequestingIt() {
        let engine = FakeMirrorEngine()
        var requests = 0
        let store = MirrorStore(
            engine: engine,
            authorizationStatus: { .notDetermined },
            availableCameras: { [.init(id: "built-in", name: "Built-in")] },
            requestCameraAccess: { requests += 1; return true }
        )
        store.start()
        #expect(store.access == .unknown)
        #expect(requests == 0)
        #expect(engine.starts.isEmpty)
        store.stop()
    }

    @MainActor
    @Test func reopeningAfterGrantRefreshesPermissionWithoutPrompt() {
        let engine = FakeMirrorEngine()
        var status: AVAuthorizationStatus = .denied
        var requests = 0
        let store = MirrorStore(
            engine: engine,
            authorizationStatus: { status },
            availableCameras: { [.init(id: "built-in", name: "Built-in")] },
            requestCameraAccess: { requests += 1; return false }
        )
        store.start()
        #expect(store.access == .denied)
        #expect(engine.starts.isEmpty)
        store.stop()

        status = .authorized
        store.start()
        #expect(store.access == .granted)
        #expect(engine.starts == ["built-in"])
        #expect(requests == 0)
        store.stop()
    }

    @MainActor
    @Test func cameraHotplugStartsAndDisconnectStopsWhileVisible() async {
        let engine = FakeMirrorEngine()
        var cameras: [MirrorStore.Camera] = []
        let store = MirrorStore(
            engine: engine,
            authorizationStatus: { .authorized },
            availableCameras: { cameras }
        )
        store.start()
        #expect(store.hasNoCamera)
        #expect(engine.starts.isEmpty)

        cameras = [.init(id: "usb", name: "USB camera")]
        NotificationCenter.default.post(name: AVCaptureDevice.wasConnectedNotification, object: nil)
        await waitUntil { engine.starts.count == 1 }
        #expect(engine.starts == ["usb"])
        #expect(store.isStarting)
        engine.finish(.success("usb"), at: 0)
        await waitUntil { store.isRunning }
        #expect(store.isRunning)

        cameras = []
        NotificationCenter.default.post(name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        await waitUntil { store.hasNoCamera && !store.isRunning }
        #expect(store.hasNoCamera)
        #expect(!store.isRunning)
        #expect(engine.stopCount > 0)
        store.stop()
    }

    @MainActor
    @Test func startupAndCameraSwitchReflectEngineResults() async {
        let engine = FakeMirrorEngine()
        let store = MirrorStore(
            engine: engine,
            authorizationStatus: { .authorized },
            availableCameras: {
                [.init(id: "built-in", name: "Built-in"), .init(id: "usb", name: "USB")]
            }
        )
        store.start()
        #expect(store.isStarting)
        #expect(!store.isRunning)
        #expect(engine.starts == ["built-in"])

        engine.finish(.success("built-in"), at: 0)
        await waitUntil { store.isRunning }
        #expect(store.isRunning)

        store.selectedCameraID = "usb"
        #expect(store.isStarting)
        #expect(!store.isRunning)
        #expect(engine.starts == ["built-in", "usb"])
        engine.finish(.failure(.input), at: 1)
        await waitUntil { store.failure != nil }
        #expect(!store.isRunning)
        #expect(store.failure == .input)
        #expect(engine.stopCount > 0)

        store.retry()
        #expect(engine.starts.last == "usb")
        store.stop()
    }

    @MainActor
    @Test func lateSuccessCannotReviveHiddenMirror() async {
        let engine = FakeMirrorEngine()
        let store = MirrorStore(
            engine: engine,
            authorizationStatus: { .authorized },
            availableCameras: { [.init(id: "built-in", name: "Built-in")] }
        )
        store.start()
        store.stop()
        let stopsBeforeReply = engine.stopCount
        engine.finish(.success("built-in"), at: 0)
        for _ in 0..<20 { await Task.yield() }
        #expect(!store.isRunning)
        #expect(!store.isStarting)
        #expect(engine.stopCount == stopsBeforeReply)
    }
}
