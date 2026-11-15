import XCTest
@testable import SpadeCore

// Families: a parent's Spade and a child's Spade keeping each other up to date
// through two pages in iCloud. Here a pretend iCloud stands in for the real one.

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

    /// A pretend iCloud for one child: the two pages, as the text stored on them.
    private struct Pages {
        var parent = ""
        var kid = ""
    }

    /// Where the pretend pages live.
    private let place = CloudLink(zone: "SpadeFamily", owner: "_mum")

    /// What the parent's phone does on a sync, in the same order as the app:
    /// store its own page if iCloud is behind, then read the child's.
    private func syncParent(_ save: Save, _ kidId: String, _ cloud: inout Pages) -> Save {
        var save = save
        if let due = parentPageDue(save, kidId: kidId) {
            cloud.parent = due.body
            save = markSent(save, kidId: kidId, revision: due.revision)
        }
        if let out = readKidPage(save, kidId: kidId, cloud.kid) { save = out.save }
        return save
    }

    /// What the child's phone does on a sync: read the parent's page, then store its own if iCloud is behind.
    private func syncKid(_ save: Save, _ cloud: inout Pages, now: Date) -> Save {
        var save = save
        if let out = readParentPage(save, cloud.parent, cloud: place, now: now) { save = out.save }
        if let due = kidPageDue(save) {
            cloud.kid = due.body
            save = markReported(save, keys: due.keys)
        }
        return save
    }

    /// A parent's note, after a trip through a page.
    private func viaPage(_ note: ParentNote) throws -> ParentNote {
        guard case .fromParent(let read)? = FamilyPages.read(FamilyPages.write(.fromParent(note))) else {
            XCTFail("the page should read back as a parent's note")
            return note
        }
        return read
    }

    func testPagesReadBackWhatWasWritten() throws {
        let note = ChildNote(familyId: "fam_1", childId: "kid_1", childName: "Tess", done: [])
        let text = FamilyPages.write(.fromChild(note))
        XCTAssertTrue(text.hasPrefix("{"), "stored as readable JSON")
        XCTAssertEqual(FamilyPages.read(text), .fromChild(note))
        XCTAssertNil(FamilyPages.read(""), "an empty page, before the child has written on it")
        XCTAssertNil(FamilyPages.read("hello"))
        XCTAssertNil(FamilyPages.read("{}"), "JSON that isn't a note")
        XCTAssertNil(FamilyPages.read(#"{"v":2,"child":{"familyId":"a","childId":"b","childName":"c","done":[]}}"#), "a version this app doesn't know")
    }

    /// The whole thing through the pretend iCloud: invite, join, a finished quest, the parent's answer.
    func testPagesKeepTwoPhonesInStep() throws {
        let now = at(2026, 11, 14)
        var cloud = Pages()
        var (parent, kidId) = try parentWithKid(now)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)

        // Nothing goes to iCloud until the child has been invited.
        XCTAssertNil(parentPageDue(parent, kidId: kidId))
        parent = markShared(parent, kidId: kidId, true)
        parent = syncParent(parent, kidId, &cloud)
        XCTAssertFalse(cloud.parent.isEmpty)
        XCTAssertFalse(try XCTUnwrap(parent.household?.children.first).needsUpdate)
        XCTAssertNil(parent.household?.children.first?.joined, "the child hasn't opened the invite yet")

        // The child opens the invite: the quest is on their board, and their page says hello.
        var child = player(3, "Tessie", now)
        XCTAssertNil(kidPageDue(child), "not in a family yet")
        child = syncKid(child, &cloud, now: now)
        XCTAssertEqual(child.role, .child)
        XCTAssertEqual(child.family?.cloud, place)
        XCTAssertEqual(child.boards.daily.quests.first?.title, "Take out the bins")
        XCTAssertFalse(cloud.kid.isEmpty, "an empty note, to say they joined")
        parent = syncParent(parent, kidId, &cloud)
        XCTAssertEqual(parent.household?.children.first?.joined, true)

        // The child finishes it. One sync each, and the parent's Spade knows.
        let key = try XCTUnwrap(child.boards.daily.quests.first?.key)
        child = markQuest(child, .daily, key: key, now: now, clock: clock).save
        XCTAssertEqual(unsentClaims(child).count, 1)
        child = syncKid(child, &cloud, now: now)
        XCTAssertTrue(unsentClaims(child).isEmpty)
        parent = syncParent(parent, kidId, &cloud)
        XCTAssertEqual(parent.household?.children.first?.claims.map { $0.status }, [.waiting])

        // The parent approves. One sync each, and the child's Spade knows.
        parent = decideClaim(parent, kidId: kidId, key: key, approve: true)
        parent = syncParent(parent, kidId, &cloud)
        child = syncKid(child, &cloud, now: now)
        XCTAssertEqual(child.family?.claims.map { $0.status }, [.approved])

        // With nothing new, more syncs change nothing at all, on either phone or in iCloud.
        let before = cloud
        XCTAssertEqual(syncParent(parent, kidId, &cloud), parent)
        XCTAssertEqual(syncKid(child, &cloud, now: now), child)
        XCTAssertEqual(cloud.parent, before.parent)
        XCTAssertEqual(cloud.kid, before.kid)
    }

    /// Both phones change things while the child's is offline. When it comes back, nothing is
    /// lost and nothing counts twice, whichever phone syncs first.
    func testOfflineChangesCatchUpInAnyOrder() throws {
        let now = at(2026, 11, 14)
        for parentFirst in [true, false] {
            var cloud = Pages()
            var (parent, kidId) = try parentWithKid(now)
            parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)
            var shed = chores()
            shed.title = "Tidy the shed"
            shed.allowance = 400
            parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, shed, now: now)
            parent = markShared(parent, kidId: kidId, true)
            parent = syncParent(parent, kidId, &cloud)
            var child = syncKid(player(3, "Tess", now), &cloud, now: now)
            let xpBefore = child.xp

            // Offline, the child finishes both quests.
            for entry in child.boards.daily.quests where entry.family != nil {
                child = markQuest(child, .daily, key: entry.key, now: now, clock: clock).save
            }
            XCTAssertEqual(unsentClaims(child).count, 2)
            let xpEarned = child.xp - xpBefore
            XCTAssertGreaterThanOrEqual(xpEarned, 120, "60 XP for each of the two quests")

            // Meanwhile the parent raises one quest's allowance and deletes the other.
            let quests = try XCTUnwrap(parent.household?.children.first?.quests)
            let binsId = try XCTUnwrap(quests.first { $0.title == "Take out the bins" }?.id)
            let shedId = try XCTUnwrap(quests.first { $0.title == "Tidy the shed" }?.id)
            var raised = chores()
            raised.allowance = 200
            parent = saveFamilyQuest(parent, kidId: kidId, questId: binsId, raised, now: now)
            parent = removeFamilyQuest(parent, kidId: kidId, questId: shedId)

            // The child's phone comes back. The phones sync in one order or the other, twice over.
            for _ in 0..<2 {
                if parentFirst {
                    parent = syncParent(parent, kidId, &cloud)
                    child = syncKid(child, &cloud, now: now)
                } else {
                    child = syncKid(child, &cloud, now: now)
                    parent = syncParent(parent, kidId, &cloud)
                }
            }

            // The child keeps the XP their phone gave them, and both finished quests stay on record.
            XCTAssertEqual(child.xp - xpBefore, xpEarned, "parent first: \(parentFirst)")
            XCTAssertEqual(child.family?.claims.count, 2)
            XCTAssertEqual(child.family?.quests.map { $0.title }, ["Take out the bins"], "the deleted quest is gone from the list")
            XCTAssertTrue(unsentClaims(child).isEmpty)

            // The parent sees both, each once, at the amounts on the parent's own phone:
            // the raised one at the new amount, the deleted one at what it was.
            let claims = try XCTUnwrap(parent.household?.children.first?.claims)
            XCTAssertEqual(claims.count, 2, "parent first: \(parentFirst)")
            XCTAssertEqual(claims.first { $0.questId == binsId }?.allowance, 200)
            XCTAssertEqual(claims.first { $0.questId == shedId }?.allowance, 400)
            XCTAssertEqual(claims.first { $0.questId == shedId }?.title, "Tidy the shed")
            XCTAssertEqual(claims.total(.waiting), 600)
            XCTAssertFalse(try XCTUnwrap(parent.household?.children.first).needsUpdate)
        }
    }

    /// A page that turns up late (an older copy than one already read) changes nothing.
    func testAnOlderPageIsIgnored() throws {
        let now = at(2026, 11, 14)
        var cloud = Pages()
        var (parent, kidId) = try parentWithKid(now)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)
        parent = markShared(parent, kidId: kidId, true)
        parent = syncParent(parent, kidId, &cloud)
        let older = cloud.parent

        var second = chores()
        second.title = "Feed the cat"
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, second, now: now)
        parent = syncParent(parent, kidId, &cloud)
        var child = syncKid(player(3, "Tess", now), &cloud, now: now)
        XCTAssertEqual(child.family?.quests.count, 2)

        cloud.parent = older
        let again = try XCTUnwrap(readParentPage(child, cloud.parent, cloud: place, now: now))
        XCTAssertEqual(again.result, .stale)
        XCTAssertEqual(again.save, child)
        child = syncKid(child, &cloud, now: now)
        XCTAssertEqual(child.family?.quests.count, 2, "still both quests")
    }

    /// Something can change while a page is on its way to iCloud. Only what was
    /// actually stored counts as stored; the rest goes with the next sync.
    func testOnlyWhatWasStoredCountsAsStored() throws {
        let now = at(2026, 11, 14)
        var cloud = Pages()
        var (parent, kidId) = try parentWithKid(now)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)
        parent = markShared(parent, kidId: kidId, true)

        // The parent adds a quest while the first page is still uploading.
        let first = try XCTUnwrap(parentPageDue(parent, kidId: kidId))
        var second = chores()
        second.title = "Feed the cat"
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, second, now: now)
        cloud.parent = first.body
        parent = markSent(parent, kidId: kidId, revision: first.revision)
        XCTAssertTrue(try XCTUnwrap(parent.household?.children.first).needsUpdate, "the cat quest still has to go")
        parent = syncParent(parent, kidId, &cloud)
        XCTAssertFalse(try XCTUnwrap(parent.household?.children.first).needsUpdate)

        // The child finishes a second quest while their page is still uploading.
        var child = syncKid(player(3, "Tess", now), &cloud, now: now)
        let keys = child.boards.daily.quests.filter { $0.family != nil }.map { $0.key }
        XCTAssertEqual(keys.count, 2)
        child = markQuest(child, .daily, key: keys[0], now: now, clock: clock).save
        let page = try XCTUnwrap(kidPageDue(child))
        child = markQuest(child, .daily, key: keys[1], now: now, clock: clock).save
        cloud.kid = page.body
        child = markReported(child, keys: page.keys)
        XCTAssertEqual(unsentClaims(child).map { $0.key }, [keys[1]], "the second one still has to go")
        parent = syncParent(parent, kidId, &cloud)
        XCTAssertEqual(parent.household?.children.first?.claims.count, 1)
        child = syncKid(child, &cloud, now: now)
        parent = syncParent(parent, kidId, &cloud)
        XCTAssertEqual(parent.household?.children.first?.claims.count, 2)
    }

    /// A child's page can only add that child's finished quests. It can't speak for a
    /// brother or sister, and a parent's page in its place is not read at all.
    func testAPageOnlySpeaksForItsOwnChild() throws {
        let now = at(2026, 11, 14)
        var cloud = Pages()
        var (parent, tessId) = try parentWithKid(now)
        let added = addKid(parent, name: "Robin", now: at(2026, 11, 15))
        parent = added.save
        let robinId = try XCTUnwrap(added.kidId)
        XCTAssertNotEqual(tessId, robinId)
        parent = saveFamilyQuest(parent, kidId: tessId, questId: nil, chores(), now: now)
        parent = saveFamilyQuest(parent, kidId: robinId, questId: nil, chores(), now: now)
        parent = markShared(parent, kidId: tessId, true)
        parent = syncParent(parent, tessId, &cloud)

        var tess = syncKid(player(3, "Tess", now), &cloud, now: now)
        let key = try XCTUnwrap(tess.boards.daily.quests.first?.key)
        tess = markQuest(tess, .daily, key: key, now: now, clock: clock).save
        tess = syncKid(tess, &cloud, now: now)

        XCTAssertNil(readKidPage(parent, kidId: robinId, cloud.kid), "Tess's page, offered as Robin's")
        XCTAssertNil(readKidPage(parent, kidId: tessId, cloud.parent), "a parent's page where a child's belongs")
        XCTAssertNil(readParentPage(tess, cloud.kid, cloud: place, now: now), "a child's page where a parent's belongs")
        XCTAssertNotNil(readKidPage(parent, kidId: tessId, cloud.kid))
    }

    /// Taking an invite back, then inviting again, starts cleanly: everything is sent afresh.
    func testInvitingAgainStartsAfresh() throws {
        let now = at(2026, 11, 14)
        var cloud = Pages()
        var (parent, kidId) = try parentWithKid(now)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: now)
        parent = markShared(parent, kidId: kidId, true)
        parent = syncParent(parent, kidId, &cloud)
        var child = syncKid(player(3, "Tess", now), &cloud, now: now)
        let key = try XCTUnwrap(child.boards.daily.quests.first?.key)
        child = markQuest(child, .daily, key: key, now: now, clock: clock).save
        child = syncKid(child, &cloud, now: now)
        parent = syncParent(parent, kidId, &cloud)
        XCTAssertEqual(parent.household?.children.first?.joined, true)

        // The parent stops sharing. iCloud's pages go, and the parent's Spade forgets the child had joined.
        parent = markShared(parent, kidId: kidId, false)
        cloud = Pages()
        XCTAssertNil(parent.household?.children.first?.joined)
        XCTAssertNil(parentPageDue(parent, kidId: kidId))
        XCTAssertEqual(parent.household?.children.first?.claims.count, 1, "the record stays")

        // A new invite, kept somewhere new. Both phones write their whole page again.
        parent = markShared(parent, kidId: kidId, true)
        parent = syncParent(parent, kidId, &cloud)
        XCTAssertFalse(cloud.parent.isEmpty)
        let elsewhere = CloudLink(zone: "SpadeFamily", owner: "_dad")
        child = try XCTUnwrap(readParentPage(child, cloud.parent, cloud: elsewhere, now: now)).save
        XCTAssertEqual(child.family?.cloud, elsewhere)
        XCTAssertEqual(unsentClaims(child).count, 1, "the finished quest goes on the new page")
        XCTAssertEqual(child.family?.claims.count, 1, "and the child's own record is untouched")
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

        // The parent's note travels on a page; the child's Spade joins the family.
        let note = try viaPage(try XCTUnwrap(noteFor(parent, kidId: kidId)))
        parent = markSent(parent, kidId: kidId, revision: note.revision)
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

        // The child's note goes back. Even if the amount in it were changed, the parent's own amount counts.
        var report = try XCTUnwrap(childNote(child))
        report.done[0].allowance = 99_999
        child = markReported(child, keys: report.done.map { $0.key })
        XCTAssertTrue(unsentClaims(child).isEmpty)
        guard case .fromChild(let travelled)? = FamilyPages.read(FamilyPages.write(.fromChild(report))) else {
            return XCTFail("expected a child's note")
        }
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

    /// Both phones can see when each quest was done, including quests that pay no allowance,
    /// and how much each quest has earned.
    func testEveryFamilyQuestIsRecordedWithItsEarnings() throws {
        let day1 = at(2026, 11, 14)
        let day2 = at(2026, 11, 15)
        var (parent, kidId) = try parentWithKid(day1)
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, chores(), now: day1)
        var reading = chores()
        reading.title = "Read for 20 minutes"
        reading.allowance = 0
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, reading, now: day1)
        var child = receiveParentNote(player(3, "Tess", day1), try XCTUnwrap(noteFor(parent, kidId: kidId)), now: day1).save

        // Two days of both quests.
        for day in [day1, day2] {
            child = syncPeriods(child, now: day, clock: clock)
            for entry in child.boards.daily.quests where entry.family != nil && !entry.done {
                let out = markQuest(child, .daily, key: entry.key, now: day, clock: clock)
                child = out.save
                // Only the allowance quest raises the "send it to your parent" notice.
                XCTAssertEqual(out.events.contains(.allowance(amount: 150)), entry.title == "Take out the bins")
            }
        }

        // The child's phone recorded all four, with when each was done.
        let mine = try XCTUnwrap(child.family?.claims)
        XCTAssertEqual(mine.count, 4)
        XCTAssertEqual(mine.filter { $0.title == "Read for 20 minutes" }.map { $0.status }, [.done, .done])
        XCTAssertEqual(mine.filter { $0.title == "Take out the bins" }.map { $0.status }, [.waiting, .waiting])
        XCTAssertEqual(mine.map { $0.doneAt }, [millis(day1), millis(day1), millis(day2), millis(day2)])
        XCTAssertEqual(unsentClaims(child).count, 4, "XP-only quests are reported too")

        // The parent hears about all four; only the allowance ones need checking.
        let heard = receiveChildNote(parent, try XCTUnwrap(childNote(child)))
        parent = heard.save
        XCTAssertEqual(heard.result, .added(kidId: kidId, count: 4))
        child = markReported(child, keys: unsentClaims(child).map { $0.key })
        XCTAssertTrue(unsentClaims(child).isEmpty)
        var claims = try XCTUnwrap(parent.household?.children.first?.claims)
        XCTAssertEqual(claims.filter { $0.status == .waiting }.count, 2)
        XCTAssertEqual(claims.filter { $0.status == .done }.map { $0.doneAt }, [millis(day1), millis(day2)])

        // Earnings, quest by quest: one approved, one turned down.
        let bins = try XCTUnwrap(parent.household?.children.first?.quests.first { $0.title == "Take out the bins" })
        let readId = try XCTUnwrap(parent.household?.children.first?.quests.first { $0.title == "Read for 20 minutes" }?.id)
        XCTAssertEqual(claims.earnings(for: bins.id), QuestEarnings(times: 2, earned: 0, waiting: 300))
        let waitingKeys = claims.filter { $0.status == .waiting }.map { $0.key }
        parent = decideClaim(parent, kidId: kidId, key: waitingKeys[0], approve: true)
        parent = decideClaim(parent, kidId: kidId, key: waitingKeys[1], approve: false)
        claims = try XCTUnwrap(parent.household?.children.first?.claims)
        XCTAssertEqual(claims.earnings(for: bins.id), QuestEarnings(times: 1, earned: 150, waiting: 0))
        XCTAssertEqual(claims.earnings(for: readId), QuestEarnings(times: 2, earned: 0, waiting: 0))

        // The child sees the same once the parent's next note arrives.
        child = receiveParentNote(child, try XCTUnwrap(noteFor(parent, kidId: kidId)), now: day2).save
        let theirs = try XCTUnwrap(child.family?.claims)
        XCTAssertEqual(theirs.earnings(for: bins.id), QuestEarnings(times: 1, earned: 150, waiting: 0))
        XCTAssertEqual(theirs.earnings(for: readId).times, 2)
    }

    /// A parent can ask for a photo. The request reaches the child's board, the child's record
    /// notes that a photo was taken, and the parent's copy learns that one was sent.
    func testPhotoProofFlagsTravel() throws {
        let now = at(2026, 11, 14)
        var (parent, kidId) = try parentWithKid(now)
        var lawn = chores()
        lawn.title = "Mow the lawn"
        lawn.askPhoto = true
        parent = saveFamilyQuest(parent, kidId: kidId, questId: nil, lawn, now: now)
        XCTAssertEqual(parent.household?.children.first?.quests.first?.askPhoto, true)

        var child = receiveParentNote(player(3, "Tess", now), try XCTUnwrap(noteFor(parent, kidId: kidId)), now: now).save
        let entry = try XCTUnwrap(child.boards.daily.quests.first)
        XCTAssertEqual(entry.family?.askPhoto, true)
        child = markQuest(child, .daily, key: entry.key, now: now, clock: clock).save
        XCTAssertNil(child.family?.claims.first?.photo)
        child = markPhotoTaken(child, key: entry.key)
        XCTAssertEqual(child.family?.claims.first?.photo, true)
        XCTAssertEqual(markPhotoTaken(child, key: "no-such-key"), child)

        parent = receiveChildNote(parent, try XCTUnwrap(childNote(child))).save
        XCTAssertEqual(parent.household?.children.first?.claims.first?.photo, true)

        // Notes from before photos existed still read, as "no photo".
        let old = #"{"id":"fq_1","title":"Bins","cadence":"daily","category":"home","xp":40,"allowance":100,"repeats":true}"#
        let quest = try JSONDecoder().decode(FamilyQuest.self, from: Data(old.utf8))
        XCTAssertNil(quest.askPhoto)
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
