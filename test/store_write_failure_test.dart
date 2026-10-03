import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/admin_menu_screen.dart';
import 'package:quick_brew/screens/admin/store_config_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// A refused write on the store editor says so, rather than throwing into
/// nowhere.
///
/// Four writes on this screen used to hand back a raw Firestore future that
/// nothing awaited: the hours toggle, and adding, editing and deleting a board
/// item. The rules let a plain admin write one shop, so a refusal here is
/// ordinary rather than exotic — and the toggle and the board both draw
/// themselves from the stream, so a refused write leaves them looking exactly as
/// they did with nothing anywhere saying why.
void main() {
  setUpAll(loadBrandFonts);

  Future<FakeFirebaseFirestore> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('shops').doc('coffee-shop-a').set({
      'name': 'Brew Lab',
      'description': 'Single origin, poured slow',
      'open': false,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StoreConfigScreen(
          partner: BrewPartner.a,
          admin: BrewAdmin(db),
          counter: BrewCounter(db),
        ),
      ),
    );
    await settle(tester);
    return db;
  }

  final denied = FirebaseException(
    plugin: 'cloud_firestore',
    code: 'permission-denied',
  );

  testWidgets('a refused hours toggle reports instead of failing silently', (
    tester,
  ) async {
    final db = await pump(tester);
    expect(find.text('CLOSED'), findsWidgets);

    whenCalling(Invocation.method(#set, null))
        .on(db.collection('shops').doc('coffee-shop-a'))
        .thenThrow(denied);

    // The whole block is the control — the "Tap to open →" line it used to
    // carry was dropped when the toggle moved into a half-width bento tile
    // with no room for it beside the status.
    await tester.tap(find.text('CLOSED').first);
    await settle(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'the refusal must not escape as an unhandled async error',
    );
    expect(find.text('That did not go through. Try again.'), findsOneWidget);
    // And the toggle still tells the truth about what the shop is.
    expect(find.text('CLOSED'), findsWidgets);
  });

  /// One item on the board, so the edit and delete paths have something to act
  /// on. Written straight to Firestore rather than through the sheet, which is
  /// the thing under test in the two cases below.
  Future<DocumentReference<Map<String, dynamic>>> seedItem(
    FakeFirebaseFirestore db,
  ) async {
    final item = db
        .collection('shops')
        .doc('coffee-shop-a')
        .collection('menu')
        .doc('latte');
    await item.set({'name': 'Iced Latte', 'priceCents': 450});
    return item;
  }

  testWidgets('a refused board edit reports instead of failing silently', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('shops').doc('coffee-shop-a').set({'open': true});
    final item = await seedItem(db);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminMenuScreen(
          partner: BrewPartner.a,
          admin: BrewAdmin(db),
          counter: BrewCounter(db),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Iced Latte'), findsOneWidget);

    whenCalling(Invocation.method(#set, null)).on(item).thenThrow(denied);

    // Reopening the item and saving it unchanged is enough: the write goes out
    // either way, and it is the write being refused that is under test. Only the
    // sheet's own button is titled exactly "Save" — the identity section's says
    // "Save profile" — so this cannot land on the wrong one.
    await tester.tap(find.text('EDIT'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'the refusal must not escape as an unhandled async error',
    );
    expect(find.text('That product did not save. Try again.'), findsOneWidget);
    // The board still says what the board actually holds.
    expect(find.text('Iced Latte'), findsOneWidget);
  });

  testWidgets('a refused delete reports instead of failing silently', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('shops').doc('coffee-shop-a').set({'open': true});
    final item = await seedItem(db);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminMenuScreen(
          partner: BrewPartner.a,
          admin: BrewAdmin(db),
          counter: BrewCounter(db),
        ),
      ),
    );
    await settle(tester);

    whenCalling(Invocation.method(#delete, null)).on(item).thenThrow(denied);

    await tester.tap(find.text('DELETE'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.text('That product did not come off the board. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Iced Latte'), findsOneWidget);
  });

  testWidgets('a board write that lands says nothing at all', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('shops').doc('coffee-shop-a').set({'open': true});
    await tester.pumpWidget(
      MaterialApp(
        home: AdminMenuScreen(
          partner: BrewPartner.a,
          admin: BrewAdmin(db),
          counter: BrewCounter(db),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('ADD PRODUCT'));
    await settle(tester);
    final inSheet =
        find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
    await tester.enterText(inSheet.first, 'Iced Latte');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('That product did not save. Try again.'), findsNothing);
    expect(find.text('Iced Latte'), findsOneWidget);
  });
}
