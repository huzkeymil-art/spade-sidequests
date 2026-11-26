import SwiftUI

private let cadenceName: [Cadence: String] = [.daily: "Daily", .weekly: "Weekly", .monthly: "Monthly"]
private let nextDeal: [Cadence: String] = [.daily: "tomorrow", .weekly: "on Monday", .monthly: "on the 1st"]

/// The quest board: today's, this week's and this month's quests.
struct QuestBoardView: View {
    @EnvironmentObject private var store: GameStore
    @State private var cadence: Cadence = .daily
    @State private var writing = false

    var body: some View {
        let save = store.save
        let board = save.boards[cadence]
        let spade = save.settings.spadeQuests
        let swaps = spade ? rerollsLeft(save) : 0
        let dailies = save.boards.daily.quests
        let countdown = formatCountdown(store.clock.nextReset(cadence, store.now).timeIntervalSince(store.now))

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    ForEach(Cadence.allCases, id: \.self) { option in
                        cadenceTab(option, open: save.boards[option].quests.filter { !$0.done }.count)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                HStack {
                    Text("New in \(countdown)").caps(Ink.faint)
                    Spacer()
                    if cadence == .daily && spade {
                        Text(swaps > 0 ? "\(swaps) swap left" : "No swaps left").caps(Ink.faint)
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 9)
                Hairline()
            }
            .padding(.horizontal, 20)

            ScreenScroll {
                VStack(spacing: 0) {
                    FamilyBanner()
                    ForEach(board.quests) { quest in
                        QuestRow(quest: quest, canSwap: cadence == .daily && swaps > 0 && !quest.pinned)
                    }

                    if cadence == .daily {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(save.boards.daily.cleared ? "Lantern full" : "Fill the lantern")
                                    .font(Typeface.text())
                                    .foregroundStyle(Ink.bone)
                                Text("All of today's quests: +\(dailyClearXp) XP").caps(Ink.faint)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(dailies) { quest in
                                    if quest.done {
                                        Ink.lantern.frame(width: 9, height: 9)
                                    } else {
                                        Dots(color: Ink.moss2, density: 2).frame(width: 9, height: 9)
                                    }
                                }
                            }
                            .accessibilityElement()
                            .accessibilityLabel("\(dailies.filter { $0.done }.count) of \(dailies.count) done")
                        }
                        .padding(.vertical, 13)
                        .padding(.horizontal, 20)
                        Hairline().padding(.horizontal, 20)
                    }

                    if board.quests.isEmpty {
                        Text(spade
                             ? "Nothing on this board yet."
                             : "Spade's quests are off, so this board holds only the quests you write. Write one below, or switch Spade's quests back on in Settings.")
                            .font(Typeface.italic())
                            .foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }

                    if !board.quests.isEmpty && board.quests.allSatisfy({ $0.done }) {
                        Text("All sealed. Fresh quests arrive \(nextDeal[cadence] ?? "soon").")
                            .font(Typeface.italic())
                            .foregroundStyle(Ink.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }

                    Button {
                        Feedback.tap()
                        writing = true
                    } label: {
                        HStack(spacing: 13) {
                            Text("+")
                                .font(Typeface.label(30))
                                .foregroundStyle(Ink.dim)
                                .frame(width: 44, height: 44)
                                .plate(fill: Ink.loam, edge: Ink.moss, notch: 5)
                            Text("Write a quest of your own").font(Typeface.italic()).foregroundStyle(Ink.dim)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(minHeight: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $writing) {
            QuestFormSheet(startCadence: cadence)
        }
        .onAppear {
            if DemoMode.requested == "form" { writing = true }
        }
    }

    private func cadenceTab(_ option: Cadence, open: Int) -> some View {
        let selected = option == cadence
        return Button {
            Feedback.select()
            cadence = option
        } label: {
            HStack(alignment: .top, spacing: 4) {
                Text(cadenceName[option] ?? "")
                    .font(Typeface.display(selected ? 40 : 30))
                    .foregroundStyle(selected ? Ink.bone : Ink.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if open > 0 {
                    Text("\(open)").font(Typeface.label(15)).foregroundStyle(Ink.lantern)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cadenceName[option] ?? ""), \(open) to do")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One quest. Pressing and holding fills the square socket; when it is full the
/// quest is marked. A quick tap just shows a reminder to hold, and dragging
/// (to scroll) cancels, so quests are never completed by accident.
struct QuestRow: View {
    let quest: ActiveQuest
    let canSwap: Bool

    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var stage: StageController
    @State private var pressing = false
    @State private var hint = false
    @State private var gain: Int?
    @State private var floated = false
    @State private var askingPhoto = false

    private let holdSeconds = 0.65
    private var counted: Bool { quest.target > 1 }
    /// A parent's quest that wants a photo before it counts.
    private var needsPhoto: Bool { quest.family?.askPhoto == true && !quest.done }
    /// For a parent's allowance quest that is done: what the parent decided.
    private var claimStatus: ClaimStatus? {
        store.save.family?.claims.first { $0.key == quest.key }?.status
    }
    private var lastStep: Bool { quest.progress + 1 >= quest.target }

    var body: some View {
        HStack(spacing: 13) {
            socket

            VStack(alignment: .leading, spacing: 5) {
                Text(quest.title)
                    .font(Typeface.text(18))
                    .strikethrough(quest.done, color: Ink.faint)
                    .foregroundStyle(quest.done ? Ink.faint : Ink.bone)
                    .fixedSize(horizontal: false, vertical: true)
                if hint {
                    Text(needsPhoto ? "Press and hold, then add a photo" : "Press and hold to \(counted && !lastStep ? "count it" : "seal it")")
                        .caps(Ink.lantern)
                } else if let tag = quest.family {
                    HStack(spacing: 6) {
                        PropIcon(name: "home", size: 18, res: 18)
                        if quest.done, let status = claimStatus {
                            let words = claimWords(status, parent: tag.parent)
                            Text(words.text).caps(words.color)
                        } else {
                            Text(tag.askPhoto == true && !quest.done ? "from \(tag.parent) · photo" : "from \(tag.parent)").caps(Ink.faint)
                        }
                        if tag.askPhoto == true && !quest.done {
                            Image(systemName: "camera")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Ink.faint)
                                .accessibilityHidden(true)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        PropIcon(name: quest.category.rawValue, size: 18, res: 18)
                        Text(quest.custom ? "\(quest.category.rawValue) · yours" : quest.category.rawValue).caps(Ink.faint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text("+\(quest.xp)")
                    .font(Typeface.label(22))
                    .foregroundStyle(quest.done ? Ink.faint : Ink.verdigris)
                if let tag = quest.family, tag.allowance > 0 {
                    Text(Money.format(tag.allowance, store.save.family?.currency ?? Money.local))
                        .caps(quest.done ? Ink.faint : Ink.lantern)
                }
                if canSwap && !quest.done {
                    Button {
                        Feedback.tap()
                        store.reroll(key: quest.key)
                    } label: {
                        Text("Swap").caps(Ink.dim).frame(minWidth: 52, minHeight: 44, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Swap \(quest.title) for a different quest")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .background(pressing ? Ink.loam : Color.clear)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Hairline().padding(.horizontal, 20) }
        .overlay(alignment: .topTrailing) {
            if let gain {
                Text("+\(gain)")
                    .font(Typeface.label(30))
                    .foregroundStyle(Ink.lantern)
                    .padding(.trailing, 20)
                    .offset(y: floated ? -6 : 18)
                    .opacity(floated ? 0 : 1)
                    .allowsHitTesting(false)
            }
        }
        // The empty tap comes first so the long press doesn't swallow scrolling.
        .onTapGesture { showHint() }
        .onLongPressGesture(minimumDuration: holdSeconds, maximumDistance: 14) {
            seal()
        } onPressingChanged: { down in
            pressing = down && !quest.done
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quest.title)
        .accessibilityValue(accessibleValue)
        .accessibilityHint(quest.done ? "" : needsPhoto ? "Double tap and hold, then add a photo" : "Double tap and hold to \(lastStep ? "seal" : "count")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { seal() }
        .sheet(isPresented: $askingPhoto) {
            PhotoProofSheet(title: quest.title, parent: quest.family?.parent ?? "your parent") { image in
                celebrate(store.sealWithPhoto(quest.cadence, key: quest.key, image: image))
            }
        }
        .onAppear {
            if DemoMode.requested == "photoproof" && needsPhoto { askingPhoto = true }
        }
    }

    private var accessibleValue: String {
        var parts: [String] = []
        if let tag = quest.family {
            parts.append("from \(tag.parent)")
            if tag.allowance > 0 {
                parts.append(Money.format(tag.allowance, store.save.family?.currency ?? Money.local))
                if quest.done, let status = claimStatus { parts.append(claimWords(status, parent: tag.parent).text) }
            }
        }
        if quest.done {
            parts.insert("Sealed", at: 0)
        } else {
            parts.insert(counted ? "\(quest.progress) of \(quest.target), \(quest.xp) XP" : "\(quest.xp) XP", at: 0)
        }
        return parts.joined(separator: ", ")
    }

    private var socket: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            // Fills from the bottom while the row is held.
            Dots(color: Ink.verdigris, density: 2)
                .frame(height: pressing ? 42 : 0)
                .animation(pressing ? .linear(duration: holdSeconds) : .linear(duration: 0.08), value: pressing)
            ZStack {
                if quest.done {
                    PropIcon(name: "seal", size: 28, res: 20)
                } else if counted {
                    Text("\(quest.progress)/\(quest.target)").font(Typeface.label(15)).foregroundStyle(Ink.dim)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 44, height: 44)
        .clipShape(Notched(notch: 5))
        .plate(
            fill: quest.done ? Color(hex: 0x17332c) : Ink.loam,
            edge: quest.done || pressing ? Ink.verdigris : Ink.moss2,
            notch: 5
        )
    }

    private func showHint() {
        guard !quest.done else { return }
        hint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { hint = false }
    }

    private func seal() {
        guard !quest.done else { return }
        pressing = false
        hint = false
        // A parent asked for a photo: it counts once one is added.
        if needsPhoto {
            Feedback.tap()
            askingPhoto = true
            return
        }
        celebrate(store.mark(quest.cadence, key: quest.key))
    }

    private func celebrate(_ events: [GameEvent]) {
        var earned = 0
        for event in events {
            if case .xp(let amount, _) = event { earned += amount }
        }
        guard earned > 0 else {
            Feedback.step()
            return
        }
        stage.cheer()
        if events.contains(.clear) { Feedback.clear() } else { Feedback.done() }
        gain = earned
        floated = false
        withAnimation(.easeOut(duration: 0.9)) { floated = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { gain = nil }
    }
}

/// The sheet for writing your own quest.
struct QuestFormSheet: View {
    let startCadence: Cadence

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var cadence: Cadence = .daily
    @State private var kind: QuestKind = .mind
    @State private var difficulty = 2
    @State private var pinned = false

    private let every: [Cadence: String] = [.daily: "day", .weekly: "week", .monthly: "month"]
    private let effort: [(Int, String)] = [(1, "Light"), (2, "Steady"), (3, "Hard")]
    private let maxLength = 80

    private var ready: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Your quest") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("What will you do?")
                    TextField("", text: $title, prompt: Text("Practise guitar for 20 minutes").foregroundStyle(Ink.faint))
                        .font(Typeface.text(19))
                        .foregroundStyle(Ink.bone)
                        .tint(Ink.lantern)
                        .submitLabel(.done)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 50)
                        .plate(fill: Ink.ink, edge: Ink.moss2, notch: 6)
                        .onChange(of: title) { _, new in
                            if new.count > maxLength { title = String(new.prefix(maxLength)) }
                        }
                    if title.count > maxLength - 20 {
                        Text("\(maxLength - title.count) left").caps(Ink.faint)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 6)
                    }

                    SectionLabel("How often?")
                    FlowLayout {
                        ForEach(Cadence.allCases, id: \.self) { option in
                            Chip(title: option.rawValue, selected: option == cadence) {
                                Feedback.select()
                                cadence = option
                            }
                        }
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

                    SectionLabel("How much effort?")
                    FlowLayout {
                        ForEach(effort, id: \.0) { level, name in
                            Chip(title: "\(name) · \(questXp(cadence, level)) XP", selected: level == difficulty) {
                                Feedback.select()
                                difficulty = level
                            }
                        }
                    }

                    RowGroup {
                        ToggleRow(
                            title: "Show it every \(every[cadence] ?? "day")",
                            note: pinned ? "Always on the board" : "On the board now, then mixed in",
                            isOn: $pinned
                        )
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Button("Add quest") {
                store.addCustom(CustomQuestInput(title: title, cadence: cadence, category: kind, difficulty: difficulty, pinned: pinned))
                Feedback.done()
                dismiss()
            }
            .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
            .disabled(!ready)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear { cadence = startCadence }
        .spadeSheet()
    }
}

/// The title and close button at the top of a sheet.
struct SheetHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(Typeface.display(40))
                .foregroundStyle(Ink.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer()
            Button {
                Feedback.tap()
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.bone)
                    .frame(width: 44, height: 44)
                    .plate(fill: Ink.loam2, edge: Ink.moss2, notch: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.top, 22)
        .padding(.bottom, 6)
    }
}
