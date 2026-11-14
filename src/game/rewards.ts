import { ITEMS } from './content';
import { weightedPick } from './rng';
import type { Cadence, Difficulty, ItemDef, Rarity } from './types';

// XP, levels and loot.

const QUEST_XP: Record<Cadence, [number, number, number]> = {
  daily: [20, 30, 45],
  weekly: [100, 125, 150],
  monthly: [400, 500, 600],
};

/** XP for finishing a quest: harder and longer quests pay more. */
export function questXp(cadence: Cadence, difficulty: Difficulty): number {
  return QUEST_XP[cadence][difficulty - 1];
}

/** Bonus for finishing every daily quest in one day. */
export const DAILY_CLEAR_XP = 25;

/** XP needed to go from `level` to the next one. Each level asks for 50 more than the last. */
export function xpToNext(level: number): number {
  return 100 + 50 * (level - 1);
}

export interface LevelInfo {
  level: number;
  /** XP earned so far inside the current level. */
  into: number;
  /** XP the current level needs in total. */
  need: number;
}

/** Works out the level from total XP by "spending" XP one level at a time. */
export function levelInfo(totalXp: number): LevelInfo {
  let level = 1;
  let left = Math.max(0, Math.floor(totalXp));
  while (left >= xpToNext(level)) {
    left -= xpToNext(level);
    level++;
  }
  return { level, into: left, need: xpToNext(level) };
}

/** Rank titles, each unlocked at a level. */
export const RANKS: [number, string][] = [
  [1, 'Greenhand'],
  [5, 'Delver'],
  [10, 'Pathfinder'],
  [15, 'Lanternbearer'],
  [20, 'Deepwalker'],
  [25, 'Barrow Warden'],
  [30, 'Moonwarden'],
  [40, 'Legend of the Loam'],
];

export function rankFor(level: number): string {
  let title = RANKS[0][1];
  for (const [at, name] of RANKS) if (level >= at) title = name;
  return title;
}

/** If `level` is exactly where a new rank begins, returns that rank. */
export function rankUnlockedAt(level: number): string | null {
  const hit = RANKS.find(([at]) => at === level && at > 1);
  return hit ? hit[1] : null;
}

/** Items handed out for reaching a level. */
export const MILESTONES: Record<number, string> = Object.fromEntries(
  ITEMS.filter((i) => i.source === 'milestone' && i.level).map((i) => [i.level as number, i.id]),
);

/** Chance that a quest digs something up at all. */
const DROP_CHANCE: Record<Cadence, number> = { daily: 0.12, weekly: 1, monthly: 1 };

/** How likely each rarity is. Longer quests dig deeper. */
const RARITY_ODDS: Record<Cadence, [Rarity, number][]> = {
  daily: [['common', 70], ['uncommon', 25], ['rare', 5]],
  weekly: [['uncommon', 65], ['rare', 30], ['mythic', 5]],
  monthly: [['rare', 75], ['mythic', 25]],
};

/** Bonus XP when a find turns out to be something already owned. */
export const ECHO_XP: Record<Rarity, number> = { common: 15, uncommon: 30, rare: 60, mythic: 120 };

export interface LootResult {
  item: ItemDef;
  /** False when the player already owns it (it becomes bonus XP instead). */
  fresh: boolean;
}

/**
 * Rolls for loot. Picks a rarity first, then an item of that rarity,
 * preferring ones the player doesn't have yet.
 */
export function rollLoot(cadence: Cadence, rng: () => number, owned: readonly string[]): LootResult | null {
  if (rng() >= DROP_CHANCE[cadence]) return null;
  const rarity = weightedPick(RARITY_ODDS[cadence], rng);
  const pool = ITEMS.filter((i) => i.source === 'loot' && i.rarity === rarity);
  if (pool.length === 0) return null;
  const unowned = pool.filter((i) => !owned.includes(i.id));
  const from = unowned.length > 0 ? unowned : pool;
  const item = from[Math.floor(rng() * from.length)];
  return { item, fresh: unowned.length > 0 };
}
