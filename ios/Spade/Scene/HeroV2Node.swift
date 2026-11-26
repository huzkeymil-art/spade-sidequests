import SceneKit
import UIKit
import simd

// The new hero: the Spade digger with grown-up proportions, a painted face and the
// hooded cloak from the logo. It follows src/three/heroV2.ts step by step, so the web
// and the iPhone show the same hero in the same poses. Two ways to draw it:
//   soft  the scene's usual lighting, each shape a little darker toward its foot
//   cel   one flat colour per shape, light in flat bands, a rim where a light from
//         behind grazes an edge, and an ink outline, like a hand-painted cartoon
// Between actions the hero drifts through small, unposed moments (glancing round,
// shading the eyes to look at the moon, a fist in the air after a quest).

private let deg: Float = .pi / 180
private let down = SIMD3<Float>(0, -1, 0)
private let defaultTunic2 = "#8c7448"

/// The hero's nodes carry this bit, so taps can find them and the hero's own fill light reaches only them.
let heroCategory = 2

private enum HeroMoment { case stand, glance, sky, cheer }
private enum HoodState { case up, down, off }

// MARK: - Materials

extension Materials {
    /// Light in two flat bands with soft edges (blended back toward smooth light by `soft`),
    /// plus a thin bright rim where a light from behind grazes an edge.
    private static func celLighting(soft: Float) -> String {
        """
        #pragma body
        float celNdl = dot(_surface.normal, _light.direction);
        float celBand = smoothstep(0.06, 0.12, celNdl) * 0.5 + smoothstep(0.5, 0.56, celNdl) * 0.32;
        float celK = mix(celBand, max(celNdl, 0.0), \(soft));
        float celBack = smoothstep(-0.1, 0.4, -dot(_light.direction, _surface.view));
        float celRim = smoothstep(0.66, 0.72, 1.0 - max(dot(_surface.normal, _surface.view), 0.0)) * smoothstep(-0.1, 0.3, celNdl) * celBack;
        _lightingContribution.diffuse += _light.intensity.rgb * (celK + celRim * 0.22);
        """
    }

    private static func celSurface(soft: Float) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = Textures.atlas
        m.diffuse.magnificationFilter = .linear
        m.diffuse.minificationFilter = .linear
        m.diffuse.mipFilter = .none
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        return finish(m, extra: [.lightingModel: celLighting(soft: soft)])
    }

    /// Cel shading for clothes, gear and hair.
    static let heroCel = celSurface(soft: 0)
    /// Cel shading for skin: softer bands, because a hard line across a face reads as a bruise.
    static let heroCelSkin = celSurface(soft: 0.7)

    /// The ink line: the same shape again, pushed out a hair along its normals, drawn inside out and dark.
    static let heroInk: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.black
        m.cullMode = .front
        let push = """
        #pragma body
        float inkDepth = -(scn_node.modelViewTransform * _geometry.position).z;
        _geometry.position.xyz += normalize(_geometry.normal) * 0.00058 * max(1.0, inkDepth);
        """
        return finish(m, fragmentStart: "_output.color.rgb = float3(0.102, 0.071, 0.051);", extra: [.geometry: push])
    }()

    /// The painted face. Lit like the skin around it; the whites of the eyes and their
    /// catchlights keep a little light of their own, so the eyes still read at phone size.
    static func heroFace(cel: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = Textures.face2
        m.diffuse.magnificationFilter = .linear
        m.diffuse.minificationFilter = .linear
        m.diffuse.mipFilter = .none
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.emission.contents = UIColor.black
        m.transparencyMode = .aOne
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        let lift = """
        #pragma body
        float faceLum = dot(_surface.diffuse.rgb, float3(0.3, 0.59, 0.11));
        _surface.emission.rgb = _surface.diffuse.rgb * smoothstep(0.55, 0.9, faceLum) * 0.17;
        """
        var extra: [SCNShaderModifierEntryPoint: String] = [.surface: lift]
        if cel { extra[.lightingModel] = celLighting(soft: 0.7) }
        return finish(m, extra: extra)
    }
}

// MARK: - The rig

final class HeroV2Node: StageHero {
    let root = SCNNode()
    let charmPivot = SCNNode()

    /// Cel shading (true) or soft shading. Takes effect at the next `apply`.
    var cel = true

    private let model = ModelLibrary.shared.hero2
    private var joints: [String: SCNNode] = [:]
    private var built: [SCNNode] = []
    private let face = SCNNode()
    private let faceSoft = Materials.heroFace(cel: false)
    private let faceCel = Materials.heroFace(cel: true)
    private var faceFrame = -1
    private var charmGlow: SCNNode?
    private var dogger: SCNNode?
    private var hasCharm = false
    private var hasTool = false
    private var hasShield = false

    private var blinkAt: Double = 2
    private var blinkUntil: Double = 0
    private var hopStart: Double = -10
    private var lookAt: Double = 6
    private var lookTarget: Float = 0
    private var headYaw: Float = 0

    // The moment being played, and when the next one starts.
    private var live: HeroMoment = .stand
    private var liveUntil: Double = 0
    private var nextMoment: Double = 16
    private var last: Double = 0
    // Where the hands are heading, eased so a change of moment is a movement, not a jump.
    private var snap = true
    private var rightAt = SIMD3<Float>(repeating: 0)
    private var rightPole = SIMD3<Float>(repeating: 0)
    private var leftAt = SIMD3<Float>(repeating: 0)
    private var leftPole = SIMD3<Float>(repeating: 0)
    private var pitch: Float = 0

    init() {
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
        root.simdScale = SIMD3(repeating: model.fit)
        joints["hat"]?.simdScale = SIMD3(repeating: model.hatScale)
        joints["shield"]?.simdScale = SIMD3(repeating: model.shieldScale)
        root.addChildNode(charmPivot)

        face.geometry = HeroV2Node.faceGeometry(model.face)
        face.categoryBitMask = 1 | heroCategory
        face.renderingOrder = 2
        joints["head"]?.addChildNode(face)
        setFrame(0)
    }

    private static func faceGeometry(_ patch: FacePatch) -> SCNGeometry {
        let count = patch.p.count / 3
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        for i in 0..<count {
            positions.append(SCNVector3(patch.p[i * 3], patch.p[i * 3 + 1], patch.p[i * 3 + 2]))
            normals.append(SCNVector3(patch.n[i * 3], patch.n[i * 3 + 1], patch.n[i * 3 + 2]))
            // Pictures count rows from the top, so the top of the patch is row 0.
            uvs.append(CGPoint(x: CGFloat(patch.uv[i * 2]), y: CGFloat(1 - patch.uv[i * 2 + 1])))
        }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs)],
            elements: [SCNGeometryElement(indices: patch.i, primitiveType: .triangles)]
        )
    }

    /// Shows one of the face's pictures: 0 open, 1 glancing right, 2 glancing left, 3 closed.
    private func setFrame(_ frame: Int) {
        let material = cel ? faceCel : faceSoft
        if face.geometry?.firstMaterial !== material { face.geometry?.materials = [material] }
        guard frame != faceFrame else { return }
        faceFrame = frame
        let share = 1 / Float(model.face.frames)
        let transform = SCNMatrix4Translate(SCNMatrix4MakeScale(1, share, 1), 0, Float(frame) * share, 0)
        faceSoft.diffuse.contentsTransform = transform
        faceCel.diffuse.contentsTransform = transform
    }

    private func mark(_ node: SCNNode) {
        node.categoryBitMask = 1 | heroCategory
    }

    private func attachNode(_ joint: String, _ node: SCNNode, outline: Bool) {
        guard let parent = joints[joint] else { return }
        mark(node)
        if cel, outline, let geometry = node.geometry?.copy() as? SCNGeometry {
            geometry.materials = [Materials.heroInk]
            let ink = SCNNode(geometry: geometry)
            mark(ink)
            node.addChildNode(ink)
        }
        parent.addChildNode(node)
        built.append(node)
    }

    private func attach(_ joint: String, _ pieces: [Piece], palette: [String: RGB], outline: Bool = true, skin: Bool = false) {
        var buffer = MeshBuffer()
        for piece in pieces { buffer.add(piece, palette: palette, cel: cel) }
        guard !buffer.isEmpty else { return }
        let lit = cel ? (skin ? Materials.heroCelSkin : Materials.heroCel) : Materials.lit
        attachNode(joint, buffer.node(lit: lit), outline: outline)
    }

    private func attach(_ joint: String, mesh: MeshData?) {
        guard let mesh else { return }
        var buffer = MeshBuffer()
        buffer.add(mesh)
        attachNode(joint, buffer.node(lit: cel ? Materials.heroCel : Materials.lit), outline: true)
    }

    func apply(look: HeroLook, gear: [String: String]) {
        for node in built { node.removeFromParentNode() }
        built = []
        charmPivot.childNodes.forEach { $0.removeFromParentNode() }
        charmGlow = nil
        dogger?.removeFromParentNode(); dogger = nil
        snap = true
        faceFrame = -1
        setFrame(0)

        let library = ModelLibrary.shared
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
            "tunic": rgb(body?.tunic ?? defaultTunic2),
            "sleeve": rgb(body?.sleeve ?? body?.tunic ?? defaultTunic2),
            "cloak": body?.cloak.map { rgb($0) } ?? rgb(model.cloakColor),
        ]

        attach("torso", model.torso, palette: palette)
        // A hat puts the hood down; a hat that is itself a hood replaces it.
        let hood: HoodState = hat == nil ? (look.hoodDown ? .down : .up) : (hat?.hair == "hide" ? .off : .down)
        attach("torso", hood == .down ? model.cloakHoodDown : model.cloakHoodUp, palette: palette)
        if hood == .up { attach("head", model.hood, palette: palette) }
        // One sleeve down, one rolled up: a small asymmetry that makes the outfit look worn, not issued.
        attach("armR", model.armR, palette: palette)
        attach("elbowR", model.elbowR, palette: palette)
        attach("armL", model.armL, palette: palette)
        attach("elbowL", model.elbowL, palette: palette)
        attach("legR", model.thigh, palette: palette)
        attach("kneeR", model.shinR, palette: palette)
        attach("legL", model.thigh, palette: palette)
        attach("kneeL", model.shinL, palette: palette)
        attach("tail1", model.tail1, palette: palette)
        attach("tail2", model.tail2, palette: palette)

        // The head's outline goes round the whole shape; the nose and ears get none, so they
        // read as part of the face instead of as stuck-on pieces.
        attach("head", model.headShell, palette: palette, skin: true)
        attach("head", model.headFeatures, palette: palette, outline: false, skin: true)
        if let locks = model.hair[look.hairStyle] {
            let hairMode = hat?.hair ?? "keep"
            let ids = hood == .up ? locks.hooded : hairMode == "hide" ? [] : hairMode == "keep" ? locks.top : locks.under
            attach("head", ids.compactMap { model.locks.indices.contains($0) ? model.locks[$0] : nil }, palette: palette)
        }

        func worn(_ found: ItemModel?) -> MeshData? {
            guard let found else { return nil }
            return cel ? (found.worn2?.cel ?? found.mesh) : (found.worn2?.soft ?? found.mesh)
        }
        attach("hat", mesh: worn(hat))
        attach("tool", mesh: worn(tool))
        attach("shield", mesh: worn(shield))
        hasTool = tool != nil
        hasShield = shield != nil

        if gear["charm"] == "dogger", let mesh = charm?.mesh {
            // The dog trots alongside instead of circling the hero's head.
            var buffer = MeshBuffer()
            buffer.add(mesh)
            let pet = buffer.node(lit: cel ? Materials.heroCel : Materials.lit)
            mark(pet)
            pet.position = SCNVector3(-0.58, 0, 0.22)
            root.addChildNode(pet)
            dogger = pet
        }
        hasCharm = charm != nil && dogger == nil
        if dogger == nil, let charm, let mesh = charm.mesh {
            var buffer = MeshBuffer()
            buffer.add(mesh)
            let node = buffer.node(lit: cel ? Materials.heroCel : Materials.lit)
            mark(node)
            node.simdScale = SIMD3(repeating: 0.85)
            charmPivot.addChildNode(node)
            if let glow = charm.glow {
                let sprite = makeGlow(color: UIColor(rgb(glow)), size: 0.55)
                charmPivot.addChildNode(sprite)
                charmGlow = sprite
            }
        }
        update(time: last)
    }

    /// A little jump and a fist in the air, played when a quest is finished.
    func cheer(at time: Double) {
        hopStart = time
    }

    // MARK: Posing

    /// Two-bone reach: turns the shoulder and elbow so the palm lands on `target` (in the shoulder's parent's space).
    private func reach(_ shoulder: SCNNode, _ elbow: SCNNode, target: SIMD3<Float>, pole: SIMD3<Float>, a: Float, b: Float) {
        let origin = shoulder.simdPosition
        let toTarget = target - origin
        let d = min(max(simd_length(toTarget), abs(a - b) + 1e-3), a + b - 1e-3)
        let dir = simd_normalize(toTarget)
        let bendAt = acos(min(max((a * a + d * d - b * b) / (2 * a * d), -1), 1))
        var axis = simd_cross(dir, pole)
        axis = simd_length(axis) < 1e-5 ? SIMD3(1, 0, 0) : simd_normalize(axis)
        let upper = simd_act(simd_quatf(angle: bendAt, axis: axis), dir)
        let elbowAt = origin + upper * a
        let lower = simd_normalize(target - elbowAt)
        let turn = simd_quatf(from: down, to: upper)
        shoulder.simdOrientation = turn
        elbow.simdOrientation = simd_quatf(from: down, to: simd_act(turn.inverse, lower))
    }

    /// Which moment to play now. Now and then the hero looks up at the moon; after a quest, a fist goes up.
    private func moment(at time: Double) -> HeroMoment {
        if time - hopStart >= 0 && time - hopStart < 1.4 { return .cheer }
        if time < liveUntil { return live }
        if time > nextMoment {
            live = hasShield ? .glance : .sky
            liveUntil = time + 3.2 + Double.random(in: 0...1.6)
            nextMoment = liveUntil + 18 + Double.random(in: 0...20)
            return live
        }
        return .stand
    }

    /// The relaxed stance: weight on the right leg, the left knee soft, shoulders and hips tilted against each other.
    private func pose(time: Double, breathe: Float, lift: Float, moment m: HeroMoment, ease: Float) {
        guard let hips = joints["hips"], let torso = joints["torso"], let head = joints["head"],
              let armR = joints["armR"], let elbowR = joints["elbowR"], let armL = joints["armL"], let elbowL = joints["elbowL"]
        else { return }
        let shift = Float(sin(time * 0.45)) * 0.6
        hips.simdOrientation = rotation(z: (-2.5 + shift) * deg)
        torso.simdOrientation = rotation(x: breathe * 0.004, y: -4 * deg, z: (4 - shift * 1.2) * deg)
        joints["legR"]?.simdOrientation = rotation(y: -4 * deg, z: (2.5 - shift) * deg)
        joints["kneeR"]?.simdOrientation = simd_quatf(angle: 0, axis: SIMD3(1, 0, 0))
        joints["legL"]?.simdOrientation = rotation(x: -9 * deg, y: 14 * deg, z: (-3 - shift) * deg)
        joints["kneeL"]?.simdOrientation = rotation(x: 16 * deg)

        let k = snap ? 1 : ease
        let headPitch: Float = m == .sky ? -24 : m == .cheer ? -8 : 0
        pitch += (headPitch - pitch) * k
        let headTilt: Float = m == .glance ? 6 : -4
        head.simdOrientation = rotation(x: pitch * deg + breathe * 0.01 - lift * 0.4, y: headYaw, z: headTilt * deg)

        // Arms reach for a spot in the torso's own space.
        let a = model.limbs.upperArm
        let b = model.limbs.forearm
        let right: SIMD3<Float>
        var rightPoleGoal = SIMD3<Float>(-0.4, 0, -1)
        if hasTool, let tool = joints["tool"] {
            // Hold the spade by its grip.
            right = torso.simdConvertPosition(SIMD3(0, 0.95, 0), from: tool)
            rightPoleGoal = SIMD3(-0.8, 0, -0.5)
        } else if m == .cheer {
            right = SIMD3(-0.26, 0.98, 0.08)
            rightPoleGoal = SIMD3(-1, 0, 0.3)
        } else {
            right = SIMD3(-0.205, -0.02 + breathe * 0.004, 0.035)
        }
        // The grip moves with the spade, so that hand follows it exactly.
        let kr = hasTool ? 1 : k
        rightAt += (right - rightAt) * kr
        rightPole += (rightPoleGoal - rightPole) * kr
        reach(armR, elbowR, target: rightAt, pole: rightPole, a: a, b: b)

        if hasShield {
            armL.simdOrientation = rotation(x: -30 * deg, z: 16 * deg)
            elbowL.simdOrientation = rotation(x: -40 * deg)
            return
        }
        let left: SIMD3<Float>
        let leftPoleGoal: SIMD3<Float>
        if m == .sky {
            // Shading the eyes to look up at the moon.
            left = SIMD3(0.02, 0.875, 0.15)
            leftPoleGoal = SIMD3(1, 0.2, 0.1)
        } else {
            // Hand resting on the hip, elbow out and back.
            left = SIMD3(0.172, 0.085 + breathe * 0.003, 0.06)
            leftPoleGoal = SIMD3(0.55, 0, -0.85)
        }
        leftAt += (left - leftAt) * k
        leftPole += (leftPoleGoal - leftPole) * k
        reach(armL, elbowL, target: leftAt, pole: leftPole, a: a, b: b)
    }

    func update(time: Double) {
        let t = Float(time)
        let breathe = sin(t * 1.9)
        let hop = Float(time - hopStart)
        var lift: Float = 0
        var squash: Float = 0
        if hop >= 0 && hop < 0.62 {
            let p = hop / 0.62
            lift = sin(p * .pi) * 0.26
            squash = p < 0.12 ? -sin(p / 0.12 * .pi) * 0.08 : p > 0.9 ? -sin((p - 0.9) / 0.1 * .pi) * 0.06 : 0.04
        }
        joints["hips"]?.position.y = 0.79 + lift + breathe * 0.004
        joints["torso"]?.scale = SCNVector3(1 - squash * 0.5, 1 + squash + breathe * 0.008, 1 - squash * 0.5)

        // Now and then the hero glances to one side. The eyes get there first.
        if time > lookAt {
            if lookTarget == 0 {
                lookTarget = Bool.random() ? -0.5 : 0.42
                lookAt = time + 1.2 + Double.random(in: 0...1.4)
            } else {
                lookTarget = 0
                lookAt = time + 4 + Double.random(in: 0...5)
            }
        }
        headYaw += (lookTarget - headYaw) * 0.08
        let dt = min(0.1, max(0, time - last))
        last = time
        pose(time: time, breathe: breathe, lift: lift, moment: moment(at: time), ease: Float(1 - exp(-dt * 6)))
        snap = false

        joints["tail1"]?.simdOrientation = rotation(x: sin(t * 1.3) * 0.12, z: 14 * deg + sin(t * 1.7) * 0.16 + lift * 1.4)
        joints["tail2"]?.simdOrientation = rotation(x: sin(t * 1.3 + 0.9) * 0.18, z: -8 * deg + sin(t * 1.7 - 0.8) * 0.26)

        if time > blinkAt {
            blinkUntil = time + 0.13
            blinkAt = time + 2.2 + Double.random(in: 0...3.5)
        }
        let leading = lookTarget - headYaw
        let frame = time < blinkUntil ? 3 : abs(leading) > 0.12 ? (leading > 0 ? 2 : 1) : 0
        setFrame(frame)

        dogger?.eulerAngles.y = sin(t * 0.8) * 0.12
        dogger?.position.y = max(0, sin(t * 2)) * 0.008
        if hasCharm {
            let a = t * 0.9
            charmPivot.position = SCNVector3(cos(a) * 0.5, 1.55 + sin(t * 2.1) * 0.05 + lift, sin(a) * 0.5)
            charmPivot.simdOrientation = rotation(y: -a + .pi / 2)
            charmGlow?.setGlow(strength: CGFloat(0.5 + sin(t * 5) * 0.08))
        }
    }
}
