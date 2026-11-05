import AppKit
import SwiftUI

/// The player's app settings, saved as they change.
/// A hosting view that takes the first click even when the app isn't frontmost.
final class FirstClickHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class Prefs: ObservableObject {
    @Published var notch: Bool { didSet { UserDefaults.standard.set(notch, forKey: "notch"); onChange() } }
    @Published var picture: PictureMode { didSet { UserDefaults.standard.set(picture.rawValue, forKey: "picture"); onChange() } }
    var onChange: () -> Void = {}

    init() {
        let d = UserDefaults.standard
        notch = d.object(forKey: "notch") as? Bool ?? true     // on by default on a Mac
        picture = PictureMode(rawValue: d.string(forKey: "picture") ?? "") ?? .sharp
    }
}

/// Settings in the game's own look: notch, sound, picture, where to get the game.
struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var sound: Sound

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(LT.font(34)).foregroundStyle(LT.yellow).shadow(color: LT.buttonShadow, radius: 0, x: 2, y: 2)
            section("Notch", "The game lives in the notch while you work. Click the notch for the small view; the window and the notch take turns.") {
                choice("On", "rectangle.topthird.inset.filled", prefs.notch) { prefs.notch = true }
                choice("Off", "macwindow", !prefs.notch) { prefs.notch = false }
            }
            section("Sound", "Also in the Game menu: Mute is ⌘M.") {
                choice("Mute", "speaker.slash.fill", sound.muted) { sound.muted = true }
                ForEach(Sound.levels, id: \.self) { level in
                    choice("\(level)%", nil, !sound.muted && sound.volume == level) { sound.muted = false; sound.volume = level }
                }
            }
            section("Picture", "Sharp fills the window; Pixel-Perfect keeps every pixel square, with a border.") {
                choice("Sharp", "rectangle.expand.vertical", prefs.picture == .sharp) { prefs.picture = .sharp }
                choice("Pixel-Perfect", "square.grid.3x3", prefs.picture == .pixel) { prefs.picture = .pixel }
            }
            section("Your copy of the game", "Lemonade Remixed doesn't include the game; you bring your own installer.") {
                Button { InfoWindows.showWhereToGet() } label: { Label("Where to get it", systemImage: "arrow.down.circle.fill") }
                    .buttonStyle(NotchButtonStyle())
            }
        }
        .padding(18)
        .frame(width: 460, alignment: .leading)
        .background(Stripes(px: 1))
    }

    private func section<C: View>(_ title: String, _ note: String, @ViewBuilder _ content: () -> C) -> some View {
        GamePanel(px: 1) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(LT.font(22)).foregroundStyle(.white)
                HStack(spacing: 6) { content() }
                Text(note).font(LT.font(15)).foregroundStyle(LT.dim).fixedSize(horizontal: false, vertical: true)
            }
            .padding(4)
        }
    }

    private func choice(_ title: String, _ icon: String?, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let icon { Label(title, systemImage: icon) } else { Text(title) }
        }
        .buttonStyle(NotchButtonStyle(on: on))
    }
}
