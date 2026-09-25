import Darwin
import Foundation

/// Thin POSIX helpers for the agents socket, shared by `altillo-hook` (client) and the app (server).
///
/// Every fd made here is non-blocking and close-on-exec, and every wait has a deadline: a stopped or wedged app
/// must never hold an agent's hook, and a child process (osascript…) must never inherit the listener and keep a
/// dead socket "alive".
public enum UnixSocket {
    public enum Failure: Error, Equatable {
        /// No socket file, or nobody listening: Altillo isn't running.
        case unavailable
        /// Another process (a second Altillo) is already listening at the path.
        case inUse
        case pathTooLong
        case timedOut
        case system(Int32)
    }

    /// A bound, listening socket and the inode of the file it created (to tell it from a later owner's file).
    public struct Listener: Sendable, Equatable {
        public var fd: Int32
        public var inode: UInt64
    }

    /// Connects to `path` within `timeout` seconds. Fails fast with `.unavailable` when the file is missing or
    /// nobody listens. The returned fd is non-blocking.
    public static func connect(path: String, timeout: Double = 1) throws(Failure) -> Int32 {
        var address = sockaddr_un()
        guard fill(&address, path: path) else { throw .pathTooLong }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .system(errno) }
        prepare(fd)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 { return fd }
        let error = errno
        if error == EINPROGRESS || error == EAGAIN || error == EINTR {
            // The listener's backlog is full (a wedged app): wait a little, then give up.
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            if poll(&descriptor, 1, milliseconds(timeout)) == 1 {
                var status: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                if getsockopt(fd, SOL_SOCKET, SO_ERROR, &status, &length) == 0, status == 0 { return fd }
                close(fd)
                throw status == ECONNREFUSED || status == ENOENT ? .unavailable : .system(status)
            }
            close(fd)
            throw .timedOut
        }
        close(fd)
        if error == ENOENT || error == ECONNREFUSED || error == ENOTDIR { throw .unavailable }
        throw .system(error)
    }

    /// Creates the listening socket at `path` (owner-only: the file is 0600, `directory` 0700). A stale socket
    /// file left by a crash is replaced; a live one (another Altillo answers) is left alone and `.inUse` thrown.
    public static func listen(path: String, backlog: Int32 = 64) throws(Failure) -> Listener {
        var address = sockaddr_un()
        guard fill(&address, path: path) else { throw .pathTooLong }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        chmod(directory, 0o700)
        if access(path, F_OK) == 0 {
            if let other = try? connect(path: path, timeout: 0.5) {
                close(other)
                throw .inUse
            }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .system(errno) }
        prepare(fd)
        // No umask trick: it is process-wide and would race other threads creating files. The folder is 0700,
        // so nobody else can reach the socket in the instant before the chmod below.
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let error = errno
            close(fd)
            throw error == EADDRINUSE ? .inUse : .system(error)
        }
        chmod(path, 0o600)
        guard Darwin.listen(fd, backlog) == 0 else {
            let error = errno
            close(fd)
            unlink(path)
            throw .system(error)
        }
        return Listener(fd: fd, inode: inode(of: path) ?? 0)
    }

    /// The inode of the file at `path`, nil when there is none.
    public static func inode(of path: String) -> UInt64? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return UInt64(info.st_ino)
    }

    /// Removes the socket file only if it is still the one `listener` created (another instance may own the path
    /// by now).
    @discardableResult
    public static func removeIfOwned(path: String, listener: Listener) -> Bool {
        guard listener.inode != 0, inode(of: path) == listener.inode else { return false }
        return unlink(path) == 0
    }

    /// Accepts one pending connection (nil when none), already non-blocking and close-on-exec.
    public static func accept(_ listener: Int32) -> Int32? {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return nil }
        prepare(fd)
        return fd
    }

    /// The connecting process runs as the same user (the socket is owner-only anyway; this is belt and braces).
    public static func peerIsSameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { return false }
        return uid == getuid()
    }

    /// Non-blocking, close-on-exec, no SIGPIPE.
    public static func prepare(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Writes everything within `timeout` seconds. False when the peer is gone or stopped reading.
    @discardableResult
    public static func writeAll(_ fd: Int32, _ data: Data, timeout: Double = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        return data.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    guard errno == EAGAIN else { return false }
                    let left = deadline.timeIntervalSinceNow
                    guard left > 0 else { return false }
                    var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    if poll(&descriptor, 1, milliseconds(left)) < 0, errno != EINTR { return false }
                    continue
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }

    /// Reads until a newline, EOF or `timeout` seconds. Returns the line without the newline, nil on
    /// timeout/EOF-without-line.
    public static func readLine(_ fd: Int32, timeout: Double) -> Data? {
        var buffer = LineBuffer(limit: 1 << 20)
        let deadline = Date().addingTimeInterval(timeout)
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, milliseconds(remaining))
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if ready == 0 { continue }
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return nil
            }
            if count == 0 { return nil }
            if let line = buffer.append(Data(chunk[0..<count])).first { return line }
            if buffer.isOverLimit { return nil }
        }
    }

    private static func milliseconds(_ seconds: Double) -> Int32 {
        Int32(min(max(seconds * 1000, 0), Double(Int32.max)).rounded(.up))
    }

    private static func fill(_ address: inout sockaddr_un, path: String) -> Bool {
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.isEmpty, bytes.count < capacity else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return true
    }
}
