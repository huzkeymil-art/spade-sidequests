import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { Tile, tileUv, type TileName } from './textures';
import { litMaterial } from './RetroMaterial';

// Models as data.
//
// Nothing in Spade is loaded from a 3D model file. Every object is a short
// list of simple shapes (boxes, cylinders, balls), like a LEGO instruction
// sheet. This file turns such a list into something the graphics card can draw.
//
// Because the lists are plain data, the future Swift version can read the
// same lists and build the same models out of SceneKit's own boxes and balls.

export type Vec3 = [number, number, number];

interface PartBase {
  /** Position of the shape's centre. */
  at?: Vec3;
  /** Rotation in degrees around X, Y, Z. */
  rot?: Vec3;
  /** Colour at the top of the shape. */
  c: string;
  /** Colour at the bottom. Defaults to a darker version of `c`, which fakes soft shadowing. */
  c2?: string;
  /** Surface texture. */
  tile?: TileName;
  /** 0 = lit by the scene, 1 = glows with its own colour. */
  emit?: number;
  /** Stretches the shape before it is turned and moved, for example to flatten a round torso front to back. */
  scale?: Vec3;
}

export interface BoxPart extends PartBase {
  s: 'box';
  size: Vec3;
  /** Shrinks (or grows) the top face: 1 = straight sides, 0.5 = top is half as wide. */
  taper?: number | [number, number];
}

export interface CylPart extends PartBase {
  s: 'cyl';
  /** Radius, or [top, bottom] radius. A top radius of 0 makes a cone. */
  r: number | [number, number];
  h: number;
  /** Number of sides. Fewer sides = chunkier. */
  sides?: number;
  /** Flat-faced instead of smoothly shaded. */
  flat?: boolean;
}

export interface BallPart extends PartBase {
  s: 'ball';
  /** Radius, or separate radii for X, Y, Z to make an egg or a pebble. */
  r: number | Vec3;
  seg?: [number, number];
  /** Only the top half, like a dome or the crown of a cap. */
  top?: boolean;
}

/** A shape turned on a lathe: a profile of [radius, height] points spun around the up axis. */
export interface LathePart extends PartBase {
  s: 'lathe';
  /** From the bottom up. A radius of 0 closes the shape there. */
  pts: [number, number][];
  sides?: number;
  /** Leaves a gap this many degrees wide at the front (+Z), like the opening of a cloak. */
  open?: number;
}

/** A rod with rounded ends: arms, fingers, straps. `h` is the length of the straight middle. */
export interface CapsulePart extends PartBase {
  s: 'capsule';
  r: number;
  h: number;
  sides?: number;
}

/** A ring lying flat: belts, cuffs, collars. */
export interface RingPart extends PartBase {
  s: 'ring';
  /** Distance from the middle of the ring to the middle of the tube. */
  r: number;
  /** Thickness of the tube. */
  tube: number;
  sides?: number;
  /** How much of the ring to draw, in degrees (a C shape for less than 360). */
  arc?: number;
}

export type Part = BoxPart | CylPart | BallPart | LathePart | CapsulePart | RingPart;

const DEG = Math.PI / 180;
const colorA = new THREE.Color();
const colorB = new THREE.Color();

/** The darker "bottom" colour used when a part doesn't name one. */
function shadeOf(hex: string): THREE.Color {
  const c = new THREE.Color(hex);
  // Shadows lean slightly cool, the way moonlit shade does.
  return new THREE.Color(c.r * 0.6, c.g * 0.66, c.b * 0.7);
}

function shapeGeometry(part: Part): THREE.BufferGeometry {
  const geo = baseGeometry(part);
  if (part.scale) {
    geo.scale(part.scale[0], part.scale[1], part.scale[2]);
    geo.computeVertexNormals();
  }
  return geo;
}

function baseGeometry(part: Part): THREE.BufferGeometry {
  switch (part.s) {
    case 'lathe': {
      const gap = (part.open ?? 0) * DEG;
      const geo = new THREE.LatheGeometry(part.pts.map(([r, y]) => new THREE.Vector2(r, y)), part.sides ?? 12, gap / 2, Math.PI * 2 - gap);
      geo.computeVertexNormals();
      return geo;
    }
    case 'capsule':
      return new THREE.CapsuleGeometry(part.r, part.h, 3, part.sides ?? 8);
    case 'ring': {
      const geo = new THREE.TorusGeometry(part.r, part.tube, 5, part.sides ?? 14, ((part.arc ?? 360) * Math.PI) / 180);
      geo.rotateX(Math.PI / 2);
      return geo;
    }
    case 'box': {
      const geo = new THREE.BoxGeometry(part.size[0], part.size[1], part.size[2]);
      if (part.taper !== undefined) {
        const [tx, tz] = Array.isArray(part.taper) ? part.taper : [part.taper, part.taper];
        const pos = geo.attributes.position;
        for (let i = 0; i < pos.count; i++) {
          if (pos.getY(i) > 0) {
            pos.setX(i, pos.getX(i) * tx);
            pos.setZ(i, pos.getZ(i) * tz);
          }
        }
        geo.computeVertexNormals();
      }
      return geo;
    }
    case 'cyl': {
      const [top, bottom] = Array.isArray(part.r) ? part.r : [part.r, part.r];
      const geo = new THREE.CylinderGeometry(top, bottom, part.h, part.sides ?? 7, 1);
      if (part.flat) {
        const flat = geo.toNonIndexed();
        flat.computeVertexNormals();
        // Re-index so every geometry can be merged the same way.
        const index: number[] = [];
        for (let i = 0; i < flat.attributes.position.count; i++) index.push(i);
        flat.setIndex(index);
        return flat;
      }
      return geo;
    }
    case 'ball': {
      const [rx, ry, rz] = Array.isArray(part.r) ? part.r : [part.r, part.r, part.r];
      const [w, h] = part.seg ?? [8, 6];
      const geo = part.top ? new THREE.SphereGeometry(1, w, h, 0, Math.PI * 2, 0, Math.PI / 2) : new THREE.SphereGeometry(1, w, h);
      geo.scale(rx, ry, rz);
      return geo;
    }
  }
}

const matrix = new THREE.Matrix4();
const euler = new THREE.Euler();
const quat = new THREE.Quaternion();
const one = new THREE.Vector3(1, 1, 1);

/** Turns a list of parts into one merged shape. */
export function buildGeometry(parts: Part[]): THREE.BufferGeometry {
  const pieces: THREE.BufferGeometry[] = [];
  for (const part of parts) {
    const geo = shapeGeometry(part);
    const pos = geo.attributes.position;
    const count = pos.count;

    // Paint a top-to-bottom colour gradient onto the corners of the shape.
    geo.computeBoundingBox();
    const minY = geo.boundingBox!.min.y;
    const spanY = Math.max(1e-5, geo.boundingBox!.max.y - minY);
    colorA.set(part.c);
    if (part.c2) colorB.set(part.c2);
    else colorB.copy(shadeOf(part.c));
    const tint = new Float32Array(count * 3);
    const emit = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      const t = (pos.getY(i) - minY) / spanY;
      tint[i * 3] = colorB.r + (colorA.r - colorB.r) * t;
      tint[i * 3 + 1] = colorB.g + (colorA.g - colorB.g) * t;
      tint[i * 3 + 2] = colorB.b + (colorA.b - colorB.b) * t;
      emit[i] = part.emit ?? 0;
    }
    geo.setAttribute('tint', new THREE.BufferAttribute(tint, 3));
    geo.setAttribute('emit', new THREE.BufferAttribute(emit, 1));

    // Point the texture coordinates at this part's tile on the atlas.
    const uv = geo.attributes.uv;
    const tile = Tile[part.tile ?? 'plain'];
    for (let i = 0; i < count; i++) {
      const [u, v] = tileUv(tile, uv.getX(i), uv.getY(i));
      uv.setXY(i, u, v);
    }

    // Move and turn the shape into place.
    const [rx, ry, rz] = part.rot ?? [0, 0, 0];
    euler.set(rx * DEG, ry * DEG, rz * DEG, 'ZYX');
    quat.setFromEuler(euler);
    const [x, y, z] = part.at ?? [0, 0, 0];
    matrix.compose(new THREE.Vector3(x, y, z), quat, one);
    geo.applyMatrix4(matrix);

    pieces.push(geo);
  }
  if (pieces.length === 0) return new THREE.BufferGeometry();
  const merged = mergeGeometries(pieces, false);
  pieces.forEach((g) => g.dispose());
  return merged ?? new THREE.BufferGeometry();
}

/** Builds a drawable mesh from a list of parts. */
export function buildMesh(parts: Part[], material: THREE.Material = litMaterial()): THREE.Mesh {
  return new THREE.Mesh(buildGeometry(parts), material);
}

/** Mirrors parts left-to-right, for the other arm, boot, and so on. */
export function mirrored(parts: Part[]): Part[] {
  return parts.map((p) => ({
    ...p,
    at: p.at ? [-p.at[0], p.at[1], p.at[2]] : undefined,
    rot: p.rot ? [p.rot[0], -p.rot[1], -p.rot[2]] : undefined,
  }));
}
