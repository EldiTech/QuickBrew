import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/orders_panel.dart';
import 'package:quick_brew/widgets/stagger.dart';

import 'support/fonts.dart';

/// The Orders tab on its own.
///
/// home_screen_test.dart already reaches this through the nav, which is how a
/// reader gets here. These are the cases that are awkward from there: a history
/// long enough to scroll, a stage column with finished and live orders side by
/// side, and the two absent states.
void main() {
  setUpAll(loadBrandFonts);

  late FakeFirebaseFirestore db;
  late BrewCounter counter;

  setUp(() {
    db = FakeFirebaseFirestore();
    counter = BrewCounter(db);
  });

  Future<void> place(
    String id, {
    String stage = 'preparing',
    String shop = 'coffee-shop-a',
    List<String> items = const ['Iced Latte'],
    required int hour,
  }) {
    return db.collection('orders').doc(id).set({
      'uid': 'dave',
      'shop': shop,
      'items': items,
      'stage': stage,
      'placedAt': Timestamp.fromDate(DateTime(2026, 7, 25, hour)),
    });
  }

  /// Parks an unfinished order for the reader under test.
  ///
  /// Written straight to Firestore rather than through [BrewCounter.saveDraft],
  /// so these tests cover what the card does with a document rather than
  /// re-covering the wizard's write — which
  /// [order_wizard_screen_test.dart](order_wizard_screen_test.dart) already does.
  Future<void> saveDraft({
    String shop = 'coffee-shop-a',
    String step = 'pickup',
    List<Map<String, Object?>> lines = const [
      {
        'itemId': 'latte',
        'size': 'medium',
        'extraIds': <String>[],
        'quantity': 1,
        'unitCents': 8000,
      },
    ],
  }) {
    return db.collection('drafts').doc('dave').set({
      'shop': shop,
      'step': step,
      'lines': lines,
      'pickupName': 'David Espino',
      'pickupPhone': '09171234567',
      'pickupNote': '',
      'paymentMethod': 'Pay at counter',
      'savedAt': Timestamp.fromDate(DateTime(2026, 7, 25, 9)),
    });
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    bool firestore = true,
    Size size = const Size(390, 844),
    bool withDraft = false,
    List<BrewDraft> resumed = const [],
    List<BrewDraft> discarded = const [],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF2A3D28),
          body: OrdersPanel(
            compact: size.height <= 667,
            orders: firestore ? counter.orders('dave') : null,
            draft: withDraft ? counter.draft('dave') : null,
            onResumeDraft: resumed.add,
            onDiscardDraft: discarded.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reports nothing known yet rather than an empty history', (
    tester,
  ) async {
    await pumpPanel(tester, firestore: false);

    expect(find.text('Looking up your orders…'), findsOneWidget);
    expect(
      find.textContaining('Nothing yet'),
      findsNothing,
      reason: 'no history and an unknown history are different claims',
    );
  });

  testWidgets('an account with no orders is told where they will appear', (
    tester,
  ) async {
    await pumpPanel(tester);

    expect(find.textContaining('Nothing yet'), findsOneWidget);
    expect(find.textContaining('Pick a shop on Home'), findsOneWidget);
  });

  testWidgets('lists newest first, whatever order the documents arrive in', (
    tester,
  ) async {
    await place('oldest', items: const ['Filter'], hour: 8, stage: 'completed');
    await place('newest', items: const ['Cortado'], hour: 11);
    await place('middle', items: const ['Bun'], hour: 9, stage: 'completed');
    await pumpPanel(tester);

    final tops = {
      for (final item in ['Cortado', 'Bun', 'Filter'])
        item: tester.getTopLeft(find.text(item)).dy,
    };
    expect(tops['Cortado']!, lessThan(tops['Bun']!));
    expect(tops['Bun']!, lessThan(tops['Filter']!));
  });

  testWidgets('holds a finished order back and keeps a live one in full ink', (
    tester,
  ) async {
    await place('live', items: const ['Cortado'], hour: 11, stage: 'ready');
    await place('done', items: const ['Bun'], hour: 9, stage: 'completed');
    await pumpPanel(tester);

    // The stage name, not its sentence: this is a column to scan down.
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('Ready for pickup'), findsNothing);

    final live = tester.widget<Text>(find.text('READY')).style!.color;
    final done = tester.widget<Text>(find.text('COMPLETED')).style!.color;
    expect(
      done!.a,
      lessThan(live!.a),
      reason: 'history is held back so the live orders read first',
    );
  });

  testWidgets('names both partners and does not confuse them', (tester) async {
    await place('a', shop: 'coffee-shop-a', items: const ['Cortado'], hour: 11);
    await place('b', shop: 'coffee-shop-b', items: const ['Bun'], hour: 10);
    await pumpPanel(tester);

    expect(find.text('Drip & Co'), findsOneWidget);
    expect(find.text('Seven Coffee & Tea'), findsOneWidget);
  });

  testWidgets('a long history scrolls rather than overflowing', (tester) async {
    for (var hour = 0; hour < 20; hour++) {
      await place('order-$hour', items: ['Cup $hour'], hour: hour);
    }
    await pumpPanel(tester, size: const Size(375, 667));

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  /// The stagger timeline, across every shape this screen's one optional block
  /// takes.
  ///
  /// [StaggerGroup] sizes its ramp from `staggerCount`, and a [StaggerItem]
  /// handed an index past the end of that ramp asserts inside [Interval] rather
  /// than merely animating oddly. The count and the indices are two expressions
  /// that have to agree about how many rows there are, and the history is null,
  /// empty, or any length — so a test that only pumped one of those three would
  /// prove nothing about the other two. Each case below pumps and asserts no
  /// exception, which is the whole of what the assert would announce.
  ///
  /// The check reads the largest index actually dealt off the tree and compares
  /// it to the group's own count rather than waiting for a throw. Waiting is not
  /// enough on its own here: rows that arrive on a later snapshot mount into a
  /// controller already past their cue and take [StaggerItem]'s `_late` ramp,
  /// which never constructs the [Interval] whose `end <= 1.0` is the assertion.
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

    expect(indices, isNotEmpty, reason: 'the masthead and headline always sit');
    expect(
      indices.reduce((a, b) => a > b ? a : b),
      lessThan(group.itemCount),
      reason: 'an index at or past itemCount falls off the end of the timeline',
    );
  }

  group('stagger timeline', () {
    testWidgets('an unknown history', (tester) async {
      await pumpPanel(tester, firestore: false);
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a known-empty history', (tester) async {
      await pumpPanel(tester);
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a single row', (tester) async {
      await place('only', items: const ['Cortado'], hour: 11);
      await pumpPanel(tester);
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Cortado'), findsOneWidget);
    });

    testWidgets('a history longer than the two fixed rows above it', (
      tester,
    ) async {
      for (var hour = 0; hour < 6; hour++) {
        await place('order-$hour', items: ['Cup $hour'], hour: hour);
      }
      await pumpPanel(tester);
      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Cup 5'), findsOneWidget);
    });

    testWidgets('a history that grows while the screen is on it', (
      tester,
    ) async {
      await place('first', items: const ['Cortado'], hour: 8);
      await pumpPanel(tester);

      // The counter is dealt inside the StreamBuilder, so a second snapshot
      // re-runs the allocation from zero. A counter closed over from outside
      // would carry the first run's total forward and hand the new row an index
      // past the end of the ramp — the failure admin_home_screen.dart documents
      // having hit twice.
      await place('second', items: const ['Bun'], hour: 9);
      await tester.pumpAndSettle();

      expectIndicesInsideCount(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Bun'), findsOneWidget);
      expect(find.text('Cortado'), findsOneWidget);
    });
  });

  testWidgets('a document the app cannot read costs that row and no other', (
    tester,
  ) async {
    await place('good', items: const ['Cortado'], hour: 11);
    await db.collection('orders').doc('bad').set({
      'uid': 'dave',
      'shop': 'coffee-shop-a',
      'items': <String>[],
      'stage': 'levitating',
    });
    await pumpPanel(tester);

    expect(find.text('Cortado'), findsOneWidget);
    expect(find.textContaining('Nothing yet'), findsNothing);
  });

  group('the filter', () {
    testWidgets('opens on Orders, not Saved', (tester) async {
      await place('only', items: const ['Cortado'], hour: 11);
      await pumpPanel(tester, withDraft: true);

      expect(find.text('Cortado'), findsOneWidget);
      expect(find.text('SAVED · PICK UP WHERE YOU LEFT OFF'), findsNothing);
    });

    testWidgets('Saved hides the placed history and shows the draft', (
      tester,
    ) async {
      await place('placed', items: const ['Cortado'], hour: 11);
      await saveDraft();
      await pumpPanel(tester, withDraft: true);

      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();

      expect(find.text('Cortado'), findsNothing);
      expect(find.textContaining('1 drink, not yet ordered'), findsOneWidget);
    });

    testWidgets('switching back to Orders restores the placed history', (
      tester,
    ) async {
      await place('placed', items: const ['Cortado'], hour: 11);
      await saveDraft();
      await pumpPanel(tester, withDraft: true);

      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ORDERS'));
      await tester.pumpAndSettle();

      expect(find.text('Cortado'), findsOneWidget);
      expect(find.textContaining('1 drink, not yet ordered'), findsNothing);
    });

    testWidgets('Saved with nothing parked says so rather than showing '
        'nothing', (tester) async {
      await pumpPanel(tester, withDraft: true);

      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing saved'), findsOneWidget);
    });
  });

  group('the saved order card', () {
    testWidgets('names the shop and how much is in it', (tester) async {
      await saveDraft();
      await pumpPanel(tester, withDraft: true);
      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 drink, not yet ordered'), findsOneWidget);
      expect(find.text('RESUME ORDER →'), findsOneWidget);
      expect(find.text('Discard order'), findsOneWidget);
    });

    testWidgets('counts quantities rather than lines', (tester) async {
      await saveDraft(
        lines: const [
          {
            'itemId': 'latte',
            'size': 'medium',
            'extraIds': <String>[],
            'quantity': 2,
            'unitCents': 8000,
          },
          {
            'itemId': 'bun',
            'size': null,
            'extraIds': <String>[],
            'quantity': 1,
            'unitCents': 2500,
          },
        ],
      );
      await pumpPanel(tester, withDraft: true);
      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();

      // Three drinks across two lines. The reader is being told how much coffee
      // is parked, not how many rows the cart happens to have.
      expect(find.textContaining('3 drinks, not yet ordered'), findsOneWidget);
    });

    testWidgets('draws no progress rule, unlike a placed order', (
      tester,
    ) async {
      await saveDraft();
      await pumpPanel(tester, withDraft: true);
      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();

      // A segmented rule with nothing inked would read as an order stuck at the
      // first stage. This order has not started at all.
      expect(find.textContaining('ESTIMATED TIME'), findsNothing);
      expect(find.textContaining('SAVED ·'), findsOneWidget);
    });

    testWidgets('Resume hands the whole draft back', (tester) async {
      await saveDraft(step: 'payment');
      final resumed = <BrewDraft>[];
      await pumpPanel(tester, withDraft: true, resumed: resumed);
      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('RESUME ORDER →'));
      await tester.pumpAndSettle();

      expect(resumed, hasLength(1));
      // The step travels with it, which is the whole point — the reader is put
      // back where they left rather than at the top of the flow.
      expect(resumed.single.step, 'payment');
      expect(resumed.single.partner, BrewPartner.a);
      expect(resumed.single.pickupPhone, '09171234567');
    });

    testWidgets('Discard is reported separately from Resume', (tester) async {
      await saveDraft();
      final resumed = <BrewDraft>[];
      final discarded = <BrewDraft>[];
      await pumpPanel(
        tester,
        withDraft: true,
        resumed: resumed,
        discarded: discarded,
      );
      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard order'));
      await tester.pumpAndSettle();

      // The two controls are not the same press. A card whose Discard could be
      // hit while aiming for Resume would be a card that throws away an order
      // the reader was trying to finish.
      expect(discarded, hasLength(1));
      expect(resumed, isEmpty);
    });

    testWidgets('goes when the draft does', (tester) async {
      await saveDraft();
      await pumpPanel(tester, withDraft: true);
      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();
      expect(find.text('RESUME ORDER →'), findsOneWidget);

      await db.collection('drafts').doc('dave').delete();
      await tester.pumpAndSettle();

      // The card follows the document rather than a snapshot taken at mount:
      // the reader resumes the order, finishes it, and walks back onto this
      // tab, which must not still be offering to resume it.
      expect(find.text('RESUME ORDER →'), findsNothing);
      expect(find.textContaining('Nothing saved'), findsOneWidget);
    });

    testWidgets('a draft naming a shop this build does not know draws '
        'nothing', (tester) async {
      await saveDraft(shop: 'coffee-shop-z');
      await pumpPanel(tester, withDraft: true);
      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();

      // There is no third partner and nothing to resume into. [BrewDraft.read]
      // returns null for an unrecognised shop, so the stream never hands this
      // panel a draft to build a card from.
      expect(find.text('RESUME ORDER →'), findsNothing);
      expect(find.textContaining('Nothing saved'), findsOneWidget);
    });

    testWidgets('a draft with no readable lines draws nothing', (tester) async {
      await saveDraft(lines: const [{'quantity': 2}]);
      await pumpPanel(tester, withDraft: true);
      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();

      // A line with no item id cannot be rebuilt, and a draft of nothing but
      // those is not an order — see [BrewDraft.read].
      expect(find.text('RESUME ORDER →'), findsNothing);
      expect(find.textContaining('Nothing saved'), findsOneWidget);
    });
  });
}
