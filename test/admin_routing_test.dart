import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/main.dart';
import 'package:quick_brew/screens/admin/admin_home_screen.dart';
import 'package:quick_brew/screens/home_screen.dart';
import 'package:quick_brew/widgets/stagger.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The second routing rule, on top of "a session means home": **what
/// `users/{uid}` says decides which home.**
///
/// The cases here are the ones that actually went wrong on a device, not
/// hypotheticals. The first super admin is made by hand in the Firebase console
/// — there is deliberately no in-app path to that role — so the shapes a
/// hand-made document comes in are the shapes this has to survive.
void main() {
  setUpAll(loadBrandFonts);

  final dave = MockUser(
    uid: 'dave',
    email: 'david@work.com',
    displayName: 'David Espino',
  );

  Future<FakeFirebaseFirestore> pumpApp(
    WidgetTester tester, {
    Map<String, Object?>? profile,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    if (profile != null) {
      await db.collection('users').doc(dave.uid).set(profile);
    }

    await tester.pumpWidget(
      QuickBrewApp(
        backend: Future.value((
          auth: BrewAuth(MockFirebaseAuth(signedIn: true, mockUser: dave)),
          counter: BrewCounter(db),
          admin: BrewAdmin(db),
        )),
      ),
    );
    return db;
  }

  testWidgets('a hand-made super admin document with nothing but a role still '
      'reaches the admin dashboard', (tester) async {
    // Exactly what someone types into the console when told "set role to
    // superadmin": one field. Requiring an email alongside it used to read this
    // as no profile at all, which silently dropped the super admin onto the
    // customer app with nothing anywhere saying why.
    await pumpApp(tester, profile: {'role': 'superadmin'});
    await settle(tester);

    expect(find.byType(AdminHomeScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Admin dashboard.'), findsOneWidget);
  });

  testWidgets('a super admin sees both stores and the team actions',
      (tester) async {
    await pumpApp(tester, profile: {
      'email': 'david@work.com',
      'role': 'superadmin',
    });
    await settle(tester);

    expect(find.text('Drip & Co'), findsOneWidget);
    expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    expect(find.text('See all users'), findsOneWidget);
    expect(find.text('Create an admin'), findsOneWidget);
  });

  testWidgets('an admin sees only the one store assigned to them',
      (tester) async {
    await pumpApp(tester, profile: {
      'email': 'david@work.com',
      'role': 'admin',
      'assignedStore': 'coffee-shop-b',
    });
    await settle(tester);

    expect(find.byType(AdminHomeScreen), findsOneWidget);
    expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    expect(
      find.text('Drip & Co'),
      findsNothing,
      reason: 'an admin has no business configuring the other partner',
    );
    expect(
      find.text('Create an admin'),
      findsNothing,
      reason: 'only a super admin assigns credentials',
    );
  });

  testWidgets('an admin with no store assigned is told so rather than shown '
      'nothing', (tester) async {
    await pumpApp(tester, profile: {'email': 'x@work.com', 'role': 'admin'});
    await settle(tester);

    expect(find.byType(AdminHomeScreen), findsOneWidget);
    expect(find.textContaining('No store is assigned'), findsOneWidget);
  });

  /// The stagger timeline, across every combination of the two things that
  /// decide this screen's shape.
  ///
  /// `staggerCount` here is arithmetic — `teamBase + (_superadmin ? 3 : 0)` over
  /// `storeBase + stores.length` — and it is **deliberately left as arithmetic**.
  /// Read the note at admin_home_screen.dart:107-120: a running counter is what
  /// this screen shipped with and it failed twice over, because the store cards
  /// are allocated inside a StreamBuilder that had not run when the count was
  /// read, and that builder then re-ran on every snapshot and kept incrementing.
  /// orders_panel.dart could be converted because every slot there is dealt into
  /// a local before the children list is built; this screen cannot.
  ///
  /// So the arithmetic stays and these tests guard it instead. The check reads
  /// the largest index actually dealt off the tree and compares it to the
  /// group's own count, rather than pumping and asking whether anything threw:
  /// the store cards arrive from a snapshot, so they mount into a controller
  /// already past their cue and take [StaggerItem]'s `_late` ramp, which never
  /// constructs the [Interval] whose `end <= 1.0` is the assertion. Only one
  /// combination is live on any given frame, which is why one test here would
  /// prove nothing about the other three.
  group('admin dashboard stagger timeline', () {
    void expectIndicesInsideCount(WidgetTester tester) {
      final group = tester.widget<StaggerGroup>(find.byType(StaggerGroup).last);
      final indices = tester
          .widgetList<StaggerItem>(
            find.descendant(
              of: find.byWidget(group),
              matching: find.byType(StaggerItem),
            ),
          )
          .map((item) => item.index);

      expect(indices, isNotEmpty, reason: 'the dashboard deals rows');
      expect(
        indices.reduce((a, b) => a > b ? a : b),
        lessThan(group.itemCount),
        reason:
            'an index at or past itemCount falls off the end of the timeline',
      );
    }

    Future<void> pumpRole(
      WidgetTester tester, {
      required String role,
      String? store,
    }) async {
      await pumpApp(tester, profile: {
        'email': 'david@work.com',
        'role': role,
        'assignedStore': ?store,
      });
      await settle(tester);
      expect(find.byType(AdminHomeScreen), findsOneWidget);
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
    }

    testWidgets('a super admin: both stores and the three team rows', (
      tester,
    ) async {
      await pumpRole(tester, role: 'superadmin');
      expect(find.text('Create an admin'), findsOneWidget);
    });

    testWidgets('an admin with a store: one store, no team rows', (
      tester,
    ) async {
      await pumpRole(tester, role: 'admin', store: 'coffee-shop-b');
      expect(find.text('Create an admin'), findsNothing);
    });

    testWidgets('an admin with no store: the shortest the screen gets', (
      tester,
    ) async {
      // storeBase with nothing after it and no team block — the combination
      // where an off-by-one in the arithmetic has the least slack to hide in.
      await pumpRole(tester, role: 'admin');
      expect(find.textContaining('No store is assigned'), findsOneWidget);
    });

    testWidgets('a super admin with an unrecognised store still counts both', (
      tester,
    ) async {
      // A hand-made console document naming a store that is not one of the two.
      // The role decides the team block, the store list decides the rest, and
      // this is the pair disagreeing about which shape the screen is in.
      await pumpRole(tester, role: 'superadmin', store: 'coffee-shop-z');
      expect(find.text('Drip & Co'), findsOneWidget);
      expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    });
  });

  testWidgets('an ordinary customer gets the customer app', (tester) async {
    await pumpApp(tester, profile: {
      'email': 'david@work.com',
      'role': 'customer',
    });
    await settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AdminHomeScreen), findsNothing);
  });

  testWidgets('a first-time account is written as a customer, not an admin',
      (tester) async {
    final db = await pumpApp(tester);
    await settle(tester);

    final written = await db.collection('users').doc(dave.uid).get();
    expect(written.exists, isTrue, reason: 'the profile self-heals on login');
    expect(written.data()?['role'], 'customer');
    expect(written.data()?['email'], 'david@work.com');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('an account whose email has a pending invite claims it, and the '
      'invite is spent', (tester) async {
    final db = FakeFirebaseFirestore();
    // Keyed lower-case, the way BrewAdmin.inviteAdmin files it — and the way
    // the rules look it up again.
    await db.collection('invites').doc('david@work.com').set({
      'role': 'admin',
      'assignedStore': 'coffee-shop-a',
      'used': false,
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      QuickBrewApp(
        backend: Future.value((
          auth: BrewAuth(MockFirebaseAuth(signedIn: true, mockUser: dave)),
          counter: BrewCounter(db),
          admin: BrewAdmin(db),
        )),
      ),
    );
    await settle(tester);

    final written = await db.collection('users').doc(dave.uid).get();
    expect(written.data()?['role'], 'admin');
    expect(written.data()?['assignedStore'], 'coffee-shop-a');

    final invite = await db.collection('invites').doc('david@work.com').get();
    expect(
      invite.data()?['used'],
      isTrue,
      reason: 'an invite claimed twice is two admins from one offer',
    );

    expect(find.byType(AdminHomeScreen), findsOneWidget);
  });

  testWidgets('an invite already spent grants nothing', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('invites').doc('david@work.com').set({
      'role': 'admin',
      'assignedStore': 'coffee-shop-a',
      'used': true,
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      QuickBrewApp(
        backend: Future.value((
          auth: BrewAuth(MockFirebaseAuth(signedIn: true, mockUser: dave)),
          counter: BrewCounter(db),
          admin: BrewAdmin(db),
        )),
      ),
    );
    await settle(tester);

    final written = await db.collection('users').doc(dave.uid).get();
    expect(written.data()?['role'], 'customer');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('an existing profile is never overwritten by a later login',
      (tester) async {
    // The regression that would quietly demote every admin on their second
    // launch. ensureProfile has to return early on an existing document.
    final db = await pumpApp(tester, profile: {
      'email': 'david@work.com',
      'role': 'superadmin',
    });
    await settle(tester);

    final written = await db.collection('users').doc(dave.uid).get();
    expect(written.data()?['role'], 'superadmin');
    expect(find.byType(AdminHomeScreen), findsOneWidget);
  });
}
