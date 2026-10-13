import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/category_menu_screen.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadBrandFonts);

  late FakeFirebaseFirestore db;
  late BrewCounter counter;

  setUp(() {
    db = FakeFirebaseFirestore();
    counter = BrewCounter(db);
  });

  Future<void> pumpCategory(
    WidgetTester tester, {
    String category = 'Iced Blended',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: CategoryMenuScreen(
          shop: const BrewShop(
            partner: BrewPartner.a,
            status: BrewShopStatus.open,
          ),
          counter: counter,
          initialCategory: category,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders category drinks without top hero banner or cart bar', (tester) async {
    await pumpCategory(tester);

    expect(find.text('Drip & Co'), findsOneWidget);
    expect(find.text('Iced Blended'), findsOneWidget);
    // Hero banner and cart bar are removed
    expect(find.text('Cool comfort in every sip'), findsNothing);
    expect(find.text('View Cart'), findsNothing);
    expect(find.text('₱96.00'), findsNothing);

    // Drinks in Iced Blended
    expect(find.text('Dirty Avalanche'), findsOneWidget);
    expect(find.text('Java Frappe'), findsOneWidget);
    expect(find.text('₱80 | ₱90'), findsOneWidget);
  });

  testWidgets('toggles between list view (Screen 3) and grid view (Screen 4)', (
    tester,
  ) async {
    await pumpCategory(tester);

    // Initial state is list view: grid icon is offered to switch
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(find.byType(SliverGrid), findsNothing);

    // Tap layout toggle button in top bar
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();

    // Now in 2-column grid view (Screen 4)
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);

    // Tapping again switches back to list view
    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(SliverGrid), findsNothing);
  });

  testWidgets('renders products filtered by initial category without category pills bar', (
    tester,
  ) async {
    await pumpCategory(tester, category: 'Iced Blended');
    expect(find.text('Dirty Avalanche'), findsOneWidget);
    expect(find.text('Spanish Latte'), findsNothing);

    // Pump screen with Cà Phê
    await pumpCategory(tester, category: 'Cà Phê');
    expect(find.text('Spanish Latte'), findsOneWidget);
    expect(find.text('Dirty Avalanche'), findsNothing);
  });

  testWidgets('toggling favorite in grid view updates heart icon', (
    tester,
  ) async {
    await pumpCategory(tester);

    // Switch to grid view
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();

    // Initially outlined heart
    expect(find.byIcon(Icons.favorite_border_rounded), findsWidgets);

    // Tap first heart
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
    await tester.pumpAndSettle();

    // Now filled heart
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });
}
