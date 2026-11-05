import RemixCore
import SwiftUI

/// The Advisor's content, in the game's style, sized to the game's left panel.
struct AdvisorPanel: View {
    @ObservedObject var model: AssistantModel
    @ObservedObject var sound: Sound
    let px: CGFloat
    let close: () -> Void

    private var s: GameState { model.state }
    private var canAct: Bool { s.isPlanning && model.busy == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Advisor").font(LT.font(26 * px)).foregroundStyle(.white)
                Spacer()
                soundControls
                Button("close", action: close).buttonStyle(GameButtonStyle(px: px))
            }
            .padding(.bottom, 2 * px)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4 * px) {
                    if let r = model.report { reportBox(r) }
                    todayBox
                    if s.running == 0 {
                        HStack(alignment: .top, spacing: 4 * px) {
                            VStack(spacing: 4 * px) { restockBox; recipesBox }
                            shopBox
                        }
                    }
                    statusLine
                }
            }
        }
        .padding(.horizontal, 8 * px).padding(.vertical, 6 * px)
        .background(LT.panel)
        .overlay(alignment: .top) { LT.panelDark.frame(height: 2 * px) }
        .overlay(alignment: .leading) { LT.panelDark.frame(width: 2 * px) }
        .overlay(alignment: .bottom) { LT.panelLight.frame(height: px) }
        .overlay(alignment: .trailing) { LT.panelLight.frame(width: px) }
    }

    // MARK: Boxes

    private var soundControls: some View {
        HStack(spacing: 2 * px) {
            ArrowButton(px: px, symbol: sound.muted ? "x" : "-", size: 9) { sound.step(-25) }
                .help("Quieter")
            PixelText(sound.muted ? "muted" : "vol \(sound.volume)", px: px, size: 12, color: LT.dim)
                .frame(minWidth: 30 * px)
                .onTapGesture { sound.muted.toggle() }
                .help("Click to mute or unmute (Cmd-M)")
            ArrowButton(px: px, symbol: "+", size: 9) { sound.step(25) }
                .help("Louder")
        }
    }

    private var todayBox: some View {
        box {
            HStack(alignment: .firstTextBaseline, spacing: 4 * px) {
                PixelText("Day \(s.dayNumber)", px: px, size: 15)
                PixelText(s.locationName, px: px, color: LT.dim)
                Spacer()
                PixelText("\(s.lowF)F - \(s.highF)F", px: px, size: 15, color: LT.yellow)
            }
            if s.running == 1 {
                HStack(spacing: 10 * px) {
                    stat("sold", "\(s.today.sold)")
                    stat("profit", money(s.today.profit))
                    stat("walked away", "\(s.today.missed)")
                }
            } else {
                HStack(spacing: 10 * px) {
                    stat("stock serves", "\(s.cupsServable) cups")
                    stat("recipe", "\(s.recipe[0])-\(s.recipe[1])-\(s.recipe[2])")
                    stat("price", money(s.price))
                }
                ForEach(Array(model.tips.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .top, spacing: 3 * px) {
                        PixelText("*", px: px, color: LT.yellow)
                        PixelText(tip, px: px, size: 12)
                    }
                }
            }
        }
    }

    private func reportBox(_ r: GameState.Report) -> some View {
        box {
            HStack(alignment: .firstTextBaseline) {
                PixelText("Day \(s.day) report", px: px, size: 15)
                Spacer()
                PixelText("earned " + money(r.earnings), px: px, size: 15, color: LT.yellow)
            }
            PixelText("Sold \(r.sold) cups for \(money(r.revenue)). Stock used \(money(r.used)), lost \(money(r.lost))."
                      + (r.rent + r.marketing > 0 ? " Rent and ads \(money(r.rent + r.marketing))." : ""), px: px, size: 12)
            let notes = [r.missed > 0 ? "\(r.missed) walked away" : nil, r.melted > 0 ? "\(r.melted) ice cubes melted" : nil].compactMap { $0 }
            if !notes.isEmpty { PixelText(notes.joined(separator: ", ") + ".", px: px, size: 12, color: LT.dim) }
        }
    }

    private var restockBox: some View {
        let plan = model.restockPlan
        let cost = Supplies.cost(plan)
        return box {
            PixelText("Restock", px: px, size: 15)
            HStack(spacing: 2 * px) {
                ArrowButton(px: px, symbol: "-", size: 9) { model.restockCups = max(0, model.restockCups - 5) }
                PixelText("\(model.restockCups) cups", px: px, color: LT.yellow).frame(minWidth: 34 * px)
                ArrowButton(px: px, symbol: "+", size: 9) { model.restockCups += 5 }
            }
            PixelText(cost == 0 ? "You have enough." : describe(plan) + " " + money(cost), px: px, size: 12, color: LT.dim)
            Button("restock") { model.restock() }
                .buttonStyle(GameButtonStyle(px: px)).disabled(!canAct || cost == 0 || cost > s.cash)
        }
    }

    private var recipesBox: some View {
        box {
            PixelText("Recipes", px: px, size: 15)
            ForEach(model.recipes) { r in
                HStack(spacing: 2 * px) {
                    Button(r.name) { model.apply(r) }.buttonStyle(GameButtonStyle(px: px)).disabled(!canAct)
                        .help("\(r.lemons) lemons, \(r.sugar) sugar, \(r.ice) ice at \(money(r.price))")
                    PixelText("\(r.lemons)-\(r.sugar)-\(r.ice) \(money(r.price))", px: px, size: 11, color: LT.dim)
                    Spacer(minLength: 0)
                    ArrowButton(px: px, symbol: "x", size: 8) { model.recipes.removeAll { $0.id == r.id } }
                }
            }
            Button("save today's") { model.saveCurrent() }
                .buttonStyle(GameButtonStyle(px: px)).disabled(s.recipe == [0, 0, 0])
        }
    }

    private var shopBox: some View {
        let cost = Supplies.cost(model.basket)
        return box {
            PixelText("Buy packs", px: px, size: 15)
            ForEach(0..<4, id: \.self) { item in
                VStack(alignment: .leading, spacing: 0) {
                    PixelText(Supplies.names[item], px: px, size: 12, color: LT.dim)
                    HStack(spacing: 2 * px) { ForEach(0..<3, id: \.self) { k in packCell(item, k) } }
                }
            }
            HStack {
                PixelText(money(cost), px: px, size: 15, color: LT.yellow)
                Spacer()
                Button("buy") { model.buyBasket() }
                    .buttonStyle(GameButtonStyle(px: px)).disabled(!canAct || cost == 0 || cost > s.cash)
            }
        }
    }

    private func packCell(_ item: Int, _ k: Int) -> some View {
        let i = item * 3 + k
        let p = Supplies.packs[item][k]
        return HStack(spacing: 0) {
            ArrowButton(px: px, symbol: "-", size: 7) { model.basket[i] = max(0, model.basket[i] - 1) }
            PixelText(model.basket[i] > 0 ? "\(model.basket[i])x\(p.count)" : "\(p.count)", px: px, size: 11,
                      color: model.basket[i] > 0 ? LT.yellow : .white)
                .frame(minWidth: 24 * px)
            ArrowButton(px: px, symbol: "+", size: 7) { model.basket[i] = min(20, model.basket[i] + 1) }
        }
        .help("\(p.count) for \(money(p.cents))")
    }

    @ViewBuilder private var statusLine: some View {
        if let busy = model.busy {
            PixelText(busy + "...", px: px, size: 12, color: LT.yellow)
        } else if let r = model.lastResult {
            PixelText(r, px: px, size: 11, color: LT.dim)
        }
    }

    // MARK: Pieces

    private func box<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2 * px) { content() }
            .padding(4 * px)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LT.inset)
            .overlay(alignment: .top) { LT.panelDark.frame(height: px) }
            .overlay(alignment: .leading) { LT.panelDark.frame(width: px) }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PixelText(label, px: px, size: 11, color: LT.dim)
            PixelText(value, px: px, size: 14)
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
