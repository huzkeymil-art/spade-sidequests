import * as THREE from 'three';
import { getAtlas, getGlowTexture } from './textures';

// The lighting recipe for the whole scene.
//
// Modern 3D works out light for every single pixel. Late-90s consoles could
// only afford to work it out at the corners of each triangle, then smoothly
// blend between the corners. On chunky models that gives soft gradients
// instead of crisp highlights, and it is the look these shaders recreate.

// Colours are used exactly as typed, with no behind-the-scenes conversion.
// The dither pass at the end expects plain "what you type is what you see" values.
THREE.ColorManagement.enabled = false;

/** Light and fog settings shared by every material, so changing one value updates the whole scene. */
export const world = {
  uAtlas: { value: null as THREE.Texture | null },
  uAmbient: { value: new THREE.Color(0.11, 0.15, 0.16) },
  uMoonDir: { value: new THREE.Vector3(0.45, 0.6, -0.66).normalize() },
  uMoonColor: { value: new THREE.Color(0.4, 0.58, 0.66) },
  uLampPos: { value: new THREE.Vector3(-0.95, 0.32, 0.55) },
  uLampColor: { value: new THREE.Color(1.0, 0.6, 0.22) },
  uLampRange: { value: 5 },
  uGlowPos: { value: new THREE.Vector3(0, 1, 0) },
  uGlowColor: { value: new THREE.Color(0, 0, 0) },
  uGlowRange: { value: 4 },
  uFogColor: { value: new THREE.Color(0x1c2a2a) },
  uFogNear: { value: 9 },
  uFogFar: { value: 50 },
  uTime: { value: 0 },
};

const litVertex = /* glsl */ `
attribute vec3 tint;
attribute float emit;

uniform vec3 uAmbient;
uniform vec3 uMoonDir;
uniform vec3 uMoonColor;
uniform vec3 uLampPos;
uniform vec3 uLampColor;
uniform float uLampRange;
uniform vec3 uGlowPos;
uniform vec3 uGlowColor;
uniform float uGlowRange;
uniform float uFogNear;
uniform float uFogFar;

varying vec3 vLight;
varying vec3 vTint;
varying vec2 vUv;
varying float vFog;
varying float vEmit;

vec3 pointLight(vec3 pos, vec3 n, vec3 lightPos, vec3 color, float range) {
  vec3 toLight = lightPos - pos;
  float dist = length(toLight);
  float fade = clamp(1.0 - dist / range, 0.0, 1.0);
  fade *= fade;
  // "Wrapped" lighting: surfaces facing slightly away still catch a little light.
  float facing = max(dot(n, toLight / max(dist, 0.001)), 0.0) * 0.8 + 0.2;
  return color * fade * facing;
}

void main() {
  vec4 worldPos = modelMatrix * vec4(position, 1.0);
  vec3 n = normalize(mat3(modelMatrix) * normal);

  vec3 light = uAmbient * (0.75 + 0.45 * (n.y * 0.5 + 0.5));
  light += uMoonColor * max(dot(n, uMoonDir), 0.0);
  light += pointLight(worldPos.xyz, n, uLampPos, uLampColor, uLampRange);
  light += pointLight(worldPos.xyz, n, uGlowPos, uGlowColor, uGlowRange);

  vLight = light;
  vTint = tint;
  vUv = uv;
  vEmit = emit;

  vec4 viewPos = viewMatrix * worldPos;
  vFog = clamp((-viewPos.z - uFogNear) / (uFogFar - uFogNear), 0.0, 1.0);
  gl_Position = projectionMatrix * viewPos;
}
`;

const litFragment = /* glsl */ `
uniform sampler2D uAtlas;
uniform vec3 uFogColor;
uniform float uFlash;
uniform float uShade;

varying vec3 vLight;
varying vec3 vTint;
varying vec2 vUv;
varying float vFog;
varying float vEmit;

void main() {
  vec3 surface = vTint * texture2D(uAtlas, vUv).rgb * 1.25;
  vec3 color = mix(surface * vLight, surface, vEmit) * uShade;
  color += uFlash;
  color = mix(color, uFogColor, vFog * (1.0 - vEmit * 0.5));
  gl_FragColor = vec4(color, 1.0);
}
`;

/** The standard material: vertex-lit, tinted, textured from the atlas, fogged. */
function makeLitMaterial(): THREE.ShaderMaterial {
  world.uAtlas.value = getAtlas();
  return new THREE.ShaderMaterial({
    uniforms: {
      ...world,
      uFlash: { value: 0 },
      uShade: { value: 1 },
    },
    vertexShader: litVertex,
    fragmentShader: litFragment,
  });
}

let sharedLit: THREE.ShaderMaterial | null = null;
/** One lit material instance reused by most meshes. */
export function litMaterial(): THREE.ShaderMaterial {
  if (!sharedLit) sharedLit = makeLitMaterial();
  return sharedLit;
}

// ---------------------------------------------------------------------------
// Glow sprites: flat squares that always face the camera and add light on top
// of whatever is behind them. Used for the flame, halos and bursts.

const glowVertex = /* glsl */ `
uniform float uSize;
varying vec2 vUv;
void main() {
  vUv = uv;
  vec4 center = modelViewMatrix * vec4(0.0, 0.0, 0.0, 1.0);
  vec2 scale = vec2(length(modelMatrix[0].xyz), length(modelMatrix[1].xyz));
  center.xy += position.xy * scale * uSize;
  gl_Position = projectionMatrix * center;
}
`;

const glowFragment = /* glsl */ `
uniform sampler2D uMap;
uniform vec3 uColor;
uniform float uStrength;
varying vec2 vUv;
void main() {
  float a = texture2D(uMap, vUv).r;
  gl_FragColor = vec4(uColor * a * uStrength, 1.0);
}
`;

const glowGeometry = new THREE.PlaneGeometry(1, 1);

export interface GlowSprite extends THREE.Mesh {
  material: THREE.ShaderMaterial;
}

/** A camera-facing blob of additive light. */
export function makeGlow(color: THREE.ColorRepresentation, size: number, strength = 1): GlowSprite {
  const material = new THREE.ShaderMaterial({
    uniforms: {
      uMap: { value: getGlowTexture() },
      uColor: { value: new THREE.Color(color) },
      uStrength: { value: strength },
      uSize: { value: size },
    },
    vertexShader: glowVertex,
    fragmentShader: glowFragment,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    transparent: true,
  });
  const mesh = new THREE.Mesh(glowGeometry, material) as unknown as GlowSprite;
  mesh.frustumCulled = false;
  mesh.renderOrder = 10;
  return mesh;
}

// ---------------------------------------------------------------------------
// Decals: small pixel-art pictures stuck onto a surface (the face, the runes).

const decalVertex = /* glsl */ `
uniform float uFogNear;
uniform float uFogFar;
uniform vec2 uUvOffset;
uniform vec2 uUvScale;
varying vec2 vUv;
varying float vFog;
void main() {
  vUv = uv * uUvScale + uUvOffset;
  vec4 viewPos = modelViewMatrix * vec4(position, 1.0);
  vFog = clamp((-viewPos.z - uFogNear) / (uFogFar - uFogNear), 0.0, 1.0);
  gl_Position = projectionMatrix * viewPos;
}
`;

const decalFragment = /* glsl */ `
uniform sampler2D uMap;
uniform vec3 uColor;
uniform vec3 uFogColor;
uniform float uTintOnly;
varying vec2 vUv;
varying float vFog;
void main() {
  vec4 texel = texture2D(uMap, vUv);
  if (texel.a < 0.5) discard;
  // uTintOnly = 1 ignores the picture's own colours and uses uColor (for glowing runes).
  vec3 color = mix(texel.rgb * uColor, uColor, uTintOnly);
  color = mix(color, uFogColor, vFog * 0.6);
  gl_FragColor = vec4(color, 1.0);
}
`;

export function makeDecalMaterial(map: THREE.Texture, color: THREE.ColorRepresentation = 0xffffff, tintOnly = false) {
  return new THREE.ShaderMaterial({
    uniforms: {
      uMap: { value: map },
      uColor: { value: new THREE.Color(color) },
      uTintOnly: { value: tintOnly ? 1 : 0 },
      uUvOffset: { value: new THREE.Vector2(0, 0) },
      uUvScale: { value: new THREE.Vector2(1, 1) },
      uFogColor: world.uFogColor,
      uFogNear: world.uFogNear,
      uFogFar: world.uFogFar,
    },
    vertexShader: decalVertex,
    fragmentShader: decalFragment,
    polygonOffset: true,
    polygonOffsetFactor: -2,
    polygonOffsetUnits: -2,
  });
}
