#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform vec4 uAudio;  // Bass, mids, treble, bass transients.
uniform vec3 uAccent;
uniform vec3 uShade;
uniform vec3 uHighlight;
uniform float uDark;
uniform float uEffect;

out vec4 fragColor;

vec2 rotatePlane(vec2 p, float angle) {
  float s = sin(angle);
  float c = cos(angle);
  return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float gaussian(float x) {
  return exp(-x * x);
}

vec3 cellRandom(vec2 cell) {
  vec3 n = fract(cell.xyx * vec3(0.1031, 0.1030, 0.0973));
  n += dot(n, n.yzx + 19.19);
  return fract((n.xxy + n.yzz) * n.zyx);
}

float cloudNoise(vec2 p) {
  vec2 cell = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float row0 = mix(cellRandom(cell).x, cellRandom(cell + vec2(1, 0)).x, f.x);
  float row1 = mix(cellRandom(cell + vec2(0, 1)).x,
                   cellRandom(cell + vec2(1, 1)).x, f.x);
  return mix(row0, row1, f.y);
}

vec3 aurora(vec2 p) {
  p = rotatePlane(p, -0.22);
  vec3 light = 0.48 * uShade * gaussian((p.y + 0.32) * 1.7);

  // Each curtain has a bright folded hem and a taller, translucent veil.
  for (int layer = 0; layer < 3; ++layer) {
    float depth = float(layer);
    float phase = uTime * (0.42 + 0.22 * depth) + 2.3 * depth;
    float x = p.x + 0.12 * depth;
    float fold = 0.12 * sin(x * (3.2 + depth) + phase)
               + 0.07 * sin(x * 8.6 - phase * 0.7);
    float height = p.y + 0.33 - depth * 0.19 - fold * (0.8 + uAudio.y * 0.7);
    float ribs = 0.63 + 0.37 * sin(17.0 * x + 2.7 * sin(5.0 * x - phase));
    float hem = gaussian(height * (31.0 - 10.0 * uAudio.x));
    float veil = smoothstep(-0.055, 0.025, height)
               * gaussian(height * (4.15 - 1.15 * uAudio.x));
    float fringe = gaussian((height - 0.012) * 53.0) * ribs * uAudio.z;
    float hue = 0.5 + 0.5 * sin(3.6 * x - 1.6 * depth + 0.25 * phase);
    vec3 tint = mix(uShade, uAccent, hue);
    light += tint * (hem * (0.22 + 0.33 * uAudio.w)
        + veil * (0.17 + ribs * (0.43 + 0.19 * uAudio.y)))
        + uHighlight * fringe * 0.42;
  }
  return light;
}

vec3 nebula(vec2 p) {
  vec2 drift = vec2(0.07 * uTime, 0.045 * uTime);
  vec2 sky = rotatePlane(p, 0.43);
  float broad = cloudNoise(sky * 2.9 + drift);
  float detail = cloudNoise(sky * 6.0 - drift * 0.55);
  float cloud = smoothstep(0.23, 0.86, broad * 0.72 + detail * 0.28);
  float arm = sky.y - 0.16 * sin(sky.x * 3.6 + broad * 2.4);
  float dust = gaussian(arm * (3.8 - uAudio.x)) * cloud;
  vec3 light = uShade * 0.31 * gaussian(length(sky + vec2(0.42, -0.13)) * 1.65)
             + mix(uShade, uAccent, broad) * dust * (1.8 + 0.9 * uAudio.x);

  // Three depths use their own drift rate, point size and focus.
  for (int layer = 0; layer < 3; ++layer) {
    float depth = float(layer);
    float scale = 30.0 - 8.5 * depth;
    vec2 grid = sky * scale + drift * (0.7 + depth * depth * 1.45) + 137.0 * depth;
    vec3 seed = cellRandom(floor(grid));
    vec2 center = 0.21 + seed.xy * 0.58;
    float r = length(fract(grid) - center);
    float size = (0.022 + depth * 0.010) * (0.65 + 0.7 * seed.y);
    float twinkle = 0.68 + 0.32 * sin(uTime * (1.4 + seed.x) + seed.y * 91.0);
    float star = (1.0 - smoothstep(size * 0.18, size, r))
               + 0.32 * gaussian(r / (size * (1.45 + depth * 0.6)));
    light += mix(uHighlight, uAccent, seed.x * 0.6)
           * step(0.78 + 0.052 * depth, seed.z) * star * twinkle
           * (0.76 + uAudio.z * 1.04 + uAudio.w * 0.27);
  }
  return light;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = (uv - 0.5) * uSize / min(uSize.x, uSize.y);
  p.y = -p.y;
  vec3 light = uEffect < 1.5 ? aurora(p) : nebula(p);

  float luminance = max(light.r, max(light.g, light.b));
  float strength = smoothstep(0.015, 0.39, max(uAudio.x, max(uAudio.y, uAudio.z)));
  float tone = 1.0 - exp(-luminance * 1.6);
  vec3 hue = light / max(0.001, luminance);
  vec3 color = hue * mix(0.80 + 0.16 * tone, 0.38 + 0.62 * tone, uDark);
  // Soften the header and controls at the edges of the stage.
  float edges = 0.63 + 0.37 * smoothstep(0.0, 0.19, min(uv.y, 1.0 - uv.y));
  float alpha = tone * strength * edges * uIntensity;
  fragColor = vec4(color * alpha, alpha);
}
