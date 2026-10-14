import 'package:flutter/animation.dart';

import 'hsl_mixer.dart';

/// Interpolates between two [HslMixer]s, for animating edits (fading a
/// "before/after" toggle, for example).
///
/// A null [begin] or [end] is treated as [HslMixer.identity].
class HslMixerTween extends Tween<HslMixer> {
  /// Creates a tween between [begin] and [end].
  HslMixerTween({super.begin, super.end});

  @override
  HslMixer lerp(double t) => HslMixer.lerp(begin, end, t);
}
