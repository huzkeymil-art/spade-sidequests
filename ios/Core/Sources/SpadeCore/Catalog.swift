import Foundation

// The game's content lives in plain JSON files (in the Content folder). They
// are copies of the web app's files, refreshed by `npm run ios:data`.

struct Looks: Codable {
    var skin: [String]
    var hair: [String]
    var scarf: [String]
    var hairStyles: [String]
}

enum Catalog {
    static let quests: [QuestDef] = load("quests")
    static let items: [ItemDef] = load("items")
    static let feats: [FeatDef] = load("achievements")
    static let looks: Looks = load("looks")

    static let itemById: [String: ItemDef] = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    static let featById: [String: FeatDef] = Dictionary(uniqueKeysWithValues: feats.map { ($0.id, $0) })

    /// Where the content files are: inside the test package when testing, inside the app otherwise.
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    private static func load<T: Decodable>(_ name: String) -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(T.self, from: data)
        else {
            fatalError("Missing or unreadable content file: \(name).json")
        }
        return value
    }
}
