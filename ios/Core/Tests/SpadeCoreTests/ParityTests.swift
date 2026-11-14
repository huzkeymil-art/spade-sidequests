import XCTest
@testable import SpadeCore

// These tests hold the Swift rules to the web version's answers.
//
// `npm run ios:data` runs the real web rules and writes what they produce to
// Fixtures/parity.json: hashes, random numbers, calendar keys, dealt boards,
// loot rolls, and the end state of a 45-day playthrough. Each test below feeds
// the same inputs to the Swift port and expects exactly the same outputs.

private struct Fixture: Decodable {
    struct Hash: Decodable { let text: String; let hash: UInt32 }
    struct Rng: Decodable { let seed: UInt32; let values: [Double] }
    struct Labelled: Decodable { let seed: Int; let labels: [String]; let values: [Double] }
    struct Shuffle: Decodable { let seed: UInt32; let result: [Int] }
    struct Period: Decodable {
        let y: Int, m: Int, d: Int
        let day: String, week: String, month: String
        let weekday: Int
        let monthProgress: Double
        let weekDays: [String]
        let nextDaily: String, nextWeekly: String, nextMonthly: String
    }
    struct DealQuest: Decodable, Equatable {
        let key: String, defId: String
        let xp: Int, target: Int
        let custom: Bool, pinned: Bool
    }
    struct Deal: Decodable {
        let seed: Int
        let cadence: Cadence
        let period: String
        let recent: [String]
        let off: [QuestKind]
        let custom: [CustomQuest]
        let quests: [DealQuest]
    }
    struct Swap: Decodable { let seed: Int; let before: [String]; let after: [String] }
    struct Loot: Decodable {
        let seed: Int
        let key: String
        let cadence: Cadence
        let owned: [String]
        let item: String?
        let fresh: Bool
    }
    struct Level: Decodable { let xp: Int, level: Int, into: Int, need: Int }
    struct Scenario: Decodable {
        let seed: Int, xp: Int, level: Int
        let inventory: [String]
        let equipped: [String: String]
        let counts: Counts
        let streak: Streak
        let feats: [String]
        let activeDays: [String]
        let customIds: [String]
        let daily: [String], weekly: [String], monthly: [String]
        let levelsSeen: [Int]
        let itemsSeen: [String]
        let totalEvents: Int
        let saveJson: String
    }

    let hashes: [Hash]
    let rng: [Rng]
    let labelled: [Labelled]
    let shuffles: [Shuffle]
    let periods: [Period]
    let deals: [Deal]
    let swaps: [Swap]
    let loot: [Loot]
    let levels: [Level]
    let scenario: Scenario
}

final class ParityTests: XCTestCase {
    private static let fixture: Fixture = {
        guard let url = Bundle.module.url(forResource: "parity", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { fatalError("parity.json is missing. Run `npm run ios:data`.") }
        do {
            return try JSONDecoder().decode(Fixture.self, from: data)
        } catch {
            fatalError("parity.json could not be read: \(error)")
        }
    }()

    private var fixture: Fixture { Self.fixture }

    // The web fixtures were made on a machine set to UTC, so the tests use UTC too.
    private let utc = TimeZone(identifier: "UTC")!
    private var clock: GameClock { GameClock(timeZone: utc) }

    /// Noon on the given day.
    private func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func addDays(_ date: Date, _ days: Int) -> Date {
        date.addingTimeInterval(Double(days) * 86400)
    }

    private let allOn: [String: Bool] = Dictionary(uniqueKeysWithValues: QuestKind.allCases.map { ($0.rawValue, true) })

    func testHashesMatch() {
        for entry in fixture.hashes {
            XCTAssertEqual(hashString(entry.text), entry.hash, "hash of \"\(entry.text)\"")
        }
    }

    func testRandomNumbersMatch() {
        for entry in fixture.rng {
            var rng = SeededRng(seed: entry.seed)
            for (i, expected) in entry.values.enumerated() {
                XCTAssertEqual(rng.next(), expected, accuracy: 1e-15, "seed \(entry.seed), draw \(i)")
            }
        }
        for entry in fixture.labelled {
            var rng: SeededRng
            switch entry.labels.count {
            case 2: rng = rngFor(entry.seed, entry.labels[0], entry.labels[1])
            default: XCTFail("unexpected label count"); return
            }
            for (i, expected) in entry.values.enumerated() {
                XCTAssertEqual(rng.next(), expected, accuracy: 1e-15, "labels \(entry.labels), draw \(i)")
            }
        }
    }

    func testShufflesMatch() {
        for entry in fixture.shuffles {
            var rng = SeededRng(seed: entry.seed)
            XCTAssertEqual(shuffled(Array(0..<10), &rng), entry.result, "seed \(entry.seed)")
        }
    }

    func testCalendarKeysMatch() {
        for p in fixture.periods {
            let date = at(p.y, p.m, p.d)
            let label = "\(p.y)-\(p.m)-\(p.d)"
            XCTAssertEqual(clock.dayKey(date), p.day, label)
            XCTAssertEqual(clock.weekKey(date), p.week, label)
            XCTAssertEqual(clock.monthKey(date), p.month, label)
            XCTAssertEqual(clock.weekdayIndex(date), p.weekday, label)
            XCTAssertEqual(clock.monthProgress(date), p.monthProgress, accuracy: 1e-12, label)
            XCTAssertEqual(clock.weekDays(date), p.weekDays, label)
            XCTAssertEqual(clock.dayKey(clock.nextReset(.daily, date)), p.nextDaily, label)
            XCTAssertEqual(clock.dayKey(clock.nextReset(.weekly, date)), p.nextWeekly, label)
            XCTAssertEqual(clock.dayKey(clock.nextReset(.monthly, date)), p.nextMonthly, label)
        }
    }

    func testDealsMatch() {
        for deal in fixture.deals {
            var categories = allOn
            for kind in deal.off { categories[kind.rawValue] = false }
            let ctx = DealContext(seed: deal.seed, custom: deal.custom, categories: categories, recent: deal.recent)
            let board = dealBoard(deal.cadence, period: deal.period, ctx)
            let got = board.quests.map {
                Fixture.DealQuest(key: $0.key, defId: $0.defId, xp: $0.xp, target: $0.target, custom: $0.custom, pinned: $0.pinned)
            }
            XCTAssertEqual(got, deal.quests, "seed \(deal.seed) \(deal.cadence.rawValue) \(deal.period)")
        }
    }

    func testSwapsMatch() {
        for swap in fixture.swaps {
            let ctx = DealContext(seed: swap.seed, custom: [], categories: allOn, recent: ["d_walk"])
            let board = dealBoard(.daily, period: "2026-11-14", ctx)
            XCTAssertEqual(board.quests.map { $0.defId }, swap.before, "seed \(swap.seed) before")
            let swapped = swapQuest(board, key: board.quests[1].key, ctx)
            XCTAssertEqual(swapped?.quests.map { $0.defId }, swap.after, "seed \(swap.seed) after")
        }
    }

    func testLootRollsMatch() {
        for roll in fixture.loot {
            var rng = rngFor(roll.seed, "loot", roll.key)
            let result = rollLoot(roll.cadence, &rng, owned: roll.owned)
            XCTAssertEqual(result?.item.id, roll.item, roll.key)
            XCTAssertEqual(result?.fresh ?? false, roll.fresh, roll.key)
        }
    }

    func testLevelsMatch() {
        for entry in fixture.levels {
            XCTAssertEqual(levelInfo(entry.xp), LevelInfo(level: entry.level, into: entry.into, need: entry.need), "xp \(entry.xp)")
        }
    }

    /// Plays the same 45 days the web fixture played and expects to finish in the same place.
    func testFortyFiveDayPlaythroughMatches() {
        let expected = fixture.scenario
        let start = at(2026, 11, 1)
        var save = beginJourney(newSave(seed: expected.seed, now: start), name: "Tess", now: start, clock: clock).save
        save = equip(save, .hand, "rusty_spade", now: start).save
        var levelsSeen: [Int] = []
        var itemsSeen: [String] = []
        var totalEvents = 0

        func absorb(_ out: Outcome, _ now: Date) {
            save = out.save
            totalEvents += out.events.count
            for event in out.events {
                switch event {
                case .level(let level, _):
                    levelsSeen.append(level)
                case .item(let itemId, let fresh, _, _):
                    itemsSeen.append("\(itemId):\(fresh ? "new" : "again")")
                    // Wear every new find, so the "all five slots" feat can trigger.
                    if fresh, let item = Catalog.itemById[itemId] {
                        absorb(equip(save, item.slot, itemId, now: now), now)
                    }
                default:
                    break
                }
            }
        }

        for day in 0..<45 {
            if day == 19 || day == 20 { continue } // two days off: the streak goes out
            let now = addDays(start, day)
            save = syncPeriods(save, now: now, clock: clock)
            if day == 4 {
                absorb(addCustomQuest(save, CustomQuestInput(title: "Feed the cat", cadence: .daily, category: .home, difficulty: 1, pinned: true), now: now), now)
            }
            if day == 6 {
                absorb(addCustomQuest(save, CustomQuestInput(title: "Juggle three balls", cadence: .daily, category: .craft, difficulty: 3, pinned: false), now: now), now)
            }
            if day == 8, let target = save.boards.daily.quests.first(where: { !$0.pinned }) {
                save = rerollDaily(save, key: target.key)
            }
            for cadence in Cadence.allCases {
                let quests = save.boards[cadence].quests
                for quest in quests where !quest.done {
                    var step = quest.progress
                    while step < quest.target {
                        absorb(markQuest(save, cadence, key: quest.key, now: now, clock: clock), now)
                        step += 1
                    }
                }
            }
        }

        XCTAssertEqual(save.xp, expected.xp, "total XP")
        XCTAssertEqual(levelInfo(save.xp).level, expected.level, "level")
        XCTAssertEqual(save.inventory, expected.inventory, "inventory, in the order found")
        XCTAssertEqual(save.equipped, expected.equipped, "worn items")
        XCTAssertEqual(save.counts, expected.counts, "counts")
        XCTAssertEqual(save.streak, expected.streak, "streak")
        XCTAssertEqual(save.feats.keys.sorted(), expected.feats, "feats earned")
        XCTAssertEqual(save.activeDays, expected.activeDays, "active days")
        XCTAssertEqual(save.custom.map { $0.id }, expected.customIds, "custom quest ids")
        XCTAssertEqual(save.boards.daily.quests.map { $0.defId }, expected.daily, "final daily board")
        XCTAssertEqual(save.boards.weekly.quests.map { $0.defId }, expected.weekly, "final weekly board")
        XCTAssertEqual(save.boards.monthly.quests.map { $0.defId }, expected.monthly, "final monthly board")
        XCTAssertEqual(levelsSeen, expected.levelsSeen, "level-ups, in order")
        XCTAssertEqual(itemsSeen, expected.itemsSeen, "finds, in order")
        XCTAssertEqual(totalEvents, expected.totalEvents, "number of events")
    }

    /// A save written by the web app's "Back up save" must load here with nothing lost.
    func testWebSaveImports() throws {
        let expected = fixture.scenario
        let data = Data(expected.saveJson.utf8)
        let save = try XCTUnwrap(repairSave(data, now: at(2026, 12, 15)), "the web save should be readable")
        XCTAssertEqual(save.seed, expected.seed)
        XCTAssertEqual(save.xp, expected.xp)
        XCTAssertEqual(save.hero.name, "Tess")
        XCTAssertEqual(save.inventory, expected.inventory)
        XCTAssertEqual(save.equipped, expected.equipped)
        XCTAssertEqual(save.counts, expected.counts)
        XCTAssertEqual(save.streak, expected.streak)
        XCTAssertEqual(save.feats.keys.sorted(), expected.feats)
        XCTAssertEqual(save.custom.map { $0.id }, expected.customIds)
        XCTAssertEqual(save.boards.daily.quests.map { $0.defId }, expected.daily)
        XCTAssertTrue(save.onboarded)
        // The web app has no reminders setting; it should simply default to off.
        XCTAssertFalse(save.settings.reminders)

        // And it survives being written out and read back by the Swift app.
        let again = try XCTUnwrap(repairSave(exportSave(save), now: at(2026, 12, 15)))
        XCTAssertEqual(again, save)
    }
}
