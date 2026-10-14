// Renders the README images into ../doc/. Run from the example directory:
//
//   flutter test tool/render_screenshots.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hsl_mixer/hsl_mixer.dart';
import 'package:hsl_mixer_example/main.dart';

import 'readme_shots.dart';

void main() {
  setUpAll(loadShotFonts);

  testWidgets('demo.gif', (tester) async {
    final image = buildSampleImage(480, 320);
    final state = ValueNotifier<(HslMixer, String)>((HslMixer(), 'Original'));
    final boundary = await pumpShot(
      tester,
      const Size(400, 420),
      phone(
        width: 380,
        height: 400,
        Scaffold(
          appBar: AppBar(title: const Text('HSL mixer')),
          body: ValueListenableBuilder<(HslMixer, String)>(
            valueListenable: state,
            builder: (context, value, _) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: AspectRatio(
                    aspectRatio: 3 / 2,
                    child: RawHslMixerImage(
                      image: image,
                      mixer: value.$1,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Text(value.$2, style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
        ),
      ),
    );
    final gif = GifRecorder(tester, boundary);

    Future<void> animate(HslMixer from, HslMixer to, String label) async {
      final tween = HslMixerTween(begin: from, end: to);
      for (var i = 1; i <= 10; i++) {
        state.value = (tween.transform(i / 10), label);
        await tester.pump();
        await gif.frame(8);
      }
      await gif.frame(90);
    }

    await gif.frame(90);
    final blue = HslMixer({HslBand.blue: const HslAdjustment(hue: 0.6)});
    await animate(HslMixer(), blue, 'blue: hue +60');
    final green = blue.withBand(
      HslBand.green,
      const HslAdjustment(saturation: -1),
    );
    await animate(blue, green, 'blue: hue +60, green: saturation -100');
    final splash = HslMixer.only({HslBand.red, HslBand.orange});
    await animate(green, splash, 'HslMixer.only({red, orange})');
    await animate(splash, HslMixer(), 'Original');
    gif.save('demo.gif');
    image.dispose();
  });

  testWidgets('comparison.png', (tester) async {
    final image = buildSampleImage(480, 320);
    Widget panel(String title, String detail, Widget child) => SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          caption(title, detail: detail),
          AspectRatio(aspectRatio: 3 / 2, child: child),
        ],
      ),
    );
    final raw = RawImage(image: image, fit: BoxFit.cover);
    await writePng(
      tester,
      'comparison.png',
      const Size(1000, 340),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          panel('Original', 'Every hue, plus a gray strip\n', raw),
          panel(
            'ColorFiltered',
            'One matrix for every pixel:\nthe reds go gray too',
            ColorFiltered(colorFilter: _grayscale, child: raw),
          ),
          panel(
            'HslMixer.only({red, orange})',
            'Per hue band: the reds stay,\neverything else goes gray',
            RawHslMixerImage(
              image: image,
              mixer: HslMixer.only({HslBand.red, HslBand.orange}),
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
    image.dispose();
  });
}

const ColorFilter _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);
