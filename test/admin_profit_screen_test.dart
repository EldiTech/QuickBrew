import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/admin_profit_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

void main() {
  setUpAll(loadBrandFonts);

  testWidgets('shows completed sales minus one platform fee per order', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('orders').doc('done').set({
      'uid': 'reader-1',
      'shop': 'coffee-shop-a',
      'items': ['Iced Latte'],
      'stage': 'completed',
      'totalCents': 8500,
      'pickupName': 'Completed Customer',
    });
    await db.collection('orders').doc('pending').set({
      'uid': 'reader-2',
      'shop': 'coffee-shop-a',
      'items': ['Americano'],
      'stage': 'preparing',
      'totalCents': 6000,
      'pickupName': 'Pending Customer',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AdminProfitScreen(
          partners: const [BrewPartner.a],
          admin: BrewAdmin(db),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Gross completed sales'), findsOneWidget);
    expect(find.text('Platform fees (₱5 × 1)'), findsOneWidget);
    expect(find.text('Net shop profit'), findsNWidgets(2));
    expect(find.text('₱85'), findsNWidgets(2));
    expect(find.text('-₱5'), findsNWidgets(2));
    expect(find.text('₱80'), findsNWidgets(2));
    expect(find.text('Pending Customer'), findsNothing);
  });
}
