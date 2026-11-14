import Foundation
import SwiftUI

// The store: the one place the app's data lives while it is running.
//
// The rules in SpadeCore are pure functions. This class plugs them into the
// app: it holds the current save, runs a rule when the player does something,
// queues up anything worth celebrating, and writes the result to the phone.

/// A reward moment that takes over the screen until the player dismisses it.
enum Moment: Identifiable, Equatable {
    case item(serial: Int, itemId: String, fresh: Bool, echoXp: Int)
    case level(serial: Int, level: Int, rank: String?)

    var id: Int {
        switch self {
        case .item(let serial, _, _, _): return serial
        case .level(let serial, _, _): return serial
        }
    }
}

/// A small notice that appears briefly and goes away on its own.
struct Toast: Identifiable, Equatable {
    enum Kind: Equatable {
        case feat(id: String)
        case clear
    }

    let id: Int
    let kind: Kind
}

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var save: Save
    /// The current time, refreshed regularly so countdowns stay right.
    @Published private(set) var now = Date()
    @Published private(set) var moments: [Moment] = []
    @Published private(set) var toasts: [Toast] = []

    /// When true, nothing is written to the phone (used for screenshots and previews).
    private let ephemeral: Bool
    private var serial = 0

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spade", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("save.json")
    }

    private static func freshSave() -> Save {
        newSave(seed: Int.random(in: 1..<0x7fff_ffff), now: Date())
    }

    init() {
        ephemeral = false
        if let data = try? Data(contentsOf: Self.fileURL), let loaded = repairSave(data, now: Date()) {
            save = loaded
        } else {
            save = Self.freshSave()
        }
        sync()
    }

    /// A store that starts from a given save and never touches the phone's storage.
    init(preview: Save) {
        ephemeral = true
        save = preview
        sync()
    }

    // MARK: - Reading

    var clock: GameClock { .device }
    var level: LevelInfo { levelInfo(save.xp) }
    var moment: Moment? { moments.first }

    func item(_ id: String) -> ItemDef? {
        Catalog.itemById[id]
    }

    // MARK: - Actions

    private func commit(_ next: Save) {
        guard next != save else { return }
        save = next
        guard !ephemeral else { return }
        try? exportSave(next).write(to: Self.fileURL, options: .atomic)
    }

    /// Stores the new save and queues up anything worth celebrating.
    private func apply(_ outcome: Outcome) {
        for event in outcome.events {
            serial += 1
            switch event {
            case .item(let itemId, let fresh, let echoXp, _):
                moments.append(.item(serial: serial, itemId: itemId, fresh: fresh, echoXp: echoXp))
            case .level(let level, let rank):
                moments.append(.level(serial: serial, level: level, rank: rank))
            case .feat(let id):
                toasts.append(Toast(id: serial, kind: .feat(id: id)))
            case .clear:
                toasts.append(Toast(id: serial, kind: .clear))
            case .xp:
                break
            }
        }
        commit(outcome.save)
    }

    /// Brings the boards up to date with the clock.
    func sync() {
        now = Date()
        if save.onboarded { commit(syncPeriods(save, now: now, clock: clock)) }
    }

    func begin(name: String) {
        apply(beginJourney(save, name: name, now: Date(), clock: clock))
    }

    @discardableResult
    func mark(_ cadence: Cadence, key: String) -> [GameEvent] {
        let outcome = markQuest(save, cadence, key: key, now: Date(), clock: clock)
        apply(outcome)
        return outcome.events
    }

    func reroll(key: String) {
        commit(rerollDaily(save, key: key))
    }

    func addCustom(_ input: CustomQuestInput) {
        apply(addCustomQuest(save, input, now: Date()))
    }

    func removeCustom(id: String) {
        commit(removeCustomQuest(save, id: id))
    }

    func wear(_ slot: Slot, _ itemId: String?) {
        apply(equip(save, slot, itemId, now: Date()))
    }

    func setHero(_ change: (inout HeroSave) -> Void) {
        var next = save
        change(&next.hero)
        next.hero.name = String(next.hero.name.prefix(16))
        commit(next)
    }

    func setSettings(_ change: (inout GameSettings) -> Void) {
        var next = save
        change(&next.settings)
        commit(next)
    }

    func toggleKind(_ kind: QuestKind) {
        var next = save
        next.settings.categories[kind.rawValue] = !next.settings.allows(kind)
        // Never allow every kind to be off: there would be nothing to deal.
        guard next.settings.categories.values.contains(true) else { return }
        commit(next)
    }

    func nextMoment() {
        if !moments.isEmpty { moments.removeFirst() }
    }

    /// Puts a reward moment on screen directly. Only the demo screens use this.
    func show(_ moment: Moment) {
        moments.append(moment)
    }

    func dropToast(_ id: Int) {
        toasts.removeAll { $0.id == id }
    }

    // MARK: - Backups

    /// Writes the save to a temporary file, ready to hand to the share sheet.
    func backupFile() -> URL? {
        let stamp = clock.dayKey(Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spade-save-\(stamp).json")
        do {
            try exportSave(save).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Loads a save from a backup (from this app or from the web version). Returns false if it isn't one.
    func restore(from data: Data) -> Bool {
        guard let loaded = repairSave(data, now: Date()) else { return false }
        moments = []
        toasts = []
        commit(loaded.onboarded ? syncPeriods(loaded, now: Date(), clock: clock) : loaded)
        return true
    }

    func reset() {
        moments = []
        toasts = []
        commit(Self.freshSave())
    }
}

// MARK: - Demo saves

/// Ready-made situations, opened with the launch argument `-demo <name>`.
/// They power the automated screenshots, and never touch the real save.
enum DemoMode {
    static var requested: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-demo"), flag + 1 < args.count else { return nil }
        return args[flag + 1]
    }

    /// The store the app should run on: the real one, or a staged one for a demo screen.
    @MainActor
    static func makeStore() -> GameStore {
        guard let name = requested else { return GameStore() }
        switch name {
        case "launch", "title":
            return GameStore(preview: newSave(seed: 7, now: Date()))
        default:
            var save = midGame()
            if name == "smooth" { save.settings.retro = false }
            let store = GameStore(preview: save)
            if name == "dig" { store.show(.item(serial: -1, itemId: "moonsteel_cap", fresh: true, echoXp: 0)) }
            if name == "level" { store.show(.level(serial: -2, level: 8, rank: nil)) }
            return store
        }
    }

    /// A player a few weeks in: level 7, a 9-day streak, some gear.
    static func midGame() -> Save {
        let clock = GameClock.device
        let now = Date()
        var save = newSave(seed: 4242, now: now)
        save.onboarded = true
        save.hero = HeroSave(name: "Tess", skin: 1, hair: 2, hairStyle: 1, scarf: 0)
        save.xp = 1480
        save.inventory = ["rusty_spade", "oak_staff", "wool_cap", "straw_hat", "miners_helm", "patched_tunic", "travel_cloak", "pot_lid", "barrow_shield", "lucky_pebble", "firefly", "ember_wisp", "barrow_blade", "miners_pick"]
        save.equipped = ["hand": "rusty_spade", "head": "straw_hat", "shield": "barrow_shield", "charm": "ember_wisp"]
        let today = clock.dayKey(now)
        let yesterday = clock.shiftDay(today, -1)
        save.streak = Streak(count: 9, lastDay: yesterday)
        save.activeDays = (1...9).reversed().map { clock.shiftDay(today, -$0) }
        save.counts.quests = 61
        save.counts.daily = 52
        save.counts.weekly = 8
        save.counts.monthly = 1
        save.counts.dailyClears = 9
        save.counts.bestStreak = 9
        for id in ["broken_ground", "ten_deep", "well_dug", "full_lantern", "kindling", "steady_flame", "seven_runes", "moonturn", "delver", "full_pockets"] {
            save.feats[id] = millis(now)
        }
        save.settings.guideSeen = true
        save.settings.sound = false
        save = syncPeriods(save, now: now, clock: clock)
        // Two of today's three quests are already sealed, so the lantern is burning well.
        for quest in save.boards.daily.quests.prefix(2) {
            for _ in 0..<max(1, quest.target) {
                save = markQuest(save, .daily, key: quest.key, now: now, clock: clock).save
            }
        }
        return save
    }
}
