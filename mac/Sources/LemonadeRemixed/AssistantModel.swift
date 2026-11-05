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
    @Published private(set) var busy: String?
    @Published private(set) var lastResult: String?
    @Published var recipes: [SavedRecipe] = [] { didSet { saveRecipes() } }
    @Published var basket = [Int](repeating: 0, count: 12)
    @Published var restockCups = 0
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
        onState?(s)
    }

    /// The last finished day's report, while planning the next one.
    var report: GameState.Report? {
        let s = state
        guard s.isPlanning, s.day > 0, !s.report.isEmpty else { return nil }
        return s.report
    }

    /// The Advisor is offered on the planning and day screens.
    var showsAdvisor: Bool { state.screen == "plan" || state.screen == "day" }

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
                self?.lastResult = replies.allSatisfy({ $0.hasPrefix("ok") || $0.hasPrefix("bought") }) ? "\(label): done" : "\(label): \(replies.joined(separator: "; "))"
            }
        }
    }

    func buy(_ counts: [Int]) {
        guard counts.contains(where: { $0 > 0 }) else { return }
        perform("Buying", ["buy " + counts.map(String.init).joined(separator: " ")])
    }

    func buyBasket() { buy(basket); basket = [Int](repeating: 0, count: 12) }
    func restock() { buy(restockPlan) }
    func startDay() { perform("Starting the day", ["startday"]) }

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
