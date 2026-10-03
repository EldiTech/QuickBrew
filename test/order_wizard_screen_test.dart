import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/brew_menu_seed.dart';
import 'package:quick_brew/screens/menu_screen.dart';
import 'package:quick_brew/screens/order_wizard_screen.dart';
import 'package:quick_brew/widgets/menu_item_image.dart';
import 'package:quick_brew/widgets/stagger.dart';

import 'support/fonts.dart';

/// The buying flow: six steps from a board item to an order document.
///
/// Driven through the buttons rather than by reaching into the state, because
/// the thing worth protecting is that a reader pressing the labels in order
/// arrives at an order — a test that set the step directly would keep passing
/// through a forward button wired to the wrong step.
void main() {
  setUpAll(loadBrandFonts);

  late FakeFirebaseFirestore db;
  late BrewCounter counter;

  /// Bumped per pump, to key each one distinctly. See [pumpWizard].
  var pumpCount = 0;

  setUp(() {
    db = FakeFirebaseFirestore();
    counter = BrewCounter(db);
    pumpCount = 0;
  });

  const session = BrewSession(uid: 'reader-1', name: 'Dana Cruz');
  const shop = BrewShop(partner: BrewPartner.a, status: BrewShopStatus.open);

  /// A sized drink, which is the case that has something to pick on step one.
  const latte = BrewMenuItem(
    id: 'latte',
    name: 'Iced Latte',
    description: 'Double shot over ice',
    sizePrices: {
      BrewItemSize.small: 5000,
      BrewItemSize.medium: 8000,
      BrewItemSize.large: 9000,
    },
  );

  /// Puts the bundled Seven Coffee & Tea add-ons on one shop.
  ///
  /// Written through Firestore rather than injected, because that is the whole
  /// point of the change these tests cover: the wizard has no add-ons of its
  /// own any more, it reads whatever `shops/{shop}/addons` holds. A test that
  /// stubbed the list past the collection would keep passing if the read
  /// broke.
  Future<void> seedAddOns({BrewPartner partner = BrewPartner.a}) async {
    final collection =
        db.collection('shops').doc(partner.id).collection('addons');
    for (final addOn in BrewAddOnSeed.all) {
      await collection.add({
        'name': addOn.name,
        'priceCents': addOn.priceCents,
        'group': addOn.group,
        'sort': addOn.sort,
      });
    }
  }

  /// The smallest thing that is really a PNG: 1x1, transparent. Stands in for
  /// both the shop's QR and the reader's receipt — neither test cares what the
  /// picture shows, only that bytes travelled.
  const onePixelPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  /// A real 40x100 PNG — the *shape* an admin actually uploads.
  ///
  /// Portrait on purpose, and genuinely decodable rather than a stand-in: the
  /// layout this pins is about aspect ratio, so a 1x1 square would pass whether
  /// or not the frame boxes a tall picture into a square.
  const portraitPng =
      'iVBORw0KGgoAAAANSUhEUgAAACgAAABkCAYAAAD0ZHJ6AAAAAXNSR0IArs4c6QAAAARn'
      'QU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAB7SURBVGhD7c6hAQAwDICw'
      '/v/05mtjKohEMe+42eGaBlWDqkHVoGpQNagaVA2qBlWDqkHVoGpQNagaVA2qBlWDqkHV'
      'oGpQNagaVA2qBlWDqkHVoGpQNagaVA2qBlWDqkHVoGpQNagaVA2qBlWDqkHVoGpQNaga'
      'VA2qBtUHpWpFIyG5ExEAAAAASUVORK5CYII=';

  /// Puts a payment code on the shop, which is what turns the payment step from
  /// a notice into a task with a gate on it.
  ///
  /// Written through Firestore rather than onto the const [shop] handed to the
  /// screen, deliberately: the wizard subscribes to the shop rather than trusting
  /// the snapshot it was opened with, and a test that set the field on the widget
  /// would keep passing if that subscription broke.
  Future<void> seedPayQr({
    BrewPartner partner = BrewPartner.a,
    String png = onePixelPng,
  }) {
    return db.collection('shops').doc(partner.id).set({
      'open': true,
      'payQrBase64': png,
    });
  }

  Future<void> pumpWizard(
    WidgetTester tester, {
    BrewMenuItem item = latte,
    BrewSession? who = session,
    bool firestore = true,
    BrewDraft? draft,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: OrderWizardScreen(
          // A fresh key per pump, because the resume tests pump this screen
          // twice in one test — once to build and save an order, once to come
          // back to it. Without a distinct key the second pump finds the same
          // widget type in the same slot and *updates* the first one's State
          // rather than replacing it, so initState never runs again and the
          // draft handed in is silently ignored. Which is a property of the
          // test, not of the screen: in the app the second one is a new route.
          key: ValueKey(pumpCount++),
          shop: shop,
          item: item,
          session: who,
          counter: firestore ? counter : null,
          draft: draft,
          // Stands in for the gallery — see [OrderWizardScreen.pickReceipt].
          // Every pump gets it; only the tests that press Upload ever call it.
          pickReceipt: () async => base64Decode(onePixelPng),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }


  /// Presses a label and lets the cross-fade finish. Scrolls it into view
  /// first: the pinned footer is always on screen, but the option rows on a
  /// long step are not.
  ///
  /// Falls back to the uppercase spelling because [BrewMonoButton] uppercases
  /// what it is given — Remove and Add another drink are painted as REMOVE and
  /// ADD ANOTHER DRINK, and a test that had to know which controls happen to be
  /// mono buttons would be a test of this app's typography.
  Future<void> press(WidgetTester tester, String label) async {
    var finder = find.text(label);
    if (finder.evaluate().isEmpty) finder = find.text(label.toUpperCase());
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  /// Presses Upload receipt and lets the picked bytes land.
  Future<void> uploadReceipt(WidgetTester tester) async {
    await press(tester, 'Upload receipt');
    await tester.pumpAndSettle();
  }

  /// Presses the confirm button specifically.
  ///
  /// "Confirm order" is on screen twice on the last step — once as the
  /// heading, once on the button — and the heading is painted first, so
  /// [press]'s `.first` would tap a Text that is not a control and the order
  /// would silently never be placed.
  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('Confirm order').last);
    await tester.pumpAndSettle();
  }

  /// Walks steps one through three, leaving the reader on the cart with one
  /// medium latte in it.
  Future<void> fillCart(WidgetTester tester) async {
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');
    await press(tester, 'Add to cart');
  }

  /// Fills the pickup form and advances off it.
  Future<void> fillPickup(WidgetTester tester) async {
    await press(tester, 'Enter pickup details');
    await tester.enterText(find.byType(TextField).at(1), '09171234567');
    await tester.pumpAndSettle();
    await press(tester, 'Pay for your order');
  }

  testWidgets('opens on step one with the item and its sizes', (tester) async {
    await pumpWizard(tester);

    expect(find.text('Step 1 of 6'.toUpperCase()), findsOneWidget);
    expect(find.text('Select coffee & size'), findsOneWidget);
    expect(find.text('Iced Latte'), findsOneWidget);

    // Every size the shop priced, each beside its own figure — the choice the
    // board could not offer from a grid cell.
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('₱50'), findsOneWidget);
    expect(find.text('₱90'), findsOneWidget);
  });

  testWidgets('a flat-priced item says there is no size to pick', (
    tester,
  ) async {
    await pumpWizard(
      tester,
      item: const BrewMenuItem(id: 'bun', name: 'Bun', priceCents: 250),
    );

    // Stated rather than shown as an empty section: a heading with nothing
    // under it reads as a list that failed to load.
    expect(find.textContaining('comes one way'), findsOneWidget);
    expect(find.text('Small'), findsNothing);
  });

  testWidgets('extras add their surcharge to the drink total', (tester) async {
    await seedAddOns();
    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');

    // Medium alone.
    expect(find.text('₱80'), findsOneWidget);

    // Espresso shot, ₱10 under the Coffee heading.
    await press(tester, 'Coffee');
    await press(tester, 'Espresso shot');
    expect(find.text('₱90'), findsOneWidget);

    // Oat milk is the dear one on this board at ₱40, and it lives under its
    // own Milk choice heading rather than among the toppings.
    await press(tester, 'Milk choice');
    await press(tester, 'Oat milk');
    expect(find.text('₱130'), findsOneWidget);
  });

  testWidgets('the board prices two sinkers above their own heading', (
    tester,
  ) async {
    await seedAddOns();
    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');
    await press(tester, 'Sinkers');

    // The heading says ₱10 and most of the section is, but the shop prices
    // these two at ₱15 — a group-level price would have to lie about one end
    // of this list or the other.
    await press(tester, 'Pearls');
    expect(find.text('₱90'), findsOneWidget);

    await press(tester, 'Popping boba SB');
    expect(find.text('₱105'), findsOneWidget);
  });

  testWidgets('quantity multiplies the drink, not the extras twice', (
    tester,
  ) async {
    await seedAddOns();
    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');
    await press(tester, 'Coffee');
    await press(tester, 'Espresso shot');
    await press(tester, '+');

    // (8000 + 1000) × 2, which is the reading that would break if quantity
    // were applied to the base and the add-ons added on afterwards.
    expect(find.text('₱180'), findsOneWidget);
  });

  testWidgets('pressing plus at five pops up the quantity cap', (
    tester,
  ) async {
    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');
    for (var i = 0; i < 4; i++) {
      await press(tester, '+');
    }
    expect(find.text('5'), findsOneWidget);

    // The sixth press pops up the cap instead of going quiet — the plus
    // stays live rather than going dead at the edge, so the pop-up is what
    // answers a reader who keeps pressing past it.
    await press(tester, '+');
    expect(
      find.text('That is as many as one line can hold right now.'),
      findsOneWidget,
    );
    expect(find.textContaining('capped at 5 at a time'), findsOneWidget);

    // Dismissing it leaves the quantity exactly where it was.
    await press(tester, 'Got it');
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('one pending order shrinks the stepper cap to four', (
    tester,
  ) async {
    await counter.placeOrder(
      uid: session.uid,
      partner: BrewPartner.a,
      items: const ['Iced Latte (Medium)'],
      totalCents: 8000,
      pickupName: 'Dana Cruz',
      pickupPhone: '09171234567',
      paymentMethod: 'Pay at counter',
    );

    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');
    for (var i = 0; i < 3; i++) {
      await press(tester, '+');
    }
    expect(find.text('4'), findsOneWidget);

    // The five-drink budget is shared with the order already at the
    // counter, so the fourth press — not the fifth — is what trips it.
    await press(tester, '+');
    expect(
      find.text('That is as many as one line can hold right now.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('You have 1 order open, which leaves room for 4'),
      findsOneWidget,
    );
  });

  testWidgets('five pending orders leave the stepper no room at all', (
    tester,
  ) async {
    for (var i = 0; i < 5; i++) {
      await counter.placeOrder(
        uid: session.uid,
        partner: BrewPartner.a,
        items: const ['Iced Latte (Medium)'],
        totalCents: 8000,
        pickupName: 'Dana Cruz',
        pickupPhone: '09171234567',
        paymentMethod: 'Pay at counter',
      );
    }

    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');

    // Quantity is still shown at 1 — the minus floor, not the cap — but even
    // the first press on plus is already past a cap of zero.
    expect(find.text('1'), findsOneWidget);
    await press(tester, '+');
    expect(find.text('You have no room left for this order.'), findsOneWidget);
  });

  testWidgets('the add-ons board opens one section at a time', (tester) async {
    await seedAddOns();
    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');

    // Every heading on the shop's board, and none of their options yet.
    for (final heading in [
      'Coffee',
      'Drizzle',
      'Syrup',
      'Sinkers',
      'Toppings',
      'Milk choice',
    ]) {
      expect(find.text(heading.toUpperCase()), findsOneWidget);
    }
    expect(find.text('Pearls'), findsNothing);
    expect(find.text('Cream cheese'), findsNothing);

    await press(tester, 'Sinkers');
    expect(find.text('Pearls'), findsOneWidget);

    // Opening another closes the first, so the stepper below never sits under
    // two open sections.
    await press(tester, 'Toppings');
    expect(find.text('Cream cheese'), findsOneWidget);
    expect(find.text('Pearls'), findsNothing);
  });

  testWidgets('a collapsed section still says something in it is chosen', (
    tester,
  ) async {
    await seedAddOns();
    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');
    await press(tester, 'Sinkers');
    await press(tester, 'Pearls');
    await press(tester, 'Nata');

    // Closed again — the options go, the count stays, so the collapse hides
    // the list rather than the decision.
    await press(tester, 'Sinkers');
    expect(find.text('Pearls'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(Row),
        matching: find.text('2'),
      ),
      findsWidgets,
      reason: 'the heading carries how many of its options are on the drink',
    );
  });

  testWidgets('a shop with no add-ons draws no add-ons section at all', (
    tester,
  ) async {
    // Nothing seeded: the truthful reading of an empty collection is a shop
    // that sells no extras, and the step is then a quantity and a total rather
    // than an ADD ONS heading over nothing.
    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');

    expect(find.text('ADD ONS'), findsNothing);
    expect(find.text('SINKERS'), findsNothing);

    // The rest of the step is untouched — this is a section coming off, not a
    // step being skipped.
    expect(find.text('HOW MANY'), findsOneWidget);
    expect(find.text('₱80'), findsWidgets);
  });

  testWidgets("one shop's add-ons never reach the other's wizard", (
    tester,
  ) async {
    // The whole point of moving these into `shops/{shop}/addons`: seeded on
    // shop A, and shop B's customise step has to come up empty.
    await seedAddOns();

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: OrderWizardScreen(
          shop: const BrewShop(
            partner: BrewPartner.b,
            status: BrewShopStatus.open,
          ),
          item: latte,
          session: session,
          counter: counter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');

    expect(find.text('ADD ONS'), findsNothing);
    expect(find.text('SINKERS'), findsNothing);
    expect(find.text('Pearls'), findsNothing);
  });

  testWidgets('add to cart banks the drink and lands on the cart', (
    tester,
  ) async {
    await pumpWizard(tester);
    await fillCart(tester);

    expect(find.text('Your cart'), findsOneWidget);
    expect(find.text('Step 3 of 6'.toUpperCase()), findsOneWidget);
    // The configuration survives the step, which is the whole point of banking
    // it rather than carrying loose fields forward.
    expect(find.textContaining('Medium'), findsWidgets);
    expect(find.text('₱80'), findsWidgets);
  });

  testWidgets('Add another returns to step one with the cart intact', (
    tester,
  ) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await press(tester, 'Add another drink');

    expect(find.text('Select coffee & size'), findsOneWidget);

    await press(tester, 'Large');
    await press(tester, 'Customise your drink');
    await press(tester, 'Add to cart');

    // Two lines, and a total that is the sum rather than the last one.
    expect(find.text('Cart total'.toUpperCase()), findsOneWidget);
    expect(find.text('₱170'), findsOneWidget);
  });

  testWidgets('Add another drink can pick a different drink off the board', (
    tester,
  ) async {
    await db
        .collection('shops')
        .doc(BrewPartner.a.id)
        .collection('menu')
        .doc('latte')
        .set({
          'name': 'Iced Latte',
          'sizePrices': {'small': 5000, 'medium': 8000, 'large': 9000},
          'sort': 10,
        });
    await db
        .collection('shops')
        .doc(BrewPartner.a.id)
        .collection('menu')
        .doc('bun')
        .set({'name': 'Bun', 'priceCents': 2500, 'sort': 20});

    await pumpWizard(tester);
    await fillCart(tester);
    await press(tester, 'Add another drink');

    // The board offers both items, not just the one the reader arrived on.
    expect(find.text('Iced Latte'), findsWidgets);
    expect(find.text('Bun'), findsOneWidget);

    await press(tester, 'Bun');
    // Flat-priced, so step one now says so instead of offering the latte's
    // sizes — proof the picker actually swapped the drink being configured.
    expect(find.textContaining('comes one way'), findsOneWidget);

    await press(tester, 'Customise your drink');
    await press(tester, 'Add to cart');

    // A medium latte (₱80) plus a bun (₱2.50), not two lattes.
    expect(find.text('Cart total'.toUpperCase()), findsOneWidget);
    expect(find.text('₱105'), findsOneWidget);
  });

  testWidgets('a cart of five drinks stops offering a sixth', (tester) async {
    await pumpWizard(tester);
    await fillCart(tester);
    for (var i = 0; i < 4; i++) {
      await press(tester, 'Add another drink');
      await press(tester, 'Medium');
      await press(tester, 'Customise your drink');
      await press(tester, 'Add to cart');
    }

    // Five lines in, early-dev cap reached: the door back to a picker that
    // has nowhere left to land a sixth line is closed rather than left open
    // onto a dead end — see the note on [_cartBody]'s conditional.
    expect(find.text('Add another drink'.toUpperCase()), findsNothing);

    // Still able to walk the rest of the flow with the five it has.
    await press(tester, 'Enter pickup details');
    expect(find.text('Enter pickup details'), findsOneWidget);
  });

  testWidgets('five drinks in fewer than five lines still stops a sixth', (
    tester,
  ) async {
    // The case the line count alone misses. Five drinks banked as two lines —
    // one of four, one of one — leaves [_maxCartLines] with three lines still
    // spare, so "Add another drink" is still on offer even though the order is
    // already at the five-drink budget the stepper enforces within a line.
    await pumpWizard(tester);
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');
    for (var i = 0; i < 3; i++) {
      await press(tester, '+');
    }
    expect(find.text('4'), findsOneWidget);
    await press(tester, 'Add to cart');

    await press(tester, 'Add another drink');
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');
    await press(tester, 'Add to cart');

    // Five drinks across two lines. The door has to be shut on drinks, not on
    // lines: a sixth here is exactly the order the stepper refused to build
    // inside one line, assembled across two.
    expect(find.text('Add another drink'.toUpperCase()), findsNothing);

    // And the five it has still walk the rest of the flow.
    await press(tester, 'Enter pickup details');
    expect(find.text('Enter pickup details'), findsOneWidget);
  });

  testWidgets('a sixth drink some other way pops up the cart cap', (
    tester,
  ) async {
    // Reached through a resumed draft rather than the ordinary flow: a draft
    // saved with five lines can still be reopened on its customise step —
    // [_Step.restore] — which is the one door into [_addDraftToCart] that
    // does not run through the now-hidden "Add another drink" button.
    await db
        .collection('shops')
        .doc(BrewPartner.a.id)
        .collection('menu')
        .doc('latte')
        .set({
          'name': 'Iced Latte',
          'sizePrices': {'small': 5000, 'medium': 8000, 'large': 9000},
          'sort': 10,
        });
    final draft = BrewDraft(
      partner: BrewPartner.a,
      step: 'customise',
      lines: [
        for (var i = 0; i < 5; i++)
          const BrewDraftLine(
            itemId: 'latte',
            size: BrewItemSize.medium,
            extraIds: [],
            quantity: 1,
            unitCents: 8000,
          ),
      ],
      pickupName: 'Dana Cruz',
      pickupPhone: '',
      pickupNote: '',
      paymentMethod: 'Pay at counter',
      scheduledFor: null,
    );

    await pumpWizard(tester, draft: draft);
    await press(tester, 'Add to cart');

    expect(find.text('This order is full.'), findsOneWidget);
    expect(find.textContaining('capped at 5 drinks'), findsOneWidget);

    await press(tester, 'Got it');
    // The pop-up answered the press; it did not bank a sixth line.
    expect(find.text('Step 2 of 6'.toUpperCase()), findsOneWidget);
  });

  testWidgets('a resumed draft at the drink cap refuses a line with rows spare',
      (tester) async {
    // The backstop the button gate cannot cover. Two lines holding five drinks
    // between them leaves three rows free, so the line count says there is
    // room — and this door does not run through the cart body's conditional at
    // all. [_addDraftToCart] has to refuse on the drink total itself.
    await db
        .collection('shops')
        .doc(BrewPartner.a.id)
        .collection('menu')
        .doc('latte')
        .set({
          'name': 'Iced Latte',
          'sizePrices': {'small': 5000, 'medium': 8000, 'large': 9000},
          'sort': 10,
        });
    final draft = BrewDraft(
      partner: BrewPartner.a,
      step: 'customise',
      lines: const [
        BrewDraftLine(
          itemId: 'latte',
          size: BrewItemSize.medium,
          extraIds: [],
          quantity: 4,
          unitCents: 8000,
        ),
        BrewDraftLine(
          itemId: 'latte',
          size: BrewItemSize.small,
          extraIds: [],
          quantity: 1,
          unitCents: 5000,
        ),
      ],
      pickupName: 'Dana Cruz',
      pickupPhone: '',
      pickupNote: '',
      paymentMethod: 'Scan to pay',
      scheduledFor: null,
    );

    await pumpWizard(tester, draft: draft);
    await press(tester, 'Add to cart');

    expect(find.text('This order is full.'), findsOneWidget);
    await press(tester, 'Got it');
    expect(find.text('Step 2 of 6'.toUpperCase()), findsOneWidget);
  });

  testWidgets('removing the last line blocks the way forward', (tester) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await press(tester, 'Remove');

    expect(find.textContaining('cart is empty'), findsOneWidget);

    // The forward button is still drawn — a control that vanishes takes the
    // layout with it — but pressing it goes nowhere.
    await press(tester, 'Enter pickup details');
    expect(
      find.text('Your cart'),
      findsOneWidget,
      reason: 'an empty cart cannot walk on to pickup',
    );
  });

  testWidgets('a removed line stops counting before it finishes leaving', (
    tester,
  ) async {
    await pumpWizard(tester);
    await fillCart(tester);

    // Two lines, so the one that stays gives the total something to fall to
    // that is neither the pair's total nor zero.
    await press(tester, 'Add another drink');
    await press(tester, 'Medium');
    await press(tester, 'Customise your drink');
    await press(tester, 'Add to cart');
    // The figure beside CART TOTAL specifically: ₱80 is also each row's own
    // price, so a bare text finder would match the rows as well as the total.
    String cartTotal() => tester
        .widget<Text>(
          find.descendant(
            of: find.ancestor(
              of: find.text('CART TOTAL'),
              matching: find.byType(Row),
            ).first,
            matching: find.byType(Text),
          ).last,
        )
        .data!;

    expect(cartTotal(), '₱160', reason: 'two mediums at ₱80');

    final remove = find.text('REMOVE');
    await tester.ensureVisible(remove.first);
    await tester.tap(remove.first);

    // Halfway through the collapse: the row is still painted, but it is no
    // longer part of what the reader is buying. The figure is mid-count here,
    // so what is asserted is that it has left ₱160 — the settled value is
    // checked below.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.text('REMOVE'), findsNWidgets(2), reason: 'still collapsing');
    expect(
      cartTotal(),
      isNot('₱160'),
      reason: 'the total discounts a leaving line the moment Remove is pressed',
    );

    await tester.pumpAndSettle();
    expect(cartTotal(), '₱80');
    expect(find.text('REMOVE'), findsOneWidget, reason: 'one line left');
  });

  testWidgets('an empty pickup form says why it did not advance', (
    tester,
  ) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await press(tester, 'Enter pickup details');

    // The name is prefilled from the session, so only the number is missing.
    expect(find.text('Dana Cruz'), findsOneWidget);

    await press(tester, 'Pay for your order');

    // Still on step four, with the reason stated rather than the press
    // silently dropped.
    expect(find.text('Enter pickup details'), findsOneWidget);
    expect(find.textContaining('number to reach you on'), findsOneWidget);
  });

  testWidgets('a short number is rejected, a full one is not', (tester) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await press(tester, 'Enter pickup details');

    await tester.enterText(find.byType(TextField).at(1), '123');
    await tester.pumpAndSettle();
    await press(tester, 'Pay for your order');
    expect(find.textContaining('does not look like a full number'),
        findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), '09171234567');
    await tester.pumpAndSettle();
    await press(tester, 'Pay for your order');
    expect(find.text('Pay for your order'), findsOneWidget);
  });

  testWidgets('a shop with no QR asks for nothing and blocks nothing', (
    tester,
  ) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);

    // Nothing to scan means nothing to upload, and the step says why rather
    // than drawing an empty frame where a code goes.
    expect(find.text('PAY AT THE COUNTER'), findsOneWidget);
    expect(find.textContaining('has not put up a payment code'), findsOneWidget);
    expect(find.text('YOUR RECEIPT'), findsNothing);

    // And the forward button is live: holding a reader at an upload for a
    // payment they had no way to make would be a dead end.
    await press(tester, 'Review your order');
    expect(find.text('Confirm order'), findsWidgets);
  });

  testWidgets('a shop with a QR shows it and holds Review until a receipt', (
    tester,
  ) async {
    await seedPayQr();
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);

    expect(find.text('SCAN TO PAY'), findsOneWidget);
    expect(find.text('YOUR RECEIPT'), findsOneWidget);
    expect(
      find.textContaining('Upload proof of payment to continue'),
      findsOneWidget,
    );

    // The gate itself: pressing forward with nothing uploaded says why rather
    // than dropping the press, and leaves the reader on the step.
    await press(tester, 'Review your order');
    expect(find.text('Upload your receipt first.'), findsOneWidget);

    await press(tester, 'Not yet');
    expect(find.text('SCAN TO PAY'), findsOneWidget);
    expect(find.text('Confirm order'), findsNothing);
  });

  testWidgets('the receipt pop-up offers the upload it is asking for', (
    tester,
  ) async {
    await seedPayQr();
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);

    await press(tester, 'Review your order');
    expect(find.text('Upload your receipt first.'), findsOneWidget);

    // Taking the sheet's own Upload runs the picker, so the reader is not sent
    // back to hunt for a control behind the pop-up that just named it. `.last`
    // is the sheet's: the receipt section behind it carries a button reading
    // the same words, and tapping that one would prove nothing about the sheet.
    await tester.tap(find.text('Upload receipt').last);
    await tester.pumpAndSettle();
    expect(find.text('Upload your receipt first.'), findsNothing);

    // And the gate is open: the same press now moves.
    await press(tester, 'Review your order');
    expect(find.text('Confirm order'), findsWidgets);
  });

  testWidgets('a tall QR still leaves the upload control reachable', (
    tester,
  ) async {
    // The shape an admin actually uploads: a portrait GCash card, not a bare
    // square code. Boxed into a fixed square this used up the whole step and
    // pushed the receipt control — the one thing the forward button waits on —
    // under the pinned footer.
    await seedPayQr(png: portraitPng);
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);

    expect(find.text('SCAN TO PAY'), findsOneWidget);
    expect(find.text('YOUR RECEIPT'), findsOneWidget);

    // The measurement, not just the presence. Image.memory decodes off the
    // frame, so the picture has no intrinsic size until that lands — hence
    // runAsync, without which every Image measures 0x0 and the assertion below
    // would pass on a layout that never drew anything.
    await tester.runAsync(() async {
      final image = tester.widget<Image>(find.byType(Image).first);
      await precacheImage(image.image, tester.element(find.byType(Image).first));
    });
    await tester.pumpAndSettle();

    // A 40x100 source drawn inside a height cap comes out 100 tall at most and
    // *narrower than it is tall* — which is the whole fix. Boxed into a square
    // with BoxFit.contain the width would come out equal to the height instead,
    // with the picture letterboxed inside it and the code smaller than the
    // space allowed for it.
    final qr = tester.getSize(find.byType(Image).first);
    expect(qr.height, greaterThan(0));
    expect(qr.height, lessThanOrEqualTo(260));
    expect(
      qr.width,
      lessThan(qr.height),
      reason: 'a portrait code must stay portrait rather than being '
          'letterboxed into a square',
    );

    // And the control the forward button waits on is still reachable.
    await uploadReceipt(tester);
    await press(tester, 'Review your order');
    expect(find.text('Confirm order'), findsWidgets);
  });

  testWidgets('an uploaded receipt opens the button and travels onto the order',
      (tester) async {
    await seedPayQr();
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);

    await uploadReceipt(tester);

    // Shown back rather than replaced with a tick, so the reader can see they
    // picked the right transfer.
    expect(find.byType(BrewMenuItemImage), findsWidgets);

    await press(tester, 'Review your order');
    expect(find.text('Confirm order'), findsWidgets);
    expect(find.text('Scan to pay'), findsWidgets);

    await confirm(tester);

    final snapshot = await db.collection('orders').get();
    expect(snapshot.docs, hasLength(1));
    final data = snapshot.docs.single.data();
    expect(data['paymentMethod'], 'Scan to pay');
    expect(data['receiptBase64'], onePixelPng);
  });

  testWidgets('removing the receipt closes the button again', (tester) async {
    await seedPayQr();
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);

    await uploadReceipt(tester);
    await press(tester, 'Remove');
    await tester.pumpAndSettle();

    // Taking the evidence away puts the gate back, which is the honest
    // consequence rather than a button that stays open on a receipt that is no
    // longer attached — and the gate answers the press the same way it does the
    // first time round.
    await press(tester, 'Review your order');
    expect(find.text('Upload your receipt first.'), findsOneWidget);

    await press(tester, 'Not yet');
    expect(find.text('Confirm order'), findsNothing);
    expect(find.text('SCAN TO PAY'), findsOneWidget);
  });

  testWidgets('confirm restates every decision before it acts on one', (
    tester,
  ) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);
    await press(tester, 'Review your order');

    expect(find.text('Confirm order'), findsWidgets);
    expect(find.text('Drip & Co'), findsOneWidget);
    expect(find.textContaining('Iced Latte (Medium)'), findsOneWidget);
    expect(find.text('Dana Cruz'), findsOneWidget);
    expect(find.text('09171234567'), findsOneWidget);
    expect(find.text('Pay at counter'), findsWidgets);
    expect(find.text('₱80'), findsWidgets);
  });

  testWidgets('confirming writes one order the home screen can read', (
    tester,
  ) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);
    await press(tester, 'Review your order');
    await confirm(tester);

    final snapshot = await db.collection('orders').get();
    expect(snapshot.docs, hasLength(1));

    final data = snapshot.docs.single.data();
    expect(data['uid'], 'reader-1');
    expect(data['shop'], BrewPartner.a.id);
    expect(data['stage'], 'received');
    expect(data['items'], ['Iced Latte (Medium)']);
    expect(data['totalCents'], 8000);
    expect(data['pickupName'], 'Dana Cruz');
    expect(data['pickupPhone'], '09171234567');
    expect(data['paymentMethod'], 'Pay at counter');

    // The document round-trips through the reader the home screen uses, which
    // is the only definition of "an order this app can show" that matters.
    final order = BrewOrder.read(snapshot.docs.single.id, data);
    expect(order, isNotNull);
    expect(order!.stage, BrewOrderStage.received);
    expect(order.stage.isActive, isTrue);
    expect(order.itemLine, 'Iced Latte (Medium)');
  });

  testWidgets('an order made now carries no scheduled time', (tester) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);
    await press(tester, 'Review your order');

    // The default is restated on the summary rather than omitted.
    expect(find.text('As soon as it is ready'), findsOneWidget);

    await confirm(tester);
    final data = (await db.collection('orders').get()).docs.single.data();
    expect(data.containsKey('scheduledFor'), isFalse);
  });

  testWidgets('a scheduled pickup travels onto the order document', (
    tester,
  ) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await press(tester, 'Enter pickup details');
    await tester.enterText(find.byType(TextField).at(1), '09171234567');
    await tester.pumpAndSettle();

    await press(tester, 'Schedule pickup');
    // The dials open seeded with a valid future time.
    expect(find.text('DAY'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);

    // Book it for tomorrow, so the chosen time is in the future regardless of
    // the clock this test runs at.
    await press(tester, '+');
    expect(find.text('Tomorrow'), findsWidgets);

    await press(tester, 'Pay for your order');
    await press(tester, 'Review your order');

    // The summary restates the booking rather than the default.
    expect(find.text('As soon as it is ready'), findsNothing);

    await confirm(tester);
    final data = (await db.collection('orders').get()).docs.single.data();
    final scheduled = data['scheduledFor'];
    expect(scheduled, isA<Timestamp>());
    expect(
      (scheduled as Timestamp).toDate().isAfter(DateTime.now()),
      isTrue,
    );

    // And it survives the round-trip through the reader every screen uses.
    final order = BrewOrder.read('id', data);
    expect(order!.scheduledFor, isNotNull);
  });

  testWidgets('a scheduled pickup travels into a saved draft and back', (
    tester,
  ) async {
    // The board the resumed draft is rebuilt against — without it the saved
    // latte would be dropped as no longer sold.
    await db
        .collection('shops')
        .doc(BrewPartner.a.id)
        .collection('menu')
        .doc('latte')
        .set({
          'name': 'Iced Latte',
          'sizePrices': {'small': 5000, 'medium': 8000, 'large': 9000},
        });

    await pumpWizard(tester);
    await fillCart(tester);
    await press(tester, 'Enter pickup details');
    await tester.enterText(find.byType(TextField).at(1), '09171234567');
    await tester.pumpAndSettle();
    await press(tester, 'Schedule pickup');
    await press(tester, '+'); // Tomorrow, as above.
    await press(tester, 'Pay for your order');
    await press(tester, 'Save for later');

    final saved = (await db.collection('drafts').doc('reader-1').get()).data();
    expect(saved!['scheduledFor'], isA<Timestamp>());

    // Resume: the draft comes back on the payment step, and one step back the
    // booking is dialled in rather than reset to now.
    final draft = BrewDraft.read(saved);
    await pumpWizard(tester, draft: draft);
    await press(tester, 'Back');
    expect(find.textContaining('Tomorrow'), findsWidgets);
  });

  testWidgets('the order line carries the extras the counter has to make', (
    tester,
  ) async {
    await seedAddOns();
    await pumpWizard(tester);
    await press(tester, 'Large');
    await press(tester, 'Customise your drink');
    await press(tester, 'Coffee');
    await press(tester, 'Espresso shot');
    await press(tester, 'Sinkers');
    await press(tester, 'Pearls');
    await press(tester, '+');
    await press(tester, 'Add to cart');
    await fillPickup(tester);
    await press(tester, 'Review your order');
    await confirm(tester);

    final snapshot = await db.collection('orders').get();
    // Both add-ons reach the counter, in board order rather than in the order
    // the reader happened to tap them.
    expect(
      snapshot.docs.single.data()['items'],
      ['2× Iced Latte (Large) + Espresso shot, Pearls'],
    );
    // (9000 + 1000 + 1000) × 2.
    expect(snapshot.docs.single.data()['totalCents'], 22000);
  });

  testWidgets('the done state replaces the step rather than adding one', (
    tester,
  ) async {
    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);
    await press(tester, 'Review your order');
    await confirm(tester);

    expect(find.text('Order placed'), findsOneWidget);
    expect(find.textContaining('has your order'), findsOneWidget);
    expect(find.text('Back to the menu'), findsWidgets);
    // There is no step seven.
    expect(find.textContaining('Step 7'), findsNothing);
  });

  testWidgets('no session says so instead of dropping the press', (
    tester,
  ) async {
    await pumpWizard(tester, who: null);
    await fillCart(tester);
    await press(tester, 'Enter pickup details');
    await tester.enterText(find.byType(TextField).at(0), 'Walk-in');
    await tester.enterText(find.byType(TextField).at(1), '09171234567');
    await tester.pumpAndSettle();
    await press(tester, 'Pay for your order');
    await press(tester, 'Review your order');
    await confirm(tester);

    expect(find.textContaining('not connected'), findsOneWidget);
    expect((await db.collection('orders').get()).docs, isEmpty);
  });

  testWidgets('a reader with five open orders cannot place a sixth', (
    tester,
  ) async {
    for (var i = 0; i < 5; i++) {
      await counter.placeOrder(
        uid: session.uid,
        partner: BrewPartner.a,
        items: const ['Iced Latte (Medium)'],
        totalCents: 8000,
        pickupName: 'Dana Cruz',
        pickupPhone: '09171234567',
        paymentMethod: 'Pay at counter',
      );
    }

    await pumpWizard(tester);
    await fillCart(tester);
    await fillPickup(tester);
    await press(tester, 'Review your order');
    await confirm(tester);

    // The press pops up the cap rather than writing a sixth order.
    expect(find.textContaining('5 orders open'), findsOneWidget);
    expect((await db.collection('orders').get()).docs, hasLength(5));

    // Dismissing it leaves the reader on the confirm step, order still
    // unplaced — no order snuck through behind the pop-up.
    await press(tester, 'Got it');
    expect(find.text('Confirm order'), findsWidgets);
    expect((await db.collection('orders').get()).docs, hasLength(5));
  });

  group('save for later', () {
    /// The board the resumed drafts below are rebuilt against.
    ///
    /// Written to Firestore rather than injected because that is the whole point:
    /// a draft stores item ids and the wizard re-reads the menu to turn them back
    /// into priced drinks. A test that stubbed the board past the collection
    /// would keep passing if that read broke.
    Future<void> seedMenu({
      Map<String, int> sizePrices = const {
        'small': 5000,
        'medium': 8000,
        'large': 9000,
      },
    }) async {
      await db
          .collection('shops')
          .doc(BrewPartner.a.id)
          .collection('menu')
          .doc('latte')
          .set({
            'name': 'Iced Latte',
            'description': 'Double shot over ice',
            'sizePrices': sizePrices,
            'sort': 10,
          });
    }

    Future<Map<String, Object?>?> savedDraft() async {
      final doc = await db.collection('drafts').doc(session.uid).get();
      return doc.data();
    }

    testWidgets('is not offered until something is in the cart', (
      tester,
    ) async {
      await pumpWizard(tester);

      // Steps one and two configure a drink the reader has not yet said they
      // want. Add to cart is the press that says so.
      expect(find.text('SAVE FOR LATER'), findsNothing);
      await press(tester, 'Medium');
      await press(tester, 'Customise your drink');
      expect(find.text('SAVE FOR LATER'), findsNothing);

      await press(tester, 'Add to cart');
      expect(find.text('SAVE FOR LATER'), findsOneWidget);
    });

    testWidgets('writes the whole flow and leaves', (tester) async {
      await pumpWizard(tester);
      await fillCart(tester);
      await fillPickup(tester);

      // Saved from the payment step, so the step and the pickup form both have
      // something in them worth checking travelled.
      await press(tester, 'Save for later');

      final draft = await savedDraft();
      expect(draft, isNotNull);
      expect(draft!['shop'], BrewPartner.a.id);
      expect(draft['step'], 'payment');
      expect(draft['pickupName'], 'Dana Cruz');
      expect(draft['pickupPhone'], '09171234567');
      expect(draft['paymentMethod'], 'Pay at counter');

      final lines = draft['lines'] as List<Object?>;
      expect(lines, hasLength(1));
      final line = lines.first as Map<Object?, Object?>;
      expect(line['itemId'], 'latte');
      expect(line['size'], 'medium');
      expect(line['quantity'], 1);
      expect(line['unitCents'], 8000);

      // No order was placed. A draft is a bookmark in the reader's own flow, and
      // nothing about it reaches the counter.
      expect((await db.collection('orders').get()).docs, isEmpty);
    });

    testWidgets('resumes on the step it was left on, with the cart intact', (
      tester,
    ) async {
      await seedMenu();
      await seedAddOns();

      await pumpWizard(tester);
      await fillCart(tester);
      await fillPickup(tester);
      await press(tester, 'Save for later');

      final draft = BrewDraft.read((await savedDraft())!);
      expect(draft, isNotNull);

      await pumpWizard(tester, draft: draft);

      // Back on step five, not step one, and with the drink still in it.
      expect(find.text('Step 5 of 6'.toUpperCase()), findsOneWidget);
      expect(find.text('Pay for your order'), findsOneWidget);

      // The pickup form came back too, which is the whole reason the draft
      // stores it — retyping a phone number is the thing this feature exists to
      // avoid. Read off the fields' own controllers: the values are inside
      // TextFields here, not the plain Text the confirm summary prints them as.
      await press(tester, 'Back');
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(
        fields.map((field) => field.controller?.text),
        containsAll(<String>['Dana Cruz', '09171234567']),
      );

      await press(tester, 'Back');
      expect(find.text('Cart total'.toUpperCase()), findsOneWidget);
      // The line's own price and the total below it.
      expect(find.text('₱80'), findsNWidgets(2));
    });

    testWidgets('reprices a resumed order against the board and says so', (
      tester,
    ) async {
      await seedMenu();
      await pumpWizard(tester);
      await fillCart(tester);
      await press(tester, 'Save for later');

      final draft = BrewDraft.read((await savedDraft())!);

      // The shop puts the medium up by ₱10 overnight.
      await seedMenu(
        sizePrices: const {'small': 5000, 'medium': 9000, 'large': 10000},
      );

      await pumpWizard(tester, draft: draft);

      // Today's figure, not the one that was banked — and the reader is told
      // which, rather than left to notice the total moved.
      expect(find.text('₱90'), findsWidgets);
      expect(find.text('₱80'), findsNothing);
      expect(find.textContaining('prices have changed'), findsOneWidget);
    });

    testWidgets('leaves out a drink the shop has stopped selling', (
      tester,
    ) async {
      await seedMenu();
      await pumpWizard(tester);
      await fillCart(tester);
      await press(tester, 'Save for later');

      final draft = BrewDraft.read((await savedDraft())!);

      // The latte comes off the board entirely.
      await db
          .collection('shops')
          .doc(BrewPartner.a.id)
          .collection('menu')
          .doc('latte')
          .delete();

      await pumpWizard(tester, draft: draft);

      // Nothing recoverable, so the reader is put back on step one to build a
      // drink rather than left looking at an empty basket they cannot advance
      // out of.
      expect(find.text('Select coffee & size'), findsOneWidget);
      expect(find.text('Cart total'.toUpperCase()), findsNothing);
    });

    testWidgets('says nothing about prices when nothing moved', (tester) async {
      await seedMenu();
      await pumpWizard(tester);
      await fillCart(tester);
      await press(tester, 'Save for later');

      final draft = BrewDraft.read((await savedDraft())!);
      await pumpWizard(tester, draft: draft);

      // A resumed order that came back exactly as it was left carries no notice.
      // A card that always warns about prices is a card nobody reads.
      expect(find.textContaining('prices have changed'), findsNothing);
      expect(find.textContaining('no longer on the menu'), findsNothing);
      // Twice: the line's own price and the cart total under it.
      expect(find.text('₱80'), findsNWidgets(2));
    });

    /// Asserts the cart step's two index expressions agree, on the frame that
    /// is actually on screen.
    ///
    /// `_bodyLength` counts the cart step as
    /// `_cart.length + 2 + (_resumeNotice == null ? 0 : 1)`, and `_cartBody`
    /// deals its indices from an `offset` that is 1 when there is a notice and 0
    /// when there is not. Those are two expressions that must agree about
    /// whether the notice is present — the pair that drifted apart once already,
    /// per the comment above `offset`.
    ///
    /// Read off the tree rather than inferred from a thrown assert, because on
    /// this screen the assert never fires. A resumed cart's rows are built after
    /// [_restore]'s setState, so they mount into a [StaggerGroup] whose
    /// controller is already past their cue; [StaggerItem] hands those to its
    /// `_late` controller, which plays a fixed ramp and never constructs the
    /// [Interval] whose `end <= 1.0` is the assertion. Pumping and checking
    /// `takeException` is null therefore passes just as happily with the notice
    /// term deleted from `_bodyLength` — verified by deleting it. Comparing the
    /// largest index dealt against the group's own count is the check that does
    /// not depend on when the rows happened to mount.
    void expectIndicesInsideCount(WidgetTester tester) {
      final group = tester.widget<StaggerGroup>(
        find.byType(StaggerGroup).last,
      );
      final indices = tester
          .widgetList<StaggerItem>(
            find.descendant(
              of: find.byWidget(group),
              matching: find.byType(StaggerItem),
            ),
          )
          .map((item) => item.index);

      expect(indices, isNotEmpty, reason: 'the cart step deals rows');
      expect(
        indices.reduce((a, b) => a > b ? a : b),
        lessThan(group.itemCount),
        reason:
            'an index at or past itemCount is a timeline this row falls off '
            'the end of — the drift _bodyLength and offset are two halves of',
      );
    }

    testWidgets('a resumed cart staggers with a notice above it', (
      tester,
    ) async {
      await seedMenu();
      await pumpWizard(tester);
      await fillCart(tester);
      await press(tester, 'Save for later');

      final draft = BrewDraft.read((await savedDraft())!);

      // Moving the medium is what puts the notice on the step — the extra row
      // every index below it has to shift past.
      await seedMenu(
        sizePrices: const {'small': 5000, 'medium': 9000, 'large': 10000},
      );
      await pumpWizard(tester, draft: draft);

      expect(find.textContaining('prices have changed'), findsOneWidget);
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a resumed cart staggers with no notice above it', (
      tester,
    ) async {
      await seedMenu();
      await pumpWizard(tester);
      await fillCart(tester);
      await press(tester, 'Save for later');

      final draft = BrewDraft.read((await savedDraft())!);
      // The board is untouched, so the same cart comes back with nothing above
      // it and every index below sits one row higher.
      await pumpWizard(tester, draft: draft);

      expect(find.textContaining('prices have changed'), findsNothing);
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a resumed cart staggers when the size stopped being priced', (
      tester,
    ) async {
      await seedMenu();
      await pumpWizard(tester);
      await fillCart(tester);
      await press(tester, 'Save for later');

      final draft = BrewDraft.read((await savedDraft())!);

      // The medium the reader picked comes off the price list, which drops the
      // only line. That empties the cart, so [_restore] puts them back on step
      // one rather than on a basket they cannot advance out of — a different
      // step, with a different `_bodyLength` arm, reached through the same
      // restore path. Worth pumping because it is the branch where the cart
      // length and the notice both move and the step changes under them.
      await seedMenu(sizePrices: const {'small': 5000, 'large': 9000});
      await pumpWizard(tester, draft: draft);

      expect(find.text('Select coffee & size'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('placing a resumed order clears the draft behind it', (
      tester,
    ) async {
      await seedMenu();
      await pumpWizard(tester);
      await fillCart(tester);
      await fillPickup(tester);
      await press(tester, 'Save for later');

      final draft = BrewDraft.read((await savedDraft())!);
      await pumpWizard(tester, draft: draft);

      await press(tester, 'Review your order');
      await confirm(tester);

      expect(find.text('Order placed'), findsOneWidget);
      // One order at the counter and no draft left behind it — otherwise the
      // home screen would offer to resume an order already being made.
      expect((await db.collection('orders').get()).docs, hasLength(1));
      expect(await savedDraft(), isNull);
    });

    testWidgets('a resumed draft cannot be saved back before it has loaded', (
      tester,
    ) async {
      // No Firestore, so there is no board to rebuild the lines from and the
      // cart stays empty. Save for later must not offer to overwrite a saved
      // order with the nothing it managed to restore.
      await pumpWizard(
        tester,
        firestore: false,
        draft: const BrewDraft(
          partner: BrewPartner.a,
          step: 'cart',
          lines: [
            BrewDraftLine(
              itemId: 'latte',
              size: BrewItemSize.medium,
              extraIds: [],
              quantity: 1,
              unitCents: 8000,
            ),
          ],
          pickupName: 'Dana Cruz',
          pickupPhone: '09171234567',
          pickupNote: '',
          paymentMethod: 'Pay at counter',
        ),
      );

      expect(find.text('SAVE FOR LATER'), findsNothing);
    });
  });

  testWidgets('Buy on the board opens the wizard for that item', (
    tester,
  ) async {
    await db
        .collection('shops')
        .doc(BrewPartner.a.id)
        .collection('menu')
        .doc('latte')
        .set({'name': 'Iced Latte', 'priceCents': 8000});

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MenuScreen(shop: shop, session: session, counter: counter),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('BUY').first);
    await tester.pumpAndSettle();

    expect(find.byType(OrderWizardScreen), findsOneWidget);
    expect(find.text('Select coffee & size'), findsOneWidget);
  });
}

