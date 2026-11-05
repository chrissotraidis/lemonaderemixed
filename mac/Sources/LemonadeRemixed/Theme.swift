import AppKit
import CoreText
import SwiftUI

/// The original game's look, measured from its frames. Sizes are in game
/// pixels and multiplied by `px` (points per game pixel) so everything
/// scales with the game picture.
enum LT {
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    static let stripeA = rgb(0, 166, 49), stripeB = rgb(24, 174, 49)
    static let panel = rgb(0, 150, 49), panelDark = rgb(0, 73, 24), panelLight = rgb(49, 186, 90)
    static let inset = rgb(0, 130, 41)
    static let button = rgb(165, 215, 57), buttonHi = rgb(165, 227, 90), buttonShadow = rgb(0, 40, 0)
    static let bigButton = rgb(115, 203, 33)
    static let yellow = rgb(255, 255, 74)
    static let bar = rgb(8, 85, 16)
    static let dim = Color.white.opacity(0.72)

    /// VT323 (SIL Open Font License), bundled; close to the game's pixel type.
    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "VT323-Regular", withExtension: "ttf", subdirectory: "fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(_ size: CGFloat) -> Font { .custom("VT323", fixedSize: size) }
}

/// The game's diagonal two-tone stripes.
struct Stripes: View {
    let px: CGFloat
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(LT.stripeA))
            let band = 9 * px, period = 18 * px
            var x = -size.height
            while x < size.width + period {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + band, y: size.height))
                p.addLine(to: CGPoint(x: x + band + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.closeSubpath()
                ctx.fill(p, with: .color(LT.stripeB))
                x += period
            }
        }
    }
}

/// A recessed panel: dark top and left edges, a light bottom and right edge.
struct GamePanel<Content: View>: View {
    let px: CGFloat
    var fill: Color = LT.panel
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, 6 * px).padding(.vertical, 5 * px)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .overlay(alignment: .top) { LT.panelDark.frame(height: 2 * px) }
            .overlay(alignment: .leading) { LT.panelDark.frame(width: 2 * px) }
            .overlay(alignment: .bottom) { LT.panelLight.frame(height: px) }
            .overlay(alignment: .trailing) { LT.panelLight.frame(width: px) }
            .clipShape(RoundedRectangle(cornerRadius: 2 * px))
    }
}

/// The game's raised buttons: light green with a highlight and a dark shadow.
struct GameButtonStyle: ButtonStyle {
    let px: CGFloat
    var big = false
    func makeBody(configuration: Configuration) -> some View { Face(px: px, big: big, configuration: configuration) }

    private struct Face: View {
        let px: CGFloat, big: Bool
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(LT.font((big ? 17 : 13) * px))
                .foregroundStyle(.white)
                .padding(.horizontal, (big ? 7 : 5) * px).padding(.vertical, (big ? 2 : 1) * px)
                .background(pressed ? LT.bigButton : (big ? LT.bigButton : LT.button))
                .overlay(alignment: .top) { (pressed ? LT.buttonShadow : LT.buttonHi).frame(height: px) }
                .overlay(alignment: .leading) { (pressed ? LT.buttonShadow : LT.buttonHi).frame(width: px) }
                .overlay(alignment: .bottom) { (pressed ? LT.buttonHi : LT.buttonShadow).frame(height: px) }
                .overlay(alignment: .trailing) { (pressed ? LT.buttonHi : LT.buttonShadow).frame(width: px) }
                .saturation(enabled ? 1 : 0.35)
                .opacity(enabled ? 1 : 0.55)
        }
    }
}

/// A small square button with a yellow symbol, like the game's +/- buttons.
struct ArrowButton: View {
    let px: CGFloat
    let symbol: String
    var size: CGFloat = 10
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(LT.font(15 * px))
                .foregroundStyle(LT.yellow)
                .frame(width: size * px, height: size * px)
                .background(LT.bigButton)
                .overlay(alignment: .top) { LT.buttonHi.frame(height: px) }
                .overlay(alignment: .bottom) { LT.buttonShadow.frame(height: px) }
                .saturation(enabled ? 1 : 0.3)
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }
}

/// White pixel text in the game's style.
struct PixelText: View {
    let text: String
    let px: CGFloat
    var size: CGFloat = 13
    var color: Color = .white
    init(_ text: String, px: CGFloat, size: CGFloat = 13, color: Color = .white) {
        self.text = text; self.px = px; self.size = size; self.color = color
    }
    var body: some View {
        Text(text).font(LT.font(size * px)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}
