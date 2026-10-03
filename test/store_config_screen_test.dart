import 'package:cloud_firestore/cloud_firestore.dart' show SetOptions;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/store_config_screen.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The store editor, and specifically the order its frames arrive in.
///
/// The interesting case is not "does it render" but "what happens on the build
/// where the snapshot finally lands": the name and description fields have to be
/// filled from Firestore exactly once, and the obvious place to do that — inside
/// the StreamBuilder that already has the data — is during a build, which is
/// the one moment a TextEditingController must not be written to.
/// One of the screen's UPLOAD controls, named by what it uploads.
///
/// The picture tile and the payment QR tile both draw the same four-letter mono
/// label, so the word alone matches two widgets. The semantics label is what
/// separates them here and on a screen reader, which makes this the finder that
/// tests the thing that actually distinguishes the controls.
Finder _upload(String semanticsLabel) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.semanticsLabel == semanticsLabel,
    );

void main() {
  setUpAll(loadBrandFonts);

  Future<FakeFirebaseFirestore> pump(
    WidgetTester tester, {
    Map<String, Object?>? shopA,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    if (shopA != null) {
      await db.collection('shops').doc('coffee-shop-a').set(shopA);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: StoreConfigScreen(
          partner: BrewPartner.a,
          admin: BrewAdmin(db),
          counter: BrewCounter(db),
        ),
      ),
    );
    return db;
  }

  testWidgets('fills the name and description from Firestore without throwing '
      'when the snapshot arrives after the first frame', (tester) async {
    // The document exists before mounting, but the *stream* still delivers
    // asynchronously — so the first build has no data and the second one does.
    // That second build is where a controller write would land on an already
    // mounted TextField and mark it dirty mid-build.
    await pump(tester, shopA: {
      'name': 'Brew Lab',
      'description': 'Single origin, poured slow',
      'open': true,
    });

    await settle(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'priming the fields must not write a controller during build',
    );
    expect(find.text('Brew Lab'), findsWidgets);
    expect(find.text('Single origin, poured slow'), findsOneWidget);
  });

  testWidgets('falls back to the built-in copy when the document has no name',
      (tester) async {
    await pump(tester, shopA: {'open': true});
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Drip & Co'), findsWidgets);
  });

  testWidgets('renders with no shop document at all', (tester) async {
    await pump(tester);
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Store Identity & Branding'.toUpperCase()), findsOneWidget);
    // A shop with no document has no picture either, and Upload rather than
    // Replace is how the picture tile says so. Found by its semantics label
    // rather than by the word: the payment QR tile below it draws an identical
    // UPLOAD for the same reason, and the label is the only thing that tells
    // the two apart — which is also the only thing a screen reader has.
    expect(_upload('Upload a shop picture'), findsOneWidget);
  });

  testWidgets('an edit in progress survives a later snapshot', (tester) async {
    // The reason the priming is guarded at all: a snapshot landing while the
    // admin is mid-word must not reset the field under them. This types into
    // the name field and then provokes another snapshot.
    final db = await pump(tester, shopA: {'name': 'Brew Lab', 'open': true});
    await settle(tester);

    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, 'Half-typed nam');
    await tester.pump();

    // Something else about the shop changes — the hours, say.
    await db.collection('shops').doc('coffee-shop-a').set({
      'name': 'Brew Lab',
      'open': false,
    }, SetOptions(merge: true));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.text('Half-typed nam'),
      findsOneWidget,
      reason: 'a snapshot must not overwrite what is being typed',
    );
  });

  testWidgets('the Orders tile opens the queue for this store', (tester) async {
    await pump(tester, shopA: {'name': 'Brew Lab', 'open': true});
    await settle(tester);

    expect(find.text('View orders'), findsOneWidget);

    await tester.tap(find.text('View orders'));
    await settle(tester);

    // Landed on the orders screen: it names the store by the enum's built-in
    // copy (it takes no counter, so it has no live name to read) and prints
    // the empty-queue sentence, which is unambiguous evidence of the push
    // without reaching into the new screen's implementation.
    expect(find.text('Drip & Co'), findsWidgets);
    expect(
      find.textContaining('Orders land here'),
      findsOneWidget,
      reason: 'an empty shop has no orders yet, and the queue says so',
    );
  });

  testWidgets('an order waiting on the shop shows as a badge on the Orders tile',
      (tester) async {
    final db = await pump(tester, shopA: {'name': 'Brew Lab', 'open': true});
    await db.collection('orders').doc('waiting').set({
      'uid': 'reader-1',
      'shop': 'coffee-shop-a',
      'items': ['Bun'],
      'stage': 'received',
      'pickupName': 'Alex',
    });
    await settle(tester);

    expect(find.text('1'), findsOneWidget);
  });
}
