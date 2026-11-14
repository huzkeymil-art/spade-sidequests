// The camera's set positions, as plain data. Both the web stage and the
// Swift app read these, so the two versions frame the scene identically.

export type View = 'title' | 'quests' | 'hero' | 'satchel' | 'feats' | 'dig';

export interface Shot {
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

/** The Week Stone stands at x 1.02, z -1.0; the feats shot looks just left of it. */
export const SHOTS: Record<View, Shot> = {
  title: { target: [0.25, 1.0, 0], dist: 12.5, height: 0.9, yaw: 0, screenY: 0.4, sheet: 0.66 },
  quests: { target: [0.3, 0.9, 0], dist: 13, height: 1.35, yaw: 0, screenY: 0.25, sheet: 0.42 },
  hero: { target: [0, 0.8, 0], dist: 8.2, height: 0.78, yaw: -0.075, screenY: 0.33, sheet: 0.54 },
  satchel: { target: [0, 0.84, 0], dist: 11, height: 0.8, yaw: -0.075, screenY: 0.225, sheet: 0.38 },
  feats: { target: [0.52, 1.02, -1.0], dist: 13.5, height: 0.8, yaw: -0.1, screenY: 0.215, sheet: 0.38 },
  dig: { target: [0.5, 0.7, 0.8], dist: 7.2, height: 1.3, yaw: 0.16, screenY: 0.33, sheet: 0.6 },
};

/** Vertical field of view, in degrees. */
export const FOV = 32;
/** Which way the hero faces at rest, in radians. Slightly toward the lantern. */
export const DEFAULT_HERO_YAW = -0.22;
/** Which way the hero turns to watch a dig. */
export const DIG_HERO_YAW = 0.5;
