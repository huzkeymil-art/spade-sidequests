import SwiftUI

private let hairNames: [String: String] = ["crop": "Crop", "tuft": "Tuft", "long": "Long", "knot": "Knot", "none": "Bare"]

extension Slot {
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// The avatar screen: what the hero wears and how they look.
struct HeroScreenView: View {
    @EnvironmentObject private var store: GameStore
    @State private var picking: Slot?
    @State private var renaming = false
    @State private var draft = ""

    var body: some View {
        let save = store.save
        let looks = Catalog.looks

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    Feedback.tap()
                    draft = save.hero.name
                    renaming = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(save.hero.name)
                            .font(Typeface.display(40))
                            .foregroundStyle(Ink.bone)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("Rename").caps(Ink.faint)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(save.hero.name). Rename your hero")
                Spacer(minLength: 8)
                Text("\(rankFor(store.level.level)) · Lv \(store.level.level)").caps(Ink.dim).lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScreenScroll {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Worn").padding(.top, -12)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Slot.allCases, id: \.self) { slot in
                            let worn = save.worn(slot)
                            Button {
                                Feedback.tap()
                                picking = slot
                            } label: {
                                VStack(spacing: 6) {
                                    SlotFrame(edge: worn != nil ? Ink.lantern : Ink.moss) {
                                        if let worn {
                                            ItemIcon(id: worn, size: 50)
                                        } else {
                                            PropIcon(name: "slot_\(slot.rawValue)", size: 38, res: 20)
                                        }
                                    }
                                    Text(slot.rawValue).caps(Ink.faint, size: 14).lineLimit(1).minimumScaleFactor(0.7)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(slot.title): \(worn.flatMap { store.item($0)?.name } ?? "empty"). Change")
                        }
                    }

                    if save.settings.newHero {
                        let hatOn = save.equipped["head"] != nil
                        SectionLabel(hatOn ? "Hood · a hat keeps it down" : "Hood · or tap your hero")
                        FlowLayout {
                            ForEach([false, true], id: \.self) { down in
                                Chip(title: down ? "Down" : "Up", selected: !hatOn && save.hero.hoodDown == down) {
                                    Feedback.select()
                                    store.setHood(down: down)
                                }
                                .disabled(hatOn)
                                .opacity(hatOn ? 0.5 : 1)
                            }
                        }
                    }

                    SectionLabel("Skin")
                    FlowLayout {
                        ForEach(looks.skin.indices.filter { looks.skin[$0] != "#39ff14" || (save.chamber ?? []).contains("spade_green") }, id: \.self) { i in
                            Swatch(color: Color(hex: hexValue(looks.skin[i])), selected: save.hero.skin == i, label: looks.skin[i] == "#39ff14" ? "Spade Green" : "Skin tone \(i + 1)") {
                                Feedback.select()
                                store.setHero { $0.skin = i }
                            }
                        }
                    }

                    SectionLabel("Hair")
                    FlowLayout {
                        ForEach(looks.hairStyles.indices, id: \.self) { i in
                            Chip(title: hairNames[looks.hairStyles[i]] ?? looks.hairStyles[i], selected: save.hero.hairStyle == i) {
                                Feedback.select()
                                store.setHero { $0.hairStyle = i }
                            }
                        }
                    }
                    .padding(.bottom, 10)
                    FlowLayout {
                        ForEach(looks.hair.indices.filter { looks.hair[$0] != "#39ff14" || (save.chamber ?? []).contains("spade_green") }, id: \.self) { i in
                            Swatch(color: Color(hex: hexValue(looks.hair[i])), selected: save.hero.hair == i, label: looks.hair[i] == "#39ff14" ? "Spade Green" : "Hair colour \(i + 1)") {
                                Feedback.select()
                                store.setHero { $0.hair = i }
                            }
                        }
                    }

                    if (save.chamber ?? []).contains("spade_green") { Text("Spade Green unlocked").caps(Ink.verdigris) }
                    SectionLabel("Scarf")
                    FlowLayout {
                        ForEach(looks.scarf.indices.filter { looks.scarf[$0] != "#39ff14" || (save.chamber ?? []).contains("spade_green") }, id: \.self) { i in
                            Swatch(color: Color(hex: hexValue(looks.scarf[i])), selected: save.hero.scarf == i, label: looks.scarf[i] == "#39ff14" ? "Spade Green" : "Scarf colour \(i + 1)") {
                                Feedback.select()
                                store.setHero { $0.scarf = i }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(item: $picking) { slot in
            SlotPickerSheet(slot: slot)
        }
        .onAppear {
            if DemoMode.requested == "picker" { picking = .hand }
        }
        .alert("Rename your hero", isPresented: $renaming) {
            TextField("Name", text: $draft)
            Button("Save") {
                let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { store.setHero { $0.name = name } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

extension Slot: Identifiable {
    var id: String { rawValue }
}

/// "#rrggbb" to a number.
func hexValue(_ text: String) -> UInt32 {
    UInt32(text.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
}

/// Choose what goes in one equipment slot.
struct SlotPickerSheet: View {
    let slot: Slot
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let save = store.save
        let owned = Catalog.items.filter { $0.slot == slot && save.inventory.contains($0.id) }
        let worn = save.worn(slot)

        VStack(spacing: 0) {
            SheetHeader(title: slot.title) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if owned.isEmpty {
                        Text("Nothing for this slot yet. Weekly and monthly quests always dig something up.")
                            .font(Typeface.italic())
                            .foregroundStyle(Ink.dim)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            Button {
                                Feedback.select()
                                store.wear(slot, nil)
                            } label: {
                                SlotFrame(edge: worn == nil ? Ink.bone : Ink.moss, fill: worn == nil ? Ink.loam2 : Ink.ink) {
                                    Text("None").caps(Ink.faint, size: 14)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Wear nothing")
                            ForEach(owned) { item in
                                Button {
                                    Feedback.select()
                                    store.wear(slot, item.id)
                                } label: {
                                    SlotFrame(edge: worn == item.id ? Ink.lantern : Ink.moss, fill: Ink.ink) {
                                        ItemIcon(id: item.id, size: 50)
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        item.rarity.color.frame(width: 6, height: 6).padding(5)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.name)
                                .accessibilityAddTraits(worn == item.id ? .isSelected : [])
                            }
                        }
                        if let worn, let item = store.item(worn) {
                            HStack(spacing: 8) {
                                Text(item.name).font(Typeface.text()).foregroundStyle(Ink.bone)
                                Text("· \(item.rarity.rawValue)").caps(item.rarity.color)
                            }
                        } else {
                            Text("Nothing worn here.").font(Typeface.italic()).foregroundStyle(Ink.dim)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .spadeSheet([.medium, .large])
    }
}
