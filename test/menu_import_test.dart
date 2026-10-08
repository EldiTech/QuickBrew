import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/brew_menu_seed.dart';

/// The bulk import, which is the one write in this app that deletes things the
/// admin did not name.
void main() {
  const seed = [
    BrewSeedItem(
      name: 'Americano',
      category: 'Iced Coffee',
      subCategory: 'Classic',
      sizePrices: {BrewItemSize.medium: 3800, BrewItemSize.large: 4800},
      sort: 0,
    ),
    BrewSeedItem(
      name: 'Lemonade',
      category: 'Fresh Lemonade',
      priceCents: 4500,
      sort: 1,
    ),
  ];

  Future<FakeFirebaseFirestore> withBoard(List<Map<String, Object?>> items) async {
    final db = FakeFirebaseFirestore();
    for (final item in items) {
      await db
          .collection('shops')
          .doc(BrewPartner.b.id)
          .collection('menu')
          .add(item);
    }
    return db;
  }

  test('writes every item with its category intact', () async {
    final db = await withBoard(const []);
    final failure = await BrewAdmin(db).importMenu(BrewPartner.b, seed);
    expect(failure, isNull);

    final items = await BrewCounter(db).menu(BrewPartner.b).first;
    expect(items.map((item) => item.name), ['Americano', 'Lemonade']);

    final americano = items.first;
    expect(americano.category, 'Iced Coffee');
    expect(americano.subCategory, 'Classic');
    expect(americano.sizePrices[BrewItemSize.large], 4800);
    expect(americano.price, isNull, reason: 'a sized item has no flat price');

    final lemonade = items.last;
    expect(lemonade.subCategory, isNull);
    expect(lemonade.price, '₱45');
  });

  test('replaces the board rather than appending to it', () async {
    // Run twice against a board that already holds something. An append would
    // leave the old item behind and both copies of the seed on the board.
    final db = await withBoard([
      {'name': 'Something an admin typed', 'priceCents': 100},
    ]);
    final admin = BrewAdmin(db);

    await admin.importMenu(BrewPartner.b, seed);
    await admin.importMenu(BrewPartner.b, seed);

    final items = await BrewCounter(db).menu(BrewPartner.b).first;
    expect(items.map((item) => item.name), ['Americano', 'Lemonade']);
  });

  test('leaves the other shop alone', () async {
    final db = await withBoard(const []);
    await db
        .collection('shops')
        .doc(BrewPartner.a.id)
        .collection('menu')
        .add({'name': 'Untouched', 'priceCents': 100});

    await BrewAdmin(db).importMenu(BrewPartner.b, seed);

    final other = await BrewCounter(db).menu(BrewPartner.a).first;
    expect(other.map((item) => item.name), ['Untouched']);
  });

  test('refuses an empty list rather than wiping the board with it', () async {
    final db = await withBoard([
      {'name': 'Still here', 'priceCents': 100},
    ]);
    final failure = await BrewAdmin(db).importMenu(BrewPartner.b, const []);

    expect(failure, isNotNull);
    final items = await BrewCounter(db).menu(BrewPartner.b).first;
    expect(items.map((item) => item.name), ['Still here']);
  });

  test('imports Drip & Co menu into coffee-shop-a collection', () async {
    final csv = File(BrewMenuSeed.dripCoAsset).readAsStringSync();
    final dripSeed = BrewMenuSeed.parse(csv);
    final db = FakeFirebaseFirestore();
    final failure = await BrewAdmin(db).importMenu(BrewPartner.a, dripSeed);
    expect(failure, isNull);

    final items = await BrewCounter(db).menu(BrewPartner.a).first;
    expect(items.length, 40);
    expect(items.first.name, 'Americano');
    expect(items.last.name, 'Tiramisu Matcha');
  });

  group('the filters the board offers', () {
    BrewMenuItem item(String name, String? category, [String? sub]) =>
        BrewMenuItem.read('id-$name', {
          'name': name,
          'category': category,
          'subCategory': sub,
        })!;

    test('are the categories in use, once each and in board order', () {
      final categories = BrewMenuItem.categoriesOf([
        item('Americano', 'Iced Coffee'),
        item('Latte', 'Iced Coffee'),
        item('Taro', 'Milktea'),
        item('Unfiled', null),
      ]);
      expect(categories, ['Iced Coffee', 'Milktea']);
    });

    test('drop a sub-category that merely repeats its category', () {
      final subs = BrewMenuItem.subCategoriesOf([
        item('Americano', 'Hot Beverages', 'Hot Beverages'),
        item('Latte', 'Hot Beverages', 'Hot Beverages'),
      ], 'Hot Beverages');
      expect(subs, isEmpty);
    });

    test('are scoped to the category asked for', () {
      final subs = BrewMenuItem.subCategoriesOf([
        item('Americano', 'Iced Coffee', 'Classic'),
        item('White Mocha', 'Iced Coffee', 'Special Coffee'),
        item('Taro', 'Milktea', 'Cream Cheese'),
      ], 'Iced Coffee');
      expect(subs, ['Classic', 'Special Coffee']);
    });
  });
}
