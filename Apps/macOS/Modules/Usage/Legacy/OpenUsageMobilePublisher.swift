import AltilloCore
import AppKit
import Foundation
import OSLog
import Security

/// Writes the legacy `openusage.mobile.v1` file for the old TestFlight iPhone app into the iCloud container it
/// reads (`iCloud.me.badia.ailimits`, root → OpenUsage/Mobile/v1/<deviceID>.json), replacing the OpenUsage Mobile
/// Bridge and its launchd watchdog (PLAN §5.2, docs/uso-ia.md).
///
/// Only a release build can do this: it needs the iCloud entitlements and the Developer ID provisioning profile
/// that `script/release.sh` adds (docs/release.md). Everywhere else `isEnabled` is false and nothing happens.
/// It never writes by raw path into ~/Library/Mobile Documents: no container URL from the system, no file.
@MainActor
final class OpenUsageMobilePublisher: UsageSnapshotPublisher {
    nonisolated static let containerIdentifier = "iCloud.me.badia.ailimits"
    /// User setting (Bool, default on). Settings can bind a toggle to it.
    nonisolated static let enabledKey = "legacyMobileExport"
    /// The device id this Mac writes under. Persisted so the phone keeps seeing one Mac.
    nonisolated static let deviceIDKey = "legacyMobileExport.deviceID"
    /// Where the bridge kept its id (defaults domain of me.badia.ailimits.collector). Reusing it makes Altillo
    /// take over the bridge's file instead of showing a second Mac on the phone.
    nonisolated static let bridgeDefaultsDomain = "me.badia.ailimits.collector"
    nonisolated static let bridgeDeviceIDKeys = ["openusage.mobileBridge.deviceID.v1", "openusage.icloudSync.deviceID.v1"]

    private nonisolated static let logger = Logger(subsystem: "me.badia.altillo", category: "LegacyMobileExport")

    private let defaults: UserDefaults
    private let debounce: Duration
    private let writer: OpenUsageMobileWriter
    private var pending: Task<Void, Never>?
    let deviceID: String

    init(defaults: UserDefaults = .standard, debounce: Duration = .seconds(3)) {
        self.defaults = defaults
        self.debounce = debounce
        writer = OpenUsageMobileWriter(containerIdentifier: Self.containerIdentifier)
        deviceID = Self.resolveDeviceID(defaults: defaults)
    }

    /// The user setting (default on).
    var isSettingOn: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Signed with the iCloud entitlement for the legacy container and signed in to iCloud. Both checks are cheap
    /// and safe on the main thread; the container URL itself is resolved off the main actor by the writer.
    var isContainerReachable: Bool {
        Self.hasContainerEntitlement && FileManager.default.ubiquityIdentityToken != nil
    }

    var isEnabled: Bool { isSettingOn && isContainerReachable }

    func publish(_ snapshot: UsageSnapshot) {
        guard isEnabled else { return }
        pending?.cancel()
        let writer = writer, deviceID = deviceID, debounce = debounce
        pending = Task.detached(priority: .utility) {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let document = OpenUsageMobileExport.document(from: snapshot, deviceID: deviceID)
            do {
                let url = try await writer.write(document)
                Self.logger.debug("Legacy mobile export written to \(url.path, privacy: .public)")
            } catch {
                Self.logger.error("Legacy mobile export failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Device id

    static func resolveDeviceID(defaults: UserDefaults) -> String {
        if let saved = defaults.string(forKey: deviceIDKey), OpenUsageMobileDocument.isValidIdentifier(saved) {
            return saved
        }
        let id = bridgeDeviceID() ?? UUID().uuidString.lowercased()
        defaults.set(id, forKey: deviceIDKey)
        return id
    }

    /// The bridge's id, read-only from its preferences (Altillo isn't sandboxed). Nil when the bridge never ran.
    nonisolated static func bridgeDeviceID() -> String? {
        for key in bridgeDeviceIDKeys {
            if let value = CFPreferencesCopyAppValue(key as CFString, bridgeDefaultsDomain as CFString) as? String,
               OpenUsageMobileDocument.isValidIdentifier(value) {
                return value
            }
        }
        return nil
    }

    // MARK: - Entitlement

    nonisolated static let hasContainerEntitlement: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-container-identifiers" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains { $0.hasSuffix(containerIdentifier) } ?? false
    }()
}

/// Coordinated, atomic writes into the ubiquity container, off the main actor.
actor OpenUsageMobileWriter {
    enum WriteError: Error {
        case containerUnavailable
    }

    let containerIdentifier: String
    private var containerURL: URL?

    init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    /// `url(forUbiquityContainerIdentifier:)` can block (it may create the container on first use), so it only
    /// ever runs here. Nil without the entitlement or iCloud Drive.
    func container() -> URL? {
        if let containerURL { return containerURL }
        containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)
        return containerURL
    }

    func fileURL(deviceID: String) throws -> URL {
        guard let root = container() else { throw WriteError.containerUnavailable }
        return root.appending(path: "OpenUsage/Mobile/v1", directoryHint: .isDirectory)
            .appending(path: "\(deviceID).json", directoryHint: .notDirectory)
    }

    @discardableResult
    func write(_ document: OpenUsageMobileDocument) throws -> URL {
        let data = try document.encoded()
        let url = try fileURL(deviceID: document.deviceID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinate(url, options: .forReplacing) { try data.write(to: $0, options: .atomic) }
        return url
    }

    /// Removes this device's file (coordinated, so iCloud propagates the deletion).
    func delete(deviceID: String) throws {
        let url = try fileURL(deviceID: deviceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try coordinate(url, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
    }

    private func coordinate(_ url: URL, options: NSFileCoordinator.WritingOptions,
                            _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
            do { try body(url) } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }
}

// MARK: - Self-test (release verification)

extension OpenUsageMobilePublisher {
    /// `open -n Altillo.app --args -legacyMobileExportSelfTest <test-device-id>` writes a sample document under that
    /// id, `-legacyMobileExportSelfTestDelete <test-device-id>` removes it again; either way the app then quits.
    /// The outcome goes to ~/Library/Logs/Altillo/legacy-mobile-export-selftest.json. Used by docs/release.md to
    /// prove a signed build reaches the container. Returns true when it took over the launch.
    static func runSelfTestIfRequested(defaults: UserDefaults = .standard) -> Bool {
        let writeID = defaults.string(forKey: "legacyMobileExportSelfTest")
        let deleteID = defaults.string(forKey: "legacyMobileExportSelfTestDelete")
        guard let deviceID = writeID ?? deleteID else { return false }
        let deleting = writeID == nil
        let hasEntitlement = hasContainerEntitlement
        let signedIn = FileManager.default.ubiquityIdentityToken != nil
        Task.detached {
            let writer = OpenUsageMobileWriter(containerIdentifier: containerIdentifier)
            var report: [String: String] = [
                "mode": deleting ? "delete" : "write",
                "deviceID": deviceID,
                "hasEntitlement": String(hasEntitlement),
                "iCloudSignedIn": String(signedIn),
                "date": ISO8601DateFormatter().string(from: .now),
            ]
            let container = await writer.container()
            report["containerURL"] = container?.path ?? "nil"
            do {
                if deleting {
                    try await writer.delete(deviceID: deviceID)
                    report["result"] = "deleted"
                } else {
                    let snapshot = UsageSnapshot(deviceID: deviceID, deviceName: "Altillo self-test", updatedAt: .now,
                                                 providers: [selfTestProvider()])
                    let url = try await writer.write(OpenUsageMobileExport.document(from: snapshot, deviceID: deviceID))
                    report["result"] = "written"
                    report["file"] = url.path
                }
            } catch {
                report["result"] = "error"
                report["error"] = String(describing: error)
            }
            let logs = URL.libraryDirectory.appending(path: "Logs/Altillo", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let data = (try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            try? data.write(to: logs.appending(path: "legacy-mobile-export-selftest.json"), options: .atomic)
            await MainActor.run { NSApp.terminate(nil) }
        }
        return true
    }

    private nonisolated static func selfTestProvider() -> ProviderUsage {
        ProviderUsage(id: .claude, displayName: "Claude", plan: "Self-test",
                      windows: [UsageWindow(id: "session", kind: .session, label: "Session", used: 0.01,
                                            resetsAt: .now.addingTimeInterval(3_600), duration: 5 * 3_600)],
                      fetchedAt: .now)
    }
}
