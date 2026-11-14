// Draws Spade's app icon and saves it as PNG files in /public.
//
// The icon is pixel art made with maths rather than drawn by hand: a spade
// against a full moon, on a dithered night sky. Run it with `npm run icons`.
// It needs nothing installed beyond Node itself.

import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'public');

const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const SKY_TOP = hex('#060a0b');
const SKY_LOW = hex('#22393a');
const MOON = hex('#e9e6c9');
const MOON_SEA = hex('#c9c6a8');
const MOON_RIM = hex('#b3b196');
const INK = hex('#0d0f0c');

const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/** True if the point (x, y) is inside the spade. Coordinates run -1..1, with +y pointing up. */
function inSpade(x, y) {
  const ax = Math.abs(x);
  // Two round shoulders.
  if (Math.hypot(ax - 0.37, y + 0.14) < 0.43) return true;
  // The pointed top, with slightly bulging sides.
  if (y > -0.2 && y < 0.94 && ax < 0.8 * Math.pow((0.94 - y) / 1.14, 0.78)) return true;
  // The stem, flaring out at the bottom.
  if (y <= -0.2 && y > -0.94 && ax < 0.07 + (-0.2 - y) * 0.36) return true;
  return false;
}

/** Colour of one chunky pixel on a `grid` x `grid` canvas. */
function pixel(gx, gy, grid) {
  const x = ((gx + 0.5) / grid) * 2 - 1;
  const y = 1 - ((gy + 0.5) / grid) * 2;
  const threshold = BAYER[(gy % 4) * 4 + (gx % 4)] / 16;

  // The spade sits on the moon, a little below centre.
  if (inSpade(x / 0.5, (y + 0.02) / 0.5)) return INK;

  const moonDist = Math.hypot(x, y) / 0.72;
  if (moonDist < 1) {
    if (moonDist > 0.92 && threshold > 0.45) return MOON_RIM;
    const sea = Math.sin(x * 5.1 + 1.2) * Math.cos(y * 4.3 - 0.7) + Math.sin((x - y) * 7) * 0.4;
    return sea > 0.72 + threshold * 0.25 ? MOON_SEA : MOON;
  }

  // Night sky: a top-to-bottom fade, dithered into six flat steps.
  const t = Math.min(1, Math.max(0, (1 - y) / 2));
  const steps = 6;
  const level = Math.min(steps, Math.floor(t * steps + threshold)) / steps;
  // A faint ring of glow hugging the moon.
  const glow = Math.max(0, 1 - (moonDist - 1) / 0.35) * 0.35;
  const mix = Math.min(1, level + (glow > threshold * 0.6 ? glow : 0));
  return SKY_TOP.map((c, i) => Math.round(c + (SKY_LOW[i] - c) * mix));
}

// ---- A tiny PNG writer ------------------------------------------------------

const crcTable = new Int32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c;
});

function crc32(buffer) {
  let c = -1;
  for (const byte of buffer) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'ascii');
  const tail = Buffer.alloc(4);
  tail.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, tail]);
}

function png(size, grid) {
  const cell = size / grid;
  const raw = Buffer.alloc(size * (size * 3 + 1));
  const cache = new Map();
  for (let py = 0; py < size; py++) {
    const row = py * (size * 3 + 1);
    raw[row] = 0; // "no filter" marker that starts every row
    for (let px = 0; px < size; px++) {
      const gx = Math.min(grid - 1, Math.floor(px / cell));
      const gy = Math.min(grid - 1, Math.floor(py / cell));
      const key = gy * grid + gx;
      let rgb = cache.get(key);
      if (!rgb) cache.set(key, (rgb = pixel(gx, gy, grid)));
      raw.set(rgb, row + 1 + px * 3);
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8; // bits per channel
  header[9] = 2; // colour type: RGB
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

mkdirSync(OUT, { recursive: true });
// Each size uses a grid that divides it evenly, so every chunky pixel is the same size.
const files = [
  ['icon-192.png', 192, 32],
  ['icon-512.png', 512, 32],
  ['apple-touch-icon.png', 180, 30],
];
for (const [name, size, grid] of files) {
  writeFileSync(join(OUT, name), png(size, grid));
  console.log(`wrote public/${name} (${size}px)`);
}
