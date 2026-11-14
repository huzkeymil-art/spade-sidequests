import Foundation

// Seeded randomness.
//
// A normal random number is different every time. A *seeded* one is like a
// shuffled deck that always comes out in the same order if you start from the
// same seed. Spade uses the date as part of the seed, so today's quests stay
// the same no matter how many times the app is reopened.
//
// These are exact ports of the web version's functions. The arithmetic wraps
// around at 32 bits (the &+ and &* operators), just as it does in JavaScript,
// so both versions produce the same numbers from the same seed.

/// Turns any text into a number (FNV-1a hash). Same text in, same number out.
func hashString(_ text: String) -> UInt32 {
    var h: UInt32 = 0x811c_9dc5
    // JavaScript sees text as UTF-16 units, so this does too.
    for unit in text.utf16 {
        h ^= UInt32(unit)
        h = h &* 0x0100_0193
    }
    return h
}

/// A small, fast random number generator (mulberry32). `next()` returns numbers in 0..<1.
struct SeededRng {
    private var a: UInt32

    init(seed: UInt32) {
        a = seed
    }

    mutating func next() -> Double {
        a = a &+ 0x6d2b_79f5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }
}

/// A generator seeded from the save's seed plus any labels (a date, a quest id, ...).
func rngFor(_ seed: Int, _ labels: String...) -> SeededRng {
    SeededRng(seed: hashString("\(seed)|\(labels.joined(separator: "|"))"))
}

/// Returns a shuffled copy (Fisher-Yates).
func shuffled<T>(_ list: [T], _ rng: inout SeededRng) -> [T] {
    var out = list
    var i = out.count - 1
    while i > 0 {
        let j = Int((rng.next() * Double(i + 1)).rounded(.down))
        out.swapAt(i, j)
        i -= 1
    }
    return out
}

/// Picks one entry, where bigger weights are picked more often.
func weightedPick<T>(_ entries: [(T, Double)], _ rng: inout SeededRng) -> T {
    let total = entries.reduce(0) { $0 + $1.1 }
    var roll = rng.next() * total
    for (value, weight) in entries {
        roll -= weight
        if roll < 0 { return value }
    }
    return entries[entries.count - 1].0
}
