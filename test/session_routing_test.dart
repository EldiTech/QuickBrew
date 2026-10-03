import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/main.dart';
import 'package:quick_brew/screens/create_account_screen.dart';
import 'package:quick_brew/screens/home_screen.dart';
import 'package:quick_brew/screens/login_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The one routing rule in the app: **a session means home.**
///
/// This is the test that matters most in this pass, because the rule is stated in
/// exactly one place and everything else in the app depends on it being true —
/// no screen navigates on a successful submit, so if this is wrong, logging in
/// leaves the reader sitting on the form that just worked.
void main() {
  setUpAll(loadBrandFonts);

  final dave = MockUser(
    uid: 'dave',
    email: 'david@work.com',
    displayName: 'David Espino',
  );

  /// The whole app, with a backend that resolves the way the real one does.
  Future<void> pumpApp(
    WidgetTester tester, {
    MockFirebaseAuth? auth,
    bool firestore = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = firestore ? FakeFirebaseFirestore() : null;
    await tester.pumpWidget(
      QuickBrewApp(
        backend: Future.value((
          auth: auth == null ? null : BrewAuth(auth),
          counter: db == null ? null : BrewCounter(db),
          admin: db == null ? null : BrewAdmin(db),
        )),
      ),
    );
  }

  testWidgets('a returning reader gets the full splash, then home — never the '
      'landing screen', (tester) async {
    await pumpApp(tester, auth: MockFirebaseAuth(signedIn: true, mockUser: dave));

    // Mid-extraction the session is already known, and it has changed nothing:
    // cutting the splash short to save a second and a half would be the one
    // moment in the app where the cup jumps.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('EXTRACTING'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    await settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Good '), findsOneWidget);
    expect(
      find.text('Made before you get there.'),
      findsNothing,
      reason: 'a signed-in reader has no business on the landing screen',
    );
  });

  testWidgets('a signed-out reader lands on the landing screen and stays there',
      (tester) async {
    await pumpApp(tester, auth: MockFirebaseAuth());
    await settle(tester);

    expect(find.text('Made before you get there.'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('logging in takes the form off the stack and lands on home',
      (tester) async {
    final auth = MockFirebaseAuth(mockUser: dave);
    await pumpApp(tester, auth: auth);
    await settle(tester);

    await tester.tap(find.text('Log in'));
    await settle(tester, const Duration(milliseconds: 1200));
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'david@work.com');
    await tester.enterText(find.byType(TextField).last, 'flatwhite1');
    await tester.tap(find.text('Log in'));
    await settle(tester, const Duration(milliseconds: 1200));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      find.byType(LoginScreen),
      findsNothing,
      reason: 'the form the reader just finished with must not be behind home',
    );
    // The greeting's opener follows the wall clock the suite happens to run at,
    // so this asserts the half that is the app's doing: the name.
    expect(find.textContaining('David!'), findsOneWidget);
  });

  testWidgets('a rejected log in stays on the form and says why', (tester) async {
    final auth = MockFirebaseAuth();
    // The rejection a real project with email-enumeration protection sends back
    // for both a wrong address and a wrong password.
    whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
        .on(auth)
        .thenThrow(FirebaseAuthException(code: 'invalid-credential'));

    await pumpApp(tester, auth: auth);
    await settle(tester);

    await tester.tap(find.text('Log in'));
    await settle(tester, const Duration(milliseconds: 1200));

    await tester.enterText(find.byType(TextField).first, 'nobody@work.com');
    await tester.enterText(find.byType(TextField).last, 'flatwhite1');
    await tester.tap(find.text('Log in'));
    await settle(tester, const Duration(milliseconds: 1200));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(
      find.text('That email and password do not match an account.'),
      findsOneWidget,
    );
  });

  testWidgets('signing up goes straight to home, past the landing screen',
      (tester) async {
    final auth = MockFirebaseAuth();
    await pumpApp(tester, auth: auth);
    await settle(tester);

    await tester.tap(find.text('Log in'));
    await settle(tester, const Duration(milliseconds: 1200));
    await tester.tap(find.text('Create an account'));
    await settle(tester, const Duration(milliseconds: 1200));
    expect(find.byType(CreateAccountScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'David');
    await tester.enterText(find.byType(TextField).at(1), 'david@work.com');
    await tester.enterText(find.byType(TextField).at(2), 'flatwhite1');
    await tester.tap(find.text('Create account'));
    await settle(tester, const Duration(milliseconds: 1200));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CreateAccountScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('logging out returns to the landing screen without replaying the '
      'splash', (tester) async {
    await pumpApp(tester, auth: MockFirebaseAuth(signedIn: true, mockUser: dave));
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.text('PROFILE'));
    await settle(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('Log out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Made before you get there.'), findsOneWidget);
    expect(
      find.text('EXTRACTING'),
      findsNothing,
      reason: 'the splash is spent; it earns its time once per launch',
    );
  });

  testWidgets('with no Firebase at all the app still starts and says so on the '
      'form', (tester) async {
    await pumpApp(tester, auth: null, firestore: false);
    await settle(tester);

    expect(find.text('Made before you get there.'), findsOneWidget);

    await tester.tap(find.text('Log in'));
    await settle(tester, const Duration(milliseconds: 1200));
    await tester.enterText(find.byType(TextField).first, 'david@work.com');
    await tester.enterText(find.byType(TextField).last, 'flatwhite1');
    await tester.tap(find.text('Log in'));
    await settle(tester, const Duration(milliseconds: 1200));

    expect(
      find.text('Accounts are not connected in this build.'),
      findsOneWidget,
    );
  });
}
