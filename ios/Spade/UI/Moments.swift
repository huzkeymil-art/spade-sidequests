import SwiftUI

// The big moments: the title screen, digging up an item, levelling up, and
// the small notices for feats.

/// Makes a view arrive with a small hop, a beat after the one before it.
private struct Pop: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.26).delay(delay)) { shown = true }
            }
    }
}

private extension View {
    func pop(_ order: Int) -> some View {
        modifier(Pop(delay: Double(order) * 0.12))
    }
}

/// A panel on the dark ground below the scene, from where the scene ends to the bottom of the screen.
struct BelowPanel<Content: View>: View {
    let top: CGFloat
    let full: CGSize
    let bottomInset: CGFloat
    @ViewBuilder var content: Content
    @EnvironmentObject private var stage: StageController

    var body: some View {
        let fade = DitherFade.height(pixel: stage.pixelSize)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.top, 4)
            .padding(.horizontal, 22)
            .padding(.bottom, max(bottomInset, 14) + 12)
            .frame(width: full.width, height: max(0, full.height - top), alignment: .topLeading)
            .background(Ink.ink)
            .overlay(alignment: .top) {
                DitherFade().frame(height: fade).offset(y: -fade)
            }
            .offset(y: top)
    }
}

// MARK: - First launch

/// The name of the app, over the scene.
struct TitleLogo: View {
    let width: CGFloat

    var body: some View {
        Text("Spade")
            .font(.custom("Jacquard24-Regular", fixedSize: min(96, width * 0.26)))
            .foregroundStyle(Ink.bone)
            .shadow(color: Ink.ink, radius: 0, x: 0, y: 3)
            .frame(width: width)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isHeader)
    }
}

/// First launch, in two short steps: a name to choose, then who this Spade is for.
struct TitlePanel: View {
    @EnvironmentObject private var store: GameStore
    @State private var name = ""
    @State private var role: Role = .solo
    @State private var choosing = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if choosing {
                // Only this part scrolls, and only if very large text needs it.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Who is this Spade for?").caps(Ink.faint).padding(.bottom, 12)
                        RolePicker(role: role, showsBlurb: false) { role = $0 }
                        Text(detail)
                            .font(Typeface.italic(17))
                            .foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                HStack(spacing: 10) {
                    Button("Back") {
                        Feedback.tap()
                        choosing = false
                    }
                    .buttonStyle(PlateButtonStyle())
                    Button("Break ground", action: begin)
                        .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                }
                .padding(.top, 12)
            } else {
                Text("Real quests, every day, week and month. Dig a little. See what turns up.")
                    .font(Typeface.italic(19))
                    .foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)
                Text("Name your digger").caps(Ink.faint).padding(.bottom, 9)
                TextField("", text: $name, prompt: Text("Digger").foregroundStyle(Ink.faint))
                    .font(Typeface.text(19))
                    .foregroundStyle(Ink.bone)
                    .tint(Ink.lantern)
                    .focused($typing)
                    .submitLabel(.next)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit(next)
                    .onChange(of: name) { _, new in
                        if new.count > 16 { name = String(new.prefix(16)) }
                    }
                    .padding(.horizontal, 13)
                    .frame(minHeight: 50)
                    .plate(fill: Ink.ink, edge: Ink.moss2, notch: 6)
                    .accessibilityLabel("Name your digger")
                Spacer(minLength: 12)
                Button("Next", action: next)
                    .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
            }
        }
        .animation(.easeOut(duration: 0.2), value: choosing)
        .onChange(of: store.incoming?.id) { _, arrived in
            if arrived != nil { role = .child }
        }
        .onAppear {
            // Opened by tapping a parent's invite: this is a child's Spade.
            if store.incoming != nil { role = .child }
            if DemoMode.requested == "roles" { choosing = true }
        }
    }

    private var detail: String {
        switch role {
        case .solo: return "Spade deals you quests, and you can write your own."
        case .parent: return "You get a Family tab to set quests, XP and allowance for your kids."
        case .child: return "Your parent can send you quests, sometimes with allowance."
        }
    }

    private func next() {
        Feedback.tap()
        typing = false
        choosing = true
    }

    private func begin() {
        Feedback.dig()
        store.begin(name: name)
        if role != .solo { store.chooseRole(role) }
    }
}

// MARK: - An item is dug up

/// An item being dug up. The 3D scene plays the dig; this adds the words.
struct FoundPanel: View {
    let item: ItemDef
    let fresh: Bool
    let echoXp: Int
    let top: CGFloat
    let full: CGSize
    let bottomInset: CGFloat

    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var stage: StageController
    @State private var shown = false

    var body: some View {
        let wearing = store.save.worn(item.slot) == item.id
        let offerToWear = fresh && !wearing

        ZStack(alignment: .topLeading) {
            if shown {
                BelowPanel(top: top, full: full, bottomInset: bottomInset) {
                    Text("\(fresh ? "Unearthed" : "Found again") · \(item.rarity.rawValue) \(item.slot.rawValue)")
                        .caps(item.rarity.color)
                        .pop(0)
                    Text(item.name)
                        .font(Typeface.display(48))
                        .foregroundStyle(Ink.bone)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 7)
                        .padding(.bottom, 9)
                        .pop(1)
                    Text(fresh ? item.lore : "You already carry one, so it becomes +\(echoXp) XP.")
                        .font(Typeface.italic())
                        .foregroundStyle(Ink.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .pop(2)
                    Spacer(minLength: 12)
                    HStack(spacing: 10) {
                        if offerToWear {
                            Button("Wear it") {
                                Feedback.done()
                                store.wear(item.slot, item.id)
                                store.nextMoment()
                            }
                            .buttonStyle(PlateButtonStyle(kind: .primary, block: true))
                        }
                        Button(offerToWear ? "Stow it" : "Keep digging") {
                            Feedback.tap()
                            store.nextMoment()
                        }
                        .buttonStyle(PlateButtonStyle(kind: offerToWear ? .plain : .primary, block: true))
                    }
                    .pop(3)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(fresh ? "Unearthed" : "Found again"): \(item.name)")
            } else {
                // Until the item is out of the ground, a tap anywhere below skips ahead.
                Color.clear
                    .frame(width: full.width, height: max(0, full.height - top))
                    .contentShape(Rectangle())
                    .offset(y: top)
                    .onTapGesture { shown = true }
                    .accessibilityLabel("Skip the dig")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: full.width, height: full.height, alignment: .topLeading)
        .task {
            stage.playUnearth(itemId: item.id, color: item.rarity.light)
            Feedback.dig()
            try? await Task.sleep(for: .seconds(1.05))
            if Task.isCancelled { return }
            Feedback.reveal()
            try? await Task.sleep(for: .seconds(Unearth.revealSeconds - 1.05))
            if Task.isCancelled { return }
            shown = true
        }
    }
}

// MARK: - A new level

/// A new level. Tap anywhere to carry on.
struct LevelUpPanel: View {
    let level: Int
    let rank: String?
    let top: CGFloat

    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var stage: StageController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Button {
            store.nextMoment()
        } label: {
            VStack(spacing: 0) {
                Text("Level").caps(Ink.dim).pop(0)
                Text("\(level)")
                    .font(.custom("Jacquard24-Regular", fixedSize: 176))
                    .foregroundStyle(Ink.lantern)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                    .scaleEffect(landed || reduceMotion ? 1 : 2.4)
                    .opacity(landed ? 1 : 0)
                Text(rank.map { "New rank: \($0)" } ?? rankFor(level))
                    .font(Typeface.label(22))
                    .foregroundStyle(Ink.bone)
                    .pop(2)
                Text("Tap to carry on").caps(Ink.faint).padding(.top, 22).pop(4)
                Spacer(minLength: 0)
            }
            .padding(.top, top + 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Level \(level). Continue")
        .onAppear {
            stage.burst()
            Feedback.level()
            withAnimation(.easeOut(duration: 0.4)) { landed = true }
        }
    }
}

// MARK: - Small notices

/// Small notices that drop in at the top and leave on their own. A tap sends one away early.
struct ToastStack: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        VStack(spacing: 6) {
            ForEach(store.toasts.prefix(3)) { toast in
                ToastRow(toast: toast)
            }
        }
    }
}

private struct ToastRow: View {
    let toast: Toast
    @EnvironmentObject private var store: GameStore

    var body: some View {
        Group {
            switch toast.kind {
            case .clear:
                row(icon: "flame", title: "Lantern full", note: "Every quest today", trailing: "+\(dailyClearXp)", edge: Ink.lantern)
            case .feat(let id):
                if let feat = Catalog.featById[id] {
                    row(icon: "feat", title: feat.name, note: "Feat earned", trailing: "+\(feat.xp)", edge: Ink.verdigris)
                }
            case .allowance(let amount):
                let family = store.save.family
                row(
                    icon: "home",
                    title: "\(family?.parentName ?? "Your parent") will check it",
                    note: "Allowance waiting",
                    trailing: Money.format(amount, family?.currency ?? Money.local),
                    edge: Ink.lantern
                )
            case .family(let title, let note):
                row(icon: "home", title: title, note: note, trailing: "", edge: Ink.verdigris)
            }
        }
        .pop(0)
        .task {
            if case .feat = toast.kind { Feedback.feat() }
            try? await Task.sleep(for: .seconds(3.4))
            if Task.isCancelled { return }
            store.dropToast(toast.id)
        }
    }

    private func row(icon: String, title: String, note: String, trailing: String, edge: Color) -> some View {
        Button {
            store.dropToast(toast.id)
        } label: {
            HStack(spacing: 11) {
                PropIcon(name: icon, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Typeface.text()).foregroundStyle(Ink.bone).lineLimit(1)
                    Text(note).caps(Ink.faint)
                }
                Spacer(minLength: 8)
                Text(trailing).font(Typeface.label(22)).foregroundStyle(edge == Ink.lantern ? Ink.lantern : Ink.verdigris)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .plate(fill: Ink.loam, edge: edge, notch: 9)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Dismiss")
    }
}
