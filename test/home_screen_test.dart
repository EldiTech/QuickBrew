import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_auth.dart';
import 'package:quick_brew/brew_counter.dart';
import 'package:quick_brew/screens/home_screen.dart';
import 'package:quick_brew/widgets/brew_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

const _dave = BrewSession(
  uid: 'dave',
  name: 'David Espino',
  email: 'david@work.com',
);

/// 9am, so the greeting under test is the one the brief writes out.
final _morning = DateTime(2026, 7, 25, 9);

void main() {
  setUpAll(loadBrandFonts);

  late FakeFirebaseFirestore db;
  late BrewCounter counter;
  late List<BrewShop> viewed;
  late List<BrewDraft> resumed;
  late List<BrewDraft> discarded;
  late int loggedOut;

  setUp(() {
    db = FakeFirebaseFirestore();
    counter = BrewCounter(db);
    viewed = [];
    resumed = [];
    discarded = [];
    loggedOut = 0;
    // A fresh device per test: nothing has been seen yet.
    SharedPreferences.setMockInitialValues(const {});
  });

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
    return db.collection('drafts').doc(_dave.uid).set({
      'shop': shop,
      'step': step,
      'lines': lines,
      'pickupName': 'David Espino',
      'pickupPhone': '09171234567',
      'pickupNote': '',
      'paymentMethod': 'Pay at counter',
      'savedAt': Timestamp.fromDate(_morning),
    });
  }

  Future<void> openShops({bool a = true, bool b = true}) async {
    await db.collection('shops').doc(BrewPartner.a.id).set({'open': a});
    await db.collection('shops').doc(BrewPartner.b.id).set({'open': b});
  }

  Future<DocumentReference<Map<String, dynamic>>> placeOrder({
    String stage = 'preparing',
    String shop = 'coffee-shop-a',
    List<String> items = const ['Iced Latte', 'Croissant'],
    int? etaLow = 10,
    int? etaHigh = 15,
  }) {
    return db.collection('orders').add({
      'uid': _dave.uid,
      'shop': shop,
      'items': items,
      'stage': stage,
      // Null-aware map entries, so passing no estimate leaves the fields off the
      // document rather than writing nulls into it.
      'etaLowMinutes': ?etaLow,
      'etaHighMinutes': ?etaHigh,
      'placedAt': Timestamp.fromDate(_morning),
    });
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    DateTime? now,
    BrewSession session = _dave,
    bool firestore = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          session: session,
          counter: firestore ? counter : null,
          now: now ?? _morning,
          onViewMenu: viewed.add,
          onResumeDraft: resumed.add,
          onDiscardDraft: discarded.add,
          onSignOut: () => loggedOut++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the greeting', () {
    testWidgets('names the reader, once, and asks the one question', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('Good morning, David!'), findsOneWidget);
      expect(find.text('What would you like today?'), findsOneWidget);
      // A first name, not a form letter.
      expect(find.textContaining('Espino'), findsNothing);
    });

    testWidgets('follows the clock rather than always saying morning', (
      tester,
    ) async {
      await pumpHome(tester, now: DateTime(2026, 7, 25, 14));
      expect(find.text('Good afternoon, David!'), findsOneWidget);

      await pumpHome(tester, now: DateTime(2026, 7, 25, 21));
      expect(find.text('Good evening, David!'), findsOneWidget);

      await pumpHome(tester, now: DateTime(2026, 7, 25, 3));
      expect(
        find.text('Good evening, David!'),
        findsOneWidget,
        reason: 'three in the morning is not the morning',
      );
    });

    testWidgets('drops the address entirely when there is no name', (
      tester,
    ) async {
      await pumpHome(
        tester,
        session: const BrewSession(uid: 'dave', email: 'david@work.com'),
      );

      expect(find.text('Good morning!'), findsOneWidget);
      expect(find.textContaining('there'), findsNothing);
    });

    testWidgets('carries the two header actions and no wordmark', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.byType(BrewIconMark), findsNWidgets(2));
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
      expect(find.bySemanticsLabel('Your profile'), findsOneWidget);
      expect(
        find.text('QuickBrew'),
        findsNothing,
        reason: 'the greeting is this screen\'s masthead',
      );
    });
  });

  group('choosing a coffee shop', () {
    testWidgets('shows both partners with equal billing', (tester) async {
      await openShops();
      await pumpHome(tester);

      expect(find.text('CHOOSE A COFFEE SHOP'), findsOneWidget);
      expect(find.text('Drip & Co'), findsOneWidget);
      expect(find.text('Seven Coffee & Tea'), findsOneWidget);
      expect(
        find.text('Vietnamese style coffee'),
        findsOneWidget,
      );
      expect(
        find.text('Handcrafted coffee, tea and signature drinks'),
        findsOneWidget,
      );
      expect(find.text('View menu →'), findsNWidgets(2));
      expect(find.text('OPEN'), findsNWidgets(2));

      // Equal billing is a measurement, not an intention: same width, same
      // height, same left edge.
      // Keyed on each shop's own name rather than a shared prefix: the two
      // built-in names have nothing in common to match on, and pinning the
      // finder to one would make this pass while only half the cards exist.
      final cards = tester
          .widgetList<Semantics>(find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                BrewPartner.values.any(
                  (partner) =>
                      widget.properties.label?.startsWith(partner.name) ??
                      false,
                ),
          ))
          .toList();
      expect(cards, hasLength(2));

      final rects = [
        for (final label in ['Drip & Co', 'Seven Coffee & Tea'])
          tester.getRect(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          ),
      ];
      expect(rects[0].size, rects[1].size);
      expect(rects[0].left, 24, reason: 'the 24px gutter');
      expect(rects[1].left, 24);
      expect(rects[0].width, 390 - 48);
    });

    testWidgets('reports closed without dressing it as an error', (
      tester,
    ) async {
      await openShops(a: true, b: false);
      await pumpHome(tester);

      expect(find.text('OPEN'), findsOneWidget);
      expect(find.text('CLOSED'), findsOneWidget);
    });

    testWidgets('says the hours are unavailable rather than guessing', (
      tester,
    ) async {
      // Nothing seeded: no shops collection at all.
      await pumpHome(tester);

      expect(find.text('HOURS UNAVAILABLE'), findsNWidgets(2));
      expect(
        find.text('CLOSED'),
        findsNothing,
        reason: 'a missing document must never read as closed',
      );
    });

    testWidgets('still shows both shops with no Firestore at all', (
      tester,
    ) async {
      await pumpHome(tester, firestore: false);

      expect(find.text('Drip & Co'), findsOneWidget);
      expect(find.text('Seven Coffee & Tea'), findsOneWidget);
      // Not "Checking hours": nothing is being checked, so saying so would be a
      // spinner written out in words.
      expect(find.text('HOURS UNAVAILABLE'), findsNWidgets(2));
      expect(find.text('View menu →'), findsNWidgets(2));
    });

    testWidgets('a shop closing arrives without a reload', (tester) async {
      await openShops();
      await pumpHome(tester);
      expect(find.text('OPEN'), findsNWidgets(2));

      await db
          .collection('shops')
          .doc(BrewPartner.b.id)
          .update({'open': false});
      await tester.pumpAndSettle();

      expect(find.text('OPEN'), findsOneWidget);
      expect(find.text('CLOSED'), findsOneWidget);
    });

    testWidgets('the whole block is the tap target, not just the label', (
      tester,
    ) async {
      await openShops();
      await pumpHome(tester);

      // The card's top-left corner: inside the block, nowhere near any label.
      final card = tester.getRect(
        find
            .ancestor(
              of: find.text('Drip & Co'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      await tester.tapAt(Offset(card.left + 6, card.top + 6));
      await tester.pumpAndSettle();

      expect(viewed.map((shop) => shop.partner), [BrewPartner.a]);
    });

    testWidgets('a closed shop\'s menu can still be opened', (tester) async {
      await openShops(a: false, b: false);
      await pumpHome(tester);

      await tester.tap(find.text('Seven Coffee & Tea'));
      await tester.pumpAndSettle();

      expect(viewed.single.partner, BrewPartner.b);
      expect(viewed.single.status, BrewShopStatus.closed);
    });

    testWidgets('each card is one announcement, not four loose labels', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openShops(a: true, b: false);
      await pumpHome(tester);

      expect(
        find.bySemanticsLabel(
          'Drip & Co. Vietnamese style coffee. Open. '
          'View menu.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Seven Coffee & Tea. Handcrafted coffee, tea and signature drinks. Closed. '
          'View menu.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the active order', () {
    testWidgets('is not there at all when there is no order', (tester) async {
      await openShops();
      await pumpHome(tester);

      expect(find.text('ACTIVE ORDER'), findsNothing);
      expect(find.textContaining('No active'), findsNothing);
      expect(find.textContaining('Track order'), findsNothing);
    });

    testWidgets('sits above the shop selection when there is one', (
      tester,
    ) async {
      await openShops();
      await placeOrder();
      await pumpHome(tester);

      expect(find.text('ACTIVE ORDER'), findsOneWidget);
      // One row per drink, not the joined line the Orders tab prints.
      expect(find.text('Iced Latte'), findsOneWidget);
      expect(find.text('Croissant'), findsOneWidget);
      expect(find.text('PREPARING'), findsOneWidget);
      expect(find.text('ESTIMATED TIME'), findsOneWidget);
      expect(find.text('10–15 min'), findsOneWidget);
      expect(find.text('Track order'), findsOneWidget);

      expect(
        tester.getTopLeft(find.text('ACTIVE ORDER')).dy,
        lessThan(tester.getTopLeft(find.text('CHOOSE A COFFEE SHOP')).dy),
        reason: 'an order already being made outranks picking a shop',
      );
    });

    testWidgets('names the shop the order is with', (tester) async {
      await placeOrder(shop: 'coffee-shop-b');
      await pumpHome(tester);

      // Once on the order card and once on the shop card below it.
      expect(find.text('Seven Coffee & Tea'), findsNWidgets(2));
    });

    testWidgets('moves through the four stages as the counter says so', (
      tester,
    ) async {
      await placeOrder(stage: 'received');
      await pumpHome(tester);
      // The pill, which is uppercase; the track under it names all four stages
      // in sentence case whatever the order is doing, so it is the pill that
      // says where this one has got to.
      expect(find.text('RECEIVED'), findsOneWidget);

      final order = (await db.collection('orders').get()).docs.single.reference;

      await order.update({'stage': 'preparing'});
      await tester.pumpAndSettle();
      expect(find.text('PREPARING'), findsOneWidget);

      await order.update({'stage': 'ready'});
      await tester.pumpAndSettle();
      expect(find.text('READY'), findsOneWidget);

      // Completed is history, so the card leaves the home screen.
      await order.update({'stage': 'completed'});
      await tester.pumpAndSettle();
      expect(find.text('ACTIVE ORDER'), findsNothing);
      expect(find.text('PICKED UP'), findsNothing);
    });

    testWidgets('names all four stages, not only the one reached', (
      tester,
    ) async {
      await placeOrder(stage: 'received');
      await pumpHome(tester);

      for (final stage in ['Received', 'Preparing', 'Ready', 'Picked up']) {
        expect(find.text(stage), findsOneWidget, reason: 'the track is a map');
      }
    });

    testWidgets('carries a reference the reader can quote at the counter', (
      tester,
    ) async {
      await placeOrder(shop: 'coffee-shop-b');
      await pumpHome(tester);

      final id = (await db.collection('orders').get()).docs.single.id;
      final tail = id.toUpperCase();
      expect(
        find.text('ORDER #SCT-${tail.substring(tail.length - 4)}'),
        findsOneWidget,
      );
    });

    testWidgets('splits a drink from what was done to it', (tester) async {
      await placeOrder(
        items: const ['2× Iced Latte (Large) + Extra shot, Oat milk'],
      );
      await pumpHome(tester);

      expect(find.text('2× Iced Latte (Large)'), findsOneWidget);
      expect(find.text('Extra shot · Oat milk'), findsOneWidget);
    });

    testWidgets('counts the drinks it has no room to list', (tester) async {
      await placeOrder(
        items: const ['Espresso', 'Latte', 'Mocha', 'Cortado', 'Tea'],
      );
      await pumpHome(tester);

      expect(find.text('Espresso'), findsOneWidget);
      expect(find.text('Mocha'), findsOneWidget);
      expect(find.text('Cortado'), findsNothing);
      expect(find.text('+ 2 more items'), findsOneWidget);
    });

    testWidgets('says when the pickup is rather than only what time', (
      tester,
    ) async {
      final at = DateTime(2026, 7, 25, 17, 45);
      final order = await placeOrder();
      await order.update({'scheduledFor': Timestamp.fromDate(at)});
      await pumpHome(tester, now: _morning);

      expect(find.text('PICKUP'), findsOneWidget);
      expect(find.text('Today · 5:45 PM'), findsOneWidget);
      expect(find.text('25 Jul 2026'), findsOneWidget);
    });

    testWidgets('an order for now is a real answer, not a missing one', (
      tester,
    ) async {
      await placeOrder();
      await pumpHome(tester);

      expect(find.text('As soon as ready'), findsOneWidget);
    });

    testWidgets('omits the estimate rather than inventing one', (tester) async {
      await placeOrder(etaLow: null, etaHigh: null);
      await pumpHome(tester);

      expect(find.text('PREPARING'), findsOneWidget);
      expect(find.textContaining('ESTIMATED TIME'), findsNothing);
      // The pickup column keeps the full width rather than leaving a gap where
      // the estimate would have been.
      expect(find.text('PICKUP'), findsOneWidget);
    });

    testWidgets('Track order opens the order\'s own screen', (tester) async {
      await placeOrder(shop: 'coffee-shop-b');
      await pumpHome(tester);

      await tester.tap(find.text('Track order'));
      await tester.pumpAndSettle();

      expect(find.text('Tracking your order.'), findsOneWidget);
      // Every drink gets its own row here rather than the joined line.
      expect(find.text('Iced Latte'), findsOneWidget);
      expect(find.text('Croissant'), findsOneWidget);
      // Named once in this screen's own summary and not a second time behind
      // it — Home is not still visible underneath a route that was pushed.
      expect(find.text('Seven Coffee & Tea'), findsOneWidget);
    });

    testWidgets('Track order carries the order straight through, live', (
      tester,
    ) async {
      await placeOrder(stage: 'preparing');
      await pumpHome(tester);

      await tester.tap(find.text('Track order'));
      await tester.pumpAndSettle();
      expect(find.text('PREPARING'), findsOneWidget);

      final doc = (await db.collection('orders').get()).docs.single.reference;
      await doc.update({'stage': 'ready'});
      await tester.pumpAndSettle();

      // The stage moved without the reader having to leave this screen and
      // come back — the same subscription the home card reads from.
      expect(find.text('READY'), findsOneWidget);
    });
  });

  group('the navigation', () {
    testWidgets('is three items, and no coffee shop is one of them', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('ORDERS'), findsOneWidget);
      expect(find.text('PROFILE'), findsOneWidget);
      expect(find.text('CART'), findsNothing);
      // The two shops are a choice on the screen, never a place to live. Read
      // off the tabs themselves rather than asserting a shop's name is absent
      // from the page — both names are on it, on the cards this very screen
      // exists to offer.
      expect(
        BrewTab.values.map((tab) => tab.label),
        isNot(anyElement(isIn(BrewPartner.values.map((p) => p.name)))),
      );
    });

    testWidgets('stays on screen at the bottom of a long page', (tester) async {
      await openShops();
      await placeOrder();
      // Short viewport with a large text scale: the page is well past one screen.
      await pumpHome(tester, size: const Size(375, 667));

      final nav = tester.getRect(find.text('HOME'));
      expect(nav.bottom, lessThanOrEqualTo(667));

      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.text('HOME')),
        nav,
        reason: 'the nav is outside the scroll view',
      );
    });

    testWidgets('switches panels and reports which one is current', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);
      expect(find.bySemanticsLabel('Home, current tab'), findsOneWidget);

      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();
      expect(find.text('Your account.'), findsOneWidget);
      expect(find.text('david@work.com'), findsOneWidget);
      expect(find.bySemanticsLabel('Profile, current tab'), findsOneWidget);

      await tester.tap(find.text('HOME'));
      await tester.pumpAndSettle();
      expect(find.text('Good morning, David!'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the header profile mark lands on the same tab', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.bySemanticsLabel('Your profile'));
      await tester.pumpAndSettle();

      expect(find.text('Your account.'), findsOneWidget);
    });

    testWidgets('Log out reports out, and does not navigate itself', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.text('PROFILE'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(loggedOut, 1);
      // The session going is what moves the reader — see main.dart.
      expect(find.text('Your account.'), findsOneWidget);
    });

    testWidgets('the bell opens notices, which highlight no tab', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);

      await tester.tap(find.bySemanticsLabel('Notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Notifications.'), findsOneWidget);
      expect(find.bySemanticsLabel('Home, current tab'), findsNothing);

      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.text('Good morning, David!'), findsOneWidget);
      handle.dispose();
    });

    /// The panel used to sit on "Looking up your orders…" with nothing ever
    /// arriving whenever the read could not answer — [BrewCounter.orders]
    /// logged the error and swallowed it, leaving a stream that neither emits
    /// nor closes. The same swallow that stranded the menu board.
    testWidgets(
      'notices that cannot be read say so rather than spinning forever',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpHome(tester, firestore: false);

        await tester.tap(find.bySemanticsLabel('Notifications'));
        await tester.pumpAndSettle();

        expect(
          find.text('Looking up your orders…'),
          findsNothing,
          reason: 'nothing is coming, so this would never resolve',
        );
        expect(
          find.textContaining('Could not load your orders'),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('an empty orders list says so rather than showing nothing', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.text('ORDERS'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing yet'), findsOneWidget);
    });

    testWidgets(
      'a completed, ready, or rejected order notifies on the notices panel',
      (tester) async {
        await placeOrder(stage: 'ready', items: ['Iced Latte']);
        await placeOrder(stage: 'completed', items: ['Hot Americano']);
        await placeOrder(
          stage: 'rejected',
          items: ['Cold Brew'],
        );
        await pumpHome(tester);

        // The label now carries the unseen count, so it is matched by prefix.
        await tester.tap(find.bySemanticsLabel(RegExp('^Notifications')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Iced Latte'),
          findsOneWidget,
          reason: 'ready is a notice, not only a live tracking state',
        );
        expect(find.textContaining('Hot Americano'), findsOneWidget);
        expect(find.textContaining('Cold Brew'), findsOneWidget);
        expect(
          find.textContaining('Nothing yet'),
          findsNothing,
          reason: 'the empty-state copy should not show once there is one',
        );
      },
    );

    testWidgets(
      'an order still in progress is not a notice',
      (tester) async {
        await placeOrder(stage: 'preparing', items: ['Iced Latte']);
        await pumpHome(tester);

        await tester.tap(find.bySemanticsLabel('Notifications'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Iced Latte'),
          findsNothing,
          reason: 'an active order is still the tracking card\'s to show',
        );
        expect(find.textContaining('Nothing yet'), findsOneWidget);
      },
    );

    testWidgets(
      "a rejected order's reason is folded onto its notice",
      (tester) async {
        await db.collection('orders').add({
          'uid': _dave.uid,
          'shop': 'coffee-shop-a',
          'items': ['Cold Brew'],
          'stage': 'rejected',
          'rejectionReason': 'Out of cold brew today.',
          'placedAt': Timestamp.fromDate(_morning),
        });
        await pumpHome(tester);

        await tester.tap(find.bySemanticsLabel(RegExp('^Notifications')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Out of cold brew today.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the bell counts the notices the reader has not seen', (
      tester,
    ) async {
      await placeOrder(stage: 'ready', items: ['Iced Latte']);
      await placeOrder(stage: 'completed', items: ['Hot Americano']);
      await placeOrder(stage: 'preparing', items: ['Cold Brew']);
      await pumpHome(tester);

      // Two notices, not three — preparing is the tracking card's business.
      expect(
        find.bySemanticsLabel('Notifications, 2 new'),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('opening the bell clears the badge', (tester) async {
      await placeOrder(stage: 'ready', items: ['Iced Latte']);
      await pumpHome(tester);

      expect(find.bySemanticsLabel('Notifications, 1 new'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp('^Notifications')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();

      // Seen, so no longer counted — and the plain label is back.
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications, 1 new'), findsNothing);
    });

    testWidgets('a seen order that moves stage badges again', (tester) async {
      final doc = await db.collection('orders').add({
        'uid': _dave.uid,
        'shop': 'coffee-shop-a',
        'items': ['Iced Latte'],
        'stage': 'ready',
        'placedAt': Timestamp.fromDate(_morning),
      });
      await pumpHome(tester);

      await tester.tap(find.bySemanticsLabel(RegExp('^Notifications')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);

      // The same order completing is a new fact the reader has not seen,
      // even though the order itself has been on the panel before.
      await doc.update({'stage': 'completed'});
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Notifications, 1 new'), findsOneWidget);
    });
  });

  group('what is deliberately absent', () {
    testWidgets('none of the things the brief rules out', (tester) async {
      await openShops();
      await placeOrder();
      await pumpHome(tester);

      const banned = <String>[
        'Reward',
        'Promo',
        'Nearby',
        'Recent',
        'Recommend',
        'Favourite',
        'Favorite',
        'Reorder',
        'Deal',
        'Loyalty',
        'Points',
        'Offer',
      ];
      for (final word in banned) {
        expect(
          find.textContaining(word, findRichText: true),
          findsNothing,
          reason: '$word has no business on this screen',
        );
      }
    });

    testWidgets('holds up without overflowing at 200% text', (tester) async {
      await openShops();
      await placeOrder();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            // The landing screen clamps the scaler because it must not scroll.
            // This one scrolls, so it takes whatever the reader has set.
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: HomeScreen(
              session: _dave,
              counter: counter,
              now: _morning,
              onViewMenu: viewed.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HOME'), findsOneWidget, reason: 'nav still reachable');
    });
  });

  group('the saved order', () {
    testWidgets('does not draw on Home at all', (tester) async {
      await openShops();
      await saveDraft();
      await pumpHome(tester);

      // The draft moved to the Orders tab's Saved filter — see
      // orders_panel_test.dart. Home has nothing to say about it any more.
      expect(find.text('SAVED ORDER'), findsNothing);
      expect(find.text('CHOOSE A COFFEE SHOP'), findsOneWidget);
    });

    testWidgets('the callbacks still reach main.dart through Orders', (
      tester,
    ) async {
      await openShops();
      await saveDraft(step: 'payment');
      await pumpHome(tester);

      await tester.tap(find.text('ORDERS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAVED'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RESUME ORDER →'));
      await tester.pumpAndSettle();

      // HomeScreen only has to hand its onResumeDraft/onDiscardDraft through to
      // OrdersPanel intact — the button's own behaviour is
      // orders_panel_test.dart's job to cover.
      expect(resumed, hasLength(1));
      expect(resumed.single.step, 'payment');
    });
  });
}
