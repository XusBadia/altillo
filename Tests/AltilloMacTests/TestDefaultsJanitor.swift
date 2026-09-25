import Foundation

/// Tests make throwaway `UserDefaults` suites (`me.badia.altillo.tests.*`) so they never touch the user's settings.
/// `removePersistentDomain` empties a suite but leaves its plist behind, so without this the user's
/// ~/Library/Preferences collects thousands of files. Once per test run, stale ones from earlier runs go away.
enum TestDefaultsJanitor {
    static func purgeStale() { _ = purgeOnce }

    private static let purgeOnce: Void = {
        let fileManager = FileManager.default
        let folder = fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Preferences")
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return }
        // Older than a few minutes: another test process running right now keeps its own files.
        let cutoff = Date.now.addingTimeInterval(-10 * 60)
        for name in names where name.hasPrefix("me.badia.altillo.tests.") && name.hasSuffix(".plist") {
            let file = folder.appending(path: name)
            let modified = (try? fileManager.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? .distantPast
            if modified < cutoff { try? fileManager.removeItem(at: file) }
        }
    }()
}
