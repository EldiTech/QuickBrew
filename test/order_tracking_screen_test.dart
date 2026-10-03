import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/order_tracking_screen.dart';

import 'support/fonts.dart';

/// Where Track order goes: one order, full screen.
///
/// home_screen_test.dart already covers the press that lands here and one
/// live update through it. These are the cases that are awkward to reach from
/// there: an order with more drinks than the home card has room to list, a
/// rejected order's reason, and the screen on its own with no counter behind
/// it at all.
void main() {
  setUpAll(loadBrandFonts);

  const dave = BrewSession(uid: 'dave', name: 'David Espino', email: 'd@x.com');

  late FakeFirebaseFirestore db;
  late BrewCounter counter;

  setUp(() {
    db = FakeFirebaseFirestore();
    counter = BrewCounter(db);
  });

  Future<DocumentReference<Map<String, dynamic>>> place({
    String id = 'order1',
    String stage = 'preparing',
    String shop = 'coffee-shop-a',
    List<String> items = const ['Iced Latte', 'Croissant'],
    int? totalCents,
    String? rejectionReason,
  }) {
    return db.collection('orders').doc(id).set({
      'uid': dave.uid,
      'shop': shop,
      'items': items,
      'stage': stage,
      'etaLowMinutes': 10,
      'etaHighMinutes': 15,
      'totalCents': ?totalCents,
      'rejectionReason': ?rejectionReason,
      'placedAt': Timestamp.fromDate(DateTime(2026, 7, 25, 9)),
    }).then((_) => db.collection('orders').doc(id));
  }

  Future<BrewOrder> readBack(String id) async {
    final doc = await db.collection('orders').doc(id).get();
    return BrewOrder.read(id, doc.data()!)!;
  }

  Future<void> pump(
    WidgetTester tester,
    BrewOrder order, {
    BrewCounter? liveCounter,
    BrewSession? session,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: OrderTrackingScreen(
          order: order,
          session: session,
          counter: liveCounter,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the order it was handed with no counter at all', (
    tester,
  ) async {
    const order = BrewOrder(
      id: 'x',
      stage: BrewOrderStage.preparing,
      items: ['Iced Latte'],
    );
    await pump(tester, order);

    expect(find.text('Tracking your order.'), findsOneWidget);
    expect(find.text('PREPARING'), findsOneWidget);
    expect(find.text('Iced Latte'), findsOneWidget);
    // No live subscription was ever possible, so the screen says so rather
    // than silently pretending to be current.
    expect(find.textContaining('Live updates are unavailable'), findsOneWidget);
  });

  testWidgets('lists every drink, not just the first three', (tester) async {
    await place(
      items: const ['Espresso', 'Latte', 'Mocha', 'Cortado', 'Tea'],
    );
    final order = await readBack('order1');
    await pump(tester, order, liveCounter: counter, session: dave);

    for (final drink in ['Espresso', 'Latte', 'Mocha', 'Cortado', 'Tea']) {
      expect(find.text(drink), findsOneWidget);
    }
    expect(find.textContaining('more item'), findsNothing);
  });

  testWidgets('follows the order live after landing on it', (tester) async {
    await place(stage: 'received');
    final order = await readBack('order1');
    await pump(tester, order, liveCounter: counter, session: dave);

    expect(find.text('RECEIVED'), findsOneWidget);

    await db.collection('orders').doc('order1').update({'stage': 'ready'});
    await tester.pumpAndSettle();

    expect(find.text('READY'), findsOneWidget);
  });

  testWidgets('says why a declined order was declined', (tester) async {
    await place(stage: 'rejected', rejectionReason: 'Out of oat milk');
    final order = await readBack('order1');
    await pump(tester, order, liveCounter: counter, session: dave);

    expect(find.text('DECLINED'), findsOneWidget);
    expect(find.text('Out of oat milk'), findsOneWidget);
  });

  testWidgets('prints what the order came to, when it has a total', (
    tester,
  ) async {
    await place(totalCents: 15000);
    final order = await readBack('order1');
    await pump(tester, order, liveCounter: counter, session: dave);

    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('₱150'), findsOneWidget);
    expect(find.text('PLACED'), findsOneWidget);
  });

  testWidgets('Back pops the screen', (tester) async {
    const order = BrewOrder(
      id: 'x',
      stage: BrewOrderStage.preparing,
      items: ['Iced Latte'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              OrderTrackingScreen.route(reduced: true, order: order),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Tracking your order.'), findsOneWidget);

    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();
    expect(find.text('Tracking your order.'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
