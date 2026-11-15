import XCTest
@testable import SpadeCore

// Direct checks of the rules, independent of the web fixtures.

final class RulesTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private var clock: GameClock { GameClock(timeZone: utc) }

    private func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func started(_ now: Date) -> Save {
        beginJourney(newSave(seed: 12345, now: now), name: "Tess", now: now, clock: clock).save
    }

    func testContentIsComplete() {
        XCTAssertEqual(Catalog.items.count, 33)
        XCTAssertEqual(Catalog.feats.count, 25)
        XCTAssertEqual(Set(Catalog.quests.map { $0.id }).count, Catalog.quests.count, "quest ids are unique")
        for cadence in Cadence.allCases {
            for kind in QuestKind.allCases {
                let n = Catalog.quests.filter { $0.cadence == cadence && $0.category == kind }.count
                XCTAssertGreaterThanOrEqual(n, dealCount(cadence), "\(cadence.rawValue)/\(kind.rawValue)")
            }
        }
        for feat in Catalog.feats {
            if let item = feat.item { XCTAssertNotNil(Catalog.itemById[item], feat.id) }
        }
    }

    func testStartsWithTheSpadeToDigUp() {
        let now = at(2026, 11, 14)
        let out = beginJourney(newSave(seed: 1, now: now), name: "   ", now: now, clock: clock)
        XCTAssertEqual(out.events, [.item(itemId: "rusty_spade", fresh: true, echoXp: 0, from: .start)])
        XCTAssertEqual(out.save.hero.name, "Digger")
        XCTAssertEqual(out.save.inventory, ["rusty_spade"])
        XCTAssertNil(out.save.worn(.hand))
        XCTAssertEqual(out.save.boards.daily.quests.count, 3)
        XCTAssertEqual(out.save.boards.weekly.quests.count, 3)
        XCTAssertEqual(out.save.boards.monthly.quests.count, 2)
    }

    func testCompletingAQuestPaysOnce() throws {
        let now = at(2026, 11, 14)
        let save = started(now)
        let quest = try XCTUnwrap(save.boards.daily.quests.first { $0.target == 1 })
        let first = markQuest(save, .daily, key: quest.key, now: now, clock: clock)
        XCTAssertEqual(first.events.first, .xp(amount: quest.xp, reason: .quest))
        XCTAssertTrue(first.events.contains(.feat(id: "broken_ground")))
        XCTAssertEqual(first.save.streak, Streak(count: 1, lastDay: "2026-11-14"))
        let again = markQuest(first.save, .daily, key: quest.key, now: now, clock: clock)
        XCTAssertTrue(again.events.isEmpty)
        XCTAssertEqual(again.save.xp, first.save.xp)
    }

    func testStreakGrowsAndGoesOut() throws {
        var save = started(at(2026, 11, 14))
        for day in 14...16 {
            let now = at(2026, 11, day)
            save = syncPeriods(save, now: now, clock: clock)
            let quest = try XCTUnwrap(save.boards.daily.quests.first { $0.target == 1 })
            save = markQuest(save, .daily, key: quest.key, now: now, clock: clock).save
        }
        XCTAssertEqual(save.streak.count, 3)
        XCTAssertNotNil(save.feats["kindling"])
        XCTAssertEqual(syncPeriods(save, now: at(2026, 11, 17), clock: clock).streak.count, 3, "yesterday still counts")
        save = syncPeriods(save, now: at(2026, 11, 18), clock: clock)
        XCTAssertEqual(save.streak.count, 0)
        XCTAssertEqual(save.counts.bestStreak, 3)
    }

    func testBoardsResetOnTheirOwnSchedule() {
        var save = started(at(2026, 11, 14)) // a Saturday
        let first = save.boards
        save = syncPeriods(save, now: at(2026, 11, 15), clock: clock)
        XCTAssertEqual(save.boards.daily.period, "2026-11-15")
        XCTAssertEqual(save.boards.weekly, first.weekly)
        XCTAssertEqual(save.boards.monthly, first.monthly)
        save = syncPeriods(save, now: at(2026, 11, 16), clock: clock)
        XCTAssertEqual(save.boards.weekly.period, "2026-W47")
        XCTAssertEqual(save.boards.monthly, first.monthly)
        save = syncPeriods(save, now: at(2026, 12, 1), clock: clock)
        XCTAssertEqual(save.boards.monthly.period, "2026-12")
    }

    func testEquipOnlyAllowsOwnedItemsThatFit() {
        let now = at(2026, 11, 14)
        var save = started(now)
        save.inventory = ["rusty_spade", "wool_cap"]
        XCTAssertEqual(equip(save, .head, "straw_hat", now: now).save, save, "not owned")
        XCTAssertEqual(equip(save, .head, "rusty_spade", now: now).save, save, "wrong slot")
        let worn = equip(save, .head, "wool_cap", now: now).save
        XCTAssertEqual(worn.worn(.head), "wool_cap")
        XCTAssertNil(equip(worn, .head, nil, now: now).save.worn(.head))
    }

    func testCustomQuests() {
        let now = at(2026, 11, 14)
        let save = started(now)
        let pinned = addCustomQuest(save, CustomQuestInput(title: "  Feed the cat ", cadence: .daily, category: .home, difficulty: 1, pinned: true), now: now)
        XCTAssertEqual(pinned.save.boards.daily.quests.first?.title, "Feed the cat")
        XCTAssertEqual(pinned.save.boards.daily.quests.first?.pinned, true)
        XCTAssertEqual(pinned.save.boards.daily.quests.first?.xp, 20)
        XCTAssertTrue(pinned.events.contains(.feat(id: "own_path")))
        let removed = removeCustomQuest(pinned.save, id: pinned.save.custom[0].id)
        XCTAssertTrue(removed.custom.isEmpty)
        XCTAssertEqual(removed.boards.daily.quests.count, 3)
        let blank = addCustomQuest(save, CustomQuestInput(title: "   ", cadence: .daily, category: .home, difficulty: 1, pinned: false), now: now)
        XCTAssertEqual(blank.save, save)
    }

    /// A quest you write should show up straight away, even when it isn't pinned,
    /// and keep turning up in later deals rather than getting lost in the deck.
    func testShuffledInQuestsShowUp() {
        var save = started(at(2026, 11, 14))
        let added = addCustomQuest(save, CustomQuestInput(title: "Juggle", cadence: .daily, category: .craft, difficulty: 3, pinned: false), now: at(2026, 11, 14))
        XCTAssertEqual(added.save.boards.daily.quests.count, 4)
        XCTAssertEqual(added.save.boards.daily.quests.first?.title, "Juggle")
        XCTAssertEqual(added.save.boards.daily.quests.first?.pinned, false)
        XCTAssertEqual(added.save.boards.daily.quests.first?.xp, 45)

        save = added.save
        for day in 15...24 {
            save = syncPeriods(save, now: at(2026, 11, day), clock: clock)
            let ids = save.boards.daily.quests.map { $0.defId }
            XCTAssertEqual(ids.count, 3, "day \(day)")
            XCTAssertTrue(ids.contains(save.custom[0].id), "day \(day): the only own quest is dealt every day")
        }
    }

    func testRepairTidiesNonsense() throws {
        let now = at(2026, 11, 14)
        let junk = #"{"seed": 5, "xp": -20, "inventory": ["rusty_spade", "not_real", "rusty_spade"], "equipped": {"head": "rusty_spade"}, "hero": {"name": "A", "skin": 99, "hair": 1, "hairStyle": 1, "scarf": 0}}"#
        let fixed = try XCTUnwrap(repairSave(Data(junk.utf8), now: now))
        XCTAssertEqual(fixed.xp, 0)
        XCTAssertEqual(fixed.inventory, ["rusty_spade"])
        XCTAssertTrue(fixed.equipped.isEmpty)
        XCTAssertEqual(fixed.hero.skin, 1)
        XCTAssertTrue(fixed.settings.allows(.body))
        XCTAssertEqual(syncPeriods(fixed, now: now, clock: clock).boards.daily.quests.count, 3)
    }

    func testRepairRejectsThingsThatAreNotSaves() {
        let now = at(2026, 11, 14)
        XCTAssertNil(repairSave(Data("hello".utf8), now: now))
        XCTAssertNil(repairSave(Data("null".utf8), now: now))
        XCTAssertNil(repairSave(Data(#"{"name": "nope"}"#.utf8), now: now))
    }

    func testCountdownText() {
        XCTAssertEqual(formatCountdown(42 * 60), "42m")
        XCTAssertEqual(formatCountdown(5 * 3600 + 12 * 60), "5h 12m")
        XCTAssertEqual(formatCountdown(3 * 86400 + 4 * 3600), "3d 4h")
    }
}
