import Foundation
import Observation

/// User settings, stored in `UserDefaults` and shared by the notch and the Settings window.
@MainActor
@Observable
final class AltilloSettings {
    static let shared = AltilloSettings()

    /// Width of the open notch. Narrow by default: it should take as little room as possible.
    var openWidth: Double {
        didSet { defaults.set(openWidth.clamped(to: Self.widthRange), forKey: Key.openWidth) }
    }

    /// Modules shown in the notch, in order. The shelf is always first (`NotchModule.isAlwaysOn`).
    var modules: [NotchModule] {
        didSet { defaults.set(modules.map(\.rawValue), forKey: Key.modules) }
    }

    /// Open the notch on a sustained hover instead of requiring a click.
    var opensOnHover: Bool {
        didSet { defaults.set(opensOnHover, forKey: Key.opensOnHover) }
    }

    static let widthRange: ClosedRange<Double> = 440...760
    static let widthPresets: [(name: String, value: Double)] = [("Estrecho", 480), ("Medio", 560), ("Ancho", 680)]
    static let defaultModules: [NotchModule] = [.shelf, .usage, .agents]

    private let defaults: UserDefaults

    private enum Key {
        static let openWidth = "openWidth"
        static let modules = "modules"
        static let opensOnHover = "opensOnHover"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let width = defaults.double(forKey: Key.openWidth)
        openWidth = width > 0 ? width.clamped(to: Self.widthRange) : 560
        let stored = (defaults.array(forKey: Key.modules) as? [String])?.compactMap(NotchModule.init)
        modules = Self.normalise(stored ?? Self.defaultModules)
        opensOnHover = defaults.object(forKey: Key.opensOnHover) as? Bool ?? true
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

    /// Always-on modules first, no duplicates, nothing unknown.
    private static func normalise(_ modules: [NotchModule]) -> [NotchModule] {
        var seen = Set<NotchModule>()
        let unique = modules.filter { seen.insert($0).inserted }
        let alwaysOn = NotchModule.allCases.filter(\.isAlwaysOn)
        return alwaysOn + unique.filter { !$0.isAlwaysOn }
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
