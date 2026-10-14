import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hsl_mixer/hsl_mixer.dart';
import 'package:hsl_mixer_example/main.dart';

void main() {
  setUpAll(() async {
    await HslMixerShader.precache();
  });

  testWidgets('editing a band updates the mixer', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const HslMixerExampleApp());

    RawHslMixerImage image() =>
        tester.widget<RawHslMixerImage>(find.byType(RawHslMixerImage));
    expect(image().mixer.isIdentity, isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'blue'));
    await tester.pump();

    // Drag the saturation slider all the way left.
    final slider = find.byType(Slider).at(1);
    await tester.drag(slider, const Offset(-1000, 0));
    await tester.pumpAndSettle();

    expect(image().mixer[HslBand.blue].saturation, -1);
    expect(image().mixer[HslBand.red], HslAdjustment.zero);
    expect(find.text('-100'), findsOneWidget);

    await tester.tap(find.byTooltip('Reset'));
    await tester.pump();
    expect(image().mixer.isIdentity, isTrue);
  });

  testWidgets('color splash keeps only reds and oranges', (tester) async {
    await tester.pumpWidget(const HslMixerExampleApp());
    await tester.tap(find.byTooltip('Color splash: keep reds only'));
    await tester.pump();

    final mixer = tester
        .widget<RawHslMixerImage>(find.byType(RawHslMixerImage))
        .mixer;
    expect(mixer[HslBand.red], HslAdjustment.zero);
    expect(mixer[HslBand.orange], HslAdjustment.zero);
    expect(mixer[HslBand.blue], HslAdjustment.desaturate);
  });
}
