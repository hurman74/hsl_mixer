// Helpers for rendering README images into ../doc/ from widget tests.
// Used by tool/render_screenshots.dart. Run from the example directory:
//
//   flutter test tool/render_screenshots.dart
//
// Images use the real Roboto and Material Icons fonts from the Flutter SDK,
// so they look like the app on a device.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const double shotPixelRatio = 2;

final ThemeData shotTheme = ThemeData(
  colorSchemeSeed: Colors.indigo,
  fontFamily: 'Roboto',
);

/// Loads Roboto and Material Icons so text and icons aren't drawn as boxes.
/// Call once in `setUpAll`.
Future<void> loadShotFonts() async {
  final String flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final String fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String name) async =>
      ByteData.sublistView(File('$fonts/$name').readAsBytesSync());
  await (FontLoader('Roboto')
        ..addFont(read('Roboto-Regular.ttf'))
        ..addFont(read('Roboto-Medium.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
}

/// A phone-sized screen with rounded corners around [child].
Widget phone(Widget child, {double width = 360, double height = 640}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFDADCE0), width: 2),
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(18), child: child),
  );
}

/// A title with an optional grey detail line, placed above a [phone].
Widget caption(String text, {String? detail, Color? detailColor}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      children: <Widget>[
        Text(
          text,
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (detail != null)
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              height: 1.4,
              color: detailColor ?? const Color(0xFF5F6368),
            ),
          ),
      ],
    ),
  );
}

/// Pumps [scene] centred on a white canvas of [size] and returns the key of
/// the boundary to snapshot.
Future<GlobalKey> pumpShot(WidgetTester tester, Size size, Widget scene) async {
  final GlobalKey boundary = GlobalKey();
  tester.view.physicalSize = size * shotPixelRatio;
  tester.view.devicePixelRatio = shotPixelRatio;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: shotTheme,
      home: RepaintBoundary(
        key: boundary,
        child: Material(
          color: Colors.white,
          child: Center(child: scene),
        ),
      ),
    ),
  );
  // Let post-frame callbacks rebuild once.
  await tester.pump();
  return boundary;
}

/// The current pixels under [boundary] as PNG bytes.
Future<Uint8List> snapshot(WidgetTester tester, GlobalKey boundary) async {
  final RenderRepaintBoundary render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ByteData? png = await tester.runAsync<ByteData?>(() async {
    final ui.Image image = await render.toImage(pixelRatio: shotPixelRatio);
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  return png!.buffer.asUint8List();
}

/// Renders [scene] on a canvas of [size] and writes it to doc/[name].
Future<void> writePng(
  WidgetTester tester,
  String name,
  Size size,
  Widget scene,
) async {
  final GlobalKey boundary = await pumpShot(tester, size, scene);
  writeDoc(name, await snapshot(tester, boundary));
}

/// Collects frames from [boundary] into an animated GIF, [width] px wide.
class GifRecorder {
  GifRecorder(this.tester, this.boundary, {this.width = 400});

  final WidgetTester tester;
  final GlobalKey boundary;
  final int width;
  final img.GifEncoder _gif = img.GifEncoder(
    numColors: 128,
    dither: img.DitherKernel.none,
    samplingFactor: 4,
  );

  /// Adds the current frame, shown for [duration] hundredths of a second.
  Future<void> frame(int duration) async {
    final img.Image frame = img.decodePng(await snapshot(tester, boundary))!;
    _gif.addFrame(
      img.copyResize(
        frame,
        width: width,
        interpolation: img.Interpolation.average,
      ),
      duration: duration,
    );
  }

  /// Writes the GIF to doc/[name].
  void save(String name) => writeDoc(name, _gif.finish()!);
}

/// Writes [bytes] to ../doc/[name] (the package's doc folder).
void writeDoc(String name, List<int> bytes) {
  File('../doc/$name')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}
