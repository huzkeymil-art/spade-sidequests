import * as THREE from 'three';
import { buildMesh } from './parts';
import { world } from './RetroMaterial';
import { Hero, type Gear, type HeroLook } from './hero';
import { ITEM_MODELS, MISSING_MODEL, displayParts } from './models/items';
import { PROPS } from './models/props';

// The icon camera. Every icon in the app is a tiny photo of a real 3D model:
// the model is drawn very small, dithered the same way as the main scene, and
// then blown up with hard pixels into an image the UI can show.

const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const LEVELS = 12;
const UPSCALE = 4;

type Uniform<T> = { value: T };

export class IconForge {
  private readonly scene = new THREE.Scene();
  private readonly camera = new THREE.OrthographicCamera(-0.5, 0.5, 0.5, -0.5, 0.1, 20);
  private readonly holder = new THREE.Group();
  private readonly cache = new Map<string, string>();
  private readonly targets = new Map<number, THREE.WebGLRenderTarget>();
  private portraitHero: Hero | null = null;

  constructor(private readonly renderer: THREE.WebGLRenderer) {
    this.scene.add(this.holder);
    this.camera.position.set(0, 0, 8);
    this.camera.lookAt(0, 0, 0);
  }

  /** Icon for an inventory item. */
  item(id: string, size = 30): string {
    return this.cached(`item:${id}:${size}`, () => {
      const model = ITEM_MODELS[id];
      const parts = model ? displayParts(model) : MISSING_MODEL;
      const tall = model?.slot === 'hand';
      return this.shoot(buildMesh(parts), size, tall ? [0.18, -0.5, -0.7] : [0.3, -0.55, 0]);
    });
  }

  /** Icon for one of the little props (tab icons, category icons, and so on). */
  prop(name: string, size = 22): string {
    return this.cached(`prop:${name}:${size}`, () => {
      const parts = PROPS[name] ?? MISSING_MODEL;
      return this.shoot(buildMesh(parts), size, [0.25, -0.5, 0]);
    });
  }

  /** A head-and-shoulders picture of the hero as they currently look. */
  portrait(look: HeroLook, gear: Gear, size = 26): string {
    const key = `portrait:${JSON.stringify(look)}:${gear.head ?? ''}:${gear.body ?? ''}:${size}`;
    return this.cached(key, () => {
      if (!this.portraitHero) this.portraitHero = new Hero();
      const hero = this.portraitHero;
      hero.apply(look, { head: gear.head, body: gear.body });
      hero.joints.armR.visible = false;
      hero.joints.armL.visible = false;
      hero.root.rotation.set(0, 0, 0);
      const box = new THREE.Box3(new THREE.Vector3(-0.42, 0.86, -0.4), new THREE.Vector3(0.42, 1.7, 0.4));
      return this.shoot(hero.root, size, [0.06, -0.38, 0], box, false);
    });
  }

  private cached(key: string, make: () => string): string {
    let url = this.cache.get(key);
    if (!url) {
      url = make();
      this.cache.set(key, url);
    }
    return url;
  }

  private targetFor(size: number): THREE.WebGLRenderTarget {
    let target = this.targets.get(size);
    if (!target) {
      target = new THREE.WebGLRenderTarget(size, size, { minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter });
      this.targets.set(size, target);
    }
    return target;
  }

  /** Photographs `object`, turned by `tilt` (radians around X, Y, Z), and returns a PNG data URL. */
  private shoot(object: THREE.Object3D, size: number, tilt: [number, number, number], frame?: THREE.Box3, dispose = true): string {
    // Centre the object and zoom so it fills the frame.
    const box = frame ?? new THREE.Box3().setFromObject(object);
    const center = box.getCenter(new THREE.Vector3());
    const extent = box.getSize(new THREE.Vector3());
    const wrapper = new THREE.Group();
    wrapper.add(object);
    object.position.sub(center);
    this.holder.add(wrapper);
    wrapper.rotation.set(tilt[0], tilt[1], tilt[2], 'ZXY');

    // After turning, measure again so nothing pokes out of the picture.
    wrapper.updateMatrixWorld(true);
    let reach = Math.max(extent.x, extent.y) / 2;
    if (!frame) {
      const turned = new THREE.Box3().setFromObject(wrapper);
      reach = Math.max(Math.abs(turned.min.x), Math.abs(turned.max.x), Math.abs(turned.min.y), Math.abs(turned.max.y));
    }
    const half = reach * 1.06;
    this.camera.left = -half;
    this.camera.right = half;
    this.camera.top = half;
    this.camera.bottom = -half;
    this.camera.updateProjectionMatrix();

    // Borrow the scene's lights for a moment and set up studio lighting instead.
    const keep = snapshot();
    world.uAmbient.value.setRGB(0.56, 0.57, 0.56);
    world.uMoonDir.value.set(-0.45, 0.7, 0.55).normalize();
    world.uMoonColor.value.setRGB(1.0, 0.97, 0.9);
    world.uLampPos.value.set(2.2, -1.2, 2.5);
    world.uLampColor.value.setRGB(0.5, 0.3, 0.14);
    world.uLampRange.value = 9;
    world.uGlowColor.value.setRGB(0, 0, 0);
    world.uFogNear.value = 1000;
    world.uFogFar.value = 2000;

    const target = this.targetFor(size);
    const previousTarget = this.renderer.getRenderTarget();
    const previousClear = this.renderer.getClearColor(new THREE.Color());
    const previousAlpha = this.renderer.getClearAlpha();
    this.renderer.setRenderTarget(target);
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.clear();
    this.renderer.render(this.scene, this.camera);
    const pixels = new Uint8Array(size * size * 4);
    this.renderer.readRenderTargetPixels(target, 0, 0, size, size, pixels);
    this.renderer.setRenderTarget(previousTarget);
    this.renderer.setClearColor(previousClear, previousAlpha);
    restore(keep);

    object.position.add(center);
    wrapper.remove(object);
    this.holder.remove(wrapper);
    if (dispose) (object as THREE.Mesh).geometry?.dispose();

    return toDataUrl(pixels, size);
  }
}

type Snapshot = [Uniform<{ clone(): unknown; copy(v: never): unknown }> | Uniform<number>, unknown][];

function snapshot(): Snapshot {
  const out: Snapshot = [];
  for (const uniform of Object.values(world) as Uniform<unknown>[]) {
    const v = uniform.value;
    if (typeof v === 'number') out.push([uniform as Uniform<number>, v]);
    else if (v instanceof THREE.Color || v instanceof THREE.Vector3) out.push([uniform as never, v.clone()]);
  }
  return out;
}

function restore(saved: Snapshot) {
  for (const [uniform, value] of saved) {
    if (typeof value === 'number') (uniform as Uniform<number>).value = value;
    else (uniform.value as { copy(v: unknown): void }).copy(value);
  }
}

/** Dithers the raw pixels down to a few shades, enlarges them, and packs them as a PNG. */
function toDataUrl(pixels: Uint8Array, size: number): string {
  const small = document.createElement('canvas');
  small.width = size;
  small.height = size;
  const ctx = small.getContext('2d')!;
  const image = ctx.createImageData(size, size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const from = ((size - 1 - y) * size + x) * 4; // the graphics card stores rows bottom-up
      const to = (y * size + x) * 4;
      const threshold = BAYER[(y % 4) * 4 + (x % 4)] / 16;
      const alpha = pixels[from + 3];
      for (let c = 0; c < 3; c++) {
        const value = pixels[from + c] / 255;
        image.data[to + c] = Math.min(255, Math.round((Math.floor(value * LEVELS + threshold) / LEVELS) * 255));
      }
      image.data[to + 3] = alpha > 110 ? 255 : 0;
    }
  }
  ctx.putImageData(image, 0, 0);

  const big = document.createElement('canvas');
  big.width = size * UPSCALE;
  big.height = size * UPSCALE;
  const bigCtx = big.getContext('2d')!;
  bigCtx.imageSmoothingEnabled = false;
  bigCtx.drawImage(small, 0, 0, big.width, big.height);
  return big.toDataURL('image/png');
}
