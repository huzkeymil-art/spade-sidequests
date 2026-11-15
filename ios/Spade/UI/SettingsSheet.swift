import SwiftUI
import UniformTypeIdentifiers

/// Settings: display, sound, reminders, which kinds of quest to deal, your own quests, and the save.
struct SettingsSheet: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var guideOpen = false
    @State private var importing = false
    @State private var pasting = false
    @State private var pasted = ""
    @State private var note = ""
    @State private var reminderNote = ""
    @State private var confirming = false
    @State private var backup: URL?
    @State private var pendingRole: Role?
    @State private var allowanceOpen = false
    @State private var linkPasting = false
    @State private var linkText = ""
    @State private var linkNote = ""

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        let save = store.save

        VStack(spacing: 0) {
            SheetHeader(title: "Settings") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Who this Spade is for")
                    RolePicker(role: save.role) { requestRole($0) }
                    familyRows(save)

                    SectionLabel("Display and feel")
                    RowGroup {
                        ToggleRow(title: "Retro pixels", note: "Chunky, dithered 3D", isOn: setting(\.retro))
                        Hairline()
                        ToggleRow(title: "Sound", isOn: setting(\.sound))
                        Hairline()
                        ToggleRow(title: "Haptics", note: "Small taps you can feel", isOn: setting(\.haptics))
                    }

                    SectionLabel("Reminders")
                    RowGroup {
                        ToggleRow(
                            title: "Daily reminders",
                            note: "9 in the morning, and 7:30 if quests are left",
                            isOn: Binding(get: { save.settings.reminders }, set: setReminders)
                        )
                    }
                    if !reminderNote.isEmpty {
                        footnote(reminderNote)
                    }

                    SectionLabel("Kinds of quest to deal")
                    FlowLayout {
                        ForEach(QuestKind.allCases, id: \.self) { kind in
                            Chip(title: kind.rawValue, icon: kind.rawValue, selected: save.settings.allows(kind)) {
                                Feedback.select()
                                store.toggleKind(kind)
                            }
                        }
                    }
                    footnote("Changes apply from the next deal. At least one kind stays on.")

                    SectionLabel("Your own quests")
                    if save.custom.isEmpty {
                        Text("None yet. Add one from the bottom of the quest board.")
                            .font(Typeface.italic())
                            .foregroundStyle(Ink.dim)
                    } else {
                        RowGroup {
                            ForEach(Array(save.custom.enumerated()), id: \.element.id) { index, quest in
                                if index > 0 { Hairline() }
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(quest.title).font(Typeface.text()).foregroundStyle(Ink.bone)
                                        Text("\(quest.cadence.rawValue) · \(quest.pinned ? "always shown" : "in the deck")").caps(Ink.faint)
                                    }
                                    Spacer(minLength: 8)
                                    Button {
                                        Feedback.tap()
                                        store.removeCustom(id: quest.id)
                                    } label: {
                                        Text("Remove").caps(Ink.rust).frame(minWidth: 44, minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(quest.title)")
                                }
                                .padding(.leading, 14)
                                .padding(.trailing, 12)
                                .padding(.vertical, 6)
                                .frame(minHeight: 52)
                            }
                        }
                    }

                    SectionLabel("Your save")
                    RowGroup {
                        if let backup {
                            ShareLink(item: backup) {
                                rowLabel("Back up save", note: "Share it or save it to Files")
                            }
                            .buttonStyle(RowButtonStyle())
                            Hairline()
                        }
                        Button {
                            Feedback.tap()
                            importing = true
                        } label: {
                            rowLabel("Restore from a file")
                        }
                        .buttonStyle(RowButtonStyle())
                        Hairline()
                        Button {
                            Feedback.tap()
                            pasting.toggle()
                        } label: {
                            rowLabel("Paste a save", turned: pasting)
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                    if pasting {
                        TextEditor(text: $pasted)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Ink.bone)
                            .tint(Ink.lantern)
                            .scrollContentBackground(.hidden)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(8)
                            .frame(height: 120)
                            .plate(fill: Ink.ink, edge: Ink.moss2, notch: 6)
                            .padding(.top, 10)
                            .accessibilityLabel("Save data")
                        Button("Load this save") {
                            load(Data(pasted.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
                        }
                        .buttonStyle(PlateButtonStyle(block: true))
                        .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.top, 10)
                    }
                    footnote(note.isEmpty ? "Progress lives only on this iPhone. Back it up to keep it safe or move it to another phone. Saves from the web version of Spade load here too." : note)

                    SectionLabel("Help")
                    RowGroup {
                        Button {
                            Feedback.tap()
                            guideOpen = true
                        } label: {
                            rowLabel("How Spade works")
                        }
                        .buttonStyle(RowButtonStyle())
                        Hairline()
                        Link(destination: URL(string: "https://spade-sidequests-support.fwmiller94.chatgpt.site/support/")!) {
                            rowLabel("Contact support", note: "Help with Spade")
                        }
                        .buttonStyle(RowButtonStyle())
                        Hairline()
                        Link(destination: URL(string: "https://spade-sidequests-support.fwmiller94.chatgpt.site/privacy/")!) {
                            rowLabel("Privacy policy", note: "How your data is handled")
                        }
                        .buttonStyle(RowButtonStyle())
                    }

                    SectionLabel("Start over")
                    RowGroup {
                        Button {
                            Feedback.tap()
                            confirming = true
                        } label: {
                            Text("Erase all progress").font(Typeface.text()).foregroundStyle(Ink.rust)
                        }
                        .buttonStyle(RowButtonStyle())
                    }

                    SectionLabel("About")
                    Text("Spade \(version). All models, textures and sounds are generated by the app's own code. Typefaces: Jacquard 24 and Jersey 15 by Sarah Cadigan-Fried, IM Fell English by Igino Marini, under the SIL Open Font License.")
                        .font(Typeface.text(15))
                        .foregroundStyle(Ink.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .spadeSheet()
        .onAppear { backup = store.backupFile() }
        .onChange(of: store.save) { _, _ in backup = store.backupFile() }
        .sheet(isPresented: $guideOpen) { GuideSheet() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                load(data)
            } else {
                note = "That file couldn't be opened."
                Feedback.warn()
            }
        }
        .sheet(isPresented: $allowanceOpen) { AllowanceSheet() }
        .alert(leaveTitle, isPresented: Binding(get: { pendingRole != nil }, set: { if !$0 { pendingRole = nil } })) {
            Button("Change", role: .destructive) {
                if let role = pendingRole { store.chooseRole(role) }
                pendingRole = nil
            }
            Button("Cancel", role: .cancel) { pendingRole = nil }
        } message: {
            Text(leaveMessage)
        }
        .alert("Erase all progress?", isPresented: $confirming) {
            Button("Erase", role: .destructive) {
                store.reset()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your level, items, feats and quests will be gone for good. This can't be undone.")
        }
    }

    // MARK: - Family

    @ViewBuilder
    private func familyRows(_ save: Save) -> some View {
        switch save.role {
        case .solo:
            EmptyView()
        case .child:
            if let family = save.family {
                footnote("In \(family.parentName)'s family. Their quests show up on your board.")
                RowGroup {
                    Button {
                        Feedback.tap()
                        allowanceOpen = true
                    } label: {
                        rowLabel("Allowance", note: "\(Money.format(family.claims.total(.approved), family.currency)) owed to you")
                    }
                    .buttonStyle(RowButtonStyle())
                    Hairline()
                    pasteLinkRow()
                }
                .padding(.top, 10)
            } else {
                footnote("Ask your parent to send you a link from their Spade. Tap it, and their quests join your board.")
                RowGroup { pasteLinkRow() }
                    .padding(.top, 10)
            }
            pasteLinkBox()
        case .parent:
            footnote("Set quests and allowance for your children in the Family tab.")
            RowGroup { pasteLinkRow() }
                .padding(.top, 10)
            pasteLinkBox()
        }
    }

    private func pasteLinkRow() -> some View {
        Button {
            Feedback.tap()
            linkPasting.toggle()
            linkNote = ""
        } label: {
            rowLabel("Paste a family link", note: "If tapping the link didn't open Spade", turned: linkPasting)
        }
        .buttonStyle(RowButtonStyle())
    }

    @ViewBuilder
    private func pasteLinkBox() -> some View {
        if linkPasting {
            TextEditor(text: $linkText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Ink.bone)
                .tint(Ink.lantern)
                .scrollContentBackground(.hidden)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .frame(height: 96)
                .plate(fill: Ink.ink, edge: Ink.moss2, notch: 6)
                .padding(.top, 10)
                .accessibilityLabel("Family link")
            Button("Open link", action: openLink)
                .buttonStyle(PlateButtonStyle(block: true))
                .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.top, 10)
            if !linkNote.isEmpty { footnote(linkNote) }
        }
    }

    private func openLink() {
        let text = linkText
        guard FamilyLinks.read(text) != nil else {
            linkNote = "That isn't a Spade family link. Copy the whole link and try again."
            Feedback.warn()
            return
        }
        linkText = ""
        linkPasting = false
        // Close Settings first: what the link brings opens on the main screen.
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            store.receive(text)
        }
    }

    /// Changing role clears what belonged to the old one, so that asks first.
    private func requestRole(_ role: Role) {
        let save = store.save
        guard role != save.role else { return }
        let hasKids = !(save.household?.children.isEmpty ?? true)
        if (save.role == .parent && hasKids) || (save.role == .child && save.family != nil) {
            pendingRole = role
        } else {
            store.chooseRole(role)
        }
    }

    private var leaveTitle: String {
        store.save.role == .parent ? "Stop being a parent here?" : "Leave \(store.save.family?.parentName ?? "your parent")'s family?"
    }

    private var leaveMessage: String {
        store.save.role == .parent
            ? "Your children, their quests and the allowance records on this phone will be deleted."
            : "Their quests come off your board, and your allowance records go. Everything you've earned stays."
    }

    // MARK: - Pieces

    private func rowLabel(_ title: String, note: String? = nil, turned: Bool = false) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(Typeface.text()).foregroundStyle(Ink.bone)
                if let note { Text(note).caps(Ink.faint) }
            }
            Spacer(minLength: 8)
            Chevron().rotationEffect(.degrees(turned ? 90 : 0))
        }
        .contentShape(Rectangle())
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Typeface.italic(15))
            .foregroundStyle(Ink.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 9)
    }

    /// A two-way link between a switch and one on/off setting.
    private func setting(_ path: WritableKeyPath<GameSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.save.settings[keyPath: path] },
            set: { value in store.setSettings { $0[keyPath: path] = value } }
        )
    }

    // MARK: - Actions

    private func setReminders(_ on: Bool) {
        reminderNote = ""
        guard on else {
            store.setSettings { $0.reminders = false }
            return
        }
        // The phone asks the player once. If they said no before, only the Settings app can change it.
        Task { @MainActor in
            if await Reminders.askPermission() {
                store.setSettings { $0.reminders = true }
            } else {
                reminderNote = "Notifications are switched off for Spade. Allow them in the Settings app, then try again."
                Feedback.warn()
            }
        }
    }

    private func load(_ data: Data) {
        if store.restore(from: data) {
            note = "Save loaded."
            pasting = false
            pasted = ""
            Feedback.done()
        } else {
            note = "That doesn't look like a Spade save."
            Feedback.warn()
        }
    }
}

// MARK: - Guide

/// A short welcome sheet that explains how to play and how to read the scene.
struct GuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let rows: [(icon: String, title: String, text: String)] = [
        ("seal", "Hold to seal", "Press and hold a quest until its square fills. A quick tap does nothing, so nothing gets sealed by accident."),
        ("flame", "The lantern is today", "It burns brighter with each daily quest you finish. Keep a streak going and the flame changes colour."),
        ("feat", "The runes are your week", "Monday is at the bottom of the stone. A rune lights for every day you finish at least one daily."),
        ("moon", "The moon is your month", "A thin sliver on the 1st, full on the last day. Monthly quests reset when it starts over."),
        ("satchel", "Quests dig things up", "Weekly and monthly quests always unearth an item. Daily quests sometimes do."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "How Spade works") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.title) { row in
                        HStack(alignment: .center, spacing: 14) {
                            PropIcon(name: row.icon, size: 46, res: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).font(Typeface.text()).foregroundStyle(Ink.bone)
                                Text(row.text)
                                    .font(Typeface.text(16))
                                    .foregroundStyle(Ink.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 11)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            Button("Start digging") {
                Feedback.tap()
                dismiss()
            }
            .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .spadeSheet()
    }
}
