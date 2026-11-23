#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform vec4 uAudio;  // 低频、中频、高频、低频瞬态
uniform vec3 uAccent;
uniform vec3 uShade;
uniform vec3 uHighlight;
uniform float uDark;
uniform float uEffect;
uniform vec3 uFluidTopLeft;
uniform vec3 uFluidTopRight;
uniform vec3 uFluidBottomLeft;
uniform vec3 uFluidBottomRight;
uniform vec3 uFluidPaper;
uniform vec3 uFluidMotion;  // 漂移、旋转、起伏
uniform float uThemeTint;

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

  // 每道光幕包含明亮的折叠边缘和更高的半透明帘面。
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

  // 三层景深分别使用各自的漂移速度、点尺寸和清晰度。
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

vec2 curlAround(vec2 p, vec2 center, float spin) {
  vec2 delta = p - center;
  return center + rotatePlane(delta, spin / (1.0 + 6.0 * dot(delta, delta)));
}

vec4 fluid(vec2 uv) {
  // 背景以慢于大屏时钟的速度变化，使流动更柔和。
  float t = uTime * 0.55;
  vec2 p = (uv - 0.5) * uSize / max(1.0, min(uSize.x, uSize.y));
  vec2 q = p;
  if (uFluidMotion.x > 0.0) {
    // 上下区域的颜色沿不同斜向缓慢流动，使画面产生局部拉伸。
    vec2 drift = vec2(0.30 * sin(2.7 * p.y - 0.55 * t),
                       0.20 * cos(2.3 * p.x + 0.42 * t));
    q += uFluidMotion.x * drift;
  }
  if (uFluidMotion.y > 0.0) {
    // 偏心旋涡使中心比边缘转得更快。
    vec2 center = vec2(0.18 * sin(0.26 * t), -0.13 * cos(0.22 * t));
    vec2 orbit = curlAround(p, center, 1.05 + 0.85 * sin(0.36 * t));
    q += uFluidMotion.y * (orbit - p);
  }
  if (uFluidMotion.z > 0.0) {
    // 宽缓的斜向波将色彩带过画面，再使其回流。
    vec2 current = vec2(0.82, 0.57);
    float swell = sin(dot(p, current) * 3.6 - 0.62 * t);
    float undertow = cos(dot(p, current.yx) * 3.0 + 0.40 * t);
    q += uFluidMotion.z * (current * (0.18 + 0.08 * uAudio.x) * swell
                           + vec2(-0.08, 0.10) * undertow);
  }
  q *= 1.0 + 0.015 * sin(0.22 * t);
  q *= 1.0 - 0.04 * uAudio.x - 0.02 * uAudio.w;

  // 两组漂移的噪声场扭曲颜色坐标，形成缓慢移动的褶皱。
  vec2 warp = vec2(
      cloudNoise(q * 1.9 + vec2(0.16 * t, -0.11 * t)),
      cloudNoise(q * 1.9 + vec2(3.7 - 0.12 * t, 1.9 + 0.14 * t))) - 0.5;
  vec2 s = q + warp * 0.62;

  // 对封面四个区域的取色做平滑混合。
  float mixX = 0.5 + 0.5 * sin(s.x * 1.9 + s.y * 1.4 + 0.16 * t);
  float mixY = 0.5 + 0.5 * sin(s.y * 1.6 - s.x * 1.1 - 0.12 * t + 1.4);
  mixX = smoothstep(0.12, 0.88, mixX);
  mixY = smoothstep(0.12, 0.88, mixY);
  vec3 top = mix(uFluidTopLeft, uFluidTopRight, mixX);
  vec3 bottom = mix(uFluidBottomLeft, uFluidBottomRight, mixX);
  vec3 pigment = mix(top, bottom, mixY);

  // 用柔和阴影和高光表现层次，避免硬边在大屏上形成可见条带。
  float sheen = 0.5 + 0.5 * sin(s.x * 2.4 + s.y * 1.7 + 0.15 * t + 1.2);
  pigment *= 0.96 + 0.08 * smoothstep(0.25, 0.80, sheen);
  pigment += uHighlight * smoothstep(0.52, 0.92, sheen) *
             (0.05 + 0.04 * uAudio.z);

  float center = 1.0 - smoothstep(0.0, 1.05, length(q));
  float presence = clamp(0.62 + 0.28 * center + 0.08 * mixY, 0.0, 1.0);
  vec3 color = mix(uFluidPaper, pigment, presence);
  color += uHighlight * smoothstep(0.80, 0.98, sheen) * (0.05 + 0.03 * uAudio.z);

  // 浅色主题下混入少量浅色，使封面配色与大屏底色协调。
  color = mix(color, uHighlight, uThemeTint * (0.08 + 0.08 * sheen));
  float luminance = dot(color, vec3(0.299, 0.587, 0.114));
  color = mix(vec3(luminance), color, 1.10);

  // 加入像素级抖动，减轻平滑渐变中的色阶断层。
  vec3 grain = cellRandom(FlutterFragCoord().xy);
  float alpha = mix(0.34, 1.0, uIntensity) * (0.95 + 0.05 * uAudio.x);
  return vec4((color + (grain - 0.5) * 0.006) * alpha, alpha);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  if (uEffect > 2.5) {
    fragColor = fluid(uv);
    return;
  }
  float strength = smoothstep(0.015, 0.39, max(uAudio.x, max(uAudio.y, uAudio.z)));
  // 逐渐减弱顶部和底部的背景强度，为页眉和控件留出空间。
  float edges = 0.63 + 0.37 * smoothstep(0.0, 0.19, min(uv.y, 1.0 - uv.y));
  float opacity = strength * edges * uIntensity;
  vec2 p = (uv - 0.5) * uSize / min(uSize.x, uSize.y);
  p.y = -p.y;
  vec3 light = uEffect < 1.5 ? aurora(p) : nebula(p);

  float luminance = max(light.r, max(light.g, light.b));
  float tone = 1.0 - exp(-luminance * 1.6);
  vec3 hue = light / max(0.001, luminance);
  vec3 color = hue * mix(0.80 + 0.16 * tone, 0.38 + 0.62 * tone, uDark);
  float alpha = tone * opacity;
  fragColor = vec4(color * alpha, alpha);
}
