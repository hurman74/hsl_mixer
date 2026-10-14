import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hsl_mixer/hsl_mixer.dart';

Color rgb(int r, int g, int b, [int a = 255]) => Color.fromARGB(a, r, g, b);

List<int> channels(Color c) => [
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
  (c.a * 255).round(),
];

double hueOf(Color c) => HSLColor.fromColor(c).hue;
double saturationOf(Color c) => HSLColor.fromColor(c).saturation;
double lightnessOf(Color c) => HSLColor.fromColor(c).lightness;

const red = Color(0xFFFF0000);
const blue = Color(0xFF0000FF);
const green = Color(0xFF00FF00);

void main() {
  group('HslBand', () {
    test('a hue at a band center belongs only to that band', () {
      for (final band in HslBand.values) {
        final weights = HslBand.bandWeights(band.centerHue);
        for (final other in HslBand.values) {
          expect(
            weights[other.index],
            other == band ? 1.0 : 0.0,
            reason: '${band.name} center, weight of ${other.name}',
          );
        }
      }
    });

    test('weights add up to 1 for every hue', () {
      for (var h = 0.0; h < 360; h += 0.75) {
        final sum = HslBand.bandWeights(h).reduce((a, b) => a + b);
        expect(sum, closeTo(1, 1e-12), reason: 'hue $h');
      }
    });

    test('a hue halfway between two centers is split evenly', () {
      expect(HslBand.orange.weightFor(45), closeTo(0.5, 1e-12));
      expect(HslBand.yellow.weightFor(45), closeTo(0.5, 1e-12));
      expect(HslBand.green.weightFor(150), closeTo(0.5, 1e-12));
    });

    test('magenta blends into red across 360 degrees', () {
      expect(HslBand.magenta.weightFor(330), closeTo(0.5, 1e-12));
      expect(HslBand.red.weightFor(330), closeTo(0.5, 1e-12));
      expect(HslBand.red.weightFor(359.9), greaterThan(0.99));
    });

    test('hues outside [0, 360) wrap around', () {
      expect(HslBand.bandWeights(-30), HslBand.bandWeights(330));
      expect(HslBand.bandWeights(420), HslBand.bandWeights(60));
    });

    test('weights change smoothly', () {
      for (final band in HslBand.values) {
        var previous = band.weightFor(0);
        for (var h = 0.1; h < 360; h += 0.1) {
          final w = band.weightFor(h);
          expect((w - previous).abs(), lessThan(0.01), reason: 'hue $h');
          previous = w;
        }
      }
    });
  });

  group('HslAdjustment', () {
    test('defaults to no change', () {
      expect(const HslAdjustment().isZero, isTrue);
      expect(HslAdjustment.zero, const HslAdjustment());
      expect(const HslAdjustment(hue: 0.1).isZero, isFalse);
    });

    test('clamps values to [-1, 1]', () {
      const a = HslAdjustment(hue: 3, saturation: -5, lightness: 2);
      expect(a.hueDegrees, HslAdjustment.maxHueShiftDegrees);
      expect(a.clampedSaturation, -1);
      expect(a.clampedLightness, 1);
    });

    test('copyWith and lerp', () {
      const a = HslAdjustment(hue: 1, saturation: -1);
      expect(
        a.copyWith(lightness: 0.5),
        const HslAdjustment(hue: 1, saturation: -1, lightness: 0.5),
      );
      expect(
        HslAdjustment.lerp(a, null, 0.5),
        const HslAdjustment(hue: 0.5, saturation: -0.5),
      );
      expect(HslAdjustment.lerp(null, a, 1), a);
    });

    test('equality and hashCode', () {
      expect(
        const HslAdjustment(hue: 0.2),
        equals(const HslAdjustment(hue: 0.2)),
      );
      expect(
        const HslAdjustment(hue: 0.2).hashCode,
        const HslAdjustment(hue: 0.2).hashCode,
      );
      expect(const HslAdjustment(hue: 0.2), isNot(const HslAdjustment()));
    });
  });

  group('HslMixer', () {
    test('identity changes nothing', () {
      const mixer = HslMixer.identity();
      expect(mixer.isIdentity, isTrue);
      expect(HslMixer().isIdentity, isTrue);
      expect(HslMixer(), const HslMixer.identity());
      for (final c in [red, blue, rgb(224, 172, 105), rgb(10, 200, 90, 128)]) {
        expect(channels(mixer.applyToColor(c)), channels(c));
      }
    });

    test('only touches the adjusted band', () {
      final mixer = HslMixer({
        HslBand.blue: const HslAdjustment(saturation: -1),
      });
      expect(channels(mixer.applyToColor(blue)), [128, 128, 128, 255]);
      expect(channels(mixer.applyToColor(red)), channels(red));
      expect(channels(mixer.applyToColor(green)), channels(green));
    });

    test('hue shifts rotate toward the next band', () {
      final mixer = HslMixer({HslBand.red: const HslAdjustment(hue: 1)});
      expect(hueOf(mixer.applyToColor(red)), closeTo(30, 0.5));
      final back = HslMixer({HslBand.red: const HslAdjustment(hue: -1)});
      expect(hueOf(back.applyToColor(red)), closeTo(330, 0.5));
    });

    test('saturation boosts and cuts', () {
      final muted = rgb(150, 100, 100); // A dusty red.
      final up = HslMixer({HslBand.red: const HslAdjustment(saturation: 1)});
      expect(saturationOf(up.applyToColor(muted)), closeTo(1, 0.01));
      final half = HslMixer({
        HslBand.red: const HslAdjustment(saturation: -0.5),
      });
      expect(
        saturationOf(half.applyToColor(muted)),
        closeTo(saturationOf(muted) / 2, 0.01),
      );
    });

    test('lightness moves halfway to white or black at the extremes', () {
      final lighter = HslMixer({
        HslBand.blue: const HslAdjustment(lightness: 1),
      });
      expect(lightnessOf(lighter.applyToColor(blue)), closeTo(0.75, 0.01));
      final darker = HslMixer({
        HslBand.blue: const HslAdjustment(lightness: -1),
      });
      expect(lightnessOf(darker.applyToColor(blue)), closeTo(0.25, 0.01));
    });

    test('grays are never changed', () {
      final mixer = HslMixer.all(
        const HslAdjustment(hue: 1, saturation: 1, lightness: 1),
      );
      for (final v in [0, 1, 60, 128, 254, 255]) {
        final gray = rgb(v, v, v);
        expect(channels(mixer.applyToColor(gray)), channels(gray));
      }
    });

    test('near-grays get little saturation boost', () {
      final almostGray = rgb(130, 128, 128);
      final mixer = HslMixer.all(const HslAdjustment(saturation: 1));
      final out = channels(mixer.applyToColor(almostGray));
      expect((out[0] - out[1]).abs(), lessThan(10));
    });

    test('the same adjustment on every band is a global adjustment', () {
      final mixer = HslMixer.all(const HslAdjustment(saturation: -1));
      for (final c in [
        red,
        blue,
        green,
        rgb(224, 172, 105),
        rgb(90, 20, 160),
      ]) {
        expect(saturationOf(mixer.applyToColor(c)), closeTo(0, 0.01));
      }
    });

    test('a hue between bands is affected by both', () {
      final orangeOnly = HslMixer({
        HslBand.orange: const HslAdjustment(saturation: -1),
      });
      final between = rgb(255, 191, 0); // 45°, halfway orange to yellow.
      expect(
        saturationOf(orangeOnly.applyToColor(between)),
        closeTo(0.5, 0.02),
      );
    });

    test('only() keeps the chosen bands and grays the rest', () {
      final mixer = HslMixer.only({HslBand.red});
      expect(channels(mixer.applyToColor(red)), channels(red));
      expect(saturationOf(mixer.applyToColor(blue)), 0);
      expect(saturationOf(mixer.applyToColor(green)), 0);
      expect(mixer[HslBand.red], HslAdjustment.zero);
      expect(mixer[HslBand.blue], HslAdjustment.desaturate);
    });

    test('keeps alpha and color space', () {
      final mixer = HslMixer({HslBand.blue: HslAdjustment.desaturate});
      final c = Color.from(
        alpha: 0.4,
        red: 0,
        green: 0,
        blue: 1,
        colorSpace: ui.ColorSpace.displayP3,
      );
      final out = mixer.applyToColor(c);
      expect(out.a, 0.4);
      expect(out.colorSpace, ui.ColorSpace.displayP3);
    });

    test('withBand, updateBand and adjustments', () {
      final mixer = HslMixer()
          .withBand(HslBand.green, const HslAdjustment(hue: 0.5))
          .updateBand(HslBand.green, (a) => a.copyWith(saturation: 0.2));
      expect(
        mixer[HslBand.green],
        const HslAdjustment(hue: 0.5, saturation: 0.2),
      );
      expect(mixer.adjustments.length, HslBand.values.length);
      expect(mixer.adjustments[HslBand.red], HslAdjustment.zero);
      expect(
        () => mixer.adjustments[HslBand.red] = HslAdjustment.zero,
        returnsNormally,
      );
      expect(mixer[HslBand.red], HslAdjustment.zero);
    });

    test('lerp interpolates band by band', () {
      final a = HslMixer({HslBand.red: const HslAdjustment(hue: 1)});
      final b = HslMixer({HslBand.blue: const HslAdjustment(saturation: -1)});
      final mid = HslMixer.lerp(a, b, 0.5);
      expect(mid[HslBand.red], const HslAdjustment(hue: 0.5));
      expect(mid[HslBand.blue], const HslAdjustment(saturation: -0.5));
      expect(HslMixer.lerp(null, a, 1), a);
      expect(HslMixer.lerp(a, null, 1).isIdentity, isTrue);
      expect(HslMixerTween(begin: a, end: b).transform(0.5), mid);
    });

    test('equality and toString', () {
      final a = HslMixer({HslBand.aqua: const HslAdjustment(lightness: 0.3)});
      final b = HslMixer({HslBand.aqua: const HslAdjustment(lightness: 0.3)});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(HslMixer()));
      expect(a.toString(), contains('aqua'));
      expect(HslMixer().toString(), 'HslMixer.identity()');
    });

    test(
      'shader uniforms are hue degrees, then saturation, then lightness',
      () {
        final mixer = HslMixer({
          HslBand.orange: const HslAdjustment(
            hue: 0.5,
            saturation: -0.25,
            lightness: 2,
          ),
        });
        final u = mixer.shaderUniforms;
        expect(u.length, 24);
        expect(u[HslBand.orange.index], 15);
        expect(u[8 + HslBand.orange.index], -0.25);
        expect(u[16 + HslBand.orange.index], 1);
        expect(u.where((v) => v != 0).length, 3);
      },
    );
  });

  group('applyToRgba', () {
    test('matches applyToColor for straight alpha', () {
      final mixer = HslMixer({
        HslBand.orange: const HslAdjustment(hue: -0.4, saturation: 0.3),
        HslBand.blue: const HslAdjustment(lightness: -0.6),
      });
      final colors = [
        rgb(224, 172, 105),
        rgb(30, 60, 200),
        rgb(250, 120, 10, 200),
      ];
      final bytes = Uint8List.fromList([
        for (final c in colors) ...channels(c),
      ]);
      mixer.applyToRgba(bytes);
      for (var i = 0; i < colors.length; i++) {
        expect(
          bytes.sublist(i * 4, i * 4 + 4),
          channels(mixer.applyToColor(colors[i])),
        );
      }
    });

    test('handles premultiplied pixels', () {
      final mixer = HslMixer({HslBand.blue: HslAdjustment.desaturate});
      // Pure blue at 50% alpha, premultiplied.
      final bytes = Uint8List.fromList([0, 0, 128, 128]);
      mixer.applyToRgba(bytes, premultiplied: true);
      expect(bytes, [64, 64, 64, 128]);
    });

    test('leaves transparent pixels alone', () {
      final mixer = HslMixer.all(const HslAdjustment(hue: 1));
      final bytes = Uint8List.fromList([255, 0, 0, 0]);
      mixer.applyToRgba(bytes);
      expect(bytes, [255, 0, 0, 0]);
    });

    test('rejects a length that is not a multiple of 4', () {
      expect(() => HslMixer().applyToRgba(Uint8List(5)), throwsArgumentError);
    });
  });

  group('applyToImage', () {
    testWidgets('returns an image with the edit applied', (tester) async {
      await tester.runAsync(() async {
        final source = await imageFromPixels(4, 1, [
          ...channels(blue),
          ...channels(red),
          ...channels(rgb(128, 128, 128)),
          ...channels(rgb(0, 0, 255, 128)),
        ]);
        final mixer = HslMixer({HslBand.blue: HslAdjustment.desaturate});
        final result = await mixer.applyToImage(source);
        expect(result.width, 4);
        expect(result.height, 1);
        final pixels = await straightPixels(result);
        expect(pixels.sublist(0, 4), [128, 128, 128, 255]);
        expect(pixels.sublist(4, 8), [255, 0, 0, 255]);
        expect(pixels.sublist(8, 12), [128, 128, 128, 255]);
        expectClose(pixels.sublist(12, 16), [128, 128, 128, 128], 2);
        source.dispose();
        result.dispose();
      });
    });
  });

  group('RawHslMixerImage', () {
    setUpAll(() async {
      await HslMixerShader.precache();
    });

    // A spread of colors across every band, plus grays and transparency.
    final palette = <Color>[
      red,
      rgb(255, 128, 0),
      rgb(255, 255, 0),
      green,
      rgb(0, 255, 255),
      blue,
      rgb(128, 0, 255),
      rgb(255, 0, 255),
      rgb(224, 172, 105),
      rgb(20, 30, 80),
      rgb(128, 128, 128),
      rgb(250, 250, 245),
      rgb(150, 100, 100),
      rgb(60, 140, 70),
      rgb(255, 64, 32, 160),
      rgb(0, 0, 0, 0),
    ];

    final mixers = <String, HslMixer>{
      'identity': HslMixer(),
      'mixed edit': HslMixer({
        HslBand.red: const HslAdjustment(hue: 0.6, saturation: -0.3),
        HslBand.orange: const HslAdjustment(lightness: 0.4),
        HslBand.green: const HslAdjustment(hue: -1, saturation: 0.8),
        HslBand.blue: const HslAdjustment(saturation: 1, lightness: -0.7),
        HslBand.magenta: const HslAdjustment(hue: 1),
      }),
      'color splash': HslMixer.only({HslBand.orange}),
    };

    for (final entry in mixers.entries) {
      testWidgets('the GPU matches the Dart math: ${entry.key}', (
        tester,
      ) async {
        final image = (await tester.runAsync(
          () =>
              imageFromPixels(4, 4, [for (final c in palette) ...channels(c)]),
        ))!;
        addTearDown(image.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(
          Center(
            child: RepaintBoundary(
              key: key,
              child: RawHslMixerImage(
                image: image,
                mixer: entry.value,
                width: 4,
                height: 4,
                fit: BoxFit.fill,
              ),
            ),
          ),
        );
        final rendered = (await tester.runAsync(() => capture(key)))!;

        final expected = Uint8List.fromList([
          for (final c in palette) ...channels(c),
        ]);
        entry.value.applyToRgba(expected);
        for (var i = 0; i < palette.length; i++) {
          if (palette[i].a == 0) {
            expect(rendered[i * 4 + 3], 0, reason: 'pixel $i alpha');
            continue;
          }
          // Allow for float precision and premultiplied round trips.
          final tolerance = palette[i].a < 1 ? 4 : 2;
          expectClose(
            rendered.sublist(i * 4, i * 4 + 4),
            expected.sublist(i * 4, i * 4 + 4),
            tolerance,
            reason: 'pixel $i (${channels(palette[i])})',
          );
        }
      });
    }

    testWidgets('sizes itself like an image', (tester) async {
      final image = (await tester.runAsync(
        () => imageFromPixels(40, 20, List.filled(40 * 20 * 4, 255)),
      ))!;
      addTearDown(image.dispose);
      await tester.pumpWidget(
        Center(
          child: RawHslMixerImage(image: image, mixer: HslMixer()),
        ),
      );
      expect(tester.getSize(find.byType(RawHslMixerImage)), const Size(40, 20));

      await tester.pumpWidget(
        Center(
          child: RawHslMixerImage(image: image, mixer: HslMixer(), scale: 2),
        ),
      );
      expect(tester.getSize(find.byType(RawHslMixerImage)), const Size(20, 10));

      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 20,
            child: RawHslMixerImage(image: image, mixer: HslMixer()),
          ),
        ),
      );
      expect(tester.getSize(find.byType(RawHslMixerImage)), const Size(20, 10));

      await tester.pumpWidget(
        Center(
          child: RawHslMixerImage(image: null, mixer: HslMixer(), width: 30),
        ),
      );
      expect(tester.getSize(find.byType(RawHslMixerImage)), const Size(30, 0));
    });

    test('computes the image rect for cover and contain', () {
      final image = _FakeSize(40, 20);
      final box = RenderHslMixerImage(
        image: image.image,
        mixer: HslMixer(),
        fit: BoxFit.cover,
      );
      box.layout(BoxConstraints.tight(const Size(20, 20)));
      final cover = box.imageRects!;
      expect(cover.visible, const Rect.fromLTWH(0, 0, 20, 20));
      expect(cover.image, const Rect.fromLTWH(-10, 0, 40, 20));

      box.fit = BoxFit.contain;
      final contain = box.imageRects!;
      expect(contain.visible, const Rect.fromLTWH(0, 5, 20, 10));
      expect(contain.image, contain.visible);

      box
        ..fit = BoxFit.cover
        ..alignment = Alignment.centerLeft;
      expect(box.imageRects!.image, const Rect.fromLTWH(0, 0, 40, 20));
      image.dispose();
    });

    testWidgets('cover crops the image, not the colors', (tester) async {
      // Left half blue, right half red. Cover into a square shows the
      // middle: blue on the left, red on the right.
      final pixels = <int>[
        for (var y = 0; y < 2; y++)
          for (var x = 0; x < 8; x++) ...channels(x < 4 ? blue : red),
      ];
      final image = (await tester.runAsync(
        () => imageFromPixels(8, 2, pixels),
      ))!;
      addTearDown(image.dispose);
      final key = GlobalKey();
      final mixer = HslMixer({HslBand.blue: HslAdjustment.desaturate});
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: RawHslMixerImage(
              image: image,
              mixer: mixer,
              width: 2,
              height: 2,
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
      final rendered = (await tester.runAsync(() => capture(key)))!;
      expectClose(rendered.sublist(0, 4), [128, 128, 128, 255], 2);
      expectClose(rendered.sublist(4, 8), [255, 0, 0, 255], 2);
    });

    testWidgets('follows transforms', (tester) async {
      final image = (await tester.runAsync(
        () => imageFromPixels(2, 1, [...channels(blue), ...channels(red)]),
      ))!;
      addTearDown(image.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 4,
              height: 2,
              child: Transform.scale(
                scale: 2,
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: RawHslMixerImage(
                      image: image,
                      mixer: HslMixer({HslBand.blue: HslAdjustment.desaturate}),
                      width: 2,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final rendered = (await tester.runAsync(() => capture(key)))!;
      // 4x2 output; row 0 is gray, gray, red, red.
      expectClose(rendered.sublist(0, 4), [128, 128, 128, 255], 2);
      expectClose(rendered.sublist(4, 8), [128, 128, 128, 255], 2);
      expectClose(rendered.sublist(8, 12), [255, 0, 0, 255], 2);
      expectClose(rendered.sublist(12, 16), [255, 0, 0, 255], 2);
    });

    testWidgets('repaints when the mixer changes', (tester) async {
      final image = (await tester.runAsync(
        () => imageFromPixels(1, 1, channels(blue)),
      ))!;
      addTearDown(image.dispose);
      final key = GlobalKey();
      Future<List<int>> render(HslMixer mixer) async {
        await tester.pumpWidget(
          Center(
            child: RepaintBoundary(
              key: key,
              child: RawHslMixerImage(
                image: image,
                mixer: mixer,
                width: 1,
                height: 1,
              ),
            ),
          ),
        );
        return (await tester.runAsync(() => capture(key)))!;
      }

      expect(await render(HslMixer()), [0, 0, 255, 255]);
      expectClose(
        await render(HslMixer({HslBand.blue: HslAdjustment.desaturate})),
        [128, 128, 128, 255],
        2,
      );
      expectClose(
        await render(
          HslMixer({HslBand.blue: const HslAdjustment(lightness: 1)}),
        ),
        [128, 128, 255, 255],
        2,
      );
    });
  });

  group('HslMixerImage', () {
    setUpAll(() async {
      await HslMixerShader.precache();
    });

    testWidgets('loads an ImageProvider and applies the mixer', (tester) async {
      final png = (await tester.runAsync(() async {
        final image = await imageFromPixels(2, 1, [
          ...channels(blue),
          ...channels(green),
        ]);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
      final key = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: HslMixerImage(
                  image: MemoryImage(png),
                  mixer: HslMixer({HslBand.blue: HslAdjustment.desaturate}),
                  semanticLabel: 'Two pixels',
                ),
              ),
            ),
          ),
        );
        // Let the image decode.
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (tester.getSize(find.byType(RawHslMixerImage)).width > 0) break;
        }
      });
      expect(tester.getSize(find.byType(HslMixerImage)), const Size(2, 1));
      expect(find.bySemanticsLabel('Two pixels'), findsOneWidget);
      final rendered = (await tester.runAsync(() => capture(key)))!;
      expectClose(rendered.sublist(0, 4), [128, 128, 128, 255], 2);
      expectClose(rendered.sublist(4, 8), [0, 255, 0, 255], 2);
    });

    testWidgets('shows the errorBuilder when the image fails', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: HslMixerImage(
              image: MemoryImage(Uint8List.fromList([1, 2, 3])),
              mixer: HslMixer(),
              errorBuilder: (context, error, stack) => const Text('broken'),
            ),
          ),
        );
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.text('broken').evaluate().isNotEmpty) break;
        }
      });
      expect(find.text('broken'), findsOneWidget);
    });
  });
}

class _FakeSize {
  _FakeSize(int width, int height) : image = _solid(width, height);

  final ui.Image image;

  static ui.Image _solid(int width, int height) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  void dispose() => image.dispose();
}

Future<ui.Image> imageFromPixels(int width, int height, List<int> rgba) async {
  // decodeImageFromPixels takes premultiplied pixels.
  final bytes = Uint8List.fromList(rgba);
  for (var i = 0; i < bytes.length; i += 4) {
    final a = bytes[i + 3];
    for (var c = 0; c < 3; c++) {
      bytes[i + c] = (bytes[i + c] * a / 255).round();
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}

Future<Uint8List> straightPixels(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  return data!.buffer.asUint8List();
}

Future<Uint8List> capture(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final pixels = await straightPixels(image);
  image.dispose();
  return pixels;
}

void expectClose(
  List<int> actual,
  List<int> expected,
  int tolerance, {
  String? reason,
}) {
  expect(actual.length, expected.length, reason: reason);
  for (var i = 0; i < actual.length; i++) {
    expect(
      (actual[i] - expected[i]).abs(),
      lessThanOrEqualTo(tolerance),
      reason: '${reason ?? ''} channel $i: got $actual, expected $expected',
    );
  }
}
