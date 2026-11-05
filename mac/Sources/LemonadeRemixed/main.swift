import AppKit
import RemixCore
import SwiftUI

/// Lemonade Remixed: runs the original game in a private Wine setup and shows
/// it in a native window. Development overrides (environment):
///   LEMONADE_SUPPORT   use this folder instead of Application Support
///   LEMONADE_SETUP     install from this Setup.exe without asking
///   LEMONADE_REG_NAME, LEMONADE_REG_KEY   register without asking
///   LEMONADE_MUTED=1   start muted
final class AppController: NSObject, NSApplicationDelegate {
    let env = ProcessInfo.processInfo.environment
    lazy var runtime = GameRuntime(
        resources: Bundle.main.resourceURL!,
        support: env["LEMONADE_SUPPORT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lemonade Remixed"))
    let link = GameLink()
    let mirror = GameMirror()
    let setup = SetupModel()
    var window: NSWindow!
    var gameView: GameView!
    var showingGame = false
    var triedAutoKey = false
    var sawGame = false
    let work = DispatchQueue(label: "runtime")

    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(newValue, forKey: "muted"); applyVolume() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        if env["LEMONADE_MUTED"] == "1" { UserDefaults.standard.set(true, forKey: "muted") }
        gameView = GameView(link: link)
        mirror.attach(gameView.pixels)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Lemonade Remixed"
        window.contentAspectRatio = GameMirror.gameSize
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: SetupView(model: setup))
        window.center()
        window.makeKeyAndOrderFront(nil)
        setup.onChoose = { [weak self] in self?.chooseInstaller() }
        setup.onRegister = { [weak self] name, key in self?.register(name, key) }
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)

        if runtime.isInstalled {
            start()
        } else if let path = env["LEMONADE_SETUP"] {
            install(URL(fileURLWithPath: path))
        } else {
            setup.phase = .chooseInstaller
        }
    }

    // MARK: - Setup

    func chooseInstaller() {
        let panel = NSOpenPanel()
        panel.message = "Choose the Lemonade Tycoon Deluxe installer (Setup.exe)"
        panel.allowedContentTypes = [.exe, .item]
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.install(url) }
        }
    }

    func install(_ setupFile: URL) {
        setup.phase = .working("Checking the installer…")
        work.async { [self] in
            do {
                try runtime.install(setup: setupFile) { message in
                    DispatchQueue.main.async { self.setup.phase = .working(message) }
                }
                DispatchQueue.main.async { self.start() }
            } catch {
                DispatchQueue.main.async { self.setup.phase = .failed("\(error)") }
            }
        }
    }

    func register(_ name: String, _ key: String) {
        setup.phase = .working("Registering…")
        work.async { [self] in
            let reply = Bridge.request("register \(name)\t\(key)", timeout: 20)
            DispatchQueue.main.async {
                if reply != "ok" { self.setup.phase = .needsKey(error: "That name and key weren't accepted.") }
                else { self.setup.phase = .working("Starting the game…") }
            }
        }
    }

    // MARK: - Running

    func start() {
        setup.phase = .working("Starting the game…")
        applyVolume()
        do { try runtime.launch() } catch {
            setup.phase = .failed("\(error)")
            return
        }
        watch()
    }

    /// Follows the helper's state until the game is on screen, and quits the
    /// app when the game closes.
    func watch() {
        work.asyncAfter(deadline: .now() + 0.5) { [self] in
            let state = Bridge.request("state", timeout: 2)
            DispatchQueue.main.async {
                switch state {
                case "needs-key":
                    if case .needsKey = self.setup.phase {} else if !self.autoRegister() {
                        self.setup.phase = .needsKey(error: nil)
                    }
                case "game":
                    self.sawGame = true
                    self.showGame()
                case "stopped" where self.sawGame:
                    NSApp.terminate(nil)
                    return
                default:
                    break
                }
                self.watch()
            }
        }
    }

    func autoRegister() -> Bool {
        guard !triedAutoKey, let name = env["LEMONADE_REG_NAME"], let key = env["LEMONADE_REG_KEY"] else { return false }
        triedAutoKey = true
        register(name, key)
        return true
    }

    func showGame() {
        guard !showingGame else { return }
        showingGame = true
        window.contentView = gameView
        mirror.start()
    }

    func applyVolume() { runtime.setVolume(muted ? 0 : 100) }

    @objc func toggleMute() { muted.toggle() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        work.async { [self] in
            runtime.stop()
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Lemonade Remixed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let gameItem = NSMenuItem()
        let gameMenu = NSMenu(title: "Game")
        gameMenu.addItem(withTitle: "Mute", action: #selector(toggleMute), keyEquivalent: "m")
        gameMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        gameItem.submenu = gameMenu
        menu.addItem(gameItem)
        NSApp.mainMenu = menu
    }
}

extension AppController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleMute) { item.state = muted ? .on : .off }
        return true
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
