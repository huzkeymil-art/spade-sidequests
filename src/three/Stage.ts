import * as THREE from 'three';
import { world } from './RetroMaterial';
import { PostPass } from './post';
import { Hero, type Gear, type HeroLook } from './hero';
import { HORIZON, makeScenery, STONE_POS, type Scenery } from './scenery';
import { Unearth } from './unearth';
import { IconForge } from './icons';

// The stage: one 3D scene that sits behind the whole app.
// It owns the camera, the hero and the scenery, and redraws about 30 times a second.

export type View = 'title' | 'quests' | 'hero' | 'satchel' | 'feats' | 'dig';

interface Shot {
  /** The point the camera looks at. */
  target: [number, number, number];
  /** How far back the camera stands, and how high. */
  dist: number;
  height: number;
  /** Camera angle around the target, in radians. */
  yaw: number;
  /** Where on screen the target lands: 0 = top edge, 1 = bottom edge. */
  screenY: number;
  /** Where the panel of UI begins, as a fraction of the screen height. 1 = no panel. */
  sheet: number;
}

const SHOTS: Record<View, Shot> = {
  title: { target: [0.25, 1.0, 0], dist: 12.5, height: 0.9, yaw: 0, screenY: 0.4, sheet: 0.66 },
  quests: { target: [0.3, 0.9, 0], dist: 13, height: 1.35, yaw: 0, screenY: 0.25, sheet: 0.42 },
  hero: { target: [0, 0.8, 0], dist: 8.2, height: 0.78, yaw: -0.075, screenY: 0.33, sheet: 0.54 },
  satchel: { target: [0, 0.84, 0], dist: 11, height: 0.8, yaw: -0.075, screenY: 0.225, sheet: 0.38 },
  feats: { target: [STONE_POS.x - 0.5, 1.02, STONE_POS.z], dist: 13.5, height: 0.8, yaw: -0.1, screenY: 0.215, sheet: 0.38 },
  dig: { target: [0.5, 0.7, 0.8], dist: 7.2, height: 1.3, yaw: 0.16, screenY: 0.33, sheet: 0.6 },
};

const FOV = 32;
const FRAME = 1 / 30;
const DEFAULT_HERO_YAW = -0.22;

export interface Progress {
  /** Dailies finished today, and how many there are. */
  dailyDone: number;
  dailyTotal: number;
  streak: number;
  /** One entry per weekday (Monday first): was a daily finished that day? */
  week: boolean[];
  /** Today's weekday, 0 = Monday. */
  today: number;
  /** How far through the month it is, 0..1. */
  month: number;
}

export class Stage {
  readonly renderer: THREE.WebGLRenderer;
  readonly scene = new THREE.Scene();
  readonly camera = new THREE.PerspectiveCamera(FOV, 1, 0.5, 300);
  readonly hero = new Hero();
  readonly scenery: Scenery;
  readonly post = new PostPass();
  readonly unearth = new Unearth();
  readonly icons: IconForge;

  private target: THREE.WebGLRenderTarget;
  private retro = true;
  private view: View = 'quests';
  private shot: Shot = { ...SHOTS.quests };
  private cssWidth = 1;
  private cssHeight = 1;
  private lowWidth = 1;
  private lowHeight = 1;
  private scale = 4;

  private running = false;
  private raf = 0;
  private last = 0;
  private owed = 0;
  private time = 0;

  private heroYaw = DEFAULT_HERO_YAW;
  private heroYawTarget = DEFAULT_HERO_YAW;
  private dragging = false;
  private dragX = 0;
  private freeSpin = false;
  private burstAt = -10;
  private sheetCss = '';

  private readonly lookAt = new THREE.Vector3();
  private readonly resizeObserver: ResizeObserver;

  constructor(readonly canvas: HTMLCanvasElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false, powerPreference: 'low-power' });
    this.renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
    this.renderer.autoClear = true;
    this.renderer.setClearColor(0x0d0f0c, 1);

    this.target = new THREE.WebGLRenderTarget(4, 4, {
      minFilter: THREE.NearestFilter,
      magFilter: THREE.NearestFilter,
      depthBuffer: true,
    });

    world.uFogColor.value.copy(HORIZON);
    this.scenery = makeScenery();
    this.scene.add(this.scenery.group, this.hero.root, this.unearth.group);
    this.icons = new IconForge(this.renderer);
    this.hero.root.rotation.y = this.heroYaw;

    const s = SHOTS.quests;
    this.lookAt.set(...s.target);

    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(canvas);
    this.resize();

    canvas.addEventListener('pointerdown', this.onPointerDown);
    window.addEventListener('pointermove', this.onPointerMove);
    window.addEventListener('pointerup', this.onPointerUp);
    window.addEventListener('pointercancel', this.onPointerUp);
    document.addEventListener('visibilitychange', this.onVisibility);
  }

  // ---- Public controls ----------------------------------------------------

  start() {
    if (this.running) return;
    this.running = true;
    this.last = performance.now();
    this.raf = requestAnimationFrame(this.tick);
  }

  stop() {
    this.running = false;
    cancelAnimationFrame(this.raf);
  }

  dispose() {
    this.stop();
    this.resizeObserver.disconnect();
    this.canvas.removeEventListener('pointerdown', this.onPointerDown);
    window.removeEventListener('pointermove', this.onPointerMove);
    window.removeEventListener('pointerup', this.onPointerUp);
    window.removeEventListener('pointercancel', this.onPointerUp);
    document.removeEventListener('visibilitychange', this.onVisibility);
    this.target.dispose();
    this.renderer.dispose();
  }

  setView(view: View) {
    this.view = view;
    // Only the Hero screen lets the avatar stay turned; elsewhere it swings back to face front.
    this.freeSpin = view === 'hero';
    // During a dig the hero turns to watch.
    if (!this.freeSpin) this.heroYawTarget = view === 'dig' ? 0.5 : DEFAULT_HERO_YAW;
  }

  /** Jumps straight to a view with no camera glide (used on first load). */
  snapView(view: View) {
    this.setView(view);
    this.shot = { ...SHOTS[view] };
    this.lookAt.set(...this.shot.target);
  }

  setRetro(on: boolean) {
    if (this.retro === on) return;
    this.retro = on;
    this.resize();
  }

  setHero(look: HeroLook, gear: Gear) {
    this.hero.apply(look, gear);
  }

  setProgress(p: Progress) {
    const level = p.dailyTotal > 0 ? Math.min(1, p.dailyDone / p.dailyTotal) : 0;
    this.scenery.lantern.setFlame(level, flameColor(p.streak));
    this.scenery.weekStone.setWeek(p.week, p.today);
    // Never quite a new moon: a sliver always shows, so the moon stays part of the picture.
    this.scenery.moon.setPhase(0.1 + p.month * 0.9);
  }

  /** The hero hops and the lantern flares. */
  cheer() {
    this.hero.cheer(this.time);
    this.scenery.lantern.flare(this.time);
  }

  /** Starts the dig-up sequence for an item, lit in the given colour. */
  playUnearth(itemId: string, color: THREE.ColorRepresentation) {
    this.unearth.play(itemId, color, this.time);
  }

  endUnearth() {
    this.unearth.dismiss();
  }

  /** A burst of warm light around the hero, for level-ups. */
  burst() {
    this.burstAt = this.time;
    this.hero.cheer(this.time);
    this.scenery.lantern.flare(this.time);
  }

  // ---- Internals ----------------------------------------------------------

  private get pixelRatio() {
    const dpr = window.devicePixelRatio || 1;
    return this.retro ? dpr : Math.min(dpr, 2);
  }

  private resize() {
    const rect = this.canvas.getBoundingClientRect();
    this.cssWidth = Math.max(1, rect.width);
    this.cssHeight = Math.max(1, rect.height);
    const ratio = this.pixelRatio;
    const deviceW = Math.round(this.cssWidth * ratio);
    const deviceH = Math.round(this.cssHeight * ratio);
    // In retro mode each scene pixel covers a block of screen pixels (about 1.4 CSS px wide).
    this.scale = this.retro ? Math.max(2, Math.round(ratio * 1.4)) : 1;
    this.lowWidth = Math.ceil(deviceW / this.scale);
    this.lowHeight = Math.ceil(deviceH / this.scale);

    this.renderer.setPixelRatio(1);
    this.renderer.setSize(deviceW, deviceH, false);
    this.target.setSize(this.lowWidth, this.lowHeight);

    const u = this.post.material.uniforms;
    u.uLowSize.value.set(this.lowWidth, this.lowHeight);
    u.uScale.value = this.scale;
    u.uLevels.value = this.retro ? 22 : 64;
    u.uFade.value = (this.retro ? 26 : 34) / (this.scale / ratio);

    this.camera.aspect = this.lowWidth / this.lowHeight;
    // The UI's dot patterns stay chunky even when the scene itself is drawn sharp.
    document.documentElement.style.setProperty('--px', `${this.retro ? this.scale / ratio : 1.4}px`);
    if (!this.running) this.render();
  }

  private tick = (nowMs: number) => {
    if (!this.running) return;
    this.raf = requestAnimationFrame(this.tick);
    const dt = Math.min(0.1, (nowMs - this.last) / 1000);
    this.last = nowMs;
    this.owed += dt;
    if (this.owed < FRAME) return;
    const step = this.owed;
    this.owed = 0;
    this.time += step;
    this.update(step);
    this.render();
  };

  private update(dt: number) {
    const goal = SHOTS[this.view];
    const ease = 1 - Math.exp(-dt * 5.5);
    const s = this.shot;
    s.dist += (goal.dist - s.dist) * ease;
    s.height += (goal.height - s.height) * ease;
    s.yaw += (goal.yaw - s.yaw) * ease;
    s.screenY += (goal.screenY - s.screenY) * ease;
    s.sheet += (goal.sheet - s.sheet) * ease;
    if (Math.abs(goal.sheet - s.sheet) < 0.0015) s.sheet = goal.sheet;
    this.lookAt.x += (goal.target[0] - this.lookAt.x) * ease;
    this.lookAt.y += (goal.target[1] - this.lookAt.y) * ease;
    this.lookAt.z += (goal.target[2] - this.lookAt.z) * ease;

    if (!this.dragging) this.heroYaw += (this.heroYawTarget - this.heroYaw) * (1 - Math.exp(-dt * 6));
    this.hero.root.rotation.y = this.heroYaw;

    world.uTime.value = this.time;
    this.hero.update(this.time);
    this.scenery.lantern.update(this.time);
    this.scenery.weekStone.update(this.time);
    this.unearth.update(this.time, dt);
    if (!this.unearth.active) {
      const glow = Math.max(0, 1 - (this.time - this.burstAt) / 1.4);
      world.uGlowPos.value.set(0, 1.1, 0.9);
      world.uGlowColor.value.setRGB(1.0, 0.82, 0.5).multiplyScalar(glow * glow * 2.2);
      world.uGlowRange.value = 5;
    }
  }

  private render() {
    const s = this.shot;
    // A slow, slight drift keeps the picture from feeling frozen.
    const yaw = s.yaw + Math.sin(this.time * 0.17) * 0.035;
    this.camera.position.set(
      this.lookAt.x + Math.sin(yaw) * s.dist,
      s.height,
      this.lookAt.z + Math.cos(yaw) * s.dist,
    );
    this.camera.lookAt(this.lookAt);
    // Slide the picture up or down so the target lands at `screenY` instead of dead centre.
    const shift = Math.round((0.5 - s.screenY) * this.lowHeight);
    this.camera.setViewOffset(this.lowWidth, this.lowHeight, 0, shift, this.lowWidth, this.lowHeight);

    world.uFogNear.value = s.dist - 2;
    world.uFogFar.value = s.dist + 44;

    // The UI panel follows the same number the dither fade uses, so they never drift apart.
    const sheetLow = Math.round(s.sheet * this.lowHeight);
    this.post.material.uniforms.uSheetY.value = s.sheet >= 1 ? 1e6 : sheetLow;
    const sheetCss = `${(s.sheet >= 1 ? this.cssHeight : (sheetLow * this.scale) / this.pixelRatio).toFixed(2)}px`;
    if (sheetCss !== this.sheetCss) {
      // Only written when it changes: updating it every frame would make the browser re-style the page 30 times a second.
      this.sheetCss = sheetCss;
      document.documentElement.style.setProperty('--sheet-top', sheetCss);
    }

    this.renderer.setRenderTarget(this.target);
    this.renderer.render(this.scene, this.camera);
    this.post.material.uniforms.tScene.value = this.target.texture;
    this.renderer.setRenderTarget(null);
    this.renderer.render(this.post.scene, this.post.camera);
  }

  private onPointerDown = (e: PointerEvent) => {
    this.dragging = true;
    this.dragX = e.clientX;
  };

  private onPointerMove = (e: PointerEvent) => {
    if (!this.dragging) return;
    this.heroYaw += (e.clientX - this.dragX) * 0.012;
    this.dragX = e.clientX;
    if (this.freeSpin) this.heroYawTarget = this.heroYaw;
  };

  private onPointerUp = () => {
    this.dragging = false;
  };

  private onVisibility = () => {
    if (document.hidden) {
      cancelAnimationFrame(this.raf);
    } else if (this.running) {
      this.last = performance.now();
      this.raf = requestAnimationFrame(this.tick);
    }
  };
}

/** The lantern burns hotter, then stranger, as the streak grows. */
export function flameColor(streak: number): THREE.Color {
  if (streak >= 100) return new THREE.Color(0.78, 0.74, 1.0); // moon-white
  if (streak >= 30) return new THREE.Color(0.42, 1.0, 0.8); // foxfire
  if (streak >= 7) return new THREE.Color(1.0, 0.78, 0.42); // white-gold
  return new THREE.Color(1.0, 0.64, 0.3); // amber
}
