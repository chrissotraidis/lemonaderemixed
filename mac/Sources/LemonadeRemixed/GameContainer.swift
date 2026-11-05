import AppKit
import SwiftUI

/// The game with the assistant beside it. Both scale together: the assistant
/// is measured in game pixels, so it always matches the picture.
final class GameContainer: NSView {
    let game: GameView
    let assistant = AssistantLayout()
    private var panel: NSHostingView<AssistantView>!
    var onToggle: () -> Void = {}

    init(game: GameView, model: AssistantModel) {
        self.game = game
        super.init(frame: .zero)
        panel = NSHostingView(rootView: AssistantView(model: model, layout: assistant, onToggle: { [weak self] in self?.onToggle() }))
        panel.sizingOptions = []
        addSubview(game)
        addSubview(panel)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Content width : height for the current panel state.
    var aspect: NSSize { NSSize(width: 640 + assistant.width, height: 480) }

    override func layout() {
        super.layout()
        let scale = bounds.height / 480
        if abs(assistant.px - scale) > 0.001 { assistant.px = scale }
        let w = (assistant.width * scale).rounded()
        game.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - w), height: bounds.height)
        panel.frame = CGRect(x: bounds.width - w, y: 0, width: w, height: bounds.height)
    }
}
