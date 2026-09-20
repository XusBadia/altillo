import Foundation
import Observation
import ServiceManagement

/// User settings, stored in `UserDefaults` and shared by the notch and the Settings window.
@MainActor
@Observable
final class AltilloSettings {
    static let shared = AltilloSettings(loginItem: .system)

    /// Width of the open notch. Narrow by default: it should take as little room as possible.
    var openWidth: Double {
        didSet {
            let clamped = openWidth.clamped(to: Self.widthRange)
            guard clamped == openWidth else { openWidth = clamped; return }
            defaults.set(clamped, forKey: Key.openWidth)
        }
    }

    /// Modules shown in the notch, in order. The shelf is always first (`NotchModule.isAlwaysOn`).
    var modules: [NotchModule] {
        didSet { defaults.set(modules.map(\.rawValue), forKey: Key.modules) }
    }

    /// Open the notch on a sustained hover instead of requiring a click.
    var opensOnHover: Bool {
        didSet { defaults.set(opensOnHover, forKey: Key.opensOnHover) }
    }

    /// Start Altillo when the user logs in. Mirrors the real `SMAppService` status.
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            guard !isSyncingLoginItem else { return }
            do {
                try loginItem.setRegistered(launchAtLogin)
                launchAtLoginProblem = nil
            } catch {
                launchAtLoginProblem = launchAtLogin
                    ? "No se ha podido activar. Prueba a mover Altillo a la carpeta Aplicaciones."
                    : "No se ha podido desactivar. Quítalo en Ajustes del Sistema › General › Ítems de inicio."
                revertLaunchAtLogin(to: oldValue)
            }
        }
    }

    /// Set when registering or unregistering the login item failed; shown next to the toggle.
    private(set) var launchAtLoginProblem: String?

    /// Show the "drop something up here" hint while the shelf is empty.
    var showHintOnEmptyShelf: Bool {
        didSet { defaults.set(showHintOnEmptyShelf, forKey: Key.showHintOnEmptyShelf) }
    }

    /// How long items stay in the shelf before Altillo clears them.
    var shelfExpiry: ShelfExpiry {
        didSet { defaults.set(shelfExpiry.rawValue, forKey: Key.shelfExpiry) }
    }

    static let widthRange: ClosedRange<Double> = 440...760
    static let widthPresets: [(name: String, value: Double)] = [("Estrecho", 480), ("Medio", 560), ("Ancho", 680)]
    /// Everything on by default: sections are easier to discover in the notch than in Settings.
    static let defaultModules: [NotchModule] = NotchModule.allCases

    private let defaults: UserDefaults
    private let loginItem: LoginItem
    /// Guards `launchAtLogin` writes that only mirror the system, so they never register anything back.
    private var isSyncingLoginItem = false

    private enum Key {
        static let openWidth = "openWidth"
        static let modules = "modules"
        static let opensOnHover = "opensOnHover"
        static let launchAtLogin = "launchAtLogin"
        static let showHintOnEmptyShelf = "showHintOnEmptyShelf"
        static let shelfExpiry = "shelfExpiry"
    }

    init(defaults: UserDefaults = .standard, loginItem: LoginItem = .unmanaged) {
        self.defaults = defaults
        self.loginItem = loginItem
        let width = defaults.double(forKey: Key.openWidth)
        openWidth = width > 0 ? width.clamped(to: Self.widthRange) : 560
        let stored = (defaults.array(forKey: Key.modules) as? [String])?.compactMap(NotchModule.init)
        modules = Self.normalise(stored ?? Self.defaultModules)
        opensOnHover = defaults.object(forKey: Key.opensOnHover) as? Bool ?? true
        let rememberedLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        // The system is the source of truth: the user may have changed it in System Settings.
        launchAtLogin = loginItem.isManaged ? loginItem.isRegistered() : rememberedLogin
        showHintOnEmptyShelf = defaults.object(forKey: Key.showHintOnEmptyShelf) as? Bool ?? true
        shelfExpiry = (defaults.string(forKey: Key.shelfExpiry).flatMap(ShelfExpiry.init)) ?? .never
    }

    func isEnabled(_ module: NotchModule) -> Bool { modules.contains(module) }

    func setEnabled(_ module: NotchModule, _ enabled: Bool) {
        guard !module.isAlwaysOn else { return }
        if enabled {
            guard !modules.contains(module) else { return }
            modules.append(module)
        } else {
            modules.removeAll { $0 == module }
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var updated = modules
        updated.move(fromOffsets: source, toOffset: destination)
        modules = Self.normalise(updated)
    }

    /// Re-reads the login item status (it can change in System Settings while Altillo runs).
    func refreshLaunchAtLogin() {
        guard loginItem.isManaged else { return }
        let registered = loginItem.isRegistered()
        guard registered != launchAtLogin else { return }
        isSyncingLoginItem = true
        launchAtLogin = registered
        isSyncingLoginItem = false
    }

    private func revertLaunchAtLogin(to value: Bool) {
        isSyncingLoginItem = true
        launchAtLogin = value
        isSyncingLoginItem = false
    }

    /// Always-on modules first, no duplicates, nothing unknown.
    private static func normalise(_ modules: [NotchModule]) -> [NotchModule] {
        var seen = Set<NotchModule>()
        let unique = modules.filter { seen.insert($0).inserted }
        let alwaysOn = NotchModule.allCases.filter(\.isAlwaysOn)
        return alwaysOn + unique.filter { !$0.isAlwaysOn }
    }
}

// MARK: - Shelf expiry

/// How long the shelf keeps what you leave up there. Used by the shelf module.
enum ShelfExpiry: String, CaseIterable, Identifiable, Codable, Sendable {
    case never, day, week

    var id: Self { self }

    /// Label in Settings.
    var title: String {
        switch self {
        case .never: "Nunca"
        case .day: "Al cabo de un día"
        case .week: "Al cabo de una semana"
        }
    }

    /// How long an item survives, or `nil` if it stays forever.
    var duration: TimeInterval? {
        switch self {
        case .never: nil
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        }
    }
}

// MARK: - Login item

/// The "open at login" registration, injected so tests never touch the real `SMAppService`.
struct LoginItem: Sendable {
    /// False for the test/preview double: then the stored preference is the source of truth.
    var isManaged: Bool
    var isRegistered: @Sendable () -> Bool
    var setRegistered: @Sendable (Bool) throws -> Void

    /// The real login item of Altillo.app.
    @MainActor static let system = LoginItem(
        isManaged: true,
        isRegistered: { SMAppService.mainApp.status == .enabled },
        setRegistered: { enabled in
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return }
                try SMAppService.mainApp.unregister()
            }
        }
    )

    /// Remembers the preference without touching the system. Default for injected instances.
    static let unmanaged = LoginItem(isManaged: false, isRegistered: { false }, setRegistered: { _ in })
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
