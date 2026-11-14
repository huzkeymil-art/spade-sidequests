import Foundation

// The 3D models, read from models.json.
//
// That file is written by `npm run ios:data`, which runs the web app's own
// model code and saves the finished shapes. So the web and native versions
// always show exactly the same hero, items and scenery.

/// One finished shape: lists of numbers the graphics card can draw directly.
struct MeshData: Decodable {
    /// Positions, 3 numbers per corner.
    let p: [Float]
    /// Normals (which way each corner faces), 3 per corner.
    let n: [Float]
    /// Texture coordinates, 2 per corner.
    let uv: [Float]
    /// Glow, 1 per corner: 0 is lit by the scene, 1 shines on its own.
    let e: [Float]
    /// Corner indexes, 3 per triangle.
    let i: [UInt32]
    /// Colour, 3 per corner. Missing on parts whose colour depends on the hero's look.
    let c: [Float]?
    /// For look-dependent parts: 0 at the bottom of the part, 1 at the top.
    let t: [Float]?
}

/// A piece of the hero. Its colour may come from the player's choices.
struct Chunk: Decodable {
    /// "skin", "hair", "scarf", "tunic" or "sleeve"; nil when the colour is fixed.
    let role: String?
    /// True when the part is one flat colour instead of shading darker toward the bottom.
    let flat: Bool
    let mesh: MeshData
}

struct JointSpec: Decodable {
    let name: String
    let parent: String?
    let at: [Float]
    let rot: [Float]?
}

struct HeadSpec: Decodable {
    let center: [Float]
    let radius: [Float]
}

struct HairSet: Decodable {
    /// Hidden under a hat.
    let top: [Chunk]
    /// Still shows below a hat.
    let under: [Chunk]
}

struct HeroModel: Decodable {
    let joints: [JointSpec]
    let head: HeadSpec
    let torso: [Chunk]
    let armR: [Chunk]
    let armL: [Chunk]
    let leg: [Chunk]
    let headParts: [Chunk]
    let tail1: [Chunk]
    let tail2: [Chunk]
    let hair: [String: HairSet]

    private enum CodingKeys: String, CodingKey {
        case joints, head, torso, armR, armL, leg, tail1, tail2, hair
        case headParts = "head_"
    }
}

struct ItemModel: Decodable {
    let slot: String
    /// The item on its own, for icons and the dig-up.
    let display: MeshData
    /// The item as worn (hats, tools, shields, charms).
    let mesh: MeshData?
    /// For hats: "keep", "under" or "hide" the hero's hair.
    let hair: String?
    /// For charms: the colour of their glow, if any.
    let glow: String?
    /// For clothing: colours that replace the hero's tunic and sleeves.
    let tunic: String?
    let sleeve: String?
    /// For clothing: extra shapes on the body and on each shoulder.
    let torso: MeshData?
    let shoulderR: MeshData?
    let shoulderL: MeshData?
}

/// One of the camera's set positions.
struct ShotSpec: Decodable {
    let target: [Float]
    let dist: Float
    let height: Float
    let yaw: Float
    /// Where on screen the target lands: 0 = top edge, 1 = bottom edge.
    let screenY: Float
    /// Where the panel begins, as a fraction of the screen height. 1 = no panel.
    let sheet: Float
}

struct SceneryModel: Decodable {
    let ground: MeshData
    let ridgeFar: MeshData
    let ridgeNear: MeshData
    let weekStone: MeshData
    let scatter: MeshData
    let grass: MeshData
    let tree: MeshData
    let lantern: MeshData
    let mound: MeshData
    let lockbox: MeshData
    let lid: MeshData
    let clods: [MeshData]
}

struct PointField: Decodable {
    let positions: [Float]
    let seeds: [Float]
}

struct SkyColors: Decodable {
    let top: [Float]
    let mid: [Float]
    let horizon: [Float]
}

struct Places: Decodable {
    let lantern: [Float]
    let dig: [Float]
    let stone: [Float]
}

struct Models: Decodable {
    let shots: [String: ShotSpec]
    let fov: Float
    let heroYaw: Float
    let digHeroYaw: Float
    let places: Places
    let sky: SkyColors
    let hero: HeroModel
    let items: [String: ItemModel]
    let props: [String: MeshData]
    let scenery: SceneryModel
    let stars: PointField
    let motes: PointField
}

enum ModelLibrary {
    static let shared: Models = {
        guard let url = Bundle.main.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { fatalError("models.json is missing from the app") }
        do {
            return try JSONDecoder().decode(Models.self, from: data)
        } catch {
            fatalError("models.json could not be read: \(error)")
        }
    }()
}
