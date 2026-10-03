import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/admin_orders_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The admin queue: one shop's orders, scoped to that shop, oldest first; the
/// detail sheet a tap on a row opens; and the two writes that sheet offers —
/// advancing a stage, and rejecting the order outright.
void main() {
  setUpAll(loadBrandFonts);

  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  ordersCollection() => db.collection('orders');

  Future<void> placeOrder(
    String id, {
    BrewPartner partner = BrewPartner.a,
    String stage = 'received',
    String pickupName = 'Alex',
    List<String> items = const ['Iced Latte'],
    int totalCents = 1500,
    DateTime? placedAt,
  }) {
    return ordersCollection().doc(id).set({
      'uid': 'reader-$id',
      'shop': partner.id,
      'items': items,
      'stage': stage,
      'totalCents': totalCents,
      'pickupName': pickupName,
      'pickupPhone': '0917 000 0000',
      'paymentMethod': 'Pay at counter',
      'placedAt': Timestamp.fromDate(placedAt ?? DateTime(2026, 1, 1)),
    });
  }

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
        home: AdminOrdersScreen(
          partner: partner,
          admin: firestore ? BrewAdmin(db) : null,
        ),
      ),
    );
    await settle(tester);
  }

  /// Opens the detail sheet for the row carrying [pickupName]. Every row
  /// prints the pickup name once, so tapping that text is tapping the row.
  Future<void> openDetail(WidgetTester tester, String pickupName) async {
    await tester.tap(find.text(pickupName).first);
    await settle(tester);
  }

  testWidgets('an empty queue says so rather than showing a blank column', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(
      find.textContaining('Orders land here'),
      findsOneWidget,
    );
  });

  testWidgets('only this shop\'s orders are shown', (tester) async {
    await placeOrder('mine', partner: BrewPartner.a, pickupName: 'Casey');
    await placeOrder('theirs', partner: BrewPartner.b, pickupName: 'Drew');

    await pumpScreen(tester, partner: BrewPartner.a);

    expect(find.text('Casey'), findsOneWidget);
    expect(find.text('Drew'), findsNothing);
  });

  testWidgets('orders queue oldest first', (tester) async {
    await placeOrder(
      'newer',
      pickupName: 'Newer',
      placedAt: DateTime(2026, 1, 2),
    );
    await placeOrder(
      'older',
      pickupName: 'Older',
      placedAt: DateTime(2026, 1, 1),
    );

    await pumpScreen(tester);

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(names.indexOf('Older'), lessThan(names.indexOf('Newer')));
  });

  testWidgets('a completed order sits under its own section, not the active queue', (
    tester,
  ) async {
    await placeOrder('active-one', stage: 'received', pickupName: 'Waiting');
    await placeOrder('done-one', stage: 'completed', pickupName: 'Finished');

    await pumpScreen(tester);

    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('COMPLETED'), findsWidgets);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
  });

  testWidgets('with no Firestore behind it, the screen renders but cannot advance anything', (
    tester,
  ) async {
    await pumpScreen(tester, firestore: false);

    expect(find.text('Looking up orders…'), findsOneWidget);
  });

  group('the detail sheet', () {
    testWidgets('shows the pickup phone, note, payment method and items', (
      tester,
    ) async {
      await ordersCollection().doc('full').set({
        'uid': 'reader-full',
        'shop': BrewPartner.a.id,
        'items': ['Iced Latte', 'Croissant'],
        'stage': 'received',
        'totalCents': 31000,
        'pickupName': 'Alex',
        'pickupPhone': '0917 000 0000',
        'pickupNote': 'Extra napkins',
        'paymentMethod': 'GCash',
        'placedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await pumpScreen(tester);

      await openDetail(tester, 'Alex');

      expect(find.text('Iced Latte'), findsOneWidget);
      expect(find.text('Croissant'), findsOneWidget);
      expect(find.text('0917 000 0000'), findsOneWidget);
      expect(find.text('Extra napkins'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      // Each fact sits under its own mono label inside a card now, rather
      // than being spelled out in the value — see `_DetailCard`.
      expect(find.text('NOTE'), findsOneWidget);
      expect(find.text('PAYMENT'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
      // Twice: the card's own value, and the row still standing behind the
      // sheet, which summarises the same total.
      expect(find.text('₱310'), findsNWidgets(2));
    });

    testWidgets('an uploaded receipt reaches the counter, and none draws none', (
      tester,
    ) async {
      // 1x1 transparent PNG — the sheet only has to show that bytes arrived.
      const onePixelPng =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
          'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

      await ordersCollection().doc('paid').set({
        'uid': 'reader-paid',
        'shop': BrewPartner.a.id,
        'items': ['Iced Latte'],
        'stage': 'received',
        'totalCents': 8000,
        'pickupName': 'Alex',
        'pickupPhone': '0917 000 0000',
        'paymentMethod': 'Scan to pay',
        'receiptBase64': onePixelPng,
        'placedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await pumpScreen(tester);

      await openDetail(tester, 'Alex');
      expect(find.text('RECEIPT'), findsOneWidget);
      expect(find.text('Scan to pay'), findsOneWidget);
    });

    testWidgets('an order with no receipt draws no receipt card', (
      tester,
    ) async {
      // The ordinary case for every order placed before this step existed, and
      // for every shop with no code on file. An empty RECEIPT card would read
      // as a receipt that failed to load.
      await placeOrder('walk-in');
      await pumpScreen(tester);

      await openDetail(tester, 'Alex');
      expect(find.text('RECEIPT'), findsNothing);
    });

    testWidgets('pressing the forward action advances the stage by one', (
      tester,
    ) async {
      await placeOrder('walk-in', stage: 'received');
      await pumpScreen(tester);

      await openDetail(tester, 'Alex');
      expect(find.text('Start preparing'), findsOneWidget);

      await tester.tap(find.text('Start preparing'));
      await settle(tester);

      final doc = await ordersCollection().doc('walk-in').get();
      expect(doc.data()!['stage'], 'preparing');
    });

    testWidgets('a completed order offers no forward action and no reject', (
      tester,
    ) async {
      await placeOrder('done', stage: 'completed');
      await pumpScreen(tester);

      await openDetail(tester, 'Alex');

      expect(find.text('Mark completed'), findsNothing);
      expect(find.text('Reject order'), findsNothing);
    });

    testWidgets('rejecting asks for a reason and writes it with the stage', (
      tester,
    ) async {
      await placeOrder('walk-in', stage: 'preparing');
      await pumpScreen(tester);

      await openDetail(tester, 'Alex');
      await tester.tap(find.text('Reject order'));
      await settle(tester);

      // The confirmation sheet is up, stacked over the detail sheet rather
      // than replacing it — both are still in the tree, and both carry a
      // button reading "Reject order". `.last` is the one just opened.
      expect(find.text('Reject this order?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Out of oat milk');
      await tester.tap(find.text('Reject order').last);
      await settle(tester);

      final doc = await ordersCollection().doc('walk-in').get();
      expect(doc.data()!['stage'], 'rejected');
      expect(doc.data()!['rejectionReason'], 'Out of oat milk');
    });

    testWidgets('backing out of the reject prompt changes nothing', (
      tester,
    ) async {
      await placeOrder('walk-in', stage: 'preparing');
      await pumpScreen(tester);

      await openDetail(tester, 'Alex');
      await tester.tap(find.text('Reject order'));
      await settle(tester);

      await tester.tap(find.text('Keep the order'));
      await settle(tester);

      final doc = await ordersCollection().doc('walk-in').get();
      expect(doc.data()!['stage'], 'preparing');
    });

    testWidgets('a rejected order shows its reason and sits in Completed', (
      tester,
    ) async {
      await ordersCollection().doc('declined').set({
        'uid': 'reader-declined',
        'shop': BrewPartner.a.id,
        'items': ['Iced Latte'],
        'stage': 'rejected',
        'rejectionReason': 'Shop closing early',
        'pickupName': 'Alex',
        'placedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await pumpScreen(tester);

      expect(find.text('ORDER DECLINED'), findsOneWidget);

      await openDetail(tester, 'Alex');
      expect(find.text('Shop closing early'), findsOneWidget);
    });
  });
}
