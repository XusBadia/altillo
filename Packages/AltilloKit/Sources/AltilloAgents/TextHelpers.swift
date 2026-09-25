import Foundation

/// Small text helpers shared by the parsers and the activity descriptions.
public enum ShellWords {
    /// `["/bin/zsh", "-lc", "swift test"]` → `swift test`; other argv arrays are joined, quoting words with spaces.
    public static func commandFromArgv(_ argv: [String]) -> String {
        if argv.count >= 3, let shell = argv.first.map({ URL(fileURLWithPath: $0).lastPathComponent }),
           ["sh", "bash", "zsh", "dash", "fish"].contains(shell), argv[argv.count - 2].hasPrefix("-"),
           argv[argv.count - 2].contains("c") {
            return argv[argv.count - 1]
        }
        return argv.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }
}

/// Codex `apply_patch` text ("*** Begin Patch / *** Update File: path …").
public enum PatchText {
    public static func files(in patch: String) -> [String] {
        var files: [String] = []
        for line in patch.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            for marker in ["*** Update File: ", "*** Add File: ", "*** Delete File: ", "*** Move to: "]
            where line.hasPrefix(marker) {
                let path = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty, !files.contains(path) { files.append(path) }
            }
        }
        return files
    }
}

extension String {
    /// The first non-empty line, trimmed and cut to `limit` characters with an ellipsis.
    public func firstLine(limit: Int = 80) -> String {
        let line = split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.truncated(limit)
    }

    /// Cut to `limit` characters with an ellipsis; whitespace runs collapse to one space.
    public func truncated(_ limit: Int) -> String {
        let collapsed = split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > limit, limit > 1 else { return collapsed }
        return String(collapsed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Path shown relative to `cwd` when inside it, else with `~` for the home folder.
    public func displayPath(relativeTo cwd: String?) -> String {
        if let cwd, !cwd.isEmpty {
            let base = cwd.hasSuffix("/") ? cwd : cwd + "/"
            if hasPrefix(base) { return String(dropFirst(base.count)) }
            // macOS reports /tmp as /private/tmp in some places and not others.
            for (a, b) in [("/private/tmp/", "/tmp/"), ("/tmp/", "/private/tmp/")] where hasPrefix(a) && base.hasPrefix(b) {
                let alt = b + dropFirst(a.count)
                if alt.hasPrefix(base) { return String(alt.dropFirst(base.count)) }
            }
        }
        let home = NSHomeDirectory()
        if hasPrefix(home + "/") { return "~" + dropFirst(home.count) }
        return self
    }

    public var fileName: String { (self as NSString).lastPathComponent }
}
