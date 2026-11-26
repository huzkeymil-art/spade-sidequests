// The new hero's face, painted by code into a small picture with smooth edges
// (each pixel is sampled 16 times), instead of the original's chunky pixel art.
//
// The picture holds four frames stacked top to bottom:
//   0 eyes open, looking ahead   1 glancing to the hero's right
//   2 glancing to the hero's left   3 eyes closed (a blink)
// Like the old face, the frame is chosen by moving the picture, so the eyes can
// lead the head when it turns, the way the eyes of a toon hero look at things first.
//
// Lots of small choices aim at a candid, lived-in face rather than a mask, and one
// that reads as neither a boy nor a girl: level eyes with an even lid line (no
// lashes or wing), the iris tucked a little under the upper lid, two catchlights,
// straight, thick brows with one a touch higher than the other, a lopsided half
// smile, and a sticking plaster from yesterday's dig.

export const FACE2_W = 128;
export const FACE2_H = 120;
export const FACE2_FRAMES = 4;
export const FACE2_FRAME = { open: 0, right: 1, left: 2, closed: 3 } as const;

type RGBA = [number, number, number, number];
type Shape = (x: number, y: number) => boolean;

/** Distance from a point to a line segment. */
function segDist(px: number, py: number, ax: number, ay: number, bx: number, by: number): [number, number] {
  const dx = bx - ax;
  const dy = by - ay;
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy || 1)));
  return [Math.hypot(px - (ax + dx * t), py - (ay + dy * t)), t];
}

/** A brush stroke along a path, whose width can change from start to end. */
function stroke(points: [number, number][], w0: number, w1 = w0): Shape {
  const lengths = [0];
  for (let i = 1; i < points.length; i++) {
    lengths.push(lengths[i - 1] + Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]));
  }
  const total = lengths[lengths.length - 1] || 1;
  return (x, y) => {
    for (let i = 1; i < points.length; i++) {
      const [d, t] = segDist(x, y, points[i - 1][0], points[i - 1][1], points[i][0], points[i][1]);
      const along = (lengths[i - 1] + t * (lengths[i] - lengths[i - 1])) / total;
      if (d <= (w0 + (w1 - w0) * along) / 2) return true;
    }
    return false;
  };
}

const ellipse = (cx: number, cy: number, rx: number, ry: number, angle = 0): Shape => {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return (x, y) => {
    const dx = x - cx;
    const dy = y - cy;
    const u = (dx * c + dy * s) / rx;
    const v = (-dx * s + dy * c) / ry;
    return u * u + v * v <= 1;
  };
};

const rect = (cx: number, cy: number, w: number, h: number, angle = 0): Shape => {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return (x, y) => {
    const dx = x - cx;
    const dy = y - cy;
    return Math.abs(dx * c + dy * s) <= w / 2 && Math.abs(-dx * s + dy * c) <= h / 2;
  };
};

const and = (a: Shape, b: Shape): Shape => (x, y) => a(x, y) && b(x, y);

/** Points along a curve y = f(x), from x0 to x1. */
function curve(x0: number, x1: number, f: (x: number) => number, n = 14): [number, number][] {
  const pts: [number, number][] = [];
  for (let i = 0; i <= n; i++) {
    const x = x0 + ((x1 - x0) * i) / n;
    pts.push([x, f(x)]);
  }
  return pts;
}

interface Layer {
  shape: Shape;
  color: RGBA;
}

/** One eye. `side` is -1 for the eye on the left of the picture, +1 for the right. `glance` moves the iris sideways. */
function eye(cx: number, cy: number, side: number, glance: number, closed: boolean): Layer[] {
  const half = 15.4;
  // Nearly level: an upswept outer corner reads as a cat-eye, so it only rises a touch.
  const lift = (x: number) => ((x - cx) / half) * side * -0.4;
  const upper = (x: number) => {
    const t = (x - cx) / half;
    return cy - 9.4 * (1 - t * t) * (1 - 0.12 * t * side) + lift(x);
  };
  const lower = (x: number) => {
    const t = (x - cx) / half;
    return cy + 7.0 * Math.pow(Math.max(0, 1 - t * t), 0.85) + lift(x) * 0.5;
  };
  const x0 = cx - half;
  const x1 = cx + half;
  const skinShade: RGBA = [96, 62, 46, 52];
  if (closed) {
    const lid = (x: number) => (upper(x) * 0.25 + lower(x) * 0.75) - 1;
    return [
      { shape: stroke(curve(x0, x1, (x) => upper(x) - 3.2), 1.2), color: skinShade },
      { shape: stroke(curve(x0 - 0.3, x1 + 0.3, lid), 2.2), color: [40, 27, 21, 255] },
    ];
  }
  const opening: Shape = (x, y) => x > x0 && x < x1 && y > upper(x) && y < lower(x);
  const ix = cx + glance;
  const iy = cy - 0.6;
  return [
    // Lid crease, and the whites (slightly shaded under the upper lid).
    { shape: stroke(curve(x0 + 4, x1 - 4, (x) => upper(x) - 3.6), 1.1), color: skinShade },
    { shape: opening, color: [236, 230, 218, 255] },
    { shape: and(opening, (x, y) => y < upper(x) + 2.6), color: [198, 186, 174, 255] },
    // Iris: a dark rim, a warm hazel middle, lighter toward the bottom.
    { shape: and(opening, ellipse(ix, iy, 9.3, 9.6)), color: [52, 34, 22, 255] },
    { shape: and(opening, ellipse(ix, iy, 7.8, 8.1)), color: [120, 84, 48, 255] },
    { shape: and(opening, ellipse(ix, iy + 2.6, 6.3, 4.9)), color: [160, 120, 70, 255] },
    { shape: and(opening, ellipse(ix, iy, 3.7, 3.9)), color: [20, 13, 10, 255] },
    // Shadow of the lid across the top of the iris.
    { shape: and(opening, (x, y) => y < upper(x) + 2.2 && (x - ix) ** 2 + (y - iy) ** 2 < 92), color: [40, 28, 20, 150] },
    // Catchlights.
    { shape: and(opening, ellipse(ix - 3.0 * side - 0.6, iy - 3.7, 2.3, 2.1)), color: [255, 253, 246, 255] },
    { shape: and(opening, ellipse(ix + 2.8 * side, iy + 2.6, 0.8, 0.8)), color: [255, 253, 246, 170] },
    // Upper lid line: an even line, with no wing or lashes at the corner.
    { shape: stroke(curve(x0 - 0.3, x1 + 0.3, upper), 2.6), color: [40, 28, 22, 255] },
    // Lower lid, faint.
    { shape: stroke(curve(x0 + 3, x1 - 1, (x) => lower(x) + 0.6), 0.9), color: [110, 70, 52, 120] },
  ];
}

function brow(cx: number, cy: number, side: number, raise: number): Layer {
  const inner = cx - side * 11.5;
  const outer = cx + side * 13.5;
  const pts = curve(inner, outer, (x) => {
    const t = (x - inner) / (outer - inner);
    // Fairly straight and thick: a gentle rise, without a high, thin arch.
    return cy - 1.5 - raise - Math.sin(t * Math.PI * 0.82) * 1.4 + t * 0.9;
  });
  return { shape: stroke(pts, 4.6, 3.2), color: [58, 40, 28, 242] };
}

/** Paints all four frames. Returns RGBA pixels, top row first. */
export function paintFace2(): Uint8Array {
  const W = FACE2_W;
  const H = FACE2_H;
  const out = new Uint8Array(W * H * FACE2_FRAMES * 4);
  const L = { x: 40, y: 54 };
  const R = { x: 88, y: 54 };
  const glances = [0, -3.7, 3.7, 0];
  for (let frame = 0; frame < FACE2_FRAMES; frame++) {
    const closed = frame === FACE2_FRAME.closed;
    const g = glances[frame];
    const layers: Layer[] = [
      // A faint warmth on the cheeks, just enough that the face isn't flat.
      { shape: ellipse(30, 80, 11, 6.5), color: [204, 120, 100, 14] },
      { shape: ellipse(98, 80, 11, 6.5), color: [204, 120, 100, 14] },
      // A sticking plaster high on one cheek.
      { shape: rect(100, 77, 13, 5.6, -0.42), color: [222, 196, 156, 255] },
      { shape: rect(100, 77, 4.6, 5.0, -0.42), color: [200, 170, 128, 255] },
      ...eye(L.x, L.y, -1, g, closed),
      ...eye(R.x, R.y, 1, g, closed),
      brow(L.x, L.y - 15, -1, 0),
      brow(R.x, R.y - 15, 1, 1.2),
      // Half smile: one corner lifts a little more than the other.
      { shape: stroke(curve(54, 77, (x) => { const t = (x - 54) / 23; return 101.5 + Math.sin(t * Math.PI) * 2.1 - t * 1.6; }), 1.7, 1.3), color: [118, 60, 50, 230] },
      { shape: stroke([[76.2, 99.6], [78.4, 98.4]], 1.2, 0.6), color: [118, 60, 50, 170] },
    ];
    const SS = 4;
    for (let py = 0; py < H; py++) {
      for (let px = 0; px < W; px++) {
        let r = 0, gr = 0, b = 0, a = 0;
        for (let sy = 0; sy < SS; sy++) {
          for (let sx = 0; sx < SS; sx++) {
            const x = px + (sx + 0.5) / SS;
            const y = py + (sy + 0.5) / SS;
            // Paint layers back to front ("over" blending) onto a clear sample.
            let cr = 0, cg = 0, cb = 0, ca = 0;
            for (const layer of layers) {
              if (!layer.shape(x, y)) continue;
              const la = layer.color[3] / 255;
              cr = layer.color[0] * la + cr * (1 - la);
              cg = layer.color[1] * la + cg * (1 - la);
              cb = layer.color[2] * la + cb * (1 - la);
              ca = la + ca * (1 - la);
            }
            r += cr; gr += cg; b += cb; a += ca;
          }
        }
        const n = SS * SS;
        const i = ((frame * H + py) * W + px) * 4;
        // Store un-premultiplied colour, so soft edges blend onto any skin tone.
        const alpha = a / n;
        out[i] = alpha > 0 ? Math.round(r / n / alpha) : 0;
        out[i + 1] = alpha > 0 ? Math.round(gr / n / alpha) : 0;
        out[i + 2] = alpha > 0 ? Math.round(b / n / alpha) : 0;
        out[i + 3] = Math.round(alpha * 255);
      }
    }
  }
  return out;
}
