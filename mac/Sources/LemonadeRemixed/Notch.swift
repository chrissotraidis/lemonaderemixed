import AppKit
import RemixCore
import SwiftUI

/// What the notch shows.
enum NotchMode { case collapsed, peek, play }

/// Geometry of the notch on one screen, in points.
struct NotchGeometry {
    let screen: NSScreen
    var height: CGFloat { max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) }
    var notchWidth: CGFloat {
        guard let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return 0 }
        return max(0, r.minX - l.maxX)
    }
    static let wing: CGFloat = 104

    func size(_ mode: NotchMode) -> CGSize {
        let collapsedWidth = notchWidth + 2 * Self.wing
        switch mode {
        case .collapsed: return CGSize(width: collapsedWidth, height: height)
        case .peek: return CGSize(width: max(collapsedWidth, 360), height: height + 334)
        case .play: return CGSize(width: max(collapsedWidth, 664), height: height + 480 + 40)
        }
    }
}

/// Frames and game state for the notch.
final class NotchModel: ObservableObject {
    @Published var mode: NotchMode = .collapsed
    @Published var frame: CGImage?
    @Published var state = GameState()
    @Published var cartRect: CGRect?        // game pixels
    @Published var pulse = false
    var tip: String?
    private var tap: FrameTap?
    private var timer: Timer?
    private var lastScan = Date.distantPast

    func start(frames url: URL) {
        tap = FrameTap(url: url)
        let t = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func update(_ s: GameState, tip: String?) {
        if state.running == 1 && s.running == 0 && s.day == state.day + 1 {
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.pulse = false }
        }
        self.tip = tip
        if s != state { state = s }
    }

    private func tick() {
        guard let image = tap?.newFrame() else { return }
        frame = image
        if Date().timeIntervalSince(lastScan) > 1.5 || cartRect == nil {
            lastScan = Date()
            cartRect = Self.findCart(image)
        }
    }

    /// The lemonade cart in the town view, found by its blue-and-yellow umbrella.
    static func findCart(_ image: CGImage) -> CGRect? {
        guard let data = image.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return nil }
        let stride = image.bytesPerRow
        var minX = 640, minY = 480, maxX = 0, maxY = 0, n = 0
        for y in Swift.stride(from: 122, to: 365, by: 1) {
            for x in Swift.stride(from: 330, to: 637, by: 1) {
                let o = y * stride + x * 4      // BGRX
                let b = Int(p[o]), g = Int(p[o + 1]), r = Int(p[o + 2])
                if r < 40 && g >= 40 && g <= 75 && b >= 200 {
                    n += 1; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard n >= 8, maxX - minX < 60, maxY - minY < 40 else { return nil }
        let cx = CGFloat(minX + maxX) / 2, top = CGFloat(minY)
        return CGRect(x: cx - 40, y: top - 8, width: 80, height: 50).intersection(CGRect(x: 330, y: 122, width: 307, height: 243))
    }
}

/// A crop of the live game picture with sharp pixels.
struct GameCrop: View {
    let image: CGImage?
    let rect: CGRect
    var body: some View {
        if let image, let piece = image.cropping(to: rect.integral) {
            Image(decorative: piece, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

/// The notch content: wings around the notch, the peek and the full game.
struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var sound: Sound
    let geometry: NotchGeometry
    let gameView: NSView
    var startDay: () -> Void
    var skip: () -> Void
    var openWindow: () -> Void

    private var s: GameState { model.state }
    private let px: CGFloat = 1

    var body: some View {
        let size = geometry.size(model.mode)
        let full = geometry.size(.play)
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: model.mode == .collapsed ? 12 : 22,
                                   bottomTrailingRadius: model.mode == .collapsed ? 12 : 22)
                .fill(.black)
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: model.mode == .collapsed ? 12 : 22,
                                           bottomTrailingRadius: model.mode == .collapsed ? 12 : 22)
                        .stroke(model.pulse ? LT.yellow : .clear, lineWidth: 1.5)
                )
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(model.mode == .collapsed ? 0 : 0.45), radius: 12, y: 6)
            VStack(spacing: 0) {
                wings.frame(height: geometry.height)
                switch model.mode {
                case .collapsed: EmptyView()
                case .peek: peek.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                case .play: play.transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
        }
        .frame(width: full.width, height: full.height, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: model.mode)
        .animation(.easeInOut(duration: 0.3), value: model.pulse)
    }

    // MARK: Collapsed: the cart on the left, money and weather on the right

    private var wings: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if let r = model.cartRect, ["plan", "day"].contains(s.screen) {
                    GameCrop(image: model.frame, rect: r)
                        .frame(height: geometry.height - 4)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "cup.and.saucer.fill").foregroundStyle(LT.yellow)
                }
                if s.running == 1 {
                    Circle().fill(LT.bigButton).frame(width: 6, height: 6)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .frame(width: NotchGeometry.wing)
            Spacer().frame(width: geometry.notchWidth)
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                if s.screen != "stopped" {
                    weatherSymbol
                    VStack(alignment: .trailing, spacing: -3) {
                        Text(money(s.cash)).font(LT.font(geometry.height * 0.5)).foregroundStyle(LT.yellow)
                        Text(subline).font(LT.font(geometry.height * 0.34)).foregroundStyle(LT.dim)
                    }
                }
            }
            .padding(.trailing, 12)
            .frame(width: NotchGeometry.wing)
        }
    }

    private var subline: String {
        if s.running == 1 { return "\(s.today.sold) sold" }
        if s.screen == "plan" { return "day \(s.dayNumber) \(s.highF)F" }
        return "lemonade"
    }

    private var weatherSymbol: some View {
        let code = s.running == 1 ? s.weather[1] : s.weather.max() ?? 0
        let name = code == 0 ? "sun.max.fill" : code == 1 ? "cloud.sun.fill" : code <= 3 ? "cloud.fill" : "cloud.rain.fill"
        return Image(systemName: name)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: geometry.height * 0.38))
    }

    // MARK: Peek: the live town, today's numbers and big buttons

    private var peek: some View {
        VStack(spacing: 6) {
            Group {
                if ["plan", "day"].contains(s.screen) {
                    GameCrop(image: model.frame, rect: CGRect(x: 330, y: 122, width: 307, height: 243))
                } else {
                    GameCrop(image: model.frame, rect: CGRect(x: 0, y: 0, width: 640, height: 480))
                }
            }
            .frame(width: 307, height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { model.mode = .play }

            HStack(alignment: .firstTextBaseline) {
                PixelText("Day \(s.dayNumber)  \(s.locationName)", px: px, size: 16)
                Spacer()
                PixelText("\(s.lowF)F - \(s.highF)F", px: px, size: 16, color: LT.yellow)
            }
            HStack(alignment: .firstTextBaseline) {
                if s.running == 1 {
                    PixelText("\(s.today.sold) sold  \(money(s.today.profit)) profit  \(s.today.missed) walked", px: px, size: 14, color: LT.dim)
                } else {
                    PixelText(model.tip ?? "", px: px, size: 13, color: LT.dim).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                if s.screen == "plan" {
                    Button("start day", action: startDay).buttonStyle(GameButtonStyle(px: 1.2, big: true))
                } else if s.screen == "day" {
                    Button("skip", action: skip).buttonStyle(GameButtonStyle(px: 1.2, big: true))
                }
                Button("play") { model.mode = .play }.buttonStyle(GameButtonStyle(px: 1.2, big: true))
                Spacer()
                Button(sound.muted ? "sound off" : "sound on") { sound.muted.toggle() }
                    .buttonStyle(GameButtonStyle(px: 1.2))
            }
        }
        .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 12)
    }

    // MARK: Play: the full game

    private var play: some View {
        VStack(spacing: 0) {
            HostedView(view: gameView).frame(width: 640, height: 480)
            HStack(spacing: 6) {
                PixelText(money(s.cash), px: px, size: 18, color: LT.yellow)
                Spacer()
                Button(sound.muted ? "sound off" : "sound on") { sound.muted.toggle() }.buttonStyle(GameButtonStyle(px: 1.2))
                Button("window", action: openWindow).buttonStyle(GameButtonStyle(px: 1.2))
                Button("close") { model.mode = .collapsed }.buttonStyle(GameButtonStyle(px: 1.2))
            }
            .frame(height: 40)
            .padding(.horizontal, 12)
        }
    }
}

/// Puts an AppKit view inside SwiftUI.
struct HostedView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Hosts the notch content; only the black shape takes the mouse.
final class NotchHost: NSHostingView<NotchView> {
    var shape: () -> CGRect = { .zero }
    var onHover: (Bool) -> Void = { _ in }
    var onEscape: () -> Void = {}
    private var area: NSTrackingArea?

    func refreshTracking() {
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: shape(), options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return shape().contains(local) ? super.hitTest(point) : nil
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onEscape() } else { super.keyDown(with: event) } }
}

/// The notch window and its behaviour.
final class NotchController {
    let model = NotchModel()
    private let panel: NSPanel
    private let host: NotchHost
    private let geometry: NotchGeometry
    private var collapseWork: DispatchWorkItem?
    private var clickMonitor: Any?

    init(screen: NSScreen, sound: Sound, link: GameLink, startDay: @escaping () -> Void, openWindow: @escaping () -> Void) {
        geometry = NotchGeometry(screen: screen)
        let game = GameView(link: link)
        let full = geometry.size(.play)
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: full), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        let model = self.model
        host = NotchHost(rootView: NotchView(model: model, sound: sound, geometry: geometry, gameView: game,
                                             startDay: startDay, skip: { link.send("tap 603 352") }, openWindow: openWindow))
        host.sizingOptions = []
        panel.contentView = host
        let sf = screen.frame
        panel.setFrame(CGRect(x: sf.midX - full.width / 2, y: sf.maxY - full.height, width: full.width, height: full.height), display: true)
        host.shape = { [weak self] in self?.shapeRect ?? .zero }
        host.onHover = { [weak self] inside in self?.hover(inside) }
        host.onEscape = { [weak self] in self?.set(.collapsed) }
        host.refreshTracking()
        gameViewRef = game
        panel.orderFrontRegardless()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, self.model.mode != .collapsed else { return }
            self.set(.collapsed)
        }
    }

    private var gameViewRef: GameView?

    func start(frames url: URL) {
        model.start(frames: url)
        gameViewRef?.show(frames: url)
    }

    deinit { if let clickMonitor { NSEvent.removeMonitor(clickMonitor) } }

    func close() { panel.orderOut(nil) }

    /// The black shape in the host view's coordinates (bottom-left origin).
    private var shapeRect: CGRect {
        let s = geometry.size(model.mode), b = host.bounds
        return CGRect(x: (b.width - s.width) / 2, y: b.height - s.height, width: s.width, height: s.height)
    }

    private func hover(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            if model.mode == .collapsed { set(.peek) }
        } else if model.mode == .peek {
            let w = DispatchWorkItem { [weak self] in self?.set(.collapsed) }
            collapseWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
        }
    }

    func set(_ mode: NotchMode) {
        model.mode = mode
        if mode == .play { panel.makeKey() }
        DispatchQueue.main.async { self.host.refreshTracking() }
    }
}
