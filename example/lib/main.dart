import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hsl_mixer/hsl_mixer.dart';

void main() {
  // Optional: load the shader before the first frame that needs it.
  HslMixerShader.precache();
  runApp(const HslMixerExampleApp());
}

/// A small photo-editor style demo of the HSL mixer.
class HslMixerExampleApp extends StatelessWidget {
  /// Creates the demo app.
  const HslMixerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'hsl_mixer',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const EditorPage(),
    );
  }
}

/// The editor: an image, a band picker and three sliders.
class EditorPage extends StatefulWidget {
  /// Creates the editor page.
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage>
    with SingleTickerProviderStateMixin {
  ui.Image? _image;
  HslMixer _mixer = HslMixer();
  HslBand _band = HslBand.red;
  String? _exported;

  // Animates between the original and the edit for the before/after toggle.
  late final AnimationController _showEdit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _image = buildSampleImage(480, 320);
  }

  @override
  void dispose() {
    _showEdit.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _update(HslAdjustment Function(HslAdjustment) change) {
    setState(() {
      _mixer = _mixer.updateBand(_band, change);
      _exported = null;
    });
  }

  Future<void> _export() async {
    final image = _image;
    if (image == null) return;
    final edited = await _mixer.applyToImage(image);
    final png = await edited.toByteData(format: ui.ImageByteFormat.png);
    edited.dispose();
    if (!mounted) return;
    setState(() {
      _exported =
          'Exported a ${image.width}×${image.height} PNG '
          '(${png!.lengthInBytes ~/ 1024} KB) with the CPU path.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final adjustment = _mixer[_band];
    return Scaffold(
      appBar: AppBar(
        title: const Text('HSL mixer'),
        actions: [
          IconButton(
            tooltip: 'Color splash: keep reds only',
            icon: const Icon(Icons.water_drop_outlined),
            onPressed: () => setState(() {
              _mixer = HslMixer.only({HslBand.red, HslBand.orange});
              _exported = null;
            }),
          ),
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(() {
              _mixer = HslMixer();
              _exported = null;
            }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            // Press and hold to compare with the original.
            onTapDown: (_) => _showEdit.reverse(),
            onTapUp: (_) => _showEdit.forward(),
            onTapCancel: () => _showEdit.forward(),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: AnimatedBuilder(
                animation: _showEdit,
                builder: (context, _) => RawHslMixerImage(
                  image: _image,
                  mixer: HslMixerTween(end: _mixer).transform(_showEdit.value),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Press and hold the image to see the original.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final band in HslBand.values)
                ChoiceChip(
                  avatar: CircleAvatar(
                    backgroundColor: HSLColor.fromAHSL(
                      1,
                      band.centerHue,
                      0.9,
                      0.5,
                    ).toColor(),
                  ),
                  label: Text(band.name),
                  selected: band == _band,
                  onSelected: (_) => setState(() => _band = band),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _LabeledSlider(
            label: 'Hue',
            value: adjustment.hue,
            onChanged: (v) => _update((a) => a.copyWith(hue: v)),
          ),
          _LabeledSlider(
            label: 'Saturation',
            value: adjustment.saturation,
            onChanged: (v) => _update((a) => a.copyWith(saturation: v)),
          ),
          _LabeledSlider(
            label: 'Lightness',
            value: adjustment.lightness,
            onChanged: (v) => _update((a) => a.copyWith(lightness: v)),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _export,
            icon: const Icon(Icons.save_alt),
            label: const Text('Export'),
          ),
          if (_exported != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_exported!, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: -1,
            max: 1,
            divisions: 200,
            label: (value * 100).round().toString(),
            semanticFormatterCallback: (v) => '$label ${(v * 100).round()}',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            (value * 100).round().toString(),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

/// Paints a sample "photo" with every hue at many saturations and
/// lightnesses, plus a gray strip, so each band has something to change.
///
/// A real app would load a photo with `HslMixerImage(image: ...)`.
ui.Image buildSampleImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final w = width.toDouble();
  final h = height.toDouble();
  final photo = Rect.fromLTWH(0, 0, w, h * 0.85);

  canvas.drawRect(
    photo,
    Paint()
      ..shader = LinearGradient(
        colors: [
          for (var hue = 0; hue <= 360; hue += 30)
            HSLColor.fromAHSL(1, hue % 360, 0.85, 0.5).toColor(),
        ],
      ).createShader(photo),
  );
  // Fade to white at the top and black at the bottom, with muted tones in
  // between.
  canvas.drawRect(
    photo,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xCCFFFFFF),
          Color(0x00FFFFFF),
          Color(0x00000000),
          Color(0x66808080),
          Color(0xCC000000),
        ],
        stops: [0, 0.3, 0.5, 0.7, 1],
      ).createShader(photo),
  );
  final grays = Rect.fromLTWH(0, h * 0.85, w, h * 0.15);
  canvas.drawRect(
    grays,
    Paint()
      ..shader = const LinearGradient(
        colors: [Colors.black, Colors.white],
      ).createShader(grays),
  );

  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}
