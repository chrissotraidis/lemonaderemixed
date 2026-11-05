import Foundation

/// The game's state as published by the helper's `info` command (docs/STATE.md).
public struct GameState: Codable, Equatable {
    public struct Today: Codable, Equatable { public var sold = 0, profit = 0, missed = 0 }
    /// The game's own report for the last finished day.
    public struct Report: Codable, Equatable {
        public var sold = 0, revenue = 0, used = 0, lost = 0, rent = 0, marketing = 0, earnings = 0, missed = 0, melted = 0
        public var isEmpty: Bool { sold == 0 && revenue == 0 && used == 0 && lost == 0 }
    }
    public var screen = "stopped"
    public var cash = 0, price = 0
    public var recipe = [0, 0, 0]          // lemons, sugar per pitcher; ice per cup
    public var stock = [0, 0, 0, 0]        // lemons, sugar, ice, cups
    public var day = 0
    public var weather = [0, 0, 0]
    public var tempsC = [0, 0, 0]
    public var running = 0
    public var location = 0, rent = 0
    public var today = Today()
    public var report = Report()

    public init() {}

    public var isPlanning: Bool { screen == "plan" }
    public var dayNumber: Int { day + 1 }
    public var tempsF: [Int] { tempsC.map { Int((Double($0) * 9 / 5 + 32).rounded()) } }
    public var lowF: Int { tempsF.min() ?? 0 }
    public var highF: Int { tempsF.max() ?? 0 }
    public var isRainy: Bool { weather.contains { $0 >= 4 } }
    public var isSunny: Bool { weather.allSatisfy { $0 <= 1 } }

    /// Cups per pitcher: 8 plus 2 per ice cube (measured in the original).
    public var cupsPerPitcher: Int { 8 + 2 * recipe[2] }

    /// How many cups the current stock can serve with the current recipe.
    public var cupsServable: Int {
        let pitchers = min(recipe[0] > 0 ? stock[0] / recipe[0] : 999, recipe[1] > 0 ? stock[1] / recipe[1] : 999)
        let iceCups = recipe[2] > 0 ? stock[2] / recipe[2] : 999
        return max(0, min(pitchers * cupsPerPitcher, iceCups, stock[3]))
    }

    public static let locations = ["The Suburbs", "The Park", "Downtown", "The Train Station", "The Beach",
                                   "The Mall", "The Marina", "The Old Square", "The Magic Gardens", "The Hexa-Stad"]
    public var locationName: String { location >= 0 && location < Self.locations.count ? Self.locations[location] : "" }

    public static func weatherWord(_ code: Int) -> String {
        switch code {
        case 0: return "sunny"
        case 1: return "partly cloudy"
        case 2, 3: return "cloudy"
        case 4: return "showers"
        default: return "rain"
        }
    }
    public var forecastWords: String {
        var seen: [String] = []
        for w in weather.map(Self.weatherWord) where seen.last != w { seen.append(w) }
        return seen.joined(separator: ", then ")
    }
}

public func money(_ cents: Int) -> String {
    String(format: "%@$%d.%02d", cents < 0 ? "-" : "", abs(cents) / 100, abs(cents) % 100)
}

/// The supply packs (measured prices, in cents).
public enum Supplies {
    public static let names = ["Lemons", "Sugar", "Ice", "Cups"]
    public static let packs: [[(count: Int, cents: Int)]] = [
        [(12, 480), (24, 720), (48, 960)],
        [(12, 480), (20, 700), (50, 1500)],
        [(50, 100), (200, 300), (500, 500)],
        [(75, 100), (225, 235), (400, 375)],
    ]

    /// Cheapest packs of one item that cover at least `need` units.
    public static func cheapest(item: Int, need: Int) -> [Int] {
        guard need > 0 else { return [0, 0, 0] }
        let p = packs[item]
        var best = (cost: Int.max, counts: [0, 0, 0])
        let maxL = need / p[2].count + 1
        for l in 0...maxL {
            let restAfterL = max(0, need - l * p[2].count)
            for m in 0...(restAfterL / p[1].count + 1) {
                let rest = max(0, restAfterL - m * p[1].count)
                let s = (rest + p[0].count - 1) / p[0].count
                let cost = l * p[2].cents + m * p[1].cents + s * p[0].cents
                if cost < best.cost { best = (cost, [s, m, l]) }
            }
        }
        return best.counts
    }

    public static func cost(_ counts: [Int]) -> Int {
        var total = 0
        for item in 0..<4 { for k in 0..<3 { total += counts[item * 3 + k] * packs[item][k].cents } }
        return total
    }
}

/// Advice from the forecast, stock and yesterday's results. It never changes the rules.
public enum Advisor {
    /// Cups to plan for: yesterday's demand, scaled for the forecast.
    public static func expectedCups(_ s: GameState) -> Int {
        var base = Double(s.report.sold + s.report.missed)
        if base < 20 { base = 20 }
        if s.isRainy { base *= 0.6 } else if s.highF >= 90 { base *= 1.3 } else if s.highF < 65 { base *= 0.7 }
        return Int(base.rounded())
    }

    public static func tips(_ s: GameState) -> [String] {
        var t: [String] = []
        let ice = s.recipe[2]
        if s.highF >= 90 && ice < 4 {
            t.append("It's \(s.highF)°F today: add ice (4 or more cubes) so the lemonade stays cold, and keep the lemons and sugar in balance.")
        } else if s.highF < 70 && ice > 2 {
            t.append("A cool \(s.highF)°F: customers want less ice. Try 1 or 2 cubes.")
        }
        if s.isRainy {
            t.append("Rain in the forecast means fewer customers. Buy less and consider a lower price.")
        } else if s.highF >= 90 && s.isSunny {
            t.append("Hot and sunny: thirsty customers will pay more. Try raising the price.")
        }
        let want = expectedCups(s)
        if s.cupsServable < want {
            t.append("You can serve about \(s.cupsServable) cups but could sell around \(want). Restock before you start.")
        }
        if s.day > 0, !s.report.isEmpty, case let y = s.report, y.missed > 0, y.missed * 3 >= max(1, y.sold) {
            t.append("Yesterday \(y.missed) customers walked away. The price may be too high, or the line too slow (a cash register or helper speeds it up).")
        }
        if s.stock[2] > want * max(1, ice) * 2 {
            t.append("Ice melts every night. You have more than you'll need today.")
        }
        if s.rent > 0 && s.cash < s.rent * 3 {
            t.append("Cash is getting close to the daily rent of \(money(s.rent)). Cheaper locations are safer until profits pick up.")
        }
        if t.isEmpty { t.append("Looks good. Check the forecast, then start the day.") }
        return t
    }

    /// Packs to buy so the stock covers `cups` cups with the current recipe.
    public static func restock(_ s: GameState, cups: Int) -> [Int] {
        let pitchers = (cups + s.cupsPerPitcher - 1) / s.cupsPerPitcher
        let need = [pitchers * s.recipe[0], pitchers * s.recipe[1], cups * s.recipe[2], cups]
        var counts: [Int] = []
        for item in 0..<4 { counts += Supplies.cheapest(item: item, need: need[item] - s.stock[item]) }
        return counts
    }
}
