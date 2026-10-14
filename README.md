# hsl_mixer

Per-color HSL adjustment for photos in Flutter, like the HSL panel in photo
editors. Make the blues of a sky deeper without touching skin tones, shift
greens toward yellow, or turn everything gray except one color.

- **Eight color bands**: red, orange, yellow, green, aqua, blue, purple and
  magenta, each with its own hue, saturation and lightness.
- **Smooth**: colors between two bands are blended, so edits never leave hard
  edges, and grays are never tinted.
- **Fast on screen**: a fragment shader does the work on the GPU, so the
  sliders stay live even on large photos.
- **Same result on export**: a pure Dart version of the same math edits
  `ui.Image`s and raw RGBA bytes, so the file you save matches the preview.
- No dependencies and no native code.

## Install

```sh
flutter pub add hsl_mixer
```

## Usage

Show an edited image from any `ImageProvider`:

```dart
import 'package:hsl_mixer/hsl_mixer.dart';

HslMixerImage(
  image: const AssetImage('assets/beach.jpg'),
  mixer: HslMixer({
    HslBand.blue: const HslAdjustment(saturation: 0.4, lightness: -0.3),
    HslBand.aqua: const HslAdjustment(hue: 0.3),
    HslBand.orange: const HslAdjustment(lightness: 0.15),
  }),
  fit: BoxFit.cover,
)
```

All values are in `[-1, 1]`, where 0 means no change:

| | Negative | Positive |
|---|---|---|
| `hue` | toward the previous band (blue → aqua), up to 30° | toward the next band (blue → purple), up to 30° |
| `saturation` | grayer; -1 removes the color | more vivid; 1 is fully saturated |
| `lightness` | darker; -1 is halfway to black | lighter; 1 is halfway to white |

Wire a band to a slider:

```dart
Slider(
  value: mixer[HslBand.green].saturation,
  min: -1,
  max: 1,
  onChanged: (v) => setState(() {
    mixer = mixer.updateBand(HslBand.green, (a) => a.copyWith(saturation: v));
  }),
)
```

Presets:

```dart
HslMixer.only({HslBand.red});                         // color splash: keep only reds
HslMixer.all(const HslAdjustment(saturation: -0.5)); // global, grays untouched
```

### Export the edited photo

`HslMixerImage` only changes what's painted. To save the result, apply the
same mixer in Dart:

```dart
final ui.Image edited = await mixer.applyToImage(original);
final png = await edited.toByteData(format: ui.ImageByteFormat.png);
edited.dispose();
```

Or edit raw pixels directly, for example in an isolate:

```dart
mixer.applyToRgba(bytes);                     // straight alpha (rawStraightRgba)
mixer.applyToRgba(bytes, premultiplied: true); // premultiplied (rawRgba)
```

`applyToColor` edits a single `Color`.

### Already have a `ui.Image`?

Use `RawHslMixerImage`, the counterpart of `RawImage`:

```dart
RawHslMixerImage(image: myImage, mixer: mixer, fit: BoxFit.contain)
```

### Animate

`HslMixer.lerp` and `HslMixerTween` interpolate band by band. For example,
fade a before/after toggle with `HslMixerTween(end: mixer).transform(t)`.

### Load the shader early

The widgets load the shader on their own, and paint nothing while it loads
(at most a frame or two). To avoid even that, call this before showing an
edited image:

```dart
await HslMixerShader.precache();
```

## Why this package

Flutter's `ColorFiltered` applies a single color matrix to every pixel. It can
change the saturation or hue of the whole image, but not of one color range.
Stacking filters doesn't help, because each one still affects every pixel.
This was requested in
[flutter/flutter#80820](https://github.com/flutter/flutter/issues/80820) and
labeled "would be a good package".

Existing image filter packages offer whole-image adjustments (hue, saturation,
vibrance, lookup tables), and Photoshop preset codecs read and write settings
without rendering them. `hsl_mixer` renders per-color edits and gives you the
matching pixels for export.

## How it works

Each pixel is converted to HSL. Its hue is split between the two nearest band
centers (0°, 30°, 60°, 120°, 180°, 240°, 270° and 300°) with a smooth ramp,
and the two bands' adjustments are blended by those weights. The weights
always add up to 1, so giving every band the same adjustment is the same as
a global one. Saturation boosts and lightness changes fade out for near-gray
pixels, which have no reliable hue. The shader and the Dart code do the same
math, and the test suite renders the shader and checks that every pixel
matches the Dart result to within rounding.

## Limitations

- It edits images, not arbitrary widgets. Applying a shader to a widget
  subtree needs `ImageFilter.shader`, which only works with Impeller.
- The math runs in sRGB, on the image's 8-bit channels. Wide-gamut images are
  treated as sRGB.
- The bands and their centers are fixed. There is no custom range picker.
- The CPU path (`applyToImage`, `applyToRgba`) takes time proportional to
  the pixel count. Run it off the UI thread for large photos.
- The web needs the CanvasKit or Skwasm renderer (the default), since the
  HTML renderer had no fragment shader support.
