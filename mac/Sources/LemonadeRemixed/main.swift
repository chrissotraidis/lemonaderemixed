import AppKit
import RemixCore
import SwiftUI

/// Lemonade Remixed: runs the original game in a private Wine setup and shows
/// it in a native window. Development overrides (environment):
///   LEMONADE_SUPPORT   use this folder instead of Application Support
///   LEMONADE_SETUP     install from this Setup.exe without asking
///   LEMONADE_REG_NAME, LEMONADE_REG_KEY   register without asking
///   LEMONADE_MUTED=1   mute this session (the saved setting is unchanged)
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
    var notch: NotchController?
    var notchEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notch") }
    }
    var showingGame = false
    var triedAutoKey = false
    var sawGame = false
    let work = DispatchQueue(label: "runtime")
    var termSource: DispatchSourceSignal?

    let sound = Sound()

    func applicationDidFinishLaunching(_ note: Notification) {
        // A plain kill (logout, Activity Monitor) still closes the game and Wine.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { quitSoon() }
        term.resume()
        termSource = term
        sound.output = { [weak self] v in self?.runtime.setVolume(v) }
        if let p = env["LEMONADE_PICTURE"] { UserDefaults.standard.set(p, forKey: "picture") }
        gameView = GameView(link: link)
        gameView.mode = picture
        container = GameContainer(game: gameView, model: assistant, sound: sound)
        container.advisor.open = env["LEMONADE_ADVISOR_OPEN"] == "1"   // testing
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
        window.contentAspectRatio = GameView.gameSize
        gameView.show(frames: runtime.framesFile)
        assistant.start()
        assistant.onState = { [weak self] s in self?.notch?.model.update(s, tip: self?.assistant.tips.first) }
        updateNotch()
        if let test = env["LEMONADE_SELFTEST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { self.link.send(test) }
        }
    }

    func applyVolume() { sound.apply() }

    @objc func toggleMute() { sound.muted.toggle() }
    @objc func setVolumeLevel(_ item: NSMenuItem) { sound.muted = false; sound.volume = item.tag }
    @objc func toggleAdvisor() { container.advisor.open.toggle() }
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

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { !(showingGame && notchEnabled) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleNotch() {
        notchEnabled.toggle()
        updateNotch()
    }

    /// Shows the notch on the built-in display (or the main screen) while the game runs.
    func updateNotch() {
        guard showingGame, notchEnabled else { notch?.close(); notch = nil; return }
        guard notch == nil, let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main else { return }
        let n = NotchController(screen: screen, sound: sound, link: link,
                                openWindow: { [weak self] in self?.notch?.set(.collapsed); self?.showWindow() })
        n.start(frames: runtime.framesFile)
        n.model.update(assistant.state, tip: assistant.tips.first)
        notch = n
        if env["LEMONADE_NOTCH"] == "open" { n.set(.open) }   // testing
        if let seconds = env["LEMONADE_NOTCH_CLOSE_AFTER"].flatMap(Double.init) {   // testing
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { n.set(.collapsed) }
        }
        if let log = env["LEMONADE_NOTCH_SELFTEST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) { n.selfTest(log: log) }
        }
    }

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
        let volumeItem = gameMenu.addItem(withTitle: "Volume", action: nil, keyEquivalent: "")
        let volumeMenu = NSMenu(title: "Volume")
        for level in Sound.levels {
            let item = volumeMenu.addItem(withTitle: "\(level)%", action: #selector(setVolumeLevel(_:)), keyEquivalent: "")
            item.tag = level
        }
        volumeItem.submenu = volumeMenu
        gameMenu.addItem(.separator())
        for (i, mode) in PictureMode.allCases.enumerated() {
            let item = gameMenu.addItem(withTitle: mode.title, action: #selector(choosePicture(_:)), keyEquivalent: "\(i + 1)")
            item.representedObject = mode.rawValue
        }
        gameMenu.addItem(.separator())
        gameMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        gameMenu.addItem(withTitle: "Advisor", action: #selector(toggleAdvisor), keyEquivalent: "\\")
        gameMenu.addItem(withTitle: "Show in Notch", action: #selector(toggleNotch), keyEquivalent: "")
        gameMenu.addItem(withTitle: "Show Game Window", action: #selector(showWindow), keyEquivalent: "0")
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
        if item.action == #selector(toggleMute) { item.state = sound.muted ? .on : .off }
        if item.action == #selector(setVolumeLevel(_:)) { item.state = !sound.muted && sound.volume == item.tag ? .on : .off }
        if item.action == #selector(toggleNotch) { item.state = notchEnabled ? .on : .off }
        if item.action == #selector(toggleAdvisor) { item.state = container?.advisor.open == true ? .on : .off }
        if item.action == #selector(choosePicture(_:)) { item.state = (item.representedObject as? String) == picture.rawValue ? .on : .off }
        return true
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
