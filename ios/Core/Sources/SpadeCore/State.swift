import Foundation

// The rules of the game, as plain functions.
//
// Each function takes the current save and returns a NEW save, never changing
// the old one, plus a list of "events" describing what happened (XP gained,
// item found, level up). The screens read those events to decide what to
// celebrate. This file is a line-by-line port of the web version's state.ts,
// and the tests check that both give identical results.

/// Milliseconds since 1970, which is how the web version stamps times.
func millis(_ date: Date) -> Double {
    (date.timeIntervalSince1970 * 1000).rounded()
}

func newSave(seed: Int, now: Date) -> Save {
    Save(seed: seed, createdAt: millis(now))
}

private func dealContext(_ save: Save, _ cadence: Cadence) -> DealContext {
    DealContext(seed: save.seed, custom: save.custom, categories: save.settings.categories, recent: save.recent[cadence])
}

/// Brings the boards up to date with the clock. Call it whenever the app opens
/// or wakes: any board whose day, week or month has ended is replaced with a
/// fresh deal, and a streak that missed a day is put out.
func syncPeriods(_ save: Save, now: Date, clock: GameClock = .device) -> Save {
    var next = save
    for cadence in Cadence.allCases {
        let period = clock.periodKey(cadence, now)
        let board = next.boards[cadence]
        if board.period == period { continue }
        next.recent[cadence] = board.quests.map { $0.defId }
        next.boards[cadence] = dealBoard(cadence, period: period, dealContext(next, cadence))
    }

    // A streak survives if the last active day was today or yesterday.
    let today = clock.dayKey(now)
    let last = next.streak.lastDay
    if next.streak.count > 0 && last != today && last != clock.shiftDay(today, -1) {
        next.streak.count = 0
    }
    // A child's quests from their parent go on top of the fresh boards.
    return placeFamilyQuests(next)
}

// MARK: - Rewards

private func addXp(_ save: Save, _ amount: Int, _ reason: XpReason, _ events: inout [GameEvent]) -> Save {
    if amount <= 0 { return save }
    let before = levelInfo(save.xp).level
    var next = save
    next.xp += amount
    events.append(.xp(amount: amount, reason: reason))
    let after = levelInfo(next.xp).level
    if after > before {
        for level in (before + 1)...after {
            events.append(.level(level: level, rank: rankUnlockedAt(level)))
            if let gift = milestones[level] {
                next = giveItem(next, gift, .level, &events)
            }
        }
    }
    return next
}

private func giveItem(_ save: Save, _ itemId: String, _ from: ItemOrigin, _ events: inout [GameEvent]) -> Save {
    guard let item = Catalog.itemById[itemId] else { return save }
    if save.inventory.contains(itemId) {
        // Already owned: it "echoes" into bonus XP instead.
        let bonus = echoXp(item.rarity)
        events.append(.item(itemId: itemId, fresh: false, echoXp: bonus, from: from))
        return addXp(save, bonus, .echo, &events)
    }
    events.append(.item(itemId: itemId, fresh: true, echoXp: 0, from: from))
    var next = save
    next.inventory.append(itemId)
    return next
}

/// Awards any feats that have been earned. Loops, because a feat's XP can trigger another feat.
private func settleFeats(_ save: Save, now: Date, _ events: inout [GameEvent]) -> Save {
    var next = save
    for _ in 0..<20 {
        let earned = pendingFeats(next)
        if earned.isEmpty { break }
        for feat in earned {
            next.feats[feat.id] = millis(now)
            events.append(.feat(id: feat.id))
            next = addXp(next, feat.xp, .feat, &events)
            if let item = feat.item {
                next = giveItem(next, item, .feat, &events)
            }
        }
    }
    return next
}

// MARK: - Actions

/// Marks a quest. A counted quest ("on 4 days") moves one step closer; any
/// other quest, or the final step of a counted one, completes it and pays out.
func markQuest(_ save: Save, _ cadence: Cadence, key: String, now: Date, clock: GameClock = .device) -> Outcome {
    var events: [GameEvent] = []
    guard let at = save.boards[cadence].quests.firstIndex(where: { $0.key == key }) else {
        return Outcome(save: save)
    }
    let quest = save.boards[cadence].quests[at]
    if quest.done { return Outcome(save: save) }

    let progress = quest.progress + 1
    let done = progress >= quest.target
    var next = save
    var board = next.boards[cadence]
    board.quests[at].progress = progress
    board.quests[at].done = done
    next.boards[cadence] = board
    if !done { return Outcome(save: next) }

    if quest.family != nil {
        next = recordFamilyQuestDone(next, quest, now: now, &events)
        return Outcome(save: next, events: events)
    }
    next.counts.quests += 1
    next.counts[cadence] += 1
    if quest.custom { next.counts.customDone += 1 }
    next = addXp(next, quest.xp, .quest, &events)

    if cadence == .daily {
        // Keep the streak alive.
        let today = clock.dayKey(now)
        if next.streak.lastDay != today {
            let count = next.streak.lastDay == clock.shiftDay(today, -1) ? next.streak.count + 1 : 1
            next.streak = Streak(count: count, lastDay: today)
            next.activeDays = Array((next.activeDays.filter { $0 != today } + [today]).suffix(60))
            next.counts.bestStreak = max(next.counts.bestStreak, count)
        }
        // All of today's dailies done: pay the clear bonus once.
        if !next.boards.daily.cleared && next.boards.daily.quests.filter({ $0.family == nil }).allSatisfy({ $0.done }) {
            next.boards.daily.cleared = true
            next.counts.dailyClears += 1
            events.append(.clear)
            next = addXp(next, dailyClearXp, .clear, &events)
        }
    }

    // Loot. The roll is tied to this exact quest, so it can't be re-rolled by retrying.
    var rng = rngFor(next.seed, "loot", quest.key)
    if let loot = rollLoot(cadence, &rng, owned: next.inventory) {
        next = giveItem(next, loot.item.id, .quest, &events)
    }

    next = settleFeats(next, now: now, &events)
    return Outcome(save: next, events: events)
}

/// How many swaps are left on the daily board today.
func rerollsLeft(_ save: Save) -> Int {
    max(0, dailyRerolls - save.boards.daily.rerolls)
}

/// Swaps an unfinished daily quest for another one.
func rerollDaily(_ save: Save, key: String) -> Save {
    if rerollsLeft(save) <= 0 { return save }
    guard let swapped = swapQuest(save.boards.daily, key: key, dealContext(save, .daily)) else { return save }
    var next = save
    next.boards.daily = swapped
    return next
}

struct CustomQuestInput {
    var title: String
    var cadence: Cadence
    var category: QuestKind
    var difficulty: Int
    var pinned: Bool
}

/// Adds a quest the player wrote, and puts it on the current board straight away.
func addCustomQuest(_ save: Save, _ input: CustomQuestInput, now: Date) -> Outcome {
    var events: [GameEvent] = []
    let title = String(input.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    if title.isEmpty { return Outcome(save: save) }
    let stamp = String(Int64(millis(now)), radix: 36)
    let quest = CustomQuest(
        id: "c_\(stamp)_\(save.custom.count)",
        cadence: input.cadence,
        category: input.category,
        difficulty: input.difficulty,
        title: title,
        target: nil,
        pinned: input.pinned
    )
    var next = save
    next.custom.append(quest)
    next.counts.customMade += 1
    // Every new quest goes on the board straight away, so it can be done this period.
    // After that, pinned ones are dealt every time and the rest are mixed in with the deck.
    var board = next.boards[quest.cadence]
    board.quests.insert(activateCustom(quest, period: board.period), at: 0)
    next.boards[quest.cadence] = board
    next = settleFeats(next, now: now, &events)
    return Outcome(save: next, events: events)
}

/// Deletes a custom quest. If it is on a board and unfinished, it leaves the board too.
func removeCustomQuest(_ save: Save, id: String) -> Save {
    var next = save
    for cadence in Cadence.allCases {
        next.boards[cadence].quests.removeAll { $0.defId == id && !$0.done }
    }
    next.custom.removeAll { $0.id == id }
    return next
}

/// Puts an owned item on, or takes off whatever is in that slot when `itemId` is nil.
func equip(_ save: Save, _ slot: Slot, _ itemId: String?, now: Date) -> Outcome {
    var events: [GameEvent] = []
    var next = save
    if let itemId {
        guard let item = Catalog.itemById[itemId], item.slot == slot, save.inventory.contains(itemId) else {
            return Outcome(save: save)
        }
        next.equipped[slot.rawValue] = itemId
    } else {
        next.equipped[slot.rawValue] = nil
    }
    next = settleFeats(next, now: now, &events)
    return Outcome(save: next, events: events)
}

/// First launch: names the hero and buries the starter spade for them to dig up.
/// It isn't put in their hand automatically: choosing "Wear it" is the first thing the game teaches.
func beginJourney(_ save: Save, name: String, now: Date, clock: GameClock = .device) -> Outcome {
    var events: [GameEvent] = []
    var next = save
    next.onboarded = true
    let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    next.hero.name = trimmed.isEmpty ? "Digger" : trimmed
    next = giveItem(next, "rusty_spade", .start, &events)
    next = syncPeriods(next, now: now, clock: clock)
    return Outcome(save: next, events: events)
}

// MARK: - Loading

/// Reads a save from storage or an import, and tidies anything out of range,
/// so an old or slightly broken save can never crash the app.
/// Returns nil if the data isn't a Spade save at all.
func repairSave(_ data: Data, now: Date) -> Save? {
    guard var save = try? JSONDecoder().decode(Save.self, from: data) else { return nil }
    save.version = 1
    if save.createdAt <= 0 { save.createdAt = millis(now) }

    // Keep only real items, once each.
    var seen = Set<String>()
    save.inventory = save.inventory.filter { Catalog.itemById[$0] != nil && seen.insert($0).inserted }
    // Only owned items of the right kind may be worn.
    save.equipped = save.equipped.filter { slot, id in
        save.inventory.contains(id) && Catalog.itemById[id]?.slot.rawValue == slot
    }

    func clamp(_ value: Int, _ count: Int, _ fallback: Int) -> Int {
        value >= 0 && value < count ? value : fallback
    }
    let base = HeroSave()
    save.hero.name = String(save.hero.name.prefix(16))
    save.hero.skin = clamp(save.hero.skin, Catalog.looks.skin.count, base.skin)
    save.hero.hair = clamp(save.hero.hair, Catalog.looks.hair.count, base.hair)
    save.hero.hairStyle = clamp(save.hero.hairStyle, Catalog.looks.hairStyles.count, base.hairStyle)
    save.hero.scarf = clamp(save.hero.scarf, Catalog.looks.scarf.count, base.scarf)

    save.activeDays = Array(save.activeDays.suffix(60))
    return repairFamily(save)
}

/// Packs a save as JSON text, in the same shape the web version uses.
func exportSave(_ save: Save) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(save)) ?? Data()
}

/// Only a confirmed guardian decision can pay a new family completion.
func rewardApprovedFamilyQuest(_ save: Save, claim: Claim, xp: Int, now: Date) -> Save {
    var events: [GameEvent] = []
    var next = save
    next.counts.quests += 1
    next.counts[claim.cadence ?? .daily] += 1
    if (claim.cadence ?? .daily) == .daily {
        let clock = GameClock.device
        let finishedDay = clock.dayKey(Date(timeIntervalSince1970: claim.doneAt / 1000))
        next.activeDays = Array(Set(next.activeDays + [finishedDay])).sorted().suffix(60).map { $0 }
        if let last = next.activeDays.last, last <= clock.dayKey(now) {
            let days = Set(next.activeDays)
            var count = 1
            while days.contains(clock.shiftDay(last, -count)) { count += 1 }
            next.counts.bestStreak = max(next.counts.bestStreak, count)
            if last >= clock.shiftDay(clock.dayKey(now), -1) { next.streak = Streak(count: count, lastDay: last) }
        }
    }
    next = addXp(next, min(1000, max(5, xp)), .quest, &events)
    var rng = rngFor(next.seed, "loot", claim.key)
    if let loot = rollLoot(claim.cadence ?? .daily, &rng, owned: next.inventory) {
        next = giveItem(next, loot.item.id, .quest, &events)
    }
    return settleFeats(next, now: now, &events)
}

struct ChamberQuest: Identifiable {
    let id: String
    let title: String
    let xp: Int
    let item: String?
}
let chamberQuests = [
    ChamberQuest(id: "dogger", title: "A friend beyond the finish", xp: 500_000, item: "dogger"),
    ChamberQuest(id: "icon_spade", title: "Back to the beginning", xp: 1_000_000, item: "icon_spade"),
    ChamberQuest(id: "spade_green", title: "The colour of completion", xp: 2_500_000, item: nil)
]
func claimChamber(_ save: Save, id: String) -> Outcome {
    guard let index = chamberQuests.firstIndex(where: { $0.id == id }), save.xp >= chamberQuests[index].xp,
          !(save.chamber ?? []).contains(id), chamberQuests.prefix(index).allSatisfy({ (save.chamber ?? []).contains($0.id) }) else { return Outcome(save: save) }
    var next = save
    next.chamber = (save.chamber ?? []) + [id]
    var events: [GameEvent] = []
    if let item = chamberQuests[index].item { next = giveItem(next, item, .feat, &events) }
    return Outcome(save: next, events: events)
}
