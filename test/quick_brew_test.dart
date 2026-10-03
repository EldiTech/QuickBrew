import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_flow.dart';
import 'package:quick_brew/widgets/brew_buttons.dart';
import 'package:quick_brew/widgets/cup_mark.dart';
import 'package:quick_brew/widgets/ledger_icons.dart';
import 'package:quick_brew/widgets/rebrew_cup.dart';

import 'support/settle.dart';

/// The three sizes the design has to hold without scrolling.
const _sizes = <String, Size>{
  '390x844': Size(390, 844),
  '360x800': Size(360, 800),
  '375x667': Size(375, 667),
};

/// A notched device, so the safe-area path is the one under test rather than
/// the 20px floor.
const _notch = EdgeInsets.only(top: 44, bottom: 34);

/// Text metrics decide whether this layout fits, so the real faces have to be
/// loaded. Without this the engine substitutes its test font, every glyph
/// measures 1em, and the results say nothing about the shipped app.
Future<void> _loadBrandFonts() async {
  const faces = <String, String>{
    'Fraunces': 'assets/fonts/Fraunces.ttf',
    'Hanken Grotesk': 'assets/fonts/HankenGrotesk.ttf',
    'Martian Mono': 'assets/fonts/MartianMono.ttf',
  };

  for (final MapEntry(key: family, value: path) in faces.entries) {
    final bytes = await File(path).readAsBytes();
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  }
}

Future<void> _pumpFlow(
  WidgetTester tester,
  Size size, {
  bool reduced = false,
  EdgeInsets insets = EdgeInsets.zero,
  VoidCallback? onGetStarted,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await pumpAndWarm(
    tester,
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: insets,
          disableAnimations: reduced,
        ),
        child: BrewFlow(onGetStarted: onGetStarted),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadBrandFonts);

  group('no scrolling at any size', () {
    for (final MapEntry(key: label, value: size) in _sizes.entries) {
      testWidgets('$label with safe-area insets', (tester) async {
        await _pumpFlow(tester, size, insets: _notch);
        expect(tester.takeException(), isNull, reason: 'splash overflowed');

        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'landing overflowed');

        expect(find.byType(Scrollable), findsNothing);
        expect(find.text('Log in'), findsOneWidget);
      });

      testWidgets('$label with no insets, on the 20px floor', (tester) async {
        await _pumpFlow(tester, size);
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollable), findsNothing);
      });
    }
  });

  testWidgets('the filling cup is the loading indicator', (tester) async {
    await _pumpFlow(tester, _sizes['390x844']!);

    expect(find.text('EXTRACTING'), findsOneWidget);
    expect(find.text('READY'), findsNothing);

    // The fill only starts at 520ms, after the fade and the stroke draw.
    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('EXTRACTING'), findsNothing);

    await settle(tester);
  });

  testWidgets('the splash is non-dismissible and swallows taps', (tester) async {
    var started = 0;
    await _pumpFlow(
      tester,
      _sizes['390x844']!,
      insets: _notch,
      onGetStarted: () => started++,
    );

    // Mid-splash, over the landing CTA's position.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Log in'), warnIfMissed: false);
    await tester.pump();
    expect(started, 0, reason: 'splash must absorb pointers, not ignore them');

    await settle(tester);
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(started, 1, reason: 'landing should be live once the splash is gone');
  });

  testWidgets('the cup is drawn exactly once, so it cannot cross-fade', (
    tester,
  ) async {
    await _pumpFlow(tester, _sizes['390x844']!, insets: _notch);
    expect(find.byType(CupMark), findsOneWidget);

    // The splash run completes and the flight begins on this frame.
    await tester.pump(BrewMotionProbe.splashRun);
    expect(find.byType(CupMark), findsOneWidget);

    // Mid-flight.
    await tester.pump(const Duration(milliseconds: 210));
    expect(find.byType(CupMark), findsOneWidget);

    await settle(tester);
    expect(find.byType(CupMark), findsOneWidget);
  });

  testWidgets('the cup lands at 40px in the top-left gutter', (tester) async {
    await _pumpFlow(tester, _sizes['390x844']!, insets: _notch);
    await settle(tester);

    final landed = tester.getRect(find.byType(CupMark));
    expect(landed.width, 40);
    expect(landed.height, 40);
    expect(landed.left, 24, reason: 'the 24px gutter');
    // The safe-area inset is a floor, not a margin: the lockup clears the status
    // bar by a further 16 so it does not sit hard against it on a real device.
    expect(landed.top, _notch.top + 16);
  });

  testWidgets('reduced motion: pre-filled, held, opacity only', (tester) async {
    await _pumpFlow(tester, _sizes['390x844']!, reduced: true, insets: _notch);

    // Pre-filled: no extraction to watch, so the label is already READY.
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('EXTRACTING'), findsNothing);

    // No travel — the cup exists in both slots, the splash one simply fades.
    expect(find.byType(CupMark), findsNWidgets(2));

    // Still holding at 1000ms of the 1200ms hold.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('READY'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(find.text('READY'), findsNothing, reason: 'splash should be gone');
    expect(find.byType(CupMark), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('interaction', () {
    Future<void> pumpLanded(WidgetTester tester, {bool reduced = false}) async {
      await _pumpFlow(
        tester,
        _sizes['390x844']!,
        insets: _notch,
        reduced: reduced,
        onGetStarted: () {},
      );
      if (reduced) await tester.pump(const Duration(milliseconds: 1200));
      await settle(tester);
    }

    double cupFill(WidgetTester tester) =>
        tester.widget<CupMark>(find.byType(CupMark)).progress;

    testWidgets('tapping the mark drains it and re-extracts', (tester) async {
      await pumpLanded(tester);
      expect(cupFill(tester), 1, reason: 'at rest the cup is full');

      await tester.tap(find.byType(RebrewCupMark));
      await tester.pump(); // Lets the ticker register at elapsed zero.
      await tester.pump(const Duration(milliseconds: 200));
      expect(cupFill(tester), lessThan(0.5), reason: 'draining');

      await tester.pump(const Duration(milliseconds: 300));
      final refilling = cupFill(tester);
      expect(refilling, greaterThan(0));
      expect(refilling, lessThan(1), reason: 'mid re-extraction');

      await settle(tester);
      expect(cupFill(tester), 1, reason: 'settles back to full');
    });

    testWidgets('the whole CTA block is tappable, not just the label', (
      tester,
    ) async {
      var started = 0;
      await _pumpFlow(
        tester,
        _sizes['390x844']!,
        insets: _notch,
        onGetStarted: () => started++,
      );
      await settle(tester);

      final block = tester.getRect(find.byType(BrewTextButton));
      await tester.tapAt(Offset(block.left + 12, block.center.dy));
      await tester.pump();
      expect(started, 1, reason: 'the padding should take the tap too');
    });

    testWidgets('the CTA drops 1px on press and comes back up', (tester) async {
      await pumpLanded(tester);
      final atRest = tester.getTopLeft(find.text('Log in')).dy;

      final press = await tester.startGesture(
        tester.getCenter(find.text('Log in')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.getTopLeft(find.text('Log in')).dy - atRest,
        closeTo(1, 0.01),
        reason: 'translateY(1px), not a scale',
      );

      await press.up();
      await settle(tester);
      expect(tester.getTopLeft(find.text('Log in')).dy, closeTo(atRest, 0.01));
    });

    testWidgets('the action reports its destination', (tester) async {
      final log = <String>[];
      await _pumpFlow(
        tester,
        _sizes['390x844']!,
        insets: _notch,
        onGetStarted: () => log.add('/get-started'),
      );
      await settle(tester);

      await tester.tap(find.text('Log in'));
      await tester.pump();
      expect(log, <String>['/get-started']);
    });

    testWidgets('reduced motion: the mark holds still and the CTA does not '
        'move', (tester) async {
      await pumpLanded(tester, reduced: true);
      expect(cupFill(tester), 1);

      await tester.tap(find.byType(RebrewCupMark));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(cupFill(tester), 1, reason: 're-extraction is suppressed');

      final atRest = tester.getTopLeft(find.text('Log in')).dy;
      final press = await tester.startGesture(
        tester.getCenter(find.text('Log in')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.getTopLeft(find.text('Log in')).dy,
        closeTo(atRest, 0.01),
        reason: 'colour carries the whole press signal',
      );
      await press.up();
      await settle(tester);
    });
  });

  group('accessibility', () {
    testWidgets('the landing screen is silent to a screen reader until it '
        'lands', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpFlow(tester, _sizes['390x844']!, insets: _notch);

      // Mid-splash: the landing content is mounted but must not be announced.
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.bySemanticsLabel('Log in'),
        findsNothing,
        reason: 'landing is invisible here, so it must be out of semantics',
      );

      await settle(tester);
      expect(find.bySemanticsLabel('Log in'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the landing screen cannot be focused or activated by keyboard '
        'until it lands', (tester) async {
      var started = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BrewFlow(onGetStarted: () => started++),
        ),
      );

      // Mid-splash: tabbing must not reach the covered CTA, and Enter must not
      // fire it. AbsorbPointer only stops touches, not focus traversal.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(started, 0, reason: 'the splash must gate focus as well as touch');

      await settle(tester);

      // Once landed, keyboard traversal and activation both work.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(started, 1, reason: 'Enter should activate the focused control');
    });

    testWidgets('a disabled action neither fires nor animates', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(size: Size(390, 844)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 342,
                // No onPressed: this control is disabled.
                child: BrewPrimaryButton(label: 'Get started'),
              ),
            ),
          ),
        ),
      );

      final atRest = tester.getTopLeft(find.text('Get started')).dy;
      final press = await tester.startGesture(
        tester.getCenter(find.text('Get started')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.getTopLeft(find.text('Get started')).dy,
        closeTo(atRest, 0.01),
        reason: 'a disabled block should not take the press',
      );
      await press.up();
      await settle(tester);
    });
  });

  group('the live ledger icons', () {
    testWidgets('loop continuously without throwing', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: LedgerIcon(glyph: BrewGlyph.coffeeCup),
        ),
      );

      // Several full loop periods (2400ms each), well past the point where a
      // stale path-metric clamp or a NaN in the sine wobble would surface.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(LedgerIcon), findsOneWidget);
    });

    testWidgets('hold still under reduced motion', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: LedgerIcon(glyph: BrewGlyph.coffeeCup),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1200));

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(LedgerIcon), findsOneWidget);
    });
  });

  group('the landing flow', () {
    testWidgets('renders three visual step cards', (
      tester,
    ) async {
      await _pumpFlow(tester, _sizes['390x844']!, insets: _notch);
      await settle(tester);

      expect(find.text('Order ahead'), findsOneWidget);
      expect(find.text('Barista crafts'), findsOneWidget);
      expect(find.text('Grab & go'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);
    });

    testWidgets('display drops to 28 only at or below 667 tall', (tester) async {
      await _pumpFlow(tester, const Size(375, 667), insets: _notch);
      await settle(tester);
      expect(
        tester.widget<Text>(find.text('Made before you get there.')).style!.fontSize,
        28,
      );

      await _pumpFlow(tester, const Size(390, 844), insets: _notch);
      await settle(tester);
      expect(
        tester.widget<Text>(find.text('Made before you get there.')).style!.fontSize,
        34,
      );
    });
  });
}

/// Kept local to the test so the timings under test are stated here rather than
/// read back out of the implementation they are checking.
abstract final class BrewMotionProbe {
  /// 200ms container fade + 320ms stroke draw + 1900ms fill.
  static const splashRun = Duration(milliseconds: 2420);
}
