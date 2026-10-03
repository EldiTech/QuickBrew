import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/widgets/ledger_icons.dart';

/// [BrewGlyph.ink] is measured off the assets, and the ledger scales each glyph
/// by what it says: a swap for an export that frames itself differently would
/// otherwise silently shift that glyph off the icon column and out of size with
/// the other two, at 64px, with nothing failing. So re-measure the rasters here
/// rather than trusting the numbers to stay true.
///
/// The SVG is left to review by eye — its ink comes from path extents this
/// can't read back, and being vector it is the one that stays crisp anyway.
void main() {
  const rasters = <BrewGlyph>[BrewGlyph.coffeeCup, BrewGlyph.thumbsUp];

  for (final glyph in rasters) {
    testWidgets('${glyph.name} still inks the box it claims', (tester) async {
      late Rect measured;
      await tester.runAsync(() async {
        measured = await _inkOf(glyph.asset);
      });

      expect(
        measured.left,
        closeTo(glyph.ink.left, 0.001),
        reason: '${glyph.asset}: left margin moved',
      );
      expect(
        measured.top,
        closeTo(glyph.ink.top, 0.001),
        reason: '${glyph.asset}: top margin moved',
      );
      expect(
        measured.width,
        closeTo(glyph.ink.width, 0.001),
        reason: '${glyph.asset}: ink width moved',
      );
      expect(
        measured.height,
        closeTo(glyph.ink.height, 0.001),
        reason: '${glyph.asset}: ink height moved',
      );
    });
  }
}

/// The alpha channel's bounding box, in fractions of the image's own box.
/// 8/255 rather than 0, so a stray antialiased pixel can't count as ink.
Future<Rect> _inkOf(String asset) async {
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final image = (await codec.getNextFrame()).image;
  final pixels =
      (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();

  var left = image.width, top = image.height, right = -1, bottom = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (pixels[(y * image.width + x) * 4 + 3] <= 8) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }

  expect(right, greaterThanOrEqualTo(left), reason: '$asset decoded blank');
  return Rect.fromLTWH(
    left / image.width,
    top / image.height,
    (right - left + 1) / image.width,
    (bottom - top + 1) / image.height,
  );
}
