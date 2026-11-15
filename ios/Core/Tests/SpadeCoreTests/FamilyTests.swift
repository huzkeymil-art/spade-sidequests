import XCTest
@testable import SpadeCore

// Families: a parent's Spade and a child's Spade passing notes back and forth.

final class FamilyTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private var clock: GameClock { GameClock(timeZone: utc) }

    private func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func player(_ seed: Int, _ name: String, _ now: Date) -> Save {
        beginJourney(newSave(seed: seed, now: now), name: name, now: now, clock: clock).save
    }

    /// A parent with one child called Tess, and the child's id.
    private func parentWithKid(_ now: Date) throws -> (Save, String) {
        let parent = setRole(player(1, "Mum", now), .parent, currency: "USD", now: now)
        let out = addKid(parent, name: " Tess ", now: now)
        return (out.save, try XCTUnwrap(out.kidId))
    }

    private func chores() -> FamilyQuestInput {
        FamilyQuestInput(title: "Take out the bins", cadence: .daily, category: .home, xp: 60, allowance: 150, repeats: true)
    }

    /// Passes a note through a real link, the way it travels between phones.
    private func send(_ link: FamilyLink) throws -> FamilyLink {
        let text = FamilyLinks.webLink(link)
        XCTAssertTrue(text.hasPrefix(FamilyLinks.webPage + "#"))
        return try XCTUnwrap(FamilyLinks.read(text), "the link should read back")
    }

    func testLinksSurviveTheTrip() throws {
        let note = ChildNote(familyId: "fam_1", childId: "kid_1", childName: "Tess", done: [])
        let payload = FamilyLinks.payload(.fromChild(note))
        XCTAssertFalse(payload.contains("+") || payload.contains("/") || payload.contains("="), "URL-safe")
        XCTAssertEqual(FamilyLinks.read(payload), .fromChild(note), "bare text")
        XCTAssertEqual(FamilyLinks.read("  \(FamilyLinks.webPage)#\(payload)\n"), .fromChild(note), "pasted link")
        XCTAssertEqual(FamilyLinks.read("spade://family#\(payload)"), .fromChild(note), "the app's own link")
        XCTAssertNil(FamilyLinks.read("hello"))
        XCTAssertNil(FamilyLinks.read("https://example.com/#e30"), "valid base64 JSON that isn't a note")
        XCTAssertNil(FamilyLinks.read(""))
    }

    func testRolesStartPlainAndClearWhatTheyLeave() throws {
        let now = at(2026, 11, 14)
        let solo = player(2, "Sam", now)
        XCTAssertEqual(solo.role, .solo)
        XCTAssertNil(solo.household)
        let (parent, _) = try parentWithKid(now)
        XCTAssertEqual(parent.role, .parent)
        XCTAssertEqual(parent.household?.children.map { $0.name }, ["Tess"])
        XCTAssertEqual(parent.household?.currency, "USD")
        let back = setRole(parent, .solo, currency: "USD", now: now)
        XCTAssertNil(back.household)
        XCTAssertEqual(back.role, .solo)
        XCTAssertEqual(addKid(solo, name: "Tess", now: now).kidId, nil, "only parents have children")
    }

    /// The whole round trip: set a quest, child does it, parent checks it, parent pays.
    func testAllowanceRoundTrip() throws {
        let now = at(2026, 11, 14)
        var (parent, kidId) = try parentWithKid(now)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)
        let kid = try XCTUnwrap(parent.household?.children.first)
        XCTAssertTrue(kid.needsUpdate)

        // Parent sends a note; the child's Spade joins the family.
        guard case .fromParent(let note) = try send(.fromParent(try XCTUnwrap(noteFor(parent, kidId: kidId)))) else {
            return XCTFail("expected a parent's note")
        }
        parent = markSent(parent, kidId: kidId)
        XCTAssertFalse(try XCTUnwrap(parent.household?.children.first).needsUpdate)

        var child = player(3, "Tessie", now)
        let joined = receiveParentNote(child, note, now: now)
        child = joined.save
        XCTAssertEqual(joined.result, .applied(ParentNoteSummary(joined: true, newQuests: 1)))
        XCTAssertEqual(child.role, .child)
        XCTAssertEqual(child.family?.parentName, "Mum")

        // The quest is on today's board straight away, at the parent's XP, and can't be swapped.
        let entry = try XCTUnwrap(child.boards.daily.quests.first)
        XCTAssertEqual(entry.title, "Take out the bins")
        XCTAssertEqual(entry.xp, 60)
        XCTAssertEqual(entry.family?.allowance, 150)
        XCTAssertTrue(entry.pinned)
        XCTAssertEqual(child.boards.daily.quests.count, 4)

        // Reading the same note again changes nothing.
        XCTAssertEqual(receiveParentNote(child, note, now: now).result, .stale)

        // The child does it: XP now, allowance waits for the parent.
        let done = markQuest(child, .daily, key: entry.key, now: now, clock: clock)
        child = done.save
        XCTAssertEqual(done.events.first, .xp(amount: 60, reason: .quest))
        XCTAssertTrue(done.events.contains(.allowance(amount: 150)))
        XCTAssertEqual(child.family?.claims.map { $0.status }, [.waiting])
        XCTAssertEqual(unsentClaims(child).count, 1)

        // The child sends a note back. Even if the amount in it were changed, the parent's own amount counts.
        var report = try XCTUnwrap(childNote(child))
        report.done[0].allowance = 99_999
        child = markReported(child)
        XCTAssertTrue(unsentClaims(child).isEmpty)
        guard case .fromChild(let travelled) = try send(.fromChild(report)) else { return XCTFail("expected a child's note") }
        let heard = receiveChildNote(parent, travelled)
        parent = heard.save
        XCTAssertEqual(heard.result, .added(kidId: kidId, count: 1))
        XCTAssertEqual(receiveChildNote(parent, travelled).result, .nothingNew(kidId: kidId), "a repeat is ignored")
        var claims = try XCTUnwrap(parent.household?.children.first?.claims)
        XCTAssertEqual(claims.map { $0.allowance }, [150])
        XCTAssertEqual(claims.total(.waiting), 150)

        // The parent approves, then pays.
        parent = decideClaim(parent, kidId: kidId, key: entry.key, approve: true)
        claims = try XCTUnwrap(parent.household?.children.first?.claims)
        XCTAssertEqual(claims.total(.approved), 150)
        XCTAssertTrue(try XCTUnwrap(parent.household?.children.first).needsUpdate, "the child should hear about it")
        parent = markPaid(parent, kidId: kidId)
        claims = try XCTUnwrap(parent.household?.children.first?.claims)
        XCTAssertEqual(claims.total(.approved), 0)
        XCTAssertEqual(claims.total(.paid), 150)

        // The next note tells the child.
        let update = try XCTUnwrap(noteFor(parent, kidId: kidId))
        let told = receiveParentNote(child, update, now: now)
        XCTAssertEqual(told.result, .applied(ParentNoteSummary(paid: 1)))
        XCTAssertEqual(told.save.family?.claims.map { $0.status }, [.paid])
    }

    func testDeclinedQuestsPayNothing() throws {
        let now = at(2026, 11, 14)
        var (parent, kidId) = try parentWithKid(now)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)
        var child = receiveParentNote(player(3, "Tess", now), try XCTUnwrap(noteFor(parent, kidId: kidId)), now: now).save
        let key = try XCTUnwrap(child.boards.daily.quests.first?.key)
        child = markQuest(child, .daily, key: key, now: now, clock: clock).save
        parent = receiveChildNote(parent, try XCTUnwrap(childNote(child))).save
        parent = decideClaim(parent, kidId: kidId, key: key, approve: false)
        parent = markPaid(parent, kidId: kidId)
        let claims = try XCTUnwrap(parent.household?.children.first?.claims)
        XCTAssertEqual(claims.map { $0.status }, [.declined])
        let told = receiveParentNote(child, try XCTUnwrap(noteFor(parent, kidId: kidId)), now: now)
        XCTAssertEqual(told.result, .applied(ParentNoteSummary(declined: 1)))
    }

    func testRepeatingAndOneOffQuests() throws {
        let start = at(2026, 11, 14)
        var (parent, kidId) = try parentWithKid(start)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: start)
        var once = chores()
        once.title = "Tidy the shed"
        once.repeats = false
        once.cadence = .weekly
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, once, now: start)
        var child = receiveParentNote(player(3, "Tess", start), try XCTUnwrap(noteFor(parent, kidId: kidId)), now: start).save

        let shed = try XCTUnwrap(child.boards.weekly.quests.first { $0.title == "Tidy the shed" })
        child = markQuest(child, .weekly, key: shed.key, now: start, clock: clock).save

        // A week later the bins are back (they repeat), the shed is not (it was a one-off).
        child = syncPeriods(child, now: at(2026, 11, 21), clock: clock)
        child = syncPeriods(child, now: at(2026, 11, 23), clock: clock)
        XCTAssertTrue(child.boards.daily.quests.contains { $0.title == "Take out the bins" && !$0.done })
        XCTAssertFalse(child.boards.weekly.quests.contains { $0.title == "Tidy the shed" })
        XCTAssertEqual(child.boards.daily.quests.count, 4, "three dealt, plus the parent's")
    }

    func testParentChangesReachTheBoard() throws {
        let now = at(2026, 11, 14)
        var (parent, kidId) = try parentWithKid(now)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)
        var child = receiveParentNote(player(3, "Tess", now), try XCTUnwrap(noteFor(parent, kidId: kidId)), now: now).save
        let questId = try XCTUnwrap(parent.household?.children.first?.quests.first?.id)

        var edited = chores()
        edited.xp = 100
        edited.title = "Bins and recycling"
        parent = saveFamilyQuest(parent, kidId: kidId, questId: questId, edited, now: now)
        child = receiveParentNote(child, try XCTUnwrap(noteFor(parent, kidId: kidId)), now: now).save
        XCTAssertEqual(child.boards.daily.quests.first?.title, "Bins and recycling")
        XCTAssertEqual(child.boards.daily.quests.first?.xp, 100)

        parent = removeFamilyQuest(parent, kidId: kidId, questId: questId)
        let told = receiveParentNote(child, try XCTUnwrap(noteFor(parent, kidId: kidId)), now: now)
        XCTAssertEqual(told.result, .applied(ParentNoteSummary(removedQuests: 1)))
        XCTAssertFalse(told.save.boards.daily.quests.contains { $0.family != nil })
        XCTAssertEqual(told.save.boards.daily.quests.count, 3)
    }

    func testNotesOnlyCountInTheRightPlace() throws {
        let now = at(2026, 11, 14)
        var (parent, kidId) = try parentWithKid(now)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)
        let note = try XCTUnwrap(noteFor(parent, kidId: kidId))
        XCTAssertEqual(receiveParentNote(parent, note, now: now).result, .isParent, "a parent's Spade can't join as a child")

        var child = receiveParentNote(player(3, "Tess", now), note, now: now).save
        let key = try XCTUnwrap(child.boards.daily.quests.first?.key)
        child = markQuest(child, .daily, key: key, now: now, clock: clock).save
        let report = try XCTUnwrap(childNote(child))

        XCTAssertEqual(receiveChildNote(player(4, "Solo", now), report).result, .notParent)
        let (stranger, _) = try parentWithKid(at(2026, 11, 15))
        XCTAssertEqual(receiveChildNote(stranger, report).result, .wrongFamily)
        XCTAssertEqual(receiveChildNote(removeKid(parent, kidId: kidId), report).result, .unknownChild)

        // A made-up quest in a child's note is ignored.
        var forged = report
        forged.done[0].questId = "fq_madeup"
        forged.done[0].key = "2026-11-14:fq_madeup"
        XCTAssertEqual(receiveChildNote(parent, forged).result, .nothingNew(kidId: kidId))
    }

    func testParentsSetTheXpWithinLimits() throws {
        let now = at(2026, 11, 14)
        var (parent, kidId) = try parentWithKid(now)
        var huge = chores()
        huge.xp = 1_000_000
        huge.allowance = -5
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, huge, now: now)
        let quest = try XCTUnwrap(parent.household?.children.first?.quests.first)
        XCTAssertEqual(quest.xp, familyXpRange.upperBound)
        XCTAssertEqual(quest.allowance, 0)
        var blank = chores()
        blank.title = "  "
        XCTAssertEqual(saveFamilyQuest(parent, kidId: kidId, questId: nil, blank, now: now), parent)
    }

    func testFamilySavesSurviveSavingAndLoading() throws {
        let now = at(2026, 11, 14)
        var (parent, kidId) = try parentWithKid(now)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)
        XCTAssertEqual(repairSave(exportSave(parent), now: now), parent)

        var child = receiveParentNote(player(3, "Tess", now), try XCTUnwrap(noteFor(parent, kidId: kidId)), now: now).save
        let key = try XCTUnwrap(child.boards.daily.quests.first?.key)
        child = markQuest(child, .daily, key: key, now: now, clock: clock).save
        XCTAssertEqual(repairSave(exportSave(child), now: now), child)

        // Leaving the family takes the parent's unfinished quests off the board, and nothing else.
        let left = setRole(child, .solo, currency: "USD", now: now)
        XCTAssertNil(left.family)
        XCTAssertEqual(left.xp, child.xp)
    }
}
