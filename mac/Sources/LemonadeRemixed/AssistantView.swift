import RemixCore
import SwiftUI

/// Size and open state of the assistant, shared with the window layout.
final class AssistantLayout: ObservableObject {
    static let openWidth: CGFloat = 200     // game pixels
    static let closedWidth: CGFloat = 16
    @Published var px: CGFloat = 1.5
    @Published var open = true
    var width: CGFloat { open ? Self.openWidth : Self.closedWidth }
}

/// The assistant beside the game, drawn in the game's own style.
struct AssistantView: View {
    @ObservedObject var model: AssistantModel
    @ObservedObject var layout: AssistantLayout
    var onToggle: () -> Void = {}

    private var px: CGFloat { layout.px }
    private var s: GameState { model.state }
    private var canAct: Bool { s.isPlanning && model.busy == nil }

    var body: some View {
        ZStack {
            Stripes(px: px)
            if layout.open { openPanel } else { closedStrip }
        }
        .clipped()
    }

    // MARK: Layout

    private var closedStrip: some View {
        VStack {
            Spacer()
            ArrowButton(px: px, symbol: "◀", size: 12, action: onToggle).help("Show the assistant")
            Spacer()
        }
    }

    private var openPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4 * px) {
                ArrowButton(px: px, symbol: "▶", size: 10, action: onToggle).help("Hide the assistant")
                PixelText("Assistant", px: px, size: 17)
                Spacer()
                PixelText(s.screen == "stopped" ? "" : money(s.cash), px: px, size: 17, color: LT.yellow)
            }
            .padding(.horizontal, 5 * px).padding(.vertical, 3 * px)
            .background(LT.bar)
            .overlay(alignment: .bottom) { LT.panelDark.frame(height: px) }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 5 * px) {
                    if ["stopped", "menu", "unknown"].contains(s.screen) {
                        GamePanel(px: px) { PixelText("Start or load a game and the assistant will follow along.", px: px) }
                    } else {
                        if let r = model.report { reportPanel(r) }
                        todayPanel
                        if s.running == 0 {
                            recipesPanel
                            restockPanel
                            shopPanel
                        }
                    }
                    statusLine
                }
                .padding(5 * px)
            }
        }
    }

    // MARK: Panels

    private var todayPanel: some View {
        GamePanel(px: px) {
            VStack(alignment: .leading, spacing: 2 * px) {
                PixelText("Day \(s.dayNumber) - \(s.locationName)", px: px, size: 15)
                HStack(alignment: .firstTextBaseline, spacing: 4 * px) {
                    PixelText("\(s.lowF)F - \(s.highF)F", px: px, size: 17, color: LT.yellow)
                    PixelText(s.forecastWords, px: px, color: LT.dim)
                }
                if s.running == 1 {
                    row("Cups sold", "\(s.today.sold)")
                    row("Profit so far", money(s.today.profit))
                    row("Walked away", "\(s.today.missed)")
                } else {
                    row("Stock serves", "\(s.cupsServable) cups")
                    row("Recipe", "\(s.recipe[0]) lemons, \(s.recipe[1]) sugar, \(s.recipe[2]) ice")
                    row("Price", money(s.price))
                    ForEach(Array(model.tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 3 * px) {
                            PixelText("*", px: px, color: LT.yellow)
                            PixelText(tip, px: px)
                        }
                    }
                }
            }
        }
    }

    private func reportPanel(_ r: GameState.Report) -> some View {
        GamePanel(px: px, fill: LT.inset) {
            VStack(alignment: .leading, spacing: 2 * px) {
                HStack {
                    PixelText("Day \(s.day) results", px: px, size: 15)
                    Spacer()
                    Button("OK") { model.dismissedReportDay = s.day }.buttonStyle(GameButtonStyle(px: px))
                }
                row("Sold", "\(r.sold) cups for \(money(r.revenue))")
                row("Stock used / lost", "\(money(r.used)) / \(money(r.lost))")
                if r.rent + r.marketing > 0 { row("Rent and ads", money(r.rent + r.marketing)) }
                row("Earnings", money(r.earnings), highlight: true)
                if r.missed > 0 { PixelText("\(r.missed) customers walked away (price or waiting).", px: px, color: LT.dim) }
                if r.melted > 0 { PixelText("\(r.melted) ice cubes melted overnight.", px: px, color: LT.dim) }
            }
        }
    }

    private var recipesPanel: some View {
        GamePanel(px: px) {
            VStack(alignment: .leading, spacing: 3 * px) {
                PixelText("Saved recipes", px: px, size: 15)
                if model.recipes.isEmpty {
                    PixelText("Save today's recipe and price, then reuse them on any day.", px: px, color: LT.dim)
                }
                ForEach(model.recipes) { r in
                    HStack(spacing: 3 * px) {
                        VStack(alignment: .leading, spacing: 0) {
                            PixelText(r.name, px: px, color: LT.yellow)
                            PixelText("\(r.lemons)-\(r.sugar)-\(r.ice)  \(money(r.price))", px: px, size: 12, color: LT.dim)
                        }
                        Spacer()
                        Button("Use") { model.apply(r) }.buttonStyle(GameButtonStyle(px: px)).disabled(!canAct)
                        ArrowButton(px: px, symbol: "x") { model.recipes.removeAll { $0.id == r.id } }.help("Delete")
                    }
                }
                Button("Save current") { model.saveCurrent() }
                    .buttonStyle(GameButtonStyle(px: px)).disabled(s.recipe == [0, 0, 0])
            }
        }
    }

    private var restockPanel: some View {
        let plan = model.restockPlan
        let cost = Supplies.cost(plan)
        return GamePanel(px: px) {
            VStack(alignment: .leading, spacing: 3 * px) {
                PixelText("Restock", px: px, size: 15)
                HStack(spacing: 3 * px) {
                    PixelText("Enough for", px: px)
                    ArrowButton(px: px, symbol: "-") { model.restockCups = max(0, model.restockCups - 5) }
                    PixelText("\(model.restockCups)", px: px, color: LT.yellow).frame(minWidth: 16 * px)
                    ArrowButton(px: px, symbol: "+") { model.restockCups += 5 }
                    PixelText("cups", px: px)
                }
                PixelText(cost == 0 ? "You have enough." : describe(plan) + "  " + money(cost), px: px, color: LT.dim)
                Button("Restock") { model.restock() }
                    .buttonStyle(GameButtonStyle(px: px)).disabled(!canAct || cost == 0 || cost > s.cash)
            }
        }
    }

    private var shopPanel: some View {
        let cost = Supplies.cost(model.basket)
        return GamePanel(px: px) {
            VStack(alignment: .leading, spacing: 3 * px) {
                PixelText("Buy packs", px: px, size: 15)
                ForEach(0..<4, id: \.self) { item in
                    HStack(spacing: 2 * px) {
                        PixelText(Supplies.names[item], px: px).frame(width: 30 * px, alignment: .leading)
                        ForEach(0..<3, id: \.self) { k in packCell(item, k) }
                    }
                }
                HStack {
                    PixelText(money(cost), px: px, size: 15, color: LT.yellow)
                    Spacer()
                    Button("Clear") { model.basket = [Int](repeating: 0, count: 12) }
                        .buttonStyle(GameButtonStyle(px: px)).disabled(cost == 0)
                    Button("Buy") { model.buyBasket() }
                        .buttonStyle(GameButtonStyle(px: px)).disabled(!canAct || cost == 0 || cost > s.cash)
                }
            }
        }
    }

    private func packCell(_ item: Int, _ k: Int) -> some View {
        let i = item * 3 + k
        let p = Supplies.packs[item][k]
        return VStack(spacing: 0) {
            HStack(spacing: px) {
                ArrowButton(px: px, symbol: "-", size: 8) { model.basket[i] = max(0, model.basket[i] - 1) }
                PixelText("\(model.basket[i])", px: px, color: model.basket[i] > 0 ? LT.yellow : .white)
                    .frame(minWidth: 9 * px)
                ArrowButton(px: px, symbol: "+", size: 8) { model.basket[i] = min(20, model.basket[i] + 1) }
            }
            PixelText("x\(p.count)", px: px, size: 11, color: LT.dim)
        }
        .frame(maxWidth: .infinity)
        .help("\(p.count) for \(money(p.cents))")
    }

    @ViewBuilder private var statusLine: some View {
        if let busy = model.busy {
            PixelText(busy + "...", px: px, color: LT.yellow)
        } else if let r = model.lastResult {
            PixelText(r, px: px, size: 12, color: LT.dim)
        }
    }

    // MARK: Pieces

    private func row(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            PixelText(label, px: px, color: LT.dim)
            Spacer(minLength: 4 * px)
            PixelText(value, px: px, color: highlight ? LT.yellow : .white)
        }
    }

    private func describe(_ counts: [Int]) -> String {
        var parts: [String] = []
        for item in 0..<4 {
            let n = (0..<3).reduce(0) { $0 + counts[item * 3 + $1] * Supplies.packs[item][$1].count }
            if n > 0 { parts.append("\(n) \(Supplies.names[item].lowercased())") }
        }
        return parts.joined(separator: ", ")
    }
}
