import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/category_menu_screen.dart';
import 'package:quick_brew/screens/order_wizard_screen.dart';
import 'package:quick_brew/screens/store_landing_screen.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(loadBrandFonts);

  late FakeFirebaseFirestore db;
  late BrewCounter counter;

  setUp(() {
    db = FakeFirebaseFirestore();
    counter = BrewCounter(db);
  });

  Future<void> pumpStore(
    WidgetTester tester, {
    BrewPartner partner = BrewPartner.a,
    BrewShopStatus status = BrewShopStatus.open,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: StoreLandingScreen(
          shop: BrewShop(partner: partner, status: status),
          counter: counter,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders shop name, status, location and hours', (tester) async {
    await pumpStore(tester);

    expect(find.text('Drip & Co'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('Aurora, QC'), findsOneWidget);
    expect(find.text('7:00 AM - 10:00 PM'), findsOneWidget);
  });

  testWidgets('displays the three tab pills without reviews', (tester) async {
    await pumpStore(tester);

    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Reviews'), findsNothing);
  });

  testWidgets('renders the 5 Drip categories in MENU CATEGORIES section', (
    tester,
  ) async {
    await pumpStore(tester);

    expect(find.text('MENU CATEGORIES'), findsOneWidget);
    expect(find.text('Cà Phê Series'), findsOneWidget);
    expect(find.text('Hello Vietnam'), findsOneWidget);
    expect(find.text('Tiramisu'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('Milky Series'), findsOneWidget);
  });

  testWidgets('renders the Drip best seller and confirms cart bar is removed', (
    tester,
  ) async {
    await pumpStore(tester);

    expect(find.text('Try our Best Seller!'), findsOneWidget);
    expect(find.text('Dirty Avalanche'), findsNothing);
    expect(
      find.text(
        'Traditional slow-drip dark roast with sweetened condensed milk',
      ),
      findsOneWidget,
    );
    expect(find.text('View'), findsOneWidget);

    // Floating cart bar removed
    expect(find.text('View Cart'), findsNothing);
  });

  testWidgets('renders the Seven best seller only for Seven Coffee & Tea', (
    tester,
  ) async {
    await pumpStore(tester, partner: BrewPartner.b);

    expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    expect(find.text('Dirty Avalanche'), findsOneWidget);
    expect(find.text('Drip & Co'), findsNothing);
  });

  testWidgets('tapping Best Seller card navigates to OrderWizardScreen', (
    tester,
  ) async {
    await pumpStore(tester);

    await tester.ensureVisible(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderWizardScreen), findsOneWidget);
  });

  testWidgets(
    'tapping View button on Best Seller card navigates to OrderWizardScreen',
    (tester) async {
      await pumpStore(tester);

      await tester.ensureVisible(find.text('View'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderWizardScreen), findsOneWidget);
    },
  );

  testWidgets('tapping a category navigates to CategoryMenuScreen', (
    tester,
  ) async {
    await pumpStore(tester);

    await tester.tap(find.text('Premium'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryMenuScreen), findsOneWidget);
  });

  testWidgets('switching tabs displays About and Photos content', (
    tester,
  ) async {
    await pumpStore(tester);

    // Switch to About tab
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Our Story'), findsOneWidget);
    expect(find.text('Hours & Location'), findsOneWidget);
    expect(find.text('Amenities'), findsNothing);

    // Switch to Photos tab
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.text('STORE GALLERY'), findsOneWidget);
    expect(find.text('Barista Pour-Over Station'), findsOneWidget);

    expect(find.text('Reviews'), findsNothing);
  });

  testWidgets('Photos tab supports pagination across menu pictures', (
    tester,
  ) async {
    await pumpStore(tester);

    // Switch to Photos tab
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();

    // Verify Page 1 of 2
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Barista Pour-Over Station'), findsOneWidget);

    // Tap next page button to go to Page 2
    await tester.tap(find.byKey(const ValueKey('next_page_btn')));
    await tester.pumpAndSettle();

    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.text('Spanish Latte'), findsOneWidget);

    // Tap prev page button to go back to Page 1
    await tester.tap(find.byKey(const ValueKey('prev_page_btn')));
    await tester.pumpAndSettle();

    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Barista Pour-Over Station'), findsOneWidget);
  });

  testWidgets('tapping a photo opens a view-only item preview', (tester) async {
    await pumpStore(tester);

    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Barista Pour-Over Station'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barista Pour-Over Station'));
    await tester.pumpAndSettle();

    expect(find.text('ITEM PREVIEW'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.byType(OrderWizardScreen), findsNothing);
  });

  testWidgets(
    'category cards display pictures on Drip & Co and Seven Coffee & Tea',
    (tester) async {
      // Check Drip & Co
      await pumpStore(tester);
      expect(find.byType(Image), findsWidgets);

      // Check Seven Coffee & Tea
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: StoreLandingScreen(
            shop: const BrewShop(
              partner: BrewPartner.b,
              status: BrewShopStatus.open,
            ),
            counter: counter,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Seven Coffee & Tea'), findsOneWidget);
      expect(find.text('Cà Phê Series'), findsOneWidget);
      expect(find.text('Iced Blended'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    },
  );
}
