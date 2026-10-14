import 'package:flutter/widgets.dart';

import 'hsl_mixer.dart';
import 'raw_hsl_mixer_image.dart';

/// Shows an image with per-color HSL adjustments applied, on the GPU.
///
/// Works with any [ImageProvider] ([AssetImage], [NetworkImage],
/// [FileImage], [MemoryImage], ...). Changing [mixer] only repaints, so it's
/// cheap enough to drive straight from a slider or an animation.
///
/// ```dart
/// HslMixerImage(
///   image: const AssetImage('assets/beach.jpg'),
///   mixer: HslMixer({
///     HslBand.blue: const HslAdjustment(saturation: 0.5, lightness: -0.2),
///   }),
/// )
/// ```
///
/// To save the edited photo, decode it and call [HslMixer.applyToImage],
/// which gives the same result in Dart.
class HslMixerImage extends StatefulWidget {
  /// Creates a widget that shows [image] with [mixer] applied.
  const HslMixerImage({
    super.key,
    required this.image,
    required this.mixer,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.errorBuilder,
  });

  /// The image to show.
  final ImageProvider image;

  /// The adjustments to apply.
  final HslMixer mixer;

  /// If non-null, the width of the widget.
  final double? width;

  /// If non-null, the height of the widget.
  final double? height;

  /// How to fit the image into the widget's box.
  final BoxFit fit;

  /// How to align the image within the widget's box.
  final AlignmentGeometry alignment;

  /// A description of the image for screen readers.
  final String? semanticLabel;

  /// Whether to leave this image out of the semantics tree.
  final bool excludeFromSemantics;

  /// Builds a widget to show if the image fails to load. If null, the error
  /// is reported to [FlutterError.onError] and nothing is shown.
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<HslMixerImage> createState() => _HslMixerImageState();
}

class _HslMixerImageState extends State<HslMixerImage> {
  ImageStream? _stream;
  ImageInfo? _info;
  Object? _error;
  StackTrace? _stackTrace;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImage,
    onError: _onError,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(HslMixerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image ||
        widget.errorBuilder != oldWidget.errorBuilder) {
      _resolve();
    }
  }

  void _resolve() {
    final stream = widget.image.resolve(
      createLocalImageConfiguration(
        context,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null,
      ),
    );
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream;
    stream.addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    setState(() {
      _info?.dispose();
      _info = info;
      _error = null;
      _stackTrace = null;
    });
  }

  void _onError(Object error, StackTrace? stackTrace) {
    if (widget.errorBuilder == null) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'hsl_mixer',
          context: ErrorDescription('while loading an image for HslMixerImage'),
        ),
      );
    }
    setState(() {
      _error = error;
      _stackTrace = stackTrace;
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    _info = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _error!, _stackTrace);
    }
    Widget result = RawHslMixerImage(
      image: _info?.image,
      mixer: widget.mixer,
      width: widget.width,
      height: widget.height,
      scale: _info?.scale ?? 1.0,
      fit: widget.fit,
      alignment: widget.alignment,
    );
    if (!widget.excludeFromSemantics) {
      result = Semantics(
        container: widget.semanticLabel != null,
        image: true,
        label: widget.semanticLabel ?? '',
        child: result,
      );
    }
    return result;
  }
}
