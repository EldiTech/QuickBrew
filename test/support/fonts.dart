import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the three shipped faces into the test engine.
///
/// Text metrics decide whether these layouts fit, so the real faces have to be
/// present. Without this the engine substitutes its test font, every glyph
/// measures 1em, and a passing layout assertion says nothing about the shipped
/// app.
Future<void> loadBrandFonts() async {
  const faces = <String, String>{
    'Fraunces': 'assets/fonts/Fraunces.ttf',
    'Hanken Grotesk': 'assets/fonts/HankenGrotesk.ttf',
    'Martian Mono': 'assets/fonts/MartianMono.ttf',
  };

  for (final MapEntry(key: family, value: path) in faces.entries) {
    final bytes = await File(path).readAsBytes();
    await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  }
}
