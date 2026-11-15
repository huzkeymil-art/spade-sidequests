import SwiftUI
import UIKit

// Families, on screen.
//
//   Parent: the Family tab. One card per child, with what's waiting to be
//   checked, what's owed, their quests, and a button to invite them.
//   Child: an allowance row at the top of the quest board, and a sheet with
//   what's waiting, owed and paid.
//   The sheet that opens when a child taps a parent's invite.
//
// After the invite, the two phones keep in step through iCloud by themselves.

extension Role {
    /// The order the choices are shown in.
    static let shown: [Role] = [.solo, .parent, .child]

    var title: String {
        switch self {
        case .solo: return "Just me"
        case .parent: return "Parent or guardian"
        case .child: return "Child"
        }
    }

    var blurb: String {
        switch self {
        case .solo: return "Your own quests, for you"
        case .parent: return "Set quests and allowance for your kids"
        case .child: return "Get quests from your parent too"
        }
    }
}

/// Three chips: just me, parent or guardian, child.
struct RolePicker: View {
    let role: Role
    /// Shows a one-line description of the chosen role under the chips.
    var showsBlurb = true
    let choose: (Role) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FlowLayout {
                ForEach(Role.shown, id: \.self) { option in
                    Chip(title: option.title, selected: option == role) {
                        Feedback.select()
                        choose(option)
                    }
                }
            }
            if showsBlurb {
                Text(role.blurb).caps(Ink.faint)
            }
        }
    }
}

/// When something was done, for example "Sun, Nov 15, 4:32 PM".
private func when(_ millis: Double) -> String {
    Date(timeIntervalSince1970: millis / 1000)
        .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
}

private func schedule(_ quest: FamilyQuest) -> String {
    if quest.repeats, let day = quest.weekday, (0...6).contains(day) { return "Every " + familyWeekdays[day] }
    let every: [Cadence: String] = [.daily: "Every day", .weekly: "Every week", .monthly: "Every month"]
    let once: [Cadence: String] = [.daily: "Once, on the daily board", .weekly: "Once, on the weekly board", .monthly: "Once, on the monthly board"]
    return (quest.repeats ? every : once)[quest.cadence] ?? ""
}

/// How a finished quest is getting on, in a child's words.
func claimWords(_ status: ClaimStatus, parent: String) -> (text: String, color: Color) {
    switch status {
    case .done: return ("Done", Ink.faint)
    case .waiting: return ("Waiting for \(parent)", Ink.faint)
    case .approved: return ("Approved", Ink.verdigris)
    case .declined: return ("Not approved", Ink.rust)
    case .paid: return ("Paid", Ink.lantern)
    }
}

/// One finished family quest: what it was, when it was done, how it's getting on, and what it pays.
private struct HistoryRow: View {
    let claim: Claim
    let currency: String
    /// Who checks it, for the "Waiting for …" wording.
    let checker: String
    /// The photo itself, on the child's own phone.
    var thumbnail: UIImage?

    var body: some View {
        let words = claimWords(claim.status, parent: checker)
        HStack(spacing: 10) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Notched(notch: 5))
                    .accessibilityLabel("Photo")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(claim.title).font(Typeface.text()).foregroundStyle(Ink.bone)
                Text("\(when(claim.doneAt)) · \(words.text)\(claim.photo == true ? " · photo" : "")").caps(words.color)
            }
            Spacer(minLength: 8)
            if claim.allowance > 0 {
                Text(Money.format(claim.allowance, currency))
                    .font(Typeface.label(22))
                    .foregroundStyle(claim.status == .declined ? Ink.faint : Ink.lantern)
                    .strikethrough(claim.status == .declined)
            } else {
                Text(claim.xp.map { "\($0) XP" } ?? "No allowance").caps(Ink.faint, size: 14)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// The line under a quest that says how it's done so far: "Done 4 times · $3.00 earned".
private func earningsLine(_ e: QuestEarnings, allowance: Int, currency: String) -> String? {
    if e.times == 0 { return nil }
    var parts = [e.times == 1 ? "Done once" : "Done \(e.times) times"]
    if allowance > 0 || e.earned > 0 { parts.append("\(Money.format(e.earned, currency)) earned") }
    if e.waiting > 0 { parts.append("\(Money.format(e.waiting, currency)) waiting") }
    return parts.joined(separator: " · ")
}

// MARK: - Parent: the Family tab

private struct QuestEdit: Identifiable {
    let id = UUID()
    let kidId: String
    let quest: FamilyQuest?
}

struct FamilyView: View {
    @EnvironmentObject private var store: GameStore
    @State private var editing: QuestEdit?
    @State private var adding = false
    @State private var draftName = ""

    var body: some View {
        let house = store.save.household
        let kids = house?.children ?? []
        let currency = house?.currency ?? Money.local

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Family").font(Typeface.display(40)).foregroundStyle(Ink.bone)
                Spacer()
                Text(kids.count == 1 ? "1 child" : "\(kids.count) children").caps(Ink.dim)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ScreenScroll {
                VStack(alignment: .leading, spacing: 14) {
                    if store.save.guardianHub?.cloud == nil {
                        Button(store.save.guardianHub == nil ? "Invite another guardian" : "Manage guardians") { store.inviteGuardian() }
                            .buttonStyle(PlateButtonStyle(block: true))
                    }
                    if store.save.guardianHub != nil {
                        Text("Guardians can manage quests and approve completions. Keep Spade open on the family owner's phone to relay updates between guardians and children.")
                            .font(Typeface.text()).foregroundStyle(Ink.dim)
                    }
                    if kids.isEmpty {
                        Text("Add your child, set them a few quests, then invite them. The quests show up on their Spade, at the XP you choose, with allowance if you like.")
                            .font(Typeface.italic())
                            .foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(kids) { kid in
                        KidCard(kid: kid, currency: currency) { quest in
                            editing = QuestEdit(kidId: kid.id, quest: quest)
                        }
                    }
                    if kids.count < 8 {
                        Button(kids.isEmpty ? "Add your child" : "Add another child") {
                            Feedback.tap()
                            adding = true
                        }
                        .buttonStyle(PlateButtonStyle(kind: kids.isEmpty ? .primary : .plain, block: true))
                    }
                    Text("After the invite, your changes reach each child's Spade through iCloud by themselves. Allowance is a record of what you owe: Spade never moves real money.")
                        .font(Typeface.italic(15))
                        .foregroundStyle(Ink.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(item: $editing) { edit in
            FamilyQuestSheet(kidId: edit.kidId, quest: edit.quest)
        }
        .alert("Add a child", isPresented: $adding) {
            TextField("Name", text: $draftName)
            Button("Add") {
                store.addChild(name: draftName)
                draftName = ""
            }
            Button("Cancel", role: .cancel) { draftName = "" }
        } message: {
            Text("Their name, as you'd like it to show on their Spade.")
        }
        .alert("iCloud", isPresented: Binding(get: { store.cloudNotice != nil }, set: { if !$0 { store.cloudNotice = nil } })) {
            Button("OK", role: .cancel) { store.cloudNotice = nil }
        } message: {
            Text(store.cloudNotice ?? "")
        }
        .onAppear {
            if DemoMode.requested == "familyquest", let kid = kids.first, let quest = kid.quests.last {
                editing = QuestEdit(kidId: kid.id, quest: quest)
            }
        }
    }
}

/// One child on the parent's Spade.
private struct KidCard: View {
    let kid: Kid
    let currency: String
    let edit: (FamilyQuest?) -> Void

    @EnvironmentObject private var store: GameStore
    @State private var renaming = false
    @State private var removing = false
    @State private var draft = ""
    @State private var showingAll = false

    var body: some View {
        let waiting = kid.claims.filter { $0.status == .waiting }
        let preparing = store.preparingInvite == kid.id
        let owed = kid.claims.total(.approved)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(kid.name)
                    .font(Typeface.display(34))
                    .foregroundStyle(Ink.bone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 6)
                if owed > 0 {
                    Text("You owe \(Money.format(owed, currency))").caps(Ink.lantern).lineLimit(1)
                }
                Menu {
                    Button("Rename") {
                        draft = kid.name
                        renaming = true
                    }
                    if kid.shared == true {
                        Button("Sharing options") { store.invite(kid.id) }
                    }
                    Button("Remove \(kid.name)", role: .destructive) { removing = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Ink.dim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for \(kid.name)")
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.top, 6)

            if !waiting.isEmpty {
                Hairline()
                part("To check")
                ForEach(waiting) { claim in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(claim.title).font(Typeface.text()).foregroundStyle(Ink.bone)
                            Spacer(minLength: 8)
                            if claim.allowance > 0 { Text(Money.format(claim.allowance, currency)).font(Typeface.label(22)).foregroundStyle(Ink.lantern) }
                        }
                        Text("Done \(when(claim.doneAt))").caps(Ink.faint)
                        if let xp = claim.xp { Text("Approve to award \(xp) XP").caps(Ink.verdigris) }
                        if claim.photo == true {
                            Label("\(kid.name) took a photo. Ask to see it", systemImage: "camera")
                                .font(Typeface.label())
                                .textCase(.uppercase)
                                .foregroundStyle(Ink.verdigris)
                        } else if (kid.quests + kid.past).first(where: { $0.id == claim.questId })?.askPhoto == true {
                            Label("No photo was taken", systemImage: "camera")
                                .font(Typeface.label())
                                .textCase(.uppercase)
                                .foregroundStyle(Ink.rust)
                        }
                        HStack(spacing: 8) {
                            Button("It's done") {
                                Feedback.done()
                                store.judge(kidId: kid.id, key: claim.key, approve: true)
                            }
                            .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                            Button("Not done") {
                                Feedback.tap()
                                store.judge(kidId: kid.id, key: claim.key, approve: false)
                            }
                            .buttonStyle(PlateButtonStyle(block: true))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .contain)
                }
            }

            if owed > 0 {
                Hairline()
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To pay \(kid.name)").font(Typeface.text()).foregroundStyle(Ink.bone)
                        Text("Approved, not paid yet").caps(Ink.faint)
                    }
                    Spacer(minLength: 8)
                    Button("Paid \(Money.format(owed, currency))") {
                        Feedback.done()
                        store.payAll(kidId: kid.id)
                    }
                    .buttonStyle(PlateButtonStyle(kind: .primary))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            ForEach((kid.requests ?? []).filter { $0.status == .waiting }) { request in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Schedule request: " + (kid.quests.first { $0.id == request.questId }?.title ?? "Quest"))
                        .font(Typeface.text()).foregroundStyle(Ink.bone)
                    Text(familyWeekdays[request.weekday] + (request.permanent ? " · permanently" : " · " + request.week)).caps(Ink.dim)
                    HStack {
                        Button("Approve") { store.judgeDay(kidId: kid.id, requestId: request.id, approve: true) }.buttonStyle(PlateButtonStyle())
                        Button("Decline") { store.judgeDay(kidId: kid.id, requestId: request.id, approve: false) }.buttonStyle(PlateButtonStyle())
                    }
                }.padding(14)
            }
            FamilyActivityList(entries: kid.activity ?? []).padding(14)
            Hairline()
            part("Quests")
            if kid.quests.isEmpty {
                Text("None yet.")
                    .font(Typeface.italic())
                    .foregroundStyle(Ink.dim)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            ForEach(kid.quests) { quest in
                Button {
                    Feedback.tap()
                    edit(quest)
                } label: {
                    HStack(spacing: 12) {
                        PropIcon(name: quest.category.rawValue, size: 22, res: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(quest.title).font(Typeface.text()).foregroundStyle(Ink.bone)
                            Text(quest.askPhoto == true ? "\(schedule(quest)) · photo" : schedule(quest)).caps(Ink.faint)
                            if let line = earningsLine(kid.claims.earnings(for: quest.id), allowance: quest.allowance, currency: currency) {
                                Text(line).caps(Ink.dim)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("+\(quest.xp)").font(Typeface.label(20)).foregroundStyle(Ink.verdigris)
                            if quest.allowance > 0 {
                                Text("\(Money.format(quest.allowance, currency)) each").caps(Ink.lantern)
                            }
                        }
                        Chevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityLabel("\(quest.title), \(schedule(quest)), \(quest.xp) XP\(quest.allowance > 0 ? ", " + Money.format(quest.allowance, currency) : ""). Edit")
            }
            Button {
                Feedback.tap()
                edit(nil)
            } label: {
                HStack(spacing: 12) {
                    Text("+").font(Typeface.label(26)).foregroundStyle(Ink.dim).frame(width: 22)
                    Text("New quest for \(kid.name)").font(Typeface.italic()).foregroundStyle(Ink.dim)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())

            if !kid.claims.isEmpty {
                let history = Array(kid.claims.reversed())
                Hairline()
                part("Most recent completions")
                ForEach(Array(history.sorted { $0.doneAt > $1.doneAt }.prefix(3).enumerated()), id: \.element.id) { index, claim in
                    if index > 0 { Hairline().padding(.horizontal, 14) }
                    HistoryRow(claim: claim, currency: currency, checker: "you")
                }

            }

            Hairline()
            VStack(alignment: .leading, spacing: 8) {
                if kid.joined == true {
                    Label("Connected", systemImage: "checkmark.icloud")
                        .font(Typeface.label())
                        .textCase(.uppercase)
                        .foregroundStyle(Ink.verdigris)
                    Text(kid.needsUpdate
                         ? "Your latest changes are on their way to \(kid.name)'s Spade."
                         : "\(kid.name)'s Spade keeps up with your changes by itself.")
                        .caps(kid.needsUpdate ? Ink.lantern : Ink.faint)
                } else if kid.shared == true {
                    Text("Waiting for \(kid.name) to open the invite on their iPhone.").caps(Ink.lantern)
                    Button(preparing ? "Opening…" : "Send the invite again") {
                        Feedback.tap()
                        store.invite(kid.id)
                    }
                    .buttonStyle(PlateButtonStyle(block: true))
                    .disabled(preparing)
                } else {
                    Button(preparing ? "Getting the invite ready…" : "Invite \(kid.name)") {
                        Feedback.tap()
                        store.invite(kid.id)
                    }
                    .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                    .disabled(preparing)
                    Text("\(kid.name) opens the invite once, on an iPhone signed in to their own iCloud. After that, their Spade keeps up by itself.")
                        .caps(Ink.faint)
                }
            }
            .padding(14)
        }
        .plate(fill: Ink.loam, edge: waiting.isEmpty ? Ink.moss : Ink.lantern, notch: 9)
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $draft)
            Button("Save") { store.renameChild(kid.id, to: draft) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Remove \(kid.name)?", isPresented: $removing) {
            Button("Remove", role: .destructive) { store.removeChild(kid.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their quests and allowance records go from this phone, and sharing with them stops. Their own Spade keeps what it has.")
        }
    }

    private func part(_ title: String) -> some View {
        Text(title)
            .caps(Ink.faint)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Parent: setting a quest

struct FamilyQuestSheet: View {
    let kidId: String
    let quest: FamilyQuest?

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var cadence: Cadence = .daily
    @State private var repeats = true
    @State private var weekday = -1
    @State private var kind: QuestKind = .home
    @State private var xp = 30
    @State private var pays = false
    @State private var askPhoto = false
    @State private var amount = ""
    @State private var removing = false
    @FocusState private var typingAmount: Bool

    private var currency: String { store.save.household?.currency ?? Money.local }
    private var kidName: String {
        store.save.household?.children.first { $0.id == kidId }?.name ?? "your child"
    }
    private var cents: Int? { Money.parse(amount, currency) }
    private var ready: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!pays || (cents ?? 0) > 0)
    }

    private let names: [Cadence: String] = [.daily: "Daily", .weekly: "Weekly", .monthly: "Monthly"]
    private let every: [Cadence: String] = [.daily: "day", .weekly: "week", .monthly: "month"]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: quest == nil ? "Quest for \(kidName)" : "Edit quest") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("What should they do?")
                    TextField("", text: $title, prompt: Text("Take out the bins").foregroundStyle(Ink.faint))
                        .font(Typeface.text(19))
                        .foregroundStyle(Ink.bone)
                        .tint(Ink.lantern)
                        .submitLabel(.done)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 50)
                        .plate(fill: Ink.ink, edge: Ink.moss2, notch: 6)
                        .onChange(of: title) { _, new in
                            if new.count > 80 { title = String(new.prefix(80)) }
                        }

                    SectionLabel("Which board?")
                    FlowLayout {
                        ForEach(Cadence.allCases, id: \.self) { option in
                            Chip(title: names[option] ?? option.rawValue, selected: option == cadence) {
                                Feedback.select()
                                cadence = option
                            }
                        }
                    }
                    RowGroup {
                        ToggleRow(
                            title: "Every \(every[cadence] ?? "day")",
                            note: repeats ? "Comes back each \(every[cadence] ?? "day")" : "Just once, until it's done",
                            isOn: $repeats
                        )
                    }
                    .padding(.top, 12)

                    if repeats {
                        SectionLabel("Repeat on a weekday (optional)")
                        Picker("Repeat day", selection: $weekday) {
                            Text("Use the board schedule").tag(-1)
                            ForEach(0..<7, id: \.self) { Text(familyWeekdays[$0]).tag($0) }
                        }.tint(Ink.lantern)
                        Text("Choosing a day makes this quest repeat once each week on that day.").font(Typeface.text()).foregroundStyle(Ink.dim)
                    }
                    SectionLabel("What kind?")
                    FlowLayout {
                        ForEach(QuestKind.allCases, id: \.self) { option in
                            Chip(title: option.rawValue, icon: option.rawValue, selected: option == kind) {
                                Feedback.select()
                                kind = option
                            }
                        }
                    }

                    SectionLabel("XP")
                    HStack(spacing: 10) {
                        stepper("minus", "Less XP") { xp = max(familyXpRange.lowerBound, xp - step(down: true)) }
                        Text("\(xp)")
                            .font(Typeface.label(34))
                            .foregroundStyle(Ink.verdigris)
                            .frame(minWidth: 90)
                            .accessibilityLabel("\(xp) XP")
                        stepper("plus", "More XP") { xp = min(familyXpRange.upperBound, xp + step(down: false)) }
                        Spacer()
                    }
                    FlowLayout {
                        ForEach([20, 50, 100, 250], id: \.self) { value in
                            Chip(title: "\(value)", selected: xp == value) {
                                Feedback.select()
                                xp = value
                            }
                        }
                    }
                    .padding(.top, 10)
                    Text("Spade's own \(names[cadence]?.lowercased() ?? "") quests are worth \(questXp(cadence, 1)) to \(questXp(cadence, 3)) XP.")
                        .font(Typeface.italic(15))
                        .foregroundStyle(Ink.dim)
                        .padding(.top, 9)

                    SectionLabel("Proof")
                    RowGroup {
                        ToggleRow(
                            title: "Ask for a photo",
                            note: askPhoto ? "They take one before it counts" : "No photo needed",
                            isOn: $askPhoto
                        )
                    }

                    SectionLabel("Allowance")
                    RowGroup {
                        ToggleRow(
                            title: "Pays allowance",
                            note: pays ? "You check it before it counts" : "XP only",
                            isOn: $pays
                        )
                    }
                    if pays {
                        HStack(spacing: 6) {
                            Text(Money.symbol(currency)).font(Typeface.label(26)).foregroundStyle(Ink.lantern)
                            TextField("", text: $amount, prompt: Text(Money.plain(Money.scale(currency), currency)).foregroundStyle(Ink.faint))
                                .font(Typeface.label(26))
                                .foregroundStyle(Ink.bone)
                                .tint(Ink.lantern)
                                .keyboardType(.decimalPad)
                                .focused($typingAmount)
                                .accessibilityLabel("Amount each time")
                        }
                        .padding(.horizontal, 13)
                        .frame(minHeight: 50)
                        .plate(fill: Ink.ink, edge: pays && cents == nil && !amount.isEmpty ? Ink.rust : Ink.moss2, notch: 6)
                        .padding(.top, 10)
                        Text("Each time \(kidName) does it. Spade keeps a record; you pay in real life.")
                            .font(Typeface.italic(15))
                            .foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }

                    if quest != nil {
                        Button("Remove this quest") {
                            Feedback.tap()
                            removing = true
                        }
                        .buttonStyle(PlateButtonStyle(kind: .danger, block: true))
                        .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Button(quest == nil ? "Add quest" : "Save changes") {
                store.saveChildQuest(
                    kidId: kidId,
                    questId: quest?.id,
                    FamilyQuestInput(
                        title: title, cadence: cadence, category: kind, xp: xp,
                        allowance: pays ? (cents ?? 0) : 0, repeats: repeats, askPhoto: askPhoto, weekday: weekday >= 0 ? weekday : nil
                    )
                )
                Feedback.done()
                dismiss()
            }
            .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
            .disabled(!ready)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .spadeSheet()
        .onAppear(perform: load)
        .onChange(of: cadence) { _, new in
            // A fresh quest suggests XP to match its board.
            if quest == nil { xp = questXp(new, 2) }
        }
        .alert("Remove this quest?", isPresented: $removing) {
            Button("Remove", role: .destructive) {
                if let quest { store.removeChildQuest(kidId: kidId, questId: quest.id) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It leaves \(kidName)'s board. Anything already done stays done.")
        }
    }

    private func load() {
        guard let quest else {
            xp = questXp(cadence, 2)
            return
        }
        title = quest.title
        cadence = quest.cadence
        repeats = quest.repeats
        weekday = quest.weekday ?? -1
        kind = quest.category
        xp = quest.xp
        pays = quest.allowance > 0
        askPhoto = quest.askPhoto == true
        amount = quest.allowance > 0 ? Money.plain(quest.allowance, currency) : ""
    }

    private func step(down: Bool) -> Int {
        let threshold = down ? 100 : 99
        return xp > threshold ? 25 : 5
    }

    private func stepper(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button {
            Feedback.select()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Ink.bone)
                .frame(width: 50, height: 50)
                .plate(fill: Ink.loam2, edge: Ink.moss2, notch: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Child: allowance

/// The row at the top of a child's quest board.
struct FamilyBanner: View {
    @EnvironmentObject private var store: GameStore
    @State private var open = false

    var body: some View {
        let save = store.save
        Group {
            if save.role == .child, let family = save.family {
                let claims = family.claims
                let paysAllowance = family.quests.contains { $0.allowance > 0 } || claims.contains { $0.allowance > 0 }
                if !family.quests.isEmpty || !claims.isEmpty {
                    let unsent = unsentClaims(save).count
                    let waiting = claims.filter { $0.status == .waiting }.count
                    let summary = family.cloud == nil ? "Ask \(family.parentName) for a new invite"
                        : unsent > 0 ? "\(unsent) on the way to \(family.parentName)"
                        : waiting > 0 ? "\(waiting) waiting for \(family.parentName)"
                        : "From \(family.parentName)"
                    Button {
                        Feedback.tap()
                        open = true
                    } label: {
                        HStack(spacing: 12) {
                            PropIcon(name: "home", size: 30, res: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(paysAllowance ? "Allowance" : "Family quests").font(Typeface.text()).foregroundStyle(Ink.bone)
                                Text(summary).caps(unsent > 0 || family.cloud == nil ? Ink.lantern : Ink.faint)
                            }
                            Spacer(minLength: 8)
                            if paysAllowance {
                                Text(Money.format(claims.total(.approved), family.currency))
                                    .font(Typeface.label(24))
                                    .foregroundStyle(Ink.lantern)
                                    .accessibilityLabel("\(Money.format(claims.total(.approved), family.currency)) owed to you")
                            }
                            Chevron()
                        }
                        .padding(.horizontal, 20)
                        .frame(minHeight: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { Hairline().padding(.horizontal, 20) }
                }
            } else if save.role == .child {
                HStack(alignment: .top, spacing: 12) {
                    PropIcon(name: "home", size: 30, res: 20)
                    Text("Ask your parent to invite you from the Family tab of their Spade. Tap the invite they send, and their quests show up here.")
                        .font(Typeface.italic(16))
                        .foregroundStyle(Ink.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Hairline().padding(.horizontal, 20) }
            }
        }
        .sheet(isPresented: $open) { AllowanceSheet() }
        .onAppear {
            if DemoMode.requested == "allowance" { open = true }
        }
    }
}

struct AllowanceSheet: View {
    @State private var rescheduling: FamilyQuest?
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let family = store.save.family
        let claims = family?.claims ?? []
        let currency = family?.currency ?? Money.local
        let parent = family?.parentName ?? "your parent"
        let unsent = unsentClaims(store.save).count
        let quests = family?.quests ?? []
        let paysAllowance = quests.contains { $0.allowance > 0 } || claims.contains { $0.allowance > 0 }
        let connected = family?.cloud != nil
        let onTheWay = unsent == 1 ? "1 quest is" : "\(unsent) quests are"
        let syncLine: String = !connected ? "Not connected to \(parent)'s Spade. Ask them for a new invite."
            : unsent > 0 ? "\(onTheWay) on the way to \(parent)'s Spade."
            : "\(parent)'s Spade sees these by itself."

        VStack(spacing: 0) {
            SheetHeader(title: paysAllowance ? "Allowance" : "Family quests") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if paysAllowance {
                        HStack(spacing: 6) {
                            stat("Waiting", claims.total(.waiting), currency, Ink.bone)
                            stat("Owed to you", claims.total(.approved), currency, Ink.lantern)
                            stat("Paid so far", claims.total(.paid), currency, Ink.verdigris)
                        }
                        .padding(.vertical, 10)
                        Hairline()
                        Text("\(parent) checks each allowance quest on their Spade. Once it's approved, it counts as owed.")
                            .font(Typeface.italic(16))
                            .foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }

                    ForEach(quests.filter { $0.repeats && $0.weekday != nil }) { quest in
                        Button("Request another day: " + quest.title) { rescheduling = quest }
                            .buttonStyle(RowButtonStyle())
                            .disabled((family?.requests ?? []).contains { $0.questId == quest.id && $0.status == .waiting })
                    }
                    ForEach(family?.requests ?? []) { request in
                        Text("Schedule request · " + familyWeekdays[request.weekday] + " · " + request.status.rawValue).caps(Ink.dim)
                    }
                    FamilyActivityList(entries: family?.activity ?? [])
                    if !quests.isEmpty {
                        SectionLabel("By quest")
                        RowGroup {
                            ForEach(Array(quests.enumerated()), id: \.element.id) { index, quest in
                                if index > 0 { Hairline() }
                                let earned = claims.earnings(for: quest.id)
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(quest.title).font(Typeface.text()).foregroundStyle(Ink.bone)
                                        Text(quest.allowance > 0
                                             ? "\(Money.format(quest.allowance, currency)) each · +\(quest.xp) XP"
                                             : "+\(quest.xp) XP each · no allowance")
                                            .caps(Ink.faint)
                                        Text(earningsLine(earned, allowance: quest.allowance, currency: currency) ?? "Not done yet")
                                            .caps(Ink.dim)
                                    }
                                    Spacer(minLength: 8)
                                    if quest.allowance > 0 && earned.times > 0 {
                                        Text(Money.format(earned.earned, currency))
                                            .font(Typeface.label(22))
                                            .foregroundStyle(Ink.lantern)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }

                    Text("Family XP is earned after a guardian approves your completion.").font(Typeface.text()).foregroundStyle(Ink.dim).padding(.top, 12)
                    SectionLabel("Most recent completions")
                    if claims.isEmpty {
                        Text("Finish one of \(parent)'s quests and it shows up here, with when you did it.")
                            .font(Typeface.italic())
                            .foregroundStyle(Ink.dim)
                    } else {
                        RowGroup {
                            ForEach(Array(claims.sorted { $0.doneAt > $1.doneAt }.prefix(3).enumerated()), id: \.element.id) { index, claim in
                                if index > 0 { Hairline() }
                                HistoryRow(
                                    claim: claim, currency: currency, checker: parent,
                                    thumbnail: claim.photo == true ? ProofPhotos.image(for: claim.key) : nil
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            if family != nil {
                VStack(spacing: 8) {
                    let photos = store.photosForParent().count
                    if photos > 0 {
                        // Photos stay on this iPhone, so for now they are sent by hand.
                        Button(photos == 1 ? "Send the photo to \(parent)" : "Send \(photos) photos to \(parent)") {
                            Feedback.tap()
                            store.sharePhotosWithParent()
                        }
                        .buttonStyle(PlateButtonStyle(block: true))
                    }
                    Text(syncLine)
                        .caps(unsent > 0 || !connected ? Ink.lantern : Ink.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .spadeSheet()
        .sheet(item: $rescheduling) { ScheduleRequestSheet(quest: $0) }
    }

    private func stat(_ name: String, _ amount: Int, _ currency: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Money.format(amount, currency)).font(Typeface.label(26)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(name).caps(Ink.faint, size: 14).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Child: an invite arrives

/// Opens when a parent's invite is tapped: asks whether to join, then says how it went.
struct IncomingSheet: View {
    let arrival: GameStore.Incoming

    @EnvironmentObject private var store: GameStore

    var body: some View {
        // The sheet is handed the invite once; the store has its newest state.
        let step = store.incoming?.id == arrival.id ? (store.incoming?.step ?? arrival.step) : arrival.step
        let content = describe(step)
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: content.title) { store.closeIncoming() }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(content.lines, id: \.self) { line in
                        Text(line)
                            .font(Typeface.text(18))
                            .foregroundStyle(Ink.bone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if step == .joining {
                        ProgressView().tint(Ink.lantern).frame(maxWidth: .infinity).padding(.top, 8)
                    }
                    if !content.quests.isEmpty {
                        RowGroup {
                            ForEach(Array(content.quests.enumerated()), id: \.element.id) { index, quest in
                                if index > 0 { Hairline() }
                                HStack(spacing: 10) {
                                    PropIcon(name: quest.category.rawValue, size: 22, res: 18)
                                    Text(quest.title).font(Typeface.text()).foregroundStyle(Ink.bone)
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text("+\(quest.xp)").font(Typeface.label(20)).foregroundStyle(Ink.verdigris)
                                        if quest.allowance > 0, let currency = content.currency {
                                            Text(Money.format(quest.allowance, currency)).caps(Ink.lantern)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }
                    }
                    if let note = content.note {
                        Text(note)
                            .font(Typeface.italic(16))
                            .foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
            HStack(spacing: 10) {
                switch content.action {
                case .join:
                    Button("Not now") {
                        Feedback.tap()
                        store.closeIncoming()
                    }
                    .buttonStyle(PlateButtonStyle(block: true))
                    Button("Join") {
                        Feedback.done()
                        store.acceptIncoming()
                    }
                    .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                case .retry:
                    Button("Close") {
                        Feedback.tap()
                        store.closeIncoming()
                    }
                    .buttonStyle(PlateButtonStyle(block: true))
                    Button("Try again") {
                        Feedback.tap()
                        store.acceptIncoming()
                    }
                    .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                case .wait:
                    EmptyView()
                case .done:
                    Button("OK") {
                        Feedback.tap()
                        store.closeIncoming()
                    }
                    .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .spadeSheet([.medium, .large])
    }

    private enum Action { case join, retry, wait, done }

    private struct Content {
        var title: String
        var lines: [String] = []
        var quests: [FamilyQuest] = []
        var currency: String?
        var note: String?
        var action: Action = .done
    }

    private func plural(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? "1 \(one)" : "\(n) \(many)"
    }

    private func describe(_ step: GameStore.Incoming.Step) -> Content {
        let from = arrival.from
        switch step {
        case .asking:
            var content = Content(title: "Join a family?", action: .join)
            content.lines = ["\(from) wants to send you quests in Spade."]
            if let old = store.save.family, old.parentName != from {
                content.note = "This takes you out of \(old.parentName)'s family. Everything you've earned stays."
            } else {
                content.note = "Their quests go on your board, and they can see when you finish them. Everything you've earned stays yours."
            }
            return content
        case .joining:
            return Content(title: "Joining…", lines: ["Fetching your quests from iCloud."], action: .wait)
        case .joined(let summary, let quests, let currency):
            var content = Content(title: summary.joined ? "You're in" : "From \(from)", quests: quests, currency: currency)
            if summary.joined { content.lines.append("You're in \(from)'s family now.") }
            if summary.newQuests > 0 { content.lines.append("\(plural(summary.newQuests, "new quest", "new quests")) on your board.") }
            if content.lines.isEmpty { content.lines = ["Everything is up to date."] }
            content.note = "From now on, new quests from \(from) show up by themselves."
            return content
        case .already:
            return Content(title: "Already in", lines: ["You're already in \(from)'s family, and everything is up to date."])
        case .failed(let why):
            return Content(title: "Couldn't join", lines: ["Spade couldn't fetch the quests from iCloud."], note: why, action: .retry)
        case .notForYou(let why):
            return Content(title: "Not for this Spade", lines: [why])
        }
    }
}

private struct FamilyActivityList: View {
    let entries: [FamilyActivity]
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Family changelog")
            if entries.isEmpty { Text("Changes will appear here.").font(Typeface.italic()).foregroundStyle(Ink.dim) }
            ForEach(Array(entries.sorted { $0.at > $1.at }.prefix(expanded ? entries.count : 8))) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.text).font(Typeface.text()).foregroundStyle(Ink.bone)
                    Text("\(entry.actor) · \(when(entry.at))").caps(Ink.faint)
                }.padding(.vertical, 4)
            }
            if entries.count > 8 { Button(expanded ? "Show fewer changes" : "Show all \(entries.count) changes") { expanded.toggle() }.buttonStyle(PlateButtonStyle()) }
        }
    }
}

private struct ScheduleRequestSheet: View {
    let quest: FamilyQuest
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var weekday = 0
    @State private var permanent = false
    var body: some View {
        VStack(spacing: 16) {
            SheetHeader(title: "Request another day") { dismiss() }
            Text(quest.title).font(Typeface.display(26)).foregroundStyle(Ink.bone)
            Picker("Day", selection: $weekday) {
                ForEach(0..<7, id: \.self) { Text(familyWeekdays[$0]).tag($0) }
            }.pickerStyle(.wheel)
            Picker("Change for", selection: $permanent) {
                Text("Once (this week)").tag(false)
                Text("Permanently").tag(true)
            }.pickerStyle(.segmented)
            Text("Your guardian must approve the change. A one-time change keeps the regular schedule for following weeks. A day that has already passed cannot be approved for this week.")
                .font(Typeface.text()).foregroundStyle(Ink.dim)
            Button("Send request") {
                store.requestDay(questId: quest.id, weekday: weekday, permanent: permanent)
                dismiss()
            }.buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                .disabled(!permanent && weekday < GameClock.device.weekdayIndex(Date()))
            Spacer()
        }.padding(.horizontal, 20).spadeSheet().onAppear { weekday = quest.weekday ?? 0 }
    }
}
