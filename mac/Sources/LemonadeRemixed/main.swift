import AppKit
import RemixCore
import SwiftUI

/// Lemonade Remixed: runs the original game in a private Wine setup and shows
/// it in a native window. Development overrides (environment):
///   LEMONADE_SUPPORT   use this folder instead of Application Support
///   LEMONADE_SETUP     install from this Setup.exe without asking
///   LEMONADE_REG_NAME, LEMONADE_REG_KEY   register without asking
///   LEMONADE_MUTED=1   start muted
///   LEMONADE_PICTURE=sharp|pixel    picture mode
///   LEMONADE_WINDOW=WIDTHxHEIGHT    initial window content size in points
///   LEMONADE_SELFTEST="tap X Y"     send this through the app's input link
///                                   12 s after the game appears (testing)
final class AppController: NSObject, NSApplicationDelegate {
    let env = ProcessInfo.processInfo.environment
    lazy var runtime = GameRuntime(
        resources: Bundle.main.resourceURL!,
        support: env["LEMONADE_SUPPORT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lemonade Remixed"))
    let link = GameLink()
    let setup = SetupModel()
    var window: NSWindow!
    var gameView: GameView!
    var container: GameContainer!
    let assistant = AssistantModel()
    var showingGame = false
    var triedAutoKey = false
    var sawGame = false
    let work = DispatchQueue(label: "runtime")
    var termSource: DispatchSourceSignal?

    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(newValue, forKey: "muted"); applyVolume() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        // A plain kill (logout, Activity Monitor) still closes the game and Wine.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { quitSoon() }
        term.resume()
        termSource = term
        if env["LEMONADE_MUTED"] == "1" { UserDefaults.standard.set(true, forKey: "muted") }
        if let p = env["LEMONADE_PICTURE"] { UserDefaults.standard.set(p, forKey: "picture") }
        gameView = GameView(link: link)
        gameView.mode = picture
        container = GameContainer(game: gameView, model: assistant)
        container.assistant.open = !UserDefaults.standard.bool(forKey: "hideAssistant")
        container.onToggle = { [weak self] in self?.toggleAssistant() }
        LT.registerFont()
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Lemonade Remixed"
        window.collectionBehavior = [.fullScreenPrimary]
        let setupHost = NSHostingView(rootView: SetupView(model: setup))
        setupHost.sizingOptions = []   // the window sets the size, not the content
        window.contentView = setupHost
        window.center()
        if let size = env["LEMONADE_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            window.setContentSize(CGSize(width: size[0], height: size[1]))
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        setup.onChoose = { [weak self] in self?.chooseInstaller() }
        setup.onRegister = { [weak self] name, key in self?.register(name, key) }
        buildMenu()

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
                case "stopped" where self.sawGame,
                     nil where self.sawGame && !self.runtime.isRunning:
                    quitSoon()
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
        window.contentView = container
        fitWindowToGame()
        gameView.show(frames: runtime.framesFile)
        assistant.start()
        if let test = env["LEMONADE_SELFTEST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { self.link.send(test) }
        }
    }

    func applyVolume() { runtime.setVolume(muted ? 0 : 100) }

    @objc func toggleMute() { muted.toggle() }
    @objc func showWhereToGet() { InfoWindows.showWhereToGet() }
    @objc func showAbout() { InfoWindows.showAbout() }

    var picture: PictureMode {
        PictureMode(rawValue: UserDefaults.standard.string(forKey: "picture") ?? "") ?? .sharp
    }

    @objc func choosePicture(_ item: NSMenuItem) {
        guard let mode = item.representedObject as? String else { return }
        UserDefaults.standard.set(mode, forKey: "picture")
        gameView.mode = picture
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        work.async { [self] in
            runtime.stop()
            RunLoop.main.perform(inModes: [.common, .modalPanel]) { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Lemonade Remixed", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Lemonade Remixed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let gameItem = NSMenuItem()
        let gameMenu = NSMenu(title: "Game")
        gameMenu.addItem(withTitle: "Mute", action: #selector(toggleMute), keyEquivalent: "m")
        gameMenu.addItem(.separator())
        for (i, mode) in PictureMode.allCases.enumerated() {
            let item = gameMenu.addItem(withTitle: mode.title, action: #selector(choosePicture(_:)), keyEquivalent: "\(i + 1)")
            item.representedObject = mode.rawValue
        }
        gameMenu.addItem(.separator())
        gameMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        gameMenu.addItem(withTitle: "Show Assistant", action: #selector(toggleAssistant), keyEquivalent: "\\")
        gameItem.submenu = gameMenu
        menu.addItem(gameItem)
        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Where to Get the Game...", action: #selector(showWhereToGet), keyEquivalent: "")
        helpItem.submenu = helpMenu
        menu.addItem(helpItem)
        NSApp.helpMenu = helpMenu
        NSApp.mainMenu = menu
    }
}

extension AppController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleMute) { item.state = muted ? .on : .off }
        if item.action == #selector(choosePicture(_:)) { item.state = (item.representedObject as? String) == picture.rawValue ? .on : .off }
        if item.action == #selector(toggleAssistant) { item.state = container?.assistant.open == true ? .on : .off }
        return true
    }
}

extension AppController {
    @objc func toggleAssistant() {
        container.assistant.open.toggle()
        UserDefaults.standard.set(!container.assistant.open, forKey: "hideAssistant")
        fitWindowToGame(animate: true)
    }

    /// Sizes the window so the game stays 4:3 beside the assistant.
    func fitWindowToGame(animate: Bool = false) {
        window.contentAspectRatio = container.aspect
        guard !window.styleMask.contains(.fullScreen) else { container.needsLayout = true; return }
        var h = window.contentLayoutRect.height
        let a = container.aspect
        if let screen = window.screen?.visibleFrame, h * a.width / a.height > screen.width {
            h = screen.width * a.height / a.width
        }
        let chrome = window.frame.height - window.contentLayoutRect.height
        var frame = window.frame
        frame.size = NSSize(width: (h * a.width / a.height).rounded(), height: h + chrome)
        window.setFrame(frame, display: true, animate: animate)
    }
}

/// Quits from inside a dispatched block: the terminate request runs from the
/// run loop, where the reply it waits for can still be delivered.
func quitSoon() {
    RunLoop.main.perform(inModes: [.common]) { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
