import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bounded stand-in for [WidgetTester.pumpAndSettle].
///
/// The ledger's icons loop forever by design (see
/// lib/widgets/ledger_icons.dart) — that's the whole point of a "live" icon.
/// But it means the app never reaches the zero-pending-frames state
/// pumpAndSettle waits for once the landing screen is visible: it isn't a
/// bounded wait with a timeout, it throws once its internal timeout elapses.
/// This just flushes a fixed span of wall-clock time instead, which every
/// one-shot animation in the app finishes well inside of — the longest being
/// the ~2.84s splash-to-landing handover.
///
/// This does not by itself fix real image decoding — see [pumpAndWarm]. By
/// the time a test calls [settle], the asset request was already made (during
/// whatever earlier pump put the ledger on screen), so wrapping *this* loop in
/// runAsync is too late: the codec's completion is tied to the zone active
/// when dart:ui's instantiateImageCodec was first called, not to whoever
/// awaits it afterward.
Future<void> settle(
  WidgetTester tester, [
  Duration total = const Duration(milliseconds: 6000),
]) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// Must match the PNG paths in lib/widgets/ledger_icons.dart. Duplicated
/// rather than imported so this test helper doesn't need to know about
/// [BrewGlyph] — it only needs to know which two assets are raster.
const _rasterLedgerAssets = <String>[
  'assets/icons/Coffee--Streamline-Platinum.png',
  'assets/icons/Like--Streamline-Platinum.png',
];

/// Mounts [widget] and gives real asset decoding a chance to finish before
/// returning.
///
/// Two of the three ledger glyphs are PNGs decoded through dart:ui's real
/// image codec rather than drawn paths. In this test environment that decode
/// silently never completes through the ordinary Image widget lifecycle —
/// confirmed by sampling the rendered pixels directly, not by eye: still 0
/// pixels differing from the background after pumpWidget, runAsync, and ten
/// full seconds of pumpAndSettle. [precacheImage] is the one path that
/// actually resolves it (170 pixels differing once it's used), so that's what
/// this calls instead of trusting the widget to resolve itself. The third
/// glyph (SVG) parses in pure Dart and doesn't need any of this — it just
/// paints on the first frame — which is why the gap didn't show up until the
/// PNGs were introduced.
Future<void> pumpAndWarm(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.runAsync(() async {
    final context = tester.element(find.byWidget(widget));
    for (final asset in _rasterLedgerAssets) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pump();
}
