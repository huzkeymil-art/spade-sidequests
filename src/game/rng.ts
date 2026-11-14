// Seeded randomness.
//
// A normal random number is different every time. A *seeded* one is like a
// shuffled deck that always comes out in the same order if you start from the
// same seed. Spade uses the date as part of the seed, so today's quests stay
// the same no matter how many times the app is reopened.

/** Turns any text into a number (FNV-1a hash). Same text in, same number out. */
export function hashString(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** A small, fast random number generator (mulberry32). Returns numbers in [0, 1). */
export function makeRng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Random generator seeded from the save's seed plus any labels (a date, a quest id, ...). */
export function rngFor(seed: number, ...labels: (string | number)[]): () => number {
  return makeRng(hashString(`${seed}|${labels.join('|')}`));
}

/** Returns a shuffled copy (Fisher-Yates). */
export function shuffled<T>(list: readonly T[], rng: () => number): T[] {
  const out = list.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/** Picks one entry, where bigger weights are picked more often. */
export function weightedPick<T>(entries: readonly (readonly [T, number])[], rng: () => number): T {
  const total = entries.reduce((sum, [, w]) => sum + w, 0);
  let roll = rng() * total;
  for (const [value, weight] of entries) {
    roll -= weight;
    if (roll < 0) return value;
  }
  return entries[entries.length - 1][0];
}
