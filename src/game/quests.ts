import { QUESTS } from './content';
import { questXp } from './rewards';
import { rngFor, shuffled } from './rng';
import type { ActiveQuest, Board, Cadence, Category, CustomQuest, QuestDef } from './types';

// Dealing quests onto the board.

/** How many quests each board holds. */
export const DEAL_COUNT: Record<Cadence, number> = { daily: 3, weekly: 3, monthly: 2 };

/** Free swaps allowed on the daily board each day. */
export const DAILY_REROLLS = 1;

export interface DealContext {
  seed: number;
  custom: readonly CustomQuest[];
  categories: Record<Category, boolean>;
  /** Quest ids dealt last period: skipped if there is enough else to choose from. */
  recent: readonly string[];
}

function activate(def: QuestDef, period: string, custom: boolean, pinned: boolean): ActiveQuest {
  return {
    key: `${period}:${def.id}`,
    defId: def.id,
    cadence: def.cadence,
    category: def.category,
    title: def.title,
    xp: questXp(def.cadence, def.difficulty),
    target: Math.max(1, def.target ?? 1),
    progress: 0,
    done: false,
    custom,
    pinned,
  };
}

/** The board entry for one of the player's own quests. */
export function activateCustom(quest: CustomQuest, period: string): ActiveQuest {
  return activate(quest, period, true, quest.pinned);
}

/** Every quest that could be dealt for this cadence: built-in ones in enabled categories, plus unpinned custom ones. */
function deckFor(cadence: Cadence, ctx: DealContext): { def: QuestDef; custom: boolean }[] {
  const anyEnabled = Object.values(ctx.categories).some(Boolean);
  const builtIn = QUESTS.filter((q) => q.cadence === cadence && (!anyEnabled || ctx.categories[q.category]));
  const own = ctx.custom.filter((q) => q.cadence === cadence && !q.pinned);
  return [...builtIn.map((def) => ({ def, custom: false })), ...own.map((def) => ({ def, custom: true }))];
}

/**
 * Draws `count` quests from the deck, avoiding `exclude` and spreading across
 * categories where it can. The same seed and label always give the same draw.
 */
function draw(cadence: Cadence, ctx: DealContext, count: number, exclude: readonly string[], label: string) {
  const deck = deckFor(cadence, ctx);
  let pool = deck.filter((q) => !exclude.includes(q.def.id));
  if (pool.length < count) pool = deck; // not enough variety left: allow repeats rather than deal short
  const order = shuffled(pool, rngFor(ctx.seed, cadence, label));

  const picked: typeof order = [];
  const used = new Set<Category>();
  while (picked.length < count && order.length > 0) {
    let at = order.findIndex((q) => !used.has(q.def.category));
    if (at < 0) at = 0;
    const [next] = order.splice(at, 1);
    picked.push(next);
    used.add(next.def.category);
  }
  return picked;
}

/**
 * Picks one of the player's own shuffled-in quests for this period, preferring
 * one that wasn't dealt last time. Returns undefined if they have none.
 */
function pickOwn(cadence: Cadence, period: string, ctx: DealContext): CustomQuest | undefined {
  const own = ctx.custom.filter((q) => q.cadence === cadence && !q.pinned);
  if (own.length === 0) return undefined;
  const fresh = own.filter((q) => !ctx.recent.includes(q.id));
  return shuffled(fresh.length > 0 ? fresh : own, rngFor(ctx.seed, cadence, `${period}:own`))[0];
}

/** Deals a fresh board for the given day, week or month. */
export function dealBoard(cadence: Cadence, period: string, ctx: DealContext): Board {
  const pinned = ctx.custom.filter((q) => q.cadence === cadence && q.pinned);
  // Pinned quests take up places, but at least one place is always left over.
  const places = Math.max(1, DEAL_COUNT[cadence] - pinned.length);
  // One of those places always goes to one of the player's own shuffled-in quests,
  // if they have any. Otherwise a quest they wrote could take weeks to turn up.
  const own = pickOwn(cadence, period, ctx);
  const rest = own ? { ...ctx, custom: ctx.custom.filter((q) => q.id !== own.id) } : ctx;
  const drawn = draw(cadence, rest, places - (own ? 1 : 0), ctx.recent, period);
  return {
    period,
    quests: [
      ...pinned.map((def) => activate(def, period, true, true)),
      ...(own ? [activate(own, period, true, false)] : []),
      ...drawn.map(({ def, custom }) => activate(def, period, custom, false)),
    ],
    rerolls: 0,
    cleared: false,
  };
}

/** Swaps one unfinished quest for a different one. Returns null if there is nothing to swap in. */
export function swapQuest(board: Board, key: string, ctx: DealContext): Board | null {
  const at = board.quests.findIndex((q) => q.key === key);
  if (at < 0) return null;
  const old = board.quests[at];
  if (old.done || old.pinned) return null;
  const onBoard = board.quests.map((q) => q.defId);
  const [next] = draw(old.cadence, ctx, 1, [...onBoard, ...ctx.recent], `${board.period}:swap${board.rerolls}`);
  if (!next || onBoard.includes(next.def.id)) return null;
  const quests = board.quests.slice();
  quests[at] = activate(next.def, board.period, next.custom, false);
  return { ...board, quests, rerolls: board.rerolls + 1 };
}
