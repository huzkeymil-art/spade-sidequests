import * as THREE from 'three';
import { makeRng } from '../game/rng';
import { buildMesh, type Part } from './parts';
import { litMaterial, makeDecalMaterial, makeGlow, world, type GlowSprite } from './RetroMaterial';
import { Tile, pixelTexture, tileUv } from './textures';

// The dig site: ground, the Week Stone, the lantern, the moon and the sky.

export const LANTERN_POS = new THREE.Vector3(-0.98, 0, 0.6);
export const DIG_POS = new THREE.Vector3(0.72, 0, 1.05);
export const STONE_POS = new THREE.Vector3(1.02, 0, -1.0);

const SKY_TOP = new THREE.Color(0x05080a);
const SKY_MID = new THREE.Color(0x0f1c1f);
export const HORIZON = new THREE.Color(0x24393a);

// ---------------------------------------------------------------------------
// Ground

function groundHeight(x: number, z: number): number {
  const r = Math.sqrt(x * x + z * z);
  // Flat where the hero stands, gently rolling further out.
  const roll = Math.sin(x * 0.45 + 1.3) * Math.cos(z * 0.38 - 0.4) * 0.5 + Math.sin(x * 1.3 + z * 0.9) * 0.12;
  return roll * THREE.MathUtils.smoothstep(r, 2.2, 9);
}

function makeGround(): THREE.Mesh {
  const rings = [0, 0.45, 0.9, 1.4, 2, 2.8, 3.8, 5.2, 7.5, 11, 17, 28, 60];
  const spokes = 22;
  const rng = makeRng(77);
  const positions: number[] = [];
  const tints: number[] = [];
  const uvs: number[] = [];
  const emits: number[] = [];
  const index: number[] = [];

  const near = new THREE.Color(0x5a4a34);
  const nearAlt = new THREE.Color(0x4b4a30);
  const far = new THREE.Color(0x232a22);
  const pit = new THREE.Color(0x2a2118);
  const c = new THREE.Color();

  for (let ri = 0; ri < rings.length; ri++) {
    for (let si = 0; si < spokes; si++) {
      const angle = (si / spokes) * Math.PI * 2 + (ri % 2) * (Math.PI / spokes);
      const wobble = ri === 0 ? 0 : (rng() - 0.5) * 0.25 * Math.min(1, rings[ri] / 3);
      const r = rings[ri] * (1 + wobble * 0.3);
      const x = Math.cos(angle) * r;
      const z = Math.sin(angle) * r;
      positions.push(x, groundHeight(x, z) + (ri > 0 ? (rng() - 0.5) * 0.04 : 0), z);

      c.copy(near).lerp(nearAlt, rng());
      c.lerp(far, THREE.MathUtils.smoothstep(r, 2.5, 14));
      // Freshly turned, darker earth around the dig.
      const digDist = Math.hypot(x - DIG_POS.x, z - DIG_POS.z);
      c.lerp(pit, (1 - THREE.MathUtils.smoothstep(digDist, 0.2, 0.9)) * 0.75);
      // Close up the soil is patchy; far away the patches would turn into streaks, so they fade out.
      const patchy = 0.3 * (1 - THREE.MathUtils.smoothstep(r, 3, 7));
      c.multiplyScalar(1 - patchy / 2 + rng() * patchy);
      tints.push(c.r, c.g, c.b);
      emits.push(0);

      const [u, v] = tileUv(Tile.soil, THREE.MathUtils.clamp(x / 5 + 0.5, 0, 1), THREE.MathUtils.clamp(z / 5 + 0.5, 0, 1));
      uvs.push(u, v);
    }
  }
  for (let ri = 0; ri < rings.length - 1; ri++) {
    for (let si = 0; si < spokes; si++) {
      const a = ri * spokes + si;
      const b = ri * spokes + ((si + 1) % spokes);
      const d = (ri + 1) * spokes + si;
      const e = (ri + 1) * spokes + ((si + 1) % spokes);
      // Alternate the diagonal so the triangles don't all lean the same way.
      if (ri % 2 === 0) index.push(a, b, d, b, e, d);
      else index.push(a, e, d, a, b, e);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setAttribute('tint', new THREE.Float32BufferAttribute(tints, 3));
  geo.setAttribute('emit', new THREE.Float32BufferAttribute(emits, 1));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  geo.setIndex(index);
  geo.computeVertexNormals();
  return new THREE.Mesh(geo, litMaterial());
}

// ---------------------------------------------------------------------------
// Props

const STONE = '#59635a';
const STONE_DARK = '#232823';

const weekStoneParts: Part[] = [
  { s: 'box', size: [0.56, 1.95, 0.34], taper: [0.72, 0.8], at: [0, 0.95, 0], c: STONE, c2: STONE_DARK, tile: 'stone' },
  // A chipped shoulder, so the top isn't a clean rectangle.
  { s: 'box', size: [0.3, 0.3, 0.3], taper: 0.5, at: [-0.08, 1.98, 0.0], rot: [0, 20, 8], c: STONE, tile: 'stone' },
  { s: 'box', size: [0.74, 0.16, 0.5], taper: 0.85, at: [0, 0.06, 0], c: STONE_DARK, tile: 'stone' },
];

const scatterParts: Part[] = [
  { s: 'ball', r: [0.2, 0.12, 0.16], seg: [6, 4], at: [-1.75, 0.05, -0.5], rot: [0, 30, 0], c: STONE, c2: STONE_DARK, tile: 'stone' },
  { s: 'ball', r: [0.1, 0.07, 0.09], seg: [5, 4], at: [-1.48, 0.03, -0.32], c: STONE, c2: STONE_DARK, tile: 'stone' },
  { s: 'ball', r: [0.26, 0.16, 0.2], seg: [6, 4], at: [2.05, 0.06, 0.1], rot: [0, -20, 0], c: STONE, c2: STONE_DARK, tile: 'stone' },
  { s: 'ball', r: [0.12, 0.08, 0.1], seg: [5, 4], at: [0.3, 0.03, -1.7], c: STONE, c2: STONE_DARK, tile: 'stone' },
  // The spoil heap beside the dig.
  { s: 'ball', r: [0.36, 0.17, 0.3], seg: [7, 4], at: [1.32, 0.04, 0.62], c: '#55452f', c2: '#2a2118', tile: 'soil' },
  { s: 'ball', r: [0.2, 0.1, 0.18], seg: [6, 4], at: [1.08, 0.03, 0.42], c: '#4b3d2a', c2: '#2a2118', tile: 'soil' },
];

function grassParts(): Part[] {
  const rng = makeRng(404);
  const parts: Part[] = [];
  const clumps: [number, number][] = [
    [-1.6, -0.25], [-2.3, 0.6], [1.75, -0.6], [2.4, 0.9], [0.55, -1.5], [-0.6, -1.9],
    [-1.3, 1.5], [1.9, 1.7], [1.42, -1.15], [-2.9, -1.4], [3.2, -1.8], [-0.2, 2.4],
  ];
  for (const [cx, cz] of clumps) {
    const blades = 3 + Math.floor(rng() * 3);
    for (let i = 0; i < blades; i++) {
      const h = 0.14 + rng() * 0.16;
      parts.push({
        s: 'cyl',
        r: [0, 0.018],
        h,
        sides: 3,
        at: [cx + (rng() - 0.5) * 0.16, h / 2, cz + (rng() - 0.5) * 0.16],
        rot: [(rng() - 0.5) * 34, rng() * 90, (rng() - 0.5) * 34],
        c: '#7d8a4c',
        c2: '#2c3a22',
      });
    }
  }
  return parts;
}

function treeParts(): Part[] {
  const bark = '#2b2620';
  const dark = '#14110e';
  return [
    { s: 'cyl', r: [0.1, 0.2], h: 1.5, sides: 6, at: [0, 0.75, 0], rot: [0, 0, 5], c: bark, c2: dark, tile: 'wood' },
    { s: 'cyl', r: [0.06, 0.1], h: 1.2, sides: 5, at: [-0.16, 2.0, 0], rot: [0, 0, 14], c: bark, c2: bark, tile: 'wood' },
    { s: 'cyl', r: [0.02, 0.06], h: 1.0, sides: 4, at: [-0.52, 2.86, 0], rot: [0, 0, 36], c: bark, c2: bark },
    { s: 'cyl', r: [0.02, 0.07], h: 1.1, sides: 4, at: [0.42, 1.78, 0.05], rot: [0, 0, -52], c: bark, c2: bark },
    { s: 'cyl', r: [0.012, 0.04], h: 0.7, sides: 4, at: [0.95, 2.36, 0.05], rot: [0, 0, -18], c: bark, c2: bark },
    { s: 'cyl', r: [0.012, 0.04], h: 0.6, sides: 4, at: [0.72, 1.74, 0.05], rot: [0, 0, -96], c: bark, c2: bark },
    { s: 'cyl', r: [0.012, 0.045], h: 0.8, sides: 4, at: [-0.46, 1.9, -0.05], rot: [0, 0, 64], c: bark, c2: bark },
    { s: 'cyl', r: [0.01, 0.03], h: 0.5, sides: 4, at: [-0.98, 2.2, -0.05], rot: [0, 0, 24], c: bark, c2: bark },
    { s: 'cyl', r: [0.01, 0.03], h: 0.55, sides: 4, at: [-0.2, 3.3, 0], rot: [0, 0, -12], c: bark, c2: bark },
  ];
}

/** A jagged strip of far-off hills and bare trees, seen only as a silhouette. */
function makeRidge(z: number, seed: number, baseHeight: number, color: string, spikiness: number): THREE.Mesh {
  const rng = makeRng(seed);
  const positions: number[] = [];
  const tints: number[] = [];
  const emits: number[] = [];
  const uvs: number[] = [];
  const index: number[] = [];
  const c = new THREE.Color(color);
  const width = 90;
  const steps = 60;
  let h = baseHeight;
  for (let i = 0; i <= steps; i++) {
    const x = (i / steps - 0.5) * width;
    h += (rng() - 0.5) * baseHeight * 0.42;
    h = THREE.MathUtils.clamp(h, baseHeight * 0.5, baseHeight * 1.5);
    // An occasional sharp spike reads as a distant peak or spire.
    const spike = rng() > 1 - spikiness ? baseHeight * (0.3 + rng() * 0.7) : 0;
    positions.push(x, -1, z, x, h + spike, z);
    for (let k = 0; k < 2; k++) {
      tints.push(c.r, c.g, c.b);
      emits.push(0);
      const [u, v] = tileUv(Tile.plain, 0.5, 0.5);
      uvs.push(u, v);
    }
    if (i < steps) {
      const a = i * 2;
      index.push(a, a + 2, a + 1, a + 1, a + 2, a + 3);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(positions.length).fill(0).map((_, i) => (i % 3 === 2 ? 1 : 0)), 3));
  geo.setAttribute('tint', new THREE.Float32BufferAttribute(tints, 3));
  geo.setAttribute('emit', new THREE.Float32BufferAttribute(emits, 1));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  geo.setIndex(index);
  return new THREE.Mesh(geo, litMaterial());
}

// ---------------------------------------------------------------------------
// Sky, stars and moon

function makeSky(): THREE.Mesh {
  const material = new THREE.ShaderMaterial({
    uniforms: {
      uTop: { value: SKY_TOP },
      uMid: { value: SKY_MID },
      uHorizon: { value: HORIZON },
    },
    vertexShader: /* glsl */ `
      varying vec3 vDir;
      void main() {
        vDir = normalize(position);
        vec4 p = projectionMatrix * viewMatrix * vec4(position + cameraPosition, 1.0);
        gl_Position = p.xyww;
      }
    `,
    fragmentShader: /* glsl */ `
      uniform vec3 uTop;
      uniform vec3 uMid;
      uniform vec3 uHorizon;
      varying vec3 vDir;
      void main() {
        float h = normalize(vDir).y;
        vec3 color = mix(uHorizon, uMid, smoothstep(0.0, 0.11, h));
        color = mix(color, uTop, smoothstep(0.08, 0.42, h));
        if (h < 0.0) color = uHorizon;
        gl_FragColor = vec4(color, 1.0);
      }
    `,
    side: THREE.BackSide,
    depthWrite: false,
    depthTest: false,
  });
  const mesh = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 12), material);
  mesh.frustumCulled = false;
  mesh.renderOrder = -10;
  return mesh;
}

function makeStars(): THREE.Points {
  const rng = makeRng(2024);
  const count = 150;
  const positions = new Float32Array(count * 3);
  const seeds = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    // Scattered over the half of the sky behind the hero.
    const az = Math.PI + (rng() - 0.5) * 2.2;
    const el = 0.07 + Math.pow(rng(), 1.5) * 0.75;
    positions[i * 3] = Math.sin(az) * Math.cos(el);
    positions[i * 3 + 1] = Math.sin(el);
    positions[i * 3 + 2] = Math.cos(az) * Math.cos(el);
    seeds[i] = rng();
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('seed', new THREE.BufferAttribute(seeds, 1));
  const material = new THREE.ShaderMaterial({
    uniforms: { uTime: world.uTime },
    vertexShader: /* glsl */ `
      attribute float seed;
      uniform float uTime;
      varying float vBright;
      void main() {
        float twinkle = 0.75 + 0.25 * sin(uTime * (0.6 + seed * 1.8) + seed * 40.0);
        vBright = (0.25 + seed * seed * 0.75) * twinkle;
        vec4 p = projectionMatrix * viewMatrix * vec4(position * 50.0 + cameraPosition, 1.0);
        gl_Position = p.xyww;
        gl_PointSize = seed > 0.93 ? 2.0 : 1.0;
      }
    `,
    fragmentShader: /* glsl */ `
      varying float vBright;
      void main() {
        gl_FragColor = vec4(vec3(0.82, 0.9, 0.86) * vBright, 1.0);
      }
    `,
    depthWrite: false,
    depthTest: false,
    blending: THREE.AdditiveBlending,
    // Not marked transparent on purpose: that keeps the stars in the first drawing
    // pass, after the sky and before the moon, so the moon covers the stars behind it.
    transparent: false,
  });
  const points = new THREE.Points(geo, material);
  points.frustumCulled = false;
  points.renderOrder = -9;
  return points;
}

export interface Moon {
  group: THREE.Group;
  /** 0 = new moon, 1 = full. */
  setPhase(phase: number): void;
}

function makeMoon(): Moon {
  const material = new THREE.ShaderMaterial({
    uniforms: {
      uPhase: { value: 0.6 },
      uLit: { value: new THREE.Color(0xe9e6c9) },
      uShadow: { value: new THREE.Color(0x1b2b2d) },
      uHaze: { value: HORIZON },
    },
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        vUv = uv * 2.0 - 1.0;
        vec4 center = viewMatrix * modelMatrix * vec4(0.0, 0.0, 0.0, 1.0);
        float size = length(modelMatrix[0].xyz);
        center.xy += position.xy * size;
        gl_Position = (projectionMatrix * center).xyww;
      }
    `,
    fragmentShader: /* glsl */ `
      uniform float uPhase;
      uniform vec3 uLit;
      uniform vec3 uShadow;
      uniform vec3 uHaze;
      varying vec2 vUv;

      float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      float blotch(vec2 p) {
        vec2 i = floor(p); vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
      }

      void main() {
        float r = length(vUv);
        if (r > 1.0) discard;
        // The line between day and night on a ball is half an ellipse.
        float edge = (1.0 - 2.0 * uPhase) * sqrt(max(0.0, 1.0 - vUv.y * vUv.y));
        float lit = step(edge, vUv.x);
        // Dark "seas" and a few craters.
        float seas = smoothstep(0.52, 0.7, blotch(vUv * 2.3 + 4.0)) * 0.26;
        seas += smoothstep(0.62, 0.72, blotch(vUv * 5.5 + 9.0)) * 0.12;
        vec3 color = mix(uShadow, uLit * (1.0 - seas), lit);
        // Slight darkening toward the rim makes it read as a ball, not a disc.
        color *= mix(1.0, 0.72, smoothstep(0.55, 1.0, r) * lit);
        // Low in the sky the moon picks up haze.
        color = mix(color, uHaze, smoothstep(0.2, -1.0, vUv.y) * 0.3);
        gl_FragColor = vec4(color, 1.0);
      }
    `,
    depthWrite: false,
    depthTest: false,
  });
  const disc = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), material);
  disc.frustumCulled = false;
  disc.renderOrder = -8;

  const halo = makeGlow(0x6f9a94, 5.2, 0.5);
  halo.material.depthTest = false;
  halo.material.transparent = false; // same trick as the stars: draw before the scene
  halo.renderOrder = -8.5;

  const group = new THREE.Group();
  group.add(halo, disc);
  return {
    group,
    setPhase(phase: number) {
      material.uniforms.uPhase.value = phase;
      halo.material.uniforms.uStrength.value = 0.12 + phase * 0.42;
    },
  };
}

// ---------------------------------------------------------------------------
// Runes

/** Seven carved marks, one per weekday, each drawn on an 8 x 8 grid. */
const RUNE_ROWS = [
  '...XX......XX...XX....XX.XX......XX.....XX.XX.XX..XXXX..',
  '..XXXX....XXXX...XX..XX..XXXX....XX.....XX.XX.XX.XX..XX.',
  '.XXXXXX..XX..XX...XXXX...XX.XX...XX..XX..XXXXXX.XX....XX',
  '...XX...XX....XX...XX....XX..XX..XXX.XX...XXXX..XX.XX.XX',
  '...XX...XX....XX...XX....XX.XX...XX.XXX....XX...XX.XX.XX',
  '...XX....XX..XX...XXXX...XXXX....XX..XX....XX...XX....XX',
  '...XX.....XXXX...XX..XX..XX..........XX....XX....XX..XX.',
  '...XX......XX...XX....XX.XX..........XX....XX.....XXXX..',
];

export interface WeekStone {
  group: THREE.Group;
  /** `done[i]` lights rune i (0 = Monday). `today` gets a gentle pulse until it is done. */
  setWeek(done: boolean[], today: number): void;
  update(time: number): void;
}

function makeWeekStone(): WeekStone {
  const group = new THREE.Group();
  group.position.copy(STONE_POS);
  group.rotation.set(0, -0.3, -0.045);
  group.add(buildMesh(weekStoneParts));

  const texture = pixelTexture(RUNE_ROWS, { X: [255, 255, 255, 255] });
  const quad = new THREE.PlaneGeometry(0.2, 0.2);
  const runes: { material: THREE.ShaderMaterial; glow: GlowSprite; on: boolean; today: boolean }[] = [];
  const carved = new THREE.Color(0x121512);
  const lit = new THREE.Color(0x9ff5d6);
  const waiting = new THREE.Color(0xd9a94e);

  for (let i = 0; i < 7; i++) {
    // Monday at the bottom, Sunday at the top.
    const y = 0.3 + i * 0.235;
    const material = makeDecalMaterial(texture, carved, true);
    material.uniforms.uUvScale.value.set(1 / 7, 1);
    material.uniforms.uUvOffset.value.set(i / 7, 0);
    const mesh = new THREE.Mesh(quad, material);
    // The stone narrows toward the top, so the face leans back slightly.
    const depth = 0.172 - (y / 1.95) * 0.036;
    mesh.position.set(0, y, depth);
    mesh.rotation.x = -0.018;
    group.add(mesh);

    const glow = makeGlow(0x5fd9b4, 0.62, 0);
    glow.position.set(0, y, depth + 0.02);
    group.add(glow);
    runes.push({ material, glow, on: false, today: false });
  }

  return {
    group,
    setWeek(done, today) {
      runes.forEach((rune, i) => {
        rune.on = !!done[i];
        rune.today = i === today;
      });
    },
    update(time) {
      runes.forEach((rune, i) => {
        const color = rune.material.uniforms.uColor.value as THREE.Color;
        if (rune.on) {
          const pulse = 0.88 + Math.sin(time * 1.6 + i) * 0.12;
          color.copy(lit).multiplyScalar(pulse);
          rune.glow.material.uniforms.uStrength.value = 0.4 * pulse;
        } else if (rune.today) {
          const pulse = 0.45 + Math.sin(time * 2.4) * 0.25;
          color.copy(carved).lerp(waiting, pulse);
          rune.glow.material.uniforms.uStrength.value = 0;
        } else {
          color.copy(carved);
          rune.glow.material.uniforms.uStrength.value = 0;
        }
      });
    },
  };
}

// ---------------------------------------------------------------------------
// Lantern

export interface Lantern {
  group: THREE.Group;
  /** `level` 0..1 is how full the flame is; `color` is the light it throws. */
  setFlame(level: number, color: THREE.Color): void;
  update(time: number): void;
  /** A short flare, played when a quest is completed. */
  flare(time: number): void;
}

function makeLantern(): Lantern {
  const group = new THREE.Group();
  group.position.copy(LANTERN_POS);
  group.rotation.y = 0.5;
  const iron = '#3a3d3c';
  group.add(
    buildMesh([
      { s: 'cyl', r: [0.085, 0.095], h: 0.035, sides: 6, at: [0, 0.018, 0], c: iron, tile: 'metal' },
      { s: 'box', size: [0.014, 0.2, 0.014], at: [-0.062, 0.135, -0.062], c: iron },
      { s: 'box', size: [0.014, 0.2, 0.014], at: [0.062, 0.135, -0.062], c: iron },
      { s: 'box', size: [0.014, 0.2, 0.014], at: [-0.062, 0.135, 0.062], c: iron },
      { s: 'box', size: [0.014, 0.2, 0.014], at: [0.062, 0.135, 0.062], c: iron },
      { s: 'cyl', r: [0.03, 0.105], h: 0.075, sides: 6, at: [0, 0.272, 0], c: iron, tile: 'metal' },
      { s: 'cyl', r: 0.045, h: 0.012, sides: 6, at: [0, 0.345, 0], rot: [90, 0, 0], c: iron },
    ]),
  );

  // The flame is its own mesh so its size and colour can change.
  const flameMaterial = new THREE.MeshBasicMaterial({ color: 0xffd98a });
  const flame = new THREE.Mesh(new THREE.SphereGeometry(1, 6, 5), flameMaterial);
  flame.position.set(0, 0.11, 0);
  group.add(flame);

  const glow = makeGlow(0xf2a23c, 1.5, 0.5);
  glow.position.set(0, 0.14, 0);
  group.add(glow);

  const WARM = new THREE.Color(1.0, 0.64, 0.3);
  let level = 0;
  let flareAt = -10;
  const lightColor = new THREE.Color(1, 0.6, 0.22);

  return {
    group,
    setFlame(next, color) {
      level = next;
      lightColor.copy(color);
    },
    flare(time) {
      flareAt = time;
    },
    update(time) {
      // Two sine waves at different speeds make a flicker that never quite repeats.
      const flicker = 1 + Math.sin(time * 11.3) * 0.05 + Math.sin(time * 6.7 + 1.3) * 0.06;
      const flare = Math.max(0, 1 - (time - flareAt) / 0.9);
      const power = (0.32 + level * 0.68) * flicker + flare * 0.7;

      const height = 0.022 + level * 0.05 + flare * 0.03;
      flame.scale.set(0.02 + level * 0.016, height * flicker, 0.02 + level * 0.016);
      flame.position.y = 0.075 + height;
      flameMaterial.color.copy(lightColor).lerp(new THREE.Color(1, 1, 0.9), 0.55);

      glow.material.uniforms.uColor.value.copy(lightColor);
      glow.material.uniforms.uStrength.value = 0.25 + power * 0.42;
      glow.material.uniforms.uSize.value = 0.9 + power * 1.1;

      world.uLampPos.value.set(LANTERN_POS.x, 0.34, LANTERN_POS.z);
      // The flame shows the streak colour at full strength, but the light it throws on the
      // scene stays mostly warm. Fully green light would make the hero look like a goblin.
      world.uLampColor.value.copy(WARM).lerp(lightColor, 0.3).multiplyScalar(0.5 + power * 1.25);
      world.uLampRange.value = 3.6 + power * 2.2;
    },
  };
}

// ---------------------------------------------------------------------------
// Fireflies

function makeMotes(): THREE.Points {
  const rng = makeRng(31);
  const count = 26;
  const positions = new Float32Array(count * 3);
  const seeds = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    positions[i * 3] = (rng() - 0.5) * 6.5;
    positions[i * 3 + 1] = 0.2 + rng() * 2.4;
    positions[i * 3 + 2] = (rng() - 0.5) * 5 - 0.5;
    seeds[i] = rng();
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('seed', new THREE.BufferAttribute(seeds, 1));
  const material = new THREE.ShaderMaterial({
    uniforms: { uTime: world.uTime },
    vertexShader: /* glsl */ `
      attribute float seed;
      uniform float uTime;
      varying float vBright;
      void main() {
        vec3 p = position;
        float t = uTime * (0.25 + seed * 0.35) + seed * 30.0;
        p.x += sin(t * 1.3) * 0.35;
        p.y += sin(t * 0.9 + seed * 6.0) * 0.25;
        p.z += cos(t * 1.1) * 0.3;
        vBright = smoothstep(0.2, 0.9, sin(t * 2.2) * 0.5 + 0.5);
        gl_Position = projectionMatrix * viewMatrix * vec4(p, 1.0);
        gl_PointSize = 1.0;
      }
    `,
    fragmentShader: /* glsl */ `
      varying float vBright;
      void main() {
        gl_FragColor = vec4(vec3(0.85, 0.95, 0.5) * vBright, 1.0);
      }
    `,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    transparent: true,
  });
  const points = new THREE.Points(geo, material);
  points.frustumCulled = false;
  return points;
}

// ---------------------------------------------------------------------------

export interface Scenery {
  group: THREE.Group;
  moon: Moon;
  weekStone: WeekStone;
  lantern: Lantern;
}

export function makeScenery(): Scenery {
  const group = new THREE.Group();
  group.add(makeSky(), makeStars());

  const moon = makeMoon();
  // Far away and large, so it barely shifts as the camera moves.
  moon.group.position.set(2.35, 3.8, -40);
  moon.group.scale.setScalar(2.7);
  group.add(moon.group);

  group.add(makeRidge(-34, 9, 3.0, '#16262a', 0.16), makeRidge(-17, 5, 1.15, '#0e1a1c', 0.05));
  group.add(makeGround());
  group.add(buildMesh(scatterParts), buildMesh(grassParts()));

  const tree = buildMesh(treeParts());
  tree.position.set(-1.72, 0, -3.6);
  tree.rotation.y = 0.3;
  tree.scale.setScalar(1.05);
  group.add(tree);

  const weekStone = makeWeekStone();
  group.add(weekStone.group);

  const lantern = makeLantern();
  group.add(lantern.group);

  group.add(makeMotes());
  return { group, moon, weekStone, lantern };
}
