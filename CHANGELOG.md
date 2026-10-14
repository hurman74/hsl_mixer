## 0.1.0

- Initial release.
- `HslMixer` with eight color bands (`HslBand`) and per-band
  `HslAdjustment`s for hue, saturation and lightness, plus `HslMixer.only`
  (color splash) and `HslMixer.all` presets.
- `HslMixerImage` and `RawHslMixerImage` render edits on the GPU with a
  fragment shader.
- `applyToImage`, `applyToRgba` and `applyToColor` apply the same math in
  Dart, for export.
- `HslMixer.lerp` and `HslMixerTween` for animation.
