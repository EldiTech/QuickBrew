import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/admin_profit_screen.dart';
import 'package:quick_brew/screens/admin/admin_transaction_logs_screen.dart';
import 'package:quick_brew/screens/order_wizard_screen.dart';
import 'package:quick_brew/widgets/brew_sheet.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

void main() {
  setUpAll(loadBrandFonts);

  test(
    'the supplied phone and tablet widths retain a usable content column',
    () {
      const widths = <double>[
        320,
        360,
        384,
        393,
        402,
        412,
        414,
        420,
        440,
        1024,
        1180,
        1280,
      ];

      for (final width in widths) {
        expect(brewPageContentWidth(width), greaterThan(0));
        expect(brewPageContentWidth(width), lessThanOrEqualTo(720));
      }

      expect(brewPageContentWidth(320), 288);
      expect(brewPageContentWidth(1024), 720);
    },
  );

  testWidgets('checkout and admin reports do not overflow at the smallest '
      'phone, narrow Android, or landscape tablet sizes', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('orders').doc('completed').set({
      'uid': 'reader-1',
      'shop': 'coffee-shop-a',
      'items': ['Iced Latte with oat milk'],
      'stage': 'completed',
      'totalCents': 8500,
      'pickupName': 'Completed Customer',
      'pickupPhone': '09170000001',
      'paymentMethod': 'Full payment',
      'placedAt': DateTime(2026, 10, 18, 9),
    });
    final admin = BrewAdmin(db);

    const sizes = <Size>[
      Size(320, 568),
      Size(360, 640),
      Size(412, 892),
      Size(1024, 768),
      Size(1280, 800),
    ];

    for (final size in sizes) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;

      await tester.pumpWidget(
        MaterialApp(
          home: AdminProfitScreen(
            partners: const [BrewPartner.a],
            admin: admin,
          ),
        ),
      );
      await settle(tester, const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: 'profit report at $size');

      await tester.pumpWidget(
        MaterialApp(
          home: AdminTransactionLogsScreen(
            kind: AdminTransactionLogKind.completed,
            admin: admin,
          ),
        ),
      );
      await settle(tester, const Duration(seconds: 2));
      expect(
        tester.takeException(),
        isNull,
        reason: 'transaction log at $size',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: OrderWizardScreen(
            shop: BrewShop(partner: BrewPartner.a, status: BrewShopStatus.open),
            item: BrewMenuItem(
              id: 'latte',
              name: 'Iced Latte',
              priceCents: 8500,
            ),
          ),
        ),
      );
      await settle(tester, const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: 'checkout at $size');
    }

    addTearDown(tester.view.reset);
  });
}
