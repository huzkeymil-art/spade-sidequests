import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import {
  addCustomQuest,
  beginJourney,
  equip,
  markQuest,
  newSave,
  removeCustomQuest,
  repairSave,
  rerollDaily,
  syncPeriods,
  SAVE_VERSION,
  type CustomQuestInput,
} from './state';
import type { Cadence, Category, GameEvent, HeroSave, Save, Settings, Slot } from './types';

// The store: the one place the app's data lives while it is running.
//
// The rules in state.ts are pure functions. This file plugs them into the app:
// it holds the current save, runs a rule when the player does something, and
// writes the result to the phone's storage so it is still there next time.

export const STORAGE_KEY = 'spade.save.v1';

/** A reward moment that takes over the screen until the player dismisses it. */
export type Moment = Extract<GameEvent, { type: 'item' } | { type: 'level' }>;

/** A small notice that appears briefly and goes away on its own. */
export interface Toast {
  id: number;
  kind: 'feat' | 'clear';
  /** Feat id, when kind is "feat". */
  ref?: string;
}

interface Store {
  save: Save;
  /** The current time, refreshed every minute so countdowns stay right. */
  now: number;
  moments: Moment[];
  toasts: Toast[];

  sync(): void;
  begin(name: string): void;
  mark(cadence: Cadence, key: string): GameEvent[];
  reroll(key: string): void;
  addCustom(input: CustomQuestInput): void;
  removeCustom(id: string): void;
  equip(slot: Slot, itemId: string | null): void;
  setHero(patch: Partial<HeroSave>): void;
  setSettings(patch: Partial<Omit<Settings, 'categories'>>): void;
  toggleCategory(category: Category): void;
  nextMoment(): void;
  dropToast(id: number): void;
  exportSave(): string;
  importSave(text: string): boolean;
  reset(): void;
}

const freshSeed = () => Math.floor(Math.random() * 0x7fffffff);
let toastId = 1;

export const useStore = create<Store>()(
  persist(
    (set, get) => {
      /** Stores the new save and queues up anything worth celebrating. */
      const apply = (save: Save, events: GameEvent[]) => {
        const moments = events.filter((e): e is Moment => e.type === 'item' || e.type === 'level');
        const toasts: Toast[] = [];
        for (const e of events) {
          if (e.type === 'feat') toasts.push({ id: toastId++, kind: 'feat', ref: e.id });
          if (e.type === 'clear') toasts.push({ id: toastId++, kind: 'clear' });
        }
        set((s) => ({ save, moments: [...s.moments, ...moments], toasts: [...s.toasts, ...toasts] }));
      };

      return {
        save: newSave(freshSeed(), new Date()),
        now: Date.now(),
        moments: [],
        toasts: [],

        sync() {
          const now = new Date();
          const { save } = get();
          set({ now: now.getTime(), save: save.onboarded ? syncPeriods(save, now) : save });
        },

        begin(name) {
          const out = beginJourney(get().save, name, new Date());
          apply(out.save, out.events);
        },

        mark(cadence, key) {
          const out = markQuest(get().save, cadence, key, new Date());
          apply(out.save, out.events);
          return out.events;
        },

        reroll(key) {
          set((s) => ({ save: rerollDaily(s.save, key) }));
        },

        addCustom(input) {
          const out = addCustomQuest(get().save, input, new Date());
          apply(out.save, out.events);
        },

        removeCustom(id) {
          set((s) => ({ save: removeCustomQuest(s.save, id) }));
        },

        equip(slot, itemId) {
          const out = equip(get().save, slot, itemId, new Date());
          apply(out.save, out.events);
        },

        setHero(patch) {
          set((s) => ({ save: { ...s.save, hero: { ...s.save.hero, ...patch } } }));
        },

        setSettings(patch) {
          set((s) => ({ save: { ...s.save, settings: { ...s.save.settings, ...patch } } }));
        },

        toggleCategory(category) {
          set((s) => {
            const categories = { ...s.save.settings.categories, [category]: !s.save.settings.categories[category] };
            // Never allow every category to be off: there would be nothing to deal.
            if (!Object.values(categories).some(Boolean)) return s;
            return { save: { ...s.save, settings: { ...s.save.settings, categories } } };
          });
        },

        nextMoment() {
          set((s) => ({ moments: s.moments.slice(1) }));
        },

        dropToast(id) {
          set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }));
        },

        exportSave() {
          return JSON.stringify(get().save);
        },

        importSave(text) {
          try {
            const repaired = repairSave(JSON.parse(text), new Date());
            if (!repaired) return false;
            set({ save: repaired.onboarded ? syncPeriods(repaired, new Date()) : repaired, moments: [], toasts: [] });
            return true;
          } catch {
            return false;
          }
        },

        reset() {
          set({ save: newSave(freshSeed(), new Date()), moments: [], toasts: [] });
        },
      };
    },
    {
      name: STORAGE_KEY,
      version: SAVE_VERSION,
      // Only the save itself is written to storage; reward moments and toasts are fleeting.
      partialize: (s) => ({ save: s.save }),
      merge: (stored, current) => {
        const repaired = repairSave((stored as { save?: unknown } | undefined)?.save, new Date());
        return repaired ? { ...current, save: repaired } : current;
      },
    },
  ),
);
