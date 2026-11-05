import AppKit
import SwiftUI

/// The game picture with the Advisor drawn over it.
final class GameContainer: NSView {
    let game: GameView
    let advisor = AdvisorState()
    private var overlay: OverlayHost!

    init(game: GameView, model: AssistantModel, sound: Sound) {
        self.game = game
        super.init(frame: .zero)
        overlay = OverlayHost(rootView: AdvisorOverlay(model: model, advisor: advisor, sound: sound))
        overlay.model = model
        overlay.advisor = advisor
        overlay.sizingOptions = []
        addSubview(game)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        game.frame = bounds
        game.layoutSubtreeIfNeeded()
        overlay.frame = game.convert(game.gameRect, to: self)
    }
}
