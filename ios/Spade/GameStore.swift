import CloudKit
import Foundation
import SwiftUI
import UIKit

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
        /// A parent's allowance quest is done and waits for them to check it.
        case allowance(amount: Int)
        /// News from the other phone in the family: "Tess finished 2 quests".
        case family(title: String, note: String)
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
        // Family invites that were opened, and nudges from iCloud, come in through here.
        CloudDoor.onInvite = { [weak self] invite in self?.inviteArrived(invite) }
        CloudDoor.onNudge = { [weak self] in await self?.syncFamilyAndWait() }
        syncFamily()
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

    /// Stores a new save. `fromCloud` marks changes that came out of a sync, which don't need another one.
    private func commit(_ next: Save, fromCloud: Bool = false) {
        guard next != save else { return }
        let familyChanged = next.household != save.household || next.family != save.family || next.role != save.role
        save = next
        guard !ephemeral else { return }
        try? exportSave(next).write(to: Self.fileURL, options: .atomic)
        if familyChanged && !fromCloud { syncFamilySoon() }
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
            case .allowance(let amount):
                toasts.append(Toast(id: serial, kind: .allowance(amount: amount)))
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

    // MARK: - Families

    /// A family invite that was opened on this iPhone, and how joining is going.
    struct Incoming: Identifiable {
        let id = UUID()
        /// Who it is from, as the parent's Spade named them ("Sam").
        var from: String
        var step: Step

        enum Step: Equatable {
            /// Waiting for the player to say yes.
            case asking
            case joining
            case joined(ParentNoteSummary, quests: [FamilyQuest], currency: String)
            /// The invite is for the family this Spade is already in.
            case already
            case failed(String)
            /// It can't be used here: this is a parent's Spade, or the parent's own invite.
            case notForYou(String)
        }
    }

    @Published var incoming: Incoming?
    /// Something about iCloud the parent should read, shown as an alert.
    @Published var cloudNotice: String?
    /// The child whose invite is being got ready, if any.
    @Published private(set) var preparingInvite: String?
    /// The invite itself, kept until the player has answered.
    private var invite: CKShare.Metadata?

    /// An invite was tapped. (iOS hands it over once the person has agreed to open it in Spade.)
    func inviteArrived(_ metadata: CKShare.Metadata) {
        invite = metadata
        let from = CloudFamily.sender(of: metadata)
        if metadata.participantRole == .owner {
            incoming = Incoming(from: from, step: .notForYou("This is your own invite. Send it to your child: it opens on their iPhone, not this one."))
        } else if save.role == .parent {
            incoming = Incoming(from: from, step: .notForYou("This invite is for a child's Spade, and this one is set up as a parent's. To join a family here, first change who this Spade is for, in Settings."))
        } else if let place = CloudFamily.place(of: metadata), save.family?.cloud == place.link, save.family?.childId == place.kidId {
            // Already in this family: there's nothing to ask, so just catch up.
            incoming = Incoming(from: from, step: .joining)
            acceptIncoming()
        } else {
            incoming = Incoming(from: from, step: .asking)
        }
    }

    /// Says yes to the waiting invite: joins through iCloud, and puts the parent's quests on the board.
    func acceptIncoming() {
        guard let metadata = invite, let arrival = incoming, let cloudKit = cloudFamily() else { return }
        incoming?.step = .joining
        Task {
            let step: Incoming.Step
            do {
                let found = try await cloudKit.join(metadata)
                let before = save
                guard let out = readParentPage(save, found.body, cloud: found.link, now: Date()) else {
                    throw CloudProblem.badInvite
                }
                commit(out.save)
                switch out.result {
                case .applied(let summary):
                    step = .joined(summary, quests: save.family?.quests ?? [], currency: save.family?.currency ?? Money.local)
                case .stale:
                    step = .already
                case .isParent:
                    step = .notForYou("This invite is for a child's Spade, and this one is set up as a parent's.")
                }
                invite = nil
                tidyCloud(after: before)
                syncFamily()
            } catch {
                step = .failed(CloudFamily.describe(error))
            }
            // Only if that sheet is still the one on screen.
            if incoming?.id == arrival.id { incoming?.step = step }
        }
    }

    func closeIncoming() {
        incoming = nil
    }

    /// Puts an invite sheet on screen directly. Only the demo screens use this.
    func showInvite(_ arrival: Incoming) {
        incoming = arrival
    }

    /// Changes who this Spade is for.
    func chooseRole(_ role: Role) {
        let before = save
        commit(setRole(save, role, currency: Money.local, now: Date()))
        tidyPhotos()
        tidyCloud(after: before)
    }

    /// Seals a parent's quest that asked for a photo: keeps the photo, then marks the quest.
    @discardableResult
    func sealWithPhoto(_ cadence: Cadence, key: String, image: UIImage) -> [GameEvent] {
        let kept = ProofPhotos.save(image, for: key)
        let events = mark(cadence, key: key)
        if kept { commit(markPhotoTaken(save, key: key)) }
        return events
    }

    /// Deletes photos for quests that are no longer on record (after leaving a family, say).
    private func tidyPhotos() {
        ProofPhotos.keepOnly(save.family?.claims.map { $0.key } ?? [])
    }

    @discardableResult
    func addChild(name: String) -> String? {
        let out = addKid(save, name: name, now: Date())
        commit(out.save)
        return out.kidId
    }

    func renameChild(_ kidId: String, to name: String) {
        commit(renameKid(save, kidId: kidId, name: name))
    }

    func removeChild(_ kidId: String) {
        let before = save
        commit(removeKid(save, kidId: kidId))
        tidyCloud(after: before)
    }

    func saveChildQuest(kidId: String, questId: String?, _ input: FamilyQuestInput) {
        commit(saveFamilyQuest(save, kidId: kidId, questId: questId, input, now: Date()))
    }

    func removeChildQuest(kidId: String, questId: String) {
        commit(removeFamilyQuest(save, kidId: kidId, questId: questId))
    }

    func judge(kidId: String, key: String, approve: Bool) {
        commit(decideClaim(save, kidId: kidId, key: key, approve: approve))
    }

    func payAll(kidId: String) {
        commit(markPaid(save, kidId: kidId))
    }

    /// The child's photos for quests the parent hasn't checked yet. Photos stay on this
    /// iPhone; for now the child sends them through the share sheet.
    func photosForParent() -> [(claim: Claim, url: URL)] {
        guard let family = save.family else { return [] }
        return family.claims.filter { $0.status == .waiting && $0.photo == true }.compactMap { claim in
            guard let url = ProofPhotos.url(for: claim.key) else { return nil }
            return (claim: claim, url: url)
        }
    }

    /// Opens the share sheet with those photos, and a line saying which quest each is for.
    func sharePhotosWithParent() {
        let photos = photosForParent()
        guard !photos.isEmpty else { return }
        var text = "Photos for my Spade quests:"
        for (index, photo) in photos.enumerated() {
            text += "\n\(index + 1). \(photo.claim.title)"
        }
        let items: [Any] = [text] + photos.map { $0.url }
        Share.present(items)
    }

    // MARK: - iCloud

    /// How keeping in step with iCloud is going. Settings shows it.
    enum CloudState: Equatable {
        /// Nothing to keep in step: no invite has been made, and no family joined.
        case idle
        case syncing
        case upToDate(Date)
        /// iCloud can't be used right now (not signed in, for example).
        case unavailable(String)
        case failed(String)
    }

    @Published private(set) var cloudState: CloudState = .idle

    private var cloudKit: CloudFamily?
    private var syncing = false
    private var syncWanted = false
    private var syncTimer: Task<Void, Never>?
    /// The version of each page that was read last, so an unchanged page isn't read twice.
    private var pageTags: [String: String] = [:]

    /// The iCloud connection, made the first time it is needed. Demo screens never get one.
    private func cloudFamily() -> CloudFamily? {
        guard !ephemeral else { return nil }
        if cloudKit == nil { cloudKit = CloudFamily() }
        return cloudKit
    }

    /// Whether this Spade has anything in iCloud to keep in step with.
    private var usesCloud: Bool {
        switch save.role {
        case .parent: return save.household?.children.contains { $0.shared == true } ?? false
        case .child: return save.family?.cloud != nil
        case .solo: return false
        }
    }

    /// Shows a sync state directly. Only the demo screens use this.
    func showCloud(_ state: CloudState) {
        cloudState = state
    }

    /// Brings this Spade and iCloud into step. It is fine to call this often: only one sync runs at a time.
    func syncFamily() {
        Task { await syncFamilyAndWait() }
    }

    /// The same, for a caller that wants to wait until it has finished.
    func syncFamilyAndWait() async {
        guard !ephemeral else { return }
        guard usesCloud, let cloudKit = cloudFamily() else {
            if cloudState != .idle { cloudState = .idle }
            return
        }
        if syncing {
            syncWanted = true
            return
        }
        syncing = true
        await runSync(cloudKit)
        syncing = false
        if syncWanted {
            syncWanted = false
            syncFamily()
        }
    }

    /// A sync shortly after something changed, so several quick changes go up together.
    private func syncFamilySoon() {
        syncTimer?.cancel()
        syncTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            if Task.isCancelled { return }
            self?.syncFamily()
        }
    }

    private func runSync(_ cloudKit: CloudFamily) async {
        if let reason = await cloudKit.unavailableReason() {
            cloudState = .unavailable(reason)
            return
        }
        // "Up to date" stays up while it is checked again, so the line doesn't flicker.
        if case .upToDate = cloudState {} else { cloudState = .syncing }
        do {
            switch save.role {
            case .parent: try await syncAsParent(cloudKit)
            case .child: try await syncAsChild(cloudKit)
            case .solo: break
            }
            if !usesCloud {
                cloudState = .idle
            } else if case .upToDate(let at) = cloudState, Date().timeIntervalSince(at) < 50 {
                // Still true, and the time shown is only to the minute: no need to redraw the screens.
            } else {
                cloudState = .upToDate(Date())
            }
        } catch {
            cloudState = .failed(CloudFamily.describe(error))
        }
    }

    /// The parent's phone: store its page for each invited child if iCloud is behind, then read theirs.
    private func syncAsParent(_ cloudKit: CloudFamily) async throws {
        await cloudKit.listen(asParent: true)
        var firstError: Error?
        let invited = (save.household?.children ?? []).filter { $0.shared == true }.map { $0.id }
        for kidId in invited {
            do {
                if let due = parentPageDue(save, kidId: kidId) {
                    try await cloudKit.storeParentPage(kidId: kidId, body: due.body)
                    commit(markSent(save, kidId: kidId, revision: due.revision), fromCloud: true)
                }
                guard let page = try await cloudKit.kidPage(kidId: kidId) else { continue }
                if let tag = page.tag, pageTags[kidId] == tag { continue }
                if let out = readKidPage(save, kidId: kidId, page.body) {
                    commit(out.save, fromCloud: true)
                    if case .added(_, let count) = out.result { announceFinished(kidId: kidId, count: count) }
                }
                pageTags[kidId] = page.tag
            } catch CloudProblem.notShared {
                // The pages are gone from iCloud (sharing was stopped somewhere else). Offer a fresh invite.
                commit(markShared(save, kidId: kidId, false), fromCloud: true)
                pageTags[kidId] = nil
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    /// The child's phone: read the parent's page, then store its own if iCloud is behind.
    private func syncAsChild(_ cloudKit: CloudFamily) async throws {
        guard let family = save.family, let link = family.cloud else { return }
        let kidId = family.childId
        // While waiting on iCloud the player may leave the family; then there is nothing more to do.
        func stillIn() -> Bool { save.family?.cloud == link && save.family?.childId == kidId }

        await cloudKit.listen(asParent: false)
        guard let page = try await cloudKit.parentPage(link: link, kidId: kidId) else { throw CloudProblem.notShared }
        guard stillIn() else { return }
        if page.tag == nil || pageTags["parent"] != page.tag {
            if let out = readParentPage(save, page.body, cloud: link, now: Date()) {
                commit(out.save, fromCloud: true)
                if case .applied(let summary) = out.result { announce(summary, from: family.parentName) }
            }
            pageTags["parent"] = page.tag
        }
        if let due = kidPageDue(save) {
            try await cloudKit.storeKidPage(link: link, kidId: kidId, body: due.body)
            guard stillIn() else { return }
            commit(markReported(save, keys: due.keys), fromCloud: true)
        }
    }

    private func toast(_ title: String, _ note: String) {
        serial += 1
        toasts.append(Toast(id: serial, kind: .family(title: title, note: note)))
    }

    /// Tells the parent a child finished something.
    private func announceFinished(kidId: String, count: Int) {
        guard let kid = save.household?.children.first(where: { $0.id == kidId }) else { return }
        let waiting = kid.claims.filter { $0.status == .waiting }.count
        toast(
            "\(kid.name) finished \(count == 1 ? "a quest" : "\(count) quests")",
            waiting > 0 ? "\(waiting) to check in Family" : "See when in Family"
        )
    }

    /// Tells the child what their parent changed.
    private func announce(_ summary: ParentNoteSummary, from parent: String) {
        func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }
        if summary.newQuests > 0 { toast(count(summary.newQuests, "new quest", "new quests"), "From \(parent)") }
        if summary.approved > 0 { toast(count(summary.approved, "quest approved", "quests approved"), "\(parent) owes you for \(summary.approved == 1 ? "it" : "them")") }
        if summary.paid > 0 { toast(count(summary.paid, "quest paid", "quests paid"), "From \(parent)") }
        if summary.declined > 0 { toast(count(summary.declined, "quest not approved", "quests not approved"), "Ask \(parent) why") }
    }

    /// Gets this child's invite ready in iCloud, then opens Apple's sharing sheet to send it.
    /// For a child who is already invited, the same sheet shows who has joined and can take the invite back.
    func invite(_ kidId: String) {
        guard preparingInvite == nil, let note = noteFor(save, kidId: kidId), let cloudKit = cloudFamily() else { return }
        preparingInvite = kidId
        Task {
            defer { preparingInvite = nil }
            if let reason = await cloudKit.unavailableReason() {
                cloudNotice = reason
                return
            }
            do {
                let title = CloudFamily.titlePrefix + note.parentName
                let share = try await cloudKit.prepareShare(kidId: kidId, title: title, body: FamilyPages.write(.fromParent(note)))
                commit(markSent(markShared(save, kidId: kidId, true), kidId: kidId, revision: note.revision))
                InviteSheet.present(
                    share: share,
                    container: cloudKit.container,
                    title: title,
                    stopped: { [weak self] in self?.sharingStopped(kidId) },
                    failed: { [weak self] error in self?.cloudNotice = CloudFamily.describe(error) }
                )
            } catch {
                cloudNotice = CloudFamily.describe(error)
            }
        }
    }

    /// The parent chose "Stop sharing" in Apple's sheet.
    private func sharingStopped(_ kidId: String) {
        commit(markShared(save, kidId: kidId, false))
        pageTags[kidId] = nil
        guard let cloudKit = cloudFamily() else { return }
        Task { try? await cloudKit.withdraw(kidId: kidId) }
    }

    /// Clears out of iCloud whatever the last change left behind: the share of a family
    /// this Spade has left, and the pages of children who are no longer in the family.
    private func tidyCloud(after before: Save) {
        if let old = before.family, let link = old.cloud, save.family?.cloud != link, let cloudKit = cloudFamily() {
            pageTags["parent"] = nil
            Task { try? await cloudKit.leave(link: link, kidId: old.childId) }
        }
        let still = Set((save.household?.children ?? []).map { $0.id })
        for kid in before.household?.children ?? [] where kid.shared == true && !still.contains(kid.id) {
            guard let cloudKit = cloudFamily() else { break }
            pageTags[kid.id] = nil
            Task { try? await cloudKit.withdraw(kidId: kid.id) }
        }
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
        let before = save
        moments = []
        toasts = []
        incoming = nil
        invite = nil
        commit(Self.freshSave())
        tidyPhotos()
        tidyCloud(after: before)
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
        case "launch", "title", "roles":
            return GameStore(preview: newSave(seed: 7, now: Date()))
        case "family", "familyquest":
            return GameStore(preview: parentGame())
        case "sync":
            // The parent's Settings, with iCloud keeping the family in step.
            let store = GameStore(preview: parentGame())
            store.showCloud(.upToDate(Date()))
            return store
        case "allowance", "childboard", "photoproof":
            let save = childGame()
            // A stand-in photo for the lawn, so the allowance sheet has one to show.
            if let key = save.family?.claims.last(where: { $0.photo == true })?.key {
                ProofPhotos.save(demoPhoto(), for: key)
            }
            return GameStore(preview: save)
        case "join":
            // A player has just tapped a parent's invite for the first time.
            let store = GameStore(preview: midGame())
            store.showInvite(GameStore.Incoming(from: "Sam", step: .asking))
            return store
        case "joined":
            // And has said yes: the parent's quests are on their board.
            let store = GameStore(preview: childGame())
            store.showInvite(GameStore.Incoming(
                from: "Sam",
                step: .joined(ParentNoteSummary(joined: true, newQuests: demoQuests.count), quests: demoQuests, currency: "USD")
            ))
            return store
        default:
            var save = midGame()
            if name == "smooth" { save.settings.retro = false }
            let store = GameStore(preview: save)
            if name == "dig" { store.show(.item(serial: -1, itemId: "moonsteel_cap", fresh: true, echoXp: 0)) }
            if name == "level" { store.show(.level(serial: -2, level: 8, rank: nil)) }
            return store
        }
    }

    /// The quests the demo parent sets for Tess.
    private static let demoQuests = [
        FamilyQuest(id: "fq_dishes", title: "Do the dishes after dinner", cadence: .daily, category: .home, xp: 40, allowance: 100, repeats: true),
        FamilyQuest(id: "fq_reading", title: "Read for 30 minutes", cadence: .daily, category: .mind, xp: 30, allowance: 0, repeats: true),
        FamilyQuest(id: "fq_lawn", title: "Mow the front lawn", cadence: .weekly, category: .home, xp: 150, allowance: 500, repeats: true, askPhoto: true),
        FamilyQuest(id: "fq_room", title: "Tidy your room", cadence: .daily, category: .home, xp: 30, allowance: 50, repeats: true, askPhoto: true),
    ]

    /// A parent, Sam, with two children: Tess has joined and has quests to check, Robin hasn't been invited yet.
    static func parentGame() -> Save {
        let now = Date()
        let clock = GameClock.device
        let ms = millis(now)
        var save = midGame()
        save.hero = HeroSave(name: "Sam", skin: 3, hair: 0, hairStyle: 0, scarf: 2)
        save = setRole(save, .parent, currency: "USD", now: now)
        save.household?.familyId = "fam_demo"

        let today = clock.dayKey(now)
        let yesterday = clock.shiftDay(today, -1)
        var tess = Kid(id: "kid_tess", name: "Tess")
        tess.quests = demoQuests
        tess.claims = [
            Claim(key: "\(clock.shiftDay(today, -2)):fq_dishes", questId: "fq_dishes", title: "Do the dishes after dinner", allowance: 100, doneAt: ms - 2 * 86_400_000, status: .paid),
            Claim(key: "\(clock.shiftDay(today, -2)):fq_reading", questId: "fq_reading", title: "Read for 30 minutes", allowance: 0, doneAt: ms - 2 * 86_400_000 + 3_600_000, status: .done),
            Claim(key: "\(yesterday):fq_dishes", questId: "fq_dishes", title: "Do the dishes after dinner", allowance: 100, doneAt: ms - 86_400_000, status: .approved),
            Claim(key: "\(yesterday):fq_reading", questId: "fq_reading", title: "Read for 30 minutes", allowance: 0, doneAt: ms - 86_400_000 + 1_800_000, status: .done),
            Claim(key: "\(clock.weekKey(now)):fq_lawn", questId: "fq_lawn", title: "Mow the front lawn", allowance: 500, doneAt: ms - 7_200_000, status: .waiting, photo: true),
        ]
        tess.revision = 6
        tess.sentRevision = 6
        tess.shared = true
        tess.joined = true
        var robin = Kid(id: "kid_robin", name: "Robin")
        robin.quests = [FamilyQuest(id: "fq_bed", title: "Make your bed", cadence: .daily, category: .home, xp: 20, allowance: 25, repeats: true)]
        robin.revision = 2
        save.household?.children = [tess, robin]
        return save
    }

    /// Tess, as a child in Sam's family: dishes done today and waiting to be checked.
    static func childGame() -> Save {
        let now = Date()
        let clock = GameClock.device
        let ms = millis(now)
        var save = midGame()
        let note = ParentNote(
            familyId: "fam_demo", parentName: "Sam", childId: "kid_tess", childName: "Tess",
            currency: "USD", revision: 6, quests: demoQuests, decisions: [:]
        )
        save = receiveParentNote(save, note, now: now).save
        if let dishes = save.boards.daily.quests.first(where: { $0.defId == "fq_dishes" }) {
            save = markQuest(save, .daily, key: dishes.key, now: now).save
        }
        // The lawn is done too, with a photo, as its quest asks.
        if let lawn = save.boards.weekly.quests.first(where: { $0.defId == "fq_lawn" }) {
            save = markQuest(save, .weekly, key: lawn.key, now: now).save
            save = markPhotoTaken(save, key: lawn.key)
        }
        let today = clock.dayKey(now)
        let older = [
            Claim(key: "\(clock.shiftDay(today, -9)):fq_lawn", questId: "fq_lawn", title: "Mow the front lawn", allowance: 500, doneAt: ms - 9 * 86_400_000, status: .paid),
            Claim(key: "\(clock.shiftDay(today, -2)):fq_dishes", questId: "fq_dishes", title: "Do the dishes after dinner", allowance: 100, doneAt: ms - 2 * 86_400_000, status: .paid),
            Claim(key: "\(clock.shiftDay(today, -1)):fq_reading", questId: "fq_reading", title: "Read for 30 minutes", allowance: 0, doneAt: ms - 86_400_000 - 3_600_000, status: .done),
            Claim(key: "\(clock.shiftDay(today, -1)):fq_dishes", questId: "fq_dishes", title: "Do the dishes after dinner", allowance: 100, doneAt: ms - 86_400_000, status: .approved),
        ]
        save.family?.claims.insert(contentsOf: older, at: 0)
        // Joined through an invite, with everything already in iCloud.
        save.family?.cloud = CloudLink(zone: "SpadeFamily", owner: "_demo")
        save = markReported(save, keys: save.family?.claims.map { $0.key } ?? [])
        return save
    }

    /// A plain picture of a striped lawn under a sky, standing in for a real photo.
    @MainActor
    static func demoPhoto() -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.62, green: 0.74, blue: 0.86, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 430))
            for stripe in 0..<8 {
                let light = stripe % 2 == 0
                UIColor(red: light ? 0.38 : 0.31, green: light ? 0.63 : 0.55, blue: light ? 0.30 : 0.24, alpha: 1).setFill()
                context.fill(CGRect(x: CGFloat(stripe) * 112.5, y: 430, width: 112.5, height: 770))
            }
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
