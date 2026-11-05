import Foundation

/// Request/reply access to the bridge inside Wine (runtime/helper/bridge.py).
public enum Bridge {
    /// The bridge's port: 47123, or LEMONADE_PORT for a second copy (testing).
    public static let port: UInt16 = ProcessInfo.processInfo.environment["LEMONADE_PORT"].flatMap { UInt16($0) } ?? 47123

    /// Sends one command and returns the reply line, or nil if the helper
    /// isn't reachable. Blocks; call it off the main thread.
    public static func request(_ line: String, timeout: TimeInterval = 10) -> String? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return nil }
        let bytes = Array((line + "\n").utf8)
        guard send(fd, bytes, bytes.count, 0) == bytes.count else { return nil }
        var reply = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 512)
        while !reply.contains(10) {
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else { return nil }
            reply += buf[0..<n]
        }
        return String(decoding: reply.prefix { $0 != 10 }, as: UTF8.self)
    }
}
