import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/screens/login_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// A field's validation message is announced, not just drawn.
///
/// [BrewField] hangs its message by hand rather than through
/// `InputDecoration.errorText`, because the container above owns the rule and the
/// field draws none of its own chrome. The cost of that — until it was fixed —
/// was that hand-hung text is not something a screen reader has any reason to
/// read out: submitting the form with a bad address moved the caret and printed a
/// sentence, and a reader who could not see the sentence got only the caret.
void main() {
  setUpAll(loadBrandFonts);

  testWidgets('a rejected field announces why, the way a form-level failure does',
      (tester) async {
    // Disposed at the end of the body rather than through addTearDown: the
    // framework's own check for a leaked handle runs before teardowns do.
    final handle = tester.ensureSemantics();

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await settle(tester);

    const message = 'Enter the email you signed up with.';
    expect(find.text(message), findsNothing);

    // Submitting empty is the shortest path to a field-level rejection.
    await tester.tap(find.text('Log in'));
    await settle(tester);

    expect(find.text(message), findsOneWidget);

    expect(
      tester.getSemantics(find.text(message)),
      // A live region is announced when it arrives rather than only when the
      // reader happens to swipe onto it, which is the whole point: they pressed
      // Log in and the answer has to reach them.
      isSemantics(label: message, isLiveRegion: true),
    );

    handle.dispose();
  });
}
