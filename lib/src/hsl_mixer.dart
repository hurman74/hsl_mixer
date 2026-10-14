import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'hsl_adjustment.dart';
import 'hsl_band.dart';

// Keep these in sync with shaders/hsl_mixer.frag.
const double _fullChroma = 0.2;
const double _lightnessScale = 0.5;

const List<HslAdjustment> _noAdjustments = [
  HslAdjustment.zero,
  HslAdjustment.zero,
  HslAdjustment.zero,
  HslAdjustment.zero,
  HslAdjustment.zero,
  HslAdjustment.zero,
  HslAdjustment.zero,
  HslAdjustment.zero,
];

/// A set of per-color HSL adjustments: one [HslAdjustment] for each
/// [HslBand].
///
/// Use it with [HslMixerImage] to show an edited photo (the work is done on
/// the GPU), or call [applyToImage], [applyToRgba] or [applyToColor] to get
/// the edited pixels in Dart, for example to save the result. Both paths use
/// the same math, so what you export matches what you saw.
///
/// ```dart
/// final mixer = HslMixer({
///   HslBand.blue: HslAdjustment(saturation: 0.4, lightness: -0.3),
///   HslBand.orange: HslAdjustment(hue: -0.2),
/// });
/// ```
@immutable
class HslMixer {
  /// Creates a mixer with the given adjustments. Bands that aren't in
  /// [adjustments] are left unchanged.
  HslMixer([Map<HslBand, HslAdjustment> adjustments = const {}])
    : _bands = List<HslAdjustment>.unmodifiable([
        for (final band in HslBand.values)
          adjustments[band] ?? HslAdjustment.zero,
      ]);

  /// A mixer that changes nothing.
  const HslMixer.identity() : _bands = _noAdjustments;

  /// A mixer that applies the same [adjustment] to every band.
  ///
  /// Because band weights always add up to 1, this adjusts every colored
  /// pixel evenly, like a global hue/saturation control that leaves grays
  /// alone.
  HslMixer.all(HslAdjustment adjustment)
    : _bands = List<HslAdjustment>.filled(
        HslBand.values.length,
        adjustment,
        growable: false,
      );

  /// A mixer that removes the color from every band except [keep], the
  /// "color splash" effect (a red coat on a gray street, for example).
  ///
  /// Hues between a kept band and a removed one fade out gradually.
  HslMixer.only(Set<HslBand> keep)
    : _bands = List<HslAdjustment>.unmodifiable([
        for (final band in HslBand.values)
          keep.contains(band) ? HslAdjustment.zero : HslAdjustment.desaturate,
      ]);

  final List<HslAdjustment> _bands;

  /// The adjustment for [band].
  HslAdjustment operator [](HslBand band) => _bands[band.index];

  /// The adjustment of every band.
  Map<HslBand, HslAdjustment> get adjustments => {
    for (final band in HslBand.values) band: _bands[band.index],
  };

  /// Whether this mixer leaves every pixel unchanged.
  bool get isIdentity => _bands.every((adjustment) => adjustment.isZero);

  /// Returns a copy with [band] set to [adjustment].
  HslMixer withBand(HslBand band, HslAdjustment adjustment) {
    return HslMixer({...adjustments, band: adjustment});
  }

  /// Returns a copy with [band]'s adjustment replaced by the result of
  /// [update], which receives the current one.
  ///
  /// Handy for wiring up a slider:
  ///
  /// ```dart
  /// mixer.updateBand(HslBand.blue, (a) => a.copyWith(saturation: value));
  /// ```
  HslMixer updateBand(
    HslBand band,
    HslAdjustment Function(HslAdjustment current) update,
  ) {
    return withBand(band, update(this[band]));
  }

  /// Linearly interpolates between two mixers, band by band.
  ///
  /// A null argument is treated as [HslMixer.identity].
  static HslMixer lerp(HslMixer? a, HslMixer? b, double t) {
    final from = a ?? const HslMixer.identity();
    final to = b ?? const HslMixer.identity();
    return HslMixer({
      for (final band in HslBand.values)
        band: HslAdjustment.lerp(from[band], to[band], t),
    });
  }

  /// The values the shader takes, in uniform order: hue shifts in degrees,
  /// then saturation, then lightness, eight bands each.
  List<double> get shaderUniforms => [
    for (final a in _bands) a.hueDegrees,
    for (final a in _bands) a.clampedSaturation,
    for (final a in _bands) a.clampedLightness,
  ];

  /// Returns [color] with this mixer applied. The alpha is kept.
  Color applyToColor(Color color) {
    final out = Float64List(3);
    final p = _Params(this);
    _adjust(color.r, color.g, color.b, p, out);
    return Color.from(
      alpha: color.a,
      red: out[0],
      green: out[1],
      blue: out[2],
      colorSpace: color.colorSpace,
    );
  }

  /// Applies this mixer in place to [bytes], which hold pixels as 4 bytes
  /// each in RGBA order (the layout of [ui.ImageByteFormat.rawRgba] and
  /// [ui.ImageByteFormat.rawStraightRgba]).
  ///
  /// Set [premultiplied] to true if the color channels are premultiplied by
  /// alpha, as in [ui.ImageByteFormat.rawRgba]. Fully transparent pixels are
  /// left alone.
  ///
  /// This runs on the CPU and takes time proportional to the pixel count.
  /// For large photos, consider running it in an isolate (`compute`).
  void applyToRgba(Uint8List bytes, {bool premultiplied = false}) {
    if (bytes.length % 4 != 0) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'The length must be a multiple of 4 (one RGBA pixel is 4 bytes).',
      );
    }
    if (isIdentity) return;
    final p = _Params(this);
    final out = Float64List(3);
    for (var i = 0; i < bytes.length; i += 4) {
      final a = bytes[i + 3];
      if (a == 0) continue;
      double r = bytes[i].toDouble();
      double g = bytes[i + 1].toDouble();
      double b = bytes[i + 2].toDouble();
      final scale = premultiplied ? a.toDouble() : 255.0;
      r = (r / scale).clamp(0.0, 1.0);
      g = (g / scale).clamp(0.0, 1.0);
      b = (b / scale).clamp(0.0, 1.0);
      _adjust(r, g, b, p, out);
      bytes[i] = (out[0] * scale).round();
      bytes[i + 1] = (out[1] * scale).round();
      bytes[i + 2] = (out[2] * scale).round();
    }
  }

  /// Returns a new image with this mixer applied to [image].
  ///
  /// The work is done in Dart on the CPU, with the same math as
  /// [HslMixerImage], so the result matches what is shown on screen. Use it
  /// to export or save an edited photo. Encode the result with
  /// [ui.Image.toByteData] and [ui.ImageByteFormat.png].
  ///
  /// The caller owns the returned image and should dispose it when done.
  Future<ui.Image> applyToImage(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('Could not read the pixels of the image.');
    }
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    applyToRgba(bytes, premultiplied: true);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.width,
      height: image.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is HslMixer && listEquals(other._bands, _bands);

  @override
  int get hashCode => Object.hashAll(_bands);

  @override
  String toString() {
    final changed = [
      for (final band in HslBand.values)
        if (!this[band].isZero) '${band.name}: ${this[band]}',
    ];
    return changed.isEmpty
        ? 'HslMixer.identity()'
        : 'HslMixer(${changed.join(', ')})';
  }
}

/// Flattened band values, so the per-pixel loop doesn't allocate.
class _Params {
  _Params(HslMixer mixer) {
    for (var i = 0; i < _count; i++) {
      final a = mixer._bands[i];
      hue[i] = a.hueDegrees;
      saturation[i] = a.clampedSaturation;
      lightness[i] = a.clampedLightness;
      centers[i] = HslBand.values[i].centerHue;
    }
  }

  static final int _count = HslBand.values.length;

  final Float64List hue = Float64List(_count);
  final Float64List saturation = Float64List(_count);
  final Float64List lightness = Float64List(_count);
  final Float64List centers = Float64List(_count);
}

/// The per-pixel math. [r], [g] and [b] are straight (not premultiplied)
/// values from 0 to 1. Writes the result to [out].
void _adjust(double r, double g, double b, _Params p, Float64List out) {
  final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final chroma = maxC - minC;
  final l = (maxC + minC) / 2;
  if (chroma <= 0) {
    // Grays have no hue, and no band changes them.
    out[0] = r;
    out[1] = g;
    out[2] = b;
    return;
  }
  var s = chroma / (1 - (2 * l - 1).abs());
  if (s > 1) s = 1;
  double h;
  if (maxC == r) {
    h = ((g - b) / chroma) % 6;
  } else if (maxC == g) {
    h = (b - r) / chroma + 2;
  } else {
    h = (r - g) / chroma + 4;
  }
  h *= 60;

  // Blend the two bands around this hue.
  final count = p.centers.length;
  var i = count - 1;
  for (var j = 0; j < count - 1; j++) {
    if (h < p.centers[j + 1]) {
      i = j;
      break;
    }
  }
  final next = (i + 1) % count;
  final start = p.centers[i];
  final end = i == count - 1 ? 360.0 : p.centers[next];
  var t = (h - start) / (end - start);
  t = t * t * (3 - 2 * t);
  final dh = p.hue[i] * (1 - t) + p.hue[next] * t;
  var ds = p.saturation[i] * (1 - t) + p.saturation[next] * t;
  var dl = p.lightness[i] * (1 - t) + p.lightness[next] * t;

  // Near-gray pixels have no reliable hue, so they get less of the
  // saturation boost and lightness change.
  var f = chroma / _fullChroma;
  if (f > 1) f = 1;
  f = f * f * (3 - 2 * f);
  if (ds > 0) ds *= f;
  dl *= f * _lightnessScale;

  final nh = (h + dh) % 360;
  var ns = ds >= 0 ? s + (1 - s) * ds : s * (1 + ds);
  var nl = dl >= 0 ? l + (1 - l) * dl : l * (1 + dl);
  ns = ns.clamp(0.0, 1.0);
  nl = nl.clamp(0.0, 1.0);

  // HSL back to RGB.
  final c = (1 - (2 * nl - 1).abs()) * ns;
  final hp = nh / 60;
  final x = c * (1 - ((hp % 2) - 1).abs());
  double r1, g1, b1;
  if (hp < 1) {
    r1 = c;
    g1 = x;
    b1 = 0;
  } else if (hp < 2) {
    r1 = x;
    g1 = c;
    b1 = 0;
  } else if (hp < 3) {
    r1 = 0;
    g1 = c;
    b1 = x;
  } else if (hp < 4) {
    r1 = 0;
    g1 = x;
    b1 = c;
  } else if (hp < 5) {
    r1 = x;
    g1 = 0;
    b1 = c;
  } else {
    r1 = c;
    g1 = 0;
    b1 = x;
  }
  final m = nl - c / 2;
  out[0] = (r1 + m).clamp(0.0, 1.0);
  out[1] = (g1 + m).clamp(0.0, 1.0);
  out[2] = (b1 + m).clamp(0.0, 1.0);
}
