import Foundation

// Achievements ("feats"). Each one watches a single number, like "quests
// finished" or "best streak", and unlocks when that number reaches its goal.

/// Reads the current value of the number a feat watches.
func statValue(_ save: Save, _ stat: StatName) -> Int {
    switch stat {
    case .quests: return save.counts.quests
    case .dailyClears: return save.counts.dailyClears
    case .bestStreak: return save.counts.bestStreak
    case .weekly: return save.counts.weekly
    case .monthly: return save.counts.monthly
    case .customMade: return save.counts.customMade
    case .customDone: return save.counts.customDone
    case .level: return levelInfo(save.xp).level
    case .items: return save.inventory.count
    case .slotsFilled: return Slot.allCases.filter { save.worn($0) != nil }.count
    case .mythics: return save.inventory.filter { Content.itemById[$0]?.rarity == .mythic }.count
    }
}

struct FeatProgress {
    var value: Int
    var goal: Int
    var done: Bool
}

/// Progress toward a feat, capped at its goal.
func featProgress(_ save: Save, _ feat: FeatDef) -> FeatProgress {
    let done = save.feats[feat.id] != nil
    let value = done ? feat.goal : min(feat.goal, statValue(save, feat.stat))
    return FeatProgress(value: value, goal: feat.goal, done: done)
}

/// Feats whose goal has been reached but which haven't been awarded yet.
func pendingFeats(_ save: Save) -> [FeatDef] {
    Content.feats.filter { save.feats[$0.id] == nil && statValue(save, $0.stat) >= $0.goal }
}
