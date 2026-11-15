import SwiftUI

/// Where an item comes from, in words, for items not found yet.
private func whereFrom(_ item: ItemDef) -> String {
    if let reward = chamberQuests.first(where: { $0.item == item.id }) {
        return "Chamber of Completion · \(reward.xp.formatted()) lifetime XP. Open Settings to claim."
    }
    if item.source == .milestone { return "Waiting at level \(item.level ?? 0)." }
    if item.source == .feat { return "A reward for a feat." }
    switch item.rarity {
    case .common: return "Turns up on daily and weekly quests."
    case .uncommon: return "Dug up on weekly quests, now and then on dailies."
    case .rare: return "Buried deep. Monthly quests find these most often."
    case .mythic: return "Almost never surfaces. Monthly quests are your best chance."
    }
}

/// Everything that can be found, with what you have so far.
struct SatchelView: View {
    @EnvironmentObject private var store: GameStore
    @State private var filter: Slot?
    @State private var open: ItemDef?

    var body: some View {
        let save = store.save
        let shown = Catalog.items.filter { filter == nil || $0.slot == filter }

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Satchel").font(Typeface.display(40)).foregroundStyle(Ink.bone)
                Spacer()
                Text("\(save.inventory.count) / \(Catalog.items.count) found").caps(Ink.dim)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Chip(title: "All", selected: filter == nil) {
                        Feedback.select()
                        filter = nil
                    }
                    ForEach(Slot.allCases, id: \.self) { slot in
                        Chip(title: slot.rawValue, selected: filter == slot) {
                            Feedback.select()
                            filter = slot
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 12)

            ScreenScroll {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(shown) { item in
                        let have = save.inventory.contains(item.id)
                        let worn = save.worn(item.slot) == item.id
                        Button {
                            Feedback.tap()
                            open = item
                        } label: {
                            SlotFrame(edge: worn ? Ink.lantern : Ink.moss, fill: have ? Ink.loam : Ink.ink) {
                                if have {
                                    ItemIcon(id: item.id, size: 62)
                                } else {
                                    Text("?").font(Typeface.label(30)).foregroundStyle(Ink.ghost)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                item.rarity.color.opacity(have ? 1 : 0.45).frame(width: 6, height: 6).padding(5)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(have ? "\(item.name)\(worn ? ", worn" : "")" : "Not found yet, \(item.rarity.rawValue) \(item.slot.rawValue)")
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(item: $open) { item in
            ItemSheet(item: item)
        }
        .onAppear {
            if DemoMode.requested == "item" { open = Catalog.itemById["barrow_blade"] }
        }
    }
}

/// One item up close, with a button to wear it or take it off.
struct ItemSheet: View {
    let item: ItemDef
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let have = store.save.inventory.contains(item.id)
        let worn = store.save.worn(item.slot) == item.id

        VStack(spacing: 0) {
            SheetHeader(title: have ? item.name : "Not yet found") { dismiss() }
            HStack(alignment: .center, spacing: 16) {
                SlotFrame(fill: have ? Ink.loam2 : Ink.ink) {
                    if have {
                        ItemIcon(id: item.id, size: 80)
                    } else {
                        Text("?").font(Typeface.label(30)).foregroundStyle(Ink.ghost)
                    }
                }
                .frame(width: 96)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(item.rarity.rawValue) · \(item.slot.rawValue)").caps(item.rarity.color)
                    Text(have ? item.lore : whereFrom(item))
                        .font(Typeface.italic())
                        .foregroundStyle(Ink.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 12)

            if have {
                Group {
                    if worn {
                        Button("Take off") {
                            Feedback.tap()
                            store.wear(item.slot, nil)
                        }
                        .buttonStyle(PlateButtonStyle(block: true))
                    } else {
                        Button("Wear it") {
                            Feedback.done()
                            store.wear(item.slot, item.id)
                        }
                        .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .spadeSheet([.height(330), .large])
    }
}

/// Achievements and lifetime numbers.
struct FeatsView: View {
    @EnvironmentObject private var store: GameStore

    private struct Entry: Identifiable {
        let feat: FeatDef
        let progress: FeatProgress
        var id: String { feat.id }
    }

    var body: some View {
        let save = store.save
        let earned = Catalog.feats.filter { save.feats[$0.id] != nil }.count
        // Earned feats first (newest at the top), then the rest by how close they are.
        let rows = Catalog.feats
            .map { Entry(feat: $0, progress: featProgress(save, $0)) }
            .sorted { a, b in
                if a.progress.done != b.progress.done { return a.progress.done }
                if a.progress.done { return (save.feats[a.feat.id] ?? 0) > (save.feats[b.feat.id] ?? 0) }
                return Double(a.progress.value) / Double(a.progress.goal) > Double(b.progress.value) / Double(b.progress.goal)
            }
        let stats: [(Int, String)] = [
            (save.counts.quests, "Quests"),
            (save.counts.bestStreak, "Best run"),
            (save.counts.dailyClears, "Full days"),
            (save.inventory.count, "Finds"),
        ]

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Feats").font(Typeface.display(40)).foregroundStyle(Ink.bone)
                    Spacer()
                    Text("\(earned) / \(Catalog.feats.count) earned").caps(Ink.dim)
                }
                .padding(.top, 12)
                .padding(.bottom, 10)
                Hairline()
                HStack(spacing: 6) {
                    ForEach(stats, id: \.1) { value, name in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(value.formatted()).font(Typeface.label(30)).foregroundStyle(Ink.bone)
                            Text(name).caps(Ink.faint, size: 14).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 10)
                Hairline()
            }
            .padding(.horizontal, 20)

            ScreenScroll {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        let feat = row.feat
                        let p = row.progress
                        HStack(spacing: 12) {
                            PropIcon(name: p.done ? "feat" : "feat_locked", size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(feat.name).font(Typeface.text()).foregroundStyle(p.done ? Ink.bone : Ink.dim)
                                Text(feat.desc + (feat.item.flatMap { store.item($0) }.map { " Reward: \($0.name)." } ?? ""))
                                    .font(Typeface.italic(15))
                                    .foregroundStyle(Ink.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !p.done && p.goal > 1 {
                                    NotchGauge(value: Double(p.value), total: Double(p.goal), height: 5, ticks: false).padding(.top, 4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 5) {
                                Text("+\(feat.xp.formatted())").font(Typeface.label(22)).foregroundStyle(p.done ? Ink.faint : Ink.verdigris)
                                if p.done {
                                    Text("Earned").caps(Ink.faint, size: 14)
                                } else if p.goal > 1 {
                                    Text("\(p.value)/\(p.goal)").caps(Ink.faint, size: 14)
                                }
                            }
                        }
                        .padding(.vertical, 11)
                        .accessibilityElement(children: .combine)
                        Hairline()
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
