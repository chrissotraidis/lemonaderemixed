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
    /// Each side of the notch when both are free; the left side alone when the right is taken.
    static let wing: CGFloat = 96, soloWing: CGFloat = 120
    static let maxRight: CGFloat = wing
    /// How far the closed island dips below the notch, for the outline that joins its two sides.
    static let lip: CGFloat = 3
    static func leftWidth(right: CGFloat) -> CGFloat { right > 0 ? right : soloWing }
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
        if let forced = ProcessInfo.processInfo.environment["LEMONADE_NOTCH_RIGHT"].flatMap(Double.init) { return forced }   // testing
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
        let room = first - notch.maxX - 6
        return room < 22 ? 0 : min(Self.maxRight, room).rounded(.down)
    }

    func island(right: CGFloat) -> CGRect {
        let left = hasNotch ? Self.leftWidth(right: right) : 0
        return CGRect(x: notch.minX - left, y: top - Self.lip, width: left + notch.width + right, height: stripHeight + Self.lip)
    }

    static let miniWidth: CGFloat = 600, view = CGSize(width: 292, height: 108), viewScale: CGFloat = 2
    static let bar: CGFloat = 34, pad: CGFloat = 8
    /// The game's left half at 1x: stock bar, tabs and the tab's panel.
    /// (The left panel ends at x 324; its buttons sit on its bottom edge at y 423, as in the original.)
    static let menus = CGRect(x: 0, y: 0, width: 324, height: 432)
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
    var relayout: (() -> Void)?

    /// Height of the small view's picture: the game's menus and its questions need more room.
    var viewHeight: CGFloat {
        if screen == "dialog" { return NotchLayout.dialog.height }
        if screen == "plan" { return NotchLayout.menus.height }
        return NotchLayout.view.height * NotchLayout.viewScale
    }
    private var tap: FrameTap?
    private var timer: Timer?
    private var lastScan = Date.distantPast
    private var sinks = NSHashTable<FrameLayerView>.weakObjects()

    /// While an action clicks through the game's screens (restock, recipe, start day),
    /// the notch holds its picture and layout so none of that flickers by.
    @Published var hold = false {
        didSet {
            guard hold != oldValue else { return }
            heldScreen = state.screen
            if !hold { if let frame { for view in sinks.allObjects { view.show(frame) } }; relayout?() }
        }
    }
    private var heldScreen = "plan"
    /// The screen the notch shows: the real one, or the one from before an action started.
    var screen: String { hold ? heldScreen : state.screen }

    var inGame: Bool { ["plan", "day"].contains(screen) }
    /// A career is open, even if the game is asking a question right now.
    var hasGame: Bool { inGame || screen == "dialog" }
    var running: Bool { screen == "day" }

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
        if viewHeight != oldHeight { relayout?() }
    }

    private func tick() {
        guard let image = tap?.newFrame() else { return }
        frame = image
        if inGame, Date().timeIntervalSince(lastScan) > 1.5 || cart == nil {
            lastScan = Date()
            if let c = Self.findCart(image), c != cart { cart = c }
        }
        if !hold { for view in sinks.allObjects { view.show(image) } }
    }

    /// A strip of the town view with the cart cartAt game pixels from its left edge, kept inside the town view.
    func strip(width: CGFloat, height: CGFloat, cartAt: CGFloat) -> CGRect {
        let town = CGRect(x: 331, y: 123, width: 300, height: 241)
        let c = cart ?? CGPoint(x: town.midX, y: town.midY)
        let w = min(width, town.width), h = min(height, town.height)
        let x = (min(max(c.x - cartAt, town.minX), town.maxX - w)).rounded()
        let y = (min(max(c.y - h / 2, town.minY), town.maxY - h)).rounded()
        return CGRect(x: x, y: y, width: w, height: h)
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
    /// The small view or the full game is open below the notch.
    private var open: Bool { model.mode != .collapsed }
    /// Both sides of the notch in use; without room on the right, the left side carries everything.
    private var split: Bool { model.right > 0 }
    private var leftW: CGFloat { NotchLayout.leftWidth(right: model.right) }

    var body: some View {
        let h = layout.stripHeight
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: open ? 0 : 10, bottomTrailingRadius: open ? 0 : 10)
        HStack(spacing: 0) {
            if layout.hasNotch {
                left(h).frame(width: leftW)
                Color.clear.frame(width: layout.notch.width)
                if split { right(h).frame(width: model.right) }
            } else {
                left(h).frame(width: leftW)
            }
        }
        .frame(height: h)
        // Closed, the island dips a few points below the notch so a lemon outline can run
        // under it and tie both sides into one piece.
        .frame(height: open ? h : h + NotchLayout.lip, alignment: .top)
        .background(shape.fill(.black))
        .overlay(alignment: .topLeading) {
            if !open {
                let line = LT.yellow.opacity(model.pulse ? 1 : 0.8), width: CGFloat = model.pulse ? 2.5 : 1.5
                if split {
                    shape.inset(by: 0.75).stroke(line, lineWidth: width)
                } else {
                    // Left side only: the outline goes round just that side.
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).inset(by: 0.75)
                        .stroke(line, lineWidth: width).frame(width: leftW)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.3), value: model.pulse)
    }

    /// One strip of street cut in two by the notch: your cart centred on the left side,
    /// the street running on along the right side. Game pixels, top-left origin.
    private func halves(_ h: CGFloat) -> (CGRect, CGRect) {
        let gameH: CGFloat = 40
        let k = gameH / (h - 4)
        let lw = ((leftW - 4) * k).rounded(), rw = split ? ((model.right - 4) * k).rounded() : 0
        let strip = model.strip(width: lw + rw, height: gameH, cartAt: split ? lw / 2 : lw * 0.4)
        return (CGRect(x: strip.minX, y: strip.minY, width: lw, height: gameH),
                CGRect(x: strip.minX + lw, y: strip.minY, width: rw, height: gameH))
    }

    @ViewBuilder private func left(_ h: CGFloat) -> some View {
        if open {
            // The stand is on screen below: today's numbers instead.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if model.hasGame, let extra {
                    VStack(alignment: .trailing, spacing: -4) {
                        Text(extra.0).font(LT.font(h * 0.5)).foregroundStyle(.white)
                        Text(extra.1).font(LT.font(h * 0.38)).foregroundStyle(LT.dim)
                    }
                    .lineLimit(1).minimumScaleFactor(0.45)
                }
            }
            .padding(.trailing, 8)
        } else {
            // Just your stand. Clicking here opens the small view.
            street(halves(h).0, h, leading: true, alone: !split)
                .overlay(alignment: .bottomTrailing) { if !split { info(h).padding(2) } }
                .padding(.leading, 4)
        }
    }

    @ViewBuilder private func right(_ h: CGFloat) -> some View {
        if open {
            HStack(spacing: 0) {
                if model.hasGame { Text(money(s.cash)).font(LT.font(h * 0.56)).foregroundStyle(LT.yellow).lineLimit(1).minimumScaleFactor(0.6) }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
        } else {
            // The street goes on, with fast-forward and the numbers laid over it, small.
            // Clicking here toggles fast-forward while selling.
            street(halves(h).1, h, leading: false, alone: false)
                .overlay { if model.hasGame { info(h) } }
                .padding(.trailing, 4)
        }
    }

    /// A piece of the street, rounded only on its outer side so the two halves read as one view.
    @ViewBuilder private func street(_ rect: CGRect, _ h: CGFloat, leading: Bool, alone: Bool) -> some View {
        let r: CGFloat = 5
        let outer = alone || leading, inner = alone || !leading
        Group {
            if model.hasGame {
                GameCrop(model: model, rect: rect)
            } else {
                title(h, leading: leading)
            }
        }
        .id(model.hasGame)
        .transition(.opacity)
        .frame(maxWidth: .infinity).frame(height: h - 4)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: outer ? r : 0, bottomLeadingRadius: outer ? r : 0,
                                          bottomTrailingRadius: inner ? r : 0, topTrailingRadius: inner ? r : 0))
        .animation(.easeInOut(duration: 0.6), value: model.hasGame)
    }

    @State private var bob = false

    /// Before a career is open: the game's own main-menu art on its stripes. Left, the
    /// play! stand tile; right, the menu's lemon, gently bobbing. While the game
    /// starts, the stripes and the app icon.
    @ViewBuilder private func title(_ h: CGFloat, leading: Bool) -> some View {
        let menu = model.screen == "menu"
        ZStack {
            Stripes(px: 0.6)
            if menu && leading {
                GameCrop(model: model, rect: CGRect(x: 9, y: 61, width: 60, height: 50))   // play!
                    .frame(width: (h - 6) * 1.2, height: h - 6)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Group {
                    if menu {
                        GameCrop(model: model, rect: CGRect(x: 114, y: 62, width: 34, height: 32))   // the lemon
                            .frame(width: (h - 8) * 34 / 32, height: h - 8)
                    } else if leading {
                        Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
                            .aspectRatio(contentMode: .fit).frame(height: h - 8)
                    }
                }
                .rotationEffect(.degrees(bob ? 7 : -7))
                .offset(y: bob ? -1.5 : 1.5)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: bob)
                .onAppear { bob = true }
            }
        }
    }

    /// Fast-forward (while selling) and the numbers taking turns, small and see-through.
    private func info(_ h: CGFloat) -> some View {
        HStack(spacing: 2) {
            if model.running {
                Image(systemName: "forward.fill")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(s.fast == 1 ? LT.buttonShadow : LT.yellow)
                    .padding(.horizontal, 3).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(s.fast == 1 ? LT.yellow : .clear))
            }
            slide(h)
        }
        .padding(.horizontal, 3).padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.5)))
        .help(model.running ? (s.fast == 1 ? "Click for normal speed" : "Click to fast forward") : "")
    }

    /// Cash, then a note, then cash again, crossfading slowly.
    private func slide(_ h: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let items = slides
            let i = Int(ctx.date.timeIntervalSinceReferenceDate / 3) % max(1, items.count)
            let item = items[min(i, items.count - 1)]
            ZStack {
                Text(item.text).font(LT.font(h * 0.42)).foregroundStyle(item.color)
                    .lineLimit(1).minimumScaleFactor(0.45)
                    .id(items.count > 1 ? i : 0)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.7), value: i)
        }
    }

    private struct Slide { var text: String; var color: Color }

    private var slides: [Slide] {
        guard model.hasGame else { return [Slide(text: "play", color: LT.yellow)] }
        if model.pulse, !s.report.isEmpty {
            return [Slide(text: signedMoney(s.report.earnings), color: s.report.earnings < 0 ? warnColor : LT.yellow)]
        }
        let cash = Slide(text: money(s.cash), color: LT.yellow)
        var notes: [Slide] = []
        if model.running {
            notes.append(Slide(text: "\(s.today.sold) sold", color: .white))
            notes.append(Slide(text: signedMoney(s.today.profit), color: s.today.profit < 0 ? warnColor : .white))
            if s.today.missed > 0 { notes.append(Slide(text: "\(s.today.missed) left", color: warnColor)) }
        } else if model.screen == "plan" {
            let short = s.cupsServable < Advisor.expectedCups(s)
            notes.append(short ? Slide(text: "restock", color: warnColor) : Slide(text: "\(s.cupsServable) cups", color: .white))
            notes.append(Slide(text: "\(s.highF)F", color: .white))
        }
        return notes.isEmpty ? [cash] : notes.flatMap { [cash, $0] }
    }

    /// While open: sales during the day, yesterday while planning.
    private var extra: (String, String)? {
        if model.running { return ("\(s.today.sold) sold", "\(s.today.missed) walked away") }
        if model.screen == "plan", s.day > 0, !s.report.isEmpty { return (signedMoney(s.report.earnings), "yesterday") }
        return nil
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

    /// Your cash, always in the same place: the bottom row of the small view and the
    /// full game's header. Under it, today's profit while selling, else yesterday's.
    @ViewBuilder private var cashChip: some View {
        if model.hasGame {
            let sub: (String, Int)? = model.running ? (signedMoney(s.today.profit) + " today", s.today.profit)
                : (s.day > 0 && !s.report.isEmpty ? (signedMoney(s.report.earnings) + " yesterday", s.report.earnings) : nil)
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(LT.yellow)
                VStack(alignment: .leading, spacing: -4) {
                    Text(money(s.cash)).font(LT.font(22)).foregroundStyle(LT.yellow)
                    if let sub { Text(sub.0).font(LT.font(13)).foregroundStyle(sub.1 < 0 ? warnColor : LT.dim) }
                }
                .lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 8).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 5).fill(LT.panelDark))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(LT.yellow.opacity(0.35), lineWidth: 1))
            .help("Your cash")
        }
    }

    // MARK: Mini: the street while selling, the day's plan before

    private var miniView: some View {
        let size = CGSize(width: NotchLayout.view.width * NotchLayout.viewScale, height: NotchLayout.view.height * NotchLayout.viewScale)
        let height = model.viewHeight
        return VStack(spacing: NotchLayout.pad) {
            Group {
                if model.running {
                    street(width: NotchLayout.view.width, height: size.height)
                } else if model.screen == "plan" {
                    // Planning: the quick plan beside the game's own stock bar, tabs and panel.
                    HStack(spacing: NotchLayout.pad) {
                        VStack(spacing: NotchLayout.pad) {
                            street(width: (size.width - NotchLayout.menus.width - NotchLayout.pad) / 2, height: 150)
                                .overlay(alignment: .bottomLeading) {
                                    Text("Day \(s.dayNumber)  \(s.locationName)").font(LT.font(15)).foregroundStyle(LT.yellow)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.65)))
                                        .padding(6)
                                        .allowsHitTesting(false)
                                }
                            planner
                        }
                        GameCrop(model: model, rect: NotchLayout.menus, link: link)
                            .frame(width: NotchLayout.menus.width, height: NotchLayout.menus.height)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LT.panelDark, lineWidth: 2))
                    }
                } else if model.screen == "dialog" {
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
                cashChip
                Spacer()
                if model.running {
                    Button(action: assistant.skipDay) { Label("Skip", systemImage: "forward.end.fill") }
                        .buttonStyle(NotchButtonStyle())
                        .help("Play out the rest of the day at once")
                    fastButton
                }
                if model.screen == "plan" {
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

    /// The everyday plan in a narrow column: forecast, recipe and price, restock,
    /// what happened, a tip. The game's own stock bar, tabs and panel sit beside it.
    private var planner: some View {
        let expected = Advisor.expectedCups(s)
        let short = s.cupsServable < expected
        let plan = Advisor.restock(s, cups: expected)
        let recipe = assistant.shownRecipe
        let warn = assistant.busy == nil && (assistant.lastResult.map { $0.hasPrefix("Not enough") || $0.hasPrefix("The game") } ?? short)
        let status = assistant.busy.map { $0 + "..." } ?? assistant.lastResult
            ?? (short ? "Serves \(s.cupsServable) cups; the forecast wants about \(expected)." : "Serves \(s.cupsServable) cups, enough for about \(expected). Ready.")
        return VStack(alignment: .leading, spacing: 7) {
            Text("\(s.lowF)-\(s.highF)F \(s.forecastWords)").font(LT.font(18)).foregroundStyle(LT.yellow)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.rent > 0 ? "rent \(money(s.rent)) a day" : "no rent here").font(LT.font(14)).foregroundStyle(LT.dim)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    stepper("lemons", "\(recipe[0])") { assistant.nudgeRecipe(0, by: $0) }
                    stepper("sugar", "\(recipe[1])") { assistant.nudgeRecipe(1, by: $0) }
                }
                GridRow {
                    stepper("ice", "\(recipe[2])") { assistant.nudgeRecipe(2, by: $0) }
                    stepper("price", money(assistant.shownPrice)) { assistant.nudgePrice(by: $0 * 10) }
                }
            }
            if short {
                Button(action: assistant.restock) {
                    Label("Restock " + money(Supplies.cost(plan)), systemImage: "cart.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(NotchButtonStyle())
                .disabled(assistant.busy != nil)
                .help("Buys what's missing for about \(expected) cups, the day the forecast suggests")
            }
            Text(status).font(LT.font(15)).foregroundStyle(warn ? warnColor : LT.dim)
                .fixedSize(horizontal: false, vertical: true)
            if !assistant.recipes.isEmpty {
                HStack(spacing: 5) {
                    ForEach(assistant.recipes.prefix(3)) { r in
                        Button { assistant.apply(r) } label: { Text(r.name) }
                            .buttonStyle(NotchButtonStyle())
                            .help("Saved recipe: \(r.lemons) lemons, \(r.sugar) sugar, \(r.ice) ice at \(money(r.price))")
                    }
                }
            }
            if let tip = assistant.tips.first {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "lightbulb.fill").font(.system(size: 11)).foregroundStyle(LT.yellow).padding(.top, 2)
                    Text(tip).font(LT.font(15)).foregroundStyle(.white).minimumScaleFactor(0.7)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                Text(model.screen == "menu" ? "Main menu" : "Lemonade Remixed")
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
                cashChip
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
            guard let self, self.model.running, self.model.mode == .collapsed else { return nil }
            let left = NotchLayout.leftWidth(right: self.model.right)
            if self.model.right > 0 {   // the whole right side
                return CGRect(x: left + self.layout.notch.width, y: 0, width: self.model.right, height: self.layout.stripHeight + NotchLayout.lip)
            }
            return CGRect(x: left / 2, y: 0, width: left / 2, height: self.layout.stripHeight)   // the info corner
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
