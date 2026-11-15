import Foundation

// The shapes of all the data in Spade. Nothing in this folder touches the
// screen: it is pure game rules. The property names match the web version's
// save file exactly, so a save exported from the web app loads here unchanged.

enum Cadence: String, Codable, CaseIterable {
    case daily, weekly, monthly
}

enum QuestKind: String, Codable, CaseIterable {
    case body, mind, craft, heart, home
}

enum Slot: String, Codable, CaseIterable {
    case head, body, hand, shield, charm
}

enum Rarity: String, Codable, CaseIterable {
    case common, uncommon, rare, mythic
}

/// A quest as written in the deck.
struct QuestDef: Codable, Equatable {
    var id: String
    var cadence: Cadence
    var category: QuestKind
    /// 1 = light, 2 = steady, 3 = hard.
    var difficulty: Int
    var title: String
    /// How many times it must be marked before it counts as done. Missing means once.
    var target: Int?
}

/// A quest the player wrote themselves.
struct CustomQuest: Codable, Equatable, Identifiable {
    var id: String
    var cadence: Cadence
    var category: QuestKind
    var difficulty: Int
    var title: String
    var target: Int?
    /// Pinned quests show up every single period instead of being shuffled into the deck.
    var pinned: Bool

    var asDef: QuestDef {
        QuestDef(id: id, cadence: cadence, category: category, difficulty: difficulty, title: title, target: target)
    }
}

/// A quest that has been dealt onto the board for the current day, week or month.
struct ActiveQuest: Codable, Equatable, Identifiable {
    /// Unique for this deal, for example "2026-11-14:d_walk".
    var key: String
    var defId: String
    var cadence: Cadence
    var category: QuestKind
    var title: String
    var xp: Int
    var target: Int
    var progress: Int
    var done: Bool
    var custom: Bool
    var pinned: Bool
    /// Set on quests a parent set for this child. The web version never has these.
    var family: FamilyTag?

    var id: String { key }
}

struct Board: Codable, Equatable {
    /// Which day, week or month this board belongs to.
    var period: String = ""
    var quests: [ActiveQuest] = []
    /// Swaps used this period.
    var rerolls: Int = 0
    /// Whether the all-clear bonus has been paid.
    var cleared: Bool = false
}

/// The three boards, one per cadence.
struct Boards: Codable, Equatable {
    var daily = Board()
    var weekly = Board()
    var monthly = Board()

    subscript(cadence: Cadence) -> Board {
        get {
            switch cadence {
            case .daily: return daily
            case .weekly: return weekly
            case .monthly: return monthly
            }
        }
        set {
            switch cadence {
            case .daily: daily = newValue
            case .weekly: weekly = newValue
            case .monthly: monthly = newValue
            }
        }
    }
}

/// Quest ids from the previous period, so they are not dealt twice in a row.
struct RecentQuests: Codable, Equatable {
    var daily: [String] = []
    var weekly: [String] = []
    var monthly: [String] = []

    subscript(cadence: Cadence) -> [String] {
        get {
            switch cadence {
            case .daily: return daily
            case .weekly: return weekly
            case .monthly: return monthly
            }
        }
        set {
            switch cadence {
            case .daily: daily = newValue
            case .weekly: weekly = newValue
            case .monthly: monthly = newValue
            }
        }
    }
}

enum ItemSource: String, Codable {
    /// Given at the beginning.
    case starter
    /// Dug up at random.
    case loot
    /// Handed out on reaching a level.
    case milestone
    /// An achievement reward.
    case feat
}

struct ItemDef: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var slot: Slot
    var rarity: Rarity
    var source: ItemSource
    var level: Int?
    var lore: String
}

/// The numbers a feat can watch.
enum StatName: String, Codable {
    case quests, dailyClears, bestStreak, weekly, monthly, level, items, slotsFilled, mythics, customMade, customDone
}

struct FeatDef: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var desc: String
    var stat: StatName
    var goal: Int
    var xp: Int
    var item: String?
}

struct HeroSave: Codable, Equatable {
    var name: String = ""
    /// Indexes into the colour lists in looks.json.
    var skin: Int = 1
    var hair: Int = 1
    var hairStyle: Int = 1
    var scarf: Int = 0
}

struct GameSettings: Codable, Equatable {
    var retro: Bool = true
    var sound: Bool = true
    var haptics: Bool = true
    /// Whether the "How Spade works" sheet has been shown.
    var guideSeen: Bool = false
    /// Notifications when new quests arrive. Only the native app has these.
    var reminders: Bool = false
    /// Quest kind name -> whether it may be dealt.
    var categories: [String: Bool] = Dictionary(uniqueKeysWithValues: QuestKind.allCases.map { ($0.rawValue, true) })

    init() {}

    // Read leniently: a save from the web app, or from an older version, may lack some of these.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        retro = (try? c.decode(Bool.self, forKey: .retro)) ?? true
        sound = (try? c.decode(Bool.self, forKey: .sound)) ?? true
        haptics = (try? c.decode(Bool.self, forKey: .haptics)) ?? true
        guideSeen = (try? c.decode(Bool.self, forKey: .guideSeen)) ?? false
        reminders = (try? c.decode(Bool.self, forKey: .reminders)) ?? false
        let stored = (try? c.decode([String: Bool].self, forKey: .categories)) ?? [:]
        for kind in QuestKind.allCases {
            categories[kind.rawValue] = stored[kind.rawValue] ?? true
        }
    }

    func allows(_ kind: QuestKind) -> Bool {
        categories[kind.rawValue] ?? true
    }
}

struct Counts: Codable, Equatable {
    var quests = 0
    var daily = 0
    var weekly = 0
    var monthly = 0
    var dailyClears = 0
    var customDone = 0
    var customMade = 0
    var bestStreak = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quests = (try? c.decode(Int.self, forKey: .quests)) ?? 0
        daily = (try? c.decode(Int.self, forKey: .daily)) ?? 0
        weekly = (try? c.decode(Int.self, forKey: .weekly)) ?? 0
        monthly = (try? c.decode(Int.self, forKey: .monthly)) ?? 0
        dailyClears = (try? c.decode(Int.self, forKey: .dailyClears)) ?? 0
        customDone = (try? c.decode(Int.self, forKey: .customDone)) ?? 0
        customMade = (try? c.decode(Int.self, forKey: .customMade)) ?? 0
        bestStreak = (try? c.decode(Int.self, forKey: .bestStreak)) ?? 0
    }

    subscript(cadence: Cadence) -> Int {
        get {
            switch cadence {
            case .daily: return daily
            case .weekly: return weekly
            case .monthly: return monthly
            }
        }
        set {
            switch cadence {
            case .daily: daily = newValue
            case .weekly: weekly = newValue
            case .monthly: monthly = newValue
            }
        }
    }
}

struct Streak: Codable, Equatable {
    var count: Int = 0
    var lastDay: String?
}

/// Everything that is remembered between visits.
struct Save: Codable, Equatable {
    var version: Int = 1
    /// A random number chosen once. It makes each player's shuffles different.
    var seed: Int
    /// When the save was made, in milliseconds since 1970 (the web's way of counting time).
    var createdAt: Double
    var onboarded: Bool = false
    var hero = HeroSave()
    /// Total XP ever earned. The level is worked out from this.
    var xp: Int = 0
    var inventory: [String] = []
    /// Slot name -> item id.
    var equipped: [String: String] = [:]
    var boards = Boards()
    var recent = RecentQuests()
    var streak = Streak()
    /// Days on which at least one daily quest was finished (most recent last).
    var activeDays: [String] = []
    var counts = Counts()
    /// Feat id -> when it was earned (milliseconds since 1970).
    var feats: [String: Double] = [:]
    var custom: [CustomQuest] = []
    var settings = GameSettings()
    /// Who this Spade is for. Only the iPhone app has families; the web version ignores these.
    var role: Role = .solo
    /// On a child's Spade: their family, and the quests and allowance from their parent.
    var family: Membership?
    /// On a parent's Spade: their children, the quests set for them, and what is owed.
    var household: Household?
    var chamber: [String]?
    var guardianHub: GuardianHub?
    var guardianPending: [GuardianChange]?

    init(seed: Int, createdAt: Double) {
        self.seed = seed
        self.createdAt = createdAt
    }

    // Read leniently, so an old or slightly damaged save still loads.
    // Only the seed and the XP are essential; without them it isn't a Spade save.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seed = Int(try c.decode(Double.self, forKey: .seed))
        xp = max(0, Int((try c.decode(Double.self, forKey: .xp)).rounded(.down)))
        createdAt = (try? c.decode(Double.self, forKey: .createdAt)) ?? 0
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? false
        hero = (try? c.decode(HeroSave.self, forKey: .hero)) ?? HeroSave()
        inventory = (try? c.decode([String].self, forKey: .inventory)) ?? []
        equipped = (try? c.decode([String: String].self, forKey: .equipped)) ?? [:]
        // Each board is read on its own, so one damaged board doesn't cost the others.
        if let nested = try? c.nestedContainer(keyedBy: BoardKeys.self, forKey: .boards) {
            boards.daily = (try? nested.decode(Board.self, forKey: .daily)) ?? Board()
            boards.weekly = (try? nested.decode(Board.self, forKey: .weekly)) ?? Board()
            boards.monthly = (try? nested.decode(Board.self, forKey: .monthly)) ?? Board()
        }
        recent = (try? c.decode(RecentQuests.self, forKey: .recent)) ?? RecentQuests()
        streak = (try? c.decode(Streak.self, forKey: .streak)) ?? Streak()
        activeDays = (try? c.decode([String].self, forKey: .activeDays)) ?? []
        counts = (try? c.decode(Counts.self, forKey: .counts)) ?? Counts()
        feats = (try? c.decode([String: Double].self, forKey: .feats)) ?? [:]
        custom = (try? c.decode([CustomQuest].self, forKey: .custom)) ?? []
        settings = (try? c.decode(GameSettings.self, forKey: .settings)) ?? GameSettings()
        role = (try? c.decode(Role.self, forKey: .role)) ?? .solo
        family = try? c.decode(Membership.self, forKey: .family)
        household = try? c.decode(Household.self, forKey: .household)
        chamber = try? c.decode([String].self, forKey: .chamber)
        guardianHub = try? c.decode(GuardianHub.self, forKey: .guardianHub)
        guardianPending = try? c.decode([GuardianChange].self, forKey: .guardianPending)
    }

    private enum BoardKeys: String, CodingKey {
        case daily, weekly, monthly
    }

    func worn(_ slot: Slot) -> String? {
        equipped[slot.rawValue]
    }
}

/// Things that happened as the result of an action, in the order the app should show them.
enum GameEvent: Equatable {
    case xp(amount: Int, reason: XpReason)
    case clear
    case item(itemId: String, fresh: Bool, echoXp: Int, from: ItemOrigin)
    case level(level: Int, rank: String?)
    case feat(id: String)
    /// A parent's allowance quest was finished, and now waits for them to check it.
    case allowance(amount: Int)
}

enum XpReason: String {
    case quest, clear, feat, echo
}

enum ItemOrigin: String {
    case quest, level, feat, start
}

/// The result of an action: the new save, and what happened along the way.
struct Outcome {
    var save: Save
    var events: [GameEvent] = []
}
