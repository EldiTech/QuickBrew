import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';

/// A shop's editable identity: what it calls itself, and the picture it shows.
///
/// The rule under all of it is that Firestore *overrides* the built-in copy in
/// [BrewPartner] rather than replacing it. The enum is what makes the home
/// screen render on a cold offline start, so every one of these cases checks
/// that a missing or blank stored value falls back rather than printing nothing.
void main() {
  /// The smallest thing that is really a PNG: 1x1, transparent. Used because
  /// the decode path has to be exercised with bytes that are actually an image,
  /// not with arbitrary base64.
  const onePixelPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  group('the stored name', () {
    test('overrides the built-in one', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('shops').doc('coffee-shop-a').set({
        'name': 'Dave\'s Roastery',
        'description': 'Single origin, poured slow',
        'open': true,
      });

      final shops = await BrewCounter(db).shops().first;
      final a = shops.firstWhere((s) => s.partner == BrewPartner.a);

      expect(a.displayName, 'Dave\'s Roastery');
      expect(a.displayDescription, 'Single origin, poured slow');
    });

    test('falls back to the built-in when absent', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('shops').doc('coffee-shop-a').set({'open': true});

      final shops = await BrewCounter(db).shops().first;
      final a = shops.firstWhere((s) => s.partner == BrewPartner.a);

      expect(a.name, isNull, reason: 'nothing was stored');
      expect(a.displayName, 'Drip & Co', reason: 'but something must print');
      expect(a.displayDescription, BrewPartner.a.description);
    });

    test('a blank or whitespace name falls back rather than printing empty',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('shops').doc('coffee-shop-b').set({
        'name': '   ',
        'description': '',
      });

      final shops = await BrewCounter(db).shops().first;
      final b = shops.firstWhere((s) => s.partner == BrewPartner.b);

      expect(b.displayName, 'Seven Coffee & Tea');
      expect(b.displayDescription, BrewPartner.b.description);
    });

    test('renaming one shop leaves the other alone', () async {
      final db = FakeFirebaseFirestore();
      await BrewAdmin(db).setShopIdentity(
        BrewPartner.a,
        name: 'Renamed A',
        description: 'New line',
      );

      final shops = await BrewCounter(db).shops().first;
      expect(shops.length, 2, reason: 'always both partners');
      expect(shops[0].displayName, 'Renamed A');
      expect(shops[1].displayName, 'Seven Coffee & Tea');
    });

    test('clearing the name stores null, which reads as the built-in',
        () async {
      final db = FakeFirebaseFirestore();
      final admin = BrewAdmin(db);
      await admin.setShopIdentity(
        BrewPartner.a,
        name: 'Temporary',
        description: 'Temporary',
      );
      await admin.setShopIdentity(BrewPartner.a, name: '', description: '');

      final stored = await db.collection('shops').doc('coffee-shop-a').get();
      expect(stored.data()?['name'], isNull);

      final shops = await BrewCounter(db).shops().first;
      expect(shops[0].displayName, 'Drip & Co');
    });
  });

  group('the uploaded picture', () {
    test('is stored as base64 and comes back as decodable bytes', () async {
      final db = FakeFirebaseFirestore();
      final bytes = base64Decode(onePixelPng);

      final failure = await BrewAdmin(db).setShopLogoBase64(
        BrewPartner.a,
        bytes,
      );
      expect(failure, isNull, reason: 'a 1x1 png is well inside the limit');

      final stored = await db.collection('shops').doc('coffee-shop-a').get();
      expect(
        stored.data()?['logoBase64'],
        onePixelPng,
        reason: 'stored bare, not as a data URI',
      );

      final shops = await BrewCounter(db).shops().first;
      expect(shops[0].logoBytes, isNotNull);
      expect(shops[0].logoBytes, bytes);
    });

    test('is refused when it would not fit the document, with a sentence',
        () async {
      final db = FakeFirebaseFirestore();
      // Just over the ceiling once encoded. base64 is 4 chars per 3 bytes, so
      // this is deliberately sized past maxLogoChars rather than near it.
      final tooBig = Uint8List(BrewAdmin.maxLogoChars);

      final failure = await BrewAdmin(db).setShopLogoBase64(
        BrewPartner.a,
        tooBig,
      );

      expect(failure, isNotNull);
      expect(failure, contains('too large'));

      final stored = await db.collection('shops').doc('coffee-shop-a').get();
      expect(
        stored.data()?['logoBase64'],
        isNull,
        reason: 'a refused upload must not be half-written',
      );
    });

    test('a data URI prefix is tolerated on read', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('shops').doc('coffee-shop-a').set({
        'logoBase64': 'data:image/png;base64,$onePixelPng',
      });

      final shops = await BrewCounter(db).shops().first;
      expect(shops[0].logoBytes, base64Decode(onePixelPng));
    });

    test('an unreadable value costs the logo, not the shop', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('shops').doc('coffee-shop-a').set({
        'name': 'Still Here',
        'logoBase64': 'this is not base64 !!!!',
        'open': true,
      });

      final shops = await BrewCounter(db).shops().first;
      expect(shops[0].logoBytes, isNull);
      expect(shops[0].displayName, 'Still Here');
      expect(shops[0].status, BrewShopStatus.open);
    });

    test('removing it clears the stored value', () async {
      final db = FakeFirebaseFirestore();
      final admin = BrewAdmin(db);
      await admin.setShopLogoBase64(BrewPartner.a, base64Decode(onePixelPng));
      await admin.setShopLogoBase64(BrewPartner.a, null);

      final shops = await BrewCounter(db).shops().first;
      expect(shops[0].logoBytes, isNull);
    });
  });

  group('seeding', () {
    test('creates both documents with the built-in copy', () async {
      final db = FakeFirebaseFirestore();
      await BrewAdmin(db).ensureShops();

      final a = await db.collection('shops').doc('coffee-shop-a').get();
      final b = await db.collection('shops').doc('coffee-shop-b').get();
      expect(a.exists, isTrue);
      expect(b.exists, isTrue);
      expect(a.data()?['name'], 'Drip & Co');
      expect(b.data()?['name'], 'Seven Coffee & Tea');
      expect(
        a.data()?['open'],
        isNull,
        reason: 'nobody has said whether it is open; seeding must not decide',
      );
    });

    test('never overwrites a shop an admin has already renamed', () async {
      final db = FakeFirebaseFirestore();
      final admin = BrewAdmin(db);
      await admin.setShopIdentity(
        BrewPartner.a,
        name: 'Dave\'s Roastery',
        description: 'Mine now',
      );

      await admin.ensureShops();

      final shops = await BrewCounter(db).shops().first;
      expect(
        shops[0].displayName,
        'Dave\'s Roastery',
        reason: 'seeding on every launch must not reset a real edit',
      );
    });
  });
}
