import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_admin.dart';
import 'package:quick_brew/screens/admin/users_screen.dart';
import 'package:quick_brew/theme/tokens.dart';
import 'package:quick_brew/widgets/brew_choice.dart';
import 'package:quick_brew/widgets/stagger.dart';

import 'support/fonts.dart';
import 'support/settle.dart';

/// The blank landing state, the Admin and User filters behind it, and the
/// View/Edit/Remove controls every row in either block now carries.
///
/// The cases worth a test here are not "does the list render" but the ones
/// where a form and a document can disagree: a promotion has to carry a store,
/// a demotion has to take one away, and neither may quietly drop the email the
/// row is identified by. The container group is about the second reading of the
/// same data — a shop with nobody assigned has to say so, and an account
/// belonging to neither shop must not be claimed by one. The tab group is about
/// the two blocks being mutually exclusive: neither shows until a filter is
/// pressed, and switching to one hides the other. The last group is about who
/// the roster leaves out — every admin and the super admin reading it, since
/// the roster is customers only.
void main() {
  setUpAll(loadBrandFonts);

  /// The reader: a super admin, as the console makes the first one.
  const dave = 'dave';

  Future<FakeFirebaseFirestore> pump(
    WidgetTester tester, {
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    final users = db.collection('users');
    await users.doc(dave).set({
      'email': 'david@work.com',
      'role': 'superadmin',
      'createdAt': DateTime(2026, 1, 1),
    });
    await users.doc('mia').set({
      'email': 'mia@work.com',
      'name': 'Mia',
      'role': 'admin',
      'assignedStore': 'coffee-shop-a',
      'createdAt': DateTime(2026, 2, 1),
    });
    await users.doc('sam').set({
      'email': 'sam@example.com',
      'name': 'Sam',
      'role': 'customer',
      'createdAt': DateTime(2026, 3, 1),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: UsersScreen(admin: BrewAdmin(db), currentUid: dave),
        ),
      ),
    );
    await settle(tester);
    return db;
  }

  /// The roster only ever lists customers, so with one customer in the fixture
  /// its Edit button is the roster's row 0. Mia, the admin, is reached through
  /// her shop container's own Edit instead — there is only one of her, so
  /// nothing there needs an index.
  const sam = 0;

  /// The roster can sit below the fold once the User tab is on screen, so a
  /// control is scrolled to before it is pressed, the way a reader gets to it.
  Future<void> tapRoster(WidgetTester tester, String label, int row) async {
    final control = find.text(label).at(row);
    await tester.ensureVisible(control);
    await settle(tester);
    await tester.tap(control);
    await settle(tester);
  }

  Future<void> openEditor(WidgetTester tester, int row) =>
      tapRoster(tester, 'EDIT', row);

  /// The tab bar above both blocks, toggling which one is on screen.
  Future<void> tapSection(WidgetTester tester, String label) async {
    final control = find.text(label);
    await tester.ensureVisible(control);
    await settle(tester);
    await tester.tap(control);
    await settle(tester);
  }

  /// The sheet, so an assertion about the editor cannot be answered by the
  /// screen behind it — which now names both stores in its own right.
  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(BottomSheet), matching: matching);

  Future<Map<String, Object?>?> read(
    FakeFirebaseFirestore db,
    String uid,
  ) async {
    return (await db.collection('users').doc(uid).get()).data();
  }

  testWidgets('opens blank, before either filter is picked', (tester) async {
    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Drip & Co'), findsNothing);
    expect(find.text('Seven Coffee & Tea'), findsNothing);
    expect(find.text('Sam'), findsNothing);
    expect(find.text('ADMIN'), findsOneWidget);
    expect(find.text('USER'), findsOneWidget);
  });

  testWidgets(
      'lists only customer accounts, leaving admins and the super admin for '
      'the Admin tab', (tester) async {
    await pump(tester);
    await tapSection(tester, 'USER');

    expect(tester.takeException(), isNull);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Mia'), findsNothing);
    expect(find.text('david@work.com'), findsNothing);
    expect(find.text('1 ACCOUNT'), findsOneWidget);
  });

  testWidgets('carries no role eyebrow, since every row it can hold is a '
      'customer', (tester) async {
    await pump(tester);
    await tapSection(tester, 'USER');

    // Not "ADMIN": the tab bar's own button already answers to that string.
    expect(find.text('SUPER ADMIN'), findsNothing);
    expect(find.text('CUSTOMER'), findsNothing);
  });

  testWidgets(
      'shows the empty message once every customer is gone, without falling '
      'back to admins', (tester) async {
    final db = await pump(tester);
    await db.collection('users').doc('sam').delete();
    await tapSection(tester, 'USER');

    expect(find.text('No accounts yet.'), findsOneWidget);
    expect(find.text('Mia'), findsNothing);
    expect(find.text('david@work.com'), findsNothing);
  });

  /// The stagger timeline, across all three states of [_section].
  ///
  /// `staggerCount` here is a switch over the section — three arms, of which
  /// exactly one is live on any frame — and it is **deliberately left as a
  /// switch**. The blocks it counts are built inside the StreamBuilder below it,
  /// so the counter that orders_panel.dart now uses is not available here for
  /// the reason admin_home_screen.dart:107-120 sets out: slots allocated inside
  /// a builder callback have not been dealt when the count above is read, and
  /// the callback re-runs on every snapshot. The counter is only safe when every
  /// slot is dealt before the children list is built.
  ///
  /// So the switch stays and these tests check each arm against it.
  ///
  /// The check reads the largest index actually dealt off the tree and compares
  /// it to the group's own count, rather than pumping and asking whether
  /// anything threw. Waiting for a throw does not work on this screen: only the
  /// blank arm is on screen when the group is built, and the other two are
  /// reached by pressing a filter, so their items mount into a controller
  /// already past their cue. [StaggerItem] hands those to its `_late` ramp,
  /// which never constructs the [Interval] whose `end <= 1.0` is the assertion —
  /// dealing the Admin arm one short leaves a pump-and-catch test passing.
  /// Comparing the two numbers directly does not care when a row mounted.
  void expectIndicesInsideCount(WidgetTester tester) {
    final group = tester.widget<StaggerGroup>(find.byType(StaggerGroup).last);
    final indices = tester
        .widgetList<StaggerItem>(
          find.descendant(
            of: find.byWidget(group),
            matching: find.byType(StaggerItem),
          ),
        )
        .map((item) => item.index);

    expect(indices, isNotEmpty, reason: 'every arm deals at least one row');
    expect(
      indices.reduce((a, b) => a > b ? a : b),
      lessThan(group.itemCount),
      reason: 'an index at or past itemCount falls off the end of the timeline',
    );
  }

  group('stagger timeline', () {
    testWidgets('the blank prompt, before either filter is pressed', (
      tester,
    ) async {
      await pump(tester);
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Pick Admin'), findsOneWidget);
    });

    testWidgets('the Admin arm, which is the longest of the three', (
      tester,
    ) async {
      await pump(tester);
      await tapSection(tester, 'ADMIN');

      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Drip & Co'), findsOneWidget);
      expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    });

    testWidgets('the User arm, which is one block however long the roster is', (
      tester,
    ) async {
      await pump(tester);
      await tapSection(tester, 'USER');

      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Sam'), findsOneWidget);
    });

    testWidgets('crossing between the two arms, in both directions', (
      tester,
    ) async {
      await pump(tester);
      await tapSection(tester, 'ADMIN');
      expectIndicesInsideCount(tester);

      await tapSection(tester, 'USER');
      expectIndicesInsideCount(tester);

      await tapSection(tester, 'ADMIN');
      // The count changes in the same frame the new block arrives in, so this
      // is the crossing rather than either arm at rest.
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Drip & Co'), findsOneWidget);
    });

    testWidgets('the Admin arm with nobody assigned to either shop', (
      tester,
    ) async {
      final db = await pump(tester);
      await db.collection('users').doc('mia').delete();
      await tapSection(tester, 'ADMIN');

      // Both containers are still drawn — the shop count is what the arm counts,
      // not the people in them — so this is the same index range on emptier
      // rows.
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Drip & Co'), findsOneWidget);
      expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    });
  });

  testWidgets('Remove is not drawn identically to Edit', (tester) async {
    await pump(tester);
    await tapSection(tester, 'USER');

    // Read off the resolved RichText rather than the Text widget: a mono label
    // takes its ink from the AnimatedDefaultTextStyle above it, so the Text's own
    // style is null, and its semanticsLabel puts a Semantics render object in
    // between.
    Color? inkOf(String label) {
      final rich = find.descendant(
        of: find.text(label).first,
        matching: find.byType(RichText),
      );
      return tester.widget<RichText>(rich.first).text.style?.color;
    }

    expect(
      inkOf('REMOVE'),
      isNot(inkOf('EDIT')),
      reason: 'one opens a sheet, the other destroys a record with no undo',
    );
    expect(inkOf('REMOVE'), BrewColor.alert);
    // Edit is unchanged: it is the ordinary utility action.
    expect(inkOf('EDIT'), BrewColor.sageLight);
  });

  testWidgets(
      'View expands a customer card to show its uid, and Hide collapses it '
      'again', (tester) async {
    await pump(tester);
    await tapSection(tester, 'USER');

    expect(find.text('UID'), findsNothing);
    await tester.tap(find.text('VIEW'));
    await settle(tester);

    expect(find.text('UID'), findsOneWidget);
    expect(find.text('sam'), findsOneWidget);
    expect(find.text('JOINED'), findsOneWidget);
    expect(find.text('Mar 1, 2026'), findsOneWidget);
    expect(find.text('HIDE'), findsOneWidget);

    await tester.tap(find.text('HIDE'));
    await settle(tester);
    expect(find.text('UID'), findsNothing);
  });

  testWidgets('two accounts whose emails share a first letter get different marks',
      (tester) async {
    final db = await pump(tester);
    // The collision that made the mark useless on a real roster: both of these
    // drew a bare "Q". Both have to be customers to land in the roster at all.
    final users = db.collection('users');
    // A full overwrite, not an update: the mark prefers a name over the email
    // fallback, so Sam's has to go for his mark to come from the address at all.
    await users.doc('sam').set({
      'email': 'quickbrew@gmail.com',
      'role': 'customer',
    });
    await users.doc('quinn').set({
      'email': 'qldespino02@tip.edu.ph',
      'role': 'customer',
    });
    await tapSection(tester, 'USER');

    expect(find.text('QU'), findsOneWidget);
    expect(find.text('QL'), findsOneWidget);
    expect(find.text('Q'), findsNothing);
  });

  testWidgets('gives each shop a container saying who runs it', (tester) async {
    await pump(tester);
    await tapSection(tester, 'ADMIN');

    expect(tester.takeException(), isNull);
    expect(find.text('Drip & Co'), findsOneWidget);
    expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    // The staffing line is the point of the block: one shop has an admin and the
    // other has nobody, which is readable without going near the roster.
    expect(find.text('1 ADMIN'), findsOneWidget);
    expect(find.text('NO ADMIN ASSIGNED'), findsOneWidget);
    // Mia's name, in the container that holds her — the roster prints it inside
    // a longer line, so a bare 'Mia' is the container's row.
    expect(find.text('Mia'), findsOneWidget);
    expect(find.text('VIEW'), findsOneWidget);
    expect(find.text('EDIT'), findsOneWidget);
    expect(find.text('REMOVE'), findsOneWidget);
  });

  testWidgets(
      'View also expands an admin row inside its shop container', (tester) async {
    await pump(tester);
    await tapSection(tester, 'ADMIN');

    expect(find.text('UID'), findsNothing);
    await tester.tap(find.text('VIEW'));
    await settle(tester);

    expect(find.text('UID'), findsOneWidget);
    expect(find.text('mia'), findsOneWidget);
    expect(find.text('Feb 1, 2026'), findsOneWidget);
  });

  testWidgets(
      'Remove also takes an admin off their shop, not just the roster',
      (tester) async {
    final db = await pump(tester);
    await tapSection(tester, 'ADMIN');

    await tester.tap(find.text('REMOVE'));
    await settle(tester);
    await tester.tap(find.text('Remove record'));
    await settle(tester);

    expect(await read(db, 'mia'), isNull);
    // Both shops are unstaffed now, since Mia was the only admin.
    expect(find.text('NO ADMIN ASSIGNED'), findsNWidgets(2));
  });

  testWidgets(
      'leaves the super admin out of the roster entirely, not just out of the '
      'two shop containers', (tester) async {
    await pump(tester);
    await tapSection(tester, 'USER');

    // Not in either shop's container — that was already true — and now not in
    // the roster either, since the roster is customers only.
    expect(find.text('david@work.com'), findsNothing);
    expect(find.text('YOU'), findsNothing);
  });

  testWidgets(
      'every row in the roster keeps both mutating controls, since the reader '
      'is never among the customers listed', (tester) async {
    await pump(tester);
    await tapSection(tester, 'USER');

    expect(find.text('EDIT'), findsNWidgets(1));
    expect(find.text('REMOVE'), findsNWidgets(1));
  });

  testWidgets('the roster carries no filter and no invites list', (tester) async {
    await pump(tester);
    await tapSection(tester, 'USER');

    // Both were removed along with the old tab bar: there is one flat roster
    // now, narrowed by nothing.
    expect(find.text('EVERYONE'), findsNothing);
    expect(find.text('CUSTOMERS'), findsNothing);
    expect(find.text('Drip & Co'), findsNothing);
    expect(find.text('Seven Coffee & Tea'), findsNothing);
    expect(find.text('Pending invites'.toUpperCase()), findsNothing);
    expect(find.text('Nobody is waiting on an invite.'), findsNothing);
  });

  testWidgets('promoting a customer to admin writes the role and the store it '
      'was given', (tester) async {
    final db = await pump(tester);
    await tapSection(tester, 'USER');
    await openEditor(tester, sam);

    // Picking Admin is what reveals the store picker at all — until then the
    // sheet is not asking a question whose answer it would keep.
    final storeOption = inSheet(find.text('Seven Coffee & Tea'));
    expect(storeOption, findsNothing);
    await tester.tap(find.text('Admin'));
    await settle(tester);

    await tester.tap(storeOption);
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    final stored = await read(db, 'sam');
    expect(stored?['role'], 'admin');
    expect(stored?['assignedStore'], 'coffee-shop-b');
    // The write is a merge, not a set: the two fields this form never showed
    // have to survive it, and `email` in particular is the line the row is
    // titled by.
    expect(stored?['email'], 'sam@example.com');
    expect(stored?['createdAt'], isNotNull);
    expect(stored?['name'], 'Sam');
    // And the shop that had nobody now has him, without the reader going
    // anywhere near the container to say so.
    await tapSection(tester, 'ADMIN');
    expect(find.text('NO ADMIN ASSIGNED'), findsNothing);
    expect(find.text('1 ADMIN'), findsNWidgets(2));
  });

  testWidgets('demoting an admin takes their store away with the role',
      (tester) async {
    final db = await pump(tester);
    await tapSection(tester, 'ADMIN');
    await tester.tap(find.text('EDIT'));
    await settle(tester);

    await tester.tap(find.text('Customer'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    final stored = await read(db, 'mia');
    expect(stored?['role'], 'customer');
    expect(
      stored?['assignedStore'],
      isNull,
      reason: 'a store left on a demoted admin reads as a half-done demotion',
    );
  });

  testWidgets('a container\'s Edit opens the same editor the roster does, and '
      'the container follows the write', (tester) async {
    final db = await pump(tester);
    await tapSection(tester, 'ADMIN');

    await tester.tap(find.text('EDIT'));
    await settle(tester);
    expect(inSheet(find.text('Edit access.')), findsOneWidget);
    expect(inSheet(find.text('mia@work.com')), findsOneWidget);

    await tester.tap(find.text('Customer'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect((await read(db, 'mia'))?['role'], 'customer');
    // Both shops are unstaffed now, and neither container is still offering to
    // edit somebody who no longer runs one.
    expect(find.text('NO ADMIN ASSIGNED'), findsNWidgets(2));
    expect(find.text('EDIT'), findsNothing);
  });

  testWidgets('a shop with nobody assigned offers the form that staffs it, '
      'already set to that shop', (tester) async {
    await pump(tester);
    await tapSection(tester, 'ADMIN');

    await tester.tap(find.text('CREATE AN ADMIN'));
    await settle(tester);

    expect(find.text('Create an admin.'), findsOneWidget);
    expect(
      tester.widget<BrewChoice>(
        find.widgetWithText(BrewChoice, 'Seven Coffee & Tea'),
      ).selected,
      isTrue,
      reason: 'the reader chose the shop by pressing the button inside it; a '
          'form opening on the other one would quietly undo that',
    );
  });

  testWidgets('an emptied name is stored as absent rather than as a blank',
      (tester) async {
    final db = await pump(tester);
    await tapSection(tester, 'USER');
    await openEditor(tester, sam);

    await tester.enterText(find.byType(TextField), '');
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect((await read(db, 'sam'))?['name'], isNull);
  });

  testWidgets('removing a row deletes the record once it is confirmed',
      (tester) async {
    final db = await pump(tester);
    await tapSection(tester, 'USER');

    await tapRoster(tester, 'REMOVE', sam);
    await tester.tap(find.text('Remove record'));
    await settle(tester);

    expect(await read(db, 'sam'), isNull);
    expect(find.text('Sam'), findsNothing);
    // Sam was the only customer, so the roster falls back to its empty message.
    expect(find.text('No accounts yet.'), findsOneWidget);
  });

  testWidgets('backing out of a removal leaves the record alone', (tester) async {
    final db = await pump(tester);
    await tapSection(tester, 'USER');

    await tapRoster(tester, 'REMOVE', sam);
    await tester.tap(find.text('Keep it'));
    await settle(tester);

    expect((await read(db, 'sam'))?['role'], 'customer');
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('says what happened when a write is refused', (tester) async {
    // The admin layer being absent is the one failure this screen can be put in
    // without a live backend, and it is the same shape as a permission-denied:
    // the controls render, and nothing they do can land.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: UsersScreen(currentUid: dave)),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);

    await tapSection(tester, 'ADMIN');
    // Neither container claims a shop is unstaffed on the strength of a roster
    // it could not read.
    expect(find.text('NO ADMIN ASSIGNED'), findsNothing);
    expect(find.text('STAFFING UNAVAILABLE'), findsNWidgets(2));

    await tapSection(tester, 'USER');
    expect(find.text('Accounts are not connected in this build.'), findsOneWidget);
  });

  testWidgets('the User filter hides the shops and shows the roster',
      (tester) async {
    await pump(tester);
    await tapSection(tester, 'USER');

    expect(find.text('Drip & Co'), findsNothing);
    expect(find.text('Seven Coffee & Tea'), findsNothing);
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('switching back to Admin restores the containers and hides the '
      'roster again', (tester) async {
    await pump(tester);
    await tapSection(tester, 'USER');
    await tapSection(tester, 'ADMIN');

    expect(find.text('Drip & Co'), findsOneWidget);
    expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    expect(find.text('Sam'), findsNothing);
  });

  testWidgets('pressing the filter already showing does nothing', (tester) async {
    await pump(tester);
    await tapSection(tester, 'ADMIN');
    await tapSection(tester, 'ADMIN');

    expect(find.text('Drip & Co'), findsOneWidget);
    expect(find.text('Sam'), findsNothing);
  });
}
