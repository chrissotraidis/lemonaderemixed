import Foundation

/// The player's sound settings, applied live by the in-game agent.
/// LEMONADE_MUTED=1 mutes one session without changing the saved setting.
final class Sound: ObservableObject {
    static let levels = [25, 50, 75, 100]
    @Published var volume: Int { didSet { save(); apply() } }
    @Published var muted: Bool { didSet { save(); apply() } }
    private let sessionMuted = ProcessInfo.processInfo.environment["LEMONADE_MUTED"] == "1"
    var output: (Int) -> Void = { _ in }

    init() {
        let d = UserDefaults.standard
        volume = d.object(forKey: "volume") as? Int ?? 100
        muted = d.bool(forKey: "muted")
    }

    var effective: Int { muted || sessionMuted ? 0 : volume }

    func apply() { output(effective) }

    func step(_ delta: Int) {
        if muted { muted = false }
        volume = max(0, min(100, volume + delta))
    }

    private func save() {
        UserDefaults.standard.set(volume, forKey: "volume")
        UserDefaults.standard.set(muted, forKey: "muted")
    }
}
