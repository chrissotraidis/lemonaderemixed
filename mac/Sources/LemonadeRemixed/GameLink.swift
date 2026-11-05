import Foundation
import Network

/// Sends input to the original game through the bridge running inside Wine.
final class GameLink {
    private let connection = NWConnection(host: "127.0.0.1", port: 47123, using: .tcp)
    private let queue = DispatchQueue(label: "GameLink")

    init() {
        connection.start(queue: queue)
        drain()
    }

    func send(_ line: String) {
        connection.send(content: Data((line + "\n").utf8), completion: .contentProcessed { _ in })
    }

    func mouse(_ kind: String, _ p: CGPoint) {
        send("\(kind) \(Int(p.x.rounded())) \(Int(p.y.rounded()))")
    }

    /// Replies are not needed; read and discard them so the socket never fills.
    private func drain() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, done, error in
            if !done && error == nil { self?.drain() }
        }
    }
}
