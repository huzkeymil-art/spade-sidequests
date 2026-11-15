import XCTest
@testable import SpadeCore

final class ProgressionUpdateTests: XCTestCase {
    private let clock = GameClock(timeZone: TimeZone(secondsFromGMT: 0)!)
    private var monday: Date { clock.parseDay("2026-11-16").addingTimeInterval(43200) }
    private func player(_ seed: Int, _ name: String) -> Save {
        beginJourney(newSave(seed: seed, now: monday), name: name, now: monday, clock: clock).save
    }
    private func pair(weekday: Int? = nil) throws -> (Save, Save, String) {
        var parent = setRole(player(1, "Sam"), .parent, currency: "USD", now: monday)
        let added = addKid(parent, name: "Alex", now: monday)
        let id = try XCTUnwrap(added.kidId)
        parent = saveFamilyQuest(added.save, kidId: id, questId: nil,
            FamilyQuestInput(title: "Read", cadence: .daily, category: .home, xp: 60, allowance: 0, repeats: true, weekday: weekday), now: monday)
        let child = receiveParentNote(player(2, "Alex"), try XCTUnwrap(noteFor(parent, kidId: id)), now: monday).save
        return (parent, child, id)
    }

    func testFinalRankKeepsLevelsOpen() {
        XCTAssertEqual(rankFor(99), "Legend of the Loam")
        XCTAssertEqual(rankUnlockedAt(100), "Mythic Marl")
        XCTAssertEqual(rankFor(101), "Mythic Marl")
        XCTAssertGreaterThan(levelInfo(500_000).level, 100)
    }

    func testEveryFamilyRewardWaitsForApprovalAndPaysOnlyOnce() throws {
        var (parent, child, id) = try pair()
        let entry = try XCTUnwrap(child.boards.daily.quests.first { $0.family != nil })
        let before = child
        child = markQuest(child, .daily, key: entry.key, now: monday, clock: clock).save
        XCTAssertEqual(child.xp, before.xp)
        XCTAssertEqual(child.inventory, before.inventory)
        XCTAssertEqual(child.counts, before.counts)
        XCTAssertEqual(child.family?.claims.first?.status, .waiting)
        parent = receiveChildNote(parent, try XCTUnwrap(childNote(child))).save
        parent = decideClaim(parent, kidId: id, key: entry.key, approve: true)
        child = receiveParentNote(child, try XCTUnwrap(noteFor(parent, kidId: id)), now: monday).save
        XCTAssertGreaterThanOrEqual(child.xp - before.xp, 60)
        XCTAssertEqual(child.counts.quests - before.counts.quests, 1)
        XCTAssertEqual(child.family?.claims.first?.xpGranted, true)
        let paid = child.xp
        parent = markPaid(parent, kidId: id)
        child = receiveParentNote(child, try XCTUnwrap(noteFor(parent, kidId: id)), now: monday).save
        XCTAssertEqual(child.xp, paid)
        XCTAssertEqual(receiveParentNote(child, try XCTUnwrap(noteFor(parent, kidId: id)), now: monday).save.xp, paid)
    }

    func testDeclineNeverAwardsXPAndLegacyApprovalDoesNotPayAgain() throws {
        for legacy in [false, true] {
            var (parent, child, id) = try pair()
            let entry = try XCTUnwrap(child.boards.daily.quests.first { $0.family != nil })
            child = markQuest(child, .daily, key: entry.key, now: monday, clock: clock).save
            if legacy { child.family?.claims[0].xpGranted = nil; child.family?.claims[0].allowance = 100; parent.household?.children[0].quests[0].allowance = 100 }
            let xp = child.xp
            parent = receiveChildNote(parent, try XCTUnwrap(childNote(child))).save
            parent = decideClaim(parent, kidId: id, key: entry.key, approve: legacy)
            child = receiveParentNote(child, try XCTUnwrap(noteFor(parent, kidId: id)), now: monday).save
            XCTAssertEqual(child.xp, xp)
        }
    }

    func testWeeklyDayAndOnceRequestRevertFollowingWeek() throws {
        var (parent, child, id) = try pair(weekday: 0)
        let quest = try XCTUnwrap(child.family?.quests.first)
        XCTAssertEqual(child.boards.weekly.quests.filter { $0.family != nil }.count, 1)
        child = requestFamilyDay(child, questId: quest.id, weekday: 2, permanent: false)
        XCTAssertEqual(requestFamilyDay(child, questId: quest.id, weekday: 3, permanent: true).family?.requests?.count, 1)
        parent = receiveChildNote(parent, try XCTUnwrap(childNote(child))).save
        parent = decideFamilyDay(parent, kidId: id, requestId: try XCTUnwrap(child.family?.requests?.first?.id), approve: true, now: monday)
        child = receiveParentNote(child, try XCTUnwrap(noteFor(parent, kidId: id)), now: monday).save
        XCTAssertFalse(child.boards.weekly.quests.contains { $0.family != nil })
        child = syncPeriods(child, now: monday.addingTimeInterval(2 * 86400), clock: clock)
        XCTAssertTrue(child.boards.weekly.quests.contains { $0.family != nil })
        child = syncPeriods(child, now: monday.addingTimeInterval(7 * 86400), clock: clock)
        XCTAssertTrue(child.boards.weekly.quests.contains { $0.family != nil })
        XCTAssertEqual(child.family?.quests.first?.weekday, 0)
    }

    func testPermanentRequestAndExpiredOnceRequest() throws {
        for permanent in [false, true] {
            var (parent, child, id) = try pair(weekday: 0)
            let quest = try XCTUnwrap(child.family?.quests.first)
            child = requestFamilyDay(child, questId: quest.id, weekday: 4, permanent: permanent)
            parent = receiveChildNote(parent, try XCTUnwrap(childNote(child))).save
            parent = decideFamilyDay(parent, kidId: id, requestId: try XCTUnwrap(child.family?.requests?.first?.id), approve: true, now: monday.addingTimeInterval(7 * 86400))
            XCTAssertEqual(parent.household?.children.first?.quests.first?.weekday, permanent ? 4 : 0)
            XCTAssertEqual(parent.household?.children.first?.requests?.first?.status, permanent ? .approved : .declined)
        }
    }

    func testChamberThresholdsSequenceAndPersistence() throws {
        var save = player(1, "Marl")
        save.xp = 499_999
        XCTAssertEqual(claimChamber(save, id: "dogger").save, save)
        save.xp = 2_500_000
        XCTAssertEqual(claimChamber(save, id: "icon_spade").save, save)
        for quest in chamberQuests {
            save = claimChamber(save, id: quest.id).save
            XCTAssertEqual(claimChamber(save, id: quest.id).save, save)
        }
        XCTAssertEqual(save.chamber, ["dogger", "icon_spade", "spade_green"])
        XCTAssertTrue(save.inventory.contains("dogger"))
        XCTAssertTrue(save.inventory.contains("icon_spade"))
        XCTAssertEqual(try JSONDecoder().decode(Save.self, from: exportSave(save)).chamber, save.chamber)
    }

    func testGuardiansMergeDifferentEditsAndIgnoreReplayedChange() throws {
        let (parent, _, id) = try pair()
        let original = try XCTUnwrap(parent.household)
        let renamed = try XCTUnwrap(renameKid(parent, kidId: id, name: "Tess").household)
        let edited = try XCTUnwrap(saveFamilyQuest(parent, kidId: id, questId: original.children[0].quests[0].id,
            FamilyQuestInput(title: "Read a chapter", cadence: .weekly, category: .home, xp: 70, allowance: 0, repeats: true), now: monday).household)
        let a = GuardianChange(before: original, after: renamed), b = GuardianChange(before: original, after: edited)
        for changes in [[a, b], [b, a]] {
            var doc = GuardianDocument(household: original)
            for change in changes { doc = mergeGuardianChange(change, into: doc) }
            XCTAssertEqual(doc.household.children[0].name, "Tess")
            XCTAssertEqual(doc.household.children[0].quests[0].title, "Read a chapter")
            XCTAssertEqual(mergeGuardianChange(a, into: doc), doc)
        }
        let removed = GuardianChange(before: original, after: Household(familyId: original.familyId, currency: original.currency))
        let doc = mergeGuardianChange(removed, into: GuardianDocument(household: original))
        XCTAssertTrue(mergeGuardianChange(a, into: doc).household.children.isEmpty)
    }

    func testTwoGuardiansCannotReverseACompletionDecision() throws {
        var (parent, child, id) = try pair()
        let entry = try XCTUnwrap(child.boards.daily.quests.first { $0.family != nil })
        child = markQuest(child, .daily, key: entry.key, now: monday, clock: clock).save
        parent = receiveChildNote(parent, try XCTUnwrap(childNote(child))).save
        let original = try XCTUnwrap(parent.household)
        let yes = GuardianChange(before: original, after: try XCTUnwrap(decideClaim(parent, kidId: id, key: entry.key, approve: true).household))
        let no = GuardianChange(before: original, after: try XCTUnwrap(decideClaim(parent, kidId: id, key: entry.key, approve: false).household))
        let doc = mergeGuardianChange(no, into: mergeGuardianChange(yes, into: GuardianDocument(household: original)))
        XCTAssertEqual(doc.household.children[0].claims[0].status, .approved)
    }
}
