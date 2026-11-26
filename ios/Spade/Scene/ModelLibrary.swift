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

/// A piece of the new hero. Its colour comes from the player's choices (`role`), or travels
/// with it (`top`, and `bottom` when the model names one).
struct Piece: Decodable {
    let role: String?
    let flat: Bool
    let top: [Float]?
    let bottom: [Float]?
    let mesh: MeshData
}

/// Which locks of hair make up a style: all of it, what shows under a hat, and under the hood.
struct HairLocks: Decodable {
    let top: [Int]
    let under: [Int]
    let hooded: [Int]
}

/// The patch of the head the new hero's face is painted on.
struct FacePatch: Decodable {
    let p: [Float]
    let n: [Float]
    let uv: [Float]
    let i: [UInt32]
    /// How many pictures are stacked in face2.png.
    let frames: Int
}

struct Limbs2: Decodable {
    let upperArm: Float
    let forearm: Float
    let thigh: Float
}

/// The new hero, in the hooded cloak. See src/three/heroV2.ts.
struct Hero2Model: Decodable {
    let joints: [JointSpec]
    let limbs: Limbs2
    /// The new hero is drawn a little smaller than life, so every camera shot still frames it.
    let fit: Float
    let hatScale: Float
    let shieldScale: Float
    let cloakColor: [Float]
    /// The hero's own soft fill light.
    let fill: [Float]
    let torso: [Piece]
    let cloakHoodUp: [Piece]
    let cloakHoodDown: [Piece]
    let hood: [Piece]
    let armR: [Piece]
    let elbowR: [Piece]
    let armL: [Piece]
    let elbowL: [Piece]
    let thigh: [Piece]
    let shinR: [Piece]
    let shinL: [Piece]
    let tail1: [Piece]
    let tail2: [Piece]
    let headShell: [Piece]
    let headFeatures: [Piece]
    let locks: [Piece]
    let hair: [String: HairLocks]
    let face: FacePatch
}

/// An item as the new hero wears it.
struct Worn2: Decodable {
    /// Only when it differs from the item's usual mesh (round caps keep just their crowns).
    let soft: MeshData?
    /// In flat colours, for cel shading.
    let cel: MeshData
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
    /// For cloaks: the colour the new hero's cloak takes on.
    let cloak: String?
    /// For hats, tools and shields: as the new hero wears them.
    let worn2: Worn2?
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
    /// Shots that differ for the new hero.
    let shots2: [String: ShotSpec]
    let fov: Float
    let heroYaw: Float
    let digHeroYaw: Float
    let places: Places
    let sky: SkyColors
    let hero: HeroModel
    let hero2: Hero2Model
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
