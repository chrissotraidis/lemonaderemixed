import AppKit

/// Shows the full game at any size (4:3, letterboxed) and forwards the mouse to it.
final class GameView: NSView {
    let pixels = CALayer.gamePixels()
    private let link: GameLink
    private var lastMove = Date.distantPast

    init(link: GameLink) {
        self.link = link
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(pixels)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The largest 4:3 rectangle that fits, centred.
    var gameRect: CGRect {
        let s = GameMirror.gameSize
        let scale = min(bounds.width / s.width, bounds.height / s.height)
        let size = CGSize(width: s.width * scale, height: s.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pixels.frame = gameRect
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    private func gamePoint(_ event: NSEvent) -> CGPoint? {
        let p = convert(event.locationInWindow, from: nil)
        let r = gameRect
        guard r.contains(p) else { return nil }
        let s = GameMirror.gameSize
        return CGPoint(x: (p.x - r.minX) / r.width * s.width, y: (p.y - r.minY) / r.height * s.height)
    }

    override func mouseDown(with e: NSEvent) { if let p = gamePoint(e) { link.mouse("down", p) } }
    override func mouseUp(with e: NSEvent) { if let p = gamePoint(e) { link.mouse("up", p) } }
    override func mouseDragged(with e: NSEvent) { move(e) }
    override func mouseMoved(with e: NSEvent) { move(e) }

    private func move(_ e: NSEvent) {
        guard Date().timeIntervalSince(lastMove) > 1.0 / 30, let p = gamePoint(e) else { return }
        lastMove = Date()
        link.mouse("move", p)
    }
}
