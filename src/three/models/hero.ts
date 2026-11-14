import type { Part, Vec3 } from '../parts';

// The digger, written as data. Distances are in "units" where the hero is
// about 1.5 units tall. +Y is up, +Z points toward the camera, and the hero's
// right hand is on the -X side.

export interface JointSpec {
  name: string;
  parent: string | null;
  at: Vec3;
  rot?: Vec3;
}

/** The skeleton: each joint is a pivot that parts hang from. */
export const HERO_JOINTS: JointSpec[] = [
  { name: 'hips', parent: null, at: [0, 0.4, 0] },
  { name: 'torso', parent: 'hips', at: [0, 0, 0] },
  { name: 'head', parent: 'torso', at: [0, 0.55, 0] },
  { name: 'hat', parent: 'head', at: [0, 0.24, 0] },
  { name: 'armR', parent: 'torso', at: [-0.225, 0.4, 0], rot: [-62, 0, -20] },
  { name: 'armL', parent: 'torso', at: [0.225, 0.4, 0], rot: [-10, 0, 13] },
  { name: 'shield', parent: 'armL', at: [0.07, -0.2, 0.07], rot: [0, 38, -8] },
  { name: 'legR', parent: 'hips', at: [-0.108, 0, 0] },
  { name: 'legL', parent: 'hips', at: [0.108, 0, 0] },
  { name: 'tail1', parent: 'torso', at: [0.19, 0.5, 0.03], rot: [0, 0, 24] },
  { name: 'tail2', parent: 'tail1', at: [0, -0.2, 0], rot: [0, 0, -10] },
  // The held tool stands on the ground, so it hangs off the hips rather than the tilted hand.
  { name: 'tool', parent: 'hips', at: [-0.3, -0.45, 0.27] },
];

/** Head size, shared with the face so the eyes sit on the surface. */
export const HEAD = { center: [0, 0.24, 0] as Vec3, radius: [0.27, 0.25, 0.255] as Vec3 };

export const HERO_COLORS = {
  tunic: '#8c7448',
  sleeve: '#8c7448',
  trouser: '#2e2c27',
  boot: '#3d2b1d',
  bootCuff: '#6a4a2c',
  glove: '#70502f',
  leather: '#4a3423',
  brass: '#c9a04a',
  pack: '#5a4029',
  bedroll: '#4f9483',
};

export interface HeroPalette {
  skin: string;
  hair: string;
  scarf: string;
  tunic: string;
  sleeve: string;
}

export function torsoParts(p: HeroPalette): Part[] {
  const c = HERO_COLORS;
  return [
    // Tunic: a flared bell shape.
    { s: 'cyl', r: [0.18, 0.28], h: 0.5, sides: 8, at: [0, 0.24, 0], c: p.tunic, tile: 'cloth' },
    { s: 'cyl', r: [0.24, 0.253], h: 0.055, sides: 8, at: [0, 0.165, 0], c: c.leather, tile: 'leather' },
    { s: 'box', size: [0.08, 0.08, 0.03], at: [0, 0.165, 0.245], c: c.brass, tile: 'metal' },
    // Scarf.
    { s: 'cyl', r: [0.195, 0.22], h: 0.13, sides: 8, at: [0, 0.505, 0], c: p.scarf, tile: 'stripes' },
    { s: 'ball', r: [0.07, 0.06, 0.06], at: [0.15, 0.48, 0.14], c: p.scarf, tile: 'stripes' },
    // Pack and bedroll.
    { s: 'box', size: [0.33, 0.3, 0.16], at: [0, 0.26, -0.27], c: c.pack, tile: 'leather' },
    { s: 'box', size: [0.34, 0.09, 0.17], at: [0, 0.38, -0.27], c: c.leather, tile: 'leather' },
    { s: 'cyl', r: 0.078, h: 0.4, sides: 7, at: [0, 0.48, -0.28], rot: [0, 0, 90], c: c.bedroll, c2: c.bedroll, tile: 'stripes' },
  ];
}

/** Right arm. The left arm is this, mirrored. */
export function armParts(p: HeroPalette): Part[] {
  const c = HERO_COLORS;
  return [
    { s: 'cyl', r: [0.078, 0.092], h: 0.21, sides: 7, at: [0, -0.1, 0], c: p.sleeve, tile: 'cloth' },
    { s: 'cyl', r: [0.074, 0.07], h: 0.07, sides: 7, at: [0, -0.235, 0], c: c.glove, tile: 'leather' },
    { s: 'ball', r: 0.09, seg: [7, 5], at: [0, -0.31, 0], c: c.glove, tile: 'leather' },
  ];
}

/** One leg and boot (the same list works for both sides). */
export function legParts(): Part[] {
  const c = HERO_COLORS;
  return [
    { s: 'cyl', r: [0.098, 0.088], h: 0.2, sides: 7, at: [0, -0.11, 0], c: c.trouser, tile: 'cloth' },
    { s: 'cyl', r: [0.103, 0.098], h: 0.12, sides: 7, at: [0, -0.255, 0], c: c.boot, tile: 'leather' },
    { s: 'cyl', r: 0.11, h: 0.04, sides: 7, at: [0, -0.195, 0], c: c.bootCuff, tile: 'leather' },
    { s: 'ball', r: [0.108, 0.088, 0.17], seg: [7, 5], at: [0, -0.322, 0.05], c: c.boot, tile: 'leather' },
  ];
}

export function headParts(p: HeroPalette): Part[] {
  return [
    { s: 'ball', r: HEAD.radius, seg: [10, 7], at: HEAD.center, c: p.skin, c2: p.skin },
    // Ears and a small nose give the head a profile when it turns.
    { s: 'ball', r: [0.04, 0.06, 0.05], seg: [5, 4], at: [-0.268, 0.225, 0], c: p.skin, c2: p.skin },
    { s: 'ball', r: [0.04, 0.06, 0.05], seg: [5, 4], at: [0.268, 0.225, 0], c: p.skin, c2: p.skin },
    { s: 'ball', r: [0.03, 0.026, 0.034], seg: [5, 4], at: [0, 0.178, 0.252], c: p.skin, c2: p.skin },
  ];
}

export function tailParts(p: HeroPalette): [Part[], Part[]] {
  return [
    [{ s: 'box', size: [0.105, 0.21, 0.035], at: [0, -0.1, 0], c: p.scarf, c2: p.scarf, tile: 'stripes' }],
    [{ s: 'box', size: [0.095, 0.17, 0.03], taper: [0.6, 1], rot: [180, 0, 0], at: [0, -0.085, 0], c: p.scarf, tile: 'stripes' }],
  ];
}

export type HairStyle = 'crop' | 'tuft' | 'long' | 'knot' | 'none';

/** Hair has two layers: `top` is hidden under a hat, `under` still shows below it. */
export function hairParts(style: HairStyle, color: string): { top: Part[]; under: Part[] } {
  const cap: Part = { s: 'ball', r: [0.287, 0.2, 0.278], seg: [10, 6], at: [0, 0.335, -0.02], c: color };
  const back: Part = { s: 'ball', r: [0.262, 0.2, 0.18], seg: [8, 5], at: [0, 0.2, -0.115], c: color };
  const fringe: Part = { s: 'box', size: [0.36, 0.075, 0.09], taper: 0.8, at: [0, 0.39, 0.215], rot: [22, 0, 0], c: color };
  switch (style) {
    case 'none':
      return { top: [], under: [] };
    case 'crop':
      return { top: [cap, fringe], under: [back] };
    case 'tuft':
      return {
        top: [
          cap,
          { s: 'cyl', r: [0, 0.08], h: 0.2, sides: 5, at: [0.03, 0.55, 0.1], rot: [28, 0, -8], c: color },
          { s: 'cyl', r: [0, 0.075], h: 0.18, sides: 5, at: [-0.11, 0.52, 0.06], rot: [20, 0, 26], c: color },
          { s: 'cyl', r: [0, 0.075], h: 0.17, sides: 5, at: [0.15, 0.5, 0.02], rot: [10, 0, -34], c: color },
          { s: 'cyl', r: [0, 0.07], h: 0.16, sides: 5, at: [0.0, 0.43, 0.24], rot: [70, 0, 6], c: color },
        ],
        under: [back],
      };
    case 'long':
      return {
        top: [cap, fringe],
        under: [
          { s: 'box', size: [0.085, 0.34, 0.25], taper: [1, 0.8], at: [-0.262, 0.13, -0.05], c: color },
          { s: 'box', size: [0.085, 0.34, 0.25], taper: [1, 0.8], at: [0.262, 0.13, -0.05], c: color },
          { s: 'box', size: [0.5, 0.38, 0.1], taper: [0.9, 1], at: [0, 0.11, -0.225], c: color },
        ],
      };
    case 'knot':
      return {
        top: [
          cap,
          fringe,
          { s: 'ball', r: 0.1, seg: [7, 5], at: [0, 0.57, -0.1], c: color },
          { s: 'cyl', r: 0.055, h: 0.05, sides: 6, at: [0, 0.5, -0.08], c: '#b5472f', c2: '#b5472f' },
        ],
        under: [back],
      };
  }
}

/** Pixel-art face. Top 12 rows: eyes open. Bottom 12 rows: eyes closed. */
export const FACE_ROWS = [
  '........................',
  '........................',
  '....BBBB........BBBB....',
  '........................',
  '.....KK..........KK.....',
  '....KWKK........KWKK....',
  '....KKKK........KKKK....',
  '....KKKK........KKKK....',
  '.....KK..........KK.....',
  '........................',
  '........................',
  '........................',
  '........................',
  '........................',
  '....BBBB........BBBB....',
  '........................',
  '........................',
  '........................',
  '........................',
  '....KKKK........KKKK....',
  '........................',
  '........................',
  '........................',
  '........................',
];
