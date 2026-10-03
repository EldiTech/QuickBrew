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
}
