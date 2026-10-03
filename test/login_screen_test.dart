import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/main.dart';
import 'package:quick_brew/screens/login_screen.dart';
import 'package:quick_brew/theme/tokens.dart';

import 'support/settle.dart';

/// Same reason as quick_brew_test.dart: the real faces decide the metrics, and
/// without them every glyph measures 1em.
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

/// The login screen inside a Navigator, so the route push, the Back affordance
/// and the text-selection overlay all have what they need.
Future<void> _pumpLogin(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Future<BrewAuthFailure?> Function(String email, String password)? onSubmit,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            LoginScreen.route(onSubmit: onSubmit),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester, const Duration(milliseconds: 1200));
}

void main() {
  setUpAll(_loadBrandFonts);

  testWidgets('the form is the ledger: two ruled fields and one Log in',
      (tester) async {
    await _pumpLogin(tester);

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });

  testWidgets('an empty form reports both fields and submits nothing',
      (tester) async {
    var submitted = 0;
    await _pumpLogin(tester, onSubmit: (_, _) async {
      submitted++;
      return null;
    });

    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.text('Enter the email you signed up with.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(submitted, 0);
  });

  testWidgets('a malformed address is caught locally and clears on edit',
      (tester) async {
    await _pumpLogin(tester);

    await tester.enterText(find.byType(TextField).first, 'dave');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(
      find.text('That address is missing a @ or a domain.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, 'dave@work.com');
    await tester.pump();
    expect(
      find.text('That address is missing a @ or a domain.'),
      findsNothing,
    );
  });

  testWidgets('a valid form hands the trimmed email to the caller',
      (tester) async {
    String? email;
    String? password;
    await _pumpLogin(tester, onSubmit: (e, p) async {
      email = e;
      password = p;
      return null;
    });

    await tester.enterText(find.byType(TextField).first, '  dave@work.com  ');
    await tester.enterText(find.byType(TextField).last, 'flatwhite');
    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(email, 'dave@work.com');
    expect(password, 'flatwhite');
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('the password is obscured until Show is tapped', (tester) async {
    await _pumpLogin(tester);

    TextField password() => tester.widget<TextField>(
          find.byType(TextField).last,
        );

    expect(password().obscureText, isTrue);
    expect(find.text('SHOW'), findsOneWidget);

    await tester.tap(find.text('SHOW'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(password().obscureText, isFalse);
    expect(find.text('HIDE'), findsOneWidget);
  });

  testWidgets("a field's hairline brightens to cream while it holds focus",
      (tester) async {
    await _pumpLogin(tester);

    Color rule(int index) {
      final container = tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decorations = container
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.border is Border)
          .toList();
      return (decorations[index].border! as Border).bottom.color;
    }

    expect(rule(0), BrewColor.hairline);

    await tester.tap(find.byType(TextField).first);
    await tester.pump(const Duration(milliseconds: 120));

    expect(rule(0), BrewColor.fieldFocus);

    // Error outranks focus, so the field being typed in keeps saying so.
    await tester.enterText(find.byType(TextField).first, 'dave');
    await tester.tap(find.text('Log in'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(rule(0), BrewColor.alert);
  });

  testWidgets('Back returns to the screen that pushed it', (tester) async {
    await _pumpLogin(tester);

    expect(find.text('BACK'), findsOneWidget);
    await tester.tap(find.text('BACK'));
    await settle(tester, const Duration(milliseconds: 1200));

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets("the landing screen's Log in is what pushes this screen",
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    // The real app, so the wiring in main.dart is what's under test.
    await pumpAndWarm(tester, const QuickBrewApp());
    await settle(tester);

    expect(find.byType(LoginScreen), findsNothing);
    await tester.tap(find.text('Log in'));
    await settle(tester, const Duration(milliseconds: 1200));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Welcome back.'), findsOneWidget);
  });

  testWidgets('the form still reaches Log in with the keyboard up',
      (tester) async {
    // 375x667 with a 336px keyboard: the tightest case, and the reason the
    // screen scrolls where the landing screen does not.
    await _pumpLogin(tester, size: const Size(375, 667));
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('Log in'),
      find.byType(SingleChildScrollView),
      const Offset(0, -60),
    );

    expect(find.text('Log in'), findsOneWidget);
  });
}
