import Combine
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: AppTab
    /// Bumped when the tab you are already on is tapped again: that screen jumps back to its top.
    @State private var tops: [AppTab: Int] = [:]
    @State private var settingsOpen = false
    @State private var guideOpen = false
    @State private var keyboard: CGFloat = 0

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    /// While Spade is open it also asks iCloud for family changes this often, in case a nudge was missed.
    private let cloudTicker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    init() {
        // The demo screens (used for automated screenshots) can open on a particular tab.
        let demo = DemoMode.requested ?? ""
        let start = AppTab(rawValue: demo) ?? (
            demo == "item" ? .satchel
                : ["picker", "chamberhero", "hoodup", "hooddown", "softhero", "legacyhero"].contains(demo) ? .hero
                : demo == "familyquest" || demo == "invite" ? .family
                : .quests
        )
        _tab = State(initialValue: start)
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
        // In steps, so the compiler checks a few modifiers at a time. As one long chain it
        // was too much for the Swift compiler in Xcode 27 ("unable to type-check this
        // expression in reasonable time").
        listening(to: following(presenting(screen)))
    }

    /// Three layers: the 3D scene at the back; the system's own tab bar and its screens
    /// in the middle (the scene shows through the top of each screen); and the HUD and
    /// the big moments (a dig, a level-up) on top.
    private var screen: some View {
        ZStack {
            measured { full, insets in
                backdrop(full: full, insets: insets)
                    .onAppear { stage.layout(full) }
                    .onChange(of: full) { _, size in stage.layout(size) }
            }
            if store.save.onboarded {
                tabs
                    .opacity(playing ? 1 : 0)
                    .allowsHitTesting(playing)
                    .accessibilityHidden(!playing)
            }
            measured { full, insets in overlays(full: full, insets: insets) }
        }
        .ignoresSafeArea(.keyboard)
        .background(Ink.ink.ignoresSafeArea())
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    /// Lays out a full-screen layer in screen points, edge to edge, with the safe area insets to hand.
    private func measured<V: View>(@ViewBuilder _ content: @escaping (CGSize, EdgeInsets) -> V) -> some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let full = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            content(full, insets)
                .frame(width: full.width, height: full.height, alignment: .topLeading)
                .ignoresSafeArea()
        }
    }

    /// Sheets and alerts.
    private func presenting(_ content: some View) -> some View {
        content
            .sheet(isPresented: $settingsOpen) { SettingsSheet() }
            .sheet(isPresented: $guideOpen, onDismiss: markGuideSeen) { GuideSheet() }
            // A family invite that was opened. It waits until the player has started.
            .sheet(item: Binding(
                get: { store.save.onboarded ? store.incoming : nil },
                set: { if $0 == nil { store.closeIncoming() } }
            )) { arrival in
                IncomingSheet(arrival: arrival)
            }
            .alert("Join as a guardian?", isPresented: $store.guardianInvitation) {
                Button("Join family") { store.acceptGuardian() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will be able to manage the family's quests, approve completions and review its history. The family owner's phone relays updates to children when Spade is open.")
            }
    }

    /// Keeps the 3D stage, the tabs and the reminders in step with the save.
    private func following(_ content: some View) -> some View {
        content
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
    }

    /// Things from outside the screen: the app coming and going, tapped notifications, timers and the keyboard.
    private func listening(to content: some View) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                stage.setPaused(phase != .active)
                if phase == .active {
                    store.sync()
                    store.syncFamily()
                }
                if phase == .background {
                    Reminders.refresh(for: store.save)
                    store.wentToBackground()
                }
            }
            // A tapped notification asks for the tab it is about.
            .onChange(of: store.requestedTab) { _, wanted in
                guard let wanted else { return }
                store.requestedTab = nil
                pick(wanted)
            }
            .onReceive(ticker) { _ in store.sync() }
            .onReceive(cloudTicker) { _ in
                guard scenePhase == .active else { return }
                store.syncFamily()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let height = max(0, UIScreen.main.bounds.height - frame.minY)
                withAnimation(.easeOut(duration: 0.22)) { keyboard = height }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.22)) { keyboard = 0 }
            }
    }

    /// The scene, and on first launch the title over it.
    @ViewBuilder
    private func backdrop(full: CGSize, insets: EdgeInsets) -> some View {
        let top = stage.panelTop
        ZStack(alignment: .topLeading) {
            StageView(stage: stage)
                .frame(width: full.width, height: full.height)
                .accessibilityHidden(true)

            if !store.save.onboarded {
                TitleLogo(width: full.width)
                    .offset(y: insets.top + full.height * 0.07)
                BelowPanel(top: top, full: full, bottomInset: insets.bottom) {
                    TitlePanel()
                }
                .offset(y: -keyboard)
            }
        }
    }

    /// Over the tabs: the level and streak plates, a dig or a level-up, and toasts.
    @ViewBuilder
    private func overlays(full: CGSize, insets: EdgeInsets) -> some View {
        let moment = store.moment
        let top = stage.panelTop
        if store.save.onboarded {
            ZStack(alignment: .topLeading) {
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

    /// The system's own tab bar: Liquid Glass on iOS 26 and newer, with its native
    /// press-and-drag between tabs, and the usual tab bar before that. Picking a tab moves
    /// the camera, and tapping the tab you are on scrolls its screen back to the top.
    private var tabs: some View {
        TabView(selection: Binding(get: { tab }, set: { pick($0) })) {
            ForEach(AppTab.shown(for: store.save.role)) { option in
                tabPage(option)
                    .tag(option)
                    .tabItem {
                        Label {
                            Text(option.title)
                        } icon: {
                            Image(uiImage: tabIcon(option)).renderingMode(.original)
                        }
                    }
            }
        }
        .tint(Ink.lantern)
    }

    /// One tab: see-through at the top, where the scene shows and a drag turns the hero (or
    /// a tap on the new hero flips its hood), then the XP gauge and the screen itself.
    private func tabPage(_ which: AppTab) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: stage.panelTop)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in stage.dragHero(translation: value.translation.width) }
                        .onEnded { _ in stage.endHeroDrag() }
                )
                .onTapGesture(coordinateSpace: .global) { point in stage.tapHero(atScreen: point) }
                .accessibilityHidden(true)
            panelBody(which)
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(playing ? .automatic : .hidden, for: .tabBar)
    }

    /// The XP gauge and one screen, on the dark panel under the scene.
    private func panelBody(_ which: AppTab) -> some View {
        let level = store.level
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

            tabContent(which)
                .environment(\.scrollTopToken, tops[which] ?? 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The dark panel runs on under the tab bar, so lists scroll beneath the glass.
        .background(Ink.ink)
        // And the scene dissolves into the panel.
        .overlay(alignment: .top) {
            DitherFade().frame(height: fade).offset(y: -fade).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func tabContent(_ which: AppTab) -> some View {
        switch which {
        case .quests: QuestBoardView()
        case .hero: HeroScreenView()
        case .satchel: SatchelView()
        case .feats: FeatsView()
        case .family: FamilyView()
        }
    }

    /// The tab's picture: the prop photographed for it, or for the Hero tab the hero's own face,
    /// in its own colours (the system would otherwise paint it one flat tint).
    private func tabIcon(_ option: AppTab) -> UIImage {
        if option == .hero {
            return TabIcons.icon(IconForge.shared.portrait(look: HeroLook(store.save.hero), gear: store.save.equipped))
        }
        return TabIcons.icon(IconForge.shared.prop(option.icon, res: 22))
    }

    // MARK: - Actions

    private func start() {
        stage.setProgress(progress)
        dressHero()
        applySettings()
        // After the hero is chosen, since the new one frames some shots a little closer.
        stage.setShot(shot, animated: false)
        let store = store
        stage.onHeroTap = { store.flipHood() }
        offerGuide()
        Task { @MainActor in
            // A moment after launch, once the first screen is up.
            try? await Task.sleep(for: .seconds(0.8))
            Feedback.prepare()
        }
        switch DemoMode.requested {
        case "settings", "sync", "chamber": settingsOpen = true
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
        stage.setHeroDesign(newHero: settings.newHero, cel: settings.celShading)
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
        guard AppTab.shown(for: store.save.role).contains(next) else { return }
        if next == tab {
            tops[next, default: 0] += 1
            return
        }
        Feedback.select()
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

/// Pixel-art icons scaled up crisply for the tab bar, kept so they aren't redrawn on every update.
@MainActor
private enum TabIcons {
    private static var cache: [ObjectIdentifier: UIImage] = [:]

    static func icon(_ image: UIImage, size: CGFloat = 28) -> UIImage {
        if let done = cache[ObjectIdentifier(image)] { return done }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let drawn = renderer.image { context in
            context.cgContext.interpolationQuality = .none
            image.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        let out = drawn.withRenderingMode(.alwaysOriginal)
        if cache.count > 40 { cache.removeAll() }
        cache[ObjectIdentifier(image)] = out
        return out
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
