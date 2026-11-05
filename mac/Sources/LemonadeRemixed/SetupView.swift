import AppKit
import SwiftUI

/// Where players can get the original game. Lemonade Remixed doesn't include
/// or distribute it.
enum GameSources {
    static let supported = URL(string: "https://oldgamesdownload.com/lemonade-tycoon/")!
    static let other = URL(string: "https://www.myabandonware.com/game/lemonade-tycoon-c4f")!

    static let notice = "Lemonade Remixed doesn't include Lemonade Tycoon Deluxe and doesn't provide it. You download the original game yourself from an abandonware archive, and Lemonade Remixed runs it on your Mac. Those sites aren't connected to Lemonade Remixed, and the game's rights belong to their owners."
    static let steps = "Supported: the Zone.com edition of Lemonade Tycoon Deluxe (Old Games Download; other editions are not supported yet). Unzip the download, then choose Setup.exe. Your registration name and key come with the download."
}

/// What the app is doing before the game is on screen.
final class SetupModel: ObservableObject {
    enum Phase: Equatable {
        case chooseInstaller
        case working(String)
        case needsKey(error: String?)
        case failed(String)
    }
    @Published var phase: Phase = .working("Starting...")
    @Published var name = ""
    @Published var key = ""
    var onChoose: () -> Void = {}
    var onRegister: (String, String) -> Void = { _, _ in }
}

/// First run and loading, drawn in the game's style.
struct SetupView: View {
    @ObservedObject var model: SetupModel
    private let px: CGFloat = 2

    var body: some View {
        ZStack {
            Stripes(px: px)
            VStack(spacing: 8 * px) {
                Text("Lemonade Remixed").font(LT.font(40 * px)).foregroundStyle(LT.yellow)
                    .shadow(color: LT.panelDark, radius: 0, x: px, y: px)
                GamePanel(px: px) { content }
                    .frame(maxWidth: 260 * px)
            }
            .padding(10 * px)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 5 * px) {
            switch model.phase {
            case .chooseInstaller:
                PixelText("Bring your own game", px: px, size: 17, color: LT.yellow)
                PixelText(GameSources.notice, px: px)
                PixelText(GameSources.steps, px: px, color: LT.dim)
                HStack(spacing: 4 * px) {
                    Button("Old Games Download") { NSWorkspace.shared.open(GameSources.supported) }
                    Button("My Abandonware") { NSWorkspace.shared.open(GameSources.other) }
                }
                .buttonStyle(GameButtonStyle(px: px))
                Button("Choose Setup.exe...", action: model.onChoose)
                    .buttonStyle(GameButtonStyle(px: px, big: true))
                    .keyboardShortcut(.defaultAction)
            case .working(let message):
                HStack(spacing: 4 * px) {
                    ProgressView().controlSize(.small).tint(LT.yellow)
                    PixelText(message, px: px)
                }
            case .needsKey(let error):
                PixelText("Register the game", px: px, size: 17, color: LT.yellow)
                PixelText("Enter the registration name and key that came with your download.", px: px)
                field("Name", text: $model.name)
                field("Key", text: $model.key)
                if let error { PixelText(error, px: px, color: LT.yellow) }
                Button("Register") { model.onRegister(model.name, model.key) }
                    .buttonStyle(GameButtonStyle(px: px, big: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.name.isEmpty || model.key.isEmpty)
            case .failed(let message):
                PixelText(message, px: px)
                PixelText(GameSources.steps, px: px, color: LT.dim)
                HStack(spacing: 4 * px) {
                    Button("Old Games Download") { NSWorkspace.shared.open(GameSources.supported) }
                        .buttonStyle(GameButtonStyle(px: px))
                    Button("Choose Setup.exe...", action: model.onChoose)
                        .buttonStyle(GameButtonStyle(px: px, big: true))
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 4 * px) {
            PixelText(label, px: px, color: LT.dim).frame(width: 30 * px, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(LT.font(15 * px))
                .foregroundStyle(.white)
                .padding(.horizontal, 3 * px).padding(.vertical, px)
                .background(LT.inset)
                .overlay(alignment: .top) { LT.panelDark.frame(height: px) }
        }
    }
}

/// Help > Where to Get the Game, and the About box.
enum InfoWindows {
    static func showWhereToGet() {
        let alert = NSAlert()
        alert.messageText = "Where to get the game"
        alert.informativeText = GameSources.notice + "\n\n" + GameSources.steps
        alert.addButton(withTitle: "Open Old Games Download")
        alert.addButton(withTitle: "Open My Abandonware")
        alert.addButton(withTitle: "Close")
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(GameSources.supported)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(GameSources.other)
        default: break
        }
    }

    static func showAbout() {
        let credits = """
        A Mac shell that runs the original Lemonade Tycoon Deluxe (Hexacto Games, 2002) from your own copy, with a sharp picture, an assistant and sound controls.

        Lemonade Tycoon is a trademark of its owners. Lemonade Remixed isn't affiliated with them and doesn't include the game.

        Includes Wine (LGPL) and the VT323 font (SIL Open Font License).
        """
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: credits, attributes: [.font: NSFont.systemFont(ofSize: 11)]),
            .applicationName: "Lemonade Remixed",
        ])
    }
}
