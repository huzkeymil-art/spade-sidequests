import SwiftUI
import UIKit

/// The four sections of the app, shown in the floating tab bar.
enum AppTab: String, CaseIterable, Identifiable {
    case quests, hero, satchel, feats, family

    var id: String { rawValue }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The prop photographed for this tab's icon. The hero tab shows the hero's own face instead.
    var icon: String {
        switch self {
        case .quests: return "scroll"
        case .hero: return ""
        case .satchel: return "satchel"
        case .feats: return "feat"
        case .family: return "home"
        }
    }

    /// The tabs a player with this role sees. Only parents have the Family tab.
    static func shown(for role: Role) -> [AppTab] {
        role == .parent ? allCases : [.quests, .hero, .satchel, .feats]
    }

    var shot: StageShot {
        switch self {
        case .quests: return .quests
        case .hero: return .hero
        case .satchel: return .satchel
        case .feats: return .feats
        case .family: return .feats
        }
    }
}

/// The whole app: the 3D scene behind, and the panel of screens that slides over its lower part.
struct RootView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var stage: StageController
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: AppTab
    /// Screens are built the first time their tab is opened and then kept, so each
    /// one remembers where it was scrolled to, the way tabs do in iPhone apps.
    @State private var opened: Set<AppTab>
    /// Bumped when the tab you are already on is tapped again: that screen jumps back to its top.
    @State private var tops: [AppTab: Int] = [:]
    @State private var settingsOpen = false
    @State private var guideOpen = false
    @State private var keyboard: CGFloat = 0

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let dockHeight: CGFloat = 62

    init() {
        // The demo screens (used for automated screenshots) can open on a particular tab.
        let demo = DemoMode.requested ?? ""
        let start = AppTab(rawValue: demo) ?? (
            demo == "item" ? .satchel
                : demo == "picker" ? .hero
                : demo == "familyquest" || demo == "openlink" ? .family
                : .quests
        )
        _tab = State(initialValue: start)
        _opened = State(initialValue: [start])
    }

    // MARK: - What the scene should show

    private var playing: Bool { store.save.onboarded && store.moment == nil }

    private var shot: StageShot {
        if !store.save.onboarded { return .title }
        if case .item = store.moment { return .dig }
        return tab.shot
    }

    private var progress: StageProgress {
        let save = store.save
        let clock = store.clock
        let dailies = save.boards.daily.quests
        return StageProgress(
            dailyDone: dailies.filter { $0.done }.count,
            dailyTotal: dailies.count,
            streak: save.streak.count,
            week: clock.weekDays(store.now).map { save.activeDays.contains($0) },
            today: clock.weekdayIndex(store.now),
            month: clock.monthProgress(store.now)
        )
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let full = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            layers(full: full, insets: insets)
                .frame(width: full.width, height: full.height, alignment: .topLeading)
                .ignoresSafeArea()
                .onAppear { stage.layout(full) }
                .onChange(of: full) { _, size in stage.layout(size) }
        }
        .ignoresSafeArea(.keyboard)
        .background(Ink.ink.ignoresSafeArea())
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .sheet(isPresented: $settingsOpen) { SettingsSheet() }
        .sheet(isPresented: $guideOpen, onDismiss: markGuideSeen) { GuideSheet() }
        // A family link that arrived. It waits until the player has started.
        .sheet(item: Binding(
            get: { store.save.onboarded ? store.incoming : nil },
            set: { if $0 == nil { store.closeIncoming() } }
        )) { arrival in
            IncomingSheet(arrival: arrival) { pick(.family) }
        }
        .onChange(of: store.save.role) { _, role in
            if !AppTab.shown(for: role).contains(tab) { tab = .quests }
        }
        .onAppear(perform: start)
        .onChange(of: shot) { _, next in stage.setShot(next) }
        .onChange(of: progress) { _, next in stage.setProgress(next) }
        .onChange(of: store.save.hero) { _, _ in dressHero() }
        .onChange(of: store.save.equipped) { _, _ in dressHero() }
        .onChange(of: store.save.settings) { _, _ in applySettings() }
        .onChange(of: store.save.boards.daily) { _, _ in Reminders.refresh(for: store.save) }
        .onChange(of: store.moment) { _, next in
            // The dig stays on screen only while an item is being shown.
            if case .item = next { return }
            stage.endUnearth()
        }
        .onChange(of: playing) { _, _ in offerGuide() }
        .onChange(of: scenePhase) { _, phase in
            stage.setPaused(phase != .active)
            if phase == .active { store.sync() }
            if phase == .background { Reminders.refresh(for: store.save) }
        }
        .onReceive(ticker) { _ in store.sync() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let height = max(0, UIScreen.main.bounds.height - frame.minY)
            withAnimation(.easeOut(duration: 0.22)) { keyboard = height }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) { keyboard = 0 }
        }
    }

    @ViewBuilder
    private func layers(full: CGSize, insets: EdgeInsets) -> some View {
        let save = store.save
        let moment = store.moment
        let top = stage.panelTop

        ZStack(alignment: .topLeading) {
            StageView(stage: stage)
                .frame(width: full.width, height: full.height)
                .accessibilityHidden(true)

            if !save.onboarded {
                TitleLogo(width: full.width)
                    .offset(y: insets.top + full.height * 0.07)
                BelowPanel(top: top, full: full, bottomInset: insets.bottom) {
                    TitlePanel()
                }
                .offset(y: -keyboard)
            } else {
                panel(full: full, insets: insets, top: top)
                    .opacity(playing ? 1 : 0)
                    .allowsHitTesting(playing)
                    .accessibilityHidden(!playing)

                if moment == nil {
                    hud
                        .padding(.horizontal, 16)
                        .frame(width: full.width)
                        .offset(y: insets.top + 10)
                }

                if case .item(_, let itemId, let fresh, let echoXp) = moment, let item = store.item(itemId) {
                    FoundPanel(item: item, fresh: fresh, echoXp: echoXp, top: top, full: full, bottomInset: insets.bottom)
                        .id(moment?.id)
                }
                if case .level(_, let level, let rank) = moment {
                    LevelUpPanel(level: level, rank: rank, top: top)
                        .frame(width: full.width, height: full.height)
                        .id(moment?.id)
                }

                ToastStack()
                    .padding(.horizontal, 16)
                    .frame(width: full.width)
                    .offset(y: insets.top + 62)
            }
        }
    }

    // MARK: - Pieces

    private var hud: some View {
        let save = store.save
        let level = store.level.level
        let lit = save.streak.count > 0
        return HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                Text("Lv").caps(Ink.faint)
                Text("\(level)").font(Typeface.display(36)).foregroundStyle(Ink.lantern)
                Text(rankFor(level)).caps(Ink.bone).lineLimit(1)
            }
            .hudPlate()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level \(level), \(rankFor(level))")

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                PropIcon(name: lit ? "flame" : "flame_out", size: 26, res: 20)
                Text("\(save.streak.count)").font(Typeface.label(30)).foregroundStyle(lit ? Ink.lantern : Ink.faint)
            }
            .hudPlate()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(save.streak.count) day streak")

            Button {
                Feedback.tap()
                settingsOpen = true
            } label: {
                PropIcon(name: "gear", size: 24, res: 20).hudPlate()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .dynamicTypeSize(.xSmall ... .xLarge)
    }

    /// The panel under the scene: the XP gauge, the four screens and the floating tab bar.
    private func panel(full: CGSize, insets: EdgeInsets, top: CGFloat) -> some View {
        let level = store.level
        let dockBottom = max(insets.bottom - 10, 12)
        let dockSpace = dockHeight + dockBottom
        let fade = DitherFade.height(pixel: stage.pixelSize)

        return VStack(spacing: 0) {
            VStack(spacing: 7) {
                NotchGauge(value: Double(level.into), total: Double(level.need))
                HStack {
                    Text("\(level.into.formatted()) / \(level.need.formatted()) XP").caps(Ink.faint)
                    Spacer()
                    Text("Level \(level.level + 1) next").caps(Ink.faint)
                }
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Experience toward level \(level.level + 1)")
            .accessibilityValue("\(level.into) of \(level.need)")

            ZStack {
                screen(.quests) { QuestBoardView() }
                screen(.hero) { HeroScreenView() }
                screen(.satchel) { SatchelView() }
                screen(.feats) { FeatsView() }
                screen(.family) { FamilyView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.dockSpace, dockSpace)
        .frame(width: full.width, height: max(0, full.height - top), alignment: .top)
        .background(Ink.ink)
        // Where a list slides under the tab bar it dissolves into the background.
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                DitherFade().frame(height: fade)
                Ink.ink.frame(height: dockSpace)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            dock
                .padding(.horizontal, 16)
                .padding(.bottom, dockBottom)
        }
        // And the scene dissolves into the panel the same way.
        .overlay(alignment: .top) {
            DitherFade().frame(height: fade).offset(y: -fade)
        }
        .offset(y: top)
    }

    @ViewBuilder
    private func screen<V: View>(_ which: AppTab, @ViewBuilder _ content: () -> V) -> some View {
        if opened.contains(which) {
            content()
                .environment(\.scrollTopToken, tops[which] ?? 0)
                .opacity(tab == which ? 1 : 0)
                .allowsHitTesting(tab == which)
                .accessibilityHidden(tab != which)
        }
    }

    private var dock: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.shown(for: store.save.role)) { option in
                let selected = option == tab
                Button {
                    pick(option)
                } label: {
                    VStack(spacing: 3) {
                        Group {
                            if option == .hero {
                                PortraitIcon(hero: store.save.hero, gear: store.save.equipped, size: 28)
                            } else {
                                PropIcon(name: option.icon, size: 28)
                            }
                        }
                        .saturation(selected ? 1 : 0.3)
                        .opacity(selected ? 1 : 0.62)
                        Text(option.title).caps(selected ? Ink.bone : Ink.faint).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .plate(fill: selected ? Ink.ink : .clear, edge: selected ? Ink.moss : .clear, notch: 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .frame(height: dockHeight)
        .plate(fill: Ink.loam2, edge: Ink.moss2, notch: 14)
        .dynamicTypeSize(.xSmall ... .large)
    }

    // MARK: - Actions

    private func start() {
        stage.setShot(shot, animated: false)
        stage.setProgress(progress)
        dressHero()
        applySettings()
        offerGuide()
        Task { @MainActor in
            // A moment after launch, once the first screen is up.
            try? await Task.sleep(for: .seconds(0.8))
            Feedback.prepare()
        }
        switch DemoMode.requested {
        case "settings": settingsOpen = true
        case "guide": guideOpen = true
        default: break
        }
    }

    private func dressHero() {
        stage.setHero(look: HeroLook(store.save.hero), gear: store.save.equipped)
    }

    private func applySettings() {
        let settings = store.save.settings
        stage.setRetro(settings.retro)
        Feedback.soundOn = settings.sound
        Feedback.hapticsOn = settings.haptics
        Reminders.refresh(for: store.save)
    }

    /// New players get a short explanation once the first dig is out of the way.
    private func offerGuide() {
        if playing && !store.save.settings.guideSeen && DemoMode.requested == nil { guideOpen = true }
    }

    private func markGuideSeen() {
        if !store.save.settings.guideSeen { store.setSettings { $0.guideSeen = true } }
    }

    private func pick(_ next: AppTab) {
        Feedback.select()
        guard AppTab.shown(for: store.save.role).contains(next) else { return }
        if next == tab {
            tops[next, default: 0] += 1
            return
        }
        opened.insert(next)
        tab = next
    }
}

private extension View {
    /// The small dark plates that float over the scene at the top of the screen.
    func hudPlate() -> some View {
        padding(.horizontal, 11)
            .frame(minWidth: 44, minHeight: 44, maxHeight: 44)
            .plate(fill: Ink.ink.opacity(0.86), edge: Ink.moss, notch: 8)
    }
}

// MARK: - Scrolling screens

private struct ScrollTopKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Changes when a screen should jump back to the top of its list.
    var scrollTopToken: Int {
        get { self[ScrollTopKey.self] }
        set { self[ScrollTopKey.self] = newValue }
    }
}

/// The scrolling part of a screen. It leaves room for the floating tab bar, and
/// jumps back to the top when its tab is tapped a second time.
struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.scrollTopToken) private var token
    @Environment(\.dockSpace) private var dockSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    content
                }
                .padding(.bottom, dockSpace + 30)
            }
            .scrollIndicators(.hidden)
            .onChange(of: token) { _, _ in
                if reduceMotion {
                    reader.scrollTo("top", anchor: .top)
                } else {
                    withAnimation(.easeOut(duration: 0.25)) { reader.scrollTo("top", anchor: .top) }
                }
            }
        }
    }
}
