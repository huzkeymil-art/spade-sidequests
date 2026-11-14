// Makes every size of Spade's app icon from one master picture, art/app-icon.png.
//
// The master is a 1024 x 1024 square with no transparency and no rounded
// corners: phones round the corners themselves. To change the icon, replace
// that file and run `npm run icons`. It needs nothing installed beyond Node itself.

import { deflateSync, inflateSync } from 'node:zlib';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MASTER = join(ROOT, 'art', 'app-icon.png');
const WEB = join(ROOT, 'public');
const IOS = join(ROOT, 'ios', 'Spade', 'Assets.xcassets', 'AppIcon.appiconset');

// ---- A tiny PNG reader --------------------------------------------------------

/** Reads a PNG into { size, rgb }. Handles the common 8-bit RGB and RGBA kinds. */
function readPng(file) {
  const data = readFileSync(file);
  let at = 8;
  let width = 0;
  let height = 0;
  let channels = 3;
  const packed = [];
  while (at < data.length) {
    const length = data.readUInt32BE(at);
    const type = data.toString('ascii', at + 4, at + 8);
    const body = data.subarray(at + 8, at + 8 + length);
    if (type === 'IHDR') {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      const kind = body[9];
      if (body[8] !== 8 || (kind !== 2 && kind !== 6) || body[12] !== 0) {
        throw new Error('art/app-icon.png must be an ordinary 8-bit RGB or RGBA PNG');
      }
      channels = kind === 6 ? 4 : 3;
    } else if (type === 'IDAT') {
      packed.push(body);
    }
    at += 12 + length;
  }
  if (width !== height) throw new Error('art/app-icon.png must be square');

  // Each row is stored as differences from its neighbours; undo that.
  const raw = inflateSync(Buffer.concat(packed));
  const stride = width * channels;
  const pixels = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const row = y * stride;
    for (let i = 0; i < stride; i++) {
      const value = raw[y * (stride + 1) + 1 + i];
      const left = i >= channels ? pixels[row + i - channels] : 0;
      const up = y > 0 ? pixels[row - stride + i] : 0;
      const upLeft = y > 0 && i >= channels ? pixels[row - stride + i - channels] : 0;
      let guess = 0;
      if (filter === 1) guess = left;
      else if (filter === 2) guess = up;
      else if (filter === 3) guess = (left + up) >> 1;
      else if (filter === 4) {
        const p = left + up - upLeft;
        const dl = Math.abs(p - left);
        const du = Math.abs(p - up);
        const dul = Math.abs(p - upLeft);
        guess = dl <= du && dl <= dul ? left : du <= dul ? up : upLeft;
      }
      pixels[row + i] = (value + guess) & 0xff;
    }
  }

  // Drop any transparency: app icons must be solid.
  const rgb = Buffer.alloc(width * height * 3);
  for (let i = 0; i < width * height; i++) {
    rgb[i * 3] = pixels[i * channels];
    rgb[i * 3 + 1] = pixels[i * channels + 1];
    rgb[i * 3 + 2] = pixels[i * channels + 2];
  }
  return { size: width, rgb };
}

/** Shrinks a square picture by averaging the block of pixels each new pixel covers. */
function shrink(image, size) {
  if (size === image.size) return image;
  const scale = image.size / size;
  const rgb = Buffer.alloc(size * size * 3);
  for (let y = 0; y < size; y++) {
    const y0 = Math.floor(y * scale);
    const y1 = Math.max(y0 + 1, Math.floor((y + 1) * scale));
    for (let x = 0; x < size; x++) {
      const x0 = Math.floor(x * scale);
      const x1 = Math.max(x0 + 1, Math.floor((x + 1) * scale));
      let r = 0;
      let g = 0;
      let b = 0;
      for (let sy = y0; sy < y1; sy++) {
        for (let sx = x0; sx < x1; sx++) {
          const i = (sy * image.size + sx) * 3;
          r += image.rgb[i];
          g += image.rgb[i + 1];
          b += image.rgb[i + 2];
        }
      }
      const count = (y1 - y0) * (x1 - x0);
      const o = (y * size + x) * 3;
      rgb[o] = Math.round(r / count);
      rgb[o + 1] = Math.round(g / count);
      rgb[o + 2] = Math.round(b / count);
    }
  }
  return { size, rgb };
}

// ---- A tiny PNG writer --------------------------------------------------------

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

function writePng(file, image) {
  const { size, rgb } = image;
  const stride = size * 3;
  const raw = Buffer.alloc(size * (stride + 1));
  for (let y = 0; y < size; y++) {
    const row = y * (stride + 1);
    // Store each row as the difference from the row above, which packs smooth pictures well.
    raw[row] = y === 0 ? 0 : 2;
    for (let i = 0; i < stride; i++) {
      const up = y === 0 ? 0 : rgb[(y - 1) * stride + i];
      raw[row + 1 + i] = (rgb[y * stride + i] - up) & 0xff;
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8; // bits per channel
  header[9] = 2; // colour type: RGB, with no transparency
  writeFileSync(
    file,
    Buffer.concat([
      Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
      chunk('IHDR', header),
      chunk('IDAT', deflateSync(raw, { level: 9 })),
      chunk('IEND', Buffer.alloc(0)),
    ]),
  );
}

// ---- Make the files -----------------------------------------------------------

const master = readPng(MASTER);
if (master.size < 1024) throw new Error('art/app-icon.png should be at least 1024 pixels wide');

mkdirSync(WEB, { recursive: true });
for (const [name, size] of [
  ['icon-192.png', 192],
  ['icon-512.png', 512],
  ['apple-touch-icon.png', 180],
]) {
  writePng(join(WEB, name), shrink(master, size));
  console.log(`wrote public/${name} (${size}px)`);
}

// The native app's icon: one large square, which Xcode scales to every size it needs.
mkdirSync(IOS, { recursive: true });
writePng(join(IOS, 'icon-1024.png'), shrink(master, 1024));
console.log('wrote the iPhone app icon (1024px)');
