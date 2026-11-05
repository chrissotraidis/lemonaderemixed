import AppKit
import RemixCore
import SwiftUI

/// Collapsed: the island around the notch (live while a day runs). Open: the game.
enum NotchMode { case collapsed, open }

/// Screen geometry, in screen coordinates (bottom-left origin).
struct NotchLayout {
    let screen: NSScreen
    static let leftWing: CGFloat = 200
    static let liveHeight: CGFloat = 108
    static let pad: CGFloat = 12, details: CGFloat = 50, gap: CGFloat = 8

    var frame: CGRect { screen.frame }
    var hasNotch: Bool { screen.auxiliaryTopLeftArea != nil }
    var stripHeight: CGFloat { max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) }
    var notch: CGRect {
        guard let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else {
            return CGRect(x: frame.midX - 60, y: frame.maxY - stripHeight, width: 120, height: stripHeight)
        }
        return CGRect(x: l.maxX, y: frame.maxY - stripHeight, width: max(0, r.minX - l.maxX), height: stripHeight)
    }

    /// Free room right of the notch, up to the first menu-bar icon.
    let rightWing: CGFloat

    init(screen: NSScreen) {
        self.screen = screen
        var room: CGFloat = 0
        if let r = screen.auxiliaryTopRightArea, let l = screen.auxiliaryTopLeftArea {
            let notchRight = r.minX, mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            var first = screen.frame.maxX
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            for w in list {
                guard (w[kCGWindowLayer as String] as? Int) == 25,
                      (w[kCGWindowOwnerPID as String] as? Int32) != ProcessInfo.processInfo.processIdentifier,
                      let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = b["X"], let y = b["Y"], let h = b["Height"], h <= 40,
                      abs((mainHeight - y) - screen.frame.maxY) < 2, x >= notchRight else { continue }
                first = min(first, x)
            }
            room = max(0, min(150, first - notchRight - 4))
            _ = l
        }
        rightWing = room
    }

    func island(live: Bool) -> CGRect {
        let h = stripHeight + (live ? Self.liveHeight : 0)
        let left = hasNotch ? Self.leftWing : 0
        let x = notch.minX - left
        return CGRect(x: x, y: frame.maxY - h, width: left + notch.width + rightWing, height: h)
    }

    var open: CGRect {
        let w: CGFloat = 640 + Self.pad * 2
        let h = stripHeight + Self.gap + Self.details + Self.gap + 480 + Self.pad
        let centred = CGRect(x: notch.midX - w / 2, y: frame.maxY - h, width: w, height: h)
        return centred.union(island(live: false))
    }

    var detailsRect: CGRect {
        let o = open
        return CGRect(x: o.midX - 320, y: o.maxY - stripHeight - Self.gap - Self.details, width: 640, height: Self.details)
    }

    var game: CGRect { CGRect(x: open.midX - 320, y: detailsRect.minY - Self.gap - 480, width: 640, height: 480) }
}

/// Frames and game state shared by the island and the open panel.
final class NotchModel: ObservableObject {
    @Published var mode: NotchMode = .collapsed { didSet { refreshLive() } }
    @Published private(set) var live = false
    @Published var frame: CGImage?
    @Published var state = GameState() { didSet { refreshLive() } }
    @Published var cart: CGPoint?            // centre of the cart, game pixels
    @Published var pulse = false
    @Published var tip: String?
    var onLive: (Bool) -> Void = { _ in }
    private var tap: FrameTap?
    private var timer: Timer?
    private var lastScan = Date.distantPast

    var inGame: Bool { ["plan", "day"].contains(state.screen) }

    private func refreshLive() {
        let l = mode == .collapsed && state.running == 1 && inGame
        if l != live { live = l; onLive(l) }
    }

    func start(frames url: URL) {
        tap = FrameTap(url: url)
        let t = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func update(_ s: GameState, tip: String?) {
        if state.running == 1 && s.running == 0 && s.day == state.day + 1 {
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.pulse = false }
        }
        if tip != self.tip { self.tip = tip }
        if s != state { state = s }
    }

    private func tick() {
        guard let image = tap?.newFrame() else { return }
        frame = image
        if inGame, Date().timeIntervalSince(lastScan) > 1.5 || cart == nil {
            lastScan = Date()
            if let c = Self.findCart(image) { cart = c }
        }
    }

    /// A crop of the town view centred on the cart, kept inside the town view.
    func around(width: CGFloat, height: CGFloat) -> CGRect {
        let town = CGRect(x: 331, y: 123, width: 305, height: 241)
        let c = cart ?? CGPoint(x: town.midX, y: town.midY)
        let x = min(max(c.x - width / 2, town.minX), town.maxX - width)
        let y = min(max(c.y - height / 2, town.minY), town.maxY - height)
        return CGRect(x: x, y: y, width: min(width, town.width), height: min(height, town.height))
    }

    /// The game's own weather icon: the forecast or, during the day, the current weather.
    var weatherRect: CGRect {
        state.running == 1 ? CGRect(x: 333, y: 80, width: 24, height: 20) : CGRect(x: 347, y: 78, width: 24, height: 18)
    }

    /// The cart, found by its blue-and-yellow umbrella.
    static func findCart(_ image: CGImage) -> CGPoint? {
        guard let data = image.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return nil }
        let stride = image.bytesPerRow
        var minX = 640, minY = 480, maxX = 0, maxY = 0, n = 0
        for y in 122..<365 {
            for x in 330..<637 {
                let o = y * stride + x * 4
                let b = Int(p[o]), g = Int(p[o + 1]), r = Int(p[o + 2])
                if r < 40 && g >= 40 && g <= 75 && b >= 200 {
                    n += 1; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard n >= 8, maxX - minX < 60, maxY - minY < 40 else { return nil }
        return CGPoint(x: CGFloat(minX + maxX) / 2, y: CGFloat(minY) + 18)
    }
}

/// A crop of the live game picture with sharp pixels.
struct GameCrop: View {
    let image: CGImage?
    let rect: CGRect
    var body: some View {
        if let image, let piece = image.cropping(to: rect.integral) {
            Image(decorative: piece, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
        }
    }
}

struct HostedView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - The island

struct IslandView: View {
    @ObservedObject var model: NotchModel
    let layout: NotchLayout
    private var s: GameState { model.state }

    var body: some View {
        let h = layout.stripHeight
        let radius: CGFloat = model.live ? 20 : 10
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if layout.hasNotch {
                    left.frame(width: NotchLayout.leftWing)
                    Color.clear.frame(width: layout.notch.width)
                    right.frame(width: layout.rightWing)
                } else {
                    left
                }
            }
            .frame(height: h)
            if model.live {
                liveStrip.frame(height: NotchLayout.liveHeight).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
                .fill(.black)
                .overlay(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
                    .stroke(model.pulse ? LT.yellow : .clear, lineWidth: 2))
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: model.live)
        .animation(.easeInOut(duration: 0.3), value: model.pulse)
    }

    /// Left of the notch, hugging it: cash and status, then your stand, live.
    private var left: some View {
        let h = layout.stripHeight
        return HStack(spacing: 6) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: -4) {
                Text(model.inGame ? money(s.cash) : "Lemonade").font(LT.font(h * 0.56)).foregroundStyle(LT.yellow)
                Text(subline).font(LT.font(h * 0.38)).foregroundStyle(LT.dim)
            }
            Group {
                if model.inGame {
                    GameCrop(image: model.frame, rect: model.around(width: 60, height: 40))
                } else {
                    Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: (h - 4) * 1.5, height: h - 4)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.trailing, 8)
    }

    private var subline: String {
        guard model.inGame else { return "click to play" }
        if s.running == 1 { return "\(s.today.sold) sold today" }
        return "day \(s.dayNumber)"
    }

    /// Right of the notch, hugging it: the game's weather icon and temperature.
    private var right: some View {
        let h = layout.stripHeight
        return HStack(spacing: 3) {
            if model.inGame {
                if layout.rightWing >= 52 {
                    GameCrop(image: model.frame, rect: model.weatherRect).frame(width: 22, height: 18)
                }
                Text("\(s.running == 1 ? s.tempsF[1] : s.highF)F")
                    .font(LT.font(h * 0.5)).foregroundStyle(.white).fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
    }

    /// While a day runs: the street around your stand, live, with today's numbers.
    private var liveStrip: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                figure("sold", "\(s.today.sold)")
                figure("profit", money(s.today.profit))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            GameCrop(image: model.frame, rect: model.around(width: 240, height: 92))
                .frame(width: 240, height: 92)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(LT.panelDark, lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                figure("walked", "\(s.today.missed)", leading: true)
                figure("now", "\(s.tempsF[1])F", leading: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
    }

    private func figure(_ label: String, _ value: String, leading: Bool = false) -> some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: -3) {
            Text(value).font(LT.font(20)).foregroundStyle(LT.yellow)
            Text(label).font(LT.font(14)).foregroundStyle(LT.dim)
        }
    }
}

// MARK: - The open panel

struct OpenView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var sound: Sound
    let layout: NotchLayout
    let gameView: NSView
    var close: () -> Void
    var openWindow: () -> Void
    private var s: GameState { model.state }

    /// A screen rect inside this panel (top-left origin).
    private func local(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX - layout.open.minX, y: layout.open.maxY - r.maxY, width: r.width, height: r.height)
    }

    var body: some View {
        let open = model.mode == .open
        let shape = local(open ? layout.open : layout.island(live: false))
        let outline = UnevenRoundedRectangle(bottomLeadingRadius: open ? 22 : 10, bottomTrailingRadius: open ? 22 : 10)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .top) {
                Color.black
                Stripes(px: 1).padding(.top, layout.stripHeight).opacity(open ? 1 : 0)
            }
            .frame(width: shape.width, height: shape.height)
            .clipShape(outline)
            .overlay(outline.stroke(LT.panelDark, lineWidth: open ? 3 : 0))
            .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 16, y: 8)
            .offset(x: shape.minX, y: shape.minY)
            .opacity(open ? 1 : 0)

            if open {
                let d = local(layout.detailsRect), g = local(layout.game)
                details.frame(width: d.width, height: d.height).offset(x: d.minX, y: d.minY)
                    .transition(.opacity)
                HostedView(view: gameView)
                    .frame(width: g.width, height: g.height)
                    .overlay(Rectangle().stroke(LT.panelDark, lineWidth: 2))
                    .offset(x: g.minX, y: g.minY)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(width: layout.open.width, height: layout.open.height, alignment: .topLeading)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: model.mode)
    }

    private var details: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: -2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.inGame ? money(s.cash) : "Lemonade Remixed").font(LT.font(24)).foregroundStyle(LT.yellow)
                    if model.inGame {
                        Text("Day \(s.dayNumber) - \(s.locationName) - \(s.lowF)F to \(s.highF)F")
                            .font(LT.font(17)).foregroundStyle(.white).lineLimit(1)
                    }
                }
                Text(detailLine).font(LT.font(15)).foregroundStyle(LT.dim).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(sound.muted ? "sound off" : "sound on") { sound.muted.toggle() }.buttonStyle(GameButtonStyle(px: 1.2))
            Button("window", action: openWindow).buttonStyle(GameButtonStyle(px: 1.2))
            Button("close", action: close).buttonStyle(GameButtonStyle(px: 1.2))
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(LT.panel)
        .overlay(alignment: .top) { LT.panelDark.frame(height: 2) }
        .overlay(alignment: .leading) { LT.panelDark.frame(width: 2) }
        .overlay(alignment: .bottom) { LT.panelLight.frame(height: 1) }
        .overlay(alignment: .trailing) { LT.panelLight.frame(width: 1) }
    }

    private var detailLine: String {
        guard model.inGame else { return "Start or load a game." }
        if s.running == 1 { return "Selling: \(s.today.sold) cups, \(money(s.today.profit)) profit, \(s.today.missed) walked away" }
        let stock = "Stock serves \(s.cupsServable) cups at \(money(s.price))"
        return model.tip.map { stock + ".  " + $0 } ?? stock
    }
}

// MARK: - Windows

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The island: every click on it toggles the game.
final class IslandHost: NSHostingView<IslandView> {
    var onClick: () -> Void = {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { onClick() }
}

final class OpenHost: NSHostingView<OpenView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController {
    let model = NotchModel()
    private let layout: NotchLayout
    private let game: GameView
    private let islandPanel: NotchPanel
    private let openPanel: NotchPanel
    private var monitor: Any?
    private var hideWork: DispatchWorkItem?

    private static func panel(_ rect: CGRect, level: NSWindow.Level) -> NotchPanel {
        let p = NotchPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = level
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false
        return p
    }

    init(screen: NSScreen, sound: Sound, link: GameLink, openWindow: @escaping () -> Void) {
        layout = NotchLayout(screen: screen)
        game = GameView(link: link)
        openPanel = Self.panel(layout.open, level: .statusBar)
        islandPanel = Self.panel(layout.island(live: false), level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))

        var close: () -> Void = {}
        let openHost = OpenHost(rootView: OpenView(model: model, sound: sound, layout: layout, gameView: game,
                                                   close: { close() }, openWindow: openWindow))
        openHost.sizingOptions = []
        openPanel.contentView = openHost
        openPanel.ignoresMouseEvents = true

        let islandHost = IslandHost(rootView: IslandView(model: model, layout: layout))
        islandHost.sizingOptions = []
        islandPanel.contentView = islandHost

        close = { [weak self] in self?.set(.collapsed) }
        islandHost.onClick = { [weak self] in self?.toggle() }
        model.onLive = { [weak self] live in self?.resizeIsland(live: live) }

        openPanel.orderFrontRegardless()
        islandPanel.orderFrontRegardless()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.openPanel, e.keyCode == 53, self.model.mode == .open else { return e }
            self.set(.collapsed)
            return nil
        }
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    func start(frames url: URL) {
        model.start(frames: url)
        game.show(frames: url)
    }

    func close() { openPanel.orderOut(nil); islandPanel.orderOut(nil) }

    func toggle() { set(model.mode == .open ? .collapsed : .open) }

    private func resizeIsland(live: Bool) {
        let target = layout.island(live: live)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            islandPanel.animator().setFrame(target, display: true)
        }
    }

    func set(_ mode: NotchMode) {
        hideWork?.cancel()
        if mode == .open {
            openPanel.ignoresMouseEvents = false
            model.mode = .open
            openPanel.makeKey()
            openPanel.makeFirstResponder(game)
        } else {
            model.mode = .collapsed
            let w = DispatchWorkItem { [weak self] in
                if self?.model.mode == .collapsed { self?.openPanel.ignoresMouseEvents = true }
            }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
        }
    }

    // MARK: Self-test (LEMONADE_NOTCH_SELFTEST=<log file>)

    func selfTest(log path: String) {
        func note(_ s: String) {
            let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            try? (old + s + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        func click(_ panel: NSPanel, _ screen: CGPoint) {
            let p = CGPoint(x: screen.x - panel.frame.minX, y: screen.y - panel.frame.minY)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    panel.sendEvent(e)
                }
            }
        }
        let i = layout.island(live: false)
        note("island \(i) rightWing \(layout.rightWing) open \(layout.open)")
        let steps: [(String, CGPoint)] = [
            ("click left wing", CGPoint(x: i.minX + 60, y: i.midY)),
            ("click the notch", CGPoint(x: layout.notch.midX, y: i.midY)),
            ("click right wing", CGPoint(x: i.maxX - 10, y: i.midY)),
        ]
        var t = 0.0
        for (name, point) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [self] in
                click(islandPanel, point)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { note("\(name): mode \(self.model.mode)") }
            }
            t += 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.2) { [self] in
            let g = layout.game
            click(openPanel, CGPoint(x: g.minX + 255, y: g.maxY - 87))   // the game's recipe tab
            note("clicked the game's recipe tab")
        }
    }
}
