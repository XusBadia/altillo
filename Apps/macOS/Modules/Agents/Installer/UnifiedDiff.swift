import Foundation

/// A line-based unified diff (`diff -u` style), for showing the user exactly what the hook installer is about to
/// write before it writes anything. Config files are small, so a plain LCS table is plenty.
struct UnifiedDiff: Equatable, Sendable {
    enum Line: Equatable, Sendable {
        case context(String)
        case removed(String)
        case added(String)
    }

    struct Hunk: Equatable, Sendable {
        var oldStart: Int
        var oldCount: Int
        var newStart: Int
        var newCount: Int
        var lines: [Line]

        var header: String {
            "@@ -\(Self.range(oldStart, oldCount)) +\(Self.range(newStart, newCount)) @@"
        }

        private static func range(_ start: Int, _ count: Int) -> String {
            count == 1 ? "\(start)" : "\(start),\(count)"
        }
    }

    let oldName: String
    let newName: String
    let hunks: [Hunk]

    var isEmpty: Bool { hunks.isEmpty }
    var addedCount: Int { hunks.reduce(0) { $0 + $1.lines.filter { if case .added = $0 { true } else { false } }.count } }
    var removedCount: Int {
        hunks.reduce(0) { $0 + $1.lines.filter { if case .removed = $0 { true } else { false } }.count }
    }

    init(old: String, new: String, oldName: String = "a", newName: String = "b", context: Int = 3) {
        self.oldName = oldName
        self.newName = newName
        hunks = Self.hunks(Self.lines(old), Self.lines(new), context: context)
    }

    /// The whole diff as text, with `---`/`+++` headers. Empty when nothing changes.
    var text: String {
        guard !hunks.isEmpty else { return "" }
        var output = "--- \(oldName)\n+++ \(newName)\n"
        for hunk in hunks {
            output += hunk.header + "\n"
            for line in hunk.lines {
                switch line {
                case .context(let text): output += " \(text)\n"
                case .removed(let text): output += "-\(text)\n"
                case .added(let text): output += "+\(text)\n"
                }
            }
        }
        return output
    }

    private static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private enum Edit { case same(Int, Int), delete(Int), insert(Int) }

    private static func edits(_ old: [String], _ new: [String]) -> [Edit] {
        let n = old.count, m = new.count
        // lcs[i][j] = length of the LCS of old[i...] and new[j...].
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var edits: [Edit] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, old[i] == new[j] {
                edits.append(.same(i, j)); i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] > lcs[i + 1][j] {
                edits.append(.insert(j)); j += 1
            } else {
                edits.append(.delete(i)); i += 1
            }
        }
        // Removals before additions inside each changed run, as `diff -u` prints them.
        var ordered: [Edit] = []
        var run: [Edit] = []
        func flushRun() {
            ordered += run.filter { if case .delete = $0 { true } else { false } }
            ordered += run.filter { if case .insert = $0 { true } else { false } }
            run.removeAll()
        }
        for edit in edits {
            if case .same = edit { flushRun(); ordered.append(edit) } else { run.append(edit) }
        }
        flushRun()
        return ordered
    }

    private static func hunks(_ old: [String], _ new: [String], context: Int) -> [Hunk] {
        let edits = edits(old, new)
        let changed = edits.indices.filter { if case .same = edits[$0] { false } else { true } }
        guard !changed.isEmpty else { return [] }

        // Group changes whose context windows touch.
        var groups: [ClosedRange<Int>] = []
        for index in changed {
            let window = max(0, index - context)...min(edits.count - 1, index + context)
            if let last = groups.last, window.lowerBound <= last.upperBound + 1 {
                groups[groups.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                groups.append(window)
            }
        }

        return groups.map { range in
            var lines: [Line] = []
            var oldStart: Int?
            var newStart: Int?
            var oldCount = 0, newCount = 0
            // Positions before the hunk, for empty sides (`-0,0`).
            var oldCursor = 0, newCursor = 0
            for edit in edits[..<range.lowerBound] {
                switch edit {
                case .same: oldCursor += 1; newCursor += 1
                case .delete: oldCursor += 1
                case .insert: newCursor += 1
                }
            }
            for edit in edits[range] {
                switch edit {
                case .same(let i, let j):
                    lines.append(.context(old[i]))
                    oldStart = oldStart ?? i + 1; newStart = newStart ?? j + 1
                    oldCount += 1; newCount += 1
                case .delete(let i):
                    lines.append(.removed(old[i]))
                    oldStart = oldStart ?? i + 1
                    oldCount += 1
                case .insert(let j):
                    lines.append(.added(new[j]))
                    newStart = newStart ?? j + 1
                    newCount += 1
                }
            }
            return Hunk(oldStart: oldStart ?? oldCursor, oldCount: oldCount,
                        newStart: newStart ?? newCursor, newCount: newCount, lines: lines)
        }
    }
}
