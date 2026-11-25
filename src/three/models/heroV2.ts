import type { Part, Vec3 } from '../parts';
import type { HairStyle, HeroPalette, JointSpec } from './hero';

// The new digger: the same Spade hero (tan tunic, striped scarf with two
// tails, pack with a bedroll, gloves, cuffed boots), with grown-up, more
// realistic proportions, elbows and knees for relaxed poses, and details that
// tell a story: one sleeve rolled up, a pencil in the pocket, a patched knee.
//
// Distances are in the same units as the original hero (about 1.5 tall); this
// one is about 1.7. +Y is up, +Z points toward the camera, the hero's right hand
// is on -X.

const DEG = Math.PI / 180;

export const HERO2_JOINTS: JointSpec[] = [
  { name: 'hips', parent: null, at: [0, 0.79, 0] },
  { name: 'torso', parent: 'hips', at: [0, 0, 0] },
  { name: 'head', parent: 'torso', at: [0, 0.56, 0.012] },
  { name: 'hat', parent: 'head', at: [0, 0.2, -0.002] },
  { name: 'armR', parent: 'torso', at: [-0.168, 0.46, -0.01] },
  { name: 'elbowR', parent: 'armR', at: [0, -0.27, 0] },
  { name: 'armL', parent: 'torso', at: [0.168, 0.46, -0.01] },
  { name: 'elbowL', parent: 'armL', at: [0, -0.27, 0] },
  { name: 'shield', parent: 'elbowL', at: [0.05, -0.13, 0.05], rot: [0, 38, -8] },
  { name: 'legR', parent: 'hips', at: [-0.086, 0, 0] },
  { name: 'kneeR', parent: 'legR', at: [0, -0.38, 0] },
  { name: 'legL', parent: 'hips', at: [0.086, 0, 0] },
  { name: 'kneeL', parent: 'legL', at: [0, -0.38, 0] },
  { name: 'tail1', parent: 'torso', at: [0.092, 0.475, 0.092], rot: [0, 0, 14] },
  { name: 'tail2', parent: 'tail1', at: [0, -0.165, 0], rot: [0, 0, -8] },
  { name: 'tool', parent: 'hips', at: [-0.3, -0.79, 0.3] },
];

/** Upper arm, elbow to palm, thigh. */
export const LIMBS2 = { upperArm: 0.27, forearm: 0.265, thigh: 0.38 };

/**
 * The head, turned on a lathe: [radius, height] from the chin up, then made narrower
 * than it is deep (HEAD2_WIDTH), for a slim oval face with a tapered jaw and a small,
 * slightly pointed chin. The face is painted onto this same surface, so it fits exactly.
 */
export const HEAD2_PROFILE: [number, number][] = [
  [0.0, -0.014], [0.022, -0.012], [0.05, -0.002], [0.08, 0.024], [0.108, 0.064], [0.13, 0.108], [0.145, 0.155],
  [0.152, 0.2], [0.149, 0.24], [0.133, 0.282], [0.1, 0.318], [0.05, 0.34], [0.0, 0.346],
];
export const HEAD2_WIDTH = 0.9;
export const HEAD2_DEPTH = 1.06;
export const HEAD2_FORWARD = 0.01;

/** How far in front of the head's middle its surface is, at a point on the face. */
export function headFrontZ(x: number, y: number): number {
  const pts = HEAD2_PROFILE;
  let r = 0;
  for (let i = 1; i < pts.length; i++) {
    const [r0, y0] = pts[i - 1];
    const [r1, y1] = pts[i];
    if (y >= y0 && y <= y1) {
      r = r0 + ((r1 - r0) * (y - y0)) / (y1 - y0 || 1);
      break;
    }
  }
  const u = x / HEAD2_WIDTH;
  return HEAD2_FORWARD + HEAD2_DEPTH * Math.sqrt(Math.max(0, r * r - u * u));
}

/** The painted face patch: its size on the head, and the height of its middle. */
export const FACE2 = { width: 0.25, height: 0.235, centerY: 0.16 };

/** Hats were made for the original, rounder head; this one wears them a little smaller. */
export const HAT2_SCALE = 0.68;

export const HERO2_COLORS = {
  trouser: '#3b3730',
  patch: '#5a4a36',
  boot: '#4a3322',
  bootCuff: '#7a5a36',
  sole: '#1f1c18',
  lace: '#c9b98f',
  glove: '#6e4e30',
  leather: '#4a3423',
  strap: '#3e2c1d',
  brass: '#c9a04a',
  pack: '#5a4029',
  packLight: '#6b4e33',
  bedroll: '#4f9483',
  stitch: '#2a2018',
  // The moss-green hooded cloak from the Spade logo.
  cloak: '#5b7d3b',
};

export function torsoParts2(p: HeroPalette): Part[] {
  const c = HERO2_COLORS;
  const depth = 0.72;
  return [
    // The tunic: fitted at the waist, flaring a little to a hem at mid-thigh.
    {
      s: 'lathe',
      pts: [[0.212, -0.24], [0.207, -0.14], [0.188, -0.03], [0.165, 0.08], [0.165, 0.17], [0.178, 0.27], [0.18, 0.36], [0.172, 0.42], [0.145, 0.465], [0.09, 0.51], [0.068, 0.525]],
      sides: 18,
      scale: [1, 1, depth],
      c: p.tunic,
      tile: 'cloth',
    },
    { s: 'ring', r: 0.21, tube: 0.012, sides: 20, at: [0, -0.232, 0], scale: [1, 1, depth], c: c.stitch, c2: c.stitch },
    { s: 'box', size: [0.016, 0.17, 0.02], at: [0, -0.155, 0.15], rot: [-4, 0, 0], c: c.stitch, c2: c.stitch },
    // Buttoned front and a chest pocket.
    { s: 'box', size: [0.028, 0.28, 0.012], at: [0, 0.31, 0.128], rot: [-6, 0, 0], c: c.leather, tile: 'leather' },
    ...[0.39, 0.32, 0.25].map((y): Part => ({ s: 'ball', r: 0.011, seg: [6, 4], at: [0, y, 0.136], c: c.brass, tile: 'metal' })),
    { s: 'box', size: [0.068, 0.064, 0.012], at: [0.076, 0.285, 0.124], rot: [-8, 16, 0], c: p.tunic, tile: 'cloth' },
    { s: 'box', size: [0.072, 0.022, 0.016], at: [0.076, 0.315, 0.127], rot: [-8, 16, 0], c: c.leather, tile: 'leather' },
    // A pencil stub in the pocket.
    { s: 'cyl', r: 0.006, h: 0.06, sides: 6, at: [0.092, 0.33, 0.129], rot: [0, 0, -10], c: '#c98f2a', c2: '#c98f2a' },
    // Belt, buckle, a pouch on the right hip and a brass compass on the left.
    { s: 'ring', r: 0.166, tube: 0.024, sides: 20, at: [0, 0.095, 0], scale: [1, 1, depth], c: c.leather, tile: 'leather' },
    { s: 'box', size: [0.054, 0.05, 0.02], at: [0, 0.095, 0.132], c: c.brass, tile: 'metal' },
    { s: 'box', size: [0.03, 0.022, 0.024], at: [0, 0.095, 0.134], c: c.leather },
    { s: 'box', size: [0.08, 0.085, 0.055], at: [-0.135, 0.03, 0.075], rot: [0, -38, 0], c: c.pack, tile: 'leather' },
    { s: 'box', size: [0.084, 0.035, 0.06], at: [-0.135, 0.07, 0.077], rot: [0, -38, 0], c: c.leather, tile: 'leather' },
    { s: 'cyl', r: 0.026, h: 0.012, sides: 12, at: [0.14, 0.035, 0.085], rot: [90, 0, 38], c: c.brass, tile: 'metal' },
    { s: 'ring', r: 0.012, tube: 0.003, sides: 8, at: [0.14, 0.07, 0.083], rot: [90, 0, 38], c: c.brass },
    // Pack straps over the shoulders and down the chest.
    ...[-1, 1].flatMap((side): Part[] => [
      { s: 'box', size: [0.036, 0.022, 0.2], at: [side * 0.105, 0.445, -0.02], rot: [0, 0, side * -12], c: c.strap, tile: 'leather' },
      { s: 'box', size: [0.036, 0.2, 0.012], at: [side * 0.11, 0.345, 0.125], rot: [-9, 0, side * 4], c: c.strap, tile: 'leather' },
      { s: 'box', size: [0.03, 0.018, 0.016], at: [side * 0.112, 0.265, 0.128], c: c.brass, tile: 'metal' },
    ]),
    // The scarf, wrapped round the neck, with its knot on the left.
    { s: 'lathe', pts: [[0.165, 0.4], [0.155, 0.445], [0.125, 0.485], [0.095, 0.52], [0.08, 0.535]], sides: 16, scale: [1, 1, 0.82], at: [0, 0, -0.005], c: p.scarf, tile: 'stripes' },
    { s: 'ring', r: 0.084, tube: 0.026, sides: 16, at: [0, 0.53, -0.005], scale: [1, 1, 0.86], c: p.scarf, tile: 'stripes' },
    { s: 'ball', r: [0.04, 0.034, 0.03], seg: [8, 6], at: [0.088, 0.47, 0.105], c: p.scarf, tile: 'stripes' },
    // The neck.
    { s: 'cyl', r: [0.046, 0.052], h: 0.1, sides: 12, at: [0, 0.575, 0.0], c: p.skin, c2: p.skin },
    // Pack, worn over the cloak like the satchel in the logo, with the teal bedroll strapped underneath.
    { s: 'box', size: [0.24, 0.25, 0.12], taper: [0.92, 1], at: [0, 0.2, -0.272], c: c.pack, tile: 'leather' },
    { s: 'cyl', r: 0.06, h: 0.24, sides: 12, at: [0, 0.325, -0.272], rot: [0, 0, 90], c: c.pack, tile: 'leather' },
    { s: 'box', size: [0.18, 0.1, 0.04], at: [0, 0.15, -0.345], c: c.packLight, tile: 'leather' },
    { s: 'box', size: [0.185, 0.034, 0.046], at: [0, 0.195, -0.347], c: c.leather, tile: 'leather' },
    { s: 'cyl', r: 0.058, h: 0.34, sides: 12, at: [0, 0.03, -0.275], rot: [0, 0, 90], c: c.bedroll, c2: c.bedroll, tile: 'stripes' },
    ...[-0.1, 0.1].map((x): Part => ({ s: 'ring', r: 0.06, tube: 0.01, sides: 12, at: [x, 0.03, -0.275], rot: [0, 0, 90], c: c.strap })),
  ];
}

/**
 * Cloth with a little thickness, for a lathe: the outside from the bottom up, then the
 * inside back down, closed at the hem. Corners are doubled so their edges stay crisp.
 */
function cloth(outside: [number, number][], thick = 0.012): [number, number][] {
  const inside = outside
    .slice()
    .reverse()
    .map(([r, y]): [number, number] => [Math.max(0.001, r - thick), y]);
  const top = outside[outside.length - 1];
  const hem = outside[0];
  const innerTop = inside[0];
  const innerHem = inside[inside.length - 1];
  return [...outside, top, innerTop, ...inside, innerHem, hem];
}

/**
 * The cloak from the Spade logo: a cape over the shoulders, open at the front so the
 * scarf and buttons show, and a long drape down the back to the knees. With `hoodDown`
 * the hood lies on the shoulders (when a hat is worn, or the player prefers it down).
 */
export function cloakParts2(color: string, hoodDown: boolean): Part[] {
  const parts: Part[] = [
    // The drape: covers the back and sides, open wide at the front so the arms swing free.
    {
      s: 'lathe', open: 205, sides: 18, scale: [1, 1, 0.86], c: color, tile: 'cloth',
      pts: cloth([[0.31, -0.44], [0.296, -0.25], [0.272, -0.02], [0.247, 0.17], [0.228, 0.3], [0.218, 0.37]]),
    },
    // The cape over the shoulders.
    {
      s: 'lathe', open: 96, sides: 20, scale: [1, 1, 0.8], c: color, tile: 'cloth',
      pts: cloth([[0.276, 0.265], [0.273, 0.33], [0.265, 0.4], [0.25, 0.462], [0.212, 0.515], [0.155, 0.548], [0.115, 0.558]], 0.014),
    },
  ];
  if (hoodDown) {
    parts.push({
      s: 'lathe', sides: 16, at: [0, 0.45, -0.175], rot: [25, 0, 0], scale: [0.85, 0.6, 0.45], c: color, tile: 'cloth',
      pts: cloth(HOOD2_SHAPE, 0.016),
    });
  }
  return parts;
}

/** The hood's shape, a deep cup turned on a lathe: [radius, depth] from the back of the head to the rim. */
const HOOD2_SHAPE: [number, number][] = [
  [0.001, -0.214], [0.085, -0.204], [0.139, -0.165], [0.174, -0.09], [0.187, 0.0], [0.183, 0.075], [0.172, 0.122],
];

/** The hood pulled up, framing the face the way it does in the logo. Worn on the head. */
export function hoodUpParts2(color: string): Part[] {
  return [
    {
      // Tipped forward: the top of the opening comes out over the brow, as in the logo, and
      // the bottom slips behind the chin into the cape, so the hood frames the face without
      // closing under it.
      s: 'lathe', sides: 22, at: [0, 0.19, -0.016], rot: [112, 0, 0], scale: [0.95, 1, 1.09], c: color, tile: 'cloth',
      pts: cloth(HOOD2_SHAPE, 0.014),
    },
  ];
}

/** Shoulder and upper arm (the right one; the left is mirrored). `rolled` sleeves stop at the elbow. */
export function upperArmParts2(p: HeroPalette, rolled: boolean): Part[] {
  return [
    { s: 'ball', r: [0.07, 0.068, 0.068], seg: [12, 8], at: [0, -0.015, 0], c: p.sleeve, tile: 'cloth' },
    { s: 'lathe', pts: [[0.056, -0.275], [0.06, -0.17], [0.066, -0.06], [0.062, 0.0]], sides: 12, c: p.sleeve, tile: 'cloth' },
    ...(rolled ? [{ s: 'ring', r: 0.058, tube: 0.021, sides: 12, at: [0, -0.255, 0], c: p.sleeve, tile: 'cloth' } as Part] : []),
  ];
}

/** Forearm and hand, hanging from the elbow, with the fingers loosely curled. */
export function forearmParts2(p: HeroPalette, rolled: boolean): Part[] {
  const c = HERO2_COLORS;
  const hand: Part[] = [
    // Fingerless glove over the palm, then the fingers and a thumb.
    { s: 'ball', r: [0.041, 0.047, 0.029], seg: [10, 6], at: [0, -0.262, 0.004], c: c.glove, tile: 'leather' },
    ...[-0.024, -0.008, 0.008, 0.024].map((x, i): Part => ({
      s: 'capsule', r: 0.0105, h: 0.03 + (i === 1 || i === 2 ? 0.006 : 0), sides: 6,
      at: [x, -0.315, 0.012], rot: [-16, 0, 0], c: p.skin, c2: p.skin,
    })),
    { s: 'capsule', r: 0.0125, h: 0.028, sides: 6, at: [0.034, -0.27, 0.022], rot: [-24, 0, 34], c: p.skin, c2: p.skin },
  ];
  if (rolled) {
    return [
      { s: 'capsule', r: 0.042, h: 0.15, sides: 10, at: [0, -0.1, 0], c: p.skin, c2: p.skin },
      { s: 'lathe', pts: [[0.047, -0.235], [0.05, -0.19], [0.048, -0.155]], sides: 12, c: c.glove, tile: 'leather' },
      ...hand,
    ];
  }
  return [
    { s: 'lathe', pts: [[0.049, -0.215], [0.053, -0.12], [0.058, -0.02], [0.06, 0.03]], sides: 12, c: p.sleeve, tile: 'cloth' },
    { s: 'ring', r: 0.05, tube: 0.013, sides: 12, at: [0, -0.21, 0], c: c.leather, tile: 'leather' },
    { s: 'capsule', r: 0.038, h: 0.03, sides: 10, at: [0, -0.225, 0], c: p.skin, c2: p.skin },
    ...hand,
  ];
}

/** Thigh, from the hip to the knee. */
export function thighParts2(): Part[] {
  const c = HERO2_COLORS;
  return [{ s: 'lathe', pts: [[0.064, -0.385], [0.07, -0.3], [0.079, -0.17], [0.084, -0.05], [0.08, 0.04]], sides: 14, c: c.trouser, tile: 'cloth' }];
}

/** Shin and boot, hanging from the knee. `patched` adds a patch over the knee. */
export function shinParts2(patched: boolean): Part[] {
  const c = HERO2_COLORS;
  return [
    { s: 'lathe', pts: [[0.06, -0.13], [0.063, -0.06], [0.066, 0.0], [0.065, 0.02]], sides: 14, c: c.trouser, tile: 'cloth' },
    ...(patched ? [{ s: 'box', size: [0.058, 0.055, 0.016], at: [0.004, 0.0, 0.064], rot: [-4, 0, 4], c: c.patch, tile: 'cloth' } as Part] : []),
    { s: 'lathe', pts: [[0.066, -0.33], [0.07, -0.25], [0.069, -0.18], [0.072, -0.12]], sides: 14, c: c.boot, tile: 'leather' },
    { s: 'ring', r: 0.072, tube: 0.017, sides: 14, at: [0, -0.12, 0], c: c.bootCuff, tile: 'leather' },
    ...[-0.16, -0.2, -0.24].map((y): Part => ({ s: 'box', size: [0.05, 0.01, 0.012], at: [0, y, 0.07], c: c.lace, c2: c.lace })),
    { s: 'ball', r: [0.066, 0.05, 0.12], seg: [12, 6], at: [0, -0.335, 0.045], c: c.boot, tile: 'leather' },
    { s: 'box', size: [0.13, 0.03, 0.255], taper: 0.98, at: [0, -0.4, 0.045], c: c.sole, c2: c.sole },
    { s: 'box', size: [0.12, 0.05, 0.06], at: [0, -0.39, -0.055], c: c.sole, c2: c.sole },
  ];
}

export function headParts2(p: HeroPalette): Part[] {
  return [
    { s: 'lathe', pts: HEAD2_PROFILE, sides: 20, at: [0, 0, HEAD2_FORWARD], scale: [HEAD2_WIDTH, 1, HEAD2_DEPTH], c: p.skin, c2: p.skin },
    // The back of the skull.
    { s: 'ball', r: [0.132, 0.13, 0.13], seg: [16, 10], at: [0, 0.215, -0.045], c: p.skin, c2: p.skin },
    // Nose: a narrow bridge and a rounded tip.
    { s: 'box', size: [0.024, 0.056, 0.03], taper: [0.55, 0.7], at: [0, 0.137, headFrontZ(0, 0.137) - 0.006], rot: [-14, 0, 0], c: p.skin, c2: p.skin },
    { s: 'ball', r: [0.019, 0.016, 0.018], seg: [8, 6], at: [0, 0.112, headFrontZ(0, 0.112) + 0.004], c: p.skin, c2: p.skin },
    // Ears.
    ...[-1, 1].map((side): Part => ({ s: 'ball', r: [0.02, 0.039, 0.029], seg: [12, 8], at: [side * 0.134, 0.16, -0.012], rot: [0, side * 12, 0], c: p.skin, c2: p.skin })),
  ];
}

export function tailParts2(p: HeroPalette): [Part[], Part[]] {
  return [
    [{ s: 'box', size: [0.072, 0.17, 0.024], at: [0, -0.085, 0], c: p.scarf, c2: p.scarf, tile: 'stripes' }],
    [{ s: 'box', size: [0.066, 0.13, 0.022], taper: [0.55, 1], rot: [180, 0, 0], at: [0, -0.065, 0], c: p.scarf, tile: 'stripes' }],
  ];
}

/**
 * Hair comes in two versions: `top` is the whole hairdo, and `under` is what still
 * peeks out below a hat (a flatter cap that fits inside the crown, the fringe under
 * the brim, and the hair at the back), so a hat never leaves the hero looking bald.
 */
export function hairParts2(style: HairStyle, color: string): { top: Part[]; under: Part[]; hooded: Part[] } {
  const cap: Part = { s: 'ball', r: [0.148, 0.15, 0.172], seg: [18, 12], at: [0, 0.255, -0.022], c: color };
  const flatCap: Part = { s: 'ball', r: [0.15, 0.118, 0.173], seg: [18, 12], at: [0, 0.252, -0.022], c: color };
  const back: Part = { s: 'ball', r: [0.142, 0.152, 0.128], seg: [14, 10], at: [0, 0.172, -0.062], c: color };
  /**
   * One chunky lock: a cone starting at (x, y, z) on the scalp and running `len`
   * in the direction `pitch` (0 = up, 90 = forward, 180 = down), leaning sideways by `lean`.
   */
  const lock = (x: number, y: number, z: number, len: number, pitch: number, lean: number, w = 0.044): Part => {
    const a = pitch * DEG;
    const dir: Vec3 = [Math.sin(lean * DEG) * 0.45, Math.cos(a), Math.sin(a)];
    return {
      s: 'cyl', r: [0.005, w], h: len, sides: 7,
      at: [x + dir[0] * len * 0.5, y + dir[1] * len * 0.5, z + dir[2] * len * 0.5],
      rot: [pitch, 0, -lean], c: color,
    };
  };
  // Along the front of the cap, so every lock starts on the scalp.
  const front = (x: number) => 0.13 * Math.sqrt(Math.max(0, 1 - (x / 0.147) ** 2));
  // A fringe of chunky locks swept to one side.
  const fringe: Part[] = [
    lock(-0.092, 0.285, front(-0.092), 0.09, 150, 20, 0.038),
    lock(-0.048, 0.3, front(-0.048), 0.11, 156, 16, 0.042),
    lock(0.0, 0.305, front(0), 0.115, 158, 14),
    lock(0.046, 0.3, front(0.046), 0.105, 154, 24, 0.04),
    lock(0.092, 0.285, front(0.092), 0.085, 146, 30, 0.034),
  ];
  // Under a hat the same fringe lies a little flatter, so it slips out from under the
  // brim or the cuff instead of poking through it.
  const tucked = fringe.map((part): Part => ({ ...part, at: [part.at![0], part.at![1] - 0.014, part.at![2] - 0.016], scale: [1, 1, 0.6] }));
  // Under the hood only the fringe shows, so the rest is a small cap that stays inside it.
  const hoodCap: Part = { s: 'ball', r: [0.138, 0.112, 0.165], seg: [18, 12], at: [0, 0.25, -0.024], c: color };
  // The fringe spills out over the forehead, the way it does in the logo.
  const spill = fringe.map((part): Part => ({ ...part, at: [part.at![0], part.at![1] - 0.004, part.at![2] + 0.008], scale: [1, 1, 0.7] }));
  const hooded = [hoodCap, ...spill];
  // Short hair over each temple, in front of the ears.
  const temples: Part[] = [-1, 1].map((side) => lock(side * 0.13, 0.245, 0.035, 0.075, 176, side * 6, 0.028));
  switch (style) {
    case 'none':
      return { top: [], under: [], hooded: [] };
    case 'crop':
      return { top: [cap, ...fringe, back, ...temples], under: [flatCap, ...tucked, back, ...temples], hooded };
    case 'tuft':
      return {
        top: [
          cap,
          back,
          ...temples,
          ...fringe.slice(1, 4),
          lock(0.0, 0.39, 0.05, 0.12, 18, 0, 0.05),
          lock(-0.07, 0.38, 0.01, 0.11, 6, -26, 0.046),
          lock(0.07, 0.38, -0.01, 0.11, 2, 30, 0.046),
          lock(0.0, 0.385, -0.07, 0.11, -26, 4, 0.046),
          lock(-0.105, 0.32, -0.03, 0.09, -10, -52, 0.04),
          lock(0.105, 0.32, -0.04, 0.09, -10, 52, 0.04),
        ],
        under: [flatCap, back, ...temples, ...tucked.slice(1, 4)],
        hooded,
      };
    case 'long': {
      const fall: Part[] = [
        { s: 'lathe', pts: [[0.13, -0.19], [0.158, -0.09], [0.168, 0.02], [0.162, 0.1], [0.12, 0.15]], sides: 18, at: [0, 0.15, -0.05], scale: [0.9, 1, 0.82], c: color },
        ...[-1, 1].map((side): Part => ({ s: 'box', size: [0.034, 0.25, 0.075], taper: [0.7, 1], at: [side * 0.142, 0.1, 0.035], rot: [0, 0, side * 4], c: color })),
      ];
      // Under the hood, two long locks fall out at the sides of the face.
      return { top: [cap, ...fringe, ...fall], under: [flatCap, ...tucked, ...fall], hooded: [...hooded, ...fall.slice(1)] };
    }
    case 'knot': {
      const bun: Part[] = [
        { s: 'ball', r: [0.07, 0.062, 0.066], seg: [12, 8], at: [0, 0.385, -0.095], c: color },
        { s: 'ring', r: 0.042, tube: 0.012, sides: 12, at: [0, 0.345, -0.085], rot: [-30, 0, 0], c: '#b5472f', c2: '#b5472f' },
      ];
      // Under a hat the knot drops to the nape of the neck.
      const lowBun: Part[] = [
        { s: 'ball', r: [0.066, 0.058, 0.06], seg: [12, 8], at: [0, 0.12, -0.18], c: color },
        { s: 'ring', r: 0.04, tube: 0.011, sides: 12, at: [0, 0.15, -0.16], rot: [-70, 0, 0], c: '#b5472f', c2: '#b5472f' },
      ];
      return { top: [cap, ...fringe, back, ...temples, ...bun], under: [flatCap, ...tucked, back, ...temples, ...lowBun], hooded };
    }
  }
}
