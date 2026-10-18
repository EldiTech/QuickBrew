import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/admin_whole_menu_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// An admin whose read of the saved boards is refused — what a shop sees when
/// the `whole_menu` rule has not been deployed yet.
class _RefusedAdmin extends BrewAdmin {
  _RefusedAdmin(super.db);

  @override
  Stream<List<BrewWholeMenuBoard>> wholeMenuFor(BrewPartner partner) =>
      Stream.error(StateError('permission-denied'));
}

void main() {
  setUpAll(loadBrandFonts);

  Future<void> pumpScreen(
    WidgetTester tester, {
    required BrewAdmin admin,
    BrewPartner partner = BrewPartner.b,
  }) async {
    // A 360dp phone at a larger system text size: the width the header, the
    // collection line and the Add Board row all overflowed at on a device.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 800),
          textScaler: TextScaler.linear(1.3),
        ),
        child: MaterialApp(
          home: AdminWholeMenuScreen(partner: partner, admin: admin),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('fits a 360dp phone and lists the bundled boards', (
    tester,
  ) async {
    await pumpScreen(tester, admin: BrewAdmin(FakeFirebaseFirestore()));

    expect(tester.takeException(), isNull);
    expect(find.text('CONFIGURED BOARDS (7)'), findsOneWidget);
    expect(find.text('Add Board'), findsOneWidget);
  });

  testWidgets('a refused read shows the bundled boards and says so, not zero', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      admin: _RefusedAdmin(FakeFirebaseFirestore()),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not load the saved boards'), findsOneWidget);
    expect(find.text('CONFIGURED BOARDS (7)'), findsOneWidget);
    expect(find.textContaining('No menu boards configured'), findsNothing);
  });
}
