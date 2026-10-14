import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'hsl_mixer.dart';
import 'hsl_mixer_shader.dart';

/// Paints a decoded [ui.Image] with an [HslMixer] applied, on the GPU.
///
/// This is the [HslMixerImage] counterpart of [RawImage]: it takes an image
/// you've already decoded and doesn't manage its lifetime. Most apps should
/// use [HslMixerImage], which loads any [ImageProvider].
///
/// Sizing follows [RawImage]: without [width] and [height], the widget is as
/// big as the image (divided by [scale]) while fitting the constraints, and
/// keeps its aspect ratio.
///
/// Until the shader has loaded (see [HslMixerShader.precache]), nothing is
/// painted, unless [mixer] is the identity. If the shader can't load at all,
/// the error is reported to [FlutterError.onError] and the image is painted
/// unedited.
class RawHslMixerImage extends StatefulWidget {
  /// Creates a widget that paints [image] with [mixer] applied.
  const RawHslMixerImage({
    super.key,
    required this.image,
    required this.mixer,
    this.width,
    this.height,
    this.scale = 1.0,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
  });

  /// The image to paint. The caller owns it and must keep it alive (not
  /// disposed) while this widget uses it.
  final ui.Image? image;

  /// The adjustments to apply.
  final HslMixer mixer;

  /// If non-null, the width of the widget.
  final double? width;

  /// If non-null, the height of the widget.
  final double? height;

  /// How many image pixels make one logical pixel, used for sizing.
  final double scale;

  /// How to fit the image into the widget's box.
  final BoxFit fit;

  /// How to align the image within the widget's box.
  final AlignmentGeometry alignment;

  @override
  State<RawHslMixerImage> createState() => _RawHslMixerImageState();
}

class _RawHslMixerImageState extends State<RawHslMixerImage> {
  ui.FragmentProgram? _program = HslMixerShader.loaded;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (_program == null) _load();
  }

  Future<void> _load() async {
    try {
      final program = await HslMixerShader.load();
      if (mounted) setState(() => _program = program);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'hsl_mixer',
          context: ErrorDescription('while loading the HSL mixer shader'),
        ),
      );
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _HslMixerImageBox(
      image: widget.image,
      mixer: widget.mixer,
      program: _program,
      paintUnedited: _failed,
      width: widget.width,
      height: widget.height,
      scale: widget.scale,
      fit: widget.fit,
      alignment: widget.alignment.resolve(Directionality.maybeOf(context)),
    );
  }
}

class _HslMixerImageBox extends LeafRenderObjectWidget {
  const _HslMixerImageBox({
    required this.image,
    required this.mixer,
    required this.program,
    required this.paintUnedited,
    required this.width,
    required this.height,
    required this.scale,
    required this.fit,
    required this.alignment,
  });

  final ui.Image? image;
  final HslMixer mixer;
  final ui.FragmentProgram? program;
  final bool paintUnedited;
  final double? width;
  final double? height;
  final double scale;
  final BoxFit fit;
  final Alignment alignment;

  @override
  RenderHslMixerImage createRenderObject(BuildContext context) {
    return RenderHslMixerImage(
      image: image,
      mixer: mixer,
      program: program,
      paintUnedited: paintUnedited,
      width: width,
      height: height,
      scale: scale,
      fit: fit,
      alignment: alignment,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHslMixerImage renderObject,
  ) {
    renderObject
      ..image = image
      ..mixer = mixer
      ..program = program
      ..paintUnedited = paintUnedited
      ..width = width
      ..height = height
      ..scale = scale
      ..fit = fit
      ..alignment = alignment;
  }
}

/// The render object behind [RawHslMixerImage].
///
/// Exposed so tests and custom layouts can inspect it; most code doesn't
/// need it.
class RenderHslMixerImage extends RenderBox {
  /// Creates the render object. See [RawHslMixerImage] for the arguments.
  RenderHslMixerImage({
    ui.Image? image,
    required HslMixer mixer,
    ui.FragmentProgram? program,
    bool paintUnedited = false,
    double? width,
    double? height,
    double scale = 1.0,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  }) : _image = image,
       _mixer = mixer,
       _program = program,
       _paintUnedited = paintUnedited,
       _width = width,
       _height = height,
       _scale = scale,
       _fit = fit,
       _alignment = alignment;

  ui.FragmentShader? _shader;

  /// The image to paint.
  ui.Image? get image => _image;
  ui.Image? _image;
  set image(ui.Image? value) {
    if (value == _image) return;
    if (value != null && _image != null && value.isCloneOf(_image!)) {
      _image = value;
      return;
    }
    final sizeChanged =
        value?.width != _image?.width || value?.height != _image?.height;
    _image = value;
    markNeedsPaint();
    if (sizeChanged && (_width == null || _height == null)) {
      markNeedsLayout();
    }
  }

  /// The adjustments to apply.
  HslMixer get mixer => _mixer;
  HslMixer _mixer;
  set mixer(HslMixer value) {
    if (value == _mixer) return;
    _mixer = value;
    markNeedsPaint();
  }

  /// The loaded shader program, or null while it is loading.
  ui.FragmentProgram? get program => _program;
  ui.FragmentProgram? _program;
  set program(ui.FragmentProgram? value) {
    if (value == _program) return;
    _program = value;
    _shader?.dispose();
    _shader = null;
    markNeedsPaint();
  }

  /// Whether to paint the image without edits when there is no [program].
  bool get paintUnedited => _paintUnedited;
  bool _paintUnedited;
  set paintUnedited(bool value) {
    if (value == _paintUnedited) return;
    _paintUnedited = value;
    markNeedsPaint();
  }

  /// If non-null, the width of the box.
  double? get width => _width;
  double? _width;
  set width(double? value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  /// If non-null, the height of the box.
  double? get height => _height;
  double? _height;
  set height(double? value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  /// How many image pixels make one logical pixel.
  double get scale => _scale;
  double _scale;
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    markNeedsLayout();
  }

  /// How to fit the image into the box.
  BoxFit get fit => _fit;
  BoxFit _fit;
  set fit(BoxFit value) {
    if (value == _fit) return;
    _fit = value;
    markNeedsPaint();
  }

  /// How to align the image within the box.
  Alignment get alignment => _alignment;
  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsPaint();
  }

  Size _sizeFor(BoxConstraints constraints) {
    constraints = BoxConstraints.tightFor(
      width: _width,
      height: _height,
    ).enforce(constraints);
    final image = _image;
    if (image == null) return constraints.smallest;
    return constraints.constrainSizeAndAttemptToPreserveAspectRatio(
      Size(image.width / _scale, image.height / _scale),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    if (_width == null && _height == null) return 0;
    return _sizeFor(BoxConstraints.tightForFinite(height: height)).width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _sizeFor(BoxConstraints.tightForFinite(height: height)).width;

  @override
  double computeMinIntrinsicHeight(double width) {
    if (_width == null && _height == null) return 0;
    return _sizeFor(BoxConstraints.tightForFinite(width: width)).height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _sizeFor(BoxConstraints.tightForFinite(width: width)).height;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(constraints);

  @override
  void performLayout() {
    size = _sizeFor(constraints);
  }

  /// The rect, in this box's coordinates, that the whole image is drawn
  /// into, and the visible part of it. With [BoxFit.cover] the image rect
  /// can be bigger than the box.
  ({Rect image, Rect visible})? get imageRects {
    final image = _image;
    if (image == null || size.isEmpty) return null;
    final inputSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(_fit, inputSize / _scale, size);
    if (fitted.source.isEmpty || fitted.destination.isEmpty) return null;
    final visible = _alignment.inscribe(fitted.destination, Offset.zero & size);
    final source = _alignment.inscribe(
      fitted.source,
      Offset.zero & (inputSize / _scale),
    );
    final k = visible.width / source.width;
    final full = Rect.fromLTWH(
      visible.left - source.left * k,
      visible.top - source.top * k,
      inputSize.width / _scale * k,
      inputSize.height / _scale * k,
    );
    return (image: full, visible: visible);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final image = _image;
    final rects = imageRects;
    if (image == null || rects == null) return;
    final canvas = context.canvas;
    final full = rects.image.shift(offset);
    final visible = rects.visible.shift(offset);

    final program = _program;
    if (program == null || _mixer.isIdentity) {
      if (program == null && !_paintUnedited && !_mixer.isIdentity) return;
      canvas.save();
      canvas.clipRect(visible);
      canvas.drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        full,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      return;
    }

    final shader = _shader ??= program.fragmentShader();
    shader
      ..setFloat(0, full.left)
      ..setFloat(1, full.top)
      ..setFloat(2, full.width)
      ..setFloat(3, full.height);
    final uniforms = _mixer.shaderUniforms;
    for (var i = 0; i < uniforms.length; i++) {
      shader.setFloat(4 + i, uniforms[i]);
    }
    shader.setImageSampler(0, image);
    canvas.drawRect(visible, Paint()..shader = shader);
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<ui.Image>('image', _image))
      ..add(DiagnosticsProperty<HslMixer>('mixer', _mixer))
      ..add(DoubleProperty('width', _width, defaultValue: null))
      ..add(DoubleProperty('height', _height, defaultValue: null))
      ..add(DoubleProperty('scale', _scale, defaultValue: 1.0))
      ..add(EnumProperty<BoxFit>('fit', _fit))
      ..add(DiagnosticsProperty<Alignment>('alignment', _alignment));
  }
}
