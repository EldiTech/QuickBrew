import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/brew_menu_seed.dart';

/// The bundled price list is data, and data this app ships is worth the same
/// scrutiny as code: a parser that silently drops half the board still
/// produces a menu, just a wrong one.
void main() {
  final csv = File(BrewMenuSeed.asset).readAsStringSync();
  final items = BrewMenuSeed.parse(csv);

  test('reads every priced row and nothing else', () {
    // The file's own footer says 116, which is the count this has to match:
    // the title, the note, the header and the two footer rows are not
    // products.
    expect(items.length, 116);
  });

  test('drops the header row rather than importing it as a drink', () {
    expect(items.where((item) => item.name == 'Item / Flavor'), isEmpty);
  });

  test('a two-size row is priced per size', () {
    final americano = items.firstWhere(
      (item) => item.name == 'Americano' && item.category == 'Iced Coffee',
    );
    expect(americano.sizePrices[BrewItemSize.medium], 3800);
    expect(americano.sizePrices[BrewItemSize.large], 4800);
    expect(americano.priceCents, isNull);
  });

  test('a one-size row is priced flat, not as a lone Medium', () {
    final lemonade = items.firstWhere((item) => item.name == 'Lemonade');
    expect(lemonade.sizePrices, isEmpty);
    expect(lemonade.priceCents, 4500);
  });

  test('categories and sub-categories come through', () {
    final dirty = items.first;
    expect(dirty.name, 'Dirty Avalanche');
    expect(dirty.category, 'Iced Blended');
    expect(dirty.subCategory, 'Frappe Series');
    expect(dirty.description, 'Coffee based');
  });

  test('a sub-category that merely repeats its category is not one', () {
    final hot = items.firstWhere(
      (item) => item.category == 'Hot Beverages',
    );
    expect(hot.subCategory, isNull);
  });

  test('bookkeeping notes are not printed as descriptions', () {
    final premium = items.firstWhere((item) => item.name == 'Sea Salt Latte');
    expect(premium.description, isNull);
  });

  test('board order is file order', () {
    for (final (index, item) in items.indexed) {
      expect(item.sort, index.toDouble());
    }
  });

  test('every item lands under a category the filters can offer', () {
    expect(items.every((item) => item.category.isNotEmpty), isTrue);
  });

  group('Drip & Co menu', () {
    final csv = File(BrewMenuSeed.dripCoAsset).readAsStringSync();
    final items = BrewMenuSeed.parse(csv);

    test('reads all 40 priced drinks', () {
      expect(items.length, 40);
    });

    test('categories match the spreadsheet', () {
      final categories = BrewMenuItem.categoriesOf([
        for (final item in items)
          BrewMenuItem.read('id-${item.name}', {
            'name': item.name,
            'category': item.category,
          })!,
      ]);
      expect(categories, [
        'Cà Phê Series',
        'Premium 45/55',
        'Premium 50/60',
        'Premium',
        'Milky Series',
        'Featured / Promo',
      ]);
    });

    test('two-size drinks are priced for Grande (medium) and Venti (large)', () {
      final americano = items.firstWhere((item) => item.name == 'Americano');
      expect(americano.sizePrices[BrewItemSize.medium], 3800);
      expect(americano.sizePrices[BrewItemSize.large], 4800);
      expect(americano.priceCents, isNull);
    });

    test('single-size promo drinks are flat priced', () {
      final eggCoffee = items.firstWhere(
        (item) => item.name == 'Cà Phê Trứng (Egg Coffee)',
      );
      expect(eggCoffee.sizePrices, isEmpty);
      expect(eggCoffee.priceCents, 8800);

      final tiramisu = items.firstWhere(
        (item) => item.name == 'Tiramisu Matcha',
      );
      expect(tiramisu.sizePrices, isEmpty);
      expect(tiramisu.priceCents, 9800);
    });

    test('board order is file order', () {
      for (final (index, item) in items.indexed) {
        expect(item.sort, index.toDouble());
      }
    });
  });

  group('Drip & Co add-ons', () {
    final addOns = BrewAddOnSeed.forPartner(BrewPartner.a);

    test('reads all 12 add-ons', () {
      expect(addOns.length, 12);
    });

    test('groups cover Coffee, Drizzle, Sinkers, Toppings, Milk choice', () {
      final groups = addOns.map((a) => a.group).toSet();
      expect(groups, containsAll([
        'Coffee',
        'Drizzle',
        'Sinkers',
        'Toppings',
        'Milk choice',
      ]));
    });

    test('prices match the spreadsheet', () {
      final extraShot = addOns.firstWhere((a) => a.name == 'Extra Shot');
      expect(extraShot.priceCents, 2000);

      final oatside = addOns.firstWhere((a) => a.name == 'Oatside');
      expect(oatside.priceCents, 3000);

      final boba = addOns.firstWhere((a) => a.name == 'Bobba Pearl');
      expect(boba.priceCents, 1000);
    });
  });
}

