import Foundation
import RemixCore

/// A recipe the player saved: lemons, sugar and ice, plus a price.
struct SavedRecipe: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var lemons: Int, sugar: Int, ice: Int, price: Int
}

/// Live game state for the assistant, plus the actions it offers.
final class AssistantModel: ObservableObject {
    @Published private(set) var state = GameState()
    @Published private(set) var busy: String? { didSet { if (busy == nil) != (oldValue == nil) { onBusy?(busy != nil) } } }
    /// Called when an action starts or finishes (the notch holds its picture meanwhile).
    var onBusy: ((Bool) -> Void)?
    @Published private(set) var lastResult: String?
    @Published var recipes: [SavedRecipe] = [] { didSet { saveRecipes() } }
    @Published var basket = [Int](repeating: 0, count: 12)
    @Published var restockCups = 0
    /// Recipe and price clicked in the notch, sent to the game once the clicking stops.
    @Published private(set) var draftRecipe: [Int]?
    @Published private(set) var draftPrice: Int?
    private var sendDraft: DispatchWorkItem?
    /// Called with every new state (the notch uses it).
    var onState: ((GameState) -> Void)?

    private let work = DispatchQueue(label: "assistant")
    private var timer: Timer?
    private var polling = false

    init() {
        if let data = UserDefaults.standard.data(forKey: "recipes"),
           let saved = try? JSONDecoder().decode([SavedRecipe].self, from: data) { recipes = saved }
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        work.async { [weak self] in
            let line = Bridge.request("info", timeout: 2)
            let s = line.flatMap { try? JSONDecoder().decode(GameState.self, from: Data($0.utf8)) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                if let s { self.update(s) }
            }
        }
    }

    private func update(_ s: GameState) {
        let old = state
        if s != old { state = s }
        if restockCups == 0 || s.day != old.day { restockCups = Advisor.expectedCups(s) }
        if s.day != old.day { lastResult = nil }
        onState?(s)
    }

    /// The last finished day's report, while planning the next one.
    var report: GameState.Report? {
        let s = state
        guard s.isPlanning, s.day > 0, !s.report.isEmpty else { return nil }
        return s.report
    }

    /// The Advisor is offered while planning; during the day the game's own panel is left clear.
    var showsAdvisor: Bool { state.screen == "plan" }

    /// Something worth a nudge: not enough stock for the day, or rent pressure.
    var urgent: Bool {
        let s = state
        guard s.isPlanning else { return false }
        return s.cupsServable < 10 || (s.rent > 0 && s.cash < s.rent * 2)
    }

    var tips: [String] { Advisor.tips(state) }
    var restockPlan: [Int] { Advisor.restock(state, cups: restockCups) }

    // MARK: - Actions (each runs through the original interface)

    private func perform(_ label: String, _ commands: [String]) {
        guard busy == nil else { return }
        busy = label
        work.async { [weak self] in
            var replies: [String] = []
            for c in commands { replies.append(Bridge.request(c, timeout: 60) ?? "no reply") }
            DispatchQueue.main.async {
                self?.busy = nil
                self?.lastResult = Self.describe(label, replies)
            }
        }
    }

    /// A plain sentence for what an action did, e.g. "Bought 200 ice for $3.00".
    static func describe(_ label: String, _ replies: [String]) -> String {
        for r in replies where r.hasPrefix("bought ") {
            let parts = r.split(separator: " ")
            let got = parts.count > 1 ? parts[1].split(separator: ",").compactMap { Int($0) } : []
            let spent = parts.count > 3 ? Int(parts[3]) ?? 0 : 0
            let names = ["lemons", "sugar", "ice", "cups"]
            let items = zip(got, names).filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
            if items.isEmpty { return "Nothing was bought (not enough cash?)" }
            return "Bought " + items.joined(separator: ", ") + " for " + money(spent)
        }
        if replies.allSatisfy({ $0.hasPrefix("ok") }) { return "\(label): done" }
        if replies.contains(where: { $0.contains("dialog") }) { return "The game is asking something" }
        return "\(label): " + replies.joined(separator: "; ")
    }

    func buy(_ counts: [Int]) {
        guard counts.contains(where: { $0 > 0 }) else { return }
        perform("Buying", ["buy " + counts.map(String.init).joined(separator: " ")])
    }

    func buyBasket() { buy(basket); basket = [Int](repeating: 0, count: 12) }
    func restock() { buy(restockPlan) }
    /// Starts the day, unless there's nothing to sell: then it says so instead of
    /// letting the game stop you with its own message.
    func startDay() {
        guard state.cupsServable > 0 else {
            lastResult = "Not enough supplies for a single cup. Restock first."
            return
        }
        perform("Starting the day", ["startday"])
    }
    func skipDay() { work.async { _ = Bridge.request("skip", timeout: 5) } }

    var shownRecipe: [Int] { draftRecipe ?? state.recipe }
    var shownPrice: Int { draftPrice ?? state.price }

    /// One click on a recipe or price arrow: shown at once, sent when the clicking stops.
    func nudgeRecipe(_ i: Int, by d: Int) {
        var r = shownRecipe
        r[i] = min(20, max(i == 2 ? 0 : 1, r[i] + d))
        draftRecipe = r
        scheduleDraft()
    }

    func nudgePrice(by cents: Int) {
        draftPrice = min(1000, max(10, shownPrice + cents))
        scheduleDraft()
    }

    private func scheduleDraft() {
        sendDraft?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var commands: [String] = []
            if let r = self.draftRecipe, r != self.state.recipe { commands.append("recipe \(r[0]) \(r[1]) \(r[2])") }
            if let p = self.draftPrice, p != self.state.price { commands.append("price \(p)") }
            guard !commands.isEmpty else { self.draftRecipe = nil; self.draftPrice = nil; return }
            self.busy = "Updating"
            self.work.async {
                for c in commands { _ = Bridge.request(c, timeout: 30) }
                DispatchQueue.main.async { self.busy = nil; self.draftRecipe = nil; self.draftPrice = nil; self.poll() }
            }
        }
        sendDraft = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: item)
    }

    /// Fast-forward on or off, without the busy indicator (it's instant).
    func setFast(_ on: Bool) {
        work.async { _ = Bridge.request("fast " + (on ? "on" : "off"), timeout: 5) }
    }

    func apply(_ r: SavedRecipe) {
        perform(r.name, ["recipe \(r.lemons) \(r.sugar) \(r.ice)", "price \(r.price)"])
    }

    /// Saves the recipe and price in use, named after today's weather.
    func saveCurrent() {
        let s = state
        let kind = s.isRainy ? "Rainy" : s.highF >= 90 ? "Hot" : s.highF >= 75 ? "Warm" : "Cool"
        let n = recipes.filter { $0.name.hasPrefix(kind) }.count + 1
        recipes.append(SavedRecipe(name: n == 1 ? kind : "\(kind) \(n)",
                                   lemons: s.recipe[0], sugar: s.recipe[1], ice: s.recipe[2], price: s.price))
    }

    private func saveRecipes() {
        if let data = try? JSONEncoder().encode(recipes) { UserDefaults.standard.set(data, forKey: "recipes") }
    }
}
