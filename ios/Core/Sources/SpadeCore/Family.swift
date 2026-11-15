import Foundation

// Families.
//
// A parent sets quests for a child, chooses the XP each one is worth, and can
// attach an allowance to it. There are no accounts and no server: the two
// phones pass notes to each other as links, the way you might pass a notebook
// back and forth.
//
//   Parent to child: "here are your quests, and here is what I decided about
//   the ones you finished". Each note carries everything, so the newest one
//   always brings the child fully up to date.
//
//   Child to parent: "these allowance quests are done, please check them".
//
// The parent's phone is the record of what is owed. A note from a child only
// says which quests were finished; the amounts always come from the parent's
// own copy, so an edited link can't ask for more.

/// Who this Spade belongs to.
enum Role: String, Codable, CaseIterable {
    /// An ordinary player: no family features.
    case solo
    /// A child, who gets quests (and maybe allowance) from a parent.
    case child
    /// A parent or guardian, who sets quests for their children.
    case parent
}

/// A quest a parent set for a child.
struct FamilyQuest: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var cadence: Cadence
    var category: QuestKind
    var xp: Int
    /// Paid each time it is done, in the smallest unit of the family's currency
    /// (cents, pence...). Zero means no allowance.
    var allowance: Int
    /// Comes back every day, week or month. If false, it stays on the board until it is done once.
    var repeats: Bool
    /// The child adds a photo before it counts. Missing in notes from older versions, which means no.
    var askPhoto: Bool?
}

/// Marks a board entry that came from a parent.
struct FamilyTag: Codable, Equatable {
    var parent: String
    var allowance: Int
    var repeats: Bool
    var askPhoto: Bool?
}

enum ClaimStatus: String, Codable {
    /// Done. It pays no allowance, so there is nothing for the parent to check.
    case done
    /// Done, and waiting for the parent to check it.
    case waiting
    /// The parent agreed it was done: the money is owed.
    case approved
    /// The parent said it wasn't done. No money.
    case declined
    /// The parent has paid it.
    case paid
}

/// One finished quest from a parent: when it was done, and what it earned.
/// Quests with an allowance go through the parent's check; the rest are simply recorded.
struct Claim: Codable, Equatable, Identifiable {
    /// The board key, for example "2026-11-14:fq_abc". One per quest per day, week or month.
    var key: String
    var questId: String
    var title: String
    var allowance: Int
    /// When it was done, in milliseconds since 1970.
    var doneAt: Double
    var status: ClaimStatus
    /// A photo was taken for it. The photo itself stays on the child's phone and travels with
    /// the child's message (never inside the link), so on the parent's Spade this only says one was sent.
    var photo: Bool?

    var id: String { key }
}

extension Array where Element == Claim {
    /// The money in all claims with this status.
    func total(_ status: ClaimStatus) -> Int {
        filter { $0.status == status }.reduce(0) { $0 + $1.allowance }
    }

    /// What one quest has earned so far.
    func earnings(for questId: String) -> QuestEarnings {
        var out = QuestEarnings()
        for claim in self where claim.questId == questId {
            switch claim.status {
            case .done:
                out.times += 1
            case .waiting:
                out.times += 1
                out.waiting += claim.allowance
            case .approved, .paid:
                out.times += 1
                out.earned += claim.allowance
            case .declined:
                break
            }
        }
        return out
    }
}

/// How one quest has done: how many times it was finished (not counting any the parent
/// turned down), the money approved or paid for it, and the money still waiting to be checked.
struct QuestEarnings: Equatable {
    var times = 0
    var earned = 0
    var waiting = 0
}

/// On a child's Spade: the family it belongs to.
struct Membership: Codable, Equatable {
    var familyId: String
    var parentName: String
    var childId: String
    var childName: String
    var currency: String
    /// The newest note from the parent that has been read.
    var revision: Int = 0
    var quests: [FamilyQuest] = []
    var claims: [Claim] = []
    /// One-off quests already done, so they are not put on the board again.
    var finished: [String] = []
    /// Claims already sent to the parent.
    var reported: [String] = []
}

/// A child, as their parent's Spade knows them.
struct Kid: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var quests: [FamilyQuest] = []
    /// Quests the parent has since removed. Kept so a late report about one still makes sense.
    var past: [FamilyQuest] = []
    var claims: [Claim] = []
    /// Goes up with every change the child should hear about.
    var revision: Int = 1
    /// The revision last sent to the child.
    var sentRevision: Int = 0

    /// Whether there are changes the child hasn't been sent yet.
    var needsUpdate: Bool { revision > sentRevision }
}

/// On a parent's Spade: their family.
struct Household: Codable, Equatable {
    var familyId: String
    var currency: String
    var children: [Kid] = []
}

// MARK: - Notes passed between phones

/// From a parent's Spade to a child's.
struct ParentNote: Codable, Equatable {
    var familyId: String
    var parentName: String
    var childId: String
    var childName: String
    var currency: String
    var revision: Int
    var quests: [FamilyQuest]
    /// Claim key -> what the parent decided about it.
    var decisions: [String: ClaimStatus]
}

/// From a child's Spade to their parent's.
struct ChildNote: Codable, Equatable {
    var familyId: String
    var childId: String
    var childName: String
    /// Allowance quests that are done and waiting to be checked.
    var done: [Claim]
}

enum FamilyLink: Equatable {
    case fromParent(ParentNote)
    case fromChild(ChildNote)
}

enum FamilyLinks {
    /// The web page a shared link points to. It hands the note straight on to the app.
    /// The note itself sits after the "#", which browsers never send to a server.
    static let webPage = "https://huzkeymil-art.github.io/spade-sidequests/family.html"
    /// The app's own link scheme, which that page opens.
    static let appScheme = "spade"

    private struct Envelope: Codable {
        var v: Int
        var parent: ParentNote?
        var child: ChildNote?
    }

    /// The text that goes after the "#": the note as JSON, in URL-safe base64.
    static func payload(_ link: FamilyLink) -> String {
        var envelope = Envelope(v: 1)
        switch link {
        case .fromParent(let note): envelope.parent = note
        case .fromChild(let note): envelope.child = note
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(envelope)) ?? Data()
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The link to share: it opens the web page, which opens Spade.
    static func webLink(_ link: FamilyLink) -> String {
        "\(webPage)#\(payload(link))"
    }

    /// What actually gets shared: a friendly line, the link, and the code again on a line of its own.
    /// Some apps turn a link into a preview card and lose everything after the "#" on the way; the
    /// code line is plain text, so it survives that, and pasting the whole message into Spade works.
    static func message(_ link: FamilyLink, intro: String) -> String {
        let code = payload(link)
        return """
        \(intro)

        \(webPage)#\(code)

        If the link doesn't open Spade, copy this whole message, then in Spade go to Settings > Paste a family link.

        Family code: \(code)
        """
    }

    /// Reads a note from anything that might hold one: a shared link, the app's own link, a whole
    /// shared message, or the bare code. Returns nil if none of it is a Spade family note.
    static func read(_ text: String) -> FamilyLink? {
        guard text.count < 200_000 else { return nil }
        for candidate in candidates(text) {
            if let link = decode(candidate) { return link }
        }
        return nil
    }

    /// True when the text looks like a family link, but the code that belongs with it is missing or
    /// damaged: for example, when an app dropped everything after the "#".
    static func missingCode(_ text: String) -> Bool {
        let lower = text.lowercased()
        return read(text) == nil && (lower.contains("family.html") || lower.contains("\(appScheme)://"))
    }

    /// The characters a code is made of (URL-safe base64).
    private static let codeCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )

    /// The code characters at the start of some text, stopping at the first one that isn't.
    private static func leadingCode<S: StringProtocol>(_ text: S) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix { codeCharacters.contains($0) }))
    }

    /// The places a code might be, most likely first.
    private static func candidates(_ text: String) -> [String] {
        var found: [String] = []
        // After a "#", up to the first character that can't be part of a code (a space, a bracket...).
        var rest = Substring(text)
        while let hash = rest.firstIndex(of: "#") {
            rest = rest[rest.index(after: hash)...]
            found.append(leadingCode(rest))
        }
        // A "d=" value, as in "?d=code".
        for part in text.components(separatedBy: CharacterSet(charactersIn: "?&")) where part.hasPrefix("d=") {
            found.append(leadingCode(part.dropFirst(2)))
        }
        // Any long run of code characters, anywhere: the "Family code:" line, or a code pasted on its own.
        let runs = text.unicodeScalars
            .split { !codeCharacters.contains($0) }
            .map { String(String.UnicodeScalarView($0)) }
            .filter { $0.count >= 40 }
            .sorted { $0.count > $1.count }
        found += runs
        // And the whole text, for anything else.
        found.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return found.filter { !$0.isEmpty }
    }

    /// Turns one candidate code back into a note, or nil if it isn't one.
    private static func decode(_ code: String) -> FamilyLink? {
        var base64 = code
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.v == 1
        else { return nil }
        if let note = envelope.parent { return .fromParent(note) }
        if let note = envelope.child { return .fromChild(note) }
        return nil
    }
}

// MARK: - Choosing a role

private func newId(_ prefix: String, _ now: Date, _ salt: Int) -> String {
    "\(prefix)_\(String(Int64(millis(now)), radix: 36))\(String(abs(salt) % 1296, radix: 36))"
}

/// Changes who this Spade is for. Leaving a role clears what belonged to it:
/// a parent's family list, or a child's quests from their parent.
func setRole(_ save: Save, _ role: Role, currency: String, now: Date) -> Save {
    var next = save
    next.role = role
    if role != .parent { next.household = nil }
    if role != .child { next.family = nil }
    if role == .parent && next.household == nil {
        next.household = Household(familyId: newId("fam", now, save.seed), currency: currency)
    }
    return placeFamilyQuests(next)
}

// MARK: - Parent side

/// What a parent fills in to set a quest.
struct FamilyQuestInput {
    var title: String
    var cadence: Cadence
    var category: QuestKind
    var xp: Int
    var allowance: Int
    var repeats: Bool
    var askPhoto = false
}

/// The XP range a parent can choose from.
let familyXpRange = 5...1000
/// The most allowance one quest can pay, in the smallest currency unit.
let familyAllowanceLimit = 100_000

private func editKid(_ save: Save, _ kidId: String, _ change: (inout Kid) -> Void) -> Save {
    guard save.role == .parent, var house = save.household,
          let at = house.children.firstIndex(where: { $0.id == kidId })
    else { return save }
    change(&house.children[at])
    var next = save
    next.household = house
    return next
}

/// Adds a child to the family. Returns the new child's id, or nil if it couldn't be added.
func addKid(_ save: Save, name: String, now: Date) -> (save: Save, kidId: String?) {
    let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    guard save.role == .parent, var house = save.household, !trimmed.isEmpty, house.children.count < 8 else {
        return (save, nil)
    }
    let id = newId("kid", now, house.children.count)
    house.children.append(Kid(id: id, name: trimmed))
    var next = save
    next.household = house
    return (next, id)
}

func renameKid(_ save: Save, kidId: String, name: String) -> Save {
    let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    if trimmed.isEmpty { return save }
    return editKid(save, kidId) {
        $0.name = trimmed
        $0.revision += 1
    }
}

func removeKid(_ save: Save, kidId: String) -> Save {
    guard save.role == .parent, var house = save.household else { return save }
    house.children.removeAll { $0.id == kidId }
    var next = save
    next.household = house
    return next
}

/// Adds a new quest for a child, or changes one (when `questId` is given).
func saveFamilyQuest(_ save: Save, kidId: String, questId: String?, _ input: FamilyQuestInput, now: Date) -> Save {
    let title = String(input.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    if title.isEmpty { return save }
    return editKid(save, kidId) { kid in
        let id = questId ?? newId("fq", now, kid.quests.count + kid.past.count)
        let quest = FamilyQuest(
            id: id,
            title: title,
            cadence: input.cadence,
            category: input.category,
            xp: min(familyXpRange.upperBound, max(familyXpRange.lowerBound, input.xp)),
            allowance: min(familyAllowanceLimit, max(0, input.allowance)),
            repeats: input.repeats,
            askPhoto: input.askPhoto ? true : nil
        )
        if let at = kid.quests.firstIndex(where: { $0.id == id }) {
            kid.quests[at] = quest
        } else {
            kid.quests.append(quest)
        }
        kid.revision += 1
    }
}

func removeFamilyQuest(_ save: Save, kidId: String, questId: String) -> Save {
    editKid(save, kidId) { kid in
        guard let at = kid.quests.firstIndex(where: { $0.id == questId }) else { return }
        let removed = kid.quests.remove(at: at)
        kid.past = Array((kid.past + [removed]).suffix(50))
        kid.revision += 1
    }
}

/// The parent's answer about a finished allowance quest.
func decideClaim(_ save: Save, kidId: String, key: String, approve: Bool) -> Save {
    editKid(save, kidId) { kid in
        guard let at = kid.claims.firstIndex(where: { $0.key == key }), kid.claims[at].status == .waiting else { return }
        kid.claims[at].status = approve ? .approved : .declined
        kid.revision += 1
    }
}

/// Records that everything approved for this child has now been paid.
func markPaid(_ save: Save, kidId: String) -> Save {
    editKid(save, kidId) { kid in
        guard kid.claims.contains(where: { $0.status == .approved }) else { return }
        for i in kid.claims.indices where kid.claims[i].status == .approved {
            kid.claims[i].status = .paid
        }
        kid.revision += 1
    }
}

/// The note to send a child: all their quests, and the newest decisions.
func noteFor(_ save: Save, kidId: String) -> ParentNote? {
    guard save.role == .parent, let house = save.household,
          let kid = house.children.first(where: { $0.id == kidId })
    else { return nil }
    var decisions: [String: ClaimStatus] = [:]
    for claim in kid.claims.suffix(120) where claim.status != .waiting && claim.status != .done {
        decisions[claim.key] = claim.status
    }
    return ParentNote(
        familyId: house.familyId,
        parentName: save.hero.name.isEmpty ? "Your parent" : save.hero.name,
        childId: kid.id,
        childName: kid.name,
        currency: house.currency,
        revision: kid.revision,
        quests: kid.quests,
        decisions: decisions
    )
}

/// Remembers that the child has been sent everything up to now.
func markSent(_ save: Save, kidId: String) -> Save {
    editKid(save, kidId) { $0.sentRevision = $0.revision }
}

enum ChildNoteResult: Equatable {
    /// New finished quests are waiting for the parent to check.
    case added(kidId: String, count: Int)
    /// Everything in the note was already known.
    case nothingNew(kidId: String)
    /// This Spade isn't set up as a parent's.
    case notParent
    /// The note is from a child in a different family.
    case wrongFamily
    /// The child isn't (or is no longer) in this family.
    case unknownChild
}

/// Reads a child's note on the parent's Spade.
func receiveChildNote(_ save: Save, _ note: ChildNote) -> (save: Save, result: ChildNoteResult) {
    guard save.role == .parent, var house = save.household else { return (save, .notParent) }
    guard note.familyId == house.familyId else { return (save, .wrongFamily) }
    guard let at = house.children.firstIndex(where: { $0.id == note.childId }) else { return (save, .unknownChild) }
    var kid = house.children[at]
    var added = 0
    for claim in note.done {
        if kid.claims.contains(where: { $0.key == claim.key }) { continue }
        // Only quests this parent actually set count, at the amount the parent set.
        guard let quest = (kid.quests + kid.past).first(where: { $0.id == claim.questId }) else { continue }
        kid.claims.append(Claim(
            key: claim.key,
            questId: quest.id,
            title: quest.title,
            allowance: quest.allowance,
            doneAt: claim.doneAt,
            // Quests with an allowance wait for the parent's check; the rest are just recorded.
            status: quest.allowance > 0 ? .waiting : .done,
            photo: claim.photo == true ? true : nil
        ))
        added += 1
    }
    kid.claims = Array(kid.claims.suffix(300))
    house.children[at] = kid
    var next = save
    next.household = house
    return (next, added > 0 ? .added(kidId: kid.id, count: added) : .nothingNew(kidId: kid.id))
}

// MARK: - Child side

/// What a parent's note changed, for telling the child about it.
struct ParentNoteSummary: Equatable {
    var joined = false
    var newQuests = 0
    var removedQuests = 0
    var approved = 0
    var declined = 0
    var paid = 0
}

enum ParentNoteResult: Equatable {
    case applied(ParentNoteSummary)
    /// An older note than one already read: nothing to do.
    case stale
    /// This Spade is a parent's, so it can't take quests from another parent.
    case isParent
}

/// Reads a parent's note on the child's Spade, joining the family if needed.
func receiveParentNote(_ save: Save, _ note: ParentNote, now: Date) -> (save: Save, result: ParentNoteResult) {
    if save.role == .parent { return (save, .isParent) }
    var next = save
    var summary = ParentNoteSummary()
    var family: Membership
    if let current = save.family, current.familyId == note.familyId, current.childId == note.childId {
        if note.revision <= current.revision { return (save, .stale) }
        family = current
    } else {
        // A first note, or one from a different family: start afresh with it.
        summary.joined = true
        family = Membership(
            familyId: note.familyId,
            parentName: note.parentName,
            childId: note.childId,
            childName: note.childName,
            currency: note.currency
        )
    }

    let before = Set(family.quests.map { $0.id })
    let after = Set(note.quests.map { $0.id })
    summary.newQuests = after.subtracting(before).count
    summary.removedQuests = before.subtracting(after).count

    for i in family.claims.indices {
        guard let decision = note.decisions[family.claims[i].key], decision != family.claims[i].status else { continue }
        switch decision {
        case .approved: summary.approved += 1
        case .declined: summary.declined += 1
        case .paid: summary.paid += 1
        case .waiting, .done: break
        }
        family.claims[i].status = decision
    }

    family.parentName = note.parentName
    family.childName = note.childName
    family.currency = note.currency
    family.revision = note.revision
    family.quests = note.quests.map { quest in
        var tidy = quest
        tidy.xp = min(familyXpRange.upperBound, max(familyXpRange.lowerBound, quest.xp))
        tidy.allowance = min(familyAllowanceLimit, max(0, quest.allowance))
        tidy.title = String(quest.title.prefix(80))
        return tidy
    }
    next.role = .child
    next.household = nil
    next.family = family
    return (placeFamilyQuests(next), .applied(summary))
}

/// Allowance quests done here that the parent hasn't been sent yet.
func unsentClaims(_ save: Save) -> [Claim] {
    guard let family = save.family else { return [] }
    return family.claims.filter { toReport($0) && !family.reported.contains($0.key) }
}

/// Finished quests the parent should hear about: allowance quests still to be checked,
/// and quests without an allowance, so the parent can see when they were done too.
private func toReport(_ claim: Claim) -> Bool {
    claim.status == .waiting || claim.status == .done
}

/// The note to send the parent: the quests finished here that they should hear about.
func childNote(_ save: Save) -> ChildNote? {
    guard save.role == .child, let family = save.family else { return nil }
    let done = family.claims.filter(toReport)
    if done.isEmpty { return nil }
    return ChildNote(
        familyId: family.familyId,
        childId: family.childId,
        childName: family.childName,
        done: Array(done.suffix(60))
    )
}

/// Remembers that the finished quests have been sent to the parent.
func markReported(_ save: Save) -> Save {
    guard var family = save.family else { return save }
    let waiting = family.claims.filter(toReport).map { $0.key }
    let all = Array(Set(family.reported + waiting)).sorted()
    family.reported = Array(all.suffix(300))
    var next = save
    next.family = family
    return next
}

// MARK: - The board

private func activateFamily(_ quest: FamilyQuest, period: String, parent: String) -> ActiveQuest {
    ActiveQuest(
        key: "\(period):\(quest.id)",
        defId: quest.id,
        cadence: quest.cadence,
        category: quest.category,
        title: quest.title,
        xp: quest.xp,
        target: 1,
        progress: 0,
        done: false,
        custom: false,
        // Parents' quests can't be swapped away.
        pinned: true,
        family: FamilyTag(parent: parent, allowance: quest.allowance, repeats: quest.repeats, askPhoto: quest.askPhoto)
    )
}

/// Puts the parent's quests on the current boards, at the top, and takes off any
/// unfinished ones the parent has removed. Finished ones stay, as a record.
func placeFamilyQuests(_ save: Save) -> Save {
    var next = save
    let family = save.role == .child ? save.family : nil
    for cadence in Cadence.allCases {
        var board = next.boards[cadence]
        let wanted = (family?.quests ?? []).filter { quest in
            quest.cadence == cadence && (quest.repeats || !(family?.finished.contains(quest.id) ?? false))
        }
        // Unfinished parent quests that are no longer wanted leave the board.
        board.quests.removeAll { entry in
            entry.family != nil && !entry.done && !wanted.contains { $0.id == entry.defId }
        }
        // Unfinished ones pick up any changes the parent made.
        for i in board.quests.indices where board.quests[i].family != nil && !board.quests[i].done {
            guard let quest = wanted.first(where: { $0.id == board.quests[i].defId }) else { continue }
            board.quests[i].title = quest.title
            board.quests[i].category = quest.category
            board.quests[i].xp = quest.xp
            board.quests[i].family = FamilyTag(
                parent: family?.parentName ?? "", allowance: quest.allowance, repeats: quest.repeats, askPhoto: quest.askPhoto
            )
        }
        // And new ones go on top, as long as the board belongs to a real day, week or month.
        if !board.period.isEmpty {
            let present = Set(board.quests.map { $0.defId })
            let fresh = wanted.filter { !present.contains($0.id) }
                .map { activateFamily($0, period: board.period, parent: family?.parentName ?? "") }
            board.quests = fresh + board.quests
        }
        next.boards[cadence] = board
    }
    return next
}

/// Bookkeeping when a parent's quest is finished: one-off quests are done for
/// good, and allowance quests wait for the parent to check them.
func recordFamilyQuestDone(_ save: Save, _ quest: ActiveQuest, now: Date, _ events: inout [GameEvent]) -> Save {
    guard let tag = quest.family, var family = save.family else { return save }
    if !tag.repeats && !family.finished.contains(quest.defId) {
        family.finished.append(quest.defId)
    }
    // Every quest from a parent is recorded with when it was done. Allowance quests then wait
    // for the parent to check them; the rest have nothing to check.
    if !family.claims.contains(where: { $0.key == quest.key }) {
        family.claims.append(Claim(
            key: quest.key,
            questId: quest.defId,
            title: quest.title,
            allowance: tag.allowance,
            doneAt: millis(now),
            status: tag.allowance > 0 ? .waiting : .done
        ))
        family.claims = Array(family.claims.suffix(300))
        if tag.allowance > 0 { events.append(.allowance(amount: tag.allowance)) }
    }
    var next = save
    next.family = family
    return next
}

/// Notes that a photo was taken for a finished quest (on the child's Spade). The photo file
/// itself is kept by the app; this flag is what travels to the parent.
func markPhotoTaken(_ save: Save, key: String) -> Save {
    guard var family = save.family, let at = family.claims.firstIndex(where: { $0.key == key }) else { return save }
    family.claims[at].photo = true
    var next = save
    next.family = family
    return next
}

/// Keeps family records within sensible limits when a save is loaded.
func repairFamily(_ save: Save) -> Save {
    var next = save
    func tidy(_ quest: FamilyQuest) -> FamilyQuest {
        var out = quest
        out.title = String(quest.title.prefix(80))
        out.xp = min(familyXpRange.upperBound, max(familyXpRange.lowerBound, quest.xp))
        out.allowance = min(familyAllowanceLimit, max(0, quest.allowance))
        return out
    }
    if var family = next.family {
        family.quests = family.quests.filter { !$0.title.isEmpty }.map(tidy)
        family.claims = Array(family.claims.suffix(300))
        next.family = family
    }
    if var house = next.household {
        for i in house.children.indices {
            house.children[i].quests = house.children[i].quests.filter { !$0.title.isEmpty }.map(tidy)
            house.children[i].claims = Array(house.children[i].claims.suffix(300))
        }
        next.household = house
    }
    // A role without its records falls back to an ordinary player.
    if next.role == .parent && next.household == nil { next.role = .solo }
    if next.role != .parent { next.household = nil }
    if next.role != .child { next.family = nil }
    return next
}
