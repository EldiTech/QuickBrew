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
    BrewShopStatus status = BrewShopStatus.open,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: StoreLandingScreen(
          shop: BrewShop(partner: BrewPartner.a, status: status),
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

  testWidgets('displays the four tab pills', (tester) async {
    await pumpStore(tester);

    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Reviews'), findsOneWidget);
  });

  testWidgets('renders the 6 category items in MENU CATEGORIES section', (
    tester,
  ) async {
    await pumpStore(tester);

    expect(find.text('MENU CATEGORIES'), findsOneWidget);
    expect(find.text('Cà Phê Series'), findsOneWidget);
    expect(find.text('Iced Blended'), findsOneWidget);
    expect(find.text('Milk Tea'), findsOneWidget);
    expect(find.text('Fresh Lemonade'), findsOneWidget);
    expect(find.text('Refresher'), findsOneWidget);
    expect(find.text('Add Ons'), findsOneWidget);
  });

  testWidgets('renders the Best Seller Dirty Avalanche card and confirms cart bar is removed', (
    tester,
  ) async {
    await pumpStore(tester);

    expect(find.text('Try our Best Seller!'), findsOneWidget);
    expect(find.text('Dirty Avalanche'), findsOneWidget);
    expect(find.text('Bold coffee. Creamy bliss.'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);

    // Floating cart bar removed
    expect(find.text('View Cart'), findsNothing);
  });

  testWidgets('tapping Best Seller card navigates to OrderWizardScreen', (
    tester,
  ) async {
    await pumpStore(tester);

    await tester.tap(find.text('Dirty Avalanche'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderWizardScreen), findsOneWidget);
  });

  testWidgets('tapping View button on Best Seller card navigates to OrderWizardScreen', (
    tester,
  ) async {
    await pumpStore(tester);

    await tester.ensureVisible(find.text('View'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderWizardScreen), findsOneWidget);
  });

  testWidgets('tapping a category navigates to CategoryMenuScreen', (
    tester,
  ) async {
    await pumpStore(tester);

    await tester.tap(find.text('Iced Blended'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryMenuScreen), findsOneWidget);
  });

  testWidgets('switching tabs displays About, Photos, and Reviews content', (
    tester,
  ) async {
    await pumpStore(tester);

    // Switch to About tab
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Our Story'), findsOneWidget);
    expect(find.text('Hours & Location'), findsOneWidget);
    expect(find.text('Amenities'), findsOneWidget);

    // Switch to Photos tab
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.text('STORE GALLERY'), findsOneWidget);
    expect(find.text('Barista Pour-Over Station'), findsOneWidget);

    // Switch to Reviews tab
    await tester.tap(find.text('Reviews'));
    await tester.pumpAndSettle();
    expect(find.text('4.9'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    // Tap Review button to open bottom sheet
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Write a Review'), findsOneWidget);
    expect(find.text('Submit Review'), findsOneWidget);

    // Submit review
    await tester.tap(find.text('Submit Review'));
    await tester.pumpAndSettle();
    expect(find.text('Thank you! Your review has been submitted.'), findsOneWidget);
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
}
