import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_flow.dart';

import 'support/settle.dart';

/// Both screens are fixed at viewport height with no scrolling, so system font
/// scaling is the one input that can break them. Measured before the cap was
/// added: the smallest frame fits 1.3x and overflows at 1.5x, which in release
/// pushes Log in off the screen entirely.
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

void main() {
  setUpAll(_loadBrandFonts);

  // 2.0 is the top of Android's accessibility font range.
  for (final scale in <double>[1.0, 1.3, 1.5, 2.0]) {
    testWidgets('survives ${scale}x system text on the smallest frame', (
      tester,
    ) async {
      const size = Size(375, 667);
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
              padding: const EdgeInsets.only(top: 44, bottom: 34),
              textScaler: TextScaler.linear(scale),
            ),
            child: const BrewFlow(),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Log in'), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
    });
  }
}
