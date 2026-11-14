import * as THREE from 'three';
import { buildMesh, type Part } from './parts';
import { makeGlow, world, type GlowSprite } from './RetroMaterial';
import { DIG_POS } from './scenery';
import { ITEM_MODELS, MISSING_MODEL, displayParts } from './models/items';

// The dig-up: how every item arrives.
//
// The ground swells, clods of earth fly, a buried lockbox pushes up through
// the soil, its lid snaps open with a burst of light, and the item rises out
// of it, turning slowly.

const SOIL = '#4b3d2a';
const SOIL_DARK = '#2a2118';
const BOX_WOOD = '#3d2f22';
const BOX_IRON = '#5c5f5e';
const BRASS = '#c9a04a';

const moundParts: Part[] = [{ s: 'ball', r: [0.46, 0.2, 0.4], seg: [8, 5], at: [0, 0.02, 0], c: SOIL, c2: SOIL_DARK, tile: 'soil' }];

const boxParts: Part[] = [
  { s: 'box', size: [0.46, 0.24, 0.32], at: [0, 0.12, 0], c: BOX_WOOD, tile: 'wood' },
  { s: 'box', size: [0.05, 0.25, 0.33], at: [-0.15, 0.12, 0], c: BOX_IRON, tile: 'metal' },
  { s: 'box', size: [0.05, 0.25, 0.33], at: [0.15, 0.12, 0], c: BOX_IRON, tile: 'metal' },
  // The inside glows once the lid lifts.
  { s: 'box', size: [0.4, 0.02, 0.26], at: [0, 0.235, 0], c: '#fff3cf', c2: '#fff3cf', emit: 1 },
];

// The lid is modelled with its hinge (back edge) at the origin, so it can swing open.
const lidParts: Part[] = [
  { s: 'box', size: [0.48, 0.1, 0.34], taper: [0.92, 0.8], at: [0, 0.05, 0.17], c: BOX_WOOD, tile: 'wood' },
  { s: 'box', size: [0.05, 0.105, 0.35], taper: [1, 0.8], at: [-0.15, 0.05, 0.17], c: BOX_IRON, tile: 'metal' },
  { s: 'box', size: [0.05, 0.105, 0.35], taper: [1, 0.8], at: [0.15, 0.05, 0.17], c: BOX_IRON, tile: 'metal' },
  { s: 'box', size: [0.08, 0.1, 0.03], at: [0, 0.0, 0.345], c: BRASS, tile: 'metal' },
];

const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
/** 0 to 1 over the time window [from, to]. */
const span = (t: number, from: number, to: number) => clamp01((t - from) / (to - from));
const easeOut = (x: number) => 1 - Math.pow(1 - x, 3);
/** Overshoots a little past 1 and settles back, like something landing. */
const easeBack = (x: number) => 1 + 2.2 * Math.pow(x - 1, 3) + 1.2 * Math.pow(x - 1, 2);

interface Clod {
  mesh: THREE.Mesh;
  velocity: THREE.Vector3;
  spin: THREE.Vector3;
}

export class Unearth {
  readonly group = new THREE.Group();
  /** True from the moment a dig starts until it is dismissed. */
  active = false;

  private readonly mound: THREE.Mesh;
  private readonly box = new THREE.Group();
  private readonly lid = new THREE.Group();
  private readonly itemPivot = new THREE.Group();
  private readonly beam: GlowSprite;
  private readonly halo: GlowSprite;
  private readonly clods: Clod[] = [];
  private itemMesh: THREE.Mesh | null = null;
  private startedAt = 0;
  private readonly color = new THREE.Color();

  constructor() {
    this.group.position.copy(DIG_POS);
    this.group.rotation.y = 0.35;
    this.group.visible = false;

    this.mound = buildMesh(moundParts);
    this.group.add(this.mound);

    this.box.add(buildMesh(boxParts));
    this.lid.position.set(0, 0.24, -0.16);
    this.lid.add(buildMesh(lidParts));
    this.box.add(this.lid);
    this.group.add(this.box);

    this.beam = makeGlow(0xffffff, 1.6, 0);
    this.beam.position.set(0, 0.5, 0);
    this.halo = makeGlow(0xffffff, 1.3, 0);
    this.group.add(this.beam, this.itemPivot);
    this.itemPivot.add(this.halo);

    for (let i = 0; i < 12; i++) {
      const size = 0.035 + (i % 4) * 0.014;
      const mesh = buildMesh([{ s: 'box', size: [size, size, size], c: i % 3 === 0 ? SOIL_DARK : SOIL, tile: 'soil' }]);
      this.group.add(mesh);
      this.clods.push({ mesh, velocity: new THREE.Vector3(), spin: new THREE.Vector3() });
    }
  }

  /** Starts the sequence for an item. `color` tints the light (by rarity). */
  play(itemId: string, color: THREE.ColorRepresentation, time: number) {
    this.clearItem();
    const model = ITEM_MODELS[itemId];
    const parts = model ? displayParts(model) : MISSING_MODEL;
    const mesh = buildMesh(parts);
    // Centre the item and scale it so big and small things present at a similar size.
    mesh.geometry.computeBoundingBox();
    const box = mesh.geometry.boundingBox!;
    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    mesh.geometry.translate(-center.x, -center.y, -center.z);
    // Long thin tools get shown larger, or they would look like a twig.
    const showSize = model?.slot === 'hand' ? 1.0 : 0.66;
    mesh.scale.setScalar(showSize / Math.max(size.x, size.y, size.z, 0.2));
    if (model?.slot === 'hand') mesh.rotation.z = -0.5;
    this.itemPivot.add(mesh);
    this.itemMesh = mesh;

    this.color.set(color);
    this.beam.material.uniforms.uColor.value.copy(this.color);
    this.halo.material.uniforms.uColor.value.copy(this.color);

    this.clods.forEach((clod, i) => {
      const angle = (i / this.clods.length) * Math.PI * 2 + (i % 2) * 0.4;
      const speed = 0.7 + (i % 3) * 0.35;
      clod.mesh.position.set(Math.cos(angle) * 0.12, 0.05, Math.sin(angle) * 0.12);
      clod.velocity.set(Math.cos(angle) * speed, 2.1 + (i % 4) * 0.45, Math.sin(angle) * speed);
      clod.spin.set(3 + i, 2 + (i % 5), 1 + (i % 3));
      clod.mesh.visible = false;
    });

    this.startedAt = time;
    this.active = true;
    this.group.visible = true;
    this.update(time, 0);
  }

  /** Puts everything away again. */
  dismiss() {
    this.active = false;
    this.group.visible = false;
    world.uGlowColor.value.setRGB(0, 0, 0);
    this.clearItem();
  }

  private clearItem() {
    if (this.itemMesh) {
      this.itemPivot.remove(this.itemMesh);
      this.itemMesh.geometry.dispose();
      this.itemMesh = null;
    }
  }

  update(time: number, dt: number) {
    if (!this.active) return;
    const t = time - this.startedAt;

    // 1. The ground swells.
    const swell = easeBack(span(t, 0, 0.4));
    this.mound.scale.set(0.3 + swell * 0.7, swell, 0.3 + swell * 0.7);

    // 2. Clods of earth fly up and fall back.
    for (const clod of this.clods) {
      if (t < 0.16) continue;
      clod.mesh.visible = clod.mesh.position.y > -0.05;
      clod.velocity.y -= 7.5 * dt;
      clod.mesh.position.addScaledVector(clod.velocity, dt);
      clod.mesh.rotation.x += clod.spin.x * dt;
      clod.mesh.rotation.y += clod.spin.y * dt;
      clod.mesh.rotation.z += clod.spin.z * dt;
    }

    // 3. The lockbox pushes up through the soil, rocking as it comes.
    const rise = easeBack(span(t, 0.32, 0.95));
    const rock = (1 - span(t, 0.32, 1.25)) * Math.sin(t * 26) * 0.07;
    this.box.position.y = -0.36 + rise * 0.48;
    this.box.rotation.set(rock * 0.6, 0, rock);

    // 4. The lid snaps open and light pours out.
    const open = easeBack(span(t, 1.05, 1.4));
    this.lid.rotation.x = -open * 1.75;
    const light = span(t, 1.05, 1.5);
    const pulse = 0.9 + Math.sin(t * 5) * 0.1;
    this.beam.material.uniforms.uStrength.value = light * 0.75 * pulse;
    this.beam.material.uniforms.uSize.value = 1.2 + light * 0.9;

    // 5. The item rises out, spinning quickly at first and then slowing.
    const lift = easeOut(span(t, 1.3, 2.4));
    const bob = t > 2.4 ? Math.sin((t - 2.4) * 1.8) * 0.035 : 0;
    this.itemPivot.position.y = 0.22 + lift * 0.86 + bob;
    this.itemPivot.scale.setScalar(0.2 + lift * 0.8);
    this.itemPivot.visible = t > 1.28;
    this.itemPivot.rotation.y = t * 1.3 + (1 - lift) * 9;
    this.halo.material.uniforms.uStrength.value = lift * 0.42 * pulse;

    // The find lights up the hero and the ground around it.
    world.uGlowPos.value.set(DIG_POS.x, 0.5 + lift * 0.5, DIG_POS.z + 0.2);
    world.uGlowColor.value.copy(this.color).multiplyScalar(light * 1.5 * pulse);
    world.uGlowRange.value = 4.5;
  }

  /** How long after `play` the item is fully presented. */
  static readonly REVEAL_SECONDS = 2.3;
}
