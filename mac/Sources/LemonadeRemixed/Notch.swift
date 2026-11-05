import AppKit
import RemixCore
import SwiftUI

/// Island: status beside the notch. Mini: the street around your stand, live,
/// with controls; it stays open while you work. Full: the whole game.
enum NotchMode { case collapsed, mini, full }

/// Screen geometry, in screen coordinates (bottom-left origin). Below the menu
/// bar is free to use; in the menu bar only the island is, and it stops short
/// of other apps' icons.
struct NotchLayout {
    let screen: NSScreen
    static let leftWing: CGFloat = 200
    static let maxRight: CGFloat = 64
    static let fastGlyph = CGRect(x: 6, y: 5, width: 26, height: 22)    // in the right wing, top-left origin

    var frame: CGRect { screen.frame }
    var hasNotch: Bool { screen.auxiliaryTopLeftArea != nil }
    var stripHeight: CGFloat { max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) }
    var top: CGFloat { frame.maxY - stripHeight }
    var notch: CGRect {
        guard let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else {
            return CGRect(x: frame.midX - 60, y: top, width: 120, height: stripHeight)
        }
        return CGRect(x: l.maxX, y: top, width: max(0, r.minX - l.maxX), height: stripHeight)
    }

    /// Free room right of the notch, up to the first menu-bar icon of another app.
    func freeRight() -> CGFloat {
        guard hasNotch else { return 0 }
        let mainHeight = NSScreen.screens.first?.frame.height ?? frame.height
        var first = frame.maxX
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 25,
                  (w[kCGWindowOwnerPID as String] as? Int32) != ProcessInfo.processInfo.processIdentifier,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let h = b["Height"], h <= 40,
                  abs((mainHeight - y) - frame.maxY) < 2, x >= notch.maxX - 1 else { continue }
            first = min(first, x)
        }
        let room = first - notch.maxX - 10
        return room < 30 ? 0 : min(Self.maxRight, room)
    }

    func island(right: CGFloat) -> CGRect {
        let left = hasNotch ? Self.leftWing : 0
        return CGRect(x: notch.minX - left, y: top, width: left + notch.width + right, height: stripHeight)
    }

    static let miniWidth: CGFloat = 600, view = CGSize(width: 292, height: 108), viewScale: CGFloat = 2
    static let bar: CGFloat = 34, pad: CGFloat = 8
    /// The game's left half at 1x: stock bar, tabs and the tab's panel.
    static let menus = CGRect(x: 0, y: 0, width: 330, height: 424)
    /// The middle of the screen at 1x, where the game asks its questions.
    static let dialog = CGRect(x: 110, y: 80, width: 420, height: 320)
    var mini: CGRect { mini(view: Self.view.height * Self.viewScale) }
    func mini(view: CGFloat) -> CGRect {
        let h = Self.pad + view + Self.pad + Self.bar + Self.pad + 2
        return CGRect(x: notch.midX - Self.miniWidth / 2, y: top - h, width: Self.miniWidth, height: h)
    }

    static let header: CGFloat = 44, fullPad: CGFloat = 10
    var full: CGRect {
        let w = 640 + Self.fullPad * 2, h = Self.fullPad + Self.header + Self.fullPad + 480 + Self.fullPad
        return CGRect(x: notch.midX - w / 2, y: top - h, width: w, height: h)
    }

    func body(_ mode: NotchMode, view: CGFloat = NotchLayout.view.height * NotchLayout.viewScale) -> CGRect {
        switch mode {
        case .collapsed: return CGRect(x: notch.midX - 160, y: top - 1, width: 320, height: 1)
        case .mini: return mini(view: view)
        case .full: return full
        }
    }
}

/// Frames and game state for the notch.
final class NotchModel: ObservableObject {
    @Published var mode: NotchMode = .collapsed { didSet { retime() } }
    /// The newest game frame. Not published: frames go straight to the
    /// FrameLayerViews below, so SwiftUI never rebuilds a panel per frame.
    private(set) var frame: CGImage?
    @Published var state = GameState()
    @Published var cart: CGPoint?
    @Published var pulse = false
    @Published var tip: String?
    @Published var right: CGFloat = 0
    /// While planning, the small view can show the game's own menus instead of the quick plan.
    @Published var menus = false { didSet { if menus != oldValue { relayout?() } } }
    var relayout: (() -> Void)?

    /// Height of the small view's picture: the game's menus and its questions need more room.
    var viewHeight: CGFloat {
        if state.screen == "dialog" { return NotchLayout.dialog.height }
        if menus && state.screen == "plan" { return NotchLayout.menus.height }
        return NotchLayout.view.height * NotchLayout.viewScale
    }
    private var tap: FrameTap?
    private var timer: Timer?
    private var lastScan = Date.distantPast
    private var sinks = NSHashTable<FrameLayerView>.weakObjects()

    var inGame: Bool { ["plan", "day"].contains(state.screen) }
    /// A career is open, even if the game is asking a question right now.
    var hasGame: Bool { inGame || state.screen == "dialog" }
    var running: Bool { state.screen == "day" }

    func start(frames url: URL) {
        tap = FrameTap(url: url)
        retime()
    }

    /// Every display refresh while the street is on screen, a few otherwise.
    private func retime() {
        timer?.invalidate()
        let fps: Double = mode == .collapsed ? 10 : 60
        let t = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func attach(_ view: FrameLayerView) {
        sinks.add(view)
        if let frame { view.show(frame) }
    }

    func update(_ s: GameState, tip: String?) {
        if state.running == 1 && s.running == 0 && s.day == state.day + 1 {
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.pulse = false }
        }
        if tip != self.tip { self.tip = tip }
        let oldHeight = viewHeight
        if s != state { state = s }
        if menus && s.screen == "day" { menus = false }
        if viewHeight != oldHeight { relayout?() }
    }

    private func tick() {
        guard let image = tap?.newFrame() else { return }
        frame = image
        if inGame, Date().timeIntervalSince(lastScan) > 1.5 || cart == nil {
            lastScan = Date()
            if let c = Self.findCart(image), c != cart { cart = c }
        }
        for view in sinks.allObjects { view.show(image) }
    }

    /// A crop of the town view centred on the cart, kept inside the town view.
    func around(width: CGFloat, height: CGFloat) -> CGRect {
        let town = CGRect(x: 331, y: 123, width: 300, height: 241)
        let c = cart ?? CGPoint(x: town.midX, y: town.midY)
        let w = min(width, town.width), h = min(height, town.height)
        let x = (min(max(c.x - w / 2, town.minX), town.maxX - w)).rounded()
        let y = (min(max(c.y - h / 2, town.minY), town.maxY - h)).rounded()
        return CGRect(x: x, y: y, width: w, height: h)
    }

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

/// A piece of the live game picture, drawn straight into a layer with crisp
/// pixels each time a frame arrives.
final class FrameLayerView: NSView {
    var crop = CGRect(x: 0, y: 0, width: 640, height: 480)
    /// Set to make this piece of the game clickable: clicks go to the game at the matching spot.
    var link: GameLink?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resize
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { link == nil ? nil : super.hitTest(point) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        if link != nil {
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        }
    }
    private func gamePoint(_ e: NSEvent) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let p = convert(e.locationInWindow, from: nil)
        let top = isFlipped ? p.y : bounds.height - p.y
        return CGPoint(x: crop.minX + p.x * crop.width / bounds.width, y: crop.minY + top * crop.height / bounds.height)
    }
    override func mouseDown(with e: NSEvent) { if let l = link, let p = gamePoint(e) { l.mouse("move", p); l.mouse("down", p) } }
    override func mouseUp(with e: NSEvent) { if let l = link, let p = gamePoint(e) { l.mouse("up", p) } }
    override func mouseDragged(with e: NSEvent) { if let l = link, let p = gamePoint(e) { l.mouse("move", p) } }
    override func mouseMoved(with e: NSEvent) { if let l = link, let p = gamePoint(e) { l.mouse("move", p) } }
    func show(_ image: CGImage) {
        guard let piece = image.cropping(to: crop.integral) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = piece
        CATransaction.commit()
    }
}

struct GameCrop: NSViewRepresentable {
    let model: NotchModel
    let rect: CGRect
    var link: GameLink? = nil
    func makeNSView(context: Context) -> FrameLayerView {
        let v = FrameLayerView(frame: .zero)
        v.crop = rect
        v.link = link
        model.attach(v)
        return v
    }
    func updateNSView(_ v: FrameLayerView, context: Context) {
        guard v.crop != rect else { return }
        v.crop = rect
        if let f = model.frame { v.show(f) }
    }
}

struct HostedView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A game-green button with an icon and a plain label. \`on\` lights it yellow.
struct NotchButtonStyle: ButtonStyle {
    var on = false
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(LT.font(17))
            .foregroundStyle(on ? LT.buttonShadow : .white)
            .padding(.horizontal, 9).frame(height: 26)
            .background(on ? LT.yellow : (prominent ? LT.bigButton : LT.bigButton.opacity(0.85)))
            .overlay(alignment: .top) { (pressed ? LT.buttonShadow : LT.buttonHi).frame(height: 1) }
            .overlay(alignment: .bottom) { (pressed ? LT.buttonHi : LT.buttonShadow).frame(height: 1) }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .brightness(pressed ? -0.08 : 0)
    }
}

struct NotchActions {
    var toggle: () -> Void = {}
    var mini: () -> Void = {}
    var full: () -> Void = {}
    var collapse: () -> Void = {}
    var openWindow: () -> Void = {}
}

/// A small square "-" or "+" in the game's button green.
struct ChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LT.font(18)).foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(LT.bigButton)
            .overlay(alignment: .top) { (configuration.isPressed ? LT.buttonShadow : LT.buttonHi).frame(height: 1) }
            .overlay(alignment: .bottom) { (configuration.isPressed ? LT.buttonHi : LT.buttonShadow).frame(height: 1) }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}

let warnColor = Color(red: 1, green: 0.55, blue: 0.4)

func signedMoney(_ cents: Int) -> String { (cents > 0 ? "+" : "") + money(cents) }

// MARK: - The island

struct IslandView: View {
    @ObservedObject var model: NotchModel
    let layout: NotchLayout
    private var s: GameState { model.state }
    /// The street view or the full game is open below the notch.
    private var open: Bool { model.mode != .collapsed }

    var body: some View {
        let h = layout.stripHeight
        HStack(spacing: 0) {
            if layout.hasNotch {
                left.frame(width: NotchLayout.leftWing)
                Color.clear.frame(width: layout.notch.width)
                if model.right > 0 { right.frame(width: model.right) }
            } else {
                left
            }
        }
        .frame(height: h)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: open ? 0 : 10, bottomTrailingRadius: open ? 0 : 10).fill(.black))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.3), value: model.pulse)
    }

    /// Left of the notch, hugging it. Closed: cash, a status line and your stand.
    /// Open: the stand is on screen below, so the wing carries more numbers instead.
    private var left: some View {
        let h = layout.stripHeight
        return HStack(spacing: 10) {
            Spacer(minLength: 0)
            if open, model.hasGame, let extra {
                VStack(alignment: .trailing, spacing: -4) {
                    Text(extra.0).font(LT.font(h * 0.5)).foregroundStyle(.white)
                    Text(extra.1).font(LT.font(h * 0.38)).foregroundStyle(LT.dim)
                }
            }
            VStack(alignment: .trailing, spacing: -4) {
                Text(model.hasGame ? money(s.cash) : "Lemonade").font(LT.font(h * 0.56)).foregroundStyle(LT.yellow)
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(LT.yellow.opacity(model.pulse ? 0.3 : 0)))
                Text(subline).font(LT.font(h * 0.38)).foregroundStyle(model.pulse ? LT.yellow : LT.dim)
            }
            if !open {
                Group {
                    if model.hasGame {
                        GameCrop(model: model, rect: model.around(width: 60, height: 40))
                    } else {
                        Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    }
                }
                .frame(width: (h - 4) * 1.5, height: h - 4)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.trailing, 8)
    }

    private var subline: String {
        guard model.hasGame else { return "Remixed" }
        if model.pulse, !s.report.isEmpty { return signedMoney(s.report.earnings) + " yesterday" }
        if s.running == 1 { return open ? signedMoney(s.today.profit) + " today" : "\(s.today.sold) sold today" }
        return "day \(s.dayNumber)"
    }

    /// The second column while open: sales during the day, the forecast while planning.
    private var extra: (String, String)? {
        if model.running { return ("\(s.today.sold) sold", "\(s.today.missed) walked away") }
        if s.screen == "plan", s.day > 0, !s.report.isEmpty { return (signedMoney(s.report.earnings), "yesterday, \(s.report.sold) sold") }
        return nil
    }

    /// Right of the notch: a small fast-forward toggle during the day, else the high.
    private var right: some View {
        let h = layout.stripHeight
        return HStack(spacing: 4) {
            if model.running {
                Image(systemName: "forward.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(s.fast == 1 ? LT.buttonShadow : LT.dim)
                    .frame(width: NotchLayout.fastGlyph.width, height: NotchLayout.fastGlyph.height)
                    .background(RoundedRectangle(cornerRadius: 5).fill(s.fast == 1 ? LT.yellow : Color.white.opacity(0.12)))
                    .help(s.fast == 1 ? "Normal speed" : "Fast forward")
                if model.right >= 60 {
                    Text("\(s.tempsF[1])F").font(LT.font(h * 0.46)).foregroundStyle(.white).fixedSize()
                }
            } else if model.hasGame {
                Text("\(s.highF)F").font(LT.font(h * 0.5)).foregroundStyle(.white).fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, NotchLayout.fastGlyph.minX)
    }
}

// MARK: - Mini and full

struct BodyView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var sound: Sound
    @ObservedObject var assistant: AssistantModel
    let link: GameLink
    let gameView: NSView
    let actions: NotchActions
    private var s: GameState { model.state }

    var body: some View {
        let full = model.mode == .full
        ZStack(alignment: .top) {
            if full { fullView } else if model.mode == .mini { miniView }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(full ? AnyView(Stripes(px: 1)) : AnyView(Color.black))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
            .stroke(full ? LT.panelDark : Color.white.opacity(0.08), lineWidth: full ? 3 : 1))
    }

    private var soundButton: some View {
        Button { sound.muted.toggle() } label: {
            Label(sound.muted ? "Muted" : "Sound", systemImage: sound.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
        .buttonStyle(NotchButtonStyle())
        .help(sound.muted ? "Turn the sound on" : "Mute")
    }

    private var fastButton: some View {
        Button { assistant.setFast(s.fast != 1) } label: { Label("Fast", systemImage: "forward.fill") }
            .buttonStyle(NotchButtonStyle(on: s.fast == 1))
            .help(s.fast == 1 ? "Back to normal speed" : "Fast forward the day")
    }

    // MARK: Mini: the street while selling, the day's plan before

    private var miniView: some View {
        let size = CGSize(width: NotchLayout.view.width * NotchLayout.viewScale, height: NotchLayout.view.height * NotchLayout.viewScale)
        let menus = model.menus && s.screen == "plan"
        let height = model.viewHeight
        return VStack(spacing: NotchLayout.pad) {
            Group {
                if model.running {
                    street(width: NotchLayout.view.width, height: size.height)
                } else if s.screen == "plan" {
                    HStack(spacing: NotchLayout.pad) {
                        street(width: menus ? (size.width - NotchLayout.menus.width - NotchLayout.pad) / 2 : 120, height: height)
                            .overlay(alignment: .bottomLeading) {
                                Text("Day \(s.dayNumber)  \(s.locationName)").font(LT.font(15)).foregroundStyle(LT.yellow)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.65)))
                                    .padding(6)
                                    .allowsHitTesting(false)
                            }
                        if menus {
                            // The game's own stock bar, tabs and panel, live and clickable.
                            GameCrop(model: model, rect: NotchLayout.menus, link: link)
                                .frame(width: NotchLayout.menus.width, height: NotchLayout.menus.height)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(LT.panelDark, lineWidth: 2))
                        } else {
                            planner.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else if s.screen == "dialog" {
                    question
                } else {
                    wholeScreen(height: size.height)
                }
            }
            .frame(width: size.width, height: height)

            HStack(spacing: 6) {
                Button(action: actions.collapse) { Label("Hide", systemImage: "chevron.up") }
                    .buttonStyle(NotchButtonStyle())
                    .help("Tuck it back into the notch")
                soundButton
                Spacer()
                if s.screen == "plan" {
                    HStack(spacing: 0) {
                        Button { model.menus = false } label: { Label("Quick", systemImage: "slider.horizontal.3") }
                            .buttonStyle(NotchButtonStyle(on: !model.menus))
                            .help("Stock, recipe, price and restocking at a glance")
                        Button { model.menus = true } label: { Label("Menus", systemImage: "square.grid.2x2.fill") }
                            .buttonStyle(NotchButtonStyle(on: model.menus))
                            .help("The game's own tabs: rent, upgrades, staff, marketing, recipe, supplies, results")
                    }
                    Spacer()
                }
                if model.running {
                    Button(action: assistant.skipDay) { Label("Skip day", systemImage: "forward.end.fill") }
                        .buttonStyle(NotchButtonStyle())
                        .help("Play out the rest of the day at once")
                    fastButton
                }
                if s.screen == "plan" {
                    Button(action: assistant.startDay) { Label("Start day", systemImage: "play.fill") }
                        .buttonStyle(NotchButtonStyle(prominent: true))
                        .disabled(assistant.busy != nil)
                }
                Button(action: actions.full) { Label("Full game", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(NotchButtonStyle(prominent: true))
                    .help("Open the whole game here: rent, upgrades, staff, marketing")
            }
            .frame(height: NotchLayout.bar)
        }
        .padding(NotchLayout.pad)
    }

    /// The live street around your stand, `width` game pixels wide at 2x. Click to open the full game.
    private func street(width: CGFloat, height: CGFloat) -> some View {
        Button(action: actions.full) {
            GameCrop(model: model, rect: model.around(width: width, height: height / NotchLayout.viewScale))
                .frame(width: width * NotchLayout.viewScale, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(LT.panelDark, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the full game")
    }

    /// The everyday plan: stock, recipe, price, restock. Everything else is in the full game.
    private var planner: some View {
        let expected = Advisor.expectedCups(s)
        let short = s.cupsServable < expected
        let plan = Advisor.restock(s, cups: expected)
        let recipe = assistant.shownRecipe
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(s.lowF)-\(s.highF)F \(s.forecastWords)").font(LT.font(18)).foregroundStyle(LT.yellow)
                Spacer(minLength: 4)
                Text("rent \(money(s.rent))/day").font(LT.font(15)).foregroundStyle(LT.dim)
            }
            GameCrop(model: model, rect: CGRect(x: 4, y: 0, width: 316, height: 38))   // the game's own stock bar, icons whole
                .frame(width: 316, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack(spacing: 10) {
                stepper("lemons", "\(recipe[0])") { assistant.nudgeRecipe(0, by: $0) }
                stepper("sugar", "\(recipe[1])") { assistant.nudgeRecipe(1, by: $0) }
                stepper("ice", "\(recipe[2])") { assistant.nudgeRecipe(2, by: $0) }
            }
            HStack(spacing: 8) {
                stepper("price", money(assistant.shownPrice)) { assistant.nudgePrice(by: $0 * 10) }
                Spacer(minLength: 0)
                if short {
                    Button(action: assistant.restock) {
                        Label("Restock " + money(Supplies.cost(plan)), systemImage: "cart.fill")
                    }
                    .buttonStyle(NotchButtonStyle())
                    .disabled(assistant.busy != nil)
                    .help("Buys what's missing for about \(expected) cups, the day the forecast suggests")
                }
            }
            Text(assistant.busy.map { $0 + "..." } ?? assistant.lastResult ?? (short ? "Serves \(s.cupsServable) cups; the forecast wants about \(expected)." : "Serves \(s.cupsServable) cups, enough for about \(expected). Ready."))
                .font(LT.font(15)).foregroundStyle(assistant.busy == nil && (assistant.lastResult.map { $0.hasPrefix("Not enough") || $0.hasPrefix("The game") } ?? short) ? warnColor : LT.dim)
                .lineLimit(1)
            if !assistant.recipes.isEmpty {
                HStack(spacing: 5) {
                    Text("recipes").font(LT.font(15)).foregroundStyle(LT.dim)
                    ForEach(assistant.recipes.prefix(4)) { r in
                        Button { assistant.apply(r) } label: { Text(r.name) }
                            .buttonStyle(NotchButtonStyle())
                            .help("\(r.lemons) lemons, \(r.sugar) sugar, \(r.ice) ice at \(money(r.price))")
                    }
                }
            }
            if let tip = assistant.tips.first {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "lightbulb.fill").font(.system(size: 11)).foregroundStyle(LT.yellow).padding(.top, 2)
                    Text(tip).font(LT.font(15)).foregroundStyle(.white).minimumScaleFactor(0.75)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(LT.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LT.panelDark, lineWidth: 2))
    }

    private func stepper(_ label: String, _ value: String, _ nudge: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label).font(LT.font(15)).foregroundStyle(LT.dim)
            Button { nudge(-1) } label: { Text("-") }.buttonStyle(ChipStyle())
            Text(value).font(LT.font(18)).foregroundStyle(LT.yellow).frame(minWidth: 16)
            Button { nudge(1) } label: { Text("+") }.buttonStyle(ChipStyle())
        }
    }

    /// Away from the street (main menu, a question from the game): the whole
    /// screen, uncropped, beside a note on what to do.
    /// The game is asking something: the middle of the screen at 1x, clickable, so it can be answered here.
    private var question: some View {
        HStack(spacing: 12) {
            GameCrop(model: model, rect: NotchLayout.dialog, link: link)
                .frame(width: NotchLayout.dialog.width, height: NotchLayout.dialog.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(LT.panelDark, lineWidth: 2))
            VStack(alignment: .leading, spacing: 8) {
                Text("The game is asking").font(LT.font(22)).foregroundStyle(LT.yellow)
                Text("Answer right here, or open the full game.").font(LT.font(17)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func wholeScreen(height: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button(action: actions.full) {
                GameCrop(model: model, rect: CGRect(x: 0, y: 0, width: 640, height: 480))
                    .frame(width: height * 4 / 3, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(LT.panelDark, lineWidth: 2))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the full game")
            VStack(alignment: .leading, spacing: 8) {
                Text(s.screen == "menu" ? "Main menu" : "Lemonade Remixed")
                    .font(LT.font(24)).foregroundStyle(LT.yellow)
                Text("Start a career or load a save in the full game. Once your stand is open, you can run it from here.")
                    .font(LT.font(17)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
    }

    // MARK: Full: the whole game

    private var fullView: some View {
        VStack(spacing: NotchLayout.fullPad) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: -3) {
                    Text(model.hasGame ? "Day \(s.dayNumber) - \(s.locationName) - \(s.lowF)F to \(s.highF)F" : "Lemonade Remixed")
                        .font(LT.font(18)).foregroundStyle(.white).lineLimit(1)
                    Text(detailLine).font(LT.font(14)).foregroundStyle(LT.dim).lineLimit(1)
                }
                Spacer(minLength: 4)
                if model.running { fastButton }
                soundButton
                Button(action: actions.openWindow) { Label("Window", systemImage: "macwindow") }
                    .buttonStyle(NotchButtonStyle())
                    .help("Move the game to its own window")
                Button(action: actions.mini) { Label("Shrink", systemImage: "arrow.down.right.and.arrow.up.left") }
                    .buttonStyle(NotchButtonStyle(prominent: true))
                    .help("Back to the small view (or click anywhere else)")
            }
            .padding(.horizontal, 8)
            .frame(height: NotchLayout.header)
            .background(LT.panel)
            .overlay(alignment: .top) { LT.panelDark.frame(height: 2) }
            .overlay(alignment: .bottom) { LT.panelLight.frame(height: 1) }
            HostedView(view: gameView)
                .frame(width: 640, height: 480)
                .overlay(Rectangle().stroke(LT.panelDark, lineWidth: 2))
        }
        .padding(NotchLayout.fullPad)
    }

    private var detailLine: String {
        guard model.hasGame else { return "Start or load a game." }
        if s.running == 1 { return "Selling: \(s.today.sold) cups, \(money(s.today.profit)) profit, \(s.today.missed) walked away" }
        let stock = "Stock serves \(s.cupsServable) cups at \(money(s.price))"
        return model.tip.map { stock + ".  " + $0 } ?? stock
    }
}

// MARK: - Windows

final class NotchPanel: NSPanel {
    var keyable = false
    override var canBecomeKey: Bool { keyable }
}

final class IslandHost: NSHostingView<IslandView> {
    var onClick: () -> Void = {}
    var onFast: () -> Void = {}
    var fastRect: () -> CGRect? = { nil }       // in view coordinates, top-left origin
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {
        let p = event.locationInWindow
        let top = CGPoint(x: p.x, y: bounds.height - p.y)
        if let r = fastRect(), r.insetBy(dx: -3, dy: -4).contains(top) { onFast() } else { onClick() }
    }
}

final class BodyHost: NSHostingView<BodyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController {
    let model = NotchModel()
    private let layout: NotchLayout
    private let game: GameView
    private let island: NotchPanel
    private let bodyPanel: NotchPanel
    private var monitors: [Any] = []
    private var roomTimer: Timer?

    private static func panel(_ rect: CGRect, level: Int) -> NotchPanel {
        let p = NotchPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: level)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false
        return p
    }

    /// Called when the notch opens from the island, so the app can put its window away:
    /// the game shows in one place at a time.
    var onOpen: () -> Void = {}

    init(screen: NSScreen, sound: Sound, link: GameLink, assistant: AssistantModel, openWindow: @escaping () -> Void) {
        layout = NotchLayout(screen: screen)
        game = GameView(link: link)
        model.right = layout.freeRight()
        island = Self.panel(layout.island(right: model.right), level: NSWindow.Level.statusBar.rawValue + 1)
        bodyPanel = Self.panel(layout.body(.collapsed), level: NSWindow.Level.statusBar.rawValue)
        bodyPanel.hasShadow = true

        let islandHost = IslandHost(rootView: IslandView(model: model, layout: layout))
        islandHost.sizingOptions = []
        island.contentView = islandHost

        var actions = NotchActions(openWindow: openWindow)
        weak var weakSelf: NotchController?
        actions.toggle = { weakSelf?.toggle() }
        actions.mini = { weakSelf?.set(.mini) }
        actions.full = { weakSelf?.set(.full) }
        actions.collapse = { weakSelf?.set(.collapsed) }
        let bodyHost = BodyHost(rootView: BodyView(model: model, sound: sound, assistant: assistant, link: link, gameView: game, actions: actions))
        bodyHost.sizingOptions = []
        bodyPanel.contentView = bodyHost
        weakSelf = self
        model.relayout = { [weak self] in
            guard let self, self.model.mode == .mini else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.bodyPanel.animator().setFrame(self.layout.body(.mini, view: self.model.viewHeight), display: true)
            }
        }

        islandHost.onClick = { [weak self] in self?.toggle() }
        islandHost.onFast = { [weak self] in
            guard let self else { return }
            assistant.setFast(self.model.state.fast != 1)
        }
        islandHost.fastRect = { [weak self] in
            guard let self, self.model.running, self.model.right > 0 else { return nil }
            return NotchLayout.fastGlyph.offsetBy(dx: NotchLayout.leftWing + self.layout.notch.width, dy: 0)
        }
        island.orderFrontRegardless()

        // Keep clear of other apps' menu-bar icons as they come and go.
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refreshRoom() }
        RunLoop.main.add(t, forMode: .common)
        roomTimer = t

        // Clicking anywhere else shrinks the full game to the street view; Esc too.
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.model.mode == .full { self?.set(.mini) }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.bodyPanel, e.keyCode == 53, self.model.mode == .full else { return e }
            self.set(.mini)
            return nil
        } as Any)
    }

    deinit { monitors.forEach(NSEvent.removeMonitor); roomTimer?.invalidate() }

    private func refreshRoom() {
        let r = layout.freeRight()
        guard r != model.right else { return }
        model.right = r
        island.setFrame(layout.island(right: r), display: true)
    }

    func start(frames url: URL) {
        model.start(frames: url)
        game.show(frames: url)
    }

    func close() { island.orderOut(nil); bodyPanel.orderOut(nil); roomTimer?.invalidate() }

    /// Clicking the notch: island -> street view -> island; from the full game, back to the street view.
    func toggle() { set(model.mode == .mini ? .collapsed : .mini) }

    func set(_ mode: NotchMode) {
        let old = model.mode
        guard mode != old else { return }
        if old == .collapsed {
            bodyPanel.setFrame(layout.body(.collapsed), display: false)
            bodyPanel.alphaValue = 0
            bodyPanel.orderFrontRegardless()
            island.orderFrontRegardless()
            onOpen()
        }
        model.mode = mode
        bodyPanel.keyable = mode == .full
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bodyPanel.animator().setFrame(layout.body(mode, view: model.viewHeight), display: true)
            bodyPanel.animator().alphaValue = mode == .collapsed ? 0 : 1
        }, completionHandler: { [weak self] in
            guard let self, self.model.mode == .collapsed else { return }
            self.bodyPanel.orderOut(nil)
        })
        if mode == .full {
            bodyPanel.makeKey()
            bodyPanel.makeFirstResponder(game)
        } else if bodyPanel.isKeyWindow {
            bodyPanel.resignKey()
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
        let i = island.frame
        note("island \(i) right \(model.right) mini \(layout.mini) full \(layout.full)")
        let steps: [(String, () -> Void)] = [
            ("click notch", { click(self.island, CGPoint(x: self.layout.notch.midX, y: i.midY)) }),
            ("click notch again", { click(self.island, CGPoint(x: i.minX + 40, y: i.midY)) }),
            ("click notch", { click(self.island, CGPoint(x: i.minX + 100, y: i.midY)) }),
            ("click street view", { let m = self.layout.mini; click(self.bodyPanel, CGPoint(x: m.midX, y: m.maxY - 100)) }),
            ("click the game's recipe tab", { let f = self.layout.full; click(self.bodyPanel, CGPoint(x: f.minX + 10 + 255, y: f.maxY - 64 - 87)) }),
            ("click notch from full", { click(self.island, CGPoint(x: self.layout.notch.midX, y: i.midY)) }),
        ]
        var t = 0.0
        for (name, act) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                act()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { note("\(name): mode \(self.model.mode)") }
            }
            t += 1.5
        }
    }
}
