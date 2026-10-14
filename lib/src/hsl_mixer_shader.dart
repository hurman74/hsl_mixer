/// @docImport 'hsl_mixer_image.dart';
library;

import 'dart:ui' as ui;

/// Loads the fragment shader that [HslMixerImage] uses, once per app.
///
/// You don't have to call anything here: the widgets load the shader on
/// their own. Call [precache] early (for example in `main` or before
/// opening an editor screen) so the first edited frame isn't delayed.
abstract final class HslMixerShader {
  static const String _asset = 'shaders/hsl_mixer.frag';

  static Future<ui.FragmentProgram>? _program;
  static ui.FragmentProgram? _loaded;

  /// The shader program if it has finished loading, or null.
  static ui.FragmentProgram? get loaded => _loaded;

  /// Loads the shader program, or returns the one already loaded.
  ///
  /// If loading fails, the error is passed on and the next call tries again.
  static Future<ui.FragmentProgram> load() {
    return _program ??= _fromAssets().then(
      (program) => _loaded = program,
      onError: (Object error, StackTrace stack) {
        _program = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  static Future<ui.FragmentProgram> _fromAssets() async {
    try {
      // The key when this package is a dependency of the app.
      return await ui.FragmentProgram.fromAsset('packages/hsl_mixer/$_asset');
    } catch (_) {
      // The key when this package is the root, as in its own tests.
      return ui.FragmentProgram.fromAsset(_asset);
    }
  }

  /// Starts loading the shader and completes when it's ready.
  static Future<void> precache() => load();
}
