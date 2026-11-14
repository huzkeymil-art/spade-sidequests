import * as THREE from 'three';

// The final step of every frame.
//
// The 3D scene is first drawn small, into an off-screen picture. This pass
// then blows that picture up to fill the screen with hard-edged pixels, and
// "dithers" it: instead of thousands of smooth colour shades, it only allows a
// few dozen, and fakes the in-between shades with a checker-like pattern of
// dots. A newspaper photo does the same trick with black ink.

const vertex = /* glsl */ `
void main() {
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
`;

const fragment = /* glsl */ `
uniform sampler2D tScene;
uniform vec2 uLowSize;
uniform float uScale;
uniform float uLevels;
uniform float uSheetY;
uniform float uFade;
uniform vec3 uInk;
uniform float uTopShade;

// A repeating 4 x 4 pattern of thresholds between 0 and 1 (a "Bayer matrix").
float bayer2(vec2 a) {
  a = floor(a);
  return fract(a.x / 2.0 + a.y * a.y * 0.75);
}
float bayer4(vec2 a) {
  return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void main() {
  vec2 low = floor(gl_FragCoord.xy / uScale);
  vec3 color = texture2D(tScene, (low + 0.5) / uLowSize).rgb;
  float threshold = bayer4(low);
  float fromTop = uLowSize.y - 1.0 - low.y;

  // Darken the very top a little so the level and streak stay readable.
  float top = clamp(1.0 - fromTop / (uLowSize.y * 0.16), 0.0, 1.0);
  color *= 1.0 - top * top * uTopShade;

  // Snap each colour channel to the nearest allowed shade, using the pattern
  // to decide which pixels round up and which round down.
  color = floor(color * uLevels + threshold) / uLevels;

  // Dissolve into the ink-coloured panel below, using the same dot pattern.
  float fade = clamp((fromTop - (uSheetY - uFade)) / uFade, 0.0, 1.0);
  if (fade * fade > threshold) color = uInk;

  gl_FragColor = vec4(color, 1.0);
}
`;

export class PostPass {
  readonly scene = new THREE.Scene();
  readonly camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  readonly material: THREE.ShaderMaterial;

  constructor() {
    this.material = new THREE.ShaderMaterial({
      uniforms: {
        tScene: { value: null },
        uLowSize: { value: new THREE.Vector2(1, 1) },
        uScale: { value: 4 },
        uLevels: { value: 24 },
        uSheetY: { value: 1e6 },
        uFade: { value: 20 },
        uInk: { value: new THREE.Color(0x0d0f0c) },
        uTopShade: { value: 0.45 },
      },
      vertexShader: vertex,
      fragmentShader: fragment,
      depthTest: false,
      depthWrite: false,
    });
    // One big triangle that covers the whole screen.
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute([-1, -1, 0, 3, -1, 0, -1, 3, 0], 3));
    const mesh = new THREE.Mesh(geo, this.material);
    mesh.frustumCulled = false;
    this.scene.add(mesh);
  }
}
