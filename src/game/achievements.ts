import { FEATS, ITEM_BY_ID } from './content';
import { levelInfo } from './rewards';
import { SLOTS, type FeatDef, type Save, type StatName } from './types';

// Achievements ("feats"). Each one watches a single number, like "quests
// finished" or "best streak", and unlocks when that number reaches its goal.

/** Reads the current value of the number a feat watches. */
export function statValue(save: Save, stat: StatName): number {
  switch (stat) {
    case 'quests':
      return save.counts.quests;
    case 'dailyClears':
      return save.counts.dailyClears;
    case 'bestStreak':
      return save.counts.bestStreak;
    case 'weekly':
      return save.counts.weekly;
    case 'monthly':
      return save.counts.monthly;
    case 'customMade':
      return save.counts.customMade;
    case 'customDone':
      return save.counts.customDone;
    case 'level':
      return levelInfo(save.xp).level;
    case 'items':
      return save.inventory.length;
    case 'slotsFilled':
      return SLOTS.filter((slot) => save.equipped[slot]).length;
    case 'mythics':
      return save.inventory.filter((id) => ITEM_BY_ID[id]?.rarity === 'mythic').length;
  }
}

/** Progress toward a feat, capped at its goal. */
export function featProgress(save: Save, feat: FeatDef): { value: number; goal: number; done: boolean } {
  const done = feat.id in save.feats;
  const value = done ? feat.goal : Math.min(feat.goal, statValue(save, feat.stat));
  return { value, goal: feat.goal, done };
}

/** Feats whose goal has been reached but which haven't been awarded yet. */
export function pendingFeats(save: Save): FeatDef[] {
  return FEATS.filter((feat) => !(feat.id in save.feats) && statValue(save, feat.stat) >= feat.goal);
}
