import 'package:cloud_firestore/cloud_firestore.dart' show SetOptions;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/store_config_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The Remove control that only a shop with a picture has.
///
/// It sits in a [Row] beside Replace and comes and goes with the upload, which
/// makes it the one horizontal [BrewReveal] in the app — and the one place where
/// getting the absent state wrong is a layout failure rather than a cosmetic one:
/// the vertical version claims full width so a Column's cross-axis does not
/// twitch, and full width inside a Row is an unbounded-constraints crash.
/// A control on the picture tile, named by what it does to the picture.
///
/// The payment QR tile below draws the same three mono labels — UPLOAD, REPLACE,
/// REMOVE — for its own code, so the words alone no longer identify a control.
/// The semantics label does, which is the same thing a screen reader relies on
/// to tell the two tiles apart.
Finder _picture(String semanticsLabel) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.semanticsLabel == semanticsLabel,
    );

void main() {
  setUpAll(loadBrandFonts);

  /// The smallest thing that is really a PNG: 1x1, transparent.
  const onePixelPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  Future<FakeFirebaseFirestore> pump(
    WidgetTester tester, {
    required bool withPicture,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('shops').doc('coffee-shop-a').set({
      'name': 'Brew Lab',
      'description': 'Single origin, poured slow',
      'open': true,
      if (withPicture) 'logoBase64': onePixelPng,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StoreConfigScreen(
          partner: BrewPartner.a,
          admin: BrewAdmin(db),
          counter: BrewCounter(db),
        ),
      ),
    );
    await settle(tester);
    return db;
  }

  testWidgets('a shop with a picture offers Remove, and laying it out is sound',
      (tester) async {
    await pump(tester, withPicture: true);

    expect(
      tester.takeException(),
      isNull,
      reason: 'a horizontal reveal must not ask its Row for infinite width',
    );
    // Replace rather than Upload is the tile's whole statement that a picture
    // is already there — the "PICTURE"/"NO PICTURE" line that used to say it
    // a second time was dropped as duplication of what the mark above it
    // already shows.
    expect(_picture('Remove the shop picture'), findsOneWidget);
    expect(_picture('Replace the shop picture'), findsOneWidget);
    expect(_picture('Upload a shop picture'), findsNothing);
  });

  testWidgets('a shop with no picture offers only Upload', (tester) async {
    await pump(tester, withPicture: false);

    expect(tester.takeException(), isNull);
    expect(_picture('Upload a shop picture'), findsOneWidget);
    expect(_picture('Replace the shop picture'), findsNothing);
    expect(_picture('Remove the shop picture'), findsNothing);
  });

  testWidgets('Remove clears both the uploaded bytes and any hosted url', (
    tester,
  ) async {
    final db = await pump(tester, withPicture: true);
    // A document carrying both, which is the state a shop that was given a URL
    // and then had one uploaded over it ends up in.
    await db.collection('shops').doc('coffee-shop-a').set({
      'logoUrl': 'https://example.test/a.png',
    }, SetOptions(merge: true));
    await settle(tester);

    await tester.tap(_picture('Remove the shop picture'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    final stored = await db.collection('shops').doc('coffee-shop-a').get();
    expect(stored.data()?['logoBase64'], isNull);
    expect(stored.data()?['logoUrl'], isNull);
    // And the controls that only exist while there is a picture have gone
    // with it: Remove is away, and Replace is back to being Upload.
    expect(_picture('Remove the shop picture'), findsNothing);
    expect(_picture('Upload a shop picture'), findsOneWidget);
  });
}
