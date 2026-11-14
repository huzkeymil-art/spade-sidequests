import SceneKit
import UIKit
import simd

// Turns the numbers in models.json into shapes SceneKit can draw, and holds
// the materials (how surfaces react to light) that every shape shares.

typealias RGB = SIMD3<Float>

/// "#rrggbb" to three numbers between 0 and 1.
func rgb(_ hex: String) -> RGB {
    var value: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
    return RGB(Float((value >> 16) & 0xff), Float((value >> 8) & 0xff), Float(value & 0xff)) / 255
}

func rgb(_ parts: [Float]) -> RGB {
    RGB(parts[0], parts[1], parts[2])
}

extension UIColor {
    convenience init(_ c: RGB, alpha: CGFloat = 1) {
        self.init(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: alpha)
    }
}

/// The darker "bottom" colour of a part. Shadows lean slightly cool, the way moonlit shade does.
func shade(_ c: RGB) -> RGB {
    RGB(c.x * 0.6, c.y * 0.66, c.z * 0.7)
}

func vec(_ a: [Float]) -> SCNVector3 {
    SCNVector3(a[0], a[1], a[2])
}

/// A rotation given as turns around X, Y and Z in radians, applied X first. (Matches the web models.)
func rotation(x: Float = 0, y: Float = 0, z: Float = 0) -> simd_quatf {
    simd_quatf(angle: z, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: y, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: x, axis: SIMD3(1, 0, 0))
}

/// Collects one or more shapes, then becomes a single piece of geometry.
struct MeshBuffer {
    private var positions: [SCNVector3] = []
    private var normals: [SCNVector3] = []
    private var uvs: [CGPoint] = []
    private var colors: [Float] = []
    private var litIndices: [UInt32] = []
    private var glowIndices: [UInt32] = []

    var isEmpty: Bool { positions.isEmpty }

    /// Adds a shape whose colours are already baked in.
    mutating func add(_ mesh: MeshData) {
        add(mesh) { i in
            guard let c = mesh.c else { return RGB(1, 0, 1) }
            return RGB(c[i * 3], c[i * 3 + 1], c[i * 3 + 2])
        }
    }

    /// Adds a piece of the hero, painting it from the player's chosen colours where needed.
    mutating func add(_ chunk: Chunk, palette: [String: RGB]) {
        guard let role = chunk.role, let top = palette[role], let t = chunk.mesh.t else {
            add(chunk.mesh)
            return
        }
        let bottom = chunk.flat ? top : shade(top)
        add(chunk.mesh) { i in bottom + (top - bottom) * t[i] }
    }

    private mutating func add(_ mesh: MeshData, color: (Int) -> RGB) {
        let base = UInt32(positions.count)
        let count = mesh.p.count / 3
        for i in 0..<count {
            positions.append(SCNVector3(mesh.p[i * 3], mesh.p[i * 3 + 1], mesh.p[i * 3 + 2]))
            normals.append(SCNVector3(mesh.n[i * 3], mesh.n[i * 3 + 1], mesh.n[i * 3 + 2]))
            uvs.append(CGPoint(x: CGFloat(mesh.uv[i * 2]), y: CGFloat(mesh.uv[i * 2 + 1])))
            // The texture is stored a little dark; this brings mid-grey back up to "no change".
            let c = color(i) * 1.25
            colors.append(contentsOf: [c.x, c.y, c.z, 1])
        }
        var k = 0
        while k + 2 < mesh.i.count {
            let a = mesh.i[k], b = mesh.i[k + 1], c = mesh.i[k + 2]
            // A triangle glows if its first corner does (parts are all-or-nothing).
            if mesh.e[Int(a)] >= 0.5 {
                glowIndices.append(contentsOf: [base + a, base + b, base + c])
            } else {
                litIndices.append(contentsOf: [base + a, base + b, base + c])
            }
            k += 3
        }
    }

    func geometry() -> SCNGeometry {
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
        var elements: [SCNGeometryElement] = []
        var materials: [SCNMaterial] = []
        if !litIndices.isEmpty {
            elements.append(SCNGeometryElement(indices: litIndices, primitiveType: .triangles))
            materials.append(Materials.lit)
        }
        if !glowIndices.isEmpty {
            elements.append(SCNGeometryElement(indices: glowIndices, primitiveType: .triangles))
            materials.append(Materials.glowing)
        }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs),
                colorSource,
            ],
            elements: elements
        )
        geometry.materials = materials
        return geometry
    }

    func node() -> SCNNode {
        SCNNode(geometry: geometry())
    }
}

func meshNode(_ mesh: MeshData) -> SCNNode {
    var buffer = MeshBuffer()
    buffer.add(mesh)
    return buffer.node()
}

/// Loads a picture that ships inside the app.
func bundleImage(_ name: String) -> UIImage {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = UIImage(contentsOfFile: url.path) else {
        fatalError("\(name).png is missing from the app")
    }
    return image
}

/// Cuts a rectangle (in pixels) out of a picture.
func crop(_ image: UIImage, x: Int, y: Int, width: Int, height: Int) -> UIImage {
    guard let cg = image.cgImage?.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else { return image }
    return UIImage(cgImage: cg)
}

enum Materials {
    /// How many shades each colour channel may use. Fewer shades make the dot pattern stronger.
    static var ditherLevels: Float = 22 {
        didSet {
            for material in all { material.setValue(NSNumber(value: ditherLevels), forKey: "ditherLevels") }
        }
    }

    private static var all: [SCNMaterial] = []

    /*
     The last step for every pixel of every surface. Instead of thousands of
     smooth shades it allows only a few, and fakes the in-between ones with a
     repeating 4 x 4 pattern of dots (a "Bayer" pattern). A newspaper photo
     does the same trick with black ink.
    */
    private static let dither = """
    #pragma arguments
    float ditherLevels;
    #pragma body
    float2 dp = floor(in.fragmentPosition.xy);
    float2 dh = floor(dp * 0.5);
    float ditherCoarse = fract(dh.x * 0.5 + dh.y * dh.y * 0.75);
    float ditherFine = fract(dp.x * 0.5 + dp.y * dp.y * 0.75);
    float ditherThreshold = ditherCoarse * 0.25 + ditherFine;
    _output.color.rgb = floor(_output.color.rgb * ditherLevels + ditherThreshold) / ditherLevels;
    """

    /// Registers a material so it gets the dot-pattern finish and follows the retro setting.
    @discardableResult
    static func finish(_ material: SCNMaterial) -> SCNMaterial {
        material.shaderModifiers = [.fragment: dither]
        material.setValue(NSNumber(value: ditherLevels), forKey: "ditherLevels")
        all.append(material)
        return material
    }

    private static func surface(_ model: SCNMaterial.LightingModel) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = model
        m.diffuse.contents = Textures.atlas
        // The tiny textures are stretched with blurry filtering, like the consoles of the time.
        m.diffuse.magnificationFilter = .linear
        m.diffuse.minificationFilter = .linear
        m.diffuse.mipFilter = .none
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.isDoubleSided = false
        return finish(m)
    }

    /// Lit by the moon and the lantern.
    static let lit: SCNMaterial = surface(.lambert)
    /// Shines with its own colour, whatever the lighting.
    static let glowing: SCNMaterial = surface(.constant)

    /// A flat, unlit colour (the lantern flame, for example).
    static func flat(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        return finish(m)
    }

    /// A soft blob of light that adds to whatever is behind it.
    static func glowSprite(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Textures.glow
        m.multiply.contents = color
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    /// A pixel-art picture stuck onto a surface (the face, the runes).
    static func decal(_ image: UIImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.diffuse.magnificationFilter = .nearest
        m.diffuse.minificationFilter = .nearest
        m.diffuse.mipFilter = .none
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }
}

/// A glow that always faces the camera.
func makeGlow(color: UIColor, size: CGFloat) -> SCNNode {
    let plane = SCNPlane(width: size, height: size)
    plane.materials = [Materials.glowSprite(color)]
    let node = SCNNode(geometry: plane)
    node.constraints = [SCNBillboardConstraint()]
    node.renderingOrder = 10
    return node
}

extension SCNNode {
    /// Sets how strong a glow made by `makeGlow` is, and optionally its colour.
    func setGlow(strength: CGFloat, color: UIColor? = nil) {
        guard let material = geometry?.firstMaterial else { return }
        if let color { material.multiply.contents = color }
        opacity = max(0, min(1, strength))
    }
}
