import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/admin_menu_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The admin board laid out as a grid, against the real menu's worst cases:
/// long names, long categories, and two sizes per item.
void main() {
  setUpAll(loadBrandFonts);

  Future<FakeFirebaseFirestore> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    final menu = db.collection('shops').doc(BrewPartner.b.id).collection('menu');
    // Straight off the imported board, including the name that wraps worst.
    const rows = [
      ('Dirty Avalanche', 'Iced Blended', 'Frappe Series', 8000, 9000),
      ('Oreo Upside Down Choco', 'Iced Blended', 'Frappe Series', 6000, 7000),
      ('Fruit Tea - Passion Fruit', 'Refresher', 'Fruit Tea', 4000, 5000),
      ('Cookies & Cream Cream Cheese', 'Milktea', 'Cream Cheese', 5000, 6000),
    ];
    for (final (index, row) in rows.indexed) {
      final (name, category, sub, medium, large) = row;
      await menu.add({
        'name': name,
        'category': category,
        'subCategory': sub,
        'description': 'Coffee based',
        'sizePrices': {'medium': medium, 'large': large},
        'sort': index,
      });
    }

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
    return db;
  }

  testWidgets('lays the board out in two columns without overflowing', (
    tester,
  ) async {
    await pump(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'a cell must not overflow at half the board width',
    );

    // Two columns: the first pair shares a row, the next pair starts another.
    final first = tester.getTopLeft(find.text('Dirty Avalanche'));
    final second = tester.getTopLeft(find.text('Oreo Upside Down Choco'));
    final third = tester.getTopLeft(find.text('Fruit Tea - Passion Fruit'));

    expect(first.dy, second.dy);
    expect(first.dx, lessThan(second.dx));
    expect(third.dy, greaterThan(first.dy));
    expect(third.dx, first.dx);
  });

  testWidgets('prints both sizes as a chip each, on one row', (tester) async {
    await pump(tester);

    // One boxed chip per size, side by side — not the run-on "M ₱80 · L ₱90"
    // this board used to print, which ran past the cell edge as soon as a peso
    // figure took a second digit. See `_MenuCardPrices`.
    expect(find.text('M ₱80'), findsOneWidget);
    expect(find.text('L ₱90'), findsOneWidget);

    // Still one row, not a line each: a cell at half the board's width cannot
    // spare two, and the chips share a baseline to prove they did not stack.
    expect(
      tester.getTopLeft(find.text('M ₱80')).dy,
      tester.getTopLeft(find.text('L ₱90')).dy,
    );
    expect(
      tester.getTopLeft(find.text('M ₱80')).dx,
      lessThan(tester.getTopLeft(find.text('L ₱90')).dx),
    );

    // The chip abbreviates to the size's initial; the full word belongs to the
    // editor, not the board.
    expect(find.text('MEDIUM'), findsNothing);
  });

  testWidgets('a third size does not truncate the last price', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('shops')
        .doc(BrewPartner.b.id)
        .collection('menu')
        .add({
          'name': 'Dirty Avalanche',
          'sizePrices': {'small': 5000, 'medium': 8000, 'large': 9000},
        });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
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

    // All three prices reach the screen — the regression this guards against
    // is the third one lost to an ellipsis once it no longer fits beside the
    // other two. Each is its own chip now, scaled down by the FittedBox inside
    // it rather than truncated, which is what makes three fit where a run-on
    // line could only fit two.
    expect(find.text('S ₱50'), findsOneWidget);
    expect(find.text('M ₱80'), findsOneWidget);
    expect(find.text('L ₱90'), findsOneWidget);

    // Three across, still one row, and none of them overlapping the next.
    final small = tester.getTopLeft(find.text('S ₱50'));
    final medium = tester.getTopLeft(find.text('M ₱80'));
    final large = tester.getTopLeft(find.text('L ₱90'));
    expect(small.dy, medium.dy);
    expect(medium.dy, large.dy);
    expect(small.dx, lessThan(medium.dx));
    expect(medium.dx, lessThan(large.dx));

    expect(tester.takeException(), isNull);
  });

  testWidgets('files a cell by its sub-category, not both', (tester) async {
    await pump(tester);

    // The more specific of the two, and the one that fits: the category is
    // already on the chip above, and printing both truncates to
    // "ICED BLENDED ·…" — the half the reader could already see.
    expect(find.text('FRAPPE SERIES'), findsWidgets);
    expect(find.text('ICED BLENDED · FRAPPE SERIES'), findsNothing);

    await tester.tap(find.text('ICED BLENDED'));
    await settle(tester);

    expect(find.text('FRAPPE SERIES'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says so when an item has no category at all', (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('shops')
        .doc(BrewPartner.b.id)
        .collection('menu')
        .add({'name': 'Unfiled', 'priceCents': 100});

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
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

    expect(find.text('UNCATEGORISED'), findsOneWidget);
  });
}
