import AppKit

/// A black shape around the notch. Collapsed, it shows the game's own lemon
/// count and cash beside the notch; on hover it drops down into the full game.
final class NotchPanel: NSPanel {
    private let screenRef: NSScreen
    private let gameView: GameView
    private let leftInfo = CALayer.gamePixels()
    private let rightInfo = CALayer.gamePixels()
    private let shape = CAShapeLayer()
    private var expanded = false
    private var collapseTimer: Timer?

    private var notchHeight: CGFloat { max(screenRef.safeAreaInsets.top, 32) }
    private var notchWidth: CGFloat {
        guard let l = screenRef.auxiliaryTopLeftArea, let r = screenRef.auxiliaryTopRightArea else { return 200 }
        return r.minX - l.maxX
    }

    init(screen: NSScreen, mirror: GameMirror, link: GameLink) {
        screenRef = screen
        gameView = GameView(link: link)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false

        let root = HoverView()
        root.onHover = { [weak self] inside in self?.hover(inside) }
        root.wantsLayer = true
        root.layer?.addSublayer(shape)
        shape.fillColor = NSColor.black.cgColor
        for info in [leftInfo, rightInfo] { root.layer?.addSublayer(info) }
        leftInfo.showGameRegion(CGRect(x: 2, y: 2, width: 58, height: 28))     // lemons in stock
        rightInfo.showGameRegion(CGRect(x: 556, y: 2, width: 62, height: 26))  // cash
        mirror.attach(leftInfo)
        mirror.attach(rightInfo)
        mirror.attach(gameView.pixels)
        gameView.isHidden = true
        root.addSubview(gameView)
        contentView = root
        layout(animated: false)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { true }

    private func hover(_ inside: Bool) {
        collapseTimer?.invalidate()
        if inside {
            if !expanded { expanded = true; layout(animated: true) }
        } else {
            collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.expanded = false
                self.layout(animated: true)
            }
        }
    }

    private func layout(animated: Bool) {
        let h = notchHeight, wing: CGFloat = 92
        let size = expanded
            ? CGSize(width: 640 + 24, height: h + 480 + 14)
            : CGSize(width: notchWidth + wing * 2, height: h)
        let sf = screenRef.frame
        let frame = CGRect(x: sf.midX - size.width / 2, y: sf.maxY - size.height, width: size.width, height: size.height)
        setFrame(frame, display: true, animate: animated)

        let radius: CGFloat = expanded ? 22 : 12
        let path = CGMutablePath()
        let r = CGRect(origin: .zero, size: size)
        path.move(to: CGPoint(x: 0, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: radius))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: 0), tangent2End: CGPoint(x: r.maxX - radius, y: 0), radius: radius)
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: 0, y: radius), radius: radius)
        path.closeSubpath()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        let infoH = h - 8, scale = infoH / 28
        leftInfo.frame = CGRect(x: 14, y: 4, width: 58 * scale, height: infoH)
        rightInfo.frame = CGRect(x: size.width - 14 - 62 * scale, y: 4, width: 62 * scale, height: infoH)
        leftInfo.isHidden = expanded
        rightInfo.isHidden = expanded
        CATransaction.commit()
        gameView.frame = CGRect(x: 12, y: 2, width: 640, height: 480)
        gameView.isHidden = !expanded
    }
}

/// Reports when the mouse enters or leaves the panel.
final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
