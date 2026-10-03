import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/screens/profile_panel.dart';
import 'package:quick_brew/theme/tokens.dart';

import 'support/fonts.dart';

/// The Profile tab on its own.
///
/// The cases home_screen_test.dart does not reach: an account whose display name
/// never got set, and a Log out with nothing wired to it.
void main() {
  setUpAll(loadBrandFonts);

  Future<int> pumpPanel(
    WidgetTester tester, {
    required BrewSession session,
    bool wired = true,
  }) async {
    var out = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: BrewColor.field,
          body: ProfilePanel(
            compact: false,
            session: session,
            onSignOut: wired ? () => out++ : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return out;
  }

  const dave = BrewSession(
    uid: 'dave',
    name: 'David Espino',
    email: 'david@work.com',
  );

  testWidgets('shows the full name here, not the greeting\'s first name', (
    tester,
  ) async {
    await pumpPanel(tester, session: dave);

    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('David Espino'), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('david@work.com'), findsOneWidget);
  });

  testWidgets('says the platform is one account for both shops', (tester) async {
    await pumpPanel(tester, session: dave);

    expect(find.text('One account, both coffee shops.'), findsOneWidget);
  });

  testWidgets('an unset name says so rather than leaving a blank rule', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      session: const BrewSession(uid: 'dave', email: 'david@work.com'),
    );

    expect(find.text('Not set'), findsOneWidget);
    // Held back, because it is the absence of a fact rather than a fact.
    final ink = tester.widget<Text>(find.text('Not set')).style!.color;
    final real = tester.widget<Text>(find.text('david@work.com')).style!.color;
    expect(ink!.a, lessThan(real!.a));
  });

  testWidgets('a name of only whitespace is still not set', (tester) async {
    await pumpPanel(
      tester,
      session: const BrewSession(uid: 'dave', name: '   ', email: 'd@work.com'),
    );

    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('Log out reports once per press and never navigates', (
    tester,
  ) async {
    var out = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: BrewColor.field,
          body: ProfilePanel(
            compact: false,
            session: dave,
            onSignOut: () => out++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(out, 1);
    // The session going is what moves the reader — see the rule in main.dart.
    expect(find.byType(ProfilePanel), findsOneWidget);
  });

  testWidgets('with nothing wired, Log out is disabled rather than silent', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpPanel(tester, session: dave, wired: false);

    expect(
      tester.getSemantics(find.text('Log out')),
      matchesSemantics(
        label: 'Log out',
        isButton: true,
        hasEnabledState: true,
        // Not enabled: a control with no callback reports that to a screen
        // reader instead of taking a press and dropping it.
        isEnabled: false,
        hasTapAction: false,
        hasFocusAction: false,
      ),
    );
    handle.dispose();
  });
}
