import Foundation

// Dealing quests onto the board.

/// How many quests each board holds.
func dealCount(_ cadence: Cadence) -> Int {
    cadence == .monthly ? 2 : 3
}

/// Free swaps allowed on the daily board each day.
let dailyRerolls = 1

struct DealContext {
    var seed: Int
    var custom: [CustomQuest]
    var categories: [String: Bool]
    /// Quest ids dealt last period: skipped if there is enough else to choose from.
    var recent: [String]
}

private struct DeckEntry {
    var def: QuestDef
    var custom: Bool
}

private func activate(_ def: QuestDef, period: String, custom: Bool, pinned: Bool) -> ActiveQuest {
    ActiveQuest(
        key: "\(period):\(def.id)",
        defId: def.id,
        cadence: def.cadence,
        category: def.category,
        title: def.title,
        xp: questXp(def.cadence, def.difficulty),
        target: max(1, def.target ?? 1),
        progress: 0,
        done: false,
        custom: custom,
        pinned: pinned
    )
}

/// Makes the board entry for a pinned custom quest.
func activatePinned(_ quest: CustomQuest, period: String) -> ActiveQuest {
    activate(quest.asDef, period: period, custom: true, pinned: true)
}

/// Every quest that could be dealt for this cadence: built-in ones in enabled kinds, plus unpinned custom ones.
private func deck(_ cadence: Cadence, _ ctx: DealContext) -> [DeckEntry] {
    let anyEnabled = ctx.categories.values.contains(true)
    let builtIn = Catalog.quests.filter { quest in
        quest.cadence == cadence && (!anyEnabled || ctx.categories[quest.category.rawValue] == true)
    }
    let own = ctx.custom.filter { $0.cadence == cadence && !$0.pinned }
    return builtIn.map { DeckEntry(def: $0, custom: false) } + own.map { DeckEntry(def: $0.asDef, custom: true) }
}

/// Draws `count` quests from the deck, avoiding `exclude` and spreading across
/// kinds where it can. The same seed and label always give the same draw.
private func draw(_ cadence: Cadence, _ ctx: DealContext, count: Int, exclude: [String], label: String) -> [DeckEntry] {
    let full = deck(cadence, ctx)
    var pool = full.filter { !exclude.contains($0.def.id) }
    if pool.count < count { pool = full } // not enough variety left: allow repeats rather than deal short
    var rng = rngFor(ctx.seed, cadence.rawValue, label)
    var order = shuffled(pool, &rng)

    var picked: [DeckEntry] = []
    var used = Set<QuestKind>()
    while picked.count < count && !order.isEmpty {
        let at = order.firstIndex { !used.contains($0.def.category) } ?? 0
        let next = order.remove(at: at)
        picked.append(next)
        used.insert(next.def.category)
    }
    return picked
}

/// Deals a fresh board for the given day, week or month.
func dealBoard(_ cadence: Cadence, period: String, _ ctx: DealContext) -> Board {
    let pinned = ctx.custom.filter { $0.cadence == cadence && $0.pinned }
    // Pinned quests take up places, but at least one place is always left for a surprise.
    let fromDeck = max(1, dealCount(cadence) - pinned.count)
    let drawn = draw(cadence, ctx, count: fromDeck, exclude: ctx.recent, label: period)
    var board = Board()
    board.period = period
    board.quests = pinned.map { activatePinned($0, period: period) }
        + drawn.map { activate($0.def, period: period, custom: $0.custom, pinned: false) }
    return board
}

/// Swaps one unfinished quest for a different one. Returns nil if there is nothing to swap in.
func swapQuest(_ board: Board, key: String, _ ctx: DealContext) -> Board? {
    guard let at = board.quests.firstIndex(where: { $0.key == key }) else { return nil }
    let old = board.quests[at]
    if old.done || old.pinned { return nil }
    let onBoard = board.quests.map { $0.defId }
    let drawn = draw(old.cadence, ctx, count: 1, exclude: onBoard + ctx.recent, label: "\(board.period):swap\(board.rerolls)")
    guard let next = drawn.first, !onBoard.contains(next.def.id) else { return nil }
    var out = board
    out.quests[at] = activate(next.def, period: board.period, custom: next.custom, pinned: false)
    out.rerolls += 1
    return out
}
