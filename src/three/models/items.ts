import type { Part } from '../parts';

// Every item the hero can wear or carry, written as lists of simple shapes.
//
// Hand tools are modelled standing upright with their tip on the ground,
// because the hero rests them planted in the soil.
// Hats are modelled around the centre of the head.
// Shields face +Z (toward the viewer) and get turned onto the arm by the rig.

export type ItemModel =
  | { slot: 'hand'; parts: Part[] }
  | { slot: 'shield'; parts: Part[] }
  | { slot: 'head'; parts: Part[]; hair: 'keep' | 'under' | 'hide' }
  | { slot: 'body'; tunic?: string; sleeve?: string; torso?: Part[]; shoulder?: Part[] }
  | { slot: 'charm'; parts: Part[]; glow?: string };

const WOOD = '#7a5a36';
const DARK_WOOD = '#4d3a26';
const IRON = '#7d8083';
const RUST = '#7c5a48';
const MOONSTEEL = '#9fc0e0';
const BRASS = '#c9a04a';
const BONE = '#e6dfc8';
const VERDIGRIS = '#5fb39a';
const LANTERN = '#f2b544';

/** A spade: blade, shaft and D-shaped grip. Colours vary by tier. */
function spade(blade: string, shaft: string, extra: Part[] = []): Part[] {
  return [
    // Blade: a pointed lower half under a square shoulder, like the card suit.
    { s: 'box', size: [0.19, 0.2, 0.026], taper: [0.08, 1], rot: [180, 0, 0], at: [0, 0.1, 0], c: blade, tile: 'metal' },
    { s: 'box', size: [0.19, 0.1, 0.026], taper: [0.86, 1], at: [0, 0.25, 0], c: blade, c2: blade, tile: 'metal' },
    { s: 'cyl', r: [0.026, 0.034], h: 0.09, sides: 6, at: [0, 0.33, 0], c: blade, tile: 'metal' },
    { s: 'cyl', r: 0.024, h: 0.7, sides: 6, at: [0, 0.58, 0], c: shaft, tile: 'wood' },
    { s: 'box', size: [0.15, 0.032, 0.036], at: [0, 1.01, 0], c: shaft, tile: 'wood' },
    { s: 'box', size: [0.028, 0.085, 0.032], at: [-0.06, 0.965, 0], c: shaft, tile: 'wood' },
    { s: 'box', size: [0.028, 0.085, 0.032], at: [0.06, 0.965, 0], c: shaft, tile: 'wood' },
    { s: 'box', size: [0.15, 0.03, 0.036], at: [0, 0.925, 0], c: shaft, tile: 'wood' },
    ...extra,
  ];
}

export const ITEM_MODELS: Record<string, ItemModel> = {
  icon_spade: { slot: 'hand', parts: spade('#39ff14', '#187d24').map((part, i) => ({ ...part, ...(i < 3 ? { emit: 1 } : {}) })) },
  dogger: { slot: 'charm', parts: [
    { s: 'ball', r: [0.12, 0.12, 0.21], at: [0, 0.18, 0], c: '#201e22', seg: [8, 6] },
    { s: 'ball', r: [0.13, 0.13, 0.1], at: [0, 0.31, 0.17], c: '#201e22', seg: [8, 6] },
    { s: 'box', size: [0.065, 0.21, 0.018], at: [0, 0.31, 0.263], c: '#fff5df' },
    { s: 'ball', r: [0.095, 0.055, 0.045], at: [0, 0.26, 0.28], c: '#fff5df', seg: [6, 4] },
    { s: 'ball', r: [0.025, 0.018, 0.018], at: [0, 0.28, 0.321], c: '#17151a', seg: [5, 4] },
    { s: 'box', size: [0.075, 0.14, 0.05], taper: [0.05, 1], at: [-0.08, 0.44, 0.16], c: '#201e22' },
    { s: 'box', size: [0.075, 0.14, 0.05], taper: [0.05, 1], at: [0.08, 0.44, 0.16], c: '#201e22' },
    { s: 'box', size: [0.12, 0.16, 0.025], at: [0, 0.16, 0.19], c: '#fff5df' },
    ...[-0.075, 0.075].flatMap((x): Part[] => [
      { s: 'box', size: [0.05, 0.12, 0.065], at: [x, 0.06, 0.12], c: '#fff5df' },
      { s: 'box', size: [0.05, 0.12, 0.065], at: [x, 0.06, -0.12], c: '#201e22' },
      { s: 'ball', r: 0.016, at: [x * 0.8, 0.33, 0.26], c: '#111015', emit: 0.2, seg: [5, 4] }
    ])
  ] },
  // ---- Hand -------------------------------------------------------------
  rusty_spade: { slot: 'hand', parts: spade(RUST, WOOD) },
  oak_staff: {
    slot: 'hand',
    parts: [
      { s: 'cyl', r: [0.03, 0.022], h: 1.35, sides: 6, at: [0, 0.675, 0], c: WOOD, tile: 'wood' },
      { s: 'ball', r: [0.06, 0.07, 0.055], seg: [6, 5], at: [0.01, 1.38, 0], c: WOOD, tile: 'wood' },
      { s: 'cyl', r: 0.036, h: 0.1, sides: 6, at: [0, 0.74, 0], c: '#6a4a2c', tile: 'leather' },
    ],
  },
  garden_fork: {
    slot: 'hand',
    parts: [
      { s: 'cyl', r: 0.023, h: 0.72, sides: 6, at: [0, 0.62, 0], c: WOOD, tile: 'wood' },
      { s: 'box', size: [0.2, 0.03, 0.035], at: [0, 0.26, 0], c: IRON, tile: 'metal' },
      { s: 'cyl', r: [0.014, 0.004], h: 0.27, sides: 4, at: [-0.085, 0.12, 0], c: IRON, tile: 'metal' },
      { s: 'cyl', r: [0.014, 0.004], h: 0.27, sides: 4, at: [-0.028, 0.12, 0], c: IRON, tile: 'metal' },
      { s: 'cyl', r: [0.014, 0.004], h: 0.27, sides: 4, at: [0.028, 0.12, 0], c: IRON, tile: 'metal' },
      { s: 'cyl', r: [0.014, 0.004], h: 0.27, sides: 4, at: [0.085, 0.12, 0], c: IRON, tile: 'metal' },
      { s: 'box', size: [0.13, 0.03, 0.034], at: [0, 0.995, 0], c: WOOD, tile: 'wood' },
    ],
  },
  miners_pick: {
    slot: 'hand',
    parts: [
      { s: 'cyl', r: [0.026, 0.03], h: 0.95, sides: 6, at: [0, 0.475, 0], c: DARK_WOOD, tile: 'wood' },
      { s: 'box', size: [0.1, 0.07, 0.06], at: [0, 0.93, 0], c: IRON, tile: 'metal' },
      { s: 'cyl', r: [0.006, 0.034], h: 0.26, sides: 4, at: [-0.17, 0.915, 0], rot: [0, 0, 78], c: IRON, tile: 'metal' },
      { s: 'cyl', r: [0.006, 0.034], h: 0.26, sides: 4, at: [0.17, 0.915, 0], rot: [0, 0, -78], c: IRON, tile: 'metal' },
    ],
  },
  barrow_blade: {
    slot: 'hand',
    parts: [
      { s: 'box', size: [0.075, 0.62, 0.02], taper: [0.25, 1], rot: [180, 0, 0], at: [0, 0.33, 0], c: '#b9c0c4', c2: '#6c7479', tile: 'metal' },
      { s: 'box', size: [0.24, 0.04, 0.045], at: [0, 0.66, 0], c: BRASS, tile: 'metal' },
      { s: 'cyl', r: 0.024, h: 0.17, sides: 6, at: [0, 0.765, 0], c: '#4a3423', tile: 'leather' },
      { s: 'ball', r: 0.042, seg: [6, 4], at: [0, 0.875, 0], c: BRASS, tile: 'metal' },
    ],
  },
  wayfinders_crook: {
    slot: 'hand',
    parts: [
      { s: 'cyl', r: [0.026, 0.022], h: 1.4, sides: 6, at: [0, 0.7, 0], c: DARK_WOOD, tile: 'wood' },
      { s: 'cyl', r: 0.022, h: 0.22, sides: 5, at: [0.09, 1.43, 0], rot: [0, 0, -62], c: DARK_WOOD, tile: 'wood' },
      { s: 'cyl', r: 0.006, h: 0.1, sides: 4, at: [0.18, 1.42, 0], c: IRON },
      { s: 'cyl', r: [0.03, 0.055], h: 0.035, sides: 6, at: [0.18, 1.36, 0], c: IRON, tile: 'metal' },
      { s: 'box', size: [0.075, 0.1, 0.075], at: [0.18, 1.29, 0], c: LANTERN, c2: '#ffdf9a', emit: 1 },
      { s: 'cyl', r: 0.055, h: 0.025, sides: 6, at: [0.18, 1.23, 0], c: IRON, tile: 'metal' },
    ],
  },
  moonsteel_spade: {
    slot: 'hand',
    parts: spade(MOONSTEEL, '#3c4654', [
      { s: 'cyl', r: 0.03, h: 0.05, sides: 6, at: [0, 0.27, 0], c: BONE, tile: 'metal' },
    ]),
  },
  gravediggers_oath: {
    slot: 'hand',
    parts: spade('#2f3336', '#241c18', [
      { s: 'box', size: [0.05, 0.11, 0.036], at: [0, 0.1, 0], c: LANTERN, c2: '#ffdf9a', emit: 1 },
      { s: 'cyl', r: 0.034, h: 0.04, sides: 6, at: [0, 0.27, 0], c: BRASS, tile: 'metal' },
      { s: 'cyl', r: 0.03, h: 0.03, sides: 6, at: [0, 0.86, 0], c: BRASS, tile: 'metal' },
    ]),
  },

  // ---- Head -------------------------------------------------------------
  wool_cap: {
    slot: 'head',
    hair: 'under',
    parts: [
      { s: 'ball', r: [0.298, 0.24, 0.29], seg: [9, 6], at: [0, 0.1, -0.01], c: '#b5472f', tile: 'cloth' },
      { s: 'cyl', r: [0.3, 0.305], h: 0.075, sides: 9, at: [0, 0.07, -0.01], c: BONE, tile: 'cloth' },
      { s: 'ball', r: 0.06, seg: [6, 4], at: [0, 0.345, -0.01], c: BONE, tile: 'cloth' },
    ],
  },
  straw_hat: {
    slot: 'head',
    hair: 'under',
    parts: [
      { s: 'cyl', r: [0.4, 0.47], h: 0.035, sides: 10, at: [0, 0.12, 0], rot: [-6, 0, 0], c: '#c9ad62', tile: 'cloth' },
      { s: 'cyl', r: [0.2, 0.26], h: 0.17, sides: 9, at: [0, 0.21, 0], rot: [-6, 0, 0], c: '#c9ad62', tile: 'cloth' },
      { s: 'cyl', r: [0.255, 0.265], h: 0.04, sides: 9, at: [0, 0.155, 0], rot: [-6, 0, 0], c: '#4a3423', tile: 'leather' },
    ],
  },
  miners_helm: {
    slot: 'head',
    hair: 'under',
    parts: [
      { s: 'ball', r: [0.3, 0.23, 0.295], seg: [9, 6], at: [0, 0.1, -0.01], c: '#6b6a60', tile: 'metal' },
      { s: 'cyl', r: [0.315, 0.33], h: 0.04, sides: 9, at: [0, 0.085, 0.02], c: '#4f4e47', tile: 'metal' },
      { s: 'box', size: [0.07, 0.07, 0.04], at: [0, 0.2, 0.275], c: BRASS, tile: 'metal' },
      { s: 'cyl', r: 0.018, h: 0.07, sides: 5, at: [0, 0.265, 0.285], c: BONE, c2: BONE },
      { s: 'ball', r: [0.022, 0.034, 0.022], seg: [5, 4], at: [0, 0.325, 0.285], c: LANTERN, c2: '#ffdf9a', emit: 1 },
    ],
  },
  fogcloak_hood: {
    slot: 'head',
    hair: 'hide',
    parts: [
      { s: 'ball', r: [0.315, 0.3, 0.31], seg: [9, 7], at: [0, 0.03, -0.045], c: '#3f4f52', tile: 'cloth' },
      { s: 'cyl', r: [0, 0.16], h: 0.24, sides: 6, at: [0, 0.3, -0.2], rot: [-58, 0, 0], c: '#3f4f52', tile: 'cloth' },
      { s: 'cyl', r: [0.25, 0.29], h: 0.12, sides: 8, at: [0, -0.25, -0.02], c: '#34423f', tile: 'cloth' },
    ],
  },
  barrow_helm: {
    slot: 'head',
    hair: 'under',
    parts: [
      { s: 'ball', r: [0.3, 0.25, 0.295], seg: [9, 6], at: [0, 0.09, -0.01], c: '#84888a', c2: '#3f4447', tile: 'metal' },
      { s: 'cyl', r: [0.305, 0.31], h: 0.05, sides: 9, at: [0, 0.075, -0.01], c: BRASS, tile: 'metal' },
      { s: 'box', size: [0.05, 0.2, 0.03], at: [0, -0.02, 0.285], c: '#84888a', tile: 'metal' },
      { s: 'box', size: [0.035, 0.26, 0.5], taper: [1, 0.4], at: [0, 0.3, -0.04], c: '#8a3b2a', tile: 'cloth' },
    ],
  },
  moonsteel_cap: {
    slot: 'head',
    hair: 'under',
    parts: [
      { s: 'ball', r: [0.298, 0.24, 0.292], seg: [9, 6], at: [0, 0.1, -0.01], c: MOONSTEEL, c2: '#4d6a8c', tile: 'metal' },
      { s: 'cyl', r: [0.302, 0.308], h: 0.045, sides: 9, at: [0, 0.08, -0.01], c: BONE, tile: 'metal' },
      { s: 'ball', r: [0.05, 0.05, 0.02], seg: [6, 4], at: [0, 0.16, 0.285], c: '#dff3ff', c2: '#dff3ff', emit: 0.9 },
    ],
  },
  crown_of_roots: {
    slot: 'head',
    hair: 'keep',
    parts: [
      { s: 'cyl', r: [0.285, 0.29], h: 0.06, sides: 9, at: [0, 0.14, -0.01], c: DARK_WOOD, tile: 'wood' },
      { s: 'cyl', r: [0.006, 0.03], h: 0.26, sides: 4, at: [-0.2, 0.3, 0.12], rot: [16, 0, 24], c: DARK_WOOD, tile: 'wood' },
      { s: 'cyl', r: [0.006, 0.03], h: 0.3, sides: 4, at: [0.2, 0.32, 0.12], rot: [16, 0, -24], c: DARK_WOOD, tile: 'wood' },
      { s: 'cyl', r: [0.006, 0.026], h: 0.2, sides: 4, at: [0, 0.27, 0.27], rot: [24, 0, 0], c: DARK_WOOD, tile: 'wood' },
      { s: 'cyl', r: [0.006, 0.026], h: 0.22, sides: 4, at: [-0.24, 0.27, -0.12], rot: [-14, 0, 28], c: DARK_WOOD, tile: 'wood' },
      { s: 'cyl', r: [0.006, 0.026], h: 0.24, sides: 4, at: [0.24, 0.28, -0.12], rot: [-14, 0, -28], c: DARK_WOOD, tile: 'wood' },
      { s: 'ball', r: 0.035, seg: [5, 4], at: [0, 0.39, 0.31], c: VERDIGRIS, c2: '#b7ffe6', emit: 1 },
      { s: 'ball', r: 0.028, seg: [5, 4], at: [-0.25, 0.44, 0.17], c: VERDIGRIS, c2: '#b7ffe6', emit: 1 },
      { s: 'ball', r: 0.028, seg: [5, 4], at: [0.26, 0.48, 0.17], c: VERDIGRIS, c2: '#b7ffe6', emit: 1 },
    ],
  },

  // ---- Body -------------------------------------------------------------
  patched_tunic: {
    slot: 'body',
    tunic: '#6f7a4e',
    sleeve: '#6f7a4e',
    torso: [
      { s: 'box', size: [0.1, 0.1, 0.02], at: [-0.1, 0.12, 0.262], rot: [-11, -14, 6], c: '#b5472f', tile: 'cloth' },
      { s: 'box', size: [0.08, 0.08, 0.02], at: [0.12, 0.33, 0.215], rot: [-11, 20, -8], c: '#c98f2a', tile: 'cloth' },
    ],
  },
  diggers_apron: {
    slot: 'body',
    torso: [
      { s: 'box', size: [0.3, 0.36, 0.03], taper: [0.7, 1], at: [0, 0.2, 0.25], rot: [-11, 0, 0], c: '#5a4029', tile: 'leather' },
      { s: 'box', size: [0.13, 0.09, 0.035], at: [0, 0.13, 0.275], rot: [-11, 0, 0], c: '#4a3423', tile: 'leather' },
    ],
  },
  travel_cloak: {
    slot: 'body',
    torso: [
      { s: 'cyl', r: [0.21, 0.37], h: 0.56, sides: 8, at: [0, 0.2, -0.06], c: '#34423f', c2: '#1c2524', tile: 'cloth' },
      { s: 'ball', r: 0.035, seg: [5, 4], at: [0, 0.44, 0.2], c: BRASS, tile: 'metal' },
    ],
  },
  ringmail: {
    slot: 'body',
    tunic: '#6d7376',
    sleeve: '#6d7376',
    torso: [
      { s: 'cyl', r: [0.19, 0.275], h: 0.36, sides: 8, at: [0, 0.31, 0], c: '#8d9396', c2: '#474c4f', tile: 'metal' },
    ],
  },
  wardens_coat: {
    slot: 'body',
    tunic: '#2f3f52',
    sleeve: '#2f3f52',
    torso: [
      { s: 'cyl', r: [0.24, 0.2], h: 0.09, sides: 8, at: [0, 0.47, 0], c: '#2f3f52', tile: 'cloth' },
      { s: 'box', size: [0.03, 0.4, 0.02], at: [0, 0.24, 0.245], rot: [-11, 0, 0], c: BRASS, tile: 'metal' },
    ],
    shoulder: [{ s: 'ball', r: [0.1, 0.07, 0.1], seg: [7, 4], at: [0, 0.0, 0], c: BRASS, tile: 'metal' }],
  },
  moonsteel_plate: {
    slot: 'body',
    tunic: '#3c4654',
    sleeve: '#3c4654',
    torso: [
      { s: 'cyl', r: [0.2, 0.255], h: 0.3, sides: 8, at: [0, 0.34, 0], c: MOONSTEEL, c2: '#4d6a8c', tile: 'metal' },
      { s: 'ball', r: [0.05, 0.05, 0.02], seg: [6, 4], at: [0, 0.36, 0.235], c: '#dff3ff', c2: '#dff3ff', emit: 0.9 },
    ],
    shoulder: [{ s: 'ball', r: [0.115, 0.08, 0.115], seg: [7, 4], at: [0, 0.01, 0], c: MOONSTEEL, c2: '#4d6a8c', tile: 'metal' }],
  },
  foxfire_mantle: {
    slot: 'body',
    tunic: '#23302e',
    sleeve: '#23302e',
    torso: [
      { s: 'cyl', r: [0.22, 0.39], h: 0.6, sides: 8, at: [0, 0.18, -0.05], c: '#1f2b29', c2: '#101615', tile: 'cloth' },
      { s: 'cyl', r: [0.385, 0.395], h: 0.03, sides: 8, at: [0, -0.11, -0.05], c: VERDIGRIS, c2: '#b7ffe6', emit: 1 },
      { s: 'ball', r: 0.04, seg: [5, 4], at: [0, 0.44, 0.21], c: VERDIGRIS, c2: '#b7ffe6', emit: 1 },
    ],
  },

  // ---- Shield -----------------------------------------------------------
  pot_lid: {
    slot: 'shield',
    parts: [
      { s: 'cyl', r: 0.19, h: 0.025, sides: 10, rot: [90, 0, 0], c: '#6b6a60', tile: 'metal' },
      { s: 'ball', r: [0.04, 0.04, 0.035], seg: [5, 4], at: [0, 0, 0.03], c: DARK_WOOD },
    ],
  },
  plank_shield: {
    slot: 'shield',
    parts: [
      { s: 'box', size: [0.1, 0.42, 0.03], at: [-0.105, 0, 0], c: WOOD, tile: 'wood' },
      { s: 'box', size: [0.1, 0.45, 0.03], at: [0, 0, 0], c: '#6a4e30', tile: 'wood' },
      { s: 'box', size: [0.1, 0.41, 0.03], at: [0.105, 0, 0], c: WOOD, tile: 'wood' },
      { s: 'box', size: [0.33, 0.045, 0.02], at: [0, 0.11, 0.022], c: IRON, tile: 'metal' },
      { s: 'box', size: [0.33, 0.045, 0.02], at: [0, -0.11, 0.022], c: IRON, tile: 'metal' },
    ],
  },
  round_buckler: {
    slot: 'shield',
    parts: [
      { s: 'cyl', r: 0.22, h: 0.03, sides: 10, rot: [90, 0, 0], c: WOOD, tile: 'wood' },
      { s: 'cyl', r: [0.235, 0.235], h: 0.02, sides: 10, rot: [90, 0, 0], at: [0, 0, -0.008], c: IRON, tile: 'metal' },
      { s: 'ball', r: [0.075, 0.075, 0.055], seg: [7, 4], at: [0, 0, 0.02], c: IRON, tile: 'metal' },
    ],
  },
  barrow_shield: {
    slot: 'shield',
    parts: [
      { s: 'box', size: [0.34, 0.26, 0.035], at: [0, 0.1, 0], c: '#2f3f52', tile: 'metal' },
      { s: 'box', size: [0.34, 0.26, 0.035], taper: [0.15, 1], rot: [180, 0, 0], at: [0, -0.16, 0], c: '#2f3f52', tile: 'metal' },
      // The spade crest: a pointed blade above a short stem.
      { s: 'box', size: [0.15, 0.15, 0.02], taper: [0.1, 1], at: [0, 0.1, 0.024], c: BONE, c2: BONE },
      { s: 'ball', r: [0.05, 0.05, 0.012], seg: [6, 4], at: [-0.04, 0.02, 0.024], c: BONE, c2: BONE },
      { s: 'ball', r: [0.05, 0.05, 0.012], seg: [6, 4], at: [0.04, 0.02, 0.024], c: BONE, c2: BONE },
      { s: 'box', size: [0.035, 0.12, 0.02], taper: [0.5, 1], at: [0, -0.07, 0.024], c: BONE, c2: BONE },
    ],
  },
  moon_mirror: {
    slot: 'shield',
    parts: [
      { s: 'cyl', r: 0.225, h: 0.03, sides: 12, rot: [90, 0, 0], c: BRASS, tile: 'metal' },
      { s: 'cyl', r: 0.185, h: 0.034, sides: 12, rot: [90, 0, 0], c: '#dff3ff', c2: '#9fc0e0', emit: 0.85 },
    ],
  },

  // ---- Charm ------------------------------------------------------------
  lucky_pebble: {
    slot: 'charm',
    parts: [{ s: 'ball', r: [0.07, 0.05, 0.06], seg: [6, 4], c: '#8f9488', tile: 'stone' }],
  },
  firefly: {
    slot: 'charm',
    glow: '#e8f08a',
    parts: [{ s: 'ball', r: 0.026, seg: [5, 4], c: '#e8f08a', c2: '#e8f08a', emit: 1 }],
  },
  dusk_moth: {
    slot: 'charm',
    parts: [
      { s: 'ball', r: [0.018, 0.018, 0.05], seg: [5, 4], c: '#5a4a3f' },
      { s: 'box', size: [0.1, 0.006, 0.085], taper: [1, 0.6], at: [-0.055, 0.012, 0], rot: [0, 0, 24], c: '#b9a98c', tile: 'cloth' },
      { s: 'box', size: [0.1, 0.006, 0.085], taper: [1, 0.6], at: [0.055, 0.012, 0], rot: [0, 0, -24], c: '#b9a98c', tile: 'cloth' },
    ],
  },
  ember_wisp: {
    slot: 'charm',
    glow: '#ff8a3c',
    parts: [
      { s: 'ball', r: [0.04, 0.055, 0.04], seg: [5, 4], c: '#ffb45a', c2: '#ff6a2a', emit: 1 },
      { s: 'cyl', r: [0, 0.03], h: 0.07, sides: 4, at: [0, 0.07, 0], c: '#ffd98a', c2: '#ff8a3c', emit: 1 },
    ],
  },
  foxfire_wisp: {
    slot: 'charm',
    glow: '#5fe0c0',
    parts: [
      { s: 'ball', r: [0.045, 0.06, 0.045], seg: [5, 4], c: '#b7ffe6', c2: '#3fb39a', emit: 1 },
      { s: 'cyl', r: [0, 0.034], h: 0.09, sides: 4, at: [0, 0.08, 0], c: '#e6fff6', c2: '#5fe0c0', emit: 1 },
    ],
  },
  pocket_moon: {
    slot: 'charm',
    glow: '#cfe3ee',
    parts: [
      { s: 'ball', r: 0.07, seg: [8, 6], c: '#f1f0dc', c2: '#8fa3ad', emit: 0.75 },
      { s: 'ball', r: [0.02, 0.02, 0.008], seg: [5, 3], at: [-0.02, 0.02, 0.066], c: '#a9b3b0', c2: '#a9b3b0', emit: 0.7 },
      { s: 'ball', r: [0.014, 0.014, 0.008], seg: [5, 3], at: [0.03, -0.015, 0.064], c: '#a9b3b0', c2: '#a9b3b0', emit: 0.7 },
    ],
  },
};

/**
 * The shapes to show when an item is displayed on its own (as an icon, or
 * rising out of the lockbox). Body items aren't a single object, so a small
 * garment stands in for them.
 */
export function displayParts(model: ItemModel): Part[] {
  if (model.slot !== 'body') return model.parts;
  const tunic = model.tunic ?? '#8c7448';
  const sleeve = model.sleeve ?? tunic;
  const shoulders = (model.shoulder ?? []).flatMap((p): Part[] => [
    { ...p, at: [-0.225 + (p.at?.[0] ?? 0), 0.4 + (p.at?.[1] ?? 0), p.at?.[2] ?? 0] },
    { ...p, at: [0.225 - (p.at?.[0] ?? 0), 0.4 + (p.at?.[1] ?? 0), p.at?.[2] ?? 0] },
  ]);
  return [
    { s: 'cyl', r: [0.18, 0.28], h: 0.5, sides: 8, at: [0, 0.24, 0], c: tunic, tile: 'cloth' },
    { s: 'cyl', r: [0.078, 0.092], h: 0.21, sides: 7, at: [-0.27, 0.34, 0], rot: [0, 0, -34], c: sleeve, tile: 'cloth' },
    { s: 'cyl', r: [0.078, 0.092], h: 0.21, sides: 7, at: [0.27, 0.34, 0], rot: [0, 0, 34], c: sleeve, tile: 'cloth' },
    { s: 'cyl', r: [0.1, 0.17], h: 0.06, sides: 8, at: [0, 0.5, 0], c: '#2a2118', c2: '#2a2118' },
    ...(model.torso ?? []),
    ...shoulders,
  ];
}

/** Fallback so a missing model can never crash the scene. */
export const MISSING_MODEL: Part[] = [{ s: 'box', size: [0.2, 0.2, 0.2], c: '#c8553d' }];
