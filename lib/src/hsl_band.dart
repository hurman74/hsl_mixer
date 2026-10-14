/// One of the eight color ranges an HSL mixer adjusts, as in the HSL panel of
/// common photo editors.
///
/// Each band has a [centerHue]. A pixel whose hue sits between two centers is
/// adjusted by both neighbors, blended by how close it is to each, so edits
/// never leave hard edges between colors.
enum HslBand {
  /// Reds, centered at 0°.
  red(0),

  /// Oranges (and most skin tones), centered at 30°.
  orange(30),

  /// Yellows, centered at 60°.
  yellow(60),

  /// Greens, centered at 120°.
  green(120),

  /// Aquas and cyans, centered at 180°.
  aqua(180),

  /// Blues, centered at 240°.
  blue(240),

  /// Purples, centered at 270°.
  purple(270),

  /// Magentas and pinks, centered at 300°.
  magenta(300);

  const HslBand(this.centerHue);

  /// The hue, in degrees from 0 up to (not including) 360, where this band
  /// has full effect.
  final double centerHue;

  /// How strongly this band affects a pixel with the given [hue], from 0
  /// (not at all) to 1 (fully).
  ///
  /// [hue] is in degrees and may be outside 0 to 360; it wraps around. The
  /// weights of all bands add up to 1 for every hue, so setting every band to
  /// the same adjustment is the same as adjusting the whole image.
  double weightFor(double hue) => bandWeights(hue)[index];

  /// The weight of every band for the given [hue], indexed by
  /// [HslBand.index]. See [weightFor].
  static List<double> bandWeights(double hue) {
    final h = hue % 360;
    final weights = List<double>.filled(values.length, 0);
    final count = values.length;
    for (var i = 0; i < count; i++) {
      final start = values[i].centerHue;
      final end = i == count - 1 ? 360.0 : values[i + 1].centerHue;
      if (h < end) {
        final t = _ease((h - start) / (end - start));
        weights[i] = 1 - t;
        weights[(i + 1) % count] = t;
        break;
      }
    }
    return weights;
  }

  static double _ease(double t) => t * t * (3 - 2 * t);
}
