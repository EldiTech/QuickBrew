import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/main.dart';
import 'package:quick_brew/screens/create_account_screen.dart';
import 'package:quick_brew/screens/login_screen.dart';
import 'package:quick_brew/widgets/brew_field.dart';

import 'support/settle.dart';

/// Same reason as quick_brew_test.dart: the real faces decide the metrics.
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

Future<void> _pumpCreateAccount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Future<BrewAuthFailure?> Function(String name, String email, String password)?
      onSubmit,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            CreateAccountScreen.route(onSubmit: onSubmit),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester, const Duration(milliseconds: 1200));
}

/// The three fields in the order they are read.
Finder _field(int index) => find.byType(TextField).at(index);

/// Whether the field at [index] holds the caret.
bool _focused(WidgetTester tester, int index) =>
    tester.widget<TextField>(_field(index)).focusNode?.hasFocus ?? false;

void main() {
  setUpAll(_loadBrandFonts);

  testWidgets('three ruled fields, one Create account, and the way back',
      (tester) async {
    await _pumpCreateAccount(tester);

    expect(find.text('Start ordering ahead.'), findsOneWidget);
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);

    // No fourth field, and nothing to agree to: both are deliberate.
    expect(find.text('CONFIRM PASSWORD'), findsNothing);
  });

  testWidgets('the password requirement is stated before it is broken',
      (tester) async {
    await _pumpCreateAccount(tester);

    expect(find.text('AT LEAST 8 CHARACTERS'), findsOneWidget);

    await tester.enterText(_field(2), 'short');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    // The error takes the note's line rather than stacking under it.
    expect(find.text('Passwords are at least 8 characters.'), findsOneWidget);
    expect(find.text('AT LEAST 8 CHARACTERS'), findsNothing);
  });

  testWidgets('an empty form reports all three at once and submits nothing',
      (tester) async {
    var submitted = 0;
    await _pumpCreateAccount(tester, onSubmit: (_, _, _) async {
      submitted++;
      return null;
    });

    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Tell us what to call you.'), findsOneWidget);
    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Pick a password.'), findsOneWidget);
    expect(submitted, 0);
  });

  testWidgets('a valid form hands trimmed values to the caller',
      (tester) async {
    String? name;
    String? email;
    String? password;
    await _pumpCreateAccount(tester, onSubmit: (n, e, p) async {
      name = n;
      email = e;
      password = p;
      return null;
    });

    await tester.enterText(_field(0), '  Dave  ');
    await tester.enterText(_field(1), ' dave@work.com ');
    await tester.enterText(_field(2), 'flatwhite');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(name, 'Dave');
    expect(email, 'dave@work.com');
    expect(password, 'flatwhite');
  });

  /// Fills the form with values that pass every local rule, so what the test
  /// exercises next is the round trip rather than the validation.
  Future<void> fillValid(WidgetTester tester) async {
    await tester.enterText(_field(0), 'Dave');
    await tester.enterText(_field(1), 'dave@work.com');
    await tester.enterText(_field(2), 'flatwhite');
  }

  testWidgets('the button holds the wait and refuses a second press',
      (tester) async {
    final inFlight = Completer<BrewAuthFailure?>();
    var calls = 0;
    await _pumpCreateAccount(tester, onSubmit: (_, _, _) {
      calls++;
      return inFlight.future;
    });

    await fillValid(tester);
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Creating account…'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);

    // A second press while the first is still out must not create a second
    // account.
    await tester.tap(find.text('Creating account…'));
    await tester.pump();
    expect(calls, 1);

    inFlight.complete(null);
    await tester.pump();

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Creating account…'), findsNothing);
  });

  testWidgets('a taken address is reported under the email field',
      (tester) async {
    await _pumpCreateAccount(
      tester,
      onSubmit: (_, _, _) async => BrewAuthFailure.fromCode(
        'email-already-in-use',
      ),
    );

    await fillValid(tester);
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(
      find.text('That email already has an account. Log in instead.'),
      findsOneWidget,
    );
    // The caret goes where the fix is.
    expect(_focused(tester, 1), isTrue);

    // And it clears the moment the address it was about starts changing.
    await tester.enterText(_field(1), 'dave@home.com');
    await tester.pump();
    expect(
      find.text('That email already has an account. Log in instead.'),
      findsNothing,
    );
  });

  testWidgets('a failure that belongs to no field sits above the button',
      (tester) async {
    await _pumpCreateAccount(
      tester,
      onSubmit: (_, _, _) async => BrewAuthFailure.fromCode(
        'network-request-failed',
      ),
    );

    await fillValid(tester);
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(
      find.text('No connection. Check the network and try again.'),
      findsOneWidget,
    );
    // No field is at fault, so none of them is marked and the caret stays put.
    expect(find.byType(BrewField), findsNWidgets(3));
    for (final field in tester.widgetList<BrewField>(find.byType(BrewField))) {
      expect(field.errorText, isNull);
    }

    // The next attempt starts from a clean slate rather than stacking messages.
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(
      find.text('No connection. Check the network and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('the new password is obscured until Show is tapped',
      (tester) async {
    await _pumpCreateAccount(tester);

    TextField password() => tester.widget<TextField>(_field(2));

    expect(password().obscureText, isTrue);
    expect(password().autofillHints, contains(AutofillHints.newPassword));

    await tester.tap(find.text('SHOW'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(password().obscureText, isFalse);
  });

  testWidgets('login and back again, through the real app', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await pumpAndWarm(tester, const QuickBrewApp());
    await settle(tester);

    await tester.tap(find.text('Log in'));
    await settle(tester, const Duration(milliseconds: 1200));
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.text('Create an account'));
    await settle(tester, const Duration(milliseconds: 1200));
    expect(find.byType(CreateAccountScreen), findsOneWidget);

    // Typed-in login state survives the detour, because create-account is
    // pushed over that form rather than replacing it.
    await tester.tap(find.text('I already have an account'));
    await settle(tester, const Duration(milliseconds: 1200));

    expect(find.byType(CreateAccountScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('the form still reaches Create account with the keyboard up',
      (tester) async {
    await _pumpCreateAccount(tester, size: const Size(375, 667));
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('Create account'),
      find.byType(SingleChildScrollView),
      const Offset(0, -60),
    );

    expect(find.text('Create account'), findsOneWidget);
  });
}
