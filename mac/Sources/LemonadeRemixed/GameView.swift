import AppKit
import RemixCore

/// Shows the game and forwards the mouse to it. Sharp mode fills the window
/// with crisp pixels; pixel-perfect mode uses the largest whole-number scale
/// that fits (centred, with a border). Frames come from the agent's frame tap.
final class GameView: NSView {
    static let gameSize = CGSize(width: FrameTap.width, height: FrameTap.height)
    private let renderer = GameRenderer()
    private let link: GameLink
    private var tap: FrameTap?
    private var timer: Timer?
    private var lastMove = Date.distantPast

    var mode: PictureMode = .sharp {
        didSet { renderer?.mode = mode; needsLayout = true }
    }

    init(link: GameLink) {
        self.link = link
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        if let renderer { layer?.addSublayer(renderer.layer) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Starts drawing frames from the given frame file.
    func show(frames url: URL) {
        tap = FrameTap(url: url)
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let renderer, let tap else { return }
        if tap.withNewFrame({ renderer.upload($0) }) { renderer.draw() }
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Where the game is drawn, in points, aligned to screen pixels.
    var gameRect: CGRect {
        let s = Self.gameSize
        let backing = window?.backingScaleFactor ?? 2
        var k = min(bounds.width * backing / s.width, bounds.height * backing / s.height)
        if mode == .pixel { k = max(1, floor(k)) }
        let w = (s.width * k).rounded(.down) / backing, h = (s.height * k).rounded(.down) / backing
        let x = ((bounds.width - w) / 2 * backing).rounded() / backing
        let y = ((bounds.height - h) / 2 * backing).rounded() / backing
        return CGRect(x: x, y: y, width: w, height: h)
    }

    override func layout() {
        super.layout()
        guard let renderer else { return }
        let backing = window?.backingScaleFactor ?? 2
        let r = gameRect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderer.layer.frame = r
        renderer.layer.contentsScale = backing
        renderer.layer.drawableSize = CGSize(width: (r.width * backing).rounded(), height: (r.height * backing).rounded())
        CATransaction.commit()
        renderer.draw()
    }

    override func viewDidChangeBackingProperties() { needsLayout = true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    private func gamePoint(_ event: NSEvent) -> CGPoint? {
        let p = convert(event.locationInWindow, from: nil)
        let r = gameRect
        guard r.contains(p) else { return nil }
        let s = Self.gameSize
        return CGPoint(x: (p.x - r.minX) / r.width * s.width, y: (p.y - r.minY) / r.height * s.height)
    }

    override var acceptsFirstResponder: Bool { true }

    /// Typing (company names) goes to the game as characters.
    override func keyDown(with e: NSEvent) {
        guard let chars = e.characters, !chars.isEmpty, !e.modifierFlags.contains(.command) else { return super.keyDown(with: e) }
        switch e.keyCode {
        case 51: link.send("char \u{8}")
        case 36, 76: link.send("char \r")
        default: link.send("char " + chars)
        }
    }

    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(self); if let p = gamePoint(e) { link.mouse("down", p) } }
    override func mouseUp(with e: NSEvent) { if let p = gamePoint(e) { link.mouse("up", p) } }
    override func mouseDragged(with e: NSEvent) { move(e) }
    override func mouseMoved(with e: NSEvent) { move(e) }

    private func move(_ e: NSEvent) {
        guard Date().timeIntervalSince(lastMove) > 1.0 / 30, let p = gamePoint(e) else { return }
        lastMove = Date()
        link.mouse("move", p)
    }
}
