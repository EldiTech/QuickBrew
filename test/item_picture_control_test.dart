import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/admin/admin_menu_screen.dart';
import 'package:quick_brew/widgets/menu_item_image.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The item sheet's picture control, in the state that has no picture yet.
///
/// This is the state an admin is in exactly when they want to upload, and it
/// used to have nothing pressable in it that looked pressable: the preview
/// collapsed to zero width with no bytes to draw, which left UPLOAD as a bare
/// 10px sage mono label stacked directly under the identically-styled NO
/// PICTURE caption. The control was there and it worked — it just read as a
/// second line of caption text, which is indistinguishable from missing.
void main() {
  setUpAll(loadBrandFonts);

  /// The smallest thing that is really a PNG: 1x1, transparent.
  const onePixelPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  Future<void> pumpSheet(
    WidgetTester tester, {
    required bool withPicture,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db
        .collection('shops')
        .doc(BrewPartner.b.id)
        .collection('menu')
        .add({
          'name': 'Iced Latte',
          'priceCents': 12000,
          if (withPicture) 'imageBase64': onePixelPng,
        });

    await tester.pumpWidget(
      MaterialApp(
        home: AdminMenuScreen(
          partner: BrewPartner.b,
          admin: BrewAdmin(db),
          counter: BrewCounter(db),
        ),
      ),
    );
    await settle(tester);

    // Into the edit sheet, which is where the picture control lives.
    await tester.tap(find.text('EDIT'));
    await settle(tester);
  }

  testWidgets('an item with no picture still offers something to press', (
    tester,
  ) async {
    await pumpSheet(tester, withPicture: false);

    expect(find.text('NO PICTURE'), findsOneWidget);
    expect(find.text('UPLOAD'), findsOneWidget);

    // The regression this file exists for. A zero-width preview is the bug:
    // it is what turned the whole picture control into two lines of caption.
    final frame = find.byType(BrewMenuItemImage);
    expect(frame, findsOneWidget);
    expect(
      tester.getSize(frame).width,
      greaterThan(0),
      reason: 'the empty picture frame must occupy space to be pressable',
    );
    expect(tester.getSize(frame), const Size(56, 56));
  });

  testWidgets('the empty frame is a control, not just a drawing', (
    tester,
  ) async {
    await pumpSheet(tester, withPicture: false);

    // Announced as a button with a sentence naming what it does — an
    // unlabelled 56px square would be read out as "button" and nothing else.
    expect(
      find.bySemanticsLabel('Upload a product picture'),
      findsWidgets,
      reason: 'the picture frame and the mono button both offer the upload',
    );
  });

  testWidgets('an item that already has one offers Replace and Remove', (
    tester,
  ) async {
    await pumpSheet(tester, withPicture: true);

    expect(find.text('PICTURE'), findsOneWidget);
    expect(find.text('REPLACE'), findsOneWidget);
    expect(find.text('REMOVE'), findsOneWidget);
    expect(find.text('UPLOAD'), findsNothing);
    // Laying a horizontal reveal out inside a Row is the one place this
    // pattern can fail outright rather than cosmetically — see
    // store_logo_control_test.dart, which makes the same check for the shop
    // logo's Remove.
    expect(tester.takeException(), isNull);
  });

  testWidgets('Remove takes the picture off without closing the sheet', (
    tester,
  ) async {
    await pumpSheet(tester, withPicture: true);

    await tester.tap(find.text('REMOVE'));
    await settle(tester);

    // Back to the empty state, still inside the sheet: removing a picture is
    // an edit to a form, not a save, and nothing is written until Save.
    expect(find.text('NO PICTURE'), findsOneWidget);
    expect(find.text('UPLOAD'), findsOneWidget);
    expect(find.text('REMOVE'), findsNothing);

    // Picked out by size rather than by position. The board row behind the
    // sheet is still drawing the saved picture at 40px, which is the point:
    // nothing has been written yet, so the two disagree until Save resolves it.
    final frames = tester.widgetList<BrewMenuItemImage>(
      find.byType(BrewMenuItemImage),
    );
    expect(
      frames.where((frame) => frame.dimension == 56).single.bytes,
      isNull,
      reason: 'the sheet\'s own 56px frame is the one that was cleared',
    );
  });
}
