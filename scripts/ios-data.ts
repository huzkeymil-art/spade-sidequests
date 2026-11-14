// Bakes data out of the web app for the Swift app to load.
//
// The web version is the source of truth for the 3D models, the textures, the
// camera positions and the game's content. Rather than retype all of that in
// Swift (and risk the two drifting apart), this script runs the real web code
// and writes its results to files inside ios/. Run it with `npm run ios:data`
// whenever a model, texture, quest, item or feat changes.

import { deflateSync } from 'node:zlib';
import { cpSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import * as THREE from 'three';

import { buildGeometry, mirrored, type Part } from '../src/three/parts';
import { getAtlas, getGlowTexture } from '../src/three/textures';
import { FACE_ROWS, HEAD, HERO_JOINTS, armParts, hairParts, headParts, legParts, tailParts, torsoParts, type HairStyle } from '../src/three/models/hero';
import { ITEM_MODELS, displayParts } from '../src/three/models/items';
import { PROPS } from '../src/three/models/props';
import {
  DIG_POS, HORIZON, LANTERN_POS, RUNE_ROWS, SKY_MID, SKY_TOP, STONE_POS,
  grassParts, lanternParts, makeGround, makeRidge, moteField, scatterParts, starField, treeParts, weekStoneParts,
} from '../src/three/scenery';
import { CLOD_COUNT, boxParts, clodParts, lidParts, moundParts } from '../src/three/unearth';
import { DEFAULT_HERO_YAW, DIG_HERO_YAW, FOV, SHOTS } from '../src/three/shots';

import { hashString, makeRng, rngFor, shuffled } from '../src/game/rng';
import { dayKey, monthKey, monthProgress, nextReset, weekDays, weekKey, weekdayIndex } from '../src/game/periods';
import { dealBoard, swapQuest } from '../src/game/quests';
import { levelInfo, rollLoot } from '../src/game/rewards';
import { addCustomQuest, beginJourney, equip, markQuest, newSave, rerollDaily, syncPeriods } from '../src/game/state';
import { ITEM_BY_ID } from '../src/game/content';
import type { Cadence, Category, CustomQuest, Save } from '../src/game/types';

// ---- Meshes ------------------------------------------------------------------

const round = (digits: number) => (v: number) => Math.round(v * 10 ** digits) / 10 ** digits;

interface Mesh {
  /** Positions, 3 numbers per corner. */
  p: number[];
  /** Normals (which way each corner faces), 3 per corner. */
  n: number[];
  /** Texture coordinates, 2 per corner. */
  uv: number[];
  /** Glow, 1 per corner: 0 is lit by the scene, 1 shines on its own. */
  e: number[];
  /** Corner indexes, 3 per triangle. */
  i: number[];
  /** Colour, 3 per corner. Missing on parts whose colour depends on the hero's look. */
  c?: number[];
  /** For look-dependent parts: 0 at the bottom of the part, 1 at the top. */
  t?: number[];
}

function toMesh(geo: THREE.BufferGeometry): Mesh {
  const attr = (name: string) => Array.from(geo.getAttribute(name).array as ArrayLike<number>);
  return {
    p: attr('position').map(round(4)),
    n: attr('normal').map(round(3)),
    uv: attr('uv').map(round(4)),
    e: attr('emit').map(round(2)),
    i: Array.from(geo.getIndex()!.array as ArrayLike<number>),
    c: attr('tint').map(round(3)),
  };
}

const bake = (parts: Part[]): Mesh => toMesh(buildGeometry(parts));

// The hero's colours are chosen by the player, so their parts can't have colour baked in.
// Each look-dependent colour is stood in for by a marker; the Swift app paints the real one.
const MARKERS = { skin: '#000001', hair: '#000002', scarf: '#000003', tunic: '#000004', sleeve: '#000005' } as const;
type Role = keyof typeof MARKERS;
const roleOf = (hex: string): Role | null => (Object.keys(MARKERS) as Role[]).find((k) => MARKERS[k] === hex) ?? null;

interface Chunk {
  /** Which of the hero's colours paints this part, or null if its colour is fixed. */
  role: Role | null;
  /** True when the part is one flat colour instead of shading darker toward the bottom. */
  flat: boolean;
  mesh: Mesh;
}

function chunk(part: Part): Chunk {
  const role = roleOf(part.c);
  if (!role) return { role: null, flat: false, mesh: bake([part]) };
  // Painting the part white-to-black makes its red channel equal the shading factor.
  const mesh = bake([{ ...part, c: '#ffffff', c2: '#000000' }]);
  const t = mesh.c!.filter((_, i) => i % 3 === 0);
  delete mesh.c;
  return { role, flat: part.c2 === part.c, mesh: { ...mesh, t } };
}

const chunks = (parts: Part[]) => parts.map(chunk);

// ---- PNG writer ----------------------------------------------------------------

const crcTable = new Int32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c;
});

function crc32(buffer: Uint8Array): number {
  let c = -1;
  for (const byte of buffer) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function pngChunk(type: string, data: Buffer): Buffer {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'ascii');
  const tail = Buffer.alloc(4);
  tail.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, tail]);
}

/** Packs RGBA pixels (top row first) into a PNG file. */
function png(width: number, height: number, rgba: Uint8Array): Buffer {
  const raw = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    raw.set(rgba.subarray(y * width * 4, (y + 1) * width * 4), y * (width * 4 + 1) + 1);
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6; // colour type: RGBA
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk('IHDR', header),
    pngChunk('IDAT', deflateSync(raw, { level: 9 })),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

/** Pixel art from rows of text, top row first. */
function pixelArt(rows: string[], key: Record<string, [number, number, number, number]>): Buffer {
  const height = rows.length;
  const width = rows[0].length;
  const data = new Uint8Array(width * height * 4);
  rows.forEach((row, y) => {
    for (let x = 0; x < width; x++) data.set(key[row[x]] ?? [0, 0, 0, 0], (y * width + x) * 4);
  });
  return png(width, height, data);
}

// ---- Parity fixtures -------------------------------------------------------------
// Answers worked out by the web rules. The Swift tests must get exactly the same.

const at = (y: number, m: number, d: number, h = 12) => new Date(y, m - 1, d, h);
const ALL_ON: Record<Category, boolean> = { body: true, mind: true, craft: true, heart: true, home: true };

function parityFixtures() {
  const hashes = ['', 'spade', '12345|daily|2026-11-14', 'héllo ✓ wörld', 'c_abc123_0'].map((text) => ({ text, hash: hashString(text) }));

  const rng = [1, 99, 4242, 2147483646, 4294967295].map((seed) => {
    const next = makeRng(seed);
    return { seed, values: Array.from({ length: 6 }, () => next()) };
  });

  const labelled = [
    { seed: 99, labels: ['daily', '2026-11-14'] },
    { seed: 12345, labels: ['loot', '2026-W46:w_active'] },
  ].map(({ seed, labels }) => {
    const next = rngFor(seed, ...labels);
    return { seed, labels, values: Array.from({ length: 4 }, () => next()) };
  });

  const shuffles = [3, 77].map((seed) => ({ seed, result: shuffled([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], makeRng(seed)) }));

  const dates: [number, number, number][] = [
    [2026, 11, 14], [2026, 11, 15], [2026, 11, 16], [2026, 12, 31], [2027, 1, 1], [2027, 1, 3], [2027, 1, 4],
    [2024, 12, 30], [2024, 2, 29], [2025, 3, 30], [2026, 3, 1], [2026, 10, 25], [2028, 2, 28], [2021, 1, 3],
  ];
  const periods = dates.map(([y, m, d]) => {
    const date = at(y, m, d);
    return {
      y, m, d,
      day: dayKey(date),
      week: weekKey(date),
      month: monthKey(date),
      weekday: weekdayIndex(date),
      monthProgress: monthProgress(date),
      weekDays: weekDays(date),
      nextDaily: dayKey(nextReset('daily', date)),
      nextWeekly: dayKey(nextReset('weekly', date)),
      nextMonthly: dayKey(nextReset('monthly', date)),
    };
  });

  const pinned: CustomQuest[] = [
    { id: 'c_one', cadence: 'daily', category: 'home', difficulty: 1, title: 'Feed the cat', pinned: true },
    { id: 'c_two', cadence: 'daily', category: 'craft', difficulty: 3, title: 'Juggle', pinned: false },
    { id: 'c_three', cadence: 'weekly', category: 'mind', difficulty: 2, title: 'Chess club', pinned: true },
  ];
  const dealCases: { seed: number; cadence: Cadence; period: string; recent: string[]; off: Category[]; custom: CustomQuest[] }[] = [
    { seed: 1, cadence: 'daily', period: '2026-11-14', recent: [], off: [], custom: [] },
    { seed: 1, cadence: 'daily', period: '2026-11-15', recent: [], off: [], custom: [] },
    { seed: 99, cadence: 'daily', period: '2026-11-14', recent: ['d_walk', 'd_read', 'd_bed'], off: [], custom: [] },
    { seed: 99, cadence: 'weekly', period: '2026-W46', recent: [], off: [], custom: [] },
    { seed: 99, cadence: 'monthly', period: '2026-11', recent: [], off: [], custom: [] },
    { seed: 12345, cadence: 'daily', period: '2027-01-01', recent: [], off: ['body', 'home'], custom: [] },
    { seed: 12345, cadence: 'weekly', period: '2026-W53', recent: [], off: ['mind', 'craft', 'heart', 'home'], custom: [] },
    { seed: 4242, cadence: 'daily', period: '2026-11-27', recent: [], off: [], custom: pinned },
    { seed: 4242, cadence: 'weekly', period: '2026-W48', recent: [], off: [], custom: pinned },
  ];
  const deals = dealCases.map((c) => {
    const categories = { ...ALL_ON };
    for (const off of c.off) categories[off] = false;
    const board = dealBoard(c.cadence, c.period, { seed: c.seed, custom: c.custom, categories, recent: c.recent });
    return { ...c, quests: board.quests.map((q) => ({ key: q.key, defId: q.defId, xp: q.xp, target: q.target, custom: q.custom, pinned: q.pinned })) };
  });

  const swaps = [1, 99, 4242].map((seed) => {
    const ctx = { seed, custom: [], categories: ALL_ON, recent: ['d_walk'] };
    const board = dealBoard('daily', '2026-11-14', ctx);
    const swapped = swapQuest(board, board.quests[1].key, ctx)!;
    return { seed, before: board.quests.map((q) => q.defId), after: swapped.quests.map((q) => q.defId) };
  });

  const loot: { seed: number; key: string; cadence: Cadence; owned: string[]; item: string | null; fresh: boolean }[] = [];
  const someOwned = ['oak_staff', 'wool_cap', 'miners_pick', 'barrow_helm', 'crown_of_roots', 'moon_mirror', 'wayfinders_crook', 'moonsteel_plate', 'foxfire_wisp'];
  for (const cadence of ['daily', 'weekly', 'monthly'] as const) {
    for (let n = 0; n < 40; n++) {
      const key = `p${n}:q_${cadence}`;
      const owned = n % 2 === 0 ? [] : someOwned;
      const roll = rollLoot(cadence, rngFor(555, 'loot', key), owned);
      loot.push({ seed: 555, key, cadence, owned, item: roll ? roll.item.id : null, fresh: roll ? roll.fresh : false });
    }
  }

  const levels = [0, 99, 100, 249, 250, 1480, 5950, 123456].map((xp) => ({ xp, ...levelInfo(xp) }));

  return { hashes, rng, labelled, shuffles, periods, deals, swaps, loot, levels, scenario: scenario() };
}

/** Plays 45 days with a fixed seed. The Swift port must end in exactly the same place. */
function scenario() {
  const seed = 777;
  let save: Save = beginJourney(newSave(seed, at(2026, 11, 1)), 'Tess', at(2026, 11, 1)).save;
  save = equip(save, 'hand', 'rusty_spade', at(2026, 11, 1)).save;
  const levelsSeen: number[] = [];
  const itemsSeen: string[] = [];
  let totalEvents = 0;

  const absorb = (out: { save: Save; events: { type: string }[] }, now: Date) => {
    save = out.save;
    totalEvents += out.events.length;
    for (const e of out.events as ({ type: 'level'; level: number } | { type: 'item'; itemId: string; fresh: boolean } | { type: 'xp' })[]) {
      if (e.type === 'level') levelsSeen.push(e.level);
      if (e.type === 'item') {
        itemsSeen.push(`${e.itemId}:${e.fresh ? 'new' : 'again'}`);
        // Wear every new find, so the "all five slots" feat can trigger.
        if (e.fresh) absorb(equip(save, ITEM_BY_ID[e.itemId].slot, e.itemId, now), now);
      }
    }
  };

  for (let day = 0; day < 45; day++) {
    if (day === 19 || day === 20) continue; // two days off: the streak goes out
    const now = new Date(2026, 10, 1 + day, 12);
    save = syncPeriods(save, now);
    if (day === 4) absorb(addCustomQuest(save, { title: 'Feed the cat', cadence: 'daily', category: 'home', difficulty: 1, pinned: true }, now), now);
    if (day === 6) absorb(addCustomQuest(save, { title: 'Juggle three balls', cadence: 'daily', category: 'craft', difficulty: 3, pinned: false }, now), now);
    if (day === 8) save = rerollDaily(save, save.boards.daily.quests.find((q) => !q.pinned)!.key);
    for (const cadence of ['daily', 'weekly', 'monthly'] as const) {
      for (const quest of save.boards[cadence].quests) {
        if (quest.done) continue;
        for (let step = quest.progress; step < quest.target; step++) absorb(markQuest(save, cadence, quest.key, now), now);
      }
    }
  }

  return {
    seed,
    xp: save.xp,
    level: levelInfo(save.xp).level,
    inventory: save.inventory,
    equipped: save.equipped,
    counts: save.counts,
    streak: save.streak,
    feats: Object.keys(save.feats).sort(),
    activeDays: save.activeDays,
    customIds: save.custom.map((q) => q.id),
    daily: save.boards.daily.quests.map((q) => q.defId),
    weekly: save.boards.weekly.quests.map((q) => q.defId),
    monthly: save.boards.monthly.quests.map((q) => q.defId),
    levelsSeen,
    itemsSeen,
    totalEvents,
    // The save exactly as the web app's "Back up save" writes it, to prove the Swift app can read one.
    saveJson: JSON.stringify(save),
  };
}

// ---- Run ---------------------------------------------------------------------------

export function run(root: string) {
  const resources = join(root, 'ios/Spade/Resources');
  const content = join(root, 'ios/Core/Sources/SpadeCore/Content');
  const fixtures = join(root, 'ios/Core/Tests/SpadeCoreTests/Fixtures');
  for (const dir of [resources, content, fixtures]) mkdirSync(dir, { recursive: true });

  // 1. Game content, copied as-is.
  cpSync(join(root, 'src/content'), content, { recursive: true });

  // 2. Models.
  const palette = MARKERS;
  const [tail1, tail2] = tailParts(palette);
  const hair = Object.fromEntries(
    (['crop', 'tuft', 'long', 'knot', 'none'] as HairStyle[]).map((style) => {
      const parts = hairParts(style, MARKERS.hair);
      return [style, { top: chunks(parts.top), under: chunks(parts.under) }];
    }),
  );

  const items = Object.fromEntries(
    Object.entries(ITEM_MODELS).map(([id, model]) => {
      const out: Record<string, unknown> = { slot: model.slot, display: bake(displayParts(model)) };
      if (model.slot === 'body') {
        out.tunic = model.tunic ?? null;
        out.sleeve = model.sleeve ?? null;
        if (model.torso?.length) out.torso = bake(model.torso);
        if (model.shoulder?.length) {
          out.shoulderR = bake(model.shoulder);
          out.shoulderL = bake(mirrored(model.shoulder));
        }
      } else {
        out.mesh = bake(model.parts);
        if (model.slot === 'head') out.hair = model.hair;
        if (model.slot === 'charm') out.glow = model.glow ?? null;
      }
      return [id, out];
    }),
  );

  const stars = starField();
  const motes = moteField();
  const rgb = (c: THREE.Color) => [c.r, c.g, c.b].map(round(4));

  const models = {
    shots: SHOTS,
    fov: FOV,
    heroYaw: DEFAULT_HERO_YAW,
    digHeroYaw: DIG_HERO_YAW,
    places: {
      lantern: LANTERN_POS.toArray(),
      dig: DIG_POS.toArray(),
      stone: STONE_POS.toArray(),
    },
    sky: { top: rgb(SKY_TOP), mid: rgb(SKY_MID), horizon: rgb(HORIZON) },
    hero: {
      joints: HERO_JOINTS,
      head: HEAD,
      torso: chunks(torsoParts(palette)),
      armR: chunks(armParts(palette)),
      armL: chunks(mirrored(armParts(palette))),
      leg: chunks(legParts()),
      head_: chunks(headParts(palette)),
      tail1: chunks(tail1),
      tail2: chunks(tail2),
      hair,
    },
    items,
    props: Object.fromEntries(Object.entries(PROPS).map(([name, parts]) => [name, bake(parts)])),
    scenery: {
      ground: toMesh(makeGround().geometry),
      ridgeFar: toMesh(makeRidge(-34, 9, 3.0, '#16262a', 0.16).geometry),
      ridgeNear: toMesh(makeRidge(-17, 5, 1.15, '#0e1a1c', 0.05).geometry),
      weekStone: bake(weekStoneParts),
      scatter: bake(scatterParts),
      grass: bake(grassParts()),
      tree: bake(treeParts()),
      lantern: bake(lanternParts),
      mound: bake(moundParts),
      lockbox: bake(boxParts),
      lid: bake(lidParts),
      clods: Array.from({ length: CLOD_COUNT }, (_, i) => bake(clodParts(i))),
    },
    stars: { positions: Array.from(stars.positions).map(round(4)), seeds: Array.from(stars.seeds).map(round(4)) },
    motes: { positions: Array.from(motes.positions).map(round(4)), seeds: Array.from(motes.seeds).map(round(4)) },
  };
  writeFileSync(join(resources, 'models.json'), JSON.stringify(models));

  // 3. Textures.
  const atlas = getAtlas().image as { data: Uint8Array; width: number; height: number };
  writeFileSync(join(resources, 'atlas.png'), png(atlas.width, atlas.height, atlas.data));
  const glow = getGlowTexture().image as { data: Uint8Array; width: number; height: number };
  // For the glow, brightness doubles as see-through-ness, so it fades cleanly at the edges.
  const glowPixels = new Uint8Array(glow.data.length);
  for (let i = 0; i < glow.data.length; i += 4) glowPixels.set([255, 255, 255, glow.data[i]], i);
  writeFileSync(join(resources, 'glow.png'), png(glow.width, glow.height, glowPixels));
  writeFileSync(
    join(resources, 'face.png'),
    pixelArt(FACE_ROWS, { K: [22, 18, 16, 255], B: [40, 30, 24, 255], W: [240, 236, 220, 255], M: [92, 44, 36, 255] }),
  );
  writeFileSync(join(resources, 'runes.png'), pixelArt(RUNE_ROWS, { X: [255, 255, 255, 255] }));

  // 4. Answers for the Swift tests to match.
  writeFileSync(join(fixtures, 'parity.json'), JSON.stringify(parityFixtures(), null, 1));

  const size = (JSON.stringify(models).length / 1024).toFixed(0);
  console.log(`ios data written: models.json (${size} KB), 4 textures, content, parity fixtures`);
}
