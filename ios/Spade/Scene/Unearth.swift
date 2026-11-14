import SceneKit
import UIKit
import simd

// The dig-up: how every item arrives.
//
// The ground swells, clods of earth fly, a buried lockbox pushes up through
// the soil, its lid snaps open with a burst of light, and the item rises out
// of it, turning slowly.

final class Unearth {
    let root = SCNNode()
    /// True from the moment a dig starts until it is dismissed.
    private(set) var active = false
    /// How long after `play` the item is fully presented.
    static let revealSeconds: Double = 2.3

    private let mound: SCNNode
    private let box = SCNNode()
    private let lid = SCNNode()
    private let itemPivot = SCNNode()
    private let beam: SCNNode
    private let halo: SCNNode
    private var clods: [(node: SCNNode, velocity: SIMD3<Float>, spin: SIMD3<Float>)] = []
    private var item: SCNNode?
    private var startedAt: Double = 0
    private var color = RGB(1, 1, 1)
    private let place: SIMD3<Float>

    init() {
        let models = ModelLibrary.shared
        let s = models.scenery
        place = SIMD3(models.places.dig[0], models.places.dig[1], models.places.dig[2])
        mound = meshNode(s.mound)
        beam = makeGlow(color: .white, size: 1.6)
        halo = makeGlow(color: .white, size: 1.3)

        root.simdPosition = place
        root.simdOrientation = rotation(y: 0.35)
        root.isHidden = true
        root.addChildNode(mound)

        box.addChildNode(meshNode(s.lockbox))
        // The lid is modelled with its hinge at the origin, so it can swing open.
        lid.position = SCNVector3(0, 0.24, -0.16)
        lid.addChildNode(meshNode(s.lid))
        box.addChildNode(lid)
        root.addChildNode(box)

        beam.position = SCNVector3(0, 0.5, 0)
        root.addChildNode(beam)
        root.addChildNode(itemPivot)
        itemPivot.addChildNode(halo)

        for mesh in s.clods {
            let node = meshNode(mesh)
            root.addChildNode(node)
            clods.append((node, .zero, .zero))
        }
    }

    /// Starts the sequence for an item. `color` tints the light (by rarity).
    func play(itemId: String, color: RGB, time: Double) {
        item?.removeFromParentNode()
        item = nil
        if let model = ModelLibrary.shared.items[itemId] {
            let shape = meshNode(model.display)
            // Centre the item and scale it so big and small things present at a similar size.
            let (low, high) = shape.boundingBox
            let size = SIMD3<Float>(high.x - low.x, high.y - low.y, high.z - low.z)
            let center = SIMD3<Float>(high.x + low.x, high.y + low.y, high.z + low.z) / 2
            shape.simdPosition = -center
            let holder = SCNNode()
            holder.addChildNode(shape)
            // Long thin tools get shown larger, or they would look like a twig.
            let showSize: Float = model.slot == "hand" ? 1.0 : 0.66
            let scale = showSize / max(size.x, size.y, size.z, 0.2)
            holder.scale = SCNVector3(scale, scale, scale)
            if model.slot == "hand" { holder.simdOrientation = rotation(z: -0.5) }
            itemPivot.addChildNode(holder)
            item = holder
        }

        self.color = color
        beam.setGlow(strength: 0, color: UIColor(color))
        halo.setGlow(strength: 0, color: UIColor(color))

        for i in clods.indices {
            let angle = Float(i) / Float(clods.count) * 2 * .pi + Float(i % 2) * 0.4
            let speed = 0.7 + Float(i % 3) * 0.35
            clods[i].node.simdPosition = SIMD3(cos(angle) * 0.12, 0.05, sin(angle) * 0.12)
            clods[i].velocity = SIMD3(cos(angle) * speed, 2.1 + Float(i % 4) * 0.45, sin(angle) * speed)
            clods[i].spin = SIMD3(3 + Float(i), 2 + Float(i % 5), 1 + Float(i % 3))
            clods[i].node.isHidden = true
        }

        startedAt = time
        active = true
        root.isHidden = false
    }

    /// Puts everything away again.
    func dismiss() {
        active = false
        root.isHidden = true
        item?.removeFromParentNode()
        item = nil
    }

    private func span(_ t: Float, _ from: Float, _ to: Float) -> Float {
        max(0, min(1, (t - from) / (to - from)))
    }

    private func easeOut(_ x: Float) -> Float {
        1 - pow(1 - x, 3)
    }

    /// Overshoots a little past 1 and settles back, like something landing.
    private func easeBack(_ x: Float) -> Float {
        1 + 2.2 * pow(x - 1, 3) + 1.2 * pow(x - 1, 2)
    }

    /// Advances the sequence. Returns the colour and strength of light the find throws on the scene.
    func update(time: Double, dt: Double) -> (position: SIMD3<Float>, light: RGB)? {
        guard active else { return nil }
        let t = Float(time - startedAt)
        let step = Float(dt)

        // 1. The ground swells.
        let swell = easeBack(span(t, 0, 0.4))
        mound.scale = SCNVector3(0.3 + swell * 0.7, max(0.001, swell), 0.3 + swell * 0.7)

        // 2. Clods of earth fly up and fall back.
        if t >= 0.16 {
            for i in clods.indices {
                clods[i].velocity.y -= 7.5 * step
                clods[i].node.simdPosition += clods[i].velocity * step
                clods[i].node.simdEulerAngles += clods[i].spin * step
                clods[i].node.isHidden = clods[i].node.simdPosition.y <= -0.05
            }
        }

        // 3. The lockbox pushes up through the soil, rocking as it comes.
        let rise = easeBack(span(t, 0.32, 0.95))
        let rock = (1 - span(t, 0.32, 1.25)) * sin(t * 26) * 0.07
        box.position.y = -0.36 + rise * 0.48
        box.simdOrientation = rotation(x: rock * 0.6, z: rock)

        // 4. The lid snaps open and light pours out.
        let open = easeBack(span(t, 1.05, 1.4))
        lid.simdOrientation = rotation(x: -open * 1.75)
        let light = span(t, 1.05, 1.5)
        let pulse = 0.9 + sin(t * 5) * 0.1
        beam.setGlow(strength: CGFloat(light * 0.75 * pulse))
        let beamSize = (1.2 + light * 0.9) / 1.6
        beam.scale = SCNVector3(beamSize, beamSize, beamSize)

        // 5. The item rises out, spinning quickly at first and then slowing.
        let lift = easeOut(span(t, 1.3, 2.4))
        let bob = t > 2.4 ? sin((t - 2.4) * 1.8) * 0.035 : 0
        itemPivot.position.y = 0.22 + lift * 0.86 + bob
        let grow = 0.2 + lift * 0.8
        itemPivot.scale = SCNVector3(grow, grow, grow)
        itemPivot.isHidden = t <= 1.28
        itemPivot.simdOrientation = rotation(y: t * 1.3 + (1 - lift) * 9)
        halo.setGlow(strength: CGFloat(lift * 0.42 * pulse))

        // The find lights up the hero and the ground around it.
        return (SIMD3(place.x, 0.5 + lift * 0.5, place.z + 0.2), color * (light * 1.5 * pulse))
    }
}
