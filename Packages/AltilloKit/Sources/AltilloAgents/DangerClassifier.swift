import Foundation

// Danger classifier for shell commands and file writes (PLAN §5.3). Altillo never auto-approves anything — this
// only decides whether a pending permission request gets an extra "are you sure?" in the UI. Called on every
// permission request, so it has to be fast and it must never crash, no matter what garbage a model hands it
// (empty strings, megabyte one-liners, unterminated quotes, emoji). False positives are fine; a miss on one of
// the listed patterns is not.

/// Why a command or file write got flagged. Just a reason string today; kept as a struct so the UI has a stable
/// type to switch on if we ever want severity levels.
public struct DangerAssessment: Hashable, Sendable {
    /// Short English reason for the UI, e.g. "Deletes files recursively", "Force-pushes git history".
    public var reason: String
    public init(reason: String) { self.reason = reason }
}

public enum DangerClassifier {

    // MARK: - Public API

    /// Classifies a shell command line. Splits on unquoted `;`, `&&`, `||`, `&` and newlines into pipe chains,
    /// each of which is further split on unquoted `|` into segments (kept grouped, since "piped into a shell"
    /// is a property of the *chain*, not of any one segment). Also recurses into `$(...)`/backtick subshells and
    /// `-c` shell-wrapper strings as full command lines of their own. Returns the first match (severity order
    /// doesn't matter here: any match is "ask again").
    public static func assess(command: String, cwd: String?) -> DangerAssessment? {
        assess(command: command, cwd: cwd, depth: 0)
    }

    /// Recursion depth cap for subshell/`-c` recursion. A real command is never nested this deep; this is only
    /// here so a pathologically nested input (`$(...)` inside `$(...)` inside …, or `bash -c "bash -c \"...\""`)
    /// can't blow the call stack — "never crash on any input" includes adversarial input, not just weird-but-
    /// valid ones.
    private static let maxRecursionDepth = 24

    private static func assess(command: String, cwd: String?, depth: Int) -> DangerAssessment? {
        // Guard against pathological input up front; nothing legitimate needs more than this to express a
        // dangerous command, and it keeps tokenization bounded on huge pastes.
        let command = command.count > 20_000 ? String(command.prefix(20_000)) : command
        guard !command.isEmpty else { return nil }
        guard depth < maxRecursionDepth else { return nil }

        // Fork bombs (`:(){ :|:& };:`) are made entirely of the separators we're about to split on (`;`, `&`,
        // `|`), so they have to be recognized on the raw text before splitting, not after.
        if let hit = ForkBombRule.assessRaw(command) {
            return hit
        }

        let parsed = CommandSplitter.parse(command)

        for subshell in parsed.subshellCommands {
            if let hit = assess(command: subshell, cwd: cwd, depth: depth + 1) {
                return hit
            }
        }
        for chain in parsed.pipeChains {
            if let hit = PipeToShellRule.assessPipeline(chain) {
                return hit
            }
            for segment in chain {
                if let hit = assessSegment(segment, cwd: cwd, depth: depth) {
                    return hit
                }
            }
        }
        return nil
    }

    /// Classifies a file the agent wants to write, edit, or delete.
    public static func assessFileWrite(path: String, cwd: String?) -> DangerAssessment? {
        guard !path.isEmpty else { return nil }
        return FileWriteRule.assess(path: path, cwd: cwd)
    }

    // MARK: - Segment classification

    /// One `;`/`&&`/`||`/`|`/`&`/newline-separated segment, already stripped of its own subshells (those are
    /// classified separately by the splitter). Tokenizes the segment, peels off assignments/wrappers, and runs
    /// the rule table.
    private static func assessSegment(_ segment: String, cwd: String?, depth: Int) -> DangerAssessment? {
        var tokens = Tokenizer.tokenize(segment)
        guard !tokens.isEmpty else { return nil }

        // Peel leading `VAR=value` environment assignments (e.g. `FOO=bar rm -rf /`).
        while let first = tokens.first, isAssignment(first) {
            tokens.removeFirst()
        }
        guard !tokens.isEmpty else { return nil }

        // Peel benign prefix commands that just wrap the real one: sudo/doas (also handled as their own rule
        // below, so peeling them still lets the inner command be checked), env, command, xargs, nice, time.
        // `xargs` is special-cased separately because `xargs rm -rf` needs the xargs rule, not a peel-and-recurse.
        if let hit = PrefixRule.assess(tokens: tokens, cwd: cwd) {
            return hit
        }
        tokens = PrefixRule.stripBenignPrefixes(tokens)
        guard let head = tokens.first else { return nil }

        // Shell-wrapper recursion: `bash -c '...'`, `sh -c "..."`, `zsh -c '...'` — classify the inner string as
        // a full command line (it may itself contain `&&`, subshells, etc.).
        if let inner = ShellWrapperRule.innerCommand(tokens: tokens) {
            if let hit = assess(command: inner, cwd: cwd, depth: depth + 1) {
                return hit
            }
        }

        // Rule table, roughly ordered by how often each shows up so common cases return fast. Called directly
        // (rather than through a `[(String, [String]) -> DangerAssessment?]` array) because several rules need
        // `cwd` and Swift can't unify those closures with the cwd-less ones into one array type.
        let tail = Array(tokens.dropFirst())
        if let hit = RmRule.rm(head: head, tail: tail, cwd: cwd) { return hit }
        if let hit = GitRule.assess(head: head, tail: tail) { return hit }
        if let hit = SudoRule.assess(head: head, tail: tail) { return hit }
        if let hit = ChmodChownRule.chmodChown(head: head, tail: tail, cwd: cwd) { return hit }
        if let hit = DiskRule.assess(head: head, tail: tail) { return hit }
        if let hit = PipeToShellRule.assess(head: head, tail: tail) { return hit }
        if let hit = SQLRule.assess(head: head, tail: tail) { return hit }
        if let hit = RedirectRule.assess(head: head, tail: tail, cwd: cwd) { return hit }
        if let hit = MoveCopyRule.assess(head: head, tail: tail, cwd: cwd) { return hit }
        if let hit = ProcessControlRule.assess(head: head, tail: tail) { return hit }
        if let hit = FindXargsRule.assess(head: head, tail: tail) { return hit }
        if let hit = PublishDestroyRule.assess(head: head, tail: tail) { return hit }

        return nil
    }

    private static func isAssignment(_ token: String) -> Bool {
        guard let eq = token.firstIndex(of: "=") else { return false }
        let name = token[token.startIndex..<eq]
        guard !name.isEmpty else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } && !(name.first?.isNumber ?? true)
    }
}

// MARK: - Tokenizer

/// A tiny shell-ish tokenizer: splits on whitespace, honours single/double quotes (no expansion inside single
/// quotes; backslash escapes inside double quotes and bare text) and backslash escapes outside quotes. It does
/// NOT do real shell parsing (no globbing, no variable expansion) — it only needs to recover argv-shaped tokens
/// well enough to recognize flags and paths. Never throws; unbalanced quotes just run to end of string.
enum Tokenizer {
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var chars = Substring(text)

        func flush() {
            if hasCurrent {
                tokens.append(current)
                current = ""
                hasCurrent = false
            }
        }

        while let ch = chars.first {
            switch ch {
            case " ", "\t", "\n", "\r":
                flush()
                chars.removeFirst()
            case "'":
                hasCurrent = true
                chars.removeFirst()
                while let c = chars.first, c != "'" {
                    current.append(c)
                    chars.removeFirst()
                }
                if !chars.isEmpty { chars.removeFirst() } // closing quote, if present
            case "\"":
                hasCurrent = true
                chars.removeFirst()
                while let c = chars.first, c != "\"" {
                    if c == "\\", let next = chars.dropFirst().first, next == "\"" || next == "\\" || next == "$" {
                        current.append(next)
                        chars.removeFirst(2)
                    } else {
                        current.append(c)
                        chars.removeFirst()
                    }
                }
                if !chars.isEmpty { chars.removeFirst() } // closing quote, if present
            case "\\":
                hasCurrent = true
                chars.removeFirst()
                if let c = chars.first {
                    current.append(c)
                    chars.removeFirst()
                }
            default:
                hasCurrent = true
                current.append(ch)
                chars.removeFirst()
            }
        }
        flush()
        return tokens
    }
}

// MARK: - Command splitter

/// Splits a command line into pipe chains (separated by unquoted `;`, `&&`, `||`, single `&`, or newlines), each
/// itself an ordered list of segments (separated by unquoted `|`) — the grouping is kept because "piped into a
/// shell" is a property of a whole chain, not any one segment. Anything inside `$(...)` or backtick subshells is
/// pulled out separately as a full command line to recurse into. Quote-aware (mirrors the tokenizer's quoting
/// rules) so separators inside strings are never split on. Never throws; unbalanced quotes/parens just run to
/// end of string.
enum CommandSplitter {
    struct Parsed {
        var pipeChains: [[String]] = []
        var subshellCommands: [String] = []
    }

    static func parse(_ text: String) -> Parsed {
        var result = Parsed()
        var currentChain: [String] = []
        var current = ""
        var chars = Substring(text)

        func flushSegment() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { currentChain.append(trimmed) }
            current = ""
        }
        func flushChain() {
            flushSegment()
            if !currentChain.isEmpty { result.pipeChains.append(currentChain) }
            currentChain = []
        }

        while let ch = chars.first {
            switch ch {
            case "'":
                // Single quotes are fully literal in the shell: no `$(...)`/backtick expansion inside them.
                current.append(ch)
                chars.removeFirst()
                while let c = chars.first, c != "'" {
                    current.append(c)
                    chars.removeFirst()
                }
                if !chars.isEmpty { current.append(chars.removeFirst()) }
            case "\"":
                // Double quotes suppress word-splitting/globbing but NOT command substitution — `$(...)` and
                // backticks still run inside `"..."`, so we still have to watch for them here.
                current.append(ch)
                chars.removeFirst()
                consumeDoubleQuotedBody(&chars, into: &current, subshells: &result.subshellCommands)
            case "\\":
                current.append(ch)
                chars.removeFirst()
                if let c = chars.first {
                    current.append(c)
                    chars.removeFirst()
                }
            case "`":
                // Backtick subshell: keep its contents in the enclosing segment too (so e.g. `rm `echo -rf`` is
                // still visible as text there), and ALSO recurse into it as a standalone command line.
                current.append(ch)
                chars.removeFirst()
                let inner = consumeBacktickBody(&chars, into: &current)
                result.subshellCommands.append(inner)
            case "$" where chars.dropFirst().first == "(":
                current.append(ch)
                chars.removeFirst()
                current.append(chars.removeFirst()) // "("
                let inner = consumeParenBody(&chars, into: &current)
                result.subshellCommands.append(inner)
            case ";", "\n", "\r":
                flushChain()
                chars.removeFirst()
            case "&":
                // `&&` (and) or a lone `&` (background) both end the chain here; `&>` redirection is handled by
                // the tokenizer/redirect rule inside a segment, not at this top level.
                flushChain()
                chars.removeFirst()
                if chars.first == "&" { chars.removeFirst() }
            case "|":
                flushSegment()
                chars.removeFirst()
                if chars.first == "|" {
                    // `||`: also ends the chain (it's not a data pipe).
                    chars.removeFirst()
                    if !currentChain.isEmpty { result.pipeChains.append(currentChain) }
                    currentChain = []
                }
            default:
                current.append(ch)
                chars.removeFirst()
            }
        }
        flushChain()
        return result
    }

    /// Consumes a double-quoted string's body (the opening `"` was already consumed), appending everything —
    /// including subshell markup — to `current` verbatim, while also collecting any `$(...)`/backtick contents
    /// into `subshells` since those still execute inside double quotes. Consumes the closing `"` too, if present.
    private static func consumeDoubleQuotedBody(_ chars: inout Substring, into current: inout String,
                                                 subshells: inout [String]) {
        while let c = chars.first, c != "\"" {
            if c == "\\", let next = chars.dropFirst().first {
                current.append(c)
                current.append(next)
                chars.removeFirst(2)
                continue
            }
            if c == "`" {
                current.append(c)
                chars.removeFirst()
                let inner = consumeBacktickBody(&chars, into: &current)
                subshells.append(inner)
                continue
            }
            if c == "$", chars.dropFirst().first == "(" {
                current.append(c)
                chars.removeFirst()
                current.append(chars.removeFirst()) // "("
                let inner = consumeParenBody(&chars, into: &current)
                subshells.append(inner)
                continue
            }
            current.append(c)
            chars.removeFirst()
        }
        if !chars.isEmpty { current.append(chars.removeFirst()) } // closing quote, if present
    }

    /// Consumes a backtick subshell's body (the opening `` ` `` was already consumed), returning its raw
    /// contents and also appending them (plus the closing backtick, if present) to `current`.
    private static func consumeBacktickBody(_ chars: inout Substring, into current: inout String) -> String {
        var inner = ""
        while let c = chars.first, c != "`" {
            inner.append(c)
            current.append(c)
            chars.removeFirst()
        }
        if !chars.isEmpty { current.append(chars.removeFirst()) }
        return inner
    }

    /// Consumes a `$(...)` subshell's body (the opening `$(` was already consumed), honouring nested parens,
    /// returning its raw contents and also appending them (plus the closing `)`, if present) to `current`.
    private static func consumeParenBody(_ chars: inout Substring, into current: inout String) -> String {
        var inner = ""
        var depth = 1
        while let c = chars.first, depth > 0 {
            if c == "(" { depth += 1 }
            if c == ")" {
                depth -= 1
                if depth == 0 {
                    current.append(chars.removeFirst())
                    break
                }
            }
            inner.append(c)
            current.append(c)
            chars.removeFirst()
        }
        return inner
    }
}

// MARK: - Path helpers

enum PathHelper {
    /// Standardizes a path against `cwd` (resolving `~`, `..`, `.` and making it absolute), without touching the
    /// filesystem.
    static func standardized(_ path: String, cwd: String?) -> String {
        var p = path
        if p.hasPrefix("~") {
            p = NSString(string: p).expandingTildeInPath
        }
        if !p.hasPrefix("/") {
            let base = cwd ?? FileManager.default.currentDirectoryPath
            p = (base as NSString).appendingPathComponent(p)
        }
        return (p as NSString).standardizingPath
    }

    static let tempPrefixes: [String] = {
        var prefixes = ["/tmp", "/private/tmp", "/var/folders"]
        let ns = NSTemporaryDirectory()
        let standardized = (ns as NSString).standardizingPath
        if !prefixes.contains(where: { standardized == $0 || standardized.hasPrefix($0 + "/") }) {
            prefixes.append(standardized)
        }
        return prefixes
    }()

    static func isUnderTemp(_ standardizedPath: String) -> Bool {
        tempPrefixes.contains { standardizedPath == $0 || standardizedPath.hasPrefix($0 + "/") }
    }

    /// Sensitive locations flagged regardless of cwd.
    static func sensitiveReason(for standardizedPath: String) -> String? {
        let home = (NSHomeDirectory() as NSString).standardizingPath
        let sensitiveHomeSuffixes = [
            "/.ssh", "/.aws", "/.gnupg", "/.config/gh",
            "/.zshrc", "/.bashrc", "/.bash_profile", "/.profile", "/.zprofile",
            "/Library/LaunchAgents",
        ]
        for suffix in sensitiveHomeSuffixes {
            let full = home + suffix
            if standardizedPath == full || standardizedPath.hasPrefix(full + "/") {
                return "Touches a sensitive file (\(suffix.split(separator: "/").last.map(String.init) ?? suffix))"
            }
        }
        let absolutePrefixes: [(String, String)] = [
            ("/etc", "Modifies system configuration (/etc)"),
            ("/System", "Modifies protected system files"),
            ("/Library", "Modifies a system-wide Library location"),
        ]
        for (prefix, reason) in absolutePrefixes {
            if standardizedPath == prefix || standardizedPath.hasPrefix(prefix + "/") {
                return reason
            }
        }
        // /usr is sensitive except /usr/local.
        if standardizedPath == "/usr" || (standardizedPath.hasPrefix("/usr/") && !standardizedPath.hasPrefix("/usr/local")) {
            return "Modifies protected system files"
        }
        // .git internals (config, hooks/, etc.) anywhere.
        if let range = standardizedPath.range(of: "/.git/") {
            let inner = standardizedPath[range.upperBound...]
            if !inner.isEmpty {
                return "Modifies git internals (.git/\(inner.split(separator: "/").first.map(String.init) ?? ""))"
            }
        }
        return nil
    }

    static func isOutsideCwd(_ standardizedPath: String, cwd: String?) -> Bool {
        guard let cwd else { return false } // nil cwd: only the sensitive-location rule applies.
        let standardizedCwd = (cwd as NSString).standardizingPath
        return standardizedPath != standardizedCwd && !standardizedPath.hasPrefix(standardizedCwd + "/")
    }
}

// MARK: - File write rule

enum FileWriteRule {
    static func assess(path: String, cwd: String?) -> DangerAssessment? {
        let standardized = PathHelper.standardized(path, cwd: cwd)

        if let sensitive = PathHelper.sensitiveReason(for: standardized) {
            return DangerAssessment(reason: sensitive)
        }
        guard let cwd, PathHelper.isOutsideCwd(standardized, cwd: cwd) else { return nil }
        if PathHelper.isUnderTemp(standardized) { return nil }
        return DangerAssessment(reason: "Writes outside the project folder")
    }
}

// MARK: - Rule: rm

enum RmRule {
    static func rm(head: String, tail: [String], cwd: String?) -> DangerAssessment? {
        guard baseName(head) == "rm" else { return nil }
        let flags = tail.filter { $0.hasPrefix("-") }
        let combined = flags.joined()
        let hasRecursive = combined.contains("r") || combined.contains("R") || flags.contains("--recursive")
        let hasForce = combined.contains("f") || flags.contains("--force")
        if hasRecursive && hasForce {
            return DangerAssessment(reason: "Deletes files recursively")
        }
        if hasRecursive {
            // Plain `rm -r` (no force): flagged if any target is `/`, `~`, `$HOME`, a glob, `..`, or outside cwd.
            let targets = tail.filter { !$0.hasPrefix("-") }
            for target in targets {
                if isBroadOrOutside(target, cwd: cwd) {
                    return DangerAssessment(reason: "Deletes files recursively")
                }
            }
        }
        return nil
    }

    private static func isBroadOrOutside(_ target: String, cwd: String?) -> Bool {
        if target == "/" || target == "~" || target == "$HOME" || target == "*" || target == ".." {
            return true
        }
        if target.contains("*") { return true }
        guard let cwd else { return false }
        let standardized = PathHelper.standardized(target, cwd: cwd)
        return PathHelper.isOutsideCwd(standardized, cwd: cwd)
    }
}

// MARK: - Rule: git

enum GitRule {
    static func assess(head: String, tail: [String]) -> DangerAssessment? {
        guard baseName(head) == "git" else { return nil }
        // Skip a leading `-C <dir>` (or other global flags with a value) so `git -C dir push -f` still matches.
        var args = tail
        while let first = args.first, first.hasPrefix("-") {
            if first == "-C" || first == "--git-dir" || first == "--work-tree" {
                args.removeFirst()
                if !args.isEmpty { args.removeFirst() }
            } else {
                break
            }
        }
        guard let sub = args.first else { return nil }
        let rest = Array(args.dropFirst())
        let flags = Set(rest)
        let flagsJoined = rest.joined(separator: " ")

        switch sub {
        case "push":
            if rest.contains(where: { $0 == "--delete" || $0 == "-d" || $0.hasPrefix(":") }) {
                return DangerAssessment(reason: "Deletes a remote branch")
            }
            if flags.contains("--force") || flags.contains("-f") || flags.contains("--force-with-lease")
                || flags.contains("--mirror") || rest.contains(where: { $0.hasPrefix("+") }) {
                return DangerAssessment(reason: "Force-pushes git history")
            }
            return nil
        case "reset":
            if flags.contains("--hard") {
                return DangerAssessment(reason: "Discards local changes (git reset --hard)")
            }
            return nil
        case "clean":
            if rest.contains(where: { $0.hasPrefix("-") && $0.contains("f") && !$0.contains("n") }) {
                return DangerAssessment(reason: "Deletes untracked files (git clean)")
            }
            return nil
        case "checkout":
            if rest.contains("--") && rest.last == "." || rest == ["."] {
                return DangerAssessment(reason: "Discards local changes (git checkout .)")
            }
            return nil
        case "restore":
            if rest.contains(".") {
                return DangerAssessment(reason: "Discards local changes (git restore)")
            }
            return nil
        case "branch":
            if flags.contains("-D") || flags.contains("--delete") && flags.contains("--force") {
                return DangerAssessment(reason: "Force-deletes a git branch")
            }
            return nil
        case "stash":
            if rest.first == "clear" {
                return DangerAssessment(reason: "Discards all stashed changes")
            }
            return nil
        case "filter-branch":
            return DangerAssessment(reason: "Rewrites git history (filter-branch)")
        case "update-ref":
            if flags.contains("-d") {
                return DangerAssessment(reason: "Deletes a git ref")
            }
            return nil
        case "reflog":
            if rest.first == "expire" {
                return DangerAssessment(reason: "Expires git reflog entries")
            }
            return nil
        case "gc":
            if flagsJoined.contains("--prune=now") {
                return DangerAssessment(reason: "Prunes unreachable git objects immediately")
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Rule: sudo / doas / su

enum SudoRule {
    static func assess(head: String, tail: [String]) -> DangerAssessment? {
        let name = baseName(head)
        if name == "sudo" || name == "doas" {
            // A bare `sudo` / `doas` with no command isn't itself dangerous, but in practice it's always followed
            // by one; flag whenever there's anything after it (or even bare, to be safe).
            return DangerAssessment(reason: "Runs as administrator")
        }
        if name == "su" {
            return DangerAssessment(reason: "Runs as administrator")
        }
        return nil
    }
}

// MARK: - Rule: chmod / chown

enum ChmodChownRule {
    static func chmodChown(head: String, tail: [String], cwd: String?) -> DangerAssessment? {
        let name = baseName(head)
        if name == "chown" {
            if tail.contains(where: isRecursiveFlag) {
                return DangerAssessment(reason: "Changes ownership recursively")
            }
            return nil
        }
        guard name == "chmod" else { return nil }
        let flags = tail.filter { $0.hasPrefix("-") }
        let recursive = flags.contains(where: isRecursiveFlag)
        let modes = tail.filter { !$0.hasPrefix("-") }
        let targets = Array(modes.dropFirst())
        let mode = modes.first ?? ""

        if recursive {
            if mode == "777" || mode.contains("a+w") || mode.contains("o+w") {
                return DangerAssessment(reason: "Changes permissions recursively")
            }
            // Any -R with a world-writable-looking symbolic mode.
            if mode.contains("+w") && (mode.hasPrefix("a") || mode.hasPrefix("o") || mode.hasPrefix("ugo")) {
                return DangerAssessment(reason: "Changes permissions recursively")
            }
            return nil
        }
        if mode == "777" {
            for target in targets {
                if target == "/" {
                    return DangerAssessment(reason: "Changes permissions recursively")
                }
                if let cwd, PathHelper.isOutsideCwd(PathHelper.standardized(target, cwd: cwd), cwd: cwd) {
                    return DangerAssessment(reason: "Changes permissions recursively")
                }
            }
        }
        return nil
    }

    private static func isRecursiveFlag(_ flag: String) -> Bool {
        if flag == "--recursive" { return true }
        guard flag.hasPrefix("-"), !flag.hasPrefix("--") else { return false }
        return flag.contains("R") || flag.contains("r")
    }
}

// MARK: - Rule: disk-erasing tools

enum DiskRule {
    static func assess(head: String, tail: [String]) -> DangerAssessment? {
        let name = baseName(head)
        if name.hasPrefix("mkfs") || name.hasPrefix("newfs") || name == "fdisk" {
            return DangerAssessment(reason: "Can erase a disk")
        }
        if name == "diskutil" {
            let sub = tail.first ?? ""
            let dangerousSubs = ["eraseDisk", "eraseVolume", "partitionDisk", "zeroDisk", "secureErase"]
            if dangerousSubs.contains(where: { sub.caseInsensitiveCompare($0) == .orderedSame }) {
                return DangerAssessment(reason: "Can erase a disk")
            }
            return nil
        }
        if name == "dd" {
            if tail.contains(where: { $0.hasPrefix("of=") }) {
                return DangerAssessment(reason: "Can erase a disk")
            }
            return nil
        }
        return nil
    }

    /// A raw block/disk device path (`/dev/disk3`, `/dev/sda`, `/dev/rdisk1s1`…). Writing to one of these
    /// directly (`dd`, a plain redirect, `tee`) can wipe a disk, so it's flagged wherever a write target is
    /// checked, independent of the cwd/sensitive-location rules in `PathHelper`.
    static func isRawDiskDevice(_ path: String) -> Bool {
        let prefixes = ["/dev/disk", "/dev/rdisk", "/dev/sd"]
        return prefixes.contains { path.hasPrefix($0) }
    }
}

// MARK: - Rule: pipe-to-shell

enum PipeToShellRule {
    private static let downloaders: Set<String> = ["curl", "wget"]
    private static let interpreters: Set<String> = ["sh", "bash", "zsh", "python", "python3", "node", "perl", "ruby"]

    /// Per-segment check for the process-/command-substitution spellings: `sh <(curl ...)` or
    /// `bash -c "$(curl ...)"`. Those don't go through an actual `|`, so `assessPipeline` below won't see them —
    /// the interpreter is handed the downloader as an argument instead. Catches it by checking whether an
    /// interpreter's argument text mentions curl/wget.
    static func assess(head: String, tail: [String]) -> DangerAssessment? {
        let name = baseName(head)
        guard interpreters.contains(name) else { return nil }
        let joined = tail.joined(separator: " ")
        if joined.contains("curl") || joined.contains("wget") {
            return DangerAssessment(reason: "Runs a script from the internet")
        }
        return nil
    }

    /// Whole-pipe-chain check used by the top-level `assess(command:)`, since the pipe itself is what separates
    /// the download half from the interpreter half. Looks for `curl`/`wget` ... `|` ... `<interpreter>` within
    /// one pipe chain (segments joined by `|`, as opposed to `;`/`&&` which don't carry data between commands).
    static func assessPipeline(_ pipelineSegments: [String]) -> DangerAssessment? {
        guard pipelineSegments.count > 1 else { return nil }
        var sawDownloader = false
        for segment in pipelineSegments {
            let tokens = Tokenizer.tokenize(segment)
            guard let name = tokens.first.map(baseName) else { continue }
            if downloaders.contains(name) {
                sawDownloader = true
                continue
            }
            if sawDownloader && interpreters.contains(name) {
                return DangerAssessment(reason: "Runs a script from the internet")
            }
        }
        return nil
    }
}

// MARK: - Rule: SQL

enum SQLRule {
    /// Scans the segment's raw text (including inside `-c`/`-e` quoted strings, which the tokenizer already
    /// unquoted into a single token) for destructive SQL. Case-insensitive, anywhere in the command — except
    /// when it's clearly just literal text being fed to a non-SQL reader (grep/rg/echo/printf/git commit -m),
    /// per spec ("prefer not flagging" there).
    static func assess(head: String, tail: [String]) -> DangerAssessment? {
        let name = baseName(head)
        let passthroughCommands: Set<String> = ["grep", "rg", "echo", "printf"]
        if passthroughCommands.contains(name) { return nil }
        if name == "git" && tail.first == "commit" { return nil }

        let haystack = ([head] + tail).joined(separator: " ")
        let upper = haystack.uppercased()

        if containsWord(upper, "DROP") && (containsWord(upper, "TABLE") || containsWord(upper, "DATABASE") || containsWord(upper, "SCHEMA")) {
            return DangerAssessment(reason: "Deletes database data")
        }
        if containsWord(upper, "TRUNCATE") && containsWord(upper, "TABLE") {
            return DangerAssessment(reason: "Deletes database data")
        }
        if containsWord(upper, "DELETE") && containsWord(upper, "FROM") && !containsWord(upper, "WHERE") {
            return DangerAssessment(reason: "Deletes database data")
        }
        return nil
    }

    private static func containsWord(_ haystack: String, _ word: String) -> Bool {
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: word, range: searchRange) {
            let beforeOK = range.lowerBound == haystack.startIndex
                || !isWordChar(haystack[haystack.index(before: range.lowerBound)])
            let afterOK = range.upperBound == haystack.endIndex || !isWordChar(haystack[range.upperBound])
            if beforeOK && afterOK { return true }
            searchRange = range.upperBound..<haystack.endIndex
        }
        return false
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}

// MARK: - Rule: redirects / tee writing somewhere sensitive

enum RedirectRule {
    /// Looks for `>`, `>>`, or `tee` targets in the raw token stream and reuses `assessFileWrite`'s logic.
    /// (The tokenizer treats `>`/`>>` as ordinary characters since they're not quote/whitespace/backslash, so a
    /// token like `>/etc/hosts` or a bare `>` followed by a path both show up in the token list.)
    static func assess(head: String, tail: [String], cwd: String?) -> DangerAssessment? {
        let allTokens = [head] + tail
        let name = baseName(head)

        if name == "tee" {
            for target in tail where !target.hasPrefix("-") {
                if let hit = writeTargetAssessment(target, cwd: cwd) {
                    return hit
                }
            }
        }

        // Scan for redirect operators, including ones glued to the following path (`>/etc/hosts`) and ones
        // separated by whitespace (`>` `/etc/hosts`, already two tokens).
        var i = 0
        while i < allTokens.count {
            let token = allTokens[i]
            if let target = redirectTarget(in: token, remaining: allTokens, index: &i) {
                if let hit = writeTargetAssessment(target, cwd: cwd) {
                    return hit
                }
            }
            i += 1
        }
        return nil
    }

    /// A write target is dangerous either because it's a raw disk device (`dd`-style erase, even via a plain
    /// redirect) or because `FileWriteRule` flags it (sensitive location / outside cwd). Redirecting to any
    /// other `/dev/*` entry (`/dev/null`, `/dev/stdout`, `/dev/tty`…) is an extremely common, harmless shell
    /// idiom (`2>/dev/null`), so those are never flagged as "outside the project" even though they're literally
    /// outside cwd.
    private static func writeTargetAssessment(_ target: String, cwd: String?) -> DangerAssessment? {
        if DiskRule.isRawDiskDevice(target) {
            return DangerAssessment(reason: "Can erase a disk")
        }
        if target.hasPrefix("/dev/") {
            return nil
        }
        return FileWriteRule.assess(path: target, cwd: cwd)
    }

    /// Returns the redirect target if `token` (at `index`) is or starts with a `>`/`>>` operator, advancing
    /// `index` past whatever was consumed.
    private static func redirectTarget(in token: String, remaining: [String], index: inout Int) -> String? {
        guard let range = token.range(of: ">") else { return nil }
        var rest = String(token[range.upperBound...])
        if rest.hasPrefix(">") { rest.removeFirst() } // `>>`
        if !rest.isEmpty {
            return rest
        }
        // Operator was its own token (or ended the token) — the path is the next token, if any.
        if index + 1 < remaining.count {
            index += 1
            return remaining[index]
        }
        return nil
    }
}

// MARK: - Rule: mv / cp destination

enum MoveCopyRule {
    static func assess(head: String, tail: [String], cwd: String?) -> DangerAssessment? {
        let name = baseName(head)
        guard name == "mv" || name == "cp" else { return nil }
        let args = tail.filter { !$0.hasPrefix("-") }
        guard let destination = args.last, args.count >= 2 else { return nil }
        if destination == "/dev/null" && name == "mv" {
            return DangerAssessment(reason: "Deletes a file (mv to /dev/null)")
        }
        if let hit = FileWriteRule.assess(path: destination, cwd: cwd) {
            return hit
        }
        return nil
    }
}

// MARK: - Rule: process / system control

enum ProcessControlRule {
    static func assess(head: String, tail: [String]) -> DangerAssessment? {
        let name = baseName(head)
        switch name {
        case "kill":
            // Plain `kill <pid>` is fine; `kill -9 -1` (or any negative pid / signal-all) is not.
            if tail.contains("-9") && tail.contains("-1") {
                return DangerAssessment(reason: "Kills every process")
            }
            if tail.contains(where: { $0 == "-1" }) {
                return DangerAssessment(reason: "Kills every process")
            }
            return nil
        case "killall":
            return DangerAssessment(reason: "Kills processes by name")
        case "pkill":
            return DangerAssessment(reason: "Kills processes by pattern")
        case "shutdown":
            return DangerAssessment(reason: "Shuts down the machine")
        case "reboot":
            return DangerAssessment(reason: "Restarts the machine")
        case "halt":
            return DangerAssessment(reason: "Halts the machine")
        case "launchctl":
            let sub = tail.first ?? ""
            if ["unload", "bootout", "remove"].contains(sub) {
                return DangerAssessment(reason: "Unloads a system service")
            }
            return nil
        case "csrutil":
            return DangerAssessment(reason: "Changes System Integrity Protection")
        case "spctl":
            if tail.contains("--master-disable") {
                return DangerAssessment(reason: "Disables Gatekeeper")
            }
            return nil
        case "nvram":
            return DangerAssessment(reason: "Changes firmware settings")
        case "crontab":
            if tail.contains("-r") {
                return DangerAssessment(reason: "Deletes all scheduled cron jobs")
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Rule: fork bomb

enum ForkBombRule {
    /// The classic `:(){ :|:& };:` fork bomb (and close spacing variants, any function name). Checked against
    /// the raw, unsplit command text — the bomb's syntax is built entirely out of `;`/`&`/`|`, the very
    /// characters `CommandSplitter` treats as separators, so splitting first would destroy the pattern.
    static func assessRaw(_ command: String) -> DangerAssessment? {
        let compact = command.filter { !$0.isWhitespace }
        if compact.contains("(){") && compact.contains("|") && compact.contains("&") {
            // Look for `<name>(){ <name>|<name>&` — a self-referencing function definition that forks and
            // backgrounds itself. Cheap enough to just retest with the concrete `:` spelling too, which covers
            // the textbook example directly even if the generic name-matching below has an edge case.
            if compact.contains(":(){:|:&") || compact.contains(":(){:|:&}") {
                return DangerAssessment(reason: "Fork bomb")
            }
            if let name = functionName(in: compact), compact.contains("\(name)(){\(name)|\(name)&") {
                return DangerAssessment(reason: "Fork bomb")
            }
        }
        return nil
    }

    /// Extracts the identifier right before `(){` in a whitespace-stripped command, if any.
    private static func functionName(in compact: String) -> String? {
        guard let range = compact.range(of: "(){") else { return nil }
        var start = range.lowerBound
        var name = ""
        while start != compact.startIndex {
            let prior = compact.index(before: start)
            let c = compact[prior]
            guard c.isLetter || c.isNumber || c == "_" || c == ":" else { break }
            name.insert(c, at: name.startIndex)
            start = prior
        }
        return name.isEmpty ? nil : name
    }
}

// MARK: - Rule: find -delete / find -exec rm / xargs rm

enum FindXargsRule {
    static func assess(head: String, tail: [String]) -> DangerAssessment? {
        let name = baseName(head)
        if name == "find" {
            if tail.contains("-delete") {
                return DangerAssessment(reason: "Deletes files found by find -delete")
            }
            if let execIndex = tail.firstIndex(of: "-exec"), execIndex + 1 < tail.count,
               baseName(tail[execIndex + 1]) == "rm" {
                return DangerAssessment(reason: "Deletes files found by find -exec rm")
            }
            return nil
        }
        if name == "xargs" {
            // Find the command xargs runs: first non-flag token (skipping xargs' own flags like -I{} -0 -n1).
            var i = 0
            while i < tail.count, tail[i].hasPrefix("-") {
                i += 1
            }
            guard i < tail.count, baseName(tail[i]) == "rm" else { return nil }
            // `xargs rm` deletes whatever was piped in, with no per-file confirmation either way, so flag it
            // regardless of -r/-f (a bare `xargs rm` is still "delete N files I didn't individually see").
            return DangerAssessment(reason: "Deletes files found by xargs rm")
        }
        return nil
    }
}

// MARK: - Rule: publish / destroy remote resources

enum PublishDestroyRule {
    static func assess(head: String, tail: [String]) -> DangerAssessment? {
        let name = baseName(head)
        let sub = tail.first ?? ""

        switch name {
        case "npm":
            if sub == "publish" { return DangerAssessment(reason: "Publishes a package publicly") }
        case "cargo":
            if sub == "publish" { return DangerAssessment(reason: "Publishes a package publicly") }
        case "gem":
            if sub == "push" { return DangerAssessment(reason: "Publishes a package publicly") }
        case "twine":
            if sub == "upload" { return DangerAssessment(reason: "Publishes a package publicly") }
        case "pod":
            if sub == "trunk" && tail.dropFirst().first == "push" {
                return DangerAssessment(reason: "Publishes a package publicly")
            }
        case "gh":
            if sub == "release" && tail.dropFirst().first == "delete" {
                return DangerAssessment(reason: "Deletes a GitHub release")
            }
            if sub == "repo" && tail.dropFirst().first == "delete" {
                return DangerAssessment(reason: "Deletes a GitHub repository")
            }
        case "terraform":
            if sub == "destroy" { return DangerAssessment(reason: "Destroys provisioned infrastructure") }
        case "kubectl":
            if sub == "delete" { return DangerAssessment(reason: "Deletes a Kubernetes resource") }
        case "docker":
            if sub == "system" && tail.dropFirst().first == "prune" {
                return DangerAssessment(reason: "Destroys unused Docker resources")
            }
            if sub == "volume" && tail.dropFirst().first == "prune" {
                return DangerAssessment(reason: "Destroys Docker volumes")
            }
            if sub == "rm" && tail.contains("-f") {
                return DangerAssessment(reason: "Force-removes Docker containers")
            }
        default:
            break
        }
        return nil
    }
}

// MARK: - Prefix handling (sudo/doas/su -c, env, command, xargs, nice, time)

enum PrefixRule {
    /// `su -c '...'` runs a command as administrator; flag before peeling so the reason still says so even
    /// though `su` itself is also caught by `SudoRule` at the head.
    static func assess(tokens: [String], cwd: String?) -> DangerAssessment? {
        guard let head = tokens.first else { return nil }
        if baseName(head) == "su" {
            return DangerAssessment(reason: "Runs as administrator")
        }
        return nil
    }

    /// Strips leading wrapper commands that don't change the danger of what follows: `env [VAR=x...] cmd`,
    /// `command cmd`, `nice [-n N] cmd`, `time cmd`. `sudo`/`doas` are intentionally NOT stripped here — they're
    /// flagged directly by `SudoRule` and stripping them would hide that. `xargs` is left alone too since it has
    /// its own rule (`FindXargsRule`) that needs to see the `xargs` head.
    static func stripBenignPrefixes(_ tokens: [String]) -> [String] {
        var tokens = tokens
        var changed = true
        while changed {
            changed = false
            guard let head = tokens.first else { break }
            let name = baseName(head)
            switch name {
            case "env":
                tokens.removeFirst()
                while let next = tokens.first, next.hasPrefix("-") || next.contains("=") {
                    tokens.removeFirst()
                }
                changed = true
            case "command":
                tokens.removeFirst()
                changed = true
            case "nice":
                tokens.removeFirst()
                while let next = tokens.first, next.hasPrefix("-") {
                    tokens.removeFirst()
                    // `-n 10` takes a value.
                    if next == "-n", let v = tokens.first, Int(v) != nil {
                        tokens.removeFirst()
                    }
                }
                changed = true
            case "time":
                tokens.removeFirst()
                while let next = tokens.first, next.hasPrefix("-") {
                    tokens.removeFirst()
                }
                changed = true
            default:
                break
            }
        }
        return tokens
    }
}

// MARK: - Shell wrapper recursion (bash -c '...', sh -c "...", zsh -c '...')

enum ShellWrapperRule {
    private static let shells: Set<String> = ["bash", "sh", "zsh"]

    /// If `tokens` is `<shell> [flags] -c <command-string> [args...]`, returns the command string to recurse
    /// into. Only `-c` is special-cased since that's the one that embeds an inner command line.
    static func innerCommand(tokens: [String]) -> String? {
        guard let head = tokens.first, shells.contains(baseName(head)) else { return nil }
        guard let cIndex = tokens.firstIndex(of: "-c"), cIndex + 1 < tokens.count else { return nil }
        return tokens[cIndex + 1]
    }
}

// MARK: - Shared helpers

/// Command name without a path prefix (`/bin/rm` → `rm`), so rules match however the agent spelled it.
func baseName(_ token: String) -> String {
    (token as NSString).lastPathComponent
}
