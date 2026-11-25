import * as THREE from 'three';
import { buildMesh, mirrored, type Part } from './parts';
import { makeGlow, world, type GlowSprite } from './RetroMaterial';
import { getAtlas } from './textures';
import {
  FACE2,
  HERO2_COLORS,
  HAT2_SCALE,
  HERO2_JOINTS,
  LIMBS2,
  cloakParts2,
  forearmParts2,
  hairParts2,
  headFrontZ,
  headParts2,
  hoodUpParts2,
  shinParts2,
  tailParts2,
  thighParts2,
  torsoParts2,
  upperArmParts2,
} from './models/heroV2';
import { FACE2_FRAME, FACE2_FRAMES, FACE2_H, FACE2_W, paintFace2 } from './models/face2';
import { HERO_COLORS, type HeroPalette } from './models/hero';
import { ITEM_MODELS, type ItemModel } from './models/items';
import type { Gear, HeroLook } from './hero';

// The new hero: the Spade digger with grown-up proportions, a painted face and the
// hooded cloak from the logo. Two ways to draw it:
//   soft  the app's own lighting, shading each shape darker toward its foot
//   cel   flat colours split into lit and shadowed bands, a bright rim where the
//         moon catches an edge, and an ink outline, like a hand-painted cartoon
// Between actions the hero drifts through small, unposed "moments" (glancing round,
// shading the eyes to look at the moon, a fist in the air after a quest), so it
// feels alive rather than waiting to be tapped.

const DEG = Math.PI / 180;
const DOWN = new THREE.Vector3(0, -1, 0);

/**
 * The new hero is drawn a little smaller than life, so it stands only a touch taller
 * than the original and every camera shot still frames it.
 */
export const HERO2_FIT = 0.92;
/** Shields were made for the original's bigger arm. */
export const SHIELD2_SCALE = 0.82;

export type HeroStyle = 'soft' | 'cel';
export type Moment = 'stand' | 'glance' | 'sky' | 'cheer';

// ---- Shading -----------------------------------------------------------------

const heroVertex = /* glsl */ `
attribute vec3 tint;
attribute float emit;
uniform float uFogNear;
uniform float uFogFar;
varying vec3 vTint;
varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vWorld;
varying float vFog;
varying float vEmit;
void main() {
  vTint = tint;
  vUv = uv;
  vEmit = emit;
  vec4 worldPos = modelMatrix * vec4(position, 1.0);
  vWorld = worldPos.xyz;
  vNormal = normalize(mat3(modelMatrix) * normal);
  vec4 viewPos = viewMatrix * worldPos;
  vFog = clamp((-viewPos.z - uFogNear) / (uFogFar - uFogNear), 0.0, 1.0);
  gl_Position = projectionMatrix * viewPos;
}
`;

/**
 * The scene's light at a point (the same recipe as the rest of the scene), plus a soft
 * fill of the hero's own from the viewer's side, the way game characters are often lit
 * a little apart from their world so a face never sinks into the night. And a banded
 * version of the light, for cel shading.
 */
const LIGHT_GLSL = /* glsl */ `
uniform vec3 uAmbient;
uniform vec3 uMoonDir;
uniform vec3 uMoonColor;
uniform vec3 uLampPos;
uniform vec3 uLampColor;
uniform float uLampRange;
uniform vec3 uGlowPos;
uniform vec3 uGlowColor;
uniform float uGlowRange;
uniform vec3 uFill;
vec3 pointLight(vec3 p, vec3 n, vec3 lightPos, vec3 color, float range) {
  vec3 toLight = lightPos - p;
  float dist = length(toLight);
  float fade = clamp(1.0 - dist / range, 0.0, 1.0);
  return color * fade * fade * (max(dot(n, toLight / max(dist, 0.001)), 0.0) * 0.8 + 0.2);
}
vec3 sceneLight(vec3 n, vec3 p) {
  vec3 light = uAmbient * (0.75 + 0.45 * (n.y * 0.5 + 0.5));
  light += uMoonColor * max(dot(n, uMoonDir), 0.0);
  light += pointLight(p, n, uLampPos, uLampColor, uLampRange);
  light += pointLight(p, n, uGlowPos, uGlowColor, uGlowRange);
  light += uFill * (max(dot(n, normalize(cameraPosition - p)), 0.0) * 0.6 + 0.4);
  return light;
}
// Cel bands: brightness snaps to steps of about two thirds of a stop, with a soft edge
// between steps. Working in stops keeps the scene's mood: a dark corner stays dark,
// just in flat bands instead of a smooth fade.
vec3 celLight(vec3 light, float soften) {
  float lum = max(dot(light, vec3(0.3, 0.59, 0.11)), 1e-4);
  float k = log2(lum) * 1.5;
  float stepped = exp2((floor(k) + smoothstep(0.42, 0.58, fract(k))) / 1.5);
  return mix(light * (stepped / lum), light, soften);
}
`;

const heroFragment = /* glsl */ `
uniform sampler2D uAtlas;
uniform vec3 uFogColor;
uniform float uFloor;
uniform float uCel;
varying vec3 vTint;
varying vec2 vUv;
varying vec3 vNormal;
varying vec3 vWorld;
varying float vFog;
varying float vEmit;
${LIGHT_GLSL}
void main() {
  vec3 n = normalize(vNormal);
  vec3 tex = texture2D(uAtlas, vUv).rgb * 1.25;
  vec3 light = sceneLight(n, vWorld);
  vec3 base;
  vec3 color;
  if (uCel > 0.5) {
    // A whisper of the cloth and leather texture, so flat colours aren't plastic.
    base = vTint * mix(vec3(1.0), tex, 0.35) * 1.15;
    // Skin keeps softer bands: a hard line across a face reads as a bruise, not a shadow.
    light = celLight(light, uFloor);
    // A thin bright rim where the moon grazes an edge.
    vec3 view = normalize(cameraPosition - vWorld);
    float rim = smoothstep(0.66, 0.72, 1.0 - max(dot(n, view), 0.0)) * smoothstep(-0.1, 0.3, dot(n, uMoonDir));
    color = base * light + rim * uMoonColor * 0.22;
  } else {
    base = vTint * tex;
    color = base * light;
  }
  color = mix(color, base, vEmit);
  color = mix(color, uFogColor, vFog * (1.0 - vEmit * 0.5));
  gl_FragColor = vec4(color, 1.0);
}
`;

/** The hero's own fill light. One value shared by every hero material. */
export const HERO2_FILL = new THREE.Color(0.15, 0.135, 0.12);
const fill = { value: HERO2_FILL };

const heroShared = new Map<string, THREE.ShaderMaterial>();
/** `floor` lifts the shadow band in cel shading: 0 for clothes, more for skin on the face. */
function heroMaterial(cel: boolean, floor = 0): THREE.ShaderMaterial {
  const key = `${cel}:${floor}`;
  let mat = heroShared.get(key);
  if (!mat) {
    world.uAtlas.value = getAtlas();
    mat = new THREE.ShaderMaterial({
      uniforms: { ...world, uFill: fill, uFloor: { value: floor }, uCel: { value: cel ? 1 : 0 } },
      vertexShader: heroVertex,
      fragmentShader: heroFragment,
    });
    heroShared.set(key, mat);
  }
  return mat;
}

let outlineShared: THREE.ShaderMaterial | null = null;
/** The ink line: the same shape again, a hair bigger, inside out and dark. */
function outlineMaterial(): THREE.ShaderMaterial {
  if (!outlineShared) {
    outlineShared = new THREE.ShaderMaterial({
      uniforms: { uWidth: { value: 0.00055 }, uColor: { value: new THREE.Color(0x1a120d) } },
      vertexShader: /* glsl */ `
        uniform float uWidth;
        void main() {
          vec4 viewPos = modelViewMatrix * vec4(position, 1.0);
          vec3 n = normalize(normalMatrix * normal);
          viewPos.xyz += n * uWidth * max(1.0, -viewPos.z);
          gl_Position = projectionMatrix * viewPos;
        }`,
      fragmentShader: /* glsl */ `
        uniform vec3 uColor;
        void main() { gl_FragColor = vec4(uColor, 1.0); }`,
      side: THREE.BackSide,
    });
  }
  return outlineShared;
}

// ---- The painted face --------------------------------------------------------

let faceTexture: THREE.DataTexture | null = null;
function getFaceTexture(): THREE.DataTexture {
  if (faceTexture) return faceTexture;
  const top = paintFace2();
  const w = FACE2_W;
  const h = FACE2_H * FACE2_FRAMES;
  const data = new Uint8Array(w * h * 4);
  // Textures start at the bottom row.
  for (let y = 0; y < h; y++) data.set(top.subarray((h - 1 - y) * w * 4, (h - y) * w * 4), y * w * 4);
  faceTexture = new THREE.DataTexture(data, w, h, THREE.RGBAFormat);
  faceTexture.magFilter = THREE.LinearFilter;
  faceTexture.minFilter = THREE.LinearFilter;
  faceTexture.generateMipmaps = false;
  faceTexture.needsUpdate = true;
  return faceTexture;
}

function faceMaterial(): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    uniforms: {
      ...world,
      uFill: fill,
      uMap: { value: getFaceTexture() },
      uFrame: { value: 0 },
      uCel: { value: 0 },
    },
    vertexShader: /* glsl */ `
      uniform float uFrame;
      uniform float uFogNear;
      uniform float uFogFar;
      varying vec2 vUv;
      varying float vFog;
      varying vec3 vNormal;
      varying vec3 vWorld;
      void main() {
        float frames = ${FACE2_FRAMES.toFixed(1)};
        vUv = vec2(uv.x, (uv.y + (frames - 1.0 - uFrame)) / frames);
        // The patch hugs the head, so its normal points out from the middle of the head.
        vNormal = normalize(mat3(modelMatrix) * normalize(position - vec3(0.0, 0.17, -0.02)));
        vec4 worldPos = modelMatrix * vec4(position, 1.0);
        vWorld = worldPos.xyz;
        vec4 viewPos = viewMatrix * worldPos;
        vFog = clamp((-viewPos.z - uFogNear) / (uFogFar - uFogNear), 0.0, 1.0);
        gl_Position = projectionMatrix * viewPos;
      }`,
    fragmentShader: /* glsl */ `
      uniform sampler2D uMap;
      uniform float uCel;
      uniform vec3 uFogColor;
      varying vec2 vUv;
      varying float vFog;
      varying vec3 vNormal;
      varying vec3 vWorld;
      ${LIGHT_GLSL}
      void main() {
        vec4 texel = texture2D(uMap, vUv);
        if (texel.a < 0.02) discard;
        vec3 light = sceneLight(normalize(vNormal), vWorld);
        if (uCel > 0.5) light = celLight(light, 0.55);
        vec3 color = texel.rgb * light * 1.15;
        // The whites of the eyes and their catchlights keep a little light of their own,
        // so the eyes still read at phone size, at night, in chunky pixels.
        float bright = smoothstep(0.55, 0.9, dot(texel.rgb, vec3(0.3, 0.59, 0.11)));
        color += texel.rgb * bright * 0.17;
        color = mix(color, uFogColor, vFog * 0.6);
        gl_FragColor = vec4(color, texel.a);
      }`,
    transparent: true,
    depthWrite: false,
    polygonOffset: true,
    polygonOffsetFactor: -2,
    polygonOffsetUnits: -2,
  });
}

/** The patch the face is painted on: a grid that hugs the front of the head. */
export function faceGeometry(): THREE.BufferGeometry {
  const cols = 14;
  const rows = 12;
  const positions: number[] = [];
  const uvs: number[] = [];
  const index: number[] = [];
  for (let j = 0; j <= rows; j++) {
    for (let i = 0; i <= cols; i++) {
      const u = i / cols;
      const v = j / rows;
      const x = (u - 0.5) * FACE2.width;
      const y = FACE2.centerY + (v - 0.5) * FACE2.height;
      positions.push(x, y, headFrontZ(x, y) + 0.0015);
      uvs.push(u, v);
    }
  }
  for (let j = 0; j < rows; j++) {
    for (let i = 0; i < cols; i++) {
      const a = j * (cols + 1) + i;
      index.push(a, a + 1, a + cols + 2, a, a + cols + 2, a + cols + 1);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  geo.setIndex(index);
  return geo;
}

/** A hat as the new hero wears it: round caps keep only their crowns. */
export function hatParts2(hat: Extract<ItemModel, { slot: 'head' }>): Part[] {
  return hat.parts.map((part) => (part.s === 'ball' && hat.hair === 'under' ? { ...part, top: true } : part));
}

// ---- Reaching: point an arm so the palm lands on a spot -----------------------

const tmpA = new THREE.Vector3();
const tmpB = new THREE.Vector3();
const tmpQ = new THREE.Quaternion();

/** Two-bone reach: turns the shoulder and elbow so the palm lands on `target` (in the shoulder's parent's space). */
function reach(root: THREE.Object3D, mid: THREE.Object3D, target: THREE.Vector3, pole: THREE.Vector3, a: number, b: number) {
  const toTarget = tmpA.copy(target).sub(root.position);
  const d = THREE.MathUtils.clamp(toTarget.length(), Math.abs(a - b) + 1e-3, a + b - 1e-3);
  const dir = toTarget.normalize();
  const bendAt = Math.acos(THREE.MathUtils.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1));
  const axis = tmpB.crossVectors(dir, pole).normalize();
  const upper = dir.clone().applyAxisAngle(axis, bendAt);
  const elbow = root.position.clone().addScaledVector(upper, a);
  const lower = target.clone().sub(elbow).normalize();
  root.quaternion.setFromUnitVectors(DOWN, upper);
  const local = lower.applyQuaternion(tmpQ.copy(root.quaternion).invert());
  mid.quaternion.setFromUnitVectors(DOWN, local);
}

// ---- The rig ------------------------------------------------------------------

export class HeroV2 {
  readonly root = new THREE.Group();
  readonly joints: Record<string, THREE.Group> = {};
  readonly charmPivot = new THREE.Group();

  private built: THREE.Object3D[] = [];
  private readonly face: THREE.ShaderMaterial;
  private charmGlow: GlowSprite | null = null;
  private hasCharm = false;
  private hasTool = false;
  private hasShield = false;

  private blinkAt = 2;
  private blinkUntil = 0;
  private hopStart = -10;
  private lookAt = 6;
  private lookTarget = 0;
  private headYaw = 0;

  /** For still pictures: no breathing, swaying or blinking, and `moment` is held. */
  still = false;
  moment: Moment = 'stand';
  /** The cloak's hood: up, framing the face as in the logo, or down on the shoulders. A hat always puts it down. */
  hood: 'up' | 'down' = 'up';

  // The moment being played live, and when the next one starts.
  private live: Moment = 'stand';
  private liveUntil = 0;
  private nextMoment = 16;
  private last = 0;
  // Where the hands are heading, eased so a change of moment is a movement, not a jump.
  private snap = true;
  private readonly rightAt = new THREE.Vector3();
  private readonly rightPole = new THREE.Vector3();
  private readonly leftAt = new THREE.Vector3();
  private readonly leftPole = new THREE.Vector3();
  private pitch = 0;

  constructor() {
    for (const spec of HERO2_JOINTS) {
      const group = new THREE.Group();
      group.name = spec.name;
      group.position.set(...spec.at);
      if (spec.rot) group.rotation.set(spec.rot[0] * DEG, spec.rot[1] * DEG, spec.rot[2] * DEG, 'ZYX');
      else group.rotation.order = 'ZYX';
      this.joints[spec.name] = group;
      (spec.parent ? this.joints[spec.parent] : this.root).add(group);
    }
    this.root.scale.setScalar(HERO2_FIT);
    this.joints.hat.scale.setScalar(HAT2_SCALE);
    this.joints.shield.scale.setScalar(SHIELD2_SCALE);
    this.root.add(this.charmPivot);
    this.face = faceMaterial();
    const faceMesh = new THREE.Mesh(faceGeometry(), this.face);
    faceMesh.renderOrder = 2;
    this.joints.head.add(faceMesh);
  }

  private style: HeroStyle = 'soft';

  private attach(joint: string, parts: Part[], opts: { outline?: boolean; floor?: number } = {}) {
    if (parts.length === 0) return;
    const cel = this.style === 'cel';
    // Cel shading paints each shape in one flat colour; the light does the rest.
    const list = cel ? parts.map((p) => ({ ...p, c2: p.c2 ?? p.c })) : parts;
    const mesh = buildMesh(list, heroMaterial(cel, opts.floor ?? 0));
    if (cel && opts.outline !== false) mesh.add(new THREE.Mesh(mesh.geometry, outlineMaterial()));
    this.joints[joint].add(mesh);
    this.built.push(mesh);
  }

  apply(look: HeroLook, gear: Gear, style: HeroStyle = this.style) {
    this.style = style;
    if (look.hoodDown !== undefined) this.hood = look.hoodDown ? 'down' : 'up';
    this.snap = true;
    this.face.uniforms.uCel.value = style === 'cel' ? 1 : 0;
    for (const obj of this.built) {
      obj.removeFromParent();
      (obj as THREE.Mesh).geometry?.dispose();
    }
    this.built = [];
    this.charmPivot.clear();
    this.charmGlow = null;

    const model = (id: string | undefined, slot: ItemModel['slot']) => {
      const found = id ? ITEM_MODELS[id] : undefined;
      return found && found.slot === slot ? found : undefined;
    };
    const body = model(gear.body, 'body') as Extract<ItemModel, { slot: 'body' }> | undefined;
    const hat = model(gear.head, 'head') as Extract<ItemModel, { slot: 'head' }> | undefined;
    const tool = model(gear.hand, 'hand') as Extract<ItemModel, { slot: 'hand' }> | undefined;
    const shield = model(gear.shield, 'shield') as Extract<ItemModel, { slot: 'shield' }> | undefined;
    const charm = model(gear.charm, 'charm') as Extract<ItemModel, { slot: 'charm' }> | undefined;

    const palette: HeroPalette = {
      skin: look.skin,
      hair: look.hair,
      scarf: look.scarf,
      tunic: body?.tunic ?? HERO_COLORS.tunic,
      sleeve: body?.sleeve ?? HERO_COLORS.sleeve,
    };

    this.attach('torso', torsoParts2(palette));
    // A hat puts the hood down; a hat that is itself a hood replaces it.
    const hood = !hat ? this.hood : hat.hair === 'hide' ? 'none' : 'down';
    this.attach('torso', cloakParts2(body?.cloak ?? HERO2_COLORS.cloak, hood === 'down'));
    if (hood === 'up') this.attach('head', hoodUpParts2(body?.cloak ?? HERO2_COLORS.cloak));
    // One sleeve down, one rolled up: a small asymmetry that makes the outfit look worn, not issued.
    this.attach('armR', upperArmParts2(palette, false));
    this.attach('elbowR', forearmParts2(palette, false));
    this.attach('armL', mirrored(upperArmParts2(palette, true)));
    this.attach('elbowL', mirrored(forearmParts2(palette, true)));
    this.attach('legR', thighParts2());
    this.attach('kneeR', shinParts2(true));
    this.attach('legL', thighParts2());
    this.attach('kneeL', shinParts2(false));
    const [tail1, tail2] = tailParts2(palette);
    this.attach('tail1', tail1);
    this.attach('tail2', tail2);

    const hair = hairParts2(look.hairStyle, look.hair);
    const hairMode = hat?.hair ?? 'keep';
    // The head's outline goes round the whole shape; the nose and ears get none, so they
    // read as part of the face instead of as stuck-on pieces.
    const [shell, skull, ...features] = headParts2(palette);
    this.attach('head', [shell, skull], { floor: 0.55 });
    this.attach('head', features, { outline: false, floor: 0.55 });
    this.attach('head', hood === 'up' ? hair.hooded : hairMode === 'hide' ? [] : hairMode === 'keep' ? hair.top : hair.under);
    // Round caps keep only their crowns: the lower half, hidden inside the original's big
    // head, would bulge out beside this slimmer face.
    if (hat) this.attach('hat', hatParts2(hat));
    if (tool) this.attach('tool', tool.parts);
    if (shield) this.attach('shield', shield.parts);
    this.hasTool = !!tool;
    this.hasShield = !!shield;

    this.hasCharm = !!charm;
    if (charm) {
      const mesh = buildMesh(charm.parts, heroMaterial(style === 'cel'));
      mesh.scale.setScalar(0.85);
      this.charmPivot.add(mesh);
      if (charm.glow) {
        this.charmGlow = makeGlow(charm.glow, 0.5, 0.55);
        this.charmPivot.add(this.charmGlow);
      }
    }
    this.update(0);
  }

  cheer(time: number) {
    this.hopStart = time;
  }

  /** The starting look, for before the player's own has arrived. */
  defaultLook(): HeroLook {
    return { skin: '#e0ac82', hair: '#4a3020', hairStyle: 'crop', scarf: '#b5472f' };
  }

  /** The relaxed stance: weight on the right leg, the left knee soft, shoulders and hips tilted against each other. */
  private pose(time: number, breathe: number, lift: number, m: Moment, ease: number) {
    const j = this.joints;
    const shift = this.still ? 0 : Math.sin(time * 0.45) * 0.6;
    j.hips.rotation.set(0, 0, (-2.5 + shift) * DEG, 'ZYX');
    j.torso.rotation.set(breathe * 0.004, -4 * DEG, (4 - shift * 1.2) * DEG, 'ZYX');
    j.legR.rotation.set(0, -4 * DEG, (2.5 - shift) * DEG, 'ZYX');
    j.kneeR.rotation.set(0, 0, 0, 'ZYX');
    j.legL.rotation.set(-9 * DEG, 14 * DEG, (-3 - shift) * DEG, 'ZYX');
    j.kneeL.rotation.set(16 * DEG, 0, 0, 'ZYX');

    const k = this.snap ? 1 : ease;
    const headPitch = m === 'sky' ? -24 : m === 'cheer' ? -8 : 0;
    this.pitch += (headPitch - this.pitch) * k;
    const headTilt = m === 'glance' ? 6 : -4;
    const yaw = m === 'glance' && this.still ? 0.55 : this.headYaw;
    j.head.rotation.set(this.pitch * DEG + breathe * 0.01 - lift * 0.4, yaw, headTilt * DEG, 'ZYX');

    // Arms reach for a spot in the torso's own space.
    j.torso.updateMatrixWorld(true);
    const a = LIMBS2.upperArm;
    const b = LIMBS2.forearm;
    const right = new THREE.Vector3();
    const rightPole = new THREE.Vector3(-0.4, 0, -1);
    if (this.hasTool) {
      // Hold the spade by its grip.
      const grip = j.tool.localToWorld(new THREE.Vector3(0, 0.95, 0));
      right.copy(j.torso.worldToLocal(grip));
      rightPole.set(-0.8, 0, -0.5);
    } else if (m === 'cheer') {
      right.set(-0.26, 0.98, 0.08);
      rightPole.set(-1, 0, 0.3);
    } else {
      right.set(-0.205, -0.02 + breathe * 0.004, 0.035);
    }
    // The grip moves with the spade, so that hand follows it exactly.
    const kr = this.hasTool ? 1 : k;
    this.rightAt.lerp(right, kr);
    this.rightPole.lerp(rightPole, kr);
    reach(j.armR, j.elbowR, this.rightAt, this.rightPole, a, b);

    if (this.hasShield) {
      j.armL.rotation.set(-30 * DEG, 0, 16 * DEG, 'ZYX');
      j.elbowL.rotation.set(-40 * DEG, 0, 0, 'ZYX');
      return;
    }
    const left = new THREE.Vector3();
    const leftPole = new THREE.Vector3();
    if (m === 'sky') {
      // Shading the eyes to look up at the moon.
      left.set(0.02, 0.875, 0.15);
      leftPole.set(1, 0.2, 0.1);
    } else {
      // Hand resting on the hip, elbow out and back.
      left.set(0.172, 0.085 + breathe * 0.003, 0.06);
      leftPole.set(0.55, 0, -0.85);
    }
    this.leftAt.lerp(left, k);
    this.leftPole.lerp(leftPole, k);
    reach(j.armL, j.elbowL, this.leftAt, this.leftPole, a, b);
  }

  /** Which moment to play now. Now and then the hero looks up at the moon; after a quest, a fist goes up. */
  private momentAt(time: number): Moment {
    if (this.still) return this.moment;
    if (time - this.hopStart >= 0 && time - this.hopStart < 1.4) return 'cheer';
    if (time < this.liveUntil) return this.live;
    if (time > this.nextMoment) {
      this.live = this.hasShield ? 'glance' : 'sky';
      this.liveUntil = time + 3.2 + Math.random() * 1.6;
      this.nextMoment = this.liveUntil + 18 + Math.random() * 20;
      return this.live;
    }
    return 'stand';
  }

  update(time: number) {
    const j = this.joints;
    const breathe = this.still ? 0 : Math.sin(time * 1.9);
    const hop = time - this.hopStart;
    let lift = this.still && this.moment === 'cheer' ? 0.06 : 0;
    let squash = 0;
    if (hop >= 0 && hop < 0.62) {
      const t = hop / 0.62;
      lift = Math.sin(t * Math.PI) * 0.26;
      squash = t < 0.12 ? -Math.sin((t / 0.12) * Math.PI) * 0.08 : t > 0.9 ? -Math.sin(((t - 0.9) / 0.1) * Math.PI) * 0.06 : 0.04;
    }
    j.hips.position.y = 0.79 + lift + breathe * 0.004;
    j.torso.scale.set(1 - squash * 0.5, 1 + squash + breathe * 0.008, 1 - squash * 0.5);

    // Now and then the hero glances to one side. The eyes get there first.
    if (!this.still && time > this.lookAt) {
      this.lookTarget = this.lookTarget === 0 ? (Math.random() < 0.5 ? -0.5 : 0.42) : 0;
      this.lookAt = time + (this.lookTarget === 0 ? 4 + Math.random() * 5 : 1.2 + Math.random() * 1.4);
    }
    this.headYaw += (this.lookTarget - this.headYaw) * 0.08;
    const dt = Math.min(0.1, Math.max(0, time - this.last));
    this.last = time;
    const m = this.momentAt(time);
    this.pose(time, breathe, lift, m, 1 - Math.exp(-dt * 6));
    this.snap = false;

    const sway = this.still ? 0 : 1;
    j.tail1.rotation.set(Math.sin(time * 1.3) * 0.12 * sway, 0, 14 * DEG + Math.sin(time * 1.7) * 0.16 * sway + lift * 1.4, 'ZYX');
    j.tail2.rotation.set(Math.sin(time * 1.3 + 0.9) * 0.18 * sway, 0, -8 * DEG + Math.sin(time * 1.7 - 0.8) * 0.26 * sway, 'ZYX');

    if (!this.still && time > this.blinkAt) {
      this.blinkUntil = time + 0.13;
      this.blinkAt = time + 2.2 + Math.random() * 3.5;
    }
    let frame: number = FACE2_FRAME.open;
    const leading = this.lookTarget - this.headYaw;
    if (this.still && this.moment === 'glance') frame = FACE2_FRAME.left;
    else if (this.still && this.moment === 'cheer') frame = FACE2_FRAME.closed;
    else if (!this.still && time < this.blinkUntil) frame = FACE2_FRAME.closed;
    else if (Math.abs(leading) > 0.12) frame = leading > 0 ? FACE2_FRAME.left : FACE2_FRAME.right;
    this.face.uniforms.uFrame.value = frame;

    if (this.hasCharm) {
      const a = time * 0.9;
      this.charmPivot.position.set(Math.cos(a) * 0.5, 1.55 + Math.sin(time * 2.1) * 0.05 + lift, Math.sin(a) * 0.5);
      this.charmPivot.rotation.y = -a + Math.PI / 2;
    }
  }
}
