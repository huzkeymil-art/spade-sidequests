// The shapes of all the data in Spade. Nothing in this folder touches the
// screen: it is pure game rules, which is what makes it easy to carry over to
// a Swift version later.

export type Cadence = 'daily' | 'weekly' | 'monthly';
export const CADENCES: Cadence[] = ['daily', 'weekly', 'monthly'];

export type Category = 'body' | 'mind' | 'craft' | 'heart' | 'home';
export const CATEGORIES: Category[] = ['body', 'mind', 'craft', 'heart', 'home'];

export type Difficulty = 1 | 2 | 3;

export type Slot = 'head' | 'body' | 'hand' | 'shield' | 'charm';
export const SLOTS: Slot[] = ['head', 'body', 'hand', 'shield', 'charm'];

export type Rarity = 'common' | 'uncommon' | 'rare' | 'mythic';
export const RARITIES: Rarity[] = ['common', 'uncommon', 'rare', 'mythic'];

/** A quest as written in the deck. */
export interface QuestDef {
  id: string;
  cadence: Cadence;
  category: Category;
  difficulty: Difficulty;
  title: string;
  /** How many times it must be marked before it counts as done. Defaults to 1. */
  target?: number;
}

/** A quest the player wrote themselves. */
export interface CustomQuest extends QuestDef {
  /** Pinned quests show up every single period instead of being shuffled into the deck. */
  pinned: boolean;
}

/** A quest that has been dealt onto the board for the current day, week or month. */
export interface ActiveQuest {
  /** Unique for this deal, e.g. "2026-11-14:d_walk". */
  key: string;
  defId: string;
  cadence: Cadence;
  category: Category;
  title: string;
  xp: number;
  target: number;
  progress: number;
  done: boolean;
  custom: boolean;
  pinned: boolean;
}

export interface Board {
  /** Which day, week or month this board belongs to. */
  period: string;
  quests: ActiveQuest[];
  /** Swaps used this period. */
  rerolls: number;
  /** Whether the all-clear bonus has been paid. */
  cleared: boolean;
}

export interface ItemDef {
  id: string;
  name: string;
  slot: Slot;
  rarity: Rarity;
  /** starter: given at the beginning. loot: dug up at random. milestone: reaching `level`. feat: an achievement reward. */
  source: 'starter' | 'loot' | 'milestone' | 'feat';
  level?: number;
  lore: string;
}

export type StatName =
  | 'quests'
  | 'dailyClears'
  | 'bestStreak'
  | 'weekly'
  | 'monthly'
  | 'level'
  | 'items'
  | 'slotsFilled'
  | 'mythics'
  | 'customMade'
  | 'customDone';

export interface FeatDef {
  id: string;
  name: string;
  desc: string;
  stat: StatName;
  goal: number;
  xp: number;
  item?: string;
}

export interface HeroSave {
  name: string;
  /** Indexes into the palettes in content/looks.json. */
  skin: number;
  hair: number;
  hairStyle: number;
  scarf: number;
}

export interface Settings {
  retro: boolean;
  sound: boolean;
  categories: Record<Category, boolean>;
}

/** Everything that is remembered between visits. */
export interface Save {
  version: 1;
  /** A random number chosen once. It makes each player's shuffles different. */
  seed: number;
  createdAt: number;
  onboarded: boolean;
  hero: HeroSave;
  /** Total XP ever earned. The level is worked out from this. */
  xp: number;
  inventory: string[];
  equipped: Partial<Record<Slot, string>>;
  boards: Record<Cadence, Board>;
  /** Quest ids from the previous period, so they are not dealt twice in a row. */
  recent: Record<Cadence, string[]>;
  streak: { count: number; lastDay: string | null };
  /** Days on which at least one daily quest was finished (most recent last). */
  activeDays: string[];
  counts: {
    quests: number;
    daily: number;
    weekly: number;
    monthly: number;
    dailyClears: number;
    customDone: number;
    customMade: number;
    bestStreak: number;
  };
  /** Achievement id -> when it was earned. */
  feats: Record<string, number>;
  custom: CustomQuest[];
  settings: Settings;
}

/** Things that happened as the result of an action, in the order the app should show them. */
export type GameEvent =
  | { type: 'xp'; amount: number; reason: 'quest' | 'clear' | 'feat' | 'echo' }
  | { type: 'clear' }
  | { type: 'item'; itemId: string; fresh: boolean; echoXp: number; from: 'quest' | 'level' | 'feat' | 'start' }
  | { type: 'level'; level: number; rank: string | null }
  | { type: 'feat'; id: string };
