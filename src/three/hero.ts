import * as THREE from 'three';
import { buildMesh, mirrored, type Part } from './parts';
import { litMaterial, makeDecalMaterial, makeGlow, type GlowSprite } from './RetroMaterial';
import { pixelTexture } from './textures';
import {
  FACE_ROWS,
  HEAD,
  HERO_COLORS,
  HERO_JOINTS,
  armParts,
  hairParts,
  headParts,
  legParts,
  tailParts,
  torsoParts,
  type HairStyle,
  type HeroPalette,
} from './models/hero';
import { ITEM_MODELS, type ItemModel } from './models/items';

export interface HeroLook {
  skin: string;
  hair: string;
  hairStyle: HairStyle;
  scarf: string;
  /** Only the new hero has a hood. */
  hoodDown?: boolean;
}

export type Gear = Partial<Record<'head' | 'body' | 'hand' | 'shield' | 'charm', string>>;

const DEG = Math.PI / 180;

/** The eyes: a small curved patch that hugs the front of the head. */
function faceGeometry(): THREE.BufferGeometry {
  const cols = 8;
  const rows = 4;
  const width = 0.37;
  const height = 0.185;
  const centerY = HEAD.center[1] - 0.005;
  const positions: number[] = [];
  const uvs: number[] = [];
  const index: number[] = [];
  for (let j = 0; j <= rows; j++) {
    for (let i = 0; i <= cols; i++) {
      const u = i / cols;
      const v = j / rows;
      const x = (u - 0.5) * width;
      const y = centerY + (v - 0.5) * height;
      const nx = x / HEAD.radius[0];
      const ny = (y - HEAD.center[1]) / HEAD.radius[1];
      const z = HEAD.radius[2] * Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny)) + 0.004;
      positions.push(x, y, z);
      uvs.push(u, v);
    }
  }
  for (let j = 0; j < rows; j++) {
    for (let i = 0; i < cols; i++) {
      const a = j * (cols + 1) + i;
      const b = a + 1;
      const c = a + cols + 1;
      const d = c + 1;
      index.push(a, b, d, a, d, c);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
  geo.setIndex(index);
  return geo;
}

export class Hero {
  readonly root = new THREE.Group();
  readonly joints: Record<string, THREE.Group> = {};
  /** The charm circles the hero on its own pivot. */
  readonly charmPivot = new THREE.Group();

  private readonly rest: Record<string, THREE.Euler> = {};
  private built: THREE.Object3D[] = [];
  private readonly faceMaterial: THREE.ShaderMaterial;
  private readonly face: THREE.Mesh;
  private charmGlow: GlowSprite | null = null;
  private hasCharm = false;

  private blinkAt = 2;
  private blinkUntil = 0;
  private hopStart = -10;
  private lookAt = 6;
  private lookTarget = 0;
  private headYaw = 0;

  constructor() {
    for (const spec of HERO_JOINTS) {
      const group = new THREE.Group();
      group.name = spec.name;
      group.position.set(...spec.at);
      if (spec.rot) group.rotation.set(spec.rot[0] * DEG, spec.rot[1] * DEG, spec.rot[2] * DEG, 'ZYX');
      else group.rotation.order = 'ZYX';
      this.joints[spec.name] = group;
      this.rest[spec.name] = group.rotation.clone();
      (spec.parent ? this.joints[spec.parent] : this.root).add(group);
    }
    this.root.add(this.charmPivot);

    const faceTexture = pixelTexture(FACE_ROWS, {
      K: [22, 18, 16, 255],
      B: [40, 30, 24, 255],
      W: [240, 236, 220, 255],
      M: [92, 44, 36, 255],
    });
    this.faceMaterial = makeDecalMaterial(faceTexture);
    this.faceMaterial.uniforms.uUvScale.value.set(1, 0.5);
    this.faceMaterial.uniforms.uUvOffset.value.set(0, 0.5);
    this.face = new THREE.Mesh(faceGeometry(), this.faceMaterial);
    this.joints.head.add(this.face);
  }

  private attach(joint: string, parts: Part[]) {
    if (parts.length === 0) return;
    const mesh = buildMesh(parts, litMaterial());
    this.joints[joint].add(mesh);
    this.built.push(mesh);
  }

  /** Rebuilds the hero from a look (skin, hair, scarf) and the gear being worn. */
  apply(look: HeroLook, gear: Gear) {
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

    this.attach('torso', [...torsoParts(palette), ...(body?.torso ?? [])]);
    this.attach('armR', [...armParts(palette), ...(body?.shoulder ?? [])]);
    this.attach('armL', mirrored([...armParts(palette), ...(body?.shoulder ?? [])]));
    this.attach('legR', legParts());
    this.attach('legL', legParts());
    const [tail1, tail2] = tailParts(palette);
    this.attach('tail1', tail1);
    this.attach('tail2', tail2);

    const hair = hairParts(look.hairStyle, look.hair);
    const hairMode = hat?.hair ?? 'keep';
    this.attach('head', [
      ...headParts(palette),
      ...(hairMode === 'hide' ? [] : hair.under),
      ...(hairMode === 'keep' ? hair.top : []),
    ]);
    if (hat) this.attach('hat', hat.parts);
    if (tool) this.attach('tool', tool.parts);
    if (shield) this.attach('shield', shield.parts);

    // With an empty hand the arm relaxes; holding a tool it reaches forward to grip.
    const armR = this.rest.armR;
    if (tool) armR.set(-62 * DEG, 0, -20 * DEG, 'ZYX');
    else armR.set(-10 * DEG, 0, -13 * DEG, 'ZYX');
    const armL = this.rest.armL;
    if (shield) armL.set(-34 * DEG, 0, 22 * DEG, 'ZYX');
    else armL.set(-10 * DEG, 0, 13 * DEG, 'ZYX');

    this.hasCharm = !!charm;
    if (charm) {
      const mesh = buildMesh(charm.parts, litMaterial());
      this.charmPivot.add(mesh);
      if (charm.glow) {
        this.charmGlow = makeGlow(charm.glow, 0.5, 0.55);
        this.charmPivot.add(this.charmGlow);
      }
    }
  }

  /** A little jump, played when a quest is finished. */
  cheer(time: number) {
    this.hopStart = time;
  }

  update(time: number) {
    const j = this.joints;
    const breathe = Math.sin(time * 1.9);

    // Hop: a quick squash, a jump, and a landing.
    const hop = time - this.hopStart;
    let lift = 0;
    let squash = 0;
    if (hop >= 0 && hop < 0.62) {
      const t = hop / 0.62;
      lift = Math.sin(t * Math.PI) * 0.26;
      squash = t < 0.12 ? -Math.sin((t / 0.12) * Math.PI) * 0.08 : t > 0.9 ? -Math.sin(((t - 0.9) / 0.1) * Math.PI) * 0.06 : 0.04;
    }

    j.hips.position.y = 0.4 + lift + breathe * 0.004;
    j.torso.scale.set(1 - squash * 0.5, 1 + squash + breathe * 0.012, 1 - squash * 0.5);
    j.torso.rotation.z = Math.sin(time * 0.7) * 0.012;

    // Now and then the hero glances to one side.
    if (time > this.lookAt) {
      this.lookTarget = this.lookTarget === 0 ? (Math.random() < 0.5 ? -0.5 : 0.42) : 0;
      this.lookAt = time + (this.lookTarget === 0 ? 4 + Math.random() * 5 : 1.2 + Math.random() * 1.4);
    }
    this.headYaw += (this.lookTarget - this.headYaw) * 0.12;
    j.head.rotation.set(Math.sin(time * 1.9 + 0.6) * 0.02 - lift * 0.5, this.headYaw, Math.sin(time * 0.9) * 0.015, 'ZYX');

    // Arms: follow the breathing; raise the free arm during a hop.
    const armR = this.rest.armR;
    const armL = this.rest.armL;
    j.armR.rotation.set(armR.x + breathe * 0.012, 0, armR.z, 'ZYX');
    const raise = lift > 0 ? Math.sin((hop / 0.62) * Math.PI) : 0;
    j.armL.rotation.set(armL.x + breathe * 0.015 - raise * 2.2, 0, armL.z + raise * 0.5, 'ZYX');

    // Scarf tail swings like a slow pendulum.
    j.tail1.rotation.set(Math.sin(time * 1.3) * 0.14, 0, 24 * DEG + Math.sin(time * 1.7) * 0.2 + lift * 1.6, 'ZYX');
    j.tail2.rotation.set(Math.sin(time * 1.3 + 0.9) * 0.2, 0, -10 * DEG + Math.sin(time * 1.7 - 0.8) * 0.3, 'ZYX');

    // Blink by swapping to the closed-eyes half of the face picture.
    if (time > this.blinkAt) {
      this.blinkUntil = time + 0.13;
      this.blinkAt = time + 2.2 + Math.random() * 3.5;
    }
    this.faceMaterial.uniforms.uUvOffset.value.y = time < this.blinkUntil ? 0 : 0.5;

    // Charm: circles the head, bobbing as it goes.
    if (this.hasCharm) {
      const a = time * 0.9;
      this.charmPivot.position.set(Math.cos(a) * 0.52, 1.28 + Math.sin(time * 2.1) * 0.06 + lift, Math.sin(a) * 0.52);
      this.charmPivot.rotation.y = -a + Math.PI / 2;
      if (this.charmGlow) this.charmGlow.material.uniforms.uStrength.value = 0.5 + Math.sin(time * 5) * 0.08;
    }
  }
}
