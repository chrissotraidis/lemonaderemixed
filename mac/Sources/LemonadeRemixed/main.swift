import AppKit

/// Prototype: mirrors the original game (running in Wine) into a sharp,
/// resizable window and into the notch, and forwards input back to it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let link = GameLink()
    let mirror = GameMirror()
    var window: NSWindow!
    var notch: NotchPanel?

    func applicationDidFinishLaunching(_ note: Notification) {
        let view = GameView(link: link)
        mirror.attach(view.pixels)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Lemonade Remixed"
        window.contentView = view
        window.contentAspectRatio = GameMirror.gameSize
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        mirror.onStatus = { [weak self] s in self?.window.subtitle = s }

        if let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) {
            notch = NotchPanel(screen: screen, mirror: mirror, link: link)
        }
        buildMenu()
        mirror.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The game's own speaker button (bottom-left of the play screen).
    @objc func toggleSound() { link.send("tap 20 457") }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Lemonade Remixed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let gameItem = NSMenuItem()
        let gameMenu = NSMenu(title: "Game")
        gameMenu.addItem(withTitle: "Mute / Unmute", action: #selector(toggleSound), keyEquivalent: "m")
        gameMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        gameItem.submenu = gameMenu
        menu.addItem(gameItem)
        NSApp.mainMenu = menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
