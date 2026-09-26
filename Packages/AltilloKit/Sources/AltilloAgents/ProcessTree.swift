import Darwin
import Foundation

/// Reads the parent chain of a process with `sysctl` (no fork, no `ps`): what `altillo-hook` sends so the app can
/// find the terminal or editor hosting the agent, and what the app checks to tell a session's process is gone.
public enum ProcessTree {
    public struct Entry: Hashable, Sendable {
        public var pid: Int32
        public var parent: Int32
        /// `p_comm`, up to 16 characters ("claude", "zsh", "iTerm2").
        public var name: String
        /// "/dev/ttys003" when the process has a controlling terminal.
        public var tty: String?

        public init(pid: Int32, parent: Int32, name: String, tty: String? = nil) {
            self.pid = pid
            self.parent = parent
            self.name = name
            self.tty = tty
        }
    }

    /// Shells and wrappers between an agent and its hooks, skipped when looking for the agent's pid.
    public static let shellNames: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "nice", "timeout", "login"]

    public static func entry(_ pid: Int32) -> Entry? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else {
            return nil
        }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        var tty: String?
        let device = info.kp_eproc.e_tdev
        if device != -1, device != 0, let pointer = devname(device, S_IFCHR) {
            tty = "/dev/" + String(cString: pointer)
        }
        return Entry(pid: pid, parent: info.kp_eproc.e_ppid, name: name, tty: tty)
    }

    /// Ancestors of `pid` (not including it), nearest first, stopping before launchd.
    public static func ancestors(of pid: Int32 = getpid(), limit: Int = 24) -> [Entry] {
        var chain: [Entry] = []
        var current = entry(pid)?.parent ?? getppid()
        while current > 1, chain.count < limit, let entry = entry(current) {
            chain.append(entry)
            if entry.parent == current { break }
            current = entry.parent
        }
        return chain
    }

    /// The first ancestor that isn't a shell (the agent itself when the hook was spawned directly or via `sh -c`).
    public static func agentPID(in chain: [Entry]) -> Int32? {
        chain.first { !shellNames.contains($0.name) }?.pid
    }

    /// The controlling terminal of the nearest ancestor that has one.
    public static func tty(in chain: [Entry]) -> String? {
        chain.lazy.compactMap(\.tty).first
    }

    /// True while `pid` exists (EPERM still means it exists, owned by someone else).
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// A process's argv (`KERN_PROCARGS2`, no fork), nil when it can't be read (another user's process, gone).
    public static func arguments(of pid: Int32) -> [String]? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        let argc = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        // The executable path, then NUL padding, then argc NUL-terminated strings (then the environment, unread).
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    /// Whether `pid`'s standard input is a terminal (`/dev/tty…`), read with libproc (no fork).
    public static func stdinIsTerminal(_ pid: Int32) -> Bool {
        var info = vnode_fdinfowithpath()
        let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        guard proc_pidfdinfo(pid, 0, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { return false }
        let path = withUnsafeBytes(of: info.pvip.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.hasPrefix("/dev/tty") || path.hasPrefix("/dev/pts/")
    }

    /// Whether an agent runs as an interactive terminal session a person can answer (so a stop hook may hold the
    /// end of a turn open for a reply). Conservative: when in doubt, no.
    /// - The agent process itself has a controlling terminal and its stdin is a terminal (`stdinIsTerminal`, injected
    ///   for tests). Editor and app integrations (no terminal) and piped runs are out.
    /// - Headless runs are out: `claude -p` (or any `CLAUDE_CODE_ENTRYPOINT` but `cli`), `codex exec`, `gemini -p`,
    ///   `copilot -p`, `cursor-agent --print`, and Gemini's one-shot `gemini "question"` (a positional prompt without
    ///   `-i`/`--prompt-interactive`).
    public static func isInteractiveSession(agent: String, chain: [Entry], agentArguments: [String]?,
                                            environment: [String: String],
                                            stdinIsTerminal: (Int32) -> Bool = ProcessTree.stdinIsTerminal) -> Bool {
        guard let agentPID = agentPID(in: chain), let entry = chain.first(where: { $0.pid == agentPID }),
              entry.tty != nil, stdinIsTerminal(agentPID) else { return false }
        if let entrypoint = environment["CLAUDE_CODE_ENTRYPOINT"], entrypoint != "cli" { return false }
        guard let arguments = agentArguments, !arguments.isEmpty else { return false }
        let headlessFlags: Set<String> = ["-p", "--print", "--prompt", "--headless", "--output-format", "--json"]
        let headlessCommands: Set<String> = ["exec", "e", "app-server", "mcp-server", "mcp", "proto", "serve", "run",
                                             "acp"]
        for argument in arguments.dropFirst() {
            if headlessFlags.contains(argument) || headlessFlags.contains(where: { argument.hasPrefix($0 + "=") }) {
                return false
            }
        }
        // The first words that aren't options or script paths (node runs `gemini` as `node …/gemini …`; an option's
        // value may come first, as in `codex -m o3 exec`).
        let words = arguments.dropFirst().filter { !$0.hasPrefix("-") && !$0.hasPrefix("/") }
        if words.prefix(2).contains(where: headlessCommands.contains) { return false }
        if agent == "gemini", hasPositionalPrompt(arguments.dropFirst()),
           !arguments.contains(where: { $0 == "-i" || $0 == "--prompt-interactive" || $0.hasPrefix("--prompt-interactive=") }) {
            return false
        }
        return true
    }

    /// Gemini's options that take a value (so the value isn't mistaken for a prompt).
    static let geminiValueOptions: Set<String> = [
        "-m", "--model", "--approval-mode", "-e", "--extensions", "--include-directories", "--allowed-tools",
        "--allowed-mcp-server-names", "-o", "--output-format", "--telemetry-target", "--telemetry-otlp-endpoint",
        "--proxy", "-r", "--resume", "--session-summary",
    ]

    /// Whether `gemini`'s arguments (after the executable) hold a positional prompt: a word that isn't an option,
    /// an option's value, or the script path.
    static func hasPositionalPrompt(_ arguments: ArraySlice<String>) -> Bool {
        var skipNext = false
        for argument in arguments {
            if skipNext { skipNext = false; continue }
            if argument.hasPrefix("-") {
                if !argument.contains("="), geminiValueOptions.contains(argument) { skipNext = true }
                continue
            }
            if argument.hasPrefix("/") || argument.hasSuffix("gemini") || argument.hasSuffix(".js") { continue }
            return true
        }
        return false
    }
}
