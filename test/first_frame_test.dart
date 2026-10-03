import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/main.dart';
import 'package:quick_brew/screens/admin/admin_home_screen.dart';
import 'package:quick_brew/screens/home_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// What the reader sees on the *first* frame of a signed-in screen, which is a
/// different question from what they see once everything has landed — and it was
/// the wrong answer twice over.
///
/// Both shops used to open on the enum's built-in "Drip & Co" and "Seven
/// Coffee & Tea" and then rename themselves a beat later, on every launch and every
/// login, because the first screen to mount was also the first thing to
/// subscribe. And an admin used to watch the customer home screen build itself
/// before being replaced by the dashboard, because a profile that has not been
/// read yet and an account with no profile are both `null`.
void main() {
  setUpAll(loadBrandFonts);

  const dave = BrewSession(uid: 'dave', email: 'david@work.com');

  /// A counter that has already answered once — the state main.dart's warm
  /// subscription leaves it in by the time any screen mounts.
  Future<BrewCounter> warmCounter(FakeFirebaseFirestore db) async {
    final counter = BrewCounter(db);
    await counter.shops().first;
    return counter;
  }

  Future<FakeFirebaseFirestore> renamedShops() async {
    final db = FakeFirebaseFirestore();
    await db.collection('shops').doc('coffee-shop-a').set({
      'name': 'Brew Lab',
      'description': 'Single origin, poured slow',
      'open': true,
    });
    await db.collection('shops').doc('coffee-shop-b').set({
      'name': 'The Kettle',
      'open': false,
    });
    return db;
  }

  void sizeTo(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  testWidgets('the shop cards open on the stored names, not the built-in pair',
      (tester) async {
    sizeTo(tester, const Size(390, 844));
    final counter = await warmCounter(await renamedShops());

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(session: dave, counter: counter)),
    );

    // One frame. No settle: the whole point is that the reader never sees the
    // enum's copy, not that it is gone by the time the fade finishes.
    expect(find.text('Brew Lab'), findsOneWidget);
    expect(find.text('The Kettle'), findsOneWidget);
    expect(find.text('Drip & Co'), findsNothing);
    expect(find.text('Seven Coffee & Tea'), findsNothing);
  });

  testWidgets('the hours mark opens on the stored answer rather than Checking '
      'hours', (tester) async {
    sizeTo(tester, const Size(390, 844));
    final counter = await warmCounter(await renamedShops());

    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(session: dave, counter: counter)),
    );

    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('CLOSED'), findsOneWidget);
    expect(find.text('CHECKING HOURS'), findsNothing);
  });

  testWidgets('a cold counter still opens on the built-in pair rather than on '
      'nothing', (tester) async {
    // The fallback is not gone, only rarer. A first-ever launch with an empty
    // cache still has two cards to draw, which is the property
    // [BrewShop.pending] exists for.
    sizeTo(tester, const Size(390, 844));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(session: dave, counter: BrewCounter(FakeFirebaseFirestore())),
      ),
    );

    expect(find.text('Drip & Co'), findsOneWidget);
    expect(find.text('Seven Coffee & Tea'), findsOneWidget);
  });

  testWidgets('the admin dashboard opens on the stored names too', (tester) async {
    sizeTo(tester, const Size(390, 844));
    final db = await renamedShops();
    final counter = await warmCounter(db);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomeScreen(
          profile: const BrewUserProfile(
            uid: 'dave',
            email: 'david@work.com',
            role: BrewRole.superadmin,
          ),
          admin: BrewAdmin(db),
          counter: counter,
        ),
      ),
    );

    expect(find.text('Brew Lab'), findsOneWidget);
    expect(find.text('The Kettle'), findsOneWidget);
    expect(find.text('Drip & Co'), findsNothing);
  });

  testWidgets('a build with no Firestore never holds anybody on a blank field',
      (tester) async {
    // The risk the profile gate introduces: waiting for an answer that is never
    // coming. Nothing here can read a role, so home must not be held back for
    // one — it goes straight to the customer app, as it did before the gate
    // existed.
    sizeTo(tester, const Size(390, 844));

    await tester.pumpWidget(
      QuickBrewApp(
        backend: Future.value((
          auth: BrewAuth(
            MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'dave', email: 'david@work.com'),
            ),
          ),
          counter: null,
          admin: null,
        )),
      ),
    );
    await settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a super admin lands on the dashboard without the customer home '
      'being built on the way', (tester) async {
    sizeTo(tester, const Size(390, 844));
    final db = await renamedShops();
    await db.collection('users').doc('dave').set({
      'email': 'david@work.com',
      'role': 'superadmin',
    });

    await tester.pumpWidget(
      QuickBrewApp(
        backend: Future.value((
          auth: BrewAuth(
            MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'dave', email: 'david@work.com'),
            ),
          ),
          counter: BrewCounter(db),
          admin: BrewAdmin(db),
        )),
      ),
    );

    // Stepped rather than settled, so the frames either side of the splash
    // handing over are actually looked at rather than skipped past.
    var sawCustomerHome = false;
    for (var elapsed = Duration.zero;
        elapsed < const Duration(milliseconds: 4000);
        elapsed += const Duration(milliseconds: 50)) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(HomeScreen).evaluate().isNotEmpty) sawCustomerHome = true;
    }

    expect(find.byType(AdminHomeScreen), findsOneWidget);
    expect(
      sawCustomerHome,
      isFalse,
      reason: 'the customer home screen must never be a step on the way to the '
          'dashboard',
    );
  });
}
