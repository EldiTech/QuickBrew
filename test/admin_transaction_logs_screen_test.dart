import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/screens/admin/admin_transaction_logs_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

void main() {
  setUpAll(loadBrandFonts);

  Future<FakeFirebaseFirestore> seed() async {
    final db = FakeFirebaseFirestore();
    final orders = db.collection('orders');
    await orders.doc('pending').set({
      'uid': 'reader-1',
      'shop': 'coffee-shop-a',
      'items': ['Iced Latte'],
      'stage': 'preparing',
      'totalCents': 8500,
      'pickupName': 'Pending Customer',
      'pickupPhone': '09170000001',
      'paymentMethod': 'Full payment',
      'placedAt': DateTime(2026, 10, 18, 9),
    });
    await orders.doc('completed').set({
      'uid': 'reader-2',
      'shop': 'coffee-shop-b',
      'items': ['Americano'],
      'stage': 'completed',
      'totalCents': 6000,
      'pickupName': 'Completed Customer',
      'pickupPhone': '09170000002',
      'paymentMethod': 'Full payment',
      'placedAt': DateTime(2026, 10, 18, 8),
    });
    await orders.doc('rejected').set({
      'uid': 'reader-3',
      'shop': 'coffee-shop-a',
      'items': ['Mocha'],
      'stage': 'rejected',
      'totalCents': 5500,
      'pickupName': 'Rejected Customer',
      'placedAt': DateTime(2026, 10, 18, 7),
    });
    return db;
  }

  Future<void> pumpLog(
    WidgetTester tester,
    FakeFirebaseFirestore db,
    AdminTransactionLogKind kind,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminTransactionLogsScreen(kind: kind, admin: BrewAdmin(db)),
      ),
    );
    await settle(tester);
  }

  testWidgets('pending log excludes completed and rejected orders', (
    tester,
  ) async {
    final db = await seed();
    await pumpLog(tester, db, AdminTransactionLogKind.pending);

    expect(find.text('Pending Customer'), findsOneWidget);
    expect(find.text('Completed Customer'), findsNothing);
    expect(find.text('Rejected Customer'), findsNothing);
    expect(find.text('₱85'), findsNWidgets(2));
  });

  testWidgets('completed log contains completed orders only', (tester) async {
    final db = await seed();
    await pumpLog(tester, db, AdminTransactionLogKind.completed);

    expect(find.text('Completed Customer'), findsOneWidget);
    expect(find.text('Pending Customer'), findsNothing);
    expect(find.text('Rejected Customer'), findsNothing);
    expect(find.text('₱60'), findsNWidgets(2));
  });
}
