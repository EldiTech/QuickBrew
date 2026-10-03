import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/menu_screen.dart';

import 'support/fonts.dart';

/// Where View menu goes. One shop's board — the ordering itself belongs to the
/// wizard Buy pushes, and is tested in order_wizard_screen_test.dart.
void main() {
  setUpAll(loadBrandFonts);

  late FakeFirebaseFirestore db;
  late BrewCounter counter;

  setUp(() {
    db = FakeFirebaseFirestore();
    counter = BrewCounter(db);
  });

  Future<void> add(String id, Map<String, Object?> data, {
    BrewPartner partner = BrewPartner.a,
  }) {
    return db
        .collection('shops')
        .doc(partner.id)
        .collection('menu')
        .doc(id)
        .set(data);
  }

  Future<void> pumpMenu(
    WidgetTester tester, {
    BrewPartner partner = BrewPartner.a,
    BrewShopStatus status = BrewShopStatus.open,
    bool firestore = true,
    BrewSession? session,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MenuScreen(
          shop: BrewShop(partner: partner, status: status),
          counter: firestore ? counter : null,
          session: session,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names the shop and repeats its hours before any price', (
    tester,
  ) async {
    await add('espresso', {'name': 'Espresso', 'priceCents': 300, 'sort': 10});
    await pumpMenu(tester, status: BrewShopStatus.closed);

    expect(find.text('Drip & Co'), findsOneWidget);
    expect(
      find.text('Vietnamese style coffee · Closed'),
      findsOneWidget,
      reason: 'a closed shop costs the reader something here, not on Home',
    );
    expect(
      tester.getTopLeft(find.text('Espresso')).dy,
      greaterThan(tester.getTopLeft(find.text('Drip & Co')).dy),
    );
  });

  testWidgets('rules the board in the order the shop set', (tester) async {
    await add('filter', {'name': 'Filter', 'priceCents': 350, 'sort': 20});
    await add('espresso', {
      'name': 'Espresso',
      'description': 'Two shots, no room',
      'priceCents': 300,
      'sort': 10,
    });
    await pumpMenu(tester);

    expect(find.text('Espresso'), findsOneWidget);
    expect(find.text('₱3'), findsOneWidget);
    expect(find.text('₱3.50'), findsOneWidget);

    // The board is a two-column grid, so the shop's order runs left to right
    // before it runs down: these two share a row, and the lower `sort` is the
    // one in the left-hand column.
    final espresso = tester.getTopLeft(find.text('Espresso'));
    final filter = tester.getTopLeft(find.text('Filter'));
    expect(espresso.dy, filter.dy, reason: 'the first two share a row');
    expect(espresso.dx, lessThan(filter.dx));
  });

  testWidgets('a third size does not truncate the last price', (
    tester,
  ) async {
    await add('avalanche', {
      'name': 'Dirty Avalanche',
      'sizePrices': {'small': 5000, 'medium': 8000, 'large': 9000},
    });
    await pumpMenu(tester);

    // All three prices reach the screen — one chip each, scaled down inside
    // its own box rather than the run-on line this card used to print, which
    // lost the last price to an ellipsis once a third size joined it. See
    // `_MenuCardPriceChip`.
    expect(find.text('S ₱50'), findsOneWidget);
    expect(find.text('M ₱80'), findsOneWidget);
    expect(find.text('L ₱90'), findsOneWidget);

    // Three across at half the board's width, sharing a baseline: the chips
    // shrink to fit rather than wrapping into a taller cell.
    final small = tester.getTopLeft(find.text('S ₱50'));
    final large = tester.getTopLeft(find.text('L ₱90'));
    expect(small.dy, large.dy);
    expect(small.dx, lessThan(large.dx));

    expect(tester.takeException(), isNull);
  });

  testWidgets('wraps onto a second row once a row is full', (tester) async {
    // Four items, so the grid has to wrap — which is where an order that only
    // held within a row would show itself.
    for (final (index, name) in ['One', 'Two', 'Three', 'Four'].indexed) {
      await add(name, {'name': name, 'priceCents': 300, 'sort': index * 10});
    }
    await pumpMenu(tester);

    final one = tester.getTopLeft(find.text('One'));
    final two = tester.getTopLeft(find.text('Two'));
    final three = tester.getTopLeft(find.text('Three'));
    final four = tester.getTopLeft(find.text('Four'));

    expect(one.dy, two.dy);
    expect(three.dy, four.dy);
    expect(three.dy, greaterThan(one.dy), reason: 'the third starts a new row');
    // And the columns line up down the grid rather than each row setting its
    // own measure.
    expect(three.dx, one.dx);
    expect(four.dx, two.dx);
  });

  testWidgets('says a shop has published nothing rather than spinning forever', (
    tester,
  ) async {
    await pumpMenu(tester, partner: BrewPartner.b);

    expect(
      find.text('Seven Coffee & Tea has not published a menu yet.'),
      findsOneWidget,
    );
  });

  testWidgets('browses only — nothing here claims to take an order', (
    tester,
  ) async {
    await add('bun', {'name': 'Bun', 'priceCents': 250});
    await pumpMenu(tester);

    for (final word in ['Add', 'Order now', 'Cart', 'Checkout', 'Basket']) {
      expect(
        find.textContaining(word),
        findsNothing,
        reason: 'there is nothing behind $word yet',
      );
    }
  });

  group('a reader at the order cap', () {
    const session = BrewSession(uid: 'reader-1', name: 'Dana Cruz');

    Future<void> placeOrders(int count) async {
      for (var i = 0; i < count; i++) {
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
    }

    testWidgets('is told at Buy rather than handed the wizard', (
      tester,
    ) async {
      await placeOrders(5);
      await add('bun', {'name': 'Bun', 'priceCents': 250});
      await pumpMenu(tester, session: session);

      await tester.tap(find.text('BUY'));
      await tester.pumpAndSettle();

      // The pop-up answers the press; the wizard never opens behind it.
      expect(find.text('You already have 5 orders open.'), findsOneWidget);
      expect(find.textContaining('wait for one of your open orders'),
          findsOneWidget);
      expect(find.text('Step 1 of 6'.toUpperCase()), findsNothing);

      // Dismissing it leaves the reader on the board they were browsing.
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Bun'), findsOneWidget);
      expect(find.byType(MenuScreen), findsOneWidget);
    });

    testWidgets('one order short of it still gets the wizard', (
      tester,
    ) async {
      await placeOrders(4);
      await add('bun', {'name': 'Bun', 'priceCents': 250});
      await pumpMenu(tester, session: session);

      await tester.tap(find.text('BUY'));
      await tester.pumpAndSettle();

      expect(find.text('Step 1 of 6'.toUpperCase()), findsOneWidget);
    });
  });

  testWidgets('Back returns to whatever pushed it', (tester) async {
    await add('bun', {'name': 'Bun'});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MenuScreen.route(
                shop: const BrewShop(
                  partner: BrewPartner.a,
                  status: BrewShopStatus.open,
                ),
                counter: counter,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuScreen), findsOneWidget);

    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();

    expect(find.byType(MenuScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  /// The board used to sit on "Loading the board…" forever whenever the read
  /// never answered — no Firestore behind the screen at all, or a refused one.
  /// [BrewCounter.menu] logged the error and swallowed it, so the stream neither
  /// emitted nor closed and the StreamBuilder held a null snapshot for good.
  group('a board that cannot be read says so rather than spinning', () {
    testWidgets('with no Firestore behind the screen', (tester) async {
      await pumpMenu(tester, firestore: false);

      expect(
        find.text('Loading the board…'),
        findsNothing,
        reason: 'nothing is coming, so this would never resolve',
      );
      expect(
        find.text(
          'Could not load the board. Check your connection and try again.',
        ),
        findsOneWidget,
      );
    });

    // The refused-read half of this — that a failing Firestore read reaches the
    // screen as an error at all rather than as silence — is covered as a unit
    // test in brew_counter_test.dart. It cannot be staged here:
    // fake_cloud_firestore does not enforce security rules on `snapshots()`, so
    // a locked-down instance yields an empty board rather than the error a
    // deployed build would raise.
  });
}
