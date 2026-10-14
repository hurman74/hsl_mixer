#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

// The rect the whole image is drawn into, in local coordinates:
// left, top, width, height.
uniform vec4 uDst;

// Per-band adjustments. The first vector of each pair holds red, orange,
// yellow and green; the second holds aqua, blue, purple and magenta.
// Hue shifts are in degrees; saturation and lightness are in [-1, 1].
uniform vec4 uHue0;
uniform vec4 uHue1;
uniform vec4 uSat0;
uniform vec4 uSat1;
uniform vec4 uLum0;
uniform vec4 uLum1;

uniform sampler2D uImage;

out vec4 fragColor;

// Keep in sync with lib/src/hsl_math.dart.
const float kFullChroma = 0.2;
const float kLightnessScale = 0.5;

vec3 rgbToHsl(vec3 c) {
  float maxC = max(c.r, max(c.g, c.b));
  float minC = min(c.r, min(c.g, c.b));
  float l = (maxC + minC) * 0.5;
  float d = maxC - minC;
  if (d <= 0.0) {
    return vec3(0.0, 0.0, l);
  }
  float s = min(1.0, d / (1.0 - abs(2.0 * l - 1.0)));
  float h;
  if (maxC == c.r) {
    h = mod((c.g - c.b) / d, 6.0);
  } else if (maxC == c.g) {
    h = (c.b - c.r) / d + 2.0;
  } else {
    h = (c.r - c.g) / d + 4.0;
  }
  return vec3(h * 60.0, s, l);
}

vec3 hslToRgb(vec3 hsl) {
  float c = (1.0 - abs(2.0 * hsl.z - 1.0)) * hsl.y;
  float hp = hsl.x / 60.0;
  float x = c * (1.0 - abs(mod(hp, 2.0) - 1.0));
  vec3 rgb;
  if (hp < 1.0) {
    rgb = vec3(c, x, 0.0);
  } else if (hp < 2.0) {
    rgb = vec3(x, c, 0.0);
  } else if (hp < 3.0) {
    rgb = vec3(0.0, c, x);
  } else if (hp < 4.0) {
    rgb = vec3(0.0, x, c);
  } else if (hp < 5.0) {
    rgb = vec3(x, 0.0, c);
  } else {
    rgb = vec3(c, 0.0, x);
  }
  return rgb + (hsl.z - c * 0.5);
}

float ease(float t) {
  return t * t * (3.0 - 2.0 * t);
}

// Splits a hue between the two band centers around it. The weights of all
// eight bands always add up to 1.
void bandWeights(float h, out vec4 w0, out vec4 w1) {
  w0 = vec4(0.0);
  w1 = vec4(0.0);
  float t;
  if (h < 30.0) {
    t = ease(h / 30.0);
    w0.x = 1.0 - t;
    w0.y = t;
  } else if (h < 60.0) {
    t = ease((h - 30.0) / 30.0);
    w0.y = 1.0 - t;
    w0.z = t;
  } else if (h < 120.0) {
    t = ease((h - 60.0) / 60.0);
    w0.z = 1.0 - t;
    w0.w = t;
  } else if (h < 180.0) {
    t = ease((h - 120.0) / 60.0);
    w0.w = 1.0 - t;
    w1.x = t;
  } else if (h < 240.0) {
    t = ease((h - 180.0) / 60.0);
    w1.x = 1.0 - t;
    w1.y = t;
  } else if (h < 270.0) {
    t = ease((h - 240.0) / 30.0);
    w1.y = 1.0 - t;
    w1.z = t;
  } else if (h < 300.0) {
    t = ease((h - 270.0) / 30.0);
    w1.z = 1.0 - t;
    w1.w = t;
  } else {
    t = ease((h - 300.0) / 60.0);
    w1.w = 1.0 - t;
    w0.x = t;
  }
}

vec3 adjust(vec3 rgb) {
  vec3 hsl = rgbToHsl(rgb);
  vec4 w0;
  vec4 w1;
  bandWeights(hsl.x, w0, w1);
  float dh = dot(w0, uHue0) + dot(w1, uHue1);
  float ds = dot(w0, uSat0) + dot(w1, uSat1);
  float dl = dot(w0, uLum0) + dot(w1, uLum1);

  // Near-gray pixels have no reliable hue, so they get less of the
  // saturation boost and lightness change.
  float chroma = max(rgb.r, max(rgb.g, rgb.b)) - min(rgb.r, min(rgb.g, rgb.b));
  float f = smoothstep(0.0, kFullChroma, chroma);
  if (ds > 0.0) {
    ds *= f;
  }
  dl *= f * kLightnessScale;

  float h = mod(hsl.x + dh, 360.0);
  float s = ds >= 0.0 ? hsl.y + (1.0 - hsl.y) * ds : hsl.y * (1.0 + ds);
  float l = dl >= 0.0 ? hsl.z + (1.0 - hsl.z) * dl : hsl.z * (1.0 + dl);
  return clamp(hslToRgb(vec3(h, clamp(s, 0.0, 1.0), clamp(l, 0.0, 1.0))),
      0.0, 1.0);
}

void main() {
  vec2 uv = (FlutterFragCoord().xy - uDst.xy) / uDst.zw;
  vec4 src = texture(uImage, uv);
  if (src.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 rgb = clamp(src.rgb / src.a, 0.0, 1.0);
  fragColor = vec4(adjust(rgb) * src.a, src.a);
}
