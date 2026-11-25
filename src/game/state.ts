import { pendingFeats } from './achievements';
import { ITEM_BY_ID, LOOKS } from './content';
import { dayKey, periodKey, shiftDay } from './periods';
import { DAILY_REROLLS, activateCustom, dealBoard, swapQuest, type DealContext } from './quests';
import { DAILY_CLEAR_XP, ECHO_XP, MILESTONES, levelInfo, rankUnlockedAt, rollLoot } from './rewards';
import { rngFor } from './rng';
import {
  CADENCES,
  CATEGORIES,
  type Board,
  type Cadence,
  type Category,
  type CustomQuest,
  type Difficulty,
  type GameEvent,
  type Save,
  type Slot,
} from './types';

// The rules of the game, as plain functions.
//
// Each function takes the current save and returns a NEW save, never changing
// the old one, plus a list of "events" describing what happened (XP gained,
// item found, level up). The screens read those events to decide what to
// celebrate. Keeping rules separate from screens is what lets them be tested
// without a phone, and rewritten in Swift line by line.

export interface Outcome {
  save: Save;
  events: GameEvent[];
}

export const SAVE_VERSION = 1;

const emptyBoard = () => ({ period: '', quests: [], rerolls: 0, cleared: false });

export function newSave(seed: number, now: Date): Save {
  return {
    version: SAVE_VERSION,
    seed,
    createdAt: now.getTime(),
    onboarded: false,
    hero: { name: '', skin: 1, hair: 1, hairStyle: 1, scarf: 0, hoodDown: false },
    xp: 0,
    inventory: [],
    equipped: {},
    boards: { daily: emptyBoard(), weekly: emptyBoard(), monthly: emptyBoard() },
    recent: { daily: [], weekly: [], monthly: [] },
    streak: { count: 0, lastDay: null },
    activeDays: [],
    counts: { quests: 0, daily: 0, weekly: 0, monthly: 0, dailyClears: 0, customDone: 0, customMade: 0, bestStreak: 0 },
    feats: {},
    custom: [],
    settings: {
      retro: true,
      sound: true,
      haptics: true,
      guideSeen: false,
      newHero: true,
      celShading: true,
      categories: { body: true, mind: true, craft: true, heart: true, home: true },
    },
  };
}

function dealContext(save: Save, cadence: Cadence): DealContext {
  return { seed: save.seed, custom: save.custom, categories: save.settings.categories, recent: save.recent[cadence] };
}

/**
 * Brings the boards up to date with the clock. Call it whenever the app opens
 * or wakes: any board whose day, week or month has ended is replaced with a
 * fresh deal, and a streak that missed a day is put out.
 */
export function syncPeriods(save: Save, now: Date): Save {
  let next = save;
  for (const cadence of CADENCES) {
    const period = periodKey(cadence, now);
    const board = next.boards[cadence];
    if (board.period === period) continue;
    const recent = board.quests.map((q) => q.defId);
    const withRecent = { ...next, recent: { ...next.recent, [cadence]: recent } };
    next = {
      ...withRecent,
      boards: { ...withRecent.boards, [cadence]: dealBoard(cadence, period, dealContext(withRecent, cadence)) },
    };
  }

  // A streak survives if the last active day was today or yesterday.
  const today = dayKey(now);
  const last = next.streak.lastDay;
  if (next.streak.count > 0 && last !== today && last !== shiftDay(today, -1)) {
    next = { ...next, streak: { ...next.streak, count: 0 } };
  }
  return next;
}

// ---- Rewards --------------------------------------------------------------

function addXp(save: Save, amount: number, reason: Extract<GameEvent, { type: 'xp' }>['reason'], events: GameEvent[]): Save {
  if (amount <= 0) return save;
  const before = levelInfo(save.xp).level;
  let next: Save = { ...save, xp: save.xp + amount };
  events.push({ type: 'xp', amount, reason });
  const after = levelInfo(next.xp).level;
  for (let level = before + 1; level <= after; level++) {
    events.push({ type: 'level', level, rank: rankUnlockedAt(level) });
    const gift = MILESTONES[level];
    if (gift) next = giveItem(next, gift, 'level', events);
  }
  return next;
}

function giveItem(save: Save, itemId: string, from: Extract<GameEvent, { type: 'item' }>['from'], events: GameEvent[]): Save {
  const item = ITEM_BY_ID[itemId];
  if (!item) return save;
  if (save.inventory.includes(itemId)) {
    // Already owned: it "echoes" into bonus XP instead.
    const echoXp = ECHO_XP[item.rarity];
    events.push({ type: 'item', itemId, fresh: false, echoXp, from });
    return addXp(save, echoXp, 'echo', events);
  }
  events.push({ type: 'item', itemId, fresh: true, echoXp: 0, from });
  return { ...save, inventory: [...save.inventory, itemId] };
}

/** Awards any feats that have been earned. Loops, because a feat's XP can trigger another feat. */
function settleFeats(save: Save, now: Date, events: GameEvent[]): Save {
  let next = save;
  for (let guard = 0; guard < 20; guard++) {
    const earned = pendingFeats(next);
    if (earned.length === 0) break;
    for (const feat of earned) {
      next = { ...next, feats: { ...next.feats, [feat.id]: now.getTime() } };
      events.push({ type: 'feat', id: feat.id });
      next = addXp(next, feat.xp, 'feat', events);
      if (feat.item) next = giveItem(next, feat.item, 'feat', events);
    }
  }
  return next;
}

// ---- Actions --------------------------------------------------------------

/**
 * Marks a quest. A counted quest ("on 4 days") moves one step closer; any
 * other quest, or the final step of a counted one, completes it and pays out.
 */
export function markQuest(save: Save, cadence: Cadence, key: string, now: Date): Outcome {
  const events: GameEvent[] = [];
  const board = save.boards[cadence];
  const at = board.quests.findIndex((q) => q.key === key);
  const quest = board.quests[at];
  if (!quest || quest.done) return { save, events };

  const progress = quest.progress + 1;
  const done = progress >= quest.target;
  const quests = board.quests.slice();
  quests[at] = { ...quest, progress, done };
  let next: Save = { ...save, boards: { ...save.boards, [cadence]: { ...board, quests } } };
  if (!done) return { save: next, events };

  next = {
    ...next,
    counts: {
      ...next.counts,
      quests: next.counts.quests + 1,
      [cadence]: next.counts[cadence] + 1,
      customDone: next.counts.customDone + (quest.custom ? 1 : 0),
    },
  };
  next = addXp(next, quest.xp, 'quest', events);

  if (cadence === 'daily') {
    // Keep the streak alive.
    const today = dayKey(now);
    if (next.streak.lastDay !== today) {
      const count = next.streak.lastDay === shiftDay(today, -1) ? next.streak.count + 1 : 1;
      next = {
        ...next,
        streak: { count, lastDay: today },
        activeDays: [...next.activeDays.filter((d) => d !== today), today].slice(-60),
        counts: { ...next.counts, bestStreak: Math.max(next.counts.bestStreak, count) },
      };
    }
    // All of today's dailies done: pay the clear bonus once.
    const daily = next.boards.daily;
    if (!daily.cleared && daily.quests.every((q) => q.done)) {
      next = {
        ...next,
        boards: { ...next.boards, daily: { ...daily, cleared: true } },
        counts: { ...next.counts, dailyClears: next.counts.dailyClears + 1 },
      };
      events.push({ type: 'clear' });
      next = addXp(next, DAILY_CLEAR_XP, 'clear', events);
    }
  }

  // Loot. The roll is tied to this exact quest, so it can't be re-rolled by retrying.
  const loot = rollLoot(cadence, rngFor(next.seed, 'loot', quest.key), next.inventory);
  if (loot) next = giveItem(next, loot.item.id, 'quest', events);

  next = settleFeats(next, now, events);
  return { save: next, events };
}

/** How many swaps are left on the daily board today. */
export function rerollsLeft(save: Save): number {
  return Math.max(0, DAILY_REROLLS - save.boards.daily.rerolls);
}

/** Swaps an unfinished daily quest for another one. */
export function rerollDaily(save: Save, key: string): Save {
  if (rerollsLeft(save) <= 0) return save;
  const swapped = swapQuest(save.boards.daily, key, dealContext(save, 'daily'));
  return swapped ? { ...save, boards: { ...save.boards, daily: swapped } } : save;
}

export interface CustomQuestInput {
  title: string;
  cadence: Cadence;
  category: Category;
  difficulty: Difficulty;
  pinned: boolean;
}

/** Adds a quest the player wrote. Pinned ones join the current board straight away. */
export function addCustomQuest(save: Save, input: CustomQuestInput, now: Date): Outcome {
  const events: GameEvent[] = [];
  const title = input.title.trim().slice(0, 80);
  if (!title) return { save, events };
  const quest: CustomQuest = {
    id: `c_${now.getTime().toString(36)}_${save.custom.length}`,
    cadence: input.cadence,
    category: input.category,
    difficulty: input.difficulty,
    title,
    pinned: input.pinned,
  };
  let next: Save = {
    ...save,
    custom: [...save.custom, quest],
    counts: { ...save.counts, customMade: save.counts.customMade + 1 },
  };
  // Every new quest goes on the board straight away, so it can be done this period.
  // After that, pinned ones are dealt every time and the rest are mixed in with the deck.
  const board = next.boards[quest.cadence];
  next = {
    ...next,
    boards: { ...next.boards, [quest.cadence]: { ...board, quests: [activateCustom(quest, board.period), ...board.quests] } },
  };
  next = settleFeats(next, now, events);
  return { save: next, events };
}

/** Deletes a custom quest. If it is on a board and unfinished, it leaves the board too. */
export function removeCustomQuest(save: Save, id: string): Save {
  const boards = { ...save.boards };
  for (const cadence of CADENCES) {
    const board = boards[cadence];
    boards[cadence] = { ...board, quests: board.quests.filter((q) => q.defId !== id || q.done) };
  }
  return { ...save, custom: save.custom.filter((q) => q.id !== id), boards };
}

/** Puts an owned item on, or takes off whatever is in that slot when `itemId` is null. */
export function equip(save: Save, slot: Slot, itemId: string | null, now: Date): Outcome {
  const events: GameEvent[] = [];
  const equipped = { ...save.equipped };
  if (itemId === null) {
    delete equipped[slot];
  } else {
    const item = ITEM_BY_ID[itemId];
    if (!item || item.slot !== slot || !save.inventory.includes(itemId)) return { save, events };
    equipped[slot] = itemId;
  }
  const next = settleFeats({ ...save, equipped }, now, events);
  return { save: next, events };
}

/**
 * First launch: names the hero and buries the starter spade for them to dig up.
 * It isn't put in their hand automatically: choosing "Wear it" is the first thing the game teaches.
 */
export function beginJourney(save: Save, name: string, now: Date): Outcome {
  const events: GameEvent[] = [];
  let next: Save = { ...save, onboarded: true, hero: { ...save.hero, name: name.trim().slice(0, 16) || 'Digger' } };
  next = giveItem(next, 'rusty_spade', 'start', events);
  next = syncPeriods(next, now);
  return { save: next, events };
}

// ---- Loading --------------------------------------------------------------

/** A board is only kept if it has the right shape; otherwise it is left empty and re-dealt. */
function validBoard(board: unknown): board is Board {
  const b = board as Partial<Board> | null;
  return (
    !!b &&
    typeof b.period === 'string' &&
    Array.isArray(b.quests) &&
    b.quests.every((q) => q && typeof q.key === 'string' && typeof q.title === 'string' && typeof q.xp === 'number')
  );
}

const clampIndex = (value: unknown, length: number, fallback: number) =>
  typeof value === 'number' && value >= 0 && value < length ? Math.floor(value) : fallback;

/**
 * Checks a save that came from storage or an import and fills in anything
 * missing, so an old or slightly broken save can never crash the app.
 * Returns null if it isn't a Spade save at all.
 */
export function repairSave(raw: unknown, now: Date): Save | null {
  if (!raw || typeof raw !== 'object') return null;
  const input = raw as Partial<Save>;
  if (typeof input.seed !== 'number' || typeof input.xp !== 'number') return null;
  const base = newSave(input.seed, now);
  const categories = { ...base.settings.categories };
  for (const c of CATEGORIES) {
    const v = input.settings?.categories?.[c];
    if (typeof v === 'boolean') categories[c] = v;
  }
  const inventory = Array.isArray(input.inventory) ? [...new Set(input.inventory.filter((id) => id in ITEM_BY_ID))] : [];
  const equipped: Save['equipped'] = {};
  for (const [slot, id] of Object.entries(input.equipped ?? {})) {
    if (id && inventory.includes(id) && ITEM_BY_ID[id].slot === slot) equipped[slot as Slot] = id;
  }
  const hero = input.hero ?? base.hero;
  return {
    ...base,
    createdAt: typeof input.createdAt === 'number' ? input.createdAt : base.createdAt,
    onboarded: !!input.onboarded,
    hero: {
      name: typeof hero.name === 'string' ? hero.name.slice(0, 16) : '',
      skin: clampIndex(hero.skin, LOOKS.skin.length, base.hero.skin),
      hair: clampIndex(hero.hair, LOOKS.hair.length, base.hero.hair),
      hairStyle: clampIndex(hero.hairStyle, LOOKS.hairStyles.length, base.hero.hairStyle),
      scarf: clampIndex(hero.scarf, LOOKS.scarf.length, base.hero.scarf),
      hoodDown: hero.hoodDown === true,
    },
    xp: Math.max(0, Math.floor(input.xp)),
    inventory,
    equipped,
    boards: {
      daily: validBoard(input.boards?.daily) ? input.boards.daily : base.boards.daily,
      weekly: validBoard(input.boards?.weekly) ? input.boards.weekly : base.boards.weekly,
      monthly: validBoard(input.boards?.monthly) ? input.boards.monthly : base.boards.monthly,
    },
    recent: { ...base.recent, ...(input.recent ?? {}) },
    streak: { count: input.streak?.count ?? 0, lastDay: input.streak?.lastDay ?? null },
    activeDays: Array.isArray(input.activeDays) ? input.activeDays.slice(-60) : [],
    counts: { ...base.counts, ...(input.counts ?? {}) },
    feats: { ...(input.feats ?? {}) },
    custom: Array.isArray(input.custom) ? input.custom : [],
    settings: {
      retro: input.settings?.retro ?? true,
      sound: input.settings?.sound ?? true,
      haptics: input.settings?.haptics ?? true,
      // A save from before the guide existed belongs to someone who already knows the game.
      guideSeen: input.settings?.guideSeen ?? !!input.onboarded,
      newHero: input.settings?.newHero ?? true,
      celShading: input.settings?.celShading ?? true,
      categories,
    },
  };
}
