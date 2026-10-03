import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/brew_menu_seed.dart';
import 'package:quick_brew/screens/admin/admin_addons_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The add-ons screen: one shop's extras, add, edit, delete and import.
///
/// The thing worth protecting here is that add-ons belong to *one* shop. They
/// used to be an enum in the order wizard, which meant both partners printed
/// the same board and neither could change it — so most of what follows checks
/// the collection is scoped and stays scoped.
void main() {
  setUpAll(loadBrandFonts);

  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  // Untyped so this file does not have to import cloud_firestore just to name
  // a reference it only ever reads and writes maps through.
  addOnsOf(BrewPartner partner) =>
      db.collection('shops').doc(partner.id).collection('addons');

  Future<void> pumpScreen(
    WidgetTester tester, {
    BrewPartner partner = BrewPartner.a,
    bool firestore = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminAddOnsScreen(
          partner: partner,
          admin: firestore ? BrewAdmin(db) : null,
          counter: firestore ? BrewCounter(db) : null,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> press(WidgetTester tester, String label) async {
    var finder = find.text(label);
    if (finder.evaluate().isEmpty) finder = find.text(label.toUpperCase());
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await settle(tester);
  }

  testWidgets('an empty list says so rather than showing a blank column', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.textContaining('offers no add-ons'), findsOneWidget);
    // And the way out of that state is offered in the same breath.
    expect(find.text('IMPORT'), findsOneWidget);
  });

  testWidgets('the bundled list imports onto this shop and no other', (
    tester,
  ) async {
    await pumpScreen(tester);

    await press(tester, 'Import');
    await press(tester, 'Replace with ${BrewAddOnSeed.all.length} add-ons');

    final mine = await addOnsOf(BrewPartner.a).get();
    expect(mine.docs, hasLength(BrewAddOnSeed.all.length));

    // The whole point of the change: the other partner is untouched.
    final theirs = await addOnsOf(BrewPartner.b).get();
    expect(theirs.docs, isEmpty);
  });

  testWidgets('imported add-ons keep their heading and price', (tester) async {
    await pumpScreen(tester);
    await press(tester, 'Import');
    await press(tester, 'Replace with ${BrewAddOnSeed.all.length} add-ons');

    final docs = await addOnsOf(BrewPartner.a).get();
    final oatMilk = docs.docs
        .map((doc) => doc.data())
        .firstWhere((data) => data['name'] == 'Oat milk');

    expect(oatMilk['priceCents'], 4000);
    expect(oatMilk['group'], 'Milk choice');
  });

  testWidgets('the list draws under the shop\'s own headings', (tester) async {
    await addOnsOf(BrewPartner.a).add({
      'name': 'Pearls',
      'priceCents': 1000,
      'group': 'Sinkers',
      'sort': 0,
    });
    await addOnsOf(BrewPartner.a).add({
      'name': 'Oat milk',
      'priceCents': 4000,
      'group': 'Milk choice',
      'sort': 1,
    });
    await pumpScreen(tester);

    expect(find.text('SINKERS'), findsOneWidget);
    expect(find.text('MILK CHOICE'), findsOneWidget);
    expect(find.text('Pearls'), findsOneWidget);
    // The surcharge reads as one — a plus and a figure, not a bare price.
    expect(find.text('+₱40'), findsOneWidget);
  });

  testWidgets('an add-on with no heading is still offered, under Ungrouped', (
    tester,
  ) async {
    await addOnsOf(BrewPartner.a).add({'name': 'Extra ice', 'priceCents': 0});
    await pumpScreen(tester);

    expect(find.text('UNGROUPED'), findsOneWidget);
    expect(find.text('Extra ice'), findsOneWidget);
  });

  testWidgets('adding one writes it to this shop', (tester) async {
    await pumpScreen(tester);

    await press(tester, 'Add an add-on');
    await tester.enterText(find.byType(TextField).first, 'Whipped cream');
    await tester.enterText(find.byType(TextField).at(1), '25');
    await settle(tester);
    await press(tester, 'Save');

    final docs = await addOnsOf(BrewPartner.a).get();
    expect(docs.docs, hasLength(1));
    final data = docs.docs.single.data();
    expect(data['name'], 'Whipped cream');
    // Pesos in the field, minor units in the document — the conversion happens
    // once, on save.
    expect(data['priceCents'], 2500);
  });

  testWidgets('a nameless or unpriced add-on is refused with a sentence', (
    tester,
  ) async {
    await pumpScreen(tester);
    await press(tester, 'Add an add-on');

    // Nothing typed at all.
    await press(tester, 'Save');
    expect(find.text('Name the add-on.'), findsOneWidget);
    expect(await addOnsOf(BrewPartner.a).get().then((s) => s.docs), isEmpty);

    // Named, but with no figure to charge — an add-on that cannot say what it
    // costs would silently add nothing to the total.
    await tester.enterText(find.byType(TextField).first, 'Mystery');
    await settle(tester);
    await press(tester, 'Save');
    expect(find.textContaining('Give this a price'), findsOneWidget);
    expect(await addOnsOf(BrewPartner.a).get().then((s) => s.docs), isEmpty);
  });

  testWidgets('editing one keeps its document rather than adding a second', (
    tester,
  ) async {
    await addOnsOf(BrewPartner.a).add({
      'name': 'Pearls',
      'priceCents': 1000,
      'group': 'Sinkers',
      'sort': 0,
    });
    await pumpScreen(tester);

    await press(tester, 'Edit');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await settle(tester);
    await press(tester, 'Save');

    final docs = await addOnsOf(BrewPartner.a).get();
    expect(docs.docs, hasLength(1), reason: 'an edit is not an add');
    expect(docs.docs.single.data()['priceCents'], 1200);
    // The heading survives an edit that never touched it.
    expect(docs.docs.single.data()['group'], 'Sinkers');
  });

  testWidgets('deleting takes it off the shop', (tester) async {
    await addOnsOf(BrewPartner.a).add({
      'name': 'Pearls',
      'priceCents': 1000,
      'group': 'Sinkers',
    });
    await pumpScreen(tester);

    await press(tester, 'Delete');

    expect(await addOnsOf(BrewPartner.a).get().then((s) => s.docs), isEmpty);
  });

  testWidgets('Remove all clears the shop once confirmed', (tester) async {
    for (final name in ['Pearls', 'Nata', 'Oat milk']) {
      await addOnsOf(BrewPartner.a).add({
        'name': name,
        'priceCents': 1000,
        'group': 'Sinkers',
      });
    }
    await pumpScreen(tester);

    await press(tester, 'Remove all');
    await press(tester, 'Remove all 3');

    expect(await addOnsOf(BrewPartner.a).get().then((s) => s.docs), isEmpty);
  });

  testWidgets('backing out of Remove all leaves the list alone', (
    tester,
  ) async {
    await addOnsOf(BrewPartner.a).add({
      'name': 'Pearls',
      'priceCents': 1000,
      'group': 'Sinkers',
    });
    await pumpScreen(tester);

    await press(tester, 'Remove all');
    await press(tester, 'Keep what is there');

    expect(await addOnsOf(BrewPartner.a).get().then((s) => s.docs), hasLength(1));
  });

  testWidgets('with no Firestore behind it every control is dead', (
    tester,
  ) async {
    await pumpScreen(tester, firestore: false);

    // The screen still renders — it just cannot save, and says nothing it
    // would have to take back.
    expect(find.text('ADD AN ADD-ON'), findsOneWidget);
    await press(tester, 'Add an add-on');
    // No sheet opened, because the control is disabled rather than live and
    // refusing.
    expect(find.text('Save'), findsNothing);
  });
}
