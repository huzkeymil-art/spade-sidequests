import questsJson from '../content/quests.json';
import itemsJson from '../content/items.json';
import featsJson from '../content/achievements.json';
import looksJson from '../content/looks.json';
import type { FeatDef, ItemDef, QuestDef } from './types';

// The game's content lives in plain JSON files (in src/content) so it can be
// edited without touching code, and reused as-is by another version of the app.

export const QUESTS = questsJson as QuestDef[];
export const ITEMS = itemsJson as ItemDef[];
export const FEATS = featsJson as FeatDef[];
export const LOOKS = looksJson as { skin: string[]; hair: string[]; scarf: string[]; hairStyles: string[] };

export const ITEM_BY_ID: Record<string, ItemDef> = Object.fromEntries(ITEMS.map((i) => [i.id, i]));
export const FEAT_BY_ID: Record<string, FeatDef> = Object.fromEntries(FEATS.map((f) => [f.id, f]));
