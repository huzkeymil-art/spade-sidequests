import SwiftUI
import UIKit

// Families, on screen.
//
//   Parent: the Family tab. One card per child, with what's waiting to be
//   checked, what's owed, their quests, and a button to send them an update.
//   Child: an allowance row at the top of the quest board, and a sheet with
//   what's waiting, owed and paid, plus a button to tell the parent.
//   Both: the sheet that opens when a family link arrives.

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

private func when(_ millis: Double) -> String {
    Date(timeIntervalSince1970: millis / 1000).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}

private func schedule(_ quest: FamilyQuest) -> String {
    let every: [Cadence: String] = [.daily: "Every day", .weekly: "Every week", .monthly: "Every month"]
    let once: [Cadence: String] = [.daily: "Once, on the daily board", .weekly: "Once, on the weekly board", .monthly: "Once, on the monthly board"]
    return (quest.repeats ? every : once)[quest.cadence] ?? ""
}

/// How a finished allowance quest is getting on, in a child's words.
func claimWords(_ status: ClaimStatus, parent: String) -> (text: String, color: Color) {
    switch status {
    case .waiting: return ("Waiting for \(parent)", Ink.faint)
    case .approved: return ("Approved", Ink.verdigris)
    case .declined: return ("Not approved", Ink.rust)
    case .paid: return ("Paid", Ink.lantern)
    }
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
                    if kids.isEmpty {
                        Text("Add your child, set them a few quests, then send them a link. The quests show up on their Spade, at the XP you choose, with allowance if you like.")
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
                    Text("Each child's Spade only changes when you send them an update. Allowance is a record of what you owe: Spade never moves real money.")
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
    @State private var copied = false

    var body: some View {
        let waiting = kid.claims.filter { $0.status == .waiting }
        let owed = kid.claims.total(.approved)
        let parent = store.save.hero.name

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
                            Text(Money.format(claim.allowance, currency)).font(Typeface.label(22)).foregroundStyle(Ink.lantern)
                        }
                        Text("Done \(when(claim.doneAt))").caps(Ink.faint)
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
                            Text(schedule(quest)).caps(Ink.faint)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("+\(quest.xp)").font(Typeface.label(20)).foregroundStyle(Ink.verdigris)
                            if quest.allowance > 0 {
                                Text(Money.format(quest.allowance, currency)).caps(Ink.lantern)
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

            Hairline()
            VStack(alignment: .leading, spacing: 8) {
                if let message = store.messageForChild(kid.id) {
                    // Shared as a message, not a bare link: some apps turn links into previews and
                    // lose the code after the "#", but the message repeats the code as plain text.
                    ShareLink(item: message, subject: Text("Quests from \(parent)")) {
                        Text(kid.needsUpdate ? "Send update to \(kid.name)" : "Send to \(kid.name) again")
                    }
                    .buttonStyle(PlateButtonStyle(kind: kid.needsUpdate ? .primary : .plain, block: true))
                    .simultaneousGesture(TapGesture().onEnded { store.sentToChild(kid.id) })
                    Button(copied ? "Copied" : "Copy link") {
                        UIPasteboard.general.string = message
                        store.sentToChild(kid.id)
                        Feedback.done()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }
                    .buttonStyle(PlateButtonStyle(block: true))
                    .accessibilityHint("Copies the link and family code, to paste into any app")
                }
                Text(kid.needsUpdate ? "\(kid.name)'s Spade doesn't have your latest changes yet." : "\(kid.name)'s Spade is up to date.")
                    .caps(kid.needsUpdate ? Ink.lantern : Ink.faint)
            }
            .padding(14)
        }
        .plate(fill: Ink.loam, edge: kid.needsUpdate || !waiting.isEmpty ? Ink.lantern : Ink.moss, notch: 9)
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $draft)
            Button("Save") { store.renameChild(kid.id, to: draft) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Remove \(kid.name)?", isPresented: $removing) {
            Button("Remove", role: .destructive) { store.removeChild(kid.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their quests and allowance records go from this phone. Their own Spade keeps what it has.")
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
    @State private var kind: QuestKind = .home
    @State private var xp = 30
    @State private var pays = false
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
                    FamilyQuestInput(title: title, cadence: cadence, category: kind, xp: xp, allowance: pays ? (cents ?? 0) : 0, repeats: repeats)
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
            Text("It leaves \(kidName)'s board the next time you send an update. Anything already done stays done.")
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
        kind = quest.category
        xp = quest.xp
        pays = quest.allowance > 0
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
                if family.quests.contains(where: { $0.allowance > 0 }) || !claims.isEmpty {
                    let unsent = unsentClaims(save).count
                    let waiting = claims.filter { $0.status == .waiting }.count
                    let summary = unsent > 0 ? "\(unsent) to send to \(family.parentName)"
                        : waiting > 0 ? "\(waiting) waiting for \(family.parentName)"
                        : "From \(family.parentName)"
                    Button {
                        Feedback.tap()
                        open = true
                    } label: {
                        HStack(spacing: 12) {
                            PropIcon(name: "home", size: 30, res: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Allowance").font(Typeface.text()).foregroundStyle(Ink.bone)
                                Text(summary).caps(unsent > 0 ? Ink.lantern : Ink.faint)
                            }
                            Spacer(minLength: 8)
                            Text(Money.format(claims.total(.approved), family.currency))
                                .font(Typeface.label(24))
                                .foregroundStyle(Ink.lantern)
                                .accessibilityLabel("\(Money.format(claims.total(.approved), family.currency)) owed to you")
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
                    Text("Ask your parent to send you a link from their Spade. Their quests will show up here.")
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
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let family = store.save.family
        let claims = family?.claims ?? []
        let currency = family?.currency ?? Money.local
        let parent = family?.parentName ?? "your parent"
        let unsent = unsentClaims(store.save).count

        VStack(spacing: 0) {
            SheetHeader(title: "Allowance") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        stat("Waiting", claims.total(.waiting), currency, Ink.bone)
                        stat("Owed to you", claims.total(.approved), currency, Ink.lantern)
                        stat("Paid so far", claims.total(.paid), currency, Ink.verdigris)
                    }
                    .padding(.vertical, 10)
                    Hairline()
                    Text("\(parent) checks each quest on their Spade. Once it's approved, it counts as owed.")
                        .font(Typeface.italic(16))
                        .foregroundStyle(Ink.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    SectionLabel("Done")
                    if claims.isEmpty {
                        Text("Finish a quest with allowance and it shows up here.")
                            .font(Typeface.italic())
                            .foregroundStyle(Ink.dim)
                    } else {
                        RowGroup {
                            ForEach(Array(claims.reversed().enumerated()), id: \.element.id) { index, claim in
                                if index > 0 { Hairline() }
                                let words = claimWords(claim.status, parent: parent)
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(claim.title).font(Typeface.text()).foregroundStyle(Ink.bone)
                                        Text("\(when(claim.doneAt)) · \(words.text)").caps(words.color)
                                    }
                                    Spacer(minLength: 8)
                                    Text(Money.format(claim.allowance, currency))
                                        .font(Typeface.label(22))
                                        .foregroundStyle(claim.status == .declined ? Ink.faint : Ink.lantern)
                                        .strikethrough(claim.status == .declined)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            if let message = store.messageForParent() {
                VStack(spacing: 8) {
                    ShareLink(item: message, subject: Text("Quests done")) {
                        Text(unsent > 0 ? "Send \(unsent) to \(parent)" : "Send to \(parent) again")
                    }
                    .buttonStyle(PlateButtonStyle(kind: unsent > 0 ? .primary : .plain, block: true))
                    .simultaneousGesture(TapGesture().onEnded { store.sentToParent() })
                    Button(copied ? "Copied" : "Copy link") {
                        UIPasteboard.general.string = message
                        store.sentToParent()
                        Feedback.done()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }
                    .buttonStyle(PlateButtonStyle(block: true))
                    .accessibilityHint("Copies the link and family code, to paste into any app")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .spadeSheet()
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

// MARK: - Both: a link arrives

struct IncomingSheet: View {
    let arrival: GameStore.Incoming
    /// Opens the Family tab, for a parent with quests to check.
    let review: () -> Void

    @EnvironmentObject private var store: GameStore

    var body: some View {
        let content = describe()
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
                case .review:
                    Button("Check them") {
                        Feedback.tap()
                        store.closeIncoming()
                        review()
                    }
                    .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
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

    private enum Action { case join, review, done }

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

    private func describe() -> Content {
        switch arrival.link {
        case .fromParent(let note):
            switch arrival.outcome {
            case nil:
                var content = Content(title: "Join a family?", quests: note.quests, currency: note.currency, action: .join)
                content.lines = ["\(note.parentName) wants to send you quests in Spade."]
                if let old = store.save.family, old.familyId != note.familyId {
                    content.note = "This takes you out of \(old.parentName)'s family. Everything you've earned stays."
                } else {
                    content.note = "Their quests go on your board. Everything you've earned stays yours."
                }
                return content
            case .fromParent(.applied(let summary))?:
                var content = Content(title: summary.joined ? "You're in" : "From \(note.parentName)")
                if summary.joined {
                    content.lines.append("You're in \(note.parentName)'s family now.")
                }
                if summary.newQuests > 0 { content.lines.append("\(plural(summary.newQuests, "new quest", "new quests")) on your board.") }
                if summary.removedQuests > 0 { content.lines.append("\(plural(summary.removedQuests, "quest", "quests")) taken off.") }
                if summary.approved > 0 { content.lines.append("\(plural(summary.approved, "quest", "quests")) approved. That allowance is owed to you.") }
                if summary.paid > 0 { content.lines.append("\(plural(summary.paid, "quest", "quests")) paid.") }
                if summary.declined > 0 { content.lines.append("\(plural(summary.declined, "quest wasn't", "quests weren't")) approved.") }
                if content.lines.isEmpty { content.lines = ["Everything is up to date."] }
                return content
            case .fromParent(.stale)?:
                return Content(title: "Up to date", lines: ["You've already opened this link, or a newer one from \(note.parentName)."])
            case .fromParent(.isParent)?, .wrongRole?:
                return Content(title: "Not for you", lines: ["This link is for a child's Spade. Send it to your child instead."])
            case .fromChild?:
                return Content(title: "Not for you", lines: ["Something went wrong reading this link."])
            }
        case .fromChild(let note):
            switch arrival.outcome {
            case .fromChild(.added(_, let count))?:
                return Content(
                    title: "From \(note.childName)",
                    lines: ["\(note.childName) finished \(plural(count, "allowance quest", "allowance quests")). Check them in Family, then send \(note.childName) an update."],
                    action: .review
                )
            case .fromChild(.nothingNew)?:
                return Content(title: "From \(note.childName)", lines: ["Nothing new. You've already seen these."])
            case .fromChild(.wrongFamily)?:
                return Content(title: "Not your family", lines: ["This link is from a child in a different family."])
            case .fromChild(.unknownChild)?:
                return Content(title: "Who's this?", lines: ["\(note.childName) isn't in your family list on this phone."])
            default:
                return Content(title: "Not for you", lines: ["This link is for a parent's Spade. Send it to your parent instead."])
            }
        }
    }
}
