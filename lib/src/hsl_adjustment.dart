import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';

/// How much to change the hue, saturation and lightness of one color band.
///
/// All three values range from -1 to 1, where 0 means no change, the same
/// scale as the sliders of a photo editor's HSL panel. Values outside that
/// range are clamped.
@immutable
class HslAdjustment {
  /// Creates an adjustment. Every value defaults to 0, which is no change.
  const HslAdjustment({this.hue = 0, this.saturation = 0, this.lightness = 0});

  /// An adjustment that changes nothing.
  static const HslAdjustment zero = HslAdjustment();

  /// An adjustment that removes all color from a band, leaving it gray.
  static const HslAdjustment desaturate = HslAdjustment(saturation: -1);

  /// The hue shift, in degrees, that a [hue] of 1 (or -1) gives.
  ///
  /// That is far enough to turn a band into its neighbor (orange into yellow,
  /// for example) without wrapping all the way around the color wheel.
  static const double maxHueShiftDegrees = 30;

  /// Rotates the band's colors around the color wheel.
  ///
  /// Positive values move toward the next band (red toward orange, blue
  /// toward purple); negative values move the other way. 1 is a shift of
  /// [maxHueShiftDegrees].
  final double hue;

  /// Makes the band's colors more vivid (positive) or more gray (negative).
  ///
  /// -1 removes the color entirely. 1 makes clearly colored pixels fully
  /// saturated; near-gray pixels get a smaller boost, so noise and neutral
  /// tones don't turn into color.
  final double saturation;

  /// Makes the band's colors lighter (positive) or darker (negative).
  ///
  /// 1 moves a color halfway to white, and -1 halfway to black. Grays are
  /// not affected, because they don't belong to any band.
  final double lightness;

  /// Whether this adjustment changes nothing.
  bool get isZero =>
      _clamp(hue) == 0 && _clamp(saturation) == 0 && _clamp(lightness) == 0;

  /// The hue shift in degrees, after clamping.
  double get hueDegrees => _clamp(hue) * maxHueShiftDegrees;

  /// [saturation], clamped to the range -1 to 1.
  double get clampedSaturation => _clamp(saturation);

  /// [lightness], clamped to the range -1 to 1.
  double get clampedLightness => _clamp(lightness);

  /// Returns a copy with the given values replaced.
  HslAdjustment copyWith({double? hue, double? saturation, double? lightness}) {
    return HslAdjustment(
      hue: hue ?? this.hue,
      saturation: saturation ?? this.saturation,
      lightness: lightness ?? this.lightness,
    );
  }

  /// Linearly interpolates between two adjustments.
  ///
  /// A null argument is treated as [zero].
  static HslAdjustment lerp(HslAdjustment? a, HslAdjustment? b, double t) {
    final from = a ?? zero;
    final to = b ?? zero;
    return HslAdjustment(
      hue: lerpDouble(from.hue, to.hue, t)!,
      saturation: lerpDouble(from.saturation, to.saturation, t)!,
      lightness: lerpDouble(from.lightness, to.lightness, t)!,
    );
  }

  static double _clamp(double value) => value.clamp(-1.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is HslAdjustment &&
      other.hue == hue &&
      other.saturation == saturation &&
      other.lightness == lightness;

  @override
  int get hashCode => Object.hash(hue, saturation, lightness);

  @override
  String toString() =>
      'HslAdjustment(hue: $hue, saturation: $saturation, '
      'lightness: $lightness)';
}
