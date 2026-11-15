import Foundation

// XP, levels and loot.

/// XP for finishing a quest: harder and longer quests pay more.
func questXp(_ cadence: Cadence, _ difficulty: Int) -> Int {
    let table: [Int]
    switch cadence {
    case .daily: table = [20, 30, 45]
    case .weekly: table = [100, 125, 150]
    case .monthly: table = [400, 500, 600]
    }
    return table[min(max(difficulty, 1), 3) - 1]
}

/// Bonus for finishing every daily quest in one day.
let dailyClearXp = 25

/// XP needed to go from `level` to the next one. Each level asks for 50 more than the last.
func xpToNext(_ level: Int) -> Int {
    100 + 50 * (level - 1)
}

struct LevelInfo: Equatable {
    var level: Int
    /// XP earned so far inside the current level.
    var into: Int
    /// XP the current level needs in total.
    var need: Int
}

/// Works out the level from total XP by "spending" XP one level at a time.
func levelInfo(_ totalXp: Int) -> LevelInfo {
    var level = 1
    var left = max(0, totalXp)
    while left >= xpToNext(level) {
        left -= xpToNext(level)
        level += 1
    }
    return LevelInfo(level: level, into: left, need: xpToNext(level))
}

/// Rank titles, each unlocked at a level.
let ranks: [(level: Int, name: String)] = [
    (1, "Greenhand"),
    (5, "Delver"),
    (10, "Pathfinder"),
    (15, "Lanternbearer"),
    (20, "Deepwalker"),
    (25, "Barrow Warden"),
    (30, "Moonwarden"),
    (40, "Legend of the Loam"),
    (100, "Mythic Marl"),
]

func rankFor(_ level: Int) -> String {
    var title = ranks[0].name
    for rank in ranks where level >= rank.level {
        title = rank.name
    }
    return title
}

/// If `level` is exactly where a new rank begins, returns that rank.
func rankUnlockedAt(_ level: Int) -> String? {
    ranks.first { $0.level == level && $0.level > 1 }?.name
}

/// Items handed out for reaching a level: level -> item id.
let milestones: [Int: String] = {
    var out: [Int: String] = [:]
    for item in Catalog.items where item.source == .milestone {
        if let level = item.level { out[level] = item.id }
    }
    return out
}()

/// Chance that a quest digs something up at all.
private func dropChance(_ cadence: Cadence) -> Double {
    cadence == .daily ? 0.12 : 1
}

/// How likely each rarity is. Longer quests dig deeper.
private func rarityOdds(_ cadence: Cadence) -> [(Rarity, Double)] {
    switch cadence {
    case .daily: return [(.common, 70), (.uncommon, 25), (.rare, 5)]
    case .weekly: return [(.uncommon, 65), (.rare, 30), (.mythic, 5)]
    case .monthly: return [(.rare, 75), (.mythic, 25)]
    }
}

/// Bonus XP when a find turns out to be something already owned.
func echoXp(_ rarity: Rarity) -> Int {
    switch rarity {
    case .common: return 15
    case .uncommon: return 30
    case .rare: return 60
    case .mythic: return 120
    }
}

struct LootResult {
    var item: ItemDef
    /// False when the player already owns it (it becomes bonus XP instead).
    var fresh: Bool
}

/// Rolls for loot. Picks a rarity first, then an item of that rarity,
/// preferring ones the player doesn't have yet.
func rollLoot(_ cadence: Cadence, _ rng: inout SeededRng, owned: [String]) -> LootResult? {
    if rng.next() >= dropChance(cadence) { return nil }
    let rarity = weightedPick(rarityOdds(cadence), &rng)
    let pool = Catalog.items.filter { $0.source == .loot && $0.rarity == rarity }
    if pool.isEmpty { return nil }
    let unowned = pool.filter { !owned.contains($0.id) }
    let from = unowned.isEmpty ? pool : unowned
    let item = from[Int((rng.next() * Double(from.count)).rounded(.down))]
    return LootResult(item: item, fresh: !unowned.isEmpty)
}
