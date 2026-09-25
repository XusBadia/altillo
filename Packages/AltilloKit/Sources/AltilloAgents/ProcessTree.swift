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
}
