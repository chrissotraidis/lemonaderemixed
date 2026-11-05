import Foundation
import Network
import RemixCore

/// Sends input to the original game through the bridge running inside Wine.
/// The bridge only starts listening once the helper is up, and restarts with
/// the game, so the connection is reopened whenever it isn't ready.
final class GameLink {
    private let queue = DispatchQueue(label: "GameLink")
    private var connection: NWConnection?

    func send(_ line: String) {
        queue.async { [self] in
            let c = ready()
            c.send(content: Data((line + "\n").utf8), completion: .contentProcessed { _ in })
        }
    }

    func mouse(_ kind: String, _ p: CGPoint) {
        send("\(kind) \(Int(p.x.rounded())) \(Int(p.y.rounded()))")
    }

    /// The current connection, or a new one if it failed or closed.
    private func ready() -> NWConnection {
        if let c = connection {
            switch c.state {
            case .failed, .cancelled, .waiting: c.cancel()
            default: return c
            }
        }
        let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Bridge.port)!, using: .tcp)
        c.stateUpdateHandler = { [weak self, weak c] state in
            switch state {
            case .failed, .waiting: c?.cancel(); self?.queue.async { if self?.connection === c { self?.connection = nil } }
            default: break
            }
        }
        c.start(queue: queue)
        drain(c)
        connection = c
        return c
    }

    /// Replies are not needed; read and discard them so the socket never fills.
    private func drain(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak c] _, _, done, error in
            if !done && error == nil, let c { self?.drain(c) }
        }
    }
}
