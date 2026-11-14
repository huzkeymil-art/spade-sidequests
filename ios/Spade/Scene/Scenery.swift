import SceneKit
import UIKit
import simd

// The dig site: ground, the Week Stone, the lantern, the moon and the sky.
// Three of these double as progress displays: the lantern flame is today,
// the runes on the stone are the week, and the moon's phase is the month.

final class Scenery {
    let root = SCNNode()

    private let models = ModelLibrary.shared
    private let horizon: RGB

    // Sky: follows the camera so it always looks infinitely far away.
    private let skyAnchor = SCNNode()
    private let moon = SCNNode()
    private let moonHalo: SCNNode
    private var moonPhase: Float = -1
    private let moonPlace = SIMD3<Float>(2.35, 3.8, -40)
    private let moonRadius: Float = 2.7

    // Week Stone.
    private var runes: [(node: SCNNode, glow: SCNNode, on: Bool, today: Bool)] = []

    // Lantern.
    private let flame: SCNNode
    private let flameMaterial: SCNMaterial
    private let lanternGlow: SCNNode
    private let lampLight = SCNNode()
    private var flameLevel: Float = 0
    private var flameColor = RGB(1.0, 0.64, 0.3)
    private var flareAt: Double = -10
    private let warm = RGB(1.0, 0.64, 0.3)

    /// A second light, for the burst when something is dug up or a level is gained.
    let burstLight = SCNNode()

    // Fireflies.
    private var motes: [(node: SCNNode, base: SIMD3<Float>, seed: Float)] = []

    init() {
        horizon = rgb(models.sky.horizon)

        moonHalo = makeGlow(color: UIColor(RGB(0.435, 0.604, 0.58)), size: 5.2)
        flameMaterial = Materials.flat(UIColor(RGB(1, 0.85, 0.54)))
        flame = SCNNode(geometry: SCNSphere(radius: 1))
        lanternGlow = makeGlow(color: UIColor(warm), size: 1)

        buildSky()
        buildLand()
        buildWeekStone()
        buildLantern()
        buildLights()
        buildMotes()
    }

    // MARK: - Building

    private func buildSky() {
        root.addChildNode(skyAnchor)

        // A dome painted dark at the top, fading to the horizon colour.
        let top = rgb(models.sky.top), mid = rgb(models.sky.mid)
        func smooth(_ a: Float, _ b: Float, _ v: Float) -> Float {
            let t = max(0, min(1, (v - a) / (b - a)))
            return t * t * (3 - 2 * t)
        }
        let rings = 48, spokes = 16
        var positions: [SCNVector3] = []
        var colors: [Float] = []
        var indices: [UInt32] = []
        for ring in 0...rings {
            let elevation = (Float(ring) / Float(rings) - 0.5) * .pi
            for spoke in 0...spokes {
                let around = Float(spoke) / Float(spokes) * 2 * .pi
                let dir = SIMD3<Float>(cos(elevation) * cos(around), sin(elevation), cos(elevation) * sin(around))
                positions.append(SCNVector3(dir * 5))
                var color = horizon
                if dir.y >= 0 {
                    color = horizon + (mid - horizon) * smooth(0, 0.11, dir.y)
                    color = color + (top - color) * smooth(0.08, 0.42, dir.y)
                }
                colors.append(contentsOf: [color.x, color.y, color.z, 1])
            }
        }
        for ring in 0..<rings {
            for spoke in 0..<spokes {
                let a = UInt32(ring * (spokes + 1) + spoke)
                let b = a + 1
                let c = a + UInt32(spokes + 1)
                let d = c + 1
                indices.append(contentsOf: [a, b, d, a, d, c])
            }
        }
        let colorSource = SCNGeometrySource(
            data: colors.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .color, vectorCount: positions.count, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16
        )
        let dome = SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions), colorSource],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let skyMaterial = Materials.flat(.white)
        skyMaterial.isDoubleSided = true
        skyMaterial.writesToDepthBuffer = false
        skyMaterial.readsFromDepthBuffer = false
        dome.materials = [skyMaterial]
        let domeNode = SCNNode(geometry: dome)
        domeNode.renderingOrder = -100
        skyAnchor.addChildNode(domeNode)

        // Stars: single pixels scattered over the half of the sky behind the hero.
        var starPositions: [SCNVector3] = []
        var starColors: [Float] = []
        let field = models.stars
        for i in 0..<field.seeds.count {
            let dir = SIMD3<Float>(field.positions[i * 3], field.positions[i * 3 + 1], field.positions[i * 3 + 2])
            starPositions.append(SCNVector3(dir * 4.8))
            let seed = field.seeds[i]
            let bright = 0.25 + seed * seed * 0.75
            starColors.append(contentsOf: [0.82 * bright, 0.9 * bright, 0.86 * bright, 1])
        }
        let starElement = SCNGeometryElement(indices: (0..<UInt32(starPositions.count)).map { $0 }, primitiveType: .point)
        starElement.pointSize = 1
        starElement.minimumPointScreenSpaceRadius = 0.5
        starElement.maximumPointScreenSpaceRadius = 0.5
        let starSource = SCNGeometrySource(
            data: starColors.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .color, vectorCount: starPositions.count, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16
        )
        let stars = SCNGeometry(sources: [SCNGeometrySource(vertices: starPositions), starSource], elements: [starElement])
        let starMaterial = SCNMaterial()
        starMaterial.lightingModel = .constant
        starMaterial.diffuse.contents = UIColor.white
        starMaterial.writesToDepthBuffer = false
        starMaterial.readsFromDepthBuffer = false
        stars.materials = [starMaterial]
        let starNode = SCNNode(geometry: stars)
        starNode.renderingOrder = -90
        skyAnchor.addChildNode(starNode)

        // Moon: a flat picture that always faces the camera, with a faint halo behind it.
        moonHalo.renderingOrder = -85
        moonHalo.geometry?.firstMaterial?.readsFromDepthBuffer = false
        root.addChildNode(moonHalo)
        let disc = SCNPlane(width: 2, height: 2)
        // A blank picture for now. `setMoon` paints the real one as soon as the date is known.
        let moonMaterial = Materials.decal(Textures.image(fromRGBA: [0, 0, 0, 0], width: 1, height: 1, scale: 1))
        moonMaterial.diffuse.magnificationFilter = .linear
        moonMaterial.diffuse.minificationFilter = .linear
        moonMaterial.readsFromDepthBuffer = false
        disc.materials = [moonMaterial]
        moon.geometry = disc
        moon.constraints = [SCNBillboardConstraint()]
        moon.renderingOrder = -80
        root.addChildNode(moon)
    }

    private func buildLand() {
        let s = models.scenery
        root.addChildNode(meshNode(s.ridgeFar))
        root.addChildNode(meshNode(s.ridgeNear))
        root.addChildNode(meshNode(s.ground))
        root.addChildNode(meshNode(s.scatter))
        root.addChildNode(meshNode(s.grass))

        let tree = meshNode(s.tree)
        tree.position = SCNVector3(-1.72, 0, -3.6)
        tree.simdOrientation = rotation(y: 0.3)
        tree.scale = SCNVector3(1.05, 1.05, 1.05)
        root.addChildNode(tree)
    }

    private func buildWeekStone() {
        let stone = meshNode(models.scenery.weekStone)
        stone.position = vec(models.places.stone)
        // The web model turns Z first, then Y.
        stone.simdOrientation = simd_quatf(angle: -0.3, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -0.045, axis: SIMD3(0, 0, 1))
        root.addChildNode(stone)

        for i in 0..<7 {
            // Monday at the bottom, Sunday at the top.
            let y = 0.3 + Float(i) * 0.235
            // The stone narrows toward the top, so its face leans back slightly.
            let depth = 0.172 - (y / 1.95) * 0.036
            let quad = SCNPlane(width: 0.2, height: 0.2)
            quad.materials = [Materials.decal(Textures.runes[i])]
            let rune = SCNNode(geometry: quad)
            rune.position = SCNVector3(0, y, depth + 0.004)
            rune.simdOrientation = rotation(x: -0.018)
            stone.addChildNode(rune)

            let glow = makeGlow(color: UIColor(RGB(0.373, 0.851, 0.706)), size: 0.62)
            glow.position = SCNVector3(0, y, depth + 0.02)
            glow.opacity = 0
            stone.addChildNode(glow)
            runes.append((rune, glow, false, false))
        }
    }

    private func buildLantern() {
        let place = models.places.lantern
        let lantern = meshNode(models.scenery.lantern)
        lantern.position = vec(place)
        lantern.simdOrientation = rotation(y: 0.5)
        root.addChildNode(lantern)

        // The flame is its own shape so its size and colour can change.
        flame.geometry?.materials = [flameMaterial]
        (flame.geometry as? SCNSphere)?.segmentCount = 8
        flame.position = SCNVector3(0, 0.11, 0)
        lantern.addChildNode(flame)

        lanternGlow.position = SCNVector3(0, 0.14, 0)
        lantern.addChildNode(lanternGlow)

        let light = SCNLight()
        light.type = .omni
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = 5
        light.attenuationFalloffExponent = 2
        lampLight.light = light
        lampLight.position = SCNVector3(place[0], 0.34, place[2])
        root.addChildNode(lampLight)
    }

    private func buildLights() {
        // Dim, cool light from everywhere.
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(RGB(0.11, 0.15, 0.16) * 1.05)
        ambient.intensity = 1000
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        root.addChildNode(ambientNode)

        // Moonlight from behind and to the right, which outlines the hero.
        let moonlight = SCNLight()
        moonlight.type = .directional
        moonlight.color = UIColor(RGB(0.4, 0.58, 0.66))
        moonlight.intensity = 1000
        let moonNode = SCNNode()
        moonNode.light = moonlight
        moonNode.position = SCNVector3(4.5, 6, -6.6)
        moonNode.look(at: SCNVector3(0, 0, 0))
        root.addChildNode(moonNode)

        let burst = SCNLight()
        burst.type = .omni
        burst.intensity = 0
        burst.attenuationStartDistance = 0
        burst.attenuationEndDistance = 4.5
        burst.attenuationFalloffExponent = 2
        burstLight.light = burst
        root.addChildNode(burstLight)
    }

    private func buildMotes() {
        let field = models.motes
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(RGB(0.85, 0.95, 0.5))
        material.blendMode = .add
        material.writesToDepthBuffer = false
        for i in 0..<field.seeds.count {
            let dot = SCNGeometry(
                sources: [SCNGeometrySource(vertices: [SCNVector3(0, 0, 0)])],
                elements: [{
                    let element = SCNGeometryElement(indices: [UInt32(0)], primitiveType: .point)
                    element.pointSize = 1
                    element.minimumPointScreenSpaceRadius = 0.5
                    element.maximumPointScreenSpaceRadius = 0.5
                    return element
                }()]
            )
            dot.materials = [material]
            let node = SCNNode(geometry: dot)
            root.addChildNode(node)
            motes.append((node, SIMD3(field.positions[i * 3], field.positions[i * 3 + 1], field.positions[i * 3 + 2]), field.seeds[i]))
        }
    }

    // MARK: - Progress

    /// `level` 0...1 is how full the flame is; `streak` picks its colour.
    func setFlame(level: Float, streak: Int) {
        flameLevel = level
        flameColor = Scenery.flameColor(streak: streak)
    }

    /// The lantern burns hotter, then stranger, as the streak grows.
    static func flameColor(streak: Int) -> RGB {
        if streak >= 100 { return RGB(0.78, 0.74, 1.0) } // moon-white
        if streak >= 30 { return RGB(0.42, 1.0, 0.8) } // foxfire
        if streak >= 7 { return RGB(1.0, 0.78, 0.42) } // white-gold
        return RGB(1.0, 0.64, 0.3) // amber
    }

    /// `done[i]` lights rune i (0 = Monday). `today` pulses gently until it is done.
    func setWeek(done: [Bool], today: Int) {
        for i in runes.indices {
            runes[i].on = i < done.count && done[i]
            runes[i].today = i == today
        }
    }

    /// 0 = new moon, 1 = full.
    func setMoon(phase: Float) {
        let rounded = (phase * 60).rounded() / 60
        guard rounded != moonPhase else { return }
        moonPhase = rounded
        moon.geometry?.firstMaterial?.diffuse.contents = Textures.moon(phase: rounded, haze: horizon)
        moonHalo.setGlow(strength: CGFloat(0.12 + rounded * 0.42))
    }

    /// A short flare of the lantern, played when a quest is completed.
    func flare(at time: Double) {
        flareAt = time
    }

    // MARK: - Every frame

    func update(time: Double, camera: SIMD3<Float>) {
        let t = Float(time)

        // Sky and moon stay centred on the camera.
        skyAnchor.simdPosition = camera
        let toMoon = moonPlace - camera
        let distance = simd_length(toMoon)
        let near: Float = 4.5
        moon.simdPosition = camera + toMoon / distance * near
        let moonScale = moonRadius * near / distance
        moon.scale = SCNVector3(moonScale, moonScale, moonScale)
        moonHalo.simdPosition = camera + toMoon / distance * (near + 0.05)
        moonHalo.scale = SCNVector3(moonScale, moonScale, moonScale)

        // Lantern. Two sine waves at different speeds make a flicker that never quite repeats.
        let flicker = 1 + sin(t * 11.3) * 0.05 + sin(t * 6.7 + 1.3) * 0.06
        let flareAmount = max(0, 1 - Float(time - flareAt) / 0.9)
        let power = (0.32 + flameLevel * 0.68) * flicker + flareAmount * 0.7
        let height = 0.022 + flameLevel * 0.05 + flareAmount * 0.03
        let width = 0.02 + flameLevel * 0.016
        flame.scale = SCNVector3(width, height * flicker, width)
        flame.position.y = 0.075 + height
        flameMaterial.diffuse.contents = UIColor(flameColor + (RGB(1, 1, 0.9) - flameColor) * 0.55)
        let glowSize = 0.9 + power * 1.1
        lanternGlow.scale = SCNVector3(glowSize, glowSize, glowSize)
        lanternGlow.setGlow(strength: CGFloat(0.25 + power * 0.42), color: UIColor(flameColor))
        // The flame shows the streak colour at full strength, but the light it throws stays
        // mostly warm. Fully green light would make the hero look like a goblin.
        let thrown = (warm + (flameColor - warm) * 0.3) * (0.5 + power * 1.25)
        lampLight.light?.color = UIColor(simd_min(thrown / max(1, max(thrown.x, max(thrown.y, thrown.z))), RGB(repeating: 1)))
        lampLight.light?.intensity = CGFloat(1000 * max(1, max(thrown.x, max(thrown.y, thrown.z))))
        lampLight.light?.attenuationEndDistance = CGFloat(3.6 + power * 2.2)

        // Runes.
        let carved = RGB(0.07, 0.082, 0.07)
        let lit = RGB(0.624, 0.961, 0.839)
        let waiting = RGB(0.851, 0.663, 0.306)
        for (i, rune) in runes.enumerated() {
            let material = rune.node.geometry?.firstMaterial
            if rune.on {
                let pulse = 0.88 + sin(t * 1.6 + Float(i)) * 0.12
                material?.multiply.contents = UIColor(lit * pulse)
                rune.glow.opacity = CGFloat(0.4 * pulse)
            } else if rune.today {
                let pulse = 0.45 + sin(t * 2.4) * 0.25
                material?.multiply.contents = UIColor(carved + (waiting - carved) * pulse)
                rune.glow.opacity = 0
            } else {
                material?.multiply.contents = UIColor(carved)
                rune.glow.opacity = 0
            }
        }

        // Fireflies drift and blink.
        for mote in motes {
            let phase = t * (0.25 + mote.seed * 0.35) + mote.seed * 30
            var p = mote.base
            p.x += sin(phase * 1.3) * 0.35
            p.y += sin(phase * 0.9 + mote.seed * 6) * 0.25
            p.z += cos(phase * 1.1) * 0.3
            mote.node.simdPosition = p
            let blink = sin(phase * 2.2) * 0.5 + 0.5
            let edge = max(0, min(1, (blink - 0.2) / 0.7))
            mote.node.opacity = CGFloat(edge * edge * (3 - 2 * edge))
        }
    }

    var horizonColor: UIColor { UIColor(horizon) }
}
