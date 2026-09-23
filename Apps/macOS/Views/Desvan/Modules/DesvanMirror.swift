import AVFoundation
import AltilloDesign
import SwiftUI

/// The mirror tab: the Mac's camera inside a wooden frame, like the little mirror by the attic door.
///
/// The camera only runs while this view is on screen: `onAppear` starts the session, `onDisappear` stops it, and
/// the store itself also stops on sleep and on quit. The light goes out the moment you look away.
struct DesvanMirrorView: View {
    let model: NotchModel

    private var store: MirrorStore { model.mirror }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { store.start() }
            .onDisappear { store.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if store.hasNoCamera {
            // Checked before the permission: a Mac mini has nothing to show whatever TCC says.
            DesvanModuleNotice(
                symbol: "questionmark.video",
                title: "I can't find a camera",
                message: "Plug one in, or bring your iPhone close to use it as a Continuity Camera."
            )
        } else {
            permissioned
        }
    }

    @ViewBuilder
    private var permissioned: some View {
        switch store.access {
        case .granted:
            mirror
        case .unknown:
            DesvanModuleNotice(
                symbol: "person.crop.square",
                title: "Want a quick look at yourself?",
                message: "The mirror shows the Mac's camera up here. The image never leaves your Mac and is never recorded.",
                actionTitle: "Turn the camera on"
            ) {
                Task { await store.requestAccess() }
            }
        case .denied:
            DesvanModuleNotice(
                symbol: "video.slash",
                title: "The camera is off",
                message: "Altillo doesn't have permission to use it. Turn it on in System Settings and open the notch again.",
                actionTitle: "Open Settings"
            ) {
                PrivacySettings.camera.open()
            }
        }
    }

    private var mirror: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            frame
            controls
            Spacer(minLength: 0)
        }
    }

    /// The looking glass: the picture set into a wooden frame, with the bulb catching its top edge.
    private var frame: some View {
        Group {
            if let session = store.session, store.isRunning {
                DesvanCameraPreview(session: session, isMirrored: store.isMirrored, cornerRadius: 8)
            } else {
                // Warming up: the glass before the image arrives.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Desvan.Palette.woodRaised)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Desvan.Palette.paperSecondary)
                    }
            }
        }
        .frame(width: 158, height: 88)
        .padding(5)
        .desvanCard(radius: 13)
        .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.isMirrored
            ? "Mirror: the Mac's camera, flipped like a mirror"
            : "Mirror: the Mac's camera, not flipped")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                store.flip()
            } label: {
                Label(store.isMirrored ? "Mirrored" : "As it is", systemImage: "arrow.left.and.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 24))
            .help("Flip the image left to right")
            .accessibilityHint("Switches between the flipped, mirror-like image and the image as it is")

            if store.cameras.count > 1 {
                Menu {
                    ForEach(store.cameras) { camera in
                        Button {
                            store.selectedCameraID = camera.id
                        } label: {
                            if camera.id == store.selectedCameraID {
                                Label(camera.name, systemImage: "checkmark")
                            } else {
                                Text(camera.name)
                            }
                        }
                    }
                } label: {
                    Label(currentCameraName, systemImage: "camera")
                }
                .menuStyle(.button)
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 24))
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose camera")
            } else if let name = store.cameras.first?.name {
                Label(name, systemImage: "camera")
                    .font(Desvan.Typeface.rounded(11, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
                    .padding(.leading, 2)
            }
        }
        .frame(maxWidth: 180, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var currentCameraName: String {
        store.cameras.first { $0.id == store.selectedCameraID }?.name ?? String(localized: "Camera")
    }
}

// MARK: - Preview layer

/// `AVCaptureVideoPreviewLayer` in an `NSView`. SwiftUI has no native camera view on macOS, and this is the only
/// way the picture renders inside a non-activating `NSPanel`: the layer draws itself, no key window needed.
struct DesvanCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool
    var cornerRadius: CGFloat = 8

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(cornerRadius: cornerRadius)
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.attach(session: session, mirrored: isMirrored)
    }

    final class PreviewView: NSView {
        private let preview = AVCaptureVideoPreviewLayer()

        init(cornerRadius: CGFloat) {
            super.init(frame: .zero)
            wantsLayer = true
            let host = CALayer()
            host.backgroundColor = NSColor.black.cgColor
            host.cornerRadius = cornerRadius
            host.cornerCurve = .continuous
            // Clipping here rather than with `.clipShape` in SwiftUI: a capture layer ignores SwiftUI's mask.
            host.masksToBounds = true
            layer = host
            layerContentsRedrawPolicy = .onSetNeedsDisplay
            preview.videoGravity = .resizeAspectFill
            host.addSublayer(preview)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            // No implicit animation: the layer would slide on every resize of the notch.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview.frame = bounds
            CATransaction.commit()
        }

        func attach(session: AVCaptureSession, mirrored: Bool) {
            if preview.session !== session { preview.session = session }
            guard let connection = preview.connection, connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}
