import Metal
import SceneKit
import UIKit
import simd

// The icon camera. Every icon in the app is a tiny photo of a real 3D model:
// the model is drawn very small through the same dot-pattern finish as the
// main scene, then shown enlarged with hard pixels.

@MainActor
final class IconForge {
    static let shared = IconForge()

    private let renderer: SCNRenderer
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let holder = SCNNode()
    private var cache: [String: UIImage] = [:]
    private var portraitHero: HeroNode?

    private init() {
        renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        // A colour no model uses. It is swapped for "see-through" after each photo.
        scene.background.contents = UIColor(red: 1, green: 0, blue: 1, alpha: 1)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 0.1
        camera.zFar = 20
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 8)
        scene.rootNode.addChildNode(cameraNode)
        renderer.pointOfView = cameraNode
        scene.rootNode.addChildNode(holder)

        // Studio lighting: soft fill, a key light from the upper left, a warm glint from below.
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(RGB(0.56, 0.57, 0.56))
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(RGB(1.0, 0.97, 0.9))
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-4.5, 7, 5.5)
        keyNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .omni
        fill.color = UIColor(RGB(0.5, 0.3, 0.14))
        fill.attenuationEndDistance = 9
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(2.2, -1.2, 2.5)
        scene.rootNode.addChildNode(fillNode)
    }

    /// Icon for an inventory item.
    func item(_ id: String, res: Int = 30) -> UIImage {
        cached("item:\(id):\(res)") {
            guard let model = ModelLibrary.shared.items[id] else { return UIImage() }
            let tall = model.slot == "hand"
            return shoot(meshNode(model.display), res: res, tilt: tall ? SIMD3(0.18, -0.5, -0.7) : SIMD3(0.3, -0.55, 0))
        }
    }

    /// Icon for one of the little props (tab icons, quest kinds, and so on).
    func prop(_ name: String, res: Int = 22) -> UIImage {
        cached("prop:\(name):\(res)") {
            guard let mesh = ModelLibrary.shared.props[name] else { return UIImage() }
            return shoot(meshNode(mesh), res: res, tilt: SIMD3(0.25, -0.5, 0))
        }
    }

    /// A head-and-shoulders picture of the hero as they currently look.
    func portrait(look: HeroLook, gear: [String: String], res: Int = 24) -> UIImage {
        let key = "portrait:\(look.skin):\(look.hair):\(look.hairStyle):\(look.scarf):\(gear["head"] ?? ""):\(gear["body"] ?? ""):\(res)"
        return cached(key) {
            let hero = portraitHero ?? HeroNode()
            portraitHero = hero
            var worn: [String: String] = [:]
            worn["head"] = gear["head"]
            worn["body"] = gear["body"]
            hero.apply(look: look, gear: worn)
            hero.root.simdOrientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
            let frame = (low: SIMD3<Float>(-0.42, 0.86, -0.4), high: SIMD3<Float>(0.42, 1.7, 0.4))
            return shoot(hero.root, res: res, tilt: SIMD3(0.06, -0.38, 0), frame: frame)
        }
    }

    private func cached(_ key: String, _ make: () -> UIImage) -> UIImage {
        if let hit = cache[key] { return hit }
        let image = make()
        cache[key] = image
        return image
    }

    /// Photographs `subject`, turned by `tilt` (radians around X, Y, Z), on a see-through background.
    private func shoot(_ subject: SCNNode, res: Int, tilt: SIMD3<Float>, frame: (low: SIMD3<Float>, high: SIMD3<Float>)? = nil) -> UIImage {
        // Centre the subject and zoom so it fills the picture.
        let bounds: (low: SIMD3<Float>, high: SIMD3<Float>)
        if let frame {
            bounds = frame
        } else {
            let (low, high) = subject.boundingBox
            bounds = (SIMD3(low.x, low.y, low.z), SIMD3(high.x, high.y, high.z))
        }
        let center = (bounds.low + bounds.high) / 2
        let wrapper = SCNNode()
        wrapper.addChildNode(subject)
        subject.simdPosition = -center
        // Turn around Y first, then X, then Z, as the web version does.
        let turn = simd_quatf(angle: tilt.z, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: tilt.x, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: tilt.y, axis: SIMD3(0, 1, 0))
        wrapper.simdOrientation = turn
        holder.addChildNode(wrapper)

        var reach: Float
        if frame != nil {
            reach = max(bounds.high.x - bounds.low.x, bounds.high.y - bounds.low.y) / 2
        } else {
            // After turning, measure again so nothing pokes out of the picture.
            reach = 0.01
            for corner in 0..<8 {
                let p = SIMD3<Float>(
                    corner & 1 == 0 ? bounds.low.x : bounds.high.x,
                    corner & 2 == 0 ? bounds.low.y : bounds.high.y,
                    corner & 4 == 0 ? bounds.low.z : bounds.high.z
                ) - center
                let turned = turn.act(p)
                reach = max(reach, abs(turned.x), abs(turned.y))
            }
        }
        cameraNode.camera?.orthographicScale = Double(reach * 1.06)

        let photo = renderer.snapshot(atTime: 0, with: CGSize(width: res, height: res), antialiasingMode: .none)

        subject.removeFromParentNode()
        subject.simdPosition = .zero
        wrapper.removeFromParentNode()

        return cutOut(photo, res: res)
    }

    /// Redraws the photo at exactly `res` pixels and makes the background colour see-through.
    private func cutOut(_ photo: UIImage, res: Int) -> UIImage {
        guard let source = photo.cgImage else { return photo }
        var pixels = [UInt8](repeating: 0, count: res * res * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: res,
                height: res,
                bitsPerComponent: 8,
                bytesPerRow: res * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(source, in: CGRect(x: 0, y: 0, width: res, height: res))
            return true
        }
        guard drawn else { return photo }
        var i = 0
        while i < pixels.count {
            if pixels[i] > 235 && pixels[i + 1] < 24 && pixels[i + 2] > 235 {
                pixels[i] = 0
                pixels[i + 1] = 0
                pixels[i + 2] = 0
                pixels[i + 3] = 0
            }
            i += 4
        }
        return Textures.image(fromRGBA: pixels, width: res, height: res)
    }
}
