import SceneKit
import UIKit
import simd

// The digger: a small skeleton of joints with shapes hanging off them, plus
// the idle animation (breathing, blinking, glancing around, a swaying scarf).

struct HeroLook: Equatable {
    var skin: String
    var hair: String
    var hairStyle: String
    var scarf: String

    /// Turns the saved palette indexes into real colours.
    init(_ hero: HeroSave) {
        let looks = Catalog.looks
        func pick(_ list: [String], _ index: Int) -> String {
            list.indices.contains(index) ? list[index] : list[0]
        }
        skin = pick(looks.skin, hero.skin)
        hair = pick(looks.hair, hero.hair)
        hairStyle = pick(looks.hairStyles, hero.hairStyle)
        scarf = pick(looks.scarf, hero.scarf)
    }
}

private let deg: Float = .pi / 180
private let defaultTunic = "#8c7448"

final class HeroNode {
    let root = SCNNode()
    /// The charm circles the hero on its own pivot.
    let charmPivot = SCNNode()

    private var joints: [String: SCNNode] = [:]
    private var built: [SCNNode] = []
    private let face: SCNNode
    private let faceMaterial: SCNMaterial
    private var charmGlow: SCNNode?
    private var hasCharm = false
    private var dogger: SCNNode?

    // Resting arm angles (turn around X, turn around Z), which depend on what is held.
    private var armR: (x: Float, z: Float) = (-10 * deg, -13 * deg)
    private var armL: (x: Float, z: Float) = (-10 * deg, 13 * deg)

    private var blinkAt: Double = 2
    private var blinkUntil: Double = 0
    private var hopStart: Double = -10
    private var lookAt: Double = 6
    private var lookTarget: Float = 0
    private var headYaw: Float = 0

    init() {
        let model = ModelLibrary.shared.hero
        faceMaterial = Materials.decal(Textures.faceOpen)
        face = SCNNode(geometry: HeroNode.faceGeometry(model.head))
        face.geometry?.materials = [faceMaterial]

        for spec in model.joints {
            let node = SCNNode()
            node.name = spec.name
            node.position = vec(spec.at)
            if let rot = spec.rot {
                node.simdOrientation = rotation(x: rot[0] * deg, y: rot[1] * deg, z: rot[2] * deg)
            }
            joints[spec.name] = node
            if let parent = spec.parent, let parentNode = joints[parent] {
                parentNode.addChildNode(node)
            } else {
                root.addChildNode(node)
            }
        }
        root.addChildNode(charmPivot)
        joints["head"]?.addChildNode(face)
    }

    /// The eyes: a small curved patch that hugs the front of the head.
    private static func faceGeometry(_ head: HeadSpec) -> SCNGeometry {
        let cols = 8, rows = 4
        let width: Float = 0.37, height: Float = 0.185
        let centerY = head.center[1] - 0.005
        var positions: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [UInt32] = []
        for j in 0...rows {
            for i in 0...cols {
                let u = Float(i) / Float(cols)
                let v = Float(j) / Float(rows)
                let x = (u - 0.5) * width
                let y = centerY + (v - 0.5) * height
                let nx = x / head.radius[0]
                let ny = (y - head.center[1]) / head.radius[1]
                let z = head.radius[2] * max(0, 1 - nx * nx - ny * ny).squareRoot() + 0.006
                positions.append(SCNVector3(x, y, z))
                // Pictures count rows from the top, so the top of the patch is row 0.
                uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(1 - v)))
            }
        }
        for j in 0..<rows {
            for i in 0..<cols {
                let a = UInt32(j * (cols + 1) + i)
                let b = a + 1
                let c = a + UInt32(cols + 1)
                let d = c + 1
                indices.append(contentsOf: [a, b, d, a, d, c])
            }
        }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(textureCoordinates: uvs)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }

    private func attach(_ joint: String, _ buffer: MeshBuffer) {
        guard !buffer.isEmpty, let parent = joints[joint] else { return }
        let node = buffer.node()
        parent.addChildNode(node)
        built.append(node)
    }

    /// Rebuilds the hero from a look (skin, hair, scarf) and the gear being worn.
    func apply(look: HeroLook, gear: [String: String]) {
        for node in built { node.removeFromParentNode() }
        built = []
        charmPivot.childNodes.forEach { $0.removeFromParentNode() }
        charmGlow = nil
        dogger?.removeFromParentNode(); dogger = nil

        let library = ModelLibrary.shared
        let model = library.hero
        func item(_ slot: String) -> ItemModel? {
            guard let id = gear[slot], let found = library.items[id], found.slot == slot else { return nil }
            return found
        }
        let body = item("body")
        let hat = item("head")
        let tool = item("hand")
        let shield = item("shield")
        let charm = item("charm")

        let palette: [String: RGB] = [
            "skin": rgb(look.skin),
            "hair": rgb(look.hair),
            "scarf": rgb(look.scarf),
            "tunic": rgb(body?.tunic ?? defaultTunic),
            "sleeve": rgb(body?.sleeve ?? body?.tunic ?? defaultTunic),
        ]
        func buffer(_ chunks: [Chunk], extra: MeshData? = nil) -> MeshBuffer {
            var out = MeshBuffer()
            for chunk in chunks { out.add(chunk, palette: palette) }
            if let extra { out.add(extra) }
            return out
        }

        attach("torso", buffer(model.torso, extra: body?.torso))
        attach("armR", buffer(model.armR, extra: body?.shoulderR))
        attach("armL", buffer(model.armL, extra: body?.shoulderL))
        attach("legR", buffer(model.leg))
        attach("legL", buffer(model.leg))
        attach("tail1", buffer(model.tail1))
        attach("tail2", buffer(model.tail2))

        let hair = model.hair[look.hairStyle]
        let hairMode = hat?.hair ?? "keep"
        var headChunks = model.headParts
        if hairMode != "hide" { headChunks += hair?.under ?? [] }
        if hairMode == "keep" { headChunks += hair?.top ?? [] }
        attach("head", buffer(headChunks))

        func single(_ mesh: MeshData?) -> MeshBuffer {
            var out = MeshBuffer()
            if let mesh { out.add(mesh) }
            return out
        }
        attach("hat", single(hat?.mesh))
        attach("tool", single(tool?.mesh))
        attach("shield", single(shield?.mesh))

        // With an empty hand the arm relaxes; holding a tool it reaches forward to grip.
        armR = tool != nil ? (-62 * deg, -20 * deg) : (-10 * deg, -13 * deg)
        armL = shield != nil ? (-34 * deg, 22 * deg) : (-10 * deg, 13 * deg)

        if gear["charm"] == "dogger", let mesh = charm?.mesh {
            let pet = meshNode(mesh); pet.position = SCNVector3(-0.52, 0, 0.2)
            root.addChildNode(pet); dogger = pet
        }
        hasCharm = charm != nil && dogger == nil
        if dogger == nil, let charm, let mesh = charm.mesh {
            charmPivot.addChildNode(meshNode(mesh))
            if let glow = charm.glow {
                let sprite = makeGlow(color: UIColor(rgb(glow)), size: 0.5)
                charmPivot.addChildNode(sprite)
                charmGlow = sprite
            }
        }
    }

    /// A little jump, played when a quest is finished.
    func cheer(at time: Double) {
        hopStart = time
    }

    func update(time: Double) {
        let t = Float(time)
        dogger?.eulerAngles.y = sin(t * 0.8) * 0.12
        dogger?.position.y = max(0, sin(t * 2)) * 0.008
        let breathe = sin(t * 1.9)

        // Hop: a quick squash, a jump, and a landing.
        let hop = Float(time - hopStart)
        var lift: Float = 0
        var squash: Float = 0
        var raise: Float = 0
        if hop >= 0 && hop < 0.62 {
            let p = hop / 0.62
            lift = sin(p * .pi) * 0.26
            raise = sin(p * .pi)
            if p < 0.12 {
                squash = -sin(p / 0.12 * .pi) * 0.08
            } else if p > 0.9 {
                squash = -sin((p - 0.9) / 0.1 * .pi) * 0.06
            } else {
                squash = 0.04
            }
        }

        joints["hips"]?.position.y = 0.4 + lift + breathe * 0.004
        if let torso = joints["torso"] {
            torso.scale = SCNVector3(1 - squash * 0.5, 1 + squash + breathe * 0.012, 1 - squash * 0.5)
            torso.simdOrientation = rotation(z: sin(t * 0.7) * 0.012)
        }

        // Now and then the hero glances to one side.
        if time > lookAt {
            if lookTarget == 0 {
                lookTarget = Bool.random() ? -0.5 : 0.42
                lookAt = time + 1.2 + Double.random(in: 0...1.4)
            } else {
                lookTarget = 0
                lookAt = time + 4 + Double.random(in: 0...5)
            }
        }
        headYaw += (lookTarget - headYaw) * 0.12
        joints["head"]?.simdOrientation = rotation(x: sin(t * 1.9 + 0.6) * 0.02 - lift * 0.5, y: headYaw, z: sin(t * 0.9) * 0.015)

        // Arms: follow the breathing; raise the free arm during a hop.
        joints["armR"]?.simdOrientation = rotation(x: armR.x + breathe * 0.012, z: armR.z)
        joints["armL"]?.simdOrientation = rotation(x: armL.x + breathe * 0.015 - raise * 2.2, z: armL.z + raise * 0.5)

        // Scarf tail swings like a slow pendulum.
        joints["tail1"]?.simdOrientation = rotation(x: sin(t * 1.3) * 0.14, z: 24 * deg + sin(t * 1.7) * 0.2 + lift * 1.6)
        joints["tail2"]?.simdOrientation = rotation(x: sin(t * 1.3 + 0.9) * 0.2, z: -10 * deg + sin(t * 1.7 - 0.8) * 0.3)

        // Blink by swapping to the closed-eyes picture.
        if time > blinkAt {
            blinkUntil = time + 0.13
            blinkAt = time + 2.2 + Double.random(in: 0...3.5)
        }
        let wanted = time < blinkUntil ? Textures.faceClosed : Textures.faceOpen
        if (faceMaterial.diffuse.contents as? UIImage) !== wanted {
            faceMaterial.diffuse.contents = wanted
        }

        // Charm: circles the head, bobbing as it goes.
        if hasCharm {
            let a = t * 0.9
            charmPivot.position = SCNVector3(cos(a) * 0.52, 1.28 + sin(t * 2.1) * 0.06 + lift, sin(a) * 0.52)
            charmPivot.simdOrientation = rotation(y: -a + .pi / 2)
            charmGlow?.setGlow(strength: CGFloat(0.5 + sin(t * 5) * 0.08))
        }
    }
}
