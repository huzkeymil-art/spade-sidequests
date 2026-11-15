import { describe, expect, it } from 'vitest';
import { FEATS, ITEMS, QUESTS } from './content';
import { dayKey, monthKey, monthProgress, nextReset, shiftDay, weekDays, weekKey, weekdayIndex } from './periods';
import { DEAL_COUNT, dealBoard } from './quests';
import { MILESTONES, levelInfo, questXp, rankFor, rollLoot, xpToNext } from './rewards';
import { makeRng } from './rng';
import { addCustomQuest, beginJourney, equip, markQuest, newSave, removeCustomQuest, repairSave, rerollDaily, rerollsLeft, syncPeriods } from './state';
import { ITEM_MODELS } from '../three/models/items';
import type { Cadence, GameEvent, Save } from './types';

const at = (y: number, m: number, d: number, h = 12) => new Date(y, m - 1, d, h);

function started(now = at(2026, 11, 14)): Save {
  return beginJourney(newSave(12345, now), 'Tess', now).save;
}

/** Completes every quest on a board, returning the save and all events. */
function clearBoard(save: Save, cadence: Cadence, now: Date) {
  const events: GameEvent[] = [];
  let next = save;
  for (const quest of save.boards[cadence].quests) {
    for (let i = 0; i < quest.target; i++) {
      const out = markQuest(next, cadence, quest.key, now);
      next = out.save;
      events.push(...out.events);
    }
  }
  return { save: next, events };
}

describe('periods', () => {
  it('names days and months from the local date', () => {
    expect(dayKey(at(2026, 3, 7))).toBe('2026-03-07');
    expect(monthKey(at(2026, 3, 7))).toBe('2026-03');
  });

  it('starts weeks on Monday', () => {
    // 14 Nov 2026 is a Saturday.
    expect(weekdayIndex(at(2026, 11, 14))).toBe(5);
    expect(weekKey(at(2026, 11, 9))).toBe('2026-W46'); // Monday
    expect(weekKey(at(2026, 11, 15))).toBe('2026-W46'); // Sunday
    expect(weekKey(at(2026, 11, 16))).toBe('2026-W47'); // next Monday
    expect(weekDays(at(2026, 11, 14))[0]).toBe('2026-11-09');
    expect(weekDays(at(2026, 11, 14))[6]).toBe('2026-11-15');
  });

  it('handles weeks that straddle a new year', () => {
    expect(weekKey(at(2026, 12, 31))).toBe('2026-W53');
    expect(weekKey(at(2027, 1, 3))).toBe('2026-W53'); // still the old year's last week
    expect(weekKey(at(2027, 1, 4))).toBe('2027-W01');
    expect(weekKey(at(2024, 12, 30))).toBe('2025-W01'); // belongs to the new year already
  });

  it('shifts days across month and year edges', () => {
    expect(shiftDay('2026-03-01', -1)).toBe('2026-02-28');
    expect(shiftDay('2026-12-31', 1)).toBe('2027-01-01');
  });

  it('knows when each board resets', () => {
    const now = at(2026, 11, 14, 15);
    expect(dayKey(nextReset('daily', now))).toBe('2026-11-15');
    expect(dayKey(nextReset('weekly', now))).toBe('2026-11-16');
    expect(dayKey(nextReset('monthly', now))).toBe('2026-12-01');
    expect(nextReset('daily', now).getHours()).toBe(0);
  });

  it('measures how far through the month it is', () => {
    expect(monthProgress(at(2026, 11, 30))).toBe(1);
    expect(monthProgress(at(2026, 11, 1))).toBeCloseTo(1 / 30);
  });
});

describe('content', () => {
  it('has a 3D model for every item, in the right slot', () => {
    for (const item of ITEMS) {
      expect(ITEM_MODELS[item.id], item.id).toBeDefined();
      expect(ITEM_MODELS[item.id].slot, item.id).toBe(item.slot);
    }
  });

  it('has unique ids and enough quests in every category to fill a board', () => {
    expect(new Set(QUESTS.map((q) => q.id)).size).toBe(QUESTS.length);
    expect(new Set(ITEMS.map((i) => i.id)).size).toBe(ITEMS.length);
    expect(new Set(FEATS.map((f) => f.id)).size).toBe(FEATS.length);
    for (const cadence of ['daily', 'weekly', 'monthly'] as const) {
      for (const category of ['body', 'mind', 'craft', 'heart', 'home'] as const) {
        const n = QUESTS.filter((q) => q.cadence === cadence && q.category === category).length;
        expect(n, `${cadence}/${category}`).toBeGreaterThanOrEqual(DEAL_COUNT[cadence]);
      }
    }
  });

  it('only rewards items that exist', () => {
    for (const feat of FEATS) if (feat.item) expect(ITEMS.some((i) => i.id === feat.item), feat.id).toBe(true);
    expect(FEATS.find((f) => f.id === 'museum_piece')?.goal).toBe(ITEMS.length);
  });
});

describe('dealing', () => {
  const ctx = {
    seed: 99,
    custom: [],
    categories: { body: true, mind: true, craft: true, heart: true, home: true },
    recent: [] as string[],
  };

  it('deals the same board for the same day, and a different one the next day', () => {
    const a = dealBoard('daily', '2026-11-14', ctx);
    const b = dealBoard('daily', '2026-11-14', ctx);
    const c = dealBoard('daily', '2026-11-15', ctx);
    expect(a).toEqual(b);
    expect(a.quests.map((q) => q.defId)).not.toEqual(c.quests.map((q) => q.defId));
  });

  it('deals the right number, from different categories', () => {
    for (const cadence of ['daily', 'weekly', 'monthly'] as const) {
      const board = dealBoard(cadence, 'x', ctx);
      expect(board.quests).toHaveLength(DEAL_COUNT[cadence]);
      expect(new Set(board.quests.map((q) => q.category)).size).toBe(DEAL_COUNT[cadence]);
    }
  });

  it('never repeats a quest two days running', () => {
    let save = started();
    for (let day = 15; day <= 28; day++) {
      const before = save.boards.daily.quests.map((q) => q.defId);
      save = syncPeriods(save, at(2026, 11, day));
      const after = save.boards.daily.quests.map((q) => q.defId);
      expect(after.some((id) => before.includes(id))).toBe(false);
    }
  });

  it('respects switched-off categories', () => {
    const board = dealBoard('daily', 'x', { ...ctx, categories: { ...ctx.categories, body: false, home: false } });
    expect(board.quests.every((q) => q.category !== 'body' && q.category !== 'home')).toBe(true);
  });

  it('saves one place in every deal for your own shuffled-in quests', () => {
    const custom = [1, 2, 3].map((n) => ({
      id: `own${n}`, cadence: 'daily' as const, category: 'mind' as const, difficulty: 1 as const, title: `Mine ${n}`, pinned: false,
    }));
    const seen = new Set<string>();
    let recent: string[] = [];
    for (let day = 1; day <= 12; day++) {
      const board = dealBoard('daily', `2026-11-${day}`, { ...ctx, custom, recent });
      expect(board.quests).toHaveLength(3);
      const own = board.quests.filter((q) => q.custom);
      expect(own.length).toBeGreaterThanOrEqual(1);
      expect(new Set(board.quests.map((q) => q.defId)).size).toBe(3);
      // The reserved place goes to one not dealt last time.
      expect(recent).not.toContain(board.quests[0].defId);
      own.forEach((q) => seen.add(q.defId));
      recent = board.quests.map((q) => q.defId);
    }
    expect(seen.size).toBe(3);
  });

  it('always shows pinned custom quests, and still leaves room for a surprise', () => {
    const custom = [1, 2, 3, 4].map((n) => ({
      id: `c${n}`, cadence: 'daily' as const, category: 'mind' as const, difficulty: 1 as const, title: `Mine ${n}`, pinned: true,
    }));
    const board = dealBoard('daily', 'x', { ...ctx, custom });
    expect(board.quests.filter((q) => q.pinned)).toHaveLength(4);
    expect(board.quests.filter((q) => !q.pinned)).toHaveLength(1);
  });
});

describe('levels', () => {
  it('asks for 50 more XP each level', () => {
    expect(xpToNext(1)).toBe(100);
    expect(xpToNext(2)).toBe(150);
    expect(levelInfo(0)).toEqual({ level: 1, into: 0, need: 100 });
    expect(levelInfo(99).level).toBe(1);
    expect(levelInfo(100)).toEqual({ level: 2, into: 0, need: 150 });
    expect(levelInfo(250).level).toBe(3);
  });

  it('pays more for harder and longer quests', () => {
    expect(questXp('daily', 1)).toBeLessThan(questXp('daily', 3));
    expect(questXp('daily', 3)).toBeLessThan(questXp('weekly', 1));
    expect(questXp('weekly', 3)).toBeLessThan(questXp('monthly', 1));
  });

  it('gives a rank title for any level', () => {
    expect(rankFor(1)).toBe('Greenhand');
    expect(rankFor(7)).toBe('Delver');
    expect(rankFor(99)).toBe('Legend of the Loam');
  });
});

describe('loot', () => {
  it('always drops for weekly and monthly quests, at the promised rarity or better', () => {
    const rng = makeRng(7);
    for (let i = 0; i < 300; i++) {
      const weekly = rollLoot('weekly', rng, []);
      const monthly = rollLoot('monthly', rng, []);
      expect(weekly && weekly.item.rarity !== 'common').toBe(true);
      expect(monthly && (monthly.item.rarity === 'rare' || monthly.item.rarity === 'mythic')).toBe(true);
    }
  });

  it('drops for roughly one daily quest in eight', () => {
    const rng = makeRng(3);
    let drops = 0;
    for (let i = 0; i < 4000; i++) if (rollLoot('daily', rng, [])) drops++;
    expect(drops / 4000).toBeGreaterThan(0.09);
    expect(drops / 4000).toBeLessThan(0.15);
  });

  it('prefers items you do not own, and flags duplicates', () => {
    const rng = makeRng(11);
    const mythics = ITEMS.filter((i) => i.source === 'loot' && i.rarity === 'mythic').map((i) => i.id);
    for (let i = 0; i < 200; i++) {
      const roll = rollLoot('monthly', rng, [mythics[0]]);
      if (roll?.item.rarity === 'mythic') {
        expect(roll.item.id).not.toBe(mythics[0]);
        expect(roll.fresh).toBe(true);
      }
    }
    const allLoot = ITEMS.filter((i) => i.source === 'loot').map((i) => i.id);
    expect(rollLoot('weekly', rng, allLoot)?.fresh).toBe(false);
  });
});

describe('playing', () => {
  it('starts with the Rusty Spade to dig up and all three boards dealt', () => {
    const now = at(2026, 11, 14);
    const { save, events } = beginJourney(newSave(1, now), '  ', now);
    expect(events).toEqual([{ type: 'item', itemId: 'rusty_spade', fresh: true, echoXp: 0, from: 'start' }]);
    expect(save.hero.name).toBe('Digger'); // a blank name gets a default
    expect(save.inventory).toEqual(['rusty_spade']);
    expect(save.equipped.hand).toBeUndefined();
    expect(save.boards.daily.quests).toHaveLength(3);
    expect(save.boards.weekly.quests).toHaveLength(3);
    expect(save.boards.monthly.quests).toHaveLength(2);
  });

  it('pays XP once, starts the streak, and earns the first feat', () => {
    const now = at(2026, 11, 14);
    const save = started(now);
    const quest = save.boards.daily.quests.find((q) => q.target === 1)!;
    const { save: after, events } = markQuest(save, 'daily', quest.key, now);
    expect(events[0]).toEqual({ type: 'xp', amount: quest.xp, reason: 'quest' });
    expect(events.some((e) => e.type === 'feat' && e.id === 'broken_ground')).toBe(true);
    expect(after.streak).toEqual({ count: 1, lastDay: '2026-11-14' });
    expect(after.xp).toBeGreaterThanOrEqual(quest.xp + 25);
    // Marking it again does nothing.
    const again = markQuest(after, 'daily', quest.key, now);
    expect(again.events).toEqual([]);
    expect(again.save.xp).toBe(after.xp);
  });

  it('counts up a multi-step quest before completing it', () => {
    const now = at(2026, 11, 14);
    let save = started(now);
    const board = save.boards.weekly;
    const counted = { ...board.quests[0], target: 3 };
    save = { ...save, boards: { ...save.boards, weekly: { ...board, quests: [counted, ...board.quests.slice(1)] } } };
    let out = markQuest(save, 'weekly', counted.key, now);
    expect(out.events).toEqual([]);
    expect(out.save.boards.weekly.quests[0]).toMatchObject({ progress: 1, done: false });
    out = markQuest(out.save, 'weekly', counted.key, now);
    out = markQuest(out.save, 'weekly', counted.key, now);
    expect(out.save.boards.weekly.quests[0].done).toBe(true);
    expect(out.events.some((e) => e.type === 'item')).toBe(true); // weekly quests always dig something up
  });

  it('pays the clear bonus exactly once when every daily is done', () => {
    const now = at(2026, 11, 14);
    const { save, events } = clearBoard(started(now), 'daily', now);
    expect(events.filter((e) => e.type === 'clear')).toHaveLength(1);
    expect(save.counts.dailyClears).toBe(1);
    expect(save.feats.full_lantern).toBeDefined();
  });

  it('grows the streak day by day and puts it out after a missed day', () => {
    let save = started(at(2026, 11, 14));
    for (let day = 14; day <= 16; day++) {
      const now = at(2026, 11, day);
      save = syncPeriods(save, now);
      save = markQuest(save, 'daily', save.boards.daily.quests.find((q) => q.target === 1)!.key, now).save;
    }
    expect(save.streak.count).toBe(3);
    expect(save.feats.kindling).toBeDefined();
    // The 17th is skipped. On the 17th the streak is still alive (yesterday counted)...
    expect(syncPeriods(save, at(2026, 11, 17)).streak.count).toBe(3);
    // ...but by the 18th it has gone out.
    save = syncPeriods(save, at(2026, 11, 18));
    expect(save.streak.count).toBe(0);
    expect(save.counts.bestStreak).toBe(3);
    save = markQuest(save, 'daily', save.boards.daily.quests.find((q) => q.target === 1)!.key, at(2026, 11, 18)).save;
    expect(save.streak.count).toBe(1);
  });

  it('resets each board on its own schedule', () => {
    let save = started(at(2026, 11, 14)); // Saturday
    const first = { ...save.boards };
    save = syncPeriods(save, at(2026, 11, 15)); // Sunday: only daily changes
    expect(save.boards.daily.period).toBe('2026-11-15');
    expect(save.boards.weekly).toBe(first.weekly);
    expect(save.boards.monthly).toBe(first.monthly);
    save = syncPeriods(save, at(2026, 11, 16)); // Monday: weekly changes too
    expect(save.boards.weekly.period).toBe('2026-W47');
    expect(save.boards.monthly).toBe(first.monthly);
    save = syncPeriods(save, at(2026, 12, 1)); // 1st: monthly changes
    expect(save.boards.monthly.period).toBe('2026-12');
  });

  it('levels up, hands out milestone items, and keeps total XP consistent', () => {
    let save = started(at(2026, 11, 1));
    const seenLevels: number[] = [];
    let earned = 0;
    for (let day = 1; day <= 28; day++) {
      const now = at(2026, 11, day);
      save = syncPeriods(save, now);
      for (const cadence of ['daily', 'weekly', 'monthly'] as const) {
        const out = clearBoard(save, cadence, now);
        save = out.save;
        for (const e of out.events) {
          if (e.type === 'xp') earned += e.amount;
          if (e.type === 'level') seenLevels.push(e.level);
        }
      }
    }
    expect(save.xp).toBe(earned);
    const level = levelInfo(save.xp).level;
    expect(level).toBeGreaterThanOrEqual(10);
    expect(seenLevels).toEqual(Array.from({ length: level - 1 }, (_, i) => i + 2)); // every level announced once
    for (const [at, id] of Object.entries(MILESTONES)) {
      if (Number(at) <= level) expect(save.inventory, id).toContain(id);
    }
    expect(new Set(save.inventory).size).toBe(save.inventory.length); // no duplicates in the bag
  });

  it('allows one daily swap, never onto a quest already on the board', () => {
    const save = started();
    expect(rerollsLeft(save)).toBe(1);
    const target = save.boards.daily.quests[0];
    const swapped = rerollDaily(save, target.key);
    const ids = swapped.boards.daily.quests.map((q) => q.defId);
    expect(ids).not.toContain(target.defId);
    expect(new Set(ids).size).toBe(3);
    expect(rerollsLeft(swapped)).toBe(0);
    expect(rerollDaily(swapped, swapped.boards.daily.quests[1].key)).toBe(swapped);
  });

  it('adds, pins and removes custom quests', () => {
    const now = at(2026, 11, 14);
    const save = started(now);
    const pinned = addCustomQuest(save, { title: '  Feed the cat ', cadence: 'daily', category: 'home', difficulty: 1, pinned: true }, now);
    expect(pinned.save.boards.daily.quests[0]).toMatchObject({ title: 'Feed the cat', custom: true, pinned: true, xp: 20 });
    expect(pinned.events.some((e) => e.type === 'feat' && e.id === 'own_path')).toBe(true);
    // Unpinned ones go on the board straight away too, not only in a later deal.
    const loose = addCustomQuest(pinned.save, { title: 'Juggle', cadence: 'daily', category: 'craft', difficulty: 3, pinned: false }, now);
    expect(loose.save.boards.daily.quests).toHaveLength(5);
    expect(loose.save.boards.daily.quests[0]).toMatchObject({ title: 'Juggle', custom: true, pinned: false, xp: 45 });
    const removed = removeCustomQuest(loose.save, pinned.save.custom[0].id);
    expect(removed.custom).toHaveLength(1);
    expect(removed.boards.daily.quests).toHaveLength(4);
    expect(removeCustomQuest(removed, loose.save.custom[1].id).boards.daily.quests).toHaveLength(3);
    expect(addCustomQuest(save, { title: '   ', cadence: 'daily', category: 'home', difficulty: 1, pinned: false }, now).save).toBe(save);
  });

  it('only equips items that are owned and fit the slot', () => {
    const now = at(2026, 11, 14);
    const save = { ...started(now), inventory: ['rusty_spade', 'wool_cap'] };
    expect(equip(save, 'head', 'straw_hat', now).save).toBe(save); // not owned
    expect(equip(save, 'head', 'rusty_spade', now).save).toBe(save); // wrong slot
    const worn = equip(save, 'head', 'wool_cap', now).save;
    expect(worn.equipped.head).toBe('wool_cap');
    expect(equip(worn, 'head', null, now).save.equipped.head).toBeUndefined();
  });
});

describe('saves', () => {
  it('survives a round trip through JSON', () => {
    const now = at(2026, 11, 14);
    const save = clearBoard(started(now), 'daily', now).save;
    expect(repairSave(JSON.parse(JSON.stringify(save)), now)).toEqual(save);
  });

  it('repairs missing or nonsense fields instead of crashing', () => {
    const now = at(2026, 11, 14);
    const fixed = repairSave({ seed: 5, xp: -20, inventory: ['rusty_spade', 'not_real', 'rusty_spade'], equipped: { head: 'rusty_spade' }, hero: { skin: 99 } }, now)!;
    expect(fixed.xp).toBe(0);
    expect(fixed.inventory).toEqual(['rusty_spade']);
    expect(fixed.equipped).toEqual({});
    expect(fixed.hero.skin).toBe(1);
    expect(fixed.settings.categories.body).toBe(true);
    expect(fixed.settings.haptics).toBe(true);
    expect(fixed.settings.guideSeen).toBe(false); // never onboarded, so the guide is still to come
    expect(syncPeriods(fixed, now).boards.daily.quests).toHaveLength(3);
  });

  it('throws away boards that are the wrong shape and deals new ones', () => {
    const now = at(2026, 11, 14);
    const broken = { ...started(now), boards: { daily: { period: 5, quests: 'no' }, weekly: null } };
    const fixed = syncPeriods(repairSave(JSON.parse(JSON.stringify(broken)), now)!, now);
    expect(fixed.boards.daily.quests).toHaveLength(3);
    expect(fixed.boards.weekly.quests).toHaveLength(3);
    expect(fixed.boards.monthly.quests).toHaveLength(2);
  });

  it('does not show the guide to a returning player whose save predates it', () => {
    const now = at(2026, 11, 14);
    const old = JSON.parse(JSON.stringify(started(now)));
    delete old.settings.guideSeen;
    delete old.settings.haptics;
    const fixed = repairSave(old, now)!;
    expect(fixed.settings.guideSeen).toBe(true);
    expect(fixed.settings.haptics).toBe(true);
  });

  it('rejects things that are not saves', () => {
    expect(repairSave(null, new Date())).toBeNull();
    expect(repairSave('hello', new Date())).toBeNull();
    expect(repairSave({ name: 'nope' }, new Date())).toBeNull();
  });
});
