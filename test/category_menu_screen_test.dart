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
            partner: BrewPartner.b,
            status: BrewShopStatus.open,
          ),
          counter: counter,
          initialCategory: category,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders category drinks without top hero banner or cart bar', (
    tester,
  ) async {
    await pumpCategory(tester);

    expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    expect(find.text('Iced Blended'), findsOneWidget);
    // Hero banner and cart bar are removed
    expect(find.text('Cool comfort in every sip'), findsNothing);
    expect(find.text('View Cart'), findsNothing);
    expect(find.text('₱96.00'), findsNothing);

    // Drinks in Iced Blended
    expect(find.text('Dirty Avalanche'), findsOneWidget);
    expect(find.text('Java Frappe'), findsOneWidget);
    // Price and size are separate tiles now, so one amount cannot run into
    // the next size label on a narrow card.
    expect(find.text('M'), findsWidgets);
    expect(find.text('L'), findsWidgets);
    expect(find.textContaining('80'), findsWidgets);
    expect(find.textContaining('90'), findsWidgets);
  });

  group('pagination', () {
    /// Fourteen drinks in one category: three pages of six, six, two.
    Future<void> seedFourteen() async {
      final menu = db
          .collection('shops')
          .doc(BrewPartner.b.id)
          .collection('menu');
      for (var i = 1; i <= 14; i++) {
        await menu.doc('brew_$i').set({
          'name': 'Brew ${i.toString().padLeft(2, '0')}',
          'category': 'House Brews',
          'sizePrices': {'medium': 5000, 'large': 6000},
          'sort': i,
        });
      }
    }

    /// Scrolls the page controls into view — they sit under the drinks, past
    /// the bottom of the screen — and presses the one labelled [label].
    Future<void> tapPage(WidgetTester tester, String label) async {
      final semantics = tester.ensureSemantics();
      final target = find.bySemanticsLabel(label);
      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
      semantics.dispose();
    }

    testWidgets('shows one page at a time, with no endless scroll', (
      tester,
    ) async {
      await seedFourteen();
      await pumpCategory(tester, category: 'House Brews');

      expect(find.text('Brew 01'), findsOneWidget);
      expect(find.text('Brew 06', skipOffstage: false), findsOneWidget);
      // Page two is not built at all — it is not merely further down.
      expect(find.text('Brew 07', skipOffstage: false), findsNothing);
      expect(
        find.text('Showing 1–6 of 14 drinks', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('Load more', skipOffstage: false),
        findsNothing,
      );

      await tapPage(tester, 'Next page');
      expect(find.text('Brew 07'), findsOneWidget);
      expect(find.text('Brew 01', skipOffstage: false), findsNothing);
      expect(
        find.text('Showing 7–12 of 14 drinks', skipOffstage: false),
        findsOneWidget,
      );

      await tapPage(tester, 'Page 3');
      expect(find.text('Brew 13'), findsOneWidget);
      expect(find.text('Brew 14', skipOffstage: false), findsOneWidget);
      expect(find.text('Brew 12', skipOffstage: false), findsNothing);

      await tapPage(tester, 'Previous page');
      expect(find.text('Brew 07'), findsOneWidget);
    });

    testWidgets('searching starts again from page one', (tester) async {
      await seedFourteen();
      await pumpCategory(tester, category: 'House Brews');
      await tapPage(tester, 'Page 3');

      await tester.enterText(find.byType(TextField), 'Brew 0');
      await tester.pumpAndSettle();

      // Brew 01–09 match: two pages, starting at the first.
      expect(find.text('Brew 01'), findsOneWidget);
      expect(
        find.text('Showing 1–6 of 9 drinks', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('a category that fits on one page draws no page controls', (
      tester,
    ) async {
      await pumpCategory(tester);
      expect(find.textContaining('Showing', skipOffstage: false), findsNothing);
      expect(find.bySemanticsLabel('Next page'), findsNothing);
    });
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

  testWidgets(
    'renders products filtered by initial category without category pills bar',
    (tester) async {
      await pumpCategory(tester, category: 'Iced Blended');
      expect(find.text('Dirty Avalanche'), findsOneWidget);
      expect(find.text('Spanish Latte'), findsNothing);

      // Pump screen with Cà Phê
      await pumpCategory(tester, category: 'Cà Phê');
      expect(find.text('Spanish Latte'), findsOneWidget);
      expect(find.text('Dirty Avalanche'), findsNothing);
    },
  );

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

  testWidgets(
    'renders Drip & Co (Partner A) drinks for Hello Vietnam category',
    (tester) async {
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
            initialCategory: 'Hello Vietnam',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Drip & Co'), findsOneWidget);
      expect(find.text('Hello Vietnam'), findsOneWidget);
      expect(find.text('Cà Phê Sữa Đá'), findsOneWidget);
      expect(find.text('Cà Phê Trứng (Egg Coffee)'), findsOneWidget);
      // Category cards no longer substitute bundled fallback artwork when live
      // image bytes are unavailable.
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'renders Drip & Co drinks for Tiramisu, Premium, and Milky categories',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      // Test Tiramisu
      await tester.pumpWidget(
        MaterialApp(
          home: CategoryMenuScreen(
            shop: const BrewShop(
              partner: BrewPartner.a,
              status: BrewShopStatus.open,
            ),
            counter: counter,
            initialCategory: 'Tiramisu',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tiramisu Latte'), findsOneWidget);
      expect(find.text('Tiramisu Matcha'), findsOneWidget);

      // Test Premium
      await tester.pumpWidget(
        MaterialApp(
          home: CategoryMenuScreen(
            shop: const BrewShop(
              partner: BrewPartner.a,
              status: BrewShopStatus.open,
            ),
            counter: counter,
            initialCategory: 'Premium',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dolce de Leche'), findsOneWidget);
      expect(find.text('Velvet Cream Latte'), findsOneWidget);

      // Test Milky Series
      await tester.pumpWidget(
        MaterialApp(
          home: CategoryMenuScreen(
            shop: const BrewShop(
              partner: BrewPartner.a,
              status: BrewShopStatus.open,
            ),
            counter: counter,
            initialCategory: 'Milky Series',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Strawberry Milk'), findsOneWidget);
      expect(find.text('Blueberry Milk'), findsOneWidget);
    },
  );
}
