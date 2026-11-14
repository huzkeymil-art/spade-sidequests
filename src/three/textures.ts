import * as THREE from 'three';
import { makeRng } from '../game/rng';

// Every surface texture in Spade is painted by code, at a tiny 32 x 32 pixels,
// and then stretched over the models with blurry filtering. That smeared,
// low-detail look is a big part of the late-90s console feel.
//
// All tiles live side by side in one image called an atlas (like a sticker
// sheet), so the whole scene can be drawn using a single texture.

export const TILE = 32;
export const ATLAS_COLS = 4;
export const ATLAS_ROWS = 2;

export const Tile = {
  plain: 0,
  soil: 1,
  stone: 2,
  wood: 3,
  cloth: 4,
  metal: 5,
  leather: 6,
  stripes: 7,
} as const;
export type TileName = keyof typeof Tile;

type Painter = (x: number, y: number, rng: () => number, noise: (x: number, y: number, cell: number) => number) => number;

// Each painter returns a brightness around 0.8 (neutral). The shader multiplies by 1.25.
const painters: Record<TileName, Painter> = {
  plain: () => 0.8,
  soil: (x, y, rng, noise) => {
    let v = 0.62 + noise(x, y, 8) * 0.3 + noise(x, y, 3) * 0.08;
    const speck = rng();
    if (speck > 0.93) v += 0.2;
    else if (speck < 0.1) v -= 0.2;
    return v;
  },
  stone: (x, y, rng, noise) => {
    let v = 0.6 + noise(x, y, 10) * 0.32 + noise(x + 40, y, 4) * 0.12;
    // A couple of dark cracks running diagonally.
    const crackA = Math.abs(y - (8 + x * 0.55 + Math.sin(x * 0.9) * 1.5));
    const crackB = Math.abs(x - (22 - y * 0.3 + Math.sin(y * 0.7) * 2));
    if (crackA < 0.7 && x > 4 && x < 26) v -= 0.3;
    if (crackB < 0.6 && y > 10) v -= 0.24;
    if (rng() > 0.95) v -= 0.14;
    return v;
  },
  wood: (x, y, rng, noise) => {
    const wobble = Math.sin(y * 0.35) * 1.2;
    const grain = Math.sin((x + wobble) * 1.35) * 0.5 + 0.5;
    let v = 0.64 + grain * 0.2 + noise(x, y * 0.25, 6) * 0.12;
    // One knot.
    const dx = x - 20;
    const dy = (y - 12) * 0.6;
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d < 3.2) v -= 0.22 * (1 - d / 3.2) + 0.06;
    if (rng() > 0.97) v -= 0.1;
    return v;
  },
  cloth: (x, y, _rng, noise) => {
    const weave = (x + y) % 2 === 0 ? 0.05 : -0.03;
    const thread = y % 4 === 0 ? -0.07 : 0;
    return 0.76 + weave + thread + noise(x, y, 12) * 0.12;
  },
  metal: (x, y, rng, noise) => {
    let v = 0.68 + noise(x * 0.2, y, 5) * 0.2 + noise(x, y, 14) * 0.06;
    if (Math.abs(y - (6 + x * 0.2)) < 0.6 && x > 6 && x < 22) v += 0.28; // bright scratch
    if (Math.abs(y - (24 - x * 0.12)) < 0.5 && x > 12) v += 0.18;
    if (rng() > 0.96) v -= 0.16; // pitting
    return v;
  },
  leather: (x, y, rng, noise) => {
    let v = 0.66 + noise(x, y, 7) * 0.24;
    if ((x === 2 || x === 29) && y % 3 !== 0) v += 0.2; // stitching down the sides
    if (rng() > 0.94) v -= 0.1;
    return v;
  },
  stripes: (x, y, _rng, noise) => {
    const band = Math.floor(y / 5) % 2 === 0 ? 0.9 : 0.56;
    return band + noise(x, y, 10) * 0.08 + ((x + y) % 2 === 0 ? 0.03 : -0.02);
  },
};

/** Smooth random blotches: random values on a coarse grid, blended between grid points. */
function makeNoise(seed: number) {
  const rng = makeRng(seed);
  const table = new Float32Array(64 * 64);
  for (let i = 0; i < table.length; i++) table[i] = rng();
  const at = (ix: number, iy: number) => table[((iy & 63) << 6) | (ix & 63)];
  return (x: number, y: number, cell: number) => {
    const fx = x / cell;
    const fy = y / cell;
    const ix = Math.floor(fx);
    const iy = Math.floor(fy);
    const tx = fx - ix;
    const ty = fy - iy;
    const sx = tx * tx * (3 - 2 * tx);
    const sy = ty * ty * (3 - 2 * ty);
    const top = at(ix, iy) * (1 - sx) + at(ix + 1, iy) * sx;
    const bottom = at(ix, iy + 1) * (1 - sx) + at(ix + 1, iy + 1) * sx;
    return top * (1 - sy) + bottom * sy - 0.5;
  };
}

let atlas: THREE.DataTexture | null = null;

/** The shared surface atlas (built once). */
export function getAtlas(): THREE.DataTexture {
  if (atlas) return atlas;
  const w = TILE * ATLAS_COLS;
  const h = TILE * ATLAS_ROWS;
  const data = new Uint8Array(w * h * 4);
  (Object.keys(Tile) as TileName[]).forEach((name) => {
    const index = Tile[name];
    const ox = (index % ATLAS_COLS) * TILE;
    const oy = Math.floor(index / ATLAS_COLS) * TILE;
    const rng = makeRng(1000 + index * 77);
    const noise = makeNoise(500 + index * 31);
    for (let y = 0; y < TILE; y++) {
      for (let x = 0; x < TILE; x++) {
        const v = Math.max(0, Math.min(1, painters[name](x, y, rng, noise)));
        const i = ((oy + y) * w + ox + x) * 4;
        const byte = Math.round(v * 255);
        data[i] = byte;
        data[i + 1] = byte;
        data[i + 2] = byte;
        data[i + 3] = 255;
      }
    }
  });
  atlas = new THREE.DataTexture(data, w, h, THREE.RGBAFormat);
  atlas.magFilter = THREE.LinearFilter;
  atlas.minFilter = THREE.LinearFilter;
  atlas.generateMipmaps = false;
  atlas.needsUpdate = true;
  return atlas;
}

/** Converts a 0..1 position on a tile into a position on the whole atlas. */
export function tileUv(tile: number, u: number, v: number): [number, number] {
  const inset = 0.5 / TILE; // stay half a pixel inside so neighbours don't bleed in
  const tx = tile % ATLAS_COLS;
  const ty = Math.floor(tile / ATLAS_COLS);
  return [
    (tx + inset + u * (1 - inset * 2)) / ATLAS_COLS,
    (ty + inset + v * (1 - inset * 2)) / ATLAS_ROWS,
  ];
}

/** Builds a small pixel-art texture from rows of text. Each character picks a colour from the key. */
export function pixelTexture(
  rows: string[],
  key: Record<string, [number, number, number, number]>,
  filter: THREE.MagnificationTextureFilter = THREE.NearestFilter,
): THREE.DataTexture {
  const h = rows.length;
  const w = rows[0].length;
  const data = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const rgba = key[rows[h - 1 - y][x]] ?? [0, 0, 0, 0]; // textures start at the bottom row
      data.set(rgba, (y * w + x) * 4);
    }
  }
  const tex = new THREE.DataTexture(data, w, h, THREE.RGBAFormat);
  tex.magFilter = filter;
  tex.minFilter = filter;
  tex.generateMipmaps = false;
  tex.needsUpdate = true;
  return tex;
}

let glow: THREE.DataTexture | null = null;

/** A soft round blob of light, used for flames, halos and fireflies. */
export function getGlowTexture(): THREE.DataTexture {
  if (glow) return glow;
  const size = 32;
  const data = new Uint8Array(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = (x + 0.5) / size - 0.5;
      const dy = (y + 0.5) / size - 0.5;
      const d = Math.min(1, Math.sqrt(dx * dx + dy * dy) * 2);
      const v = Math.pow(1 - d, 2.2);
      const i = (y * size + x) * 4;
      const byte = Math.round(v * 255);
      data[i] = data[i + 1] = data[i + 2] = byte;
      data[i + 3] = 255;
    }
  }
  glow = new THREE.DataTexture(data, size, size, THREE.RGBAFormat);
  glow.magFilter = THREE.LinearFilter;
  glow.minFilter = THREE.LinearFilter;
  glow.generateMipmaps = false;
  glow.needsUpdate = true;
  return glow;
}
