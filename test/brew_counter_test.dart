import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/brew_counter.dart';

/// The layer between Firestore and the screens.
///
/// Worth testing against a real `FirebaseFirestore` surface rather than a
/// hand-rolled fake stream, because most of what can go wrong here is in the
/// query and the mapping — a shop document that is missing, an order whose stage
/// is a string nobody recognises, a menu item with no `sort`. A fake that returned
/// tidy objects would test none of it.
void main() {
  late FakeFirebaseFirestore db;
  late BrewCounter counter;

  setUp(() {
    db = FakeFirebaseFirestore();
    counter = BrewCounter(db);
  });

  group('shops', () {
    test('is always both partners, in a fixed order, whatever is stored', () async {
      // Nothing seeded at all.
      expect(
        await counter.shops().first,
        isA<List<BrewShop>>()
            .having((s) => s.length, 'length', 2)
            .having((s) => s[0].partner, 'first', BrewPartner.a)
            .having((s) => s[1].partner, 'second', BrewPartner.b),
      );

      // And a collection that has picked up something else entirely still yields
      // exactly the two, still in this order.
      await db.collection('shops').doc('some-other-cafe').set({'open': true});
      final shops = await counter.shops().first;
      expect(shops.map((shop) => shop.partner), [
        BrewPartner.a,
        BrewPartner.b,
      ]);
    });

    test('only a stored false reads as closed', () async {
      await db.collection('shops').doc('coffee-shop-a').set({'open': true});
      await db.collection('shops').doc('coffee-shop-b').set({'open': false});

      final shops = await counter.shops().first;
      expect(shops[0].status, BrewShopStatus.open);
      expect(shops[1].status, BrewShopStatus.closed);
    });

    test('a missing document is unknown, never closed', () async {
      // Present but silent about hours, which is the same as absent from here.
      await db.collection('shops').doc('coffee-shop-a').set({'name': 'A'});

      final shops = await counter.shops().first;
      expect(shops[0].status, BrewShopStatus.unknown);
      expect(shops[1].status, BrewShopStatus.unknown);
    });

    test('an empty or blank logo url is no logo', () async {
      await db.collection('shops').doc('coffee-shop-a').set({
        'open': true,
        'logoUrl': '   ',
      });
      await db.collection('shops').doc('coffee-shop-b').set({
        'open': true,
        'logoUrl': ' https://example.test/b.png ',
      });

      final shops = await counter.shops().first;
      expect(shops[0].logoUrl, isNull);
      expect(shops[1].logoUrl, 'https://example.test/b.png');
    });

    test('hours arriving later reach a listener already attached', () async {
      final seen = <BrewShopStatus>[];
      final watch = counter.shops().listen((shops) {
        seen.add(shops.first.status);
      });
      addTearDown(watch.cancel);

      await pumpEventQueue();
      await db.collection('shops').doc('coffee-shop-a').set({'open': true});
      await pumpEventQueue();

      expect(seen.first, BrewShopStatus.unknown);
      expect(seen.last, BrewShopStatus.open);
    });

    test('logout can clear the warm cache without affecting the stream', () async {
      await db.collection('shops').doc('coffee-shop-a').set({'open': true});
      expect(await counter.shops().first, isNotEmpty);

      counter.clearCache();

      expect(counter.lastShops, isNull);
    });
  });

  group('the active order', () {
    Future<void> place(
      String id, {
      String uid = 'dave',
      String stage = 'preparing',
      String shop = 'coffee-shop-a',
      List<String> items = const ['Iced Latte'],
      DateTime? placedAt,
    }) {
      return db.collection('orders').doc(id).set({
        'uid': uid,
        'shop': shop,
        'items': items,
        'stage': stage,
        if (placedAt != null) 'placedAt': Timestamp.fromDate(placedAt),
      });
    }

    test('is absent when there is none, rather than empty', () async {
      expect(await counter.activeOrders('dave').first, isEmpty);
    });

    test('ignores a completed order', () async {
      await place('done', stage: 'completed');
      expect(await counter.activeOrders('dave').first, isEmpty);
    });

    test('ignores another account\'s order', () async {
      await place('theirs', uid: 'someone-else');
      expect(await counter.activeOrders('dave').first, isEmpty);
    });

    test('returns every order still open, newest first', () async {
      await place(
        'older',
        items: const ['Filter'],
        placedAt: DateTime.utc(2026, 7, 25, 8),
      );
      await place(
        'newer',
        items: const ['Iced Latte', 'Croissant'],
        placedAt: DateTime.utc(2026, 7, 25, 9),
      );

      final orders = await counter.activeOrders('dave').first;
      expect(
        orders.map((order) => order.itemLine),
        ['Iced Latte + Croissant', 'Filter'],
      );
    });

    test('a just-placed order with no server stamp yet sorts first', () async {
      await place('stamped', placedAt: DateTime.utc(2026, 7, 25, 8));
      await place('unstamped', items: const ['Cortado']);

      final orders = await counter.activeOrders('dave').first;
      expect(
        orders.first.itemLine,
        'Cortado',
        reason: 'a null placedAt is a stamp in flight, not an ancient order',
      );
    });

    test('a stage nobody recognises drops that order and nothing else', () async {
      await place('bogus', stage: 'levitating');
      await place('good', items: const ['Cortado']);

      final orders = await counter.orders('dave').first;
      expect(orders.map((order) => order.itemLine), ['Cortado']);
    });

    test('an order with no items is not an order', () async {
      await place('empty', items: const []);
      expect(await counter.activeOrders('dave').first, isEmpty);
    });

    test('reports the stage it is at and moves when the counter does', () async {
      await place('live', stage: 'received');
      final seen = <BrewOrderStage?>[];
      final watch = counter
          .activeOrders('dave')
          .listen((orders) => seen.add(orders.firstOrNull?.stage));
      addTearDown(watch.cancel);

      await pumpEventQueue();
      await db.collection('orders').doc('live').update({'stage': 'ready'});
      await pumpEventQueue();
      // Completed takes the card off the screen entirely.
      await db.collection('orders').doc('live').update({'stage': 'completed'});
      await pumpEventQueue();

      expect(seen, containsAllInOrder([
        BrewOrderStage.received,
        BrewOrderStage.ready,
        null,
      ]));
    });
  });

  group('an order', () {
    BrewOrder read(Map<String, Object?> data) => BrewOrder.read('id', data)!;

    test('names the shop it knows, and says something either way', () {
      expect(
        read({
          'shop': 'coffee-shop-b',
          'items': ['Bun'],
          'stage': 'ready',
        }).shopName,
        'Seven Coffee & Tea',
      );
      expect(
        read({
          'shop': 'a-shop-that-left-the-platform',
          'items': ['Bun'],
          'stage': 'ready',
        }).shopName,
        isNot(contains('a-shop-that-left')),
        reason: 'a document id is never shown to a reader',
      );
    });

    test('prints a range, a single figure, or nothing', () {
      BrewOrder withEta(Object? low, Object? high) => read({
        'items': ['Bun'],
        'stage': 'preparing',
        'etaLowMinutes': low,
        'etaHighMinutes': high,
      });

      expect(withEta(10, 15).estimate, '10–15 min');
      expect(withEta(12, null).estimate, '12 min');
      expect(withEta(null, null).estimate, isNull);
      // Nonsense is dropped rather than printed.
      expect(withEta(-3, 0).estimate, isNull);
      expect(withEta(10, 10).estimate, '10 min', reason: 'not a range of one');
    });

    test('inks one segment of the rule per stage reached', () {
      expect(
        read({'items': ['Bun'], 'stage': 'received'}).step,
        1,
      );
      expect(
        read({'items': ['Bun'], 'stage': 'ready'}).step,
        3,
      );
      expect(BrewOrder.steps, 4);
    });

    test('takes a single string of items as well as a list', () {
      expect(read({'items': 'Flat White', 'stage': 'ready'}).itemLine, 'Flat White');
    });

    test('reads the pickup, payment and total fields placeOrder writes', () {
      final order = read({
        'uid': 'reader-1',
        'items': ['Bun'],
        'stage': 'received',
        'totalCents': 3850,
        'pickupName': 'Alex',
        'pickupPhone': '0917 000 0000',
        'pickupNote': 'No sleeve',
        'paymentMethod': 'GCash',
      });

      expect(order.uid, 'reader-1');
      expect(order.totalCents, 3850);
      expect(order.totalLabel, '₱38.50');
      expect(order.pickupName, 'Alex');
      expect(order.pickupPhone, '0917 000 0000');
      expect(order.pickupNote, 'No sleeve');
      expect(order.paymentMethod, 'GCash');
    });

    test('leaves the new fields null rather than guessing at a document that lacks them', () {
      final order = read({'items': ['Bun'], 'stage': 'received'});

      expect(order.uid, isNull);
      expect(order.totalCents, isNull);
      expect(order.totalLabel, isNull);
      expect(order.pickupName, isNull);
      expect(order.pickupPhone, isNull);
      expect(order.pickupNote, isNull);
      expect(order.paymentMethod, isNull);
    });

    test('formats a whole-peso total bare, like every other price in the app', () {
      expect(
        read({'items': ['Bun'], 'stage': 'received', 'totalCents': 3800}).totalLabel,
        '₱38',
      );
    });
  });

  group('BrewOrderStage.next', () {
    test('steps forward one stage at a time and stops at completed', () {
      expect(BrewOrderStage.received.next, BrewOrderStage.preparing);
      expect(BrewOrderStage.preparing.next, BrewOrderStage.ready);
      expect(BrewOrderStage.ready.next, BrewOrderStage.completed);
      expect(BrewOrderStage.completed.next, isNull);
    });

    test('never chains into rejected — that stage is only ever set directly', () {
      expect(BrewOrderStage.rejected.next, isNull);
      for (final stage in BrewOrderStage.values) {
        expect(stage.next, isNot(BrewOrderStage.rejected));
      }
    });
  });

  group('BrewOrderStage.isActive', () {
    test('is false for both terminal stages, not just completed', () {
      expect(BrewOrderStage.received.isActive, isTrue);
      expect(BrewOrderStage.preparing.isActive, isTrue);
      expect(BrewOrderStage.ready.isActive, isTrue);
      expect(BrewOrderStage.completed.isActive, isFalse);
      expect(BrewOrderStage.rejected.isActive, isFalse);
    });
  });

  group('a rejected order', () {
    BrewOrder read(Map<String, Object?> data) => BrewOrder.read('id', data)!;

    test('parses the rejected stage and keeps its reason', () {
      final order = read({
        'items': ['Bun'],
        'stage': 'rejected',
        'rejectionReason': 'Out of stock',
      });

      expect(order.stage, BrewOrderStage.rejected);
      expect(order.rejectionReason, 'Out of stock');
    });

    test('leaves the reason null when none was given', () {
      expect(
        read({'items': ['Bun'], 'stage': 'rejected'}).rejectionReason,
        isNull,
      );
    });

    test('does not disturb BrewOrder.steps, which stays at four', () {
      // BrewOrder.step / .steps back the customer's own four-segment progress
      // rule (home_screen.dart's _StageRule) — adding a fifth enum value must
      // not silently stretch that rule to five segments.
      expect(BrewOrder.steps, 4);
    });
  });

  group('a menu', () {
    Future<void> add(
      String id,
      Map<String, Object?> data, {
      BrewPartner partner = BrewPartner.a,
    }) {
      return db
          .collection('shops')
          .doc(partner.id)
          .collection('menu')
          .doc(id)
          .set(data);
    }

    test('holds the board order the shop chose, unsorted items last', () async {
      await add('filter', {'name': 'Filter', 'sort': 20});
      await add('espresso', {'name': 'Espresso', 'sort': 10});
      await add('bun', {'name': 'Bun'});
      await add('cake', {'name': 'Cake'});

      final items = await counter.menu(BrewPartner.a).first;
      expect(items.map((item) => item.name), [
        'Espresso',
        'Filter',
        // Alphabetical only among the ones with no position of their own, so two
        // snapshots of the same data cannot come back in different orders.
        'Bun',
        'Cake',
      ]);
    });

    test('is one shop\'s board, not the platform\'s', () async {
      await add('a-only', {'name': 'Only at A'});
      await add('b-only', {'name': 'Only at B'}, partner: BrewPartner.b);

      expect(
        (await counter.menu(BrewPartner.a).first).map((item) => item.name),
        ['Only at A'],
      );
    });

    test('drops an item with no name and keeps the rest', () async {
      await add('nameless', {'priceCents': 400});
      await add('real', {'name': 'Cortado', 'priceCents': 400});

      final items = await counter.menu(BrewPartner.a).first;
      expect(items.map((item) => item.name), ['Cortado']);
    });

    test('formats a price in minor units and omits one it has not got', () {
      String? priceOf(Object? cents) =>
          BrewMenuItem.read('id', {'name': 'Bun', 'priceCents': cents})!.price;

      expect(priceOf(450), '₱4.50');
      // A whole-peso price prints bare. The boards these prices come off
      // write ₱45, not ₱45.00, and a menu of round numbers carrying two
      // decimal places everywhere reads as a spreadsheet.
      expect(priceOf(400), '₱4');
      expect(priceOf(4500), '₱45');
      expect(priceOf(5), '₱0.05');
      expect(priceOf(1250), '₱12.50');
      expect(priceOf(null), isNull);
      expect(priceOf(-1), isNull);
    });
  });

  /// A read that fails has to reach the listener *as a failure*.
  ///
  /// These streams used to end `.handleError((e) { debugPrint(e); })`, which
  /// catches the error and returns normally — so the stream neither emitted nor
  /// closed, and every `StreamBuilder` holding one sat on a null snapshot for
  /// good. That is what left the menu board on "Loading the board…" and the
  /// notifications panel on "Looking up your orders…" with nothing ever
  /// arriving, on any build where the rules refused the read.
  ///
  /// Staged with a Firestore whose reads raise, because fake_cloud_firestore
  /// does not enforce security rules on `snapshots()` — a locked-down instance
  /// returns an empty result rather than the error a deployed build raises.
  group('a failed read surfaces rather than hanging', () {
    late BrewCounter broken;

    setUp(() => broken = BrewCounter(_ThrowingFirestore()));

    /// Drains one stream and reports what it actually did: the error, or the
    /// silent close that used to leave a screen loading forever.
    ///
    /// `emitsError` alone does not catch the regression — a stream that closes
    /// without ever emitting satisfies it vacuously — so the close case is
    /// asserted against explicitly.
    Future<Object?> firstErrorOf(Stream<Object?> stream) async {
      var closedSilently = true;
      try {
        await for (final _ in stream) {
          closedSilently = false;
        }
      } catch (error) {
        return error;
      }
      return closedSilently ? null : 'emitted data';
    }

    test('menu forwards the error instead of going silent', () async {
      expect(
        await firstErrorOf(broken.menu(BrewPartner.a)),
        isA<FirebaseException>(),
        reason: 'a null here is the swallowed error that stranded the board',
      );
    });

    test('orders forwards the error instead of going silent', () async {
      expect(
        await firstErrorOf(broken.orders('dave')),
        isA<FirebaseException>(),
      );
    });

    test('activeOrders forwards the error instead of going silent', () async {
      expect(
        await firstErrorOf(broken.activeOrders('dave')),
        isA<FirebaseException>(),
      );
    });
  });

  /// Tested against a hand-built broadcast controller rather than through
  /// [FakeFirebaseFirestore], deliberately: the fake pushes a fresh `get()`
  /// into its controller on *every* `snapshots()` call, so a second listener
  /// there is always answered by somebody else's read and the behaviour this
  /// group is about — a shared stream with one native listen behind it —
  /// cannot be reproduced through it. The controller below is the shape
  /// method_channel_query.dart actually returns: broadcast, starting its read
  /// on the first listener and stopping it on the last.
  group('BrewCounter.latest', () {
    /// Waits out the microtasks a stream delivers its events on.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('hands a late listener the most recent event', () async {
      final source = StreamController<int>.broadcast();
      final stream = BrewCounter.latest(source.stream);

      final early = <int>[];
      final earlySub = stream.listen(early.add);
      source.add(1);
      await settle();
      expect(early, [1]);

      // Subscribing while `early` is still attached — the tab cross-fade's own
      // sequence. Nothing new is added to the source.
      final late_ = <int>[];
      final lateSub = stream.listen(late_.add);
      await settle();
      expect(
        late_,
        [1],
        reason: 'an empty list here is the Orders tab stuck on "Looking up '
            'your orders…" while Home already had the answer',
      );

      source.add(2);
      await settle();
      expect(early, [1, 2]);
      expect(late_, [1, 2]);

      await earlySub.cancel();
      await lateSub.cancel();
      await source.close();
    });

    test('holds one upstream read for however many listeners it has', () async {
      var listens = 0;
      var cancels = 0;
      late StreamController<int> source;
      source = StreamController<int>.broadcast(
        // What the native listener does on subscribe: answers immediately from
        // the cache.
        onListen: () {
          listens++;
          source.add(listens);
        },
        onCancel: () => cancels++,
      );
      final stream = BrewCounter.latest(source.stream);

      final first = stream.listen((_) {});
      await settle();
      final second = stream.listen((_) {});
      await settle();
      expect(listens, 1, reason: 'a second panel must not refetch');
      expect(cancels, 0);

      await first.cancel();
      await settle();
      expect(cancels, 0, reason: 'one panel leaving must not end the read');

      // The last listener leaving releases it, and the next one starts it
      // over — nothing is pinned open by the caching itself.
      await second.cancel();
      await settle();
      expect(cancels, 1);

      final third = stream.listen((_) {});
      await settle();
      expect(listens, 2);

      await third.cancel();
      await source.close();
    });

    test('forwards an error to every listener', () async {
      final source = StreamController<int>.broadcast();
      final stream = BrewCounter.latest(source.stream);

      final errors = <Object>[];
      final first = stream.listen((_) {}, onError: errors.add);
      final second = stream.listen((_) {}, onError: errors.add);
      await settle();
      source.addError(StateError('refused'));
      await settle();

      expect(errors, hasLength(2));
      await first.cancel();
      await second.cancel();
      await source.close();
    });
  });
}

/// A Firestore that fails every read the way an unreachable or refusing backend
/// does. Only the entry points [BrewCounter] actually calls are implemented;
/// everything else is [noSuchMethod]'s problem and never runs.
class _ThrowingFirestore implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _ThrowingCollection();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Implementing these sealed platform types is exactly what a stand-in for a
// failing backend has to do, and the alternative — a real Firestore that can be
// made to refuse — is the thing the fake cannot provide.
// ignore: subtype_of_sealed_class
class _ThrowingCollection implements CollectionReference<Map<String, dynamic>> {
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => Stream.error(
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
  );

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => this;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _ThrowingDocument();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _ThrowingDocument implements DocumentReference<Map<String, dynamic>> {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _ThrowingCollection();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
