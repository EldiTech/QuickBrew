import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/home_screen.dart';
import 'package:quick_brew/screens/landing_screen.dart';
import 'package:quick_brew/screens/menu_screen.dart';
import 'package:quick_brew/screens/splash_screen.dart';

import 'support/settle.dart';

/// Reference renders. Regenerate with:
///   flutter test --update-goldens test/goldens_test.dart
///
/// These are rasterised references, so they are sensitive to the host's text
/// rendering. Treat a diff as a prompt to look at the image, not as a failure.
const _frame = Size(390, 844);
const _notch = EdgeInsets.only(top: 44, bottom: 34);
const _shot = Key('shot');

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

Future<void> _shoot(
  WidgetTester tester,
  Widget child,
  String name, {
  Size frame = _frame,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = frame;
  addTearDown(tester.view.reset);

  await pumpAndWarm(
    tester,
    RepaintBoundary(
      key: _shot,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Localizations(
          locale: const Locale('en', 'US'),
          delegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: MediaQuery(
            data: MediaQueryData(size: frame, padding: _notch),
            child: child,
          ),
        ),
      ),
    ),
  );
  await settle(tester);

  await expectLater(
    find.byKey(_shot),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  setUpAll(_loadBrandFonts);

  testWidgets('splash, outline half drawn', (tester) async {
    await _shoot(
      tester,
      SplashScreen(
        progress: 0,
        strokeProgress: 0.5,
        cupSlotKey: GlobalKey(),
        showCupInSlot: true,
      ),
      'splash_drawing',
    );
  });

  testWidgets('splash, empty cup', (tester) async {
    await _shoot(
      tester,
      SplashScreen(
        progress: 0,
        strokeProgress: 1,
        cupSlotKey: GlobalKey(),
        showCupInSlot: true,
      ),
      'splash_00',
    );
  });

  testWidgets('splash, mid extraction', (tester) async {
    await _shoot(
      tester,
      SplashScreen(
        progress: 0.55,
        strokeProgress: 1,
        cupSlotKey: GlobalKey(),
        showCupInSlot: true,
      ),
      'splash_55',
    );
  });

  testWidgets('splash, ready', (tester) async {
    await _shoot(
      tester,
      SplashScreen(
        progress: 1,
        strokeProgress: 1,
        cupSlotKey: GlobalKey(),
        showCupInSlot: true,
      ),
      'splash_ready',
    );
  });

  testWidgets('landing, revealed', (tester) async {
    await _shoot(
      tester,
      LandingScreen(
        cupSlotKey: GlobalKey(),
        showCupInSlot: true,
        reveal: true,
        reduced: false,
      ),
      'landing',
    );
  });

  // The frame the Pixel 7 emulator actually reports, so what ships to a device
  // is reviewable here rather than only on the 390x844 design frame.
  testWidgets('landing, Pixel 7 frame', (tester) async {
    await _shoot(
      tester,
      LandingScreen(
        cupSlotKey: GlobalKey(),
        showCupInSlot: true,
        reveal: true,
        reduced: false,
      ),
      'landing_pixel7',
      frame: const Size(412, 915),
    );
  });

  testWidgets('landing, compact frame', (tester) async {
    await _shoot(
      tester,
      LandingScreen(
        cupSlotKey: GlobalKey(),
        showCupInSlot: true,
        reveal: true,
        reduced: false,
      ),
      'landing_compact',
      frame: const Size(375, 667),
    );
  });

  group('the signed-in screens', () {
    /// A counter with both shops seeded, and optionally an order in progress.
    ///
    /// Seeded through the real `BrewCounter` against a fake Firestore rather than
    /// by handing the screen ready-made objects, so what these images show is the
    /// shipped read path — the same one a device runs.
    Future<BrewCounter> counter({
      bool aOpen = true,
      bool bOpen = true,
      String? orderStage,
      DateTime? scheduledFor,
    }) async {
      final db = FakeFirebaseFirestore();
      await db.collection('shops').doc(BrewPartner.a.id).set({'open': aOpen});
      await db.collection('shops').doc(BrewPartner.b.id).set({'open': bOpen});
      if (orderStage != null) {
        // A fixed document id, not an autoId. The card prints a reference cut
        // from it — see [BrewOrder.reference] — so an order added the ordinary
        // way would put four random characters in every one of these images and
        // fail the comparison on the next run.
        await db.collection('orders').doc('goldenorder0248').set({
          'uid': 'dave',
          'shop': BrewPartner.a.id,
          // One plain drink and one with extras on it, so the image covers both
          // shapes the order card's item rows draw.
          'items': [
            'Iced Latte (Large) + Extra shot, Oat milk',
            'Croissant',
          ],
          'stage': orderStage,
          'etaLowMinutes': 10,
          'etaHighMinutes': 15,
          if (scheduledFor case final at?) 'scheduledFor': Timestamp.fromDate(at),
          'placedAt': Timestamp.fromDate(DateTime(2026, 7, 25, 9)),
        });
      }
      return BrewCounter(db);
    }

    /// Fixed at 9am, or the greeting in these images would change by the hour and
    /// every one of them would fail overnight.
    Widget home(BrewCounter layer) => HomeScreen(
      session: const BrewSession(
        uid: 'dave',
        name: 'David Espino',
        email: 'david@work.com',
      ),
      counter: layer,
      now: DateTime(2026, 7, 25, 9),
      onViewMenu: (_) {},
      onSignOut: () {},
    );

    testWidgets('home, both shops open, nothing in progress', (tester) async {
      await _shoot(tester, home(await counter()), 'home');
    });

    testWidgets('home, an order being made', (tester) async {
      await _shoot(
        tester,
        home(
          await counter(
            orderStage: 'preparing',
            // Collected this evening, so the card's pickup fact shows the
            // scheduled shape. The Pixel 7 frame below keeps the other one —
            // an order for now, which prints "As soon as ready".
            scheduledFor: DateTime(2026, 7, 25, 17, 45),
          ),
        ),
        'home_order',
      );
    });

    testWidgets('home, one shop closed', (tester) async {
      await _shoot(tester, home(await counter(bOpen: false)), 'home_closed');
    });

    testWidgets('home, Pixel 7 frame', (tester) async {
      await _shoot(
        tester,
        home(await counter(orderStage: 'ready')),
        'home_pixel7',
        frame: const Size(412, 915),
      );
    });

    testWidgets('a shop\'s board', (tester) async {
      final db = FakeFirebaseFirestore();
      final menu = db
          .collection('shops')
          .doc(BrewPartner.a.id)
          .collection('menu');
      await menu.add({
        'name': 'Espresso',
        'description': 'Two shots, no room',
        'priceCents': 300,
        'sort': 10,
      });
      await menu.add({
        'name': 'Iced Latte',
        'description': 'Double shot over ice, whole or oat',
        'priceCents': 450,
        'sort': 20,
      });
      await menu.add({
        'name': 'Croissant',
        'description': 'Baked on site each morning',
        'priceCents': 375,
        'sort': 30,
      });

      await _shoot(
        tester,
        MenuScreen(
          shop: const BrewShop(
            partner: BrewPartner.a,
            status: BrewShopStatus.open,
          ),
          counter: BrewCounter(db),
        ),
        'menu',
      );
    });
  });
}
