import AppKit
import RemixCore
import SwiftUI

/// Game-pixel rectangles for the Advisor, in the original 640x480 layout.
enum AdvisorGeometry {
    /// The button sits in the empty stripes between the speaker and Main Menu.
    static let button = CGRect(x: 40, y: 449, width: 96, height: 26)
    /// The panel opens exactly over the game's own left panel.
    static let panel = CGRect(x: 9, y: 119, width: 310, height: 288)
}

/// Open state of the Advisor (closed by default).
final class AdvisorState: ObservableObject {
    @Published var open = false
    @Published var seenReportDay = -1
}

/// The Advisor drawn over the game: a game-style button, and a panel that
/// opens in the game's left panel area like another tab.
struct AdvisorOverlay: View {
    @ObservedObject var model: AssistantModel
    @ObservedObject var advisor: AdvisorState
    @ObservedObject var sound: Sound

    var body: some View {
        GeometryReader { geo in
            let px = geo.size.width / 640
            ZStack(alignment: .topLeading) {
                if model.showsAdvisor {
                    if advisor.open {
                        AdvisorPanel(model: model, sound: sound, px: px, close: { advisor.open = false })
                            .frame(width: AdvisorGeometry.panel.width * px, height: AdvisorGeometry.panel.height * px)
                            .offset(x: AdvisorGeometry.panel.minX * px, y: AdvisorGeometry.panel.minY * px)
                            .transition(.opacity)
                    }
                    button(px)
                        .offset(x: AdvisorGeometry.button.minX * px, y: AdvisorGeometry.button.minY * px)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.easeOut(duration: 0.12), value: advisor.open)
        }
    }

    private var hasNews: Bool {
        guard !advisor.open else { return false }
        let s = model.state
        return (model.report != nil && advisor.seenReportDay != s.day) || model.urgent
    }

    private func button(_ px: CGFloat) -> some View {
        Button {
            advisor.open.toggle()
            if advisor.open { advisor.seenReportDay = model.state.day }
        } label: {
            HStack(spacing: 3 * px) {
                BubbleIcon(px: px, mark: hasNews ? "!" : "?")
                Text("advisor").font(LT.font(14 * px))
            }
            .frame(width: AdvisorGeometry.button.width * px - 12 * px, height: AdvisorGeometry.button.height * px - 4 * px)
        }
        .buttonStyle(GameButtonStyle(px: px, big: false))
        .overlay(alignment: .topTrailing) {
            if hasNews {
                Circle().fill(LT.yellow).frame(width: 6 * px, height: 6 * px)
                    .overlay(Circle().stroke(LT.buttonShadow, lineWidth: px))
                    .offset(x: 2 * px, y: -2 * px)
            }
        }
        .help(advisor.open ? "Close the advisor" : "Open the advisor: tips, the day's report, recipes and restocking")
    }
}

/// A small speech bubble like the game's customer reaction bubbles.
struct BubbleIcon: View {
    let px: CGFloat
    let mark: String
    var body: some View {
        ZStack {
            BubbleShape().fill(.white)
            BubbleShape().stroke(LT.buttonShadow, lineWidth: px)
            Text(mark).font(LT.font(12 * px)).foregroundStyle(LT.buttonShadow).offset(y: -1.5 * px)
        }
        .frame(width: 14 * px, height: 13 * px)
    }
}

struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.78)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: r.width * 0.18, height: r.width * 0.18))
        p.move(to: CGPoint(x: r.minX + r.width * 0.25, y: body.maxY - 0.5))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.5, y: body.maxY - 0.5))
        return p
    }
}

/// Hosts the overlay over the game picture. Only the button and the open
/// panel take clicks; everything else goes through to the game.
final class OverlayHost: NSHostingView<AdvisorOverlay> {
    var model: AssistantModel!
    var advisor: AdvisorState!

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard model.showsAdvisor, bounds.width > 0 else { return nil }
        let local = convert(point, from: superview)
        let px = bounds.width / 640
        let g = CGPoint(x: local.x / px, y: (isFlipped ? local.y : bounds.height - local.y) / px)
        if AdvisorGeometry.button.contains(g) || (advisor.open && AdvisorGeometry.panel.contains(g)) {
            return super.hitTest(point)
        }
        return nil
    }
}
