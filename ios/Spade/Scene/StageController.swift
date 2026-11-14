import SceneKit
import SwiftUI
import UIKit
import simd

// The stage: one 3D scene that sits behind the whole app.
// It owns the camera, the hero and the scenery, and updates them about 30 times a second.

/// The camera's set positions. The names match the shots in models.json.
enum StageShot: String {
    case title, quests, hero, satchel, feats, dig
}

struct StageProgress: Equatable {
    /// Dailies finished today, and how many there are.
    var dailyDone = 0
    var dailyTotal = 3
    var streak = 0
    /// One entry per weekday (Monday first): was a daily finished that day?
    var week: [Bool] = Array(repeating: false, count: 7)
    /// Today's weekday, 0 = Monday.
    var today = 0
    /// How far through the month it is, 0...1.
    var month: Double = 0.5
}

@MainActor
final class StageController: NSObject, ObservableObject {
    /// Where the panel of UI begins, in points from the top of the screen. The screens follow this.
    @Published private(set) var panelTop: CGFloat = 0
    /// Size of one chunky scene pixel, in points. The UI matches its dot patterns to it.
    @Published private(set) var pixelSize: CGFloat = 1.4

    let scene = SCNScene()
    private let hero = HeroNode()
    private let scenery = Scenery()
    private let unearth = Unearth()
    private let cameraNode = SCNNode()
    private let models = ModelLibrary.shared

    private weak var container: UIView?
    private var sceneView: SCNView?
    private var link: CADisplayLink?

    // The scene view is taller than the screen. Sliding it up or down is how the
    // picture is framed so the hero lands in the visible part above the panel.
    private let tall: CGFloat = 1.6

    private var shot: StageShot = .quests
    private var current: ShotSpec
    private var lookAt: SIMD3<Float>
    private var screen: CGSize = .zero

    private var time: Double = 0
    private var lastStamp: CFTimeInterval = 0
    private var heroYaw: Float
    private var heroYawTarget: Float
    private var freeSpin = false
    private var dragging = false
    private var burstAt: Double = -10
    private var retro = true
    private var reducedMotion = false

    override init() {
        let start = ModelLibrary.shared.shots["quests"]!
        current = start
        lookAt = SIMD3(start.target[0], start.target[1], start.target[2])
        heroYaw = ModelLibrary.shared.heroYaw
        heroYawTarget = ModelLibrary.shared.heroYaw
        super.init()

        scene.rootNode.addChildNode(scenery.root)
        scene.rootNode.addChildNode(hero.root)
        scene.rootNode.addChildNode(unearth.root)
        scene.background.contents = scenery.horizonColor
        scene.fogColor = scenery.horizonColor
        scene.fogDensityExponent = 1

        let camera = SCNCamera()
        camera.zNear = 0.5
        camera.zFar = 300
        // The view is taller than the screen, so the camera's angle is widened to match.
        let half = tan(Double(models.fov) * .pi / 360) * Double(tall)
        camera.fieldOfView = CGFloat(atan(half) * 360 / .pi)
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        hero.root.simdOrientation = rotation(y: heroYaw)
        reducedMotion = UIAccessibility.isReduceMotionEnabled

        // Start from the phone's own screen, so the first frame is already laid out.
        let scale = UIScreen.main.scale
        pixelSize = max(2, (scale * 1.4).rounded()) / scale
        screen = UIScreen.main.bounds.size
        place()
    }

    // MARK: - Hooking up to the screen

    /// Puts the 3D view inside `container` and starts the clock.
    func attach(to container: UIView) {
        guard sceneView == nil else { return }
        self.container = container
        container.clipsToBounds = true
        container.backgroundColor = UIColor(RGB(0.051, 0.059, 0.047))

        let view = SCNView(frame: .zero)
        view.scene = scene
        view.pointOfView = cameraNode
        view.antialiasingMode = .none
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        view.backgroundColor = container.backgroundColor
        view.isUserInteractionEnabled = false
        container.addSubview(view)
        sceneView = view

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        container.addGestureRecognizer(pan)

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
        applyResolution()
        place()
    }

    /// Call when the screen size is known or changes.
    func layout(_ size: CGSize) {
        guard size != screen, size.height > 0 else { return }
        screen = size
        applyResolution()
        place()
    }

    func setPaused(_ paused: Bool) {
        link?.isPaused = paused
        sceneView?.isPlaying = !paused
        if !paused { lastStamp = 0 }
    }

    private func applyResolution() {
        guard let view = sceneView else { return }
        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        let pixel: CGFloat
        if retro {
            // Each scene pixel covers a block of screen pixels, about 1.4 points wide.
            let block = max(2, (scale * 1.4).rounded())
            view.contentScaleFactor = scale / block
            view.layer.magnificationFilter = .nearest
            pixel = block / scale
            Materials.ditherLevels = 22
        } else {
            view.contentScaleFactor = min(scale, 2)
            view.layer.magnificationFilter = .linear
            pixel = 1.4
            Materials.ditherLevels = 64
        }
        // Only announce a real change: the screens redraw their dot patterns when this moves.
        if pixel != pixelSize { pixelSize = pixel }
    }

    // MARK: - Controls

    func setShot(_ next: StageShot, animated: Bool = true) {
        shot = next
        // Only the Hero screen lets the avatar stay turned; elsewhere it swings back to face front.
        freeSpin = next == .hero
        if !freeSpin { heroYawTarget = next == .dig ? models.digHeroYaw : models.heroYaw }
        if !animated, let goal = models.shots[next.rawValue] {
            current = goal
            lookAt = SIMD3(goal.target[0], goal.target[1], goal.target[2])
            place()
        }
    }

    func setRetro(_ on: Bool) {
        guard retro != on else { return }
        retro = on
        applyResolution()
    }

    func setHero(look: HeroLook, gear: [String: String]) {
        hero.apply(look: look, gear: gear)
    }

    func setProgress(_ p: StageProgress) {
        let level = p.dailyTotal > 0 ? min(1, Float(p.dailyDone) / Float(p.dailyTotal)) : 0
        scenery.setFlame(level: level, streak: p.streak)
        scenery.setWeek(done: p.week, today: p.today)
        // Never quite a new moon: a sliver always shows, so the moon stays part of the picture.
        scenery.setMoon(phase: Float(0.1 + p.month * 0.9))
    }

    /// The hero hops and the lantern flares.
    func cheer() {
        hero.cheer(at: time)
        scenery.flare(at: time)
    }

    /// A burst of warm light around the hero, for level-ups.
    func burst() {
        burstAt = time
        cheer()
    }

    func playUnearth(itemId: String, color: RGB) {
        unearth.play(itemId: itemId, color: color, time: time)
    }

    func endUnearth() {
        unearth.dismiss()
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began, .changed:
            dragging = true
            heroYaw += Float(pan.translation(in: pan.view).x) * 0.012
            pan.setTranslation(.zero, in: pan.view)
            if freeSpin { heroYawTarget = heroYaw }
        default:
            dragging = false
        }
    }

    // MARK: - Every frame

    @objc private func step(_ link: CADisplayLink) {
        let stamp = link.timestamp
        let dt = lastStamp == 0 ? 1.0 / 30 : min(0.1, stamp - lastStamp)
        lastStamp = stamp
        time += dt
        update(dt)
        place()
    }

    private func update(_ dt: Double) {
        guard let goal = models.shots[shot.rawValue] else { return }
        let ease = reducedMotion ? Float(1) : Float(1 - exp(-dt * 5.5))
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * ease }
        var sheet = mix(current.sheet, goal.sheet)
        if abs(goal.sheet - sheet) < 0.0015 { sheet = goal.sheet }
        current = ShotSpec(
            target: goal.target,
            dist: mix(current.dist, goal.dist),
            height: mix(current.height, goal.height),
            yaw: mix(current.yaw, goal.yaw),
            screenY: mix(current.screenY, goal.screenY),
            sheet: sheet
        )
        lookAt += (SIMD3(goal.target[0], goal.target[1], goal.target[2]) - lookAt) * ease

        if !dragging { heroYaw += (heroYawTarget - heroYaw) * Float(1 - exp(-dt * 6)) }
        hero.root.simdOrientation = rotation(y: heroYaw)
        hero.update(time: time)

        // A slow, slight drift keeps the picture from feeling frozen.
        let drift = reducedMotion ? 0 : sin(Float(time) * 0.17) * 0.035
        let yaw = current.yaw + drift
        let eye = SIMD3<Float>(lookAt.x + sin(yaw) * current.dist, current.height, lookAt.z + cos(yaw) * current.dist)
        cameraNode.simdPosition = eye
        cameraNode.simdLook(at: lookAt)
        scene.fogStartDistance = CGFloat(current.dist - 2)
        scene.fogEndDistance = CGFloat(current.dist + 44)

        scenery.update(time: time, camera: eye)

        // The burst light: from a dig-up if one is playing, otherwise from a level-up.
        if let glow = unearth.update(time: time, dt: dt) {
            setBurst(position: glow.position, light: glow.light, range: 4.5)
        } else {
            let fade = Float(max(0, 1 - (time - burstAt) / 1.4))
            setBurst(position: SIMD3(0, 1.1, 0.9), light: RGB(1.0, 0.82, 0.5) * (fade * fade * 2.2), range: 5)
        }
    }

    private func setBurst(position: SIMD3<Float>, light: RGB, range: Float) {
        let peak = max(light.x, max(light.y, light.z))
        scenery.burstLight.simdPosition = position
        scenery.burstLight.light?.attenuationEndDistance = CGFloat(range)
        scenery.burstLight.light?.intensity = CGFloat(1000 * peak)
        if peak > 0.001 { scenery.burstLight.light?.color = UIColor(light / peak) }
    }

    /// Positions the tall scene view and works out where the panel begins.
    private func place() {
        guard screen.height > 0 else { return }
        // Short phones give the panel a bigger share of the screen, and the picture moves up to match.
        let short = max(0, min(0.2, (780 - screen.height) / 780))
        let squeeze = current.sheet >= 1 ? 1 : 1 - short * 0.75
        let block = pixelSize
        func snap(_ v: CGFloat) -> CGFloat { (v / block).rounded() * block }

        let top = current.sheet >= 1 ? screen.height : snap(CGFloat(current.sheet) * squeeze * screen.height)
        if abs(top - panelTop) > 0.2 { panelTop = top }

        guard let view = sceneView else { return }
        let targetY = snap(CGFloat(current.screenY) * squeeze * screen.height)
        let height = screen.height * tall
        let frame = CGRect(x: 0, y: targetY - height / 2, width: screen.width, height: height)
        if view.frame != frame { view.frame = frame }
    }
}

/// The SwiftUI wrapper that shows the stage.
struct StageView: UIViewRepresentable {
    let stage: StageController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        stage.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
