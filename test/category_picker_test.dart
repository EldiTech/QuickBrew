import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/admin_menu_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The item sheet's category and sub-category pickers: a grid of what the
/// board already uses, with an "Add new" tile to grow the set, rather than
/// the free-text fields these used to be.
void main() {
  setUpAll(loadBrandFonts);

  Future<FakeFirebaseFirestore> pumpAddSheet(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    final menu = db.collection('shops').doc(BrewPartner.b.id).collection('menu');
    await menu.add({
      'name': 'Dirty Avalanche',
      'category': 'Iced Blended',
      'subCategory': 'Frappe Series',
      'priceCents': 8000,
    });
    await menu.add({
      'name': 'Fruit Tea',
      'category': 'Refresher',
      'priceCents': 4000,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AdminMenuScreen(
          partner: BrewPartner.b,
          admin: BrewAdmin(db),
          counter: BrewCounter(db),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('ADD PRODUCT'));
    await settle(tester);

    return db;
  }

  testWidgets('offers the board\'s existing categories as a grid', (
    tester,
  ) async {
    await pumpAddSheet(tester);

    expect(find.text('Iced Blended'), findsOneWidget);
    expect(find.text('Refresher'), findsOneWidget);
    expect(find.text('+ Add new'), findsWidgets);
    // Two per row: the grid is [BrewGrid], the same layout the board itself
    // uses, so the first pair shares a row.
    final first = tester.getTopLeft(find.text('Iced Blended'));
    final second = tester.getTopLeft(find.text('Refresher'));
    expect(first.dy, second.dy);
    expect(first.dx, lessThan(second.dx));
  });

  testWidgets('no sub-category grid until a category is chosen', (
    tester,
  ) async {
    await pumpAddSheet(tester);

    expect(find.text('SUB-CATEGORY (OPTIONAL)'), findsNothing);

    await tester.tap(find.text('Iced Blended'));
    await settle(tester);

    expect(find.text('SUB-CATEGORY (OPTIONAL)'), findsOneWidget);
    expect(find.text('Frappe Series'), findsOneWidget);
  });

  testWidgets('choosing a new category clears the previous sub-category pick', (
    tester,
  ) async {
    await pumpAddSheet(tester);

    await tester.tap(find.text('Iced Blended'));
    await settle(tester);
    await tester.tap(find.text('Frappe Series'));
    await settle(tester);

    await tester.tap(find.text('Refresher'));
    await settle(tester);

    // The sub-category grid stays offered — Refresher can still be given
    // its own sub-categories — but Frappe Series belonged to the category
    // just left behind and does not carry over as a stale pick.
    expect(find.text('SUB-CATEGORY (OPTIONAL)'), findsOneWidget);
    expect(find.text('Frappe Series'), findsNothing);
  });

  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(BottomSheet), matching: matching);

  testWidgets('typing a new category and confirming Add picks it', (
    tester,
  ) async {
    await pumpAddSheet(tester);

    await tester.tap(find.text('+ Add new').first);
    await settle(tester);

    // Name and Description are already on screen ahead of it, so the new
    // category's own field is the third inside the sheet.
    await tester.enterText(inSheet(find.byType(TextField)).at(2), 'Milktea');
    await tester.tap(inSheet(find.text('ADD')));
    await settle(tester);

    // The new category is now the pick, offered as a lit tile rather than
    // left in the text field.
    expect(find.text('Milktea'), findsOneWidget);
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('the chosen category and sub-category are written to Firestore', (
    tester,
  ) async {
    final db = await pumpAddSheet(tester);

    await tester.enterText(inSheet(find.byType(TextField)).first, 'Choco Frappe');
    await tester.tap(find.text('Iced Blended'));
    await settle(tester);
    await tester.tap(find.text('Frappe Series'));
    await settle(tester);

    // Name and Description are the only fields ahead of it once no "Add new"
    // grid is open, and a size in play never got toggled on here — so the
    // third text field on the sheet is the flat Price.
    await tester.enterText(inSheet(find.byType(TextField)).at(2), '90.00');

    await tester.tap(inSheet(find.text('Save')));
    await settle(tester);

    final saved = await db
        .collection('shops')
        .doc(BrewPartner.b.id)
        .collection('menu')
        .where('name', isEqualTo: 'Choco Frappe')
        .get();
    expect(saved.docs, hasLength(1));
    expect(saved.docs.single.data()['category'], 'Iced Blended');
    expect(saved.docs.single.data()['subCategory'], 'Frappe Series');
  });
}
