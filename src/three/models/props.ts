import type { Part } from '../parts';

// Small objects that exist only to be photographed as icons. Every icon in the
// app is a picture of one of these (or of an item, or of the hero), taken by
// the same dithering camera as the main scene.

const BONE = '#e6dfc8';
const LEATHER = '#5a4029';
const DARK_LEATHER = '#3d2b1d';
const BRASS = '#c9a04a';
const STONE = '#6a746a';
const STONE_DARK = '#2a302a';
const VERDIGRIS = '#9ff5d6';
const WOOD = '#7a5a36';
const IRON = '#7d8083';
const RUST = '#c8553d';

/** The spade mark: a pointed blade, two rounded shoulders and a stem. */
export function spadeMark(color: string, glow = 0): Part[] {
  return [
    { s: 'box', size: [0.5, 0.42, 0.08], taper: [0.06, 1], at: [0, 0.2, 0], c: color, c2: color, emit: glow },
    { s: 'ball', r: [0.17, 0.17, 0.045], seg: [8, 5], at: [-0.125, -0.06, 0], c: color, c2: color, emit: glow },
    { s: 'ball', r: [0.17, 0.17, 0.045], seg: [8, 5], at: [0.125, -0.06, 0], c: color, c2: color, emit: glow },
    { s: 'box', size: [0.12, 0.3, 0.08], taper: [0.45, 1], at: [0, -0.28, 0], c: color, c2: color, emit: glow },
  ];
}

export const PROPS: Record<string, Part[]> = {
  // ---- Tabs -------------------------------------------------------------
  scroll: [
    { s: 'box', size: [0.5, 0.56, 0.03], at: [0, 0, 0], c: BONE, c2: '#b8ad8c', tile: 'cloth' },
    { s: 'cyl', r: 0.055, h: 0.6, sides: 6, rot: [0, 0, 90], at: [0, 0.3, 0.01], c: BONE, c2: '#a89c7c' },
    { s: 'cyl', r: 0.055, h: 0.6, sides: 6, rot: [0, 0, 90], at: [0, -0.3, 0.01], c: BONE, c2: '#a89c7c' },
    { s: 'box', size: [0.3, 0.035, 0.02], at: [-0.04, 0.12, 0.025], c: '#5b5444', c2: '#5b5444' },
    { s: 'box', size: [0.36, 0.035, 0.02], at: [0, 0.02, 0.025], c: '#5b5444', c2: '#5b5444' },
    { s: 'box', size: [0.22, 0.035, 0.02], at: [-0.07, -0.08, 0.025], c: '#5b5444', c2: '#5b5444' },
    { s: 'ball', r: [0.07, 0.07, 0.03], seg: [6, 4], at: [0.15, -0.17, 0.03], c: RUST, c2: RUST },
  ],
  satchel: [
    { s: 'ball', r: [0.34, 0.28, 0.2], seg: [8, 6], at: [0, -0.06, 0], c: LEATHER, tile: 'leather' },
    { s: 'box', size: [0.6, 0.26, 0.24], taper: [0.8, 1], rot: [180, 0, 0], at: [0, 0.06, 0.03], c: DARK_LEATHER, c2: LEATHER, tile: 'leather' },
    { s: 'box', size: [0.1, 0.1, 0.05], at: [0, -0.06, 0.2], c: BRASS, tile: 'metal' },
    { s: 'cyl', r: 0.03, h: 0.5, sides: 5, rot: [0, 0, 62], at: [-0.2, 0.3, -0.02], c: DARK_LEATHER },
    { s: 'cyl', r: 0.03, h: 0.5, sides: 5, rot: [0, 0, -62], at: [0.2, 0.3, -0.02], c: DARK_LEATHER },
  ],
  feat: [
    { s: 'box', size: [0.44, 0.72, 0.2], taper: [0.7, 0.8], at: [0, 0, 0], c: STONE, c2: STONE_DARK, tile: 'stone' },
    { s: 'box', size: [0.16, 0.16, 0.03], rot: [0, 0, 45], at: [0, 0.03, 0.1], c: VERDIGRIS, c2: VERDIGRIS, emit: 1 },
    { s: 'box', size: [0.07, 0.07, 0.035], rot: [0, 0, 45], at: [0, 0.03, 0.1], c: STONE_DARK, c2: STONE_DARK },
  ],
  feat_locked: [
    { s: 'box', size: [0.44, 0.72, 0.2], taper: [0.7, 0.8], at: [0, 0, 0], c: '#3a403a', c2: '#191c19', tile: 'stone' },
    { s: 'box', size: [0.16, 0.16, 0.03], rot: [0, 0, 45], at: [0, 0.03, 0.1], c: '#151815', c2: '#151815' },
  ],
  gear: [
    { s: 'cyl', r: 0.25, h: 0.1, sides: 10, rot: [90, 0, 0], c: IRON, tile: 'metal' },
    ...[0, 60, 120, 180, 240, 300].map(
      (a): Part => ({
        s: 'box',
        size: [0.12, 0.14, 0.1],
        at: [Math.sin((a * Math.PI) / 180) * 0.3, Math.cos((a * Math.PI) / 180) * 0.3, 0],
        rot: [0, 0, -a],
        c: IRON,
        tile: 'metal',
      }),
    ),
    { s: 'cyl', r: 0.09, h: 0.12, sides: 8, rot: [90, 0, 0], c: '#0d0f0c', c2: '#0d0f0c' },
  ],

  // ---- HUD --------------------------------------------------------------
  flame: [
    { s: 'ball', r: [0.2, 0.24, 0.16], seg: [7, 5], at: [0, -0.14, 0], c: '#ffb45a', c2: '#e0592a', emit: 1 },
    { s: 'cyl', r: [0, 0.17], h: 0.44, sides: 6, at: [0.02, 0.17, 0], rot: [0, 0, -6], c: '#ffe2a0', c2: '#f2913c', emit: 1 },
    { s: 'ball', r: [0.09, 0.12, 0.08], seg: [6, 4], at: [0, -0.16, 0.1], c: '#fff3cf', c2: '#ffd98a', emit: 1 },
  ],
  flame_out: [
    { s: 'ball', r: [0.2, 0.24, 0.16], seg: [7, 5], at: [0, -0.14, 0], c: '#3b4038', c2: '#23261f' },
    { s: 'cyl', r: [0, 0.17], h: 0.44, sides: 6, at: [0.02, 0.17, 0], rot: [0, 0, -6], c: '#454a41', c2: '#2c3028' },
  ],
  seal: spadeMark(BONE, 1),

  // ---- Categories -------------------------------------------------------
  body: [
    { s: 'cyl', r: [0.15, 0.14], h: 0.34, sides: 7, at: [-0.06, 0.12, 0], c: LEATHER, tile: 'leather' },
    { s: 'cyl', r: 0.165, h: 0.07, sides: 7, at: [-0.06, 0.28, 0], c: '#8a6238', tile: 'leather' },
    { s: 'ball', r: [0.3, 0.14, 0.17], seg: [8, 5], at: [0.08, -0.12, 0], c: LEATHER, c2: DARK_LEATHER, tile: 'leather' },
    { s: 'box', size: [0.56, 0.05, 0.3], at: [0.07, -0.24, 0], c: '#2a1d14', c2: '#2a1d14' },
  ],
  mind: [
    { s: 'box', size: [0.5, 0.64, 0.14], at: [0, 0, 0], c: '#4f9483', c2: '#2d5a50', tile: 'cloth' },
    { s: 'box', size: [0.46, 0.6, 0.11], at: [0.03, 0, 0.01], c: BONE, c2: '#b8ad8c' },
    { s: 'box', size: [0.5, 0.64, 0.03], at: [0, 0, 0.07], c: '#4f9483', c2: '#2d5a50', tile: 'cloth' },
    { s: 'box', size: [0.22, 0.07, 0.02], at: [0, 0.14, 0.09], c: BRASS, c2: BRASS },
  ],
  craft: [
    { s: 'cyl', r: 0.045, h: 0.62, sides: 6, at: [0, -0.1, 0], c: WOOD, tile: 'wood' },
    { s: 'box', size: [0.46, 0.2, 0.2], at: [0, 0.27, 0], c: IRON, c2: '#44484a', tile: 'metal' },
    { s: 'box', size: [0.1, 0.24, 0.24], at: [-0.2, 0.27, 0], c: '#9a9da0', c2: '#55595b', tile: 'metal' },
  ],
  heart: [
    { s: 'ball', r: [0.19, 0.19, 0.12], seg: [8, 6], at: [-0.14, 0.12, 0], c: RUST, c2: '#8a2f22' },
    { s: 'ball', r: [0.19, 0.19, 0.12], seg: [8, 6], at: [0.14, 0.12, 0], c: RUST, c2: '#8a2f22' },
    { s: 'box', size: [0.56, 0.42, 0.18], taper: [0.04, 1], rot: [180, 0, 0], at: [0, -0.14, 0], c: '#b0432f', c2: '#8a2f22' },
  ],
  home: [
    { s: 'box', size: [0.52, 0.34, 0.4], at: [0, -0.14, 0], c: '#a3906c', c2: '#5c5140', tile: 'stone' },
    { s: 'box', size: [0.66, 0.3, 0.5], taper: [0.02, 1], at: [0, 0.18, 0], c: '#8a3b2a', c2: '#5a2419', tile: 'cloth' },
    { s: 'box', size: [0.13, 0.2, 0.03], at: [-0.08, -0.21, 0.2], c: '#3d2b1d', c2: '#3d2b1d' },
    { s: 'box', size: [0.1, 0.1, 0.03], at: [0.13, -0.1, 0.2], c: '#f2b544', c2: '#f2b544', emit: 1 },
  ],

  // ---- Empty equipment slots (dim outlines of what goes there) -----------
  slot_head: [{ s: 'ball', r: [0.3, 0.24, 0.3], seg: [8, 5], at: [0, 0, 0], c: '#3b4038', c2: '#23261f' }, { s: 'cyl', r: [0.36, 0.38], h: 0.05, sides: 9, at: [0, -0.1, 0], c: '#3b4038', c2: '#23261f' }],
  slot_body: [{ s: 'cyl', r: [0.18, 0.32], h: 0.6, sides: 8, at: [0, 0, 0], c: '#3b4038', c2: '#23261f' }],
  slot_hand: [{ s: 'cyl', r: 0.035, h: 0.8, sides: 5, rot: [0, 0, 40], c: '#3b4038', c2: '#23261f' }, { s: 'box', size: [0.2, 0.22, 0.03], taper: [0.2, 1], rot: [0, 0, 220], at: [0.28, -0.34, 0], c: '#3b4038', c2: '#23261f' }],
  slot_shield: [{ s: 'cyl', r: 0.32, h: 0.05, sides: 10, rot: [90, 0, 0], c: '#3b4038', c2: '#23261f' }],
  slot_charm: [{ s: 'ball', r: 0.16, seg: [7, 5], c: '#3b4038', c2: '#23261f' }, { s: 'cyl', r: [0, 0.1], h: 0.24, sides: 5, at: [0, 0.22, 0], c: '#3b4038', c2: '#23261f' }],
};
