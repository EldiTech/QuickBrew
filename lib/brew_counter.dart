import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// The two partner shops, and there are two.
///
/// Their names and descriptions ship with the app rather than arriving from
/// Firestore, because they are not data about the reader or about today — they
/// are which businesses QuickBrew is. Wiring them through the network would mean
/// a home screen that renders nothing on a cold, offline start, and the whole
/// point of this screen is to answer "which coffee shop?" instantly.
///
/// What does come from Firestore is the only part that actually changes: whether
/// each one is open. See [BrewCounter.shops].
enum BrewPartner {
  a(
    id: 'coffee-shop-a',
    name: 'Drip & Co',
    description: 'Vietnamese style coffee',
    monogram: 'D',
  ),
  b(
    id: 'coffee-shop-b',
    name: 'Seven Coffee & Tea',
    description: 'Handcrafted coffee, tea and signature drinks',
    monogram: '7',
  );

  const BrewPartner({
    required this.id,
    required this.name,
    required this.description,
    required this.monogram,
  });

  /// The `shops/{id}` document, and the value an order's `shop` field carries.
  final String id;

  final String name;

  /// One line. It has to fit two lines at 390 wide beside a 56px mark, and its
  /// job is to tell the two shops apart — not to sell either of them.
  final String description;

  /// The letter on the shop's mark when no logo has been supplied. Not a
  /// placeholder for a missing asset so much as the mark itself until a real one
  /// exists: an initial set in the display face is a monogram, whereas a grey box
  /// with a broken-image glyph is a bug the reader has to look at.
  ///
  /// Stated rather than taken from the name's first letter, because the first
  /// letter is not always the mark: Seven Coffee & Tea's is the numeral, not "S".
  /// Deriving it would also silently reintroduce the collision the two built-in
  /// names used to have — both began with "C" — the moment either is renamed.
  final String monogram;
}

/// Whether a shop is taking orders.
///
/// Four states, not the two the reader is shown, because "we have not asked yet"
/// and "we asked and there is no record" are both real and neither of them is
/// Closed. Printing Closed for a missing document would turn a configuration
/// mistake into a lie that costs the partner business.
enum BrewShopStatus {
  /// Firestore has not answered yet. The first frame after launch.
  pending,

  open,
  closed,

  /// No `shops/{id}` document, no `open` field on it, or the read failed.
  unknown;

  /// The mono label under the shop's name. Uppercased by the label itself.
  String get label => switch (this) {
    BrewShopStatus.pending => 'Checking hours',
    BrewShopStatus.open => 'Open',
    BrewShopStatus.closed => 'Closed',
    BrewShopStatus.unknown => 'Hours unavailable',
  };
}

/// A partner plus what Firestore currently says about it.
///
/// [name] and [description] are the shop's own words for itself, editable from
/// the admin side. They sit *beside* [BrewPartner]'s built-in pair rather than
/// replacing them — see [displayName] — because the enum's copy is what makes
/// the home screen render instantly on a cold, offline start, and a shop that
/// has never been renamed should not be a blank card until the network answers.
class BrewShop {
  const BrewShop({
    required this.partner,
    required this.status,
    this.name,
    this.description,
    this.logoUrl,
    this.logoBytes,
    this.payQrBytes,
  });

  /// Both shops, before the first snapshot arrives. Always both, always in
  /// enum order: the screen never has to reason about a shop being absent, and
  /// the two can never swap places between frames.
  static List<BrewShop> get pending => _both(BrewShopStatus.pending);

  /// Both shops on a build with no Firestore behind it.
  ///
  /// [unknown] rather than [BrewShopStatus.pending], because nothing is pending —
  /// there is nothing to answer. "Checking hours" that will never finish checking
  /// is a spinner in words.
  static List<BrewShop> get unavailable => _both(BrewShopStatus.unknown);

  static List<BrewShop> _both(BrewShopStatus status) => [
    for (final partner in BrewPartner.values)
      BrewShop(partner: partner, status: status),
  ];

  final BrewPartner partner;
  final BrewShopStatus status;

  /// What the shop calls itself, if an admin has set it. Null falls back to
  /// [BrewPartner.name].
  final String? name;

  /// The one line under the name, if an admin has set it. Null falls back to
  /// [BrewPartner.description].
  final String? description;

  /// A logo hosted somewhere else. Kept alongside [logoBytes] because both are
  /// legitimate — a partner with a CDN should not have to paste a data URI —
  /// and because documents written before uploads existed still carry one.
  final String? logoUrl;

  /// An uploaded logo, already decoded out of the base64 the document stores.
  ///
  /// Decoded once here rather than at paint time: the mark is rebuilt on every
  /// press animation frame, and base64-decoding tens of kilobytes inside a
  /// build method is work done sixty times a second for a result that never
  /// changes.
  final Uint8List? logoBytes;

  /// The shop's payment QR, as the admin uploaded it, already decoded out of
  /// the base64 the document stores — the same scheme [logoBytes] uses.
  ///
  /// Null for a shop whose admin has not uploaded one, which the wizard's
  /// payment step says out loud rather than drawing an empty frame: a reader
  /// cannot pay a code that is not there, and a blank square where a QR goes is
  /// the one thing worse than being told to ask at the counter.
  final Uint8List? payQrBytes;

  /// The name to print. Never null, which is the point.
  String get displayName => name ?? partner.name;

  String get displayDescription => description ?? partner.description;

  /// The live name of each partner, keyed for the screens that hold a
  /// [BrewPartner] rather than a whole [BrewShop] — the invite picker and the
  /// users list, which know which store an account is assigned to but not what
  /// that store currently calls itself.
  ///
  /// Falls back per partner, so a lookup always yields a name even for a shop
  /// the snapshot did not include.
  static String nameOf(BrewPartner partner, List<BrewShop>? shops) =>
      shops?.where((shop) => shop.partner == partner).firstOrNull?.displayName ??
      partner.name;
}

/// Where an order has got to.
///
/// The four the brief names, in the order they happen — the index is the
/// progress, which is what the rule under the status is drawn from.
enum BrewOrderStage {
  received('Order received'),
  preparing('Preparing your order'),
  ready('Ready for pickup'),
  completed('Completed'),

  /// The shop declined it — out of stock, closing early, whatever the reason
  /// the admin queue's Reject sheet records on [BrewOrder.rejectionReason].
  /// Terminal, the same as [completed], but never reached by walking forward
  /// through the others: [BrewAdmin.rejectOrder] writes this stage directly,
  /// from whichever active stage the order was sitting in.
  ///
  /// Deliberately last in the enum, after [completed] rather than beside
  /// [received]: [BrewOrder.step] reads `stage.index + 1` and [BrewOrder.steps]
  /// reads `BrewOrderStage.values.length` for the customer's own progress
  /// rule, which only ever has four segments. A rejected order does not walk
  /// that rule at all — see [isActive] — so its index never has to fit on it,
  /// but inserting it earlier would have shifted every stage after it and
  /// silently relabelled the rule's own segments.
  rejected('Order declined');

  const BrewOrderStage(this.label);

  /// What the reader is told, as a sentence about their cup rather than a state
  /// name. "Preparing your order", not "PREPARING".
  final String label;

  /// The stored value, which is the enum name — `received`, `preparing`, and so
  /// on. Unrecognised and missing values both come back null, and an order the
  /// app cannot place on this scale is not shown at all: a card that cannot say
  /// where the order is has nothing to offer over saying nothing.
  static BrewOrderStage? parse(Object? value) {
    if (value is! String) return null;
    final wanted = value.trim().toLowerCase();
    for (final stage in values) {
      if (stage.name == wanted) return stage;
    }
    return null;
  }

  /// [completed] and [rejected] are both history — one fulfilled, one
  /// declined — and everything before either is something the reader may
  /// still be walking towards, which is what puts the card on the home
  /// screen.
  bool get isActive => this != BrewOrderStage.completed && this != BrewOrderStage.rejected;

  /// The stage after this one, or null once there is nowhere further to go —
  /// the same shape [_Step.next] gives the order wizard. What the admin
  /// queue's forward button advances to; there is no control anywhere that
  /// skips a stage or moves one back.
  ///
  /// Null on [rejected] for the same reason it is null on [completed]: both
  /// are where a queue's forward button stops. [rejected] is never reached by
  /// this getter regardless — [BrewAdmin.rejectOrder] writes it directly from
  /// whichever active stage the order was in, which is a jump this getter
  /// deliberately does not offer for any other stage.
  BrewOrderStage? get next => switch (this) {
        BrewOrderStage.received => BrewOrderStage.preparing,
        BrewOrderStage.preparing => BrewOrderStage.ready,
        BrewOrderStage.ready => BrewOrderStage.completed,
        BrewOrderStage.completed => null,
        BrewOrderStage.rejected => null,
      };
}

/// One order, as the home screen and the orders list need it.
class BrewOrder {
  const BrewOrder({
    required this.id,
    required this.stage,
    required this.items,
    this.partner,
    this.etaLowMinutes,
    this.etaHighMinutes,
    this.placedAt,
    this.scheduledFor,
    this.uid,
    this.totalCents,
    this.pickupName,
    this.pickupPhone,
    this.pickupNote,
    this.paymentMethod,
    this.receiptBytes,
    this.rejectionReason,
  });

  /// Null when the document is missing a stage or its items — see
  /// [BrewOrderStage.parse]. Returned rather than thrown because one malformed
  /// order should cost the reader that one card, not the whole screen.
  static BrewOrder? read(
    String id,
    Map<String, Object?> data,
  ) {
    final stage = BrewOrderStage.parse(data['stage']);
    if (stage == null) return null;

    final items = switch (data['items']) {
      final List<Object?> list => [
        for (final item in list)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ],
      final String single when single.trim().isNotEmpty => [single.trim()],
      _ => const <String>[],
    };
    if (items.isEmpty) return null;

    return BrewOrder(
      id: id,
      stage: stage,
      items: items,
      partner: BrewPartner.values
          .where((partner) => partner.id == data['shop'])
          .firstOrNull,
      etaLowMinutes: _minutes(data['etaLowMinutes']),
      etaHighMinutes: _minutes(data['etaHighMinutes']),
      placedAt: switch (data['placedAt']) {
        final Timestamp stamp => stamp.toDate(),
        _ => null,
      },
      scheduledFor: switch (data['scheduledFor']) {
        final Timestamp stamp => stamp.toDate(),
        _ => null,
      },
      uid: _trimmedOrNull(data['uid']),
      totalCents: switch (data['totalCents']) {
        final num value when value >= 0 => value.round(),
        _ => null,
      },
      pickupName: _trimmedOrNull(data['pickupName']),
      pickupPhone: _trimmedOrNull(data['pickupPhone']),
      pickupNote: _trimmedOrNull(data['pickupNote']),
      paymentMethod: _trimmedOrNull(data['paymentMethod']),
      receiptBytes: _decodeBase64Image(_trimmedOrNull(data['receiptBase64'])),
      rejectionReason: _trimmedOrNull(data['rejectionReason']),
    );
  }

  /// Ints, and only sane ones. A negative or absurd estimate drops the line
  /// rather than printing "Estimated time: -3 min".
  static int? _minutes(Object? value) => switch (value) {
    final num number when number > 0 && number < 24 * 60 => number.round(),
    _ => null,
  };

  final String id;
  final BrewOrderStage stage;

  /// At least one, never empty.
  final List<String> items;

  /// Null if the document names a shop this build does not know about.
  final BrewPartner? partner;

  final int? etaLowMinutes;
  final int? etaHighMinutes;
  final DateTime? placedAt;

  /// When the reader asked to collect, or null for an order to be made now —
  /// which is every order placed before scheduling existed, so absence reads
  /// as "now" rather than as missing data.
  final DateTime? scheduledFor;

  /// Who placed it. Null is not expected on a document [placeOrder] wrote,
  /// but the admin queue reads orders it did not write itself and applies the
  /// same leniency every other field on this class does.
  final String? uid;

  /// Minor units, the same convention [BrewMenuItem.priceCents] uses. Null
  /// for a document with no usable figure, which prints nothing rather than
  /// a fabricated ₱0.
  final int? totalCents;

  /// Who to call out, what to reach them on, and anything for the counter —
  /// the three pickup fields [placeOrder] writes. Read only by the admin
  /// queue; the customer's own history already knows whose order it is.
  final String? pickupName;
  final String? pickupPhone;
  final String? pickupNote;

  /// [_Payment.label] as [placeOrder] stored it — see order_wizard_screen.dart.
  final String? paymentMethod;

  /// The proof of payment the reader uploaded on the payment step, decoded out
  /// of the base64 the document stores — the same scheme [BrewShop.logoBytes]
  /// uses, and for the same reason: this build has no Storage bucket.
  ///
  /// Null on every order placed before the receipt step existed, which the admin
  /// queue reads as "nothing to show" rather than as a missing payment. What it
  /// is *not* is a verified payment: nobody checked it, and the counter still
  /// looks at the picture before handing over a cup.
  final Uint8List? receiptBytes;

  /// What the shop said when it declined this order, if it said anything —
  /// see [BrewAdmin.rejectOrder]. Null on every order that was not rejected,
  /// and on a rejected one whose admin left the reason blank.
  final String? rejectionReason;

  /// The shop line on the card. Falls back rather than showing a raw document
  /// id, which would be the app's problem leaking into the reader's screen.
  String get shopName => partner?.name ?? 'Your coffee shop';

  /// The total as the admin queue prints it, or null when the document has
  /// none. Duplicates [BrewMenuItem]'s own peso formatting rather than
  /// reaching into that class for it — the same call the order wizard's own
  /// top-level `_formatCents` already makes, for the same reason: this figure
  /// has no menu item behind it.
  String? get totalLabel {
    final cents = totalCents;
    if (cents == null) return null;
    final pesos = cents ~/ 100;
    final centavos = cents % 100;
    if (centavos == 0) return '₱$pesos';
    return '₱$pesos.${centavos.toString().padLeft(2, '0')}';
  }

  /// "Iced Latte + Croissant" — the brief's own separator, and the one that
  /// reads as a single order rather than a bulleted list.
  String get itemLine => items.join(' + ');

  /// "SCT-4B2E" — what the reader quotes at the counter.
  ///
  /// Derived from what the order already is rather than stored as a field: the
  /// shop's initials, then the tail of this order's own document id. A counter
  /// asking "which order?" needs something short and sayable, and the 20-char
  /// autoId Firestore hands out is neither — but it is the only identifier
  /// that is genuinely this order's, so the short form is cut from it rather
  /// than from a sequence number nothing in this app issues.
  ///
  /// Stable for the life of the order, and unique within a shop's queue for
  /// every practical size of one: four base-62 characters is 14 million, and
  /// the shop prefix separates the two partners' queues on top of that.
  String get reference {
    final initials = [
      for (final word in shopName.split(RegExp(r'\s+')))
        if (word.isNotEmpty && RegExp('[A-Za-z0-9]').hasMatch(word[0]))
          word[0].toUpperCase(),
    ];
    // "QB" for a shop whose name is punctuation all the way down — the prefix
    // is a convenience, and losing it should not lose the reference.
    final prefix = initials.isEmpty ? 'QB' : initials.take(3).join();
    final tail = id.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
    final suffix = tail.length <= 4
        ? tail.padLeft(4, '0')
        : tail.substring(tail.length - 4);
    return '$prefix-$suffix';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  /// "2 Aug, 3:41 PM" — hand-formatted rather than pulling in `intl`, the
  /// same call [BrewMenuItem]'s own peso formatting makes and for the same
  /// reason. Lives here because three screens print an order's times — the
  /// admin detail sheet, the home card, and the wizard's summary — and each
  /// hand-rolling its own would let them drift apart.
  static String formatWhen(DateTime at) =>
      '${formatDate(at)}, ${formatClock(at)}';

  /// "5:45 PM". The clock half, for a card that sets the day and the time on
  /// two different lines.
  static String formatClock(DateTime at) {
    final hour12 = switch (at.hour % 12) { 0 => 12, final h => h };
    final minute = at.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "2 Aug", or "2 Aug 2025" with [year]. The year is off by default because
  /// the times this app prints are hours away, not months.
  static String formatDate(DateTime at, {bool year = false}) =>
      '${at.day} ${_months[at.month - 1]}${year ? ' ${at.year}' : ''}';

  /// "Today", "Tomorrow", or "Sat 2 Aug" — the day half of a pickup line, said
  /// the way someone waiting for a coffee would say it.
  ///
  /// Compared as whole calendar days rather than as a [Duration]: an hour of
  /// daylight saving between the two dates would make a 23-hour gap read as
  /// zero days, so tomorrow would print as Today twice a year.
  static String formatDay(DateTime at, DateTime now) =>
      switch (_dayNumber(at) - _dayNumber(now)) {
        0 => 'Today',
        1 => 'Tomorrow',
        _ => '${_weekdays[at.weekday - 1]} ${formatDate(at)}',
      };

  /// The local calendar day as a number, via UTC so the arithmetic cannot pick
  /// up an offset the local zone shifts partway through the year.
  static int _dayNumber(DateTime at) =>
      DateTime.utc(at.year, at.month, at.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// "10–15 min", "12 min", or null when there is no usable estimate. An en
  /// dash, not a hyphen: it is a range.
  String? get estimate {
    final (low, high) = (etaLowMinutes, etaHighMinutes);
    return switch ((low, high)) {
      (final l?, final h?) when h > l => '$l–$h min',
      (final l?, _) => '$l min',
      (_, final h?) => '$h min',
      _ => null,
    };
  }

  /// The stage as 1..4, for the progress rule. [BrewOrderStage.rejected] has
  /// no place on that rule — a declined order is never active, so it is never
  /// the order [BrewCounter.activeOrder] hands this screen — but this still
  /// clamps to [steps] rather than trust that a rule enforced two files away,
  /// so a malformed or future caller gets a segment count that fits the rule
  /// it feeds rather than one past the end of it.
  int get step {
    final raw = stage.index + 1;
    return raw > steps ? steps : raw;
  }

  /// Four: [BrewOrderStage.received], [BrewOrderStage.preparing],
  /// [BrewOrderStage.ready], [BrewOrderStage.completed]. Stated rather than
  /// read off [BrewOrderStage.values] — that list also holds
  /// [BrewOrderStage.rejected], which the progress track this feeds
  /// (`StageTrack` in widgets/order_track.dart) has no point for and never
  /// will: a declined order does not have a further stage to walk towards.
  static int get steps => 4;
}

/// The one size choice a menu item may carry.
///
/// A fixed set of three rather than free text, so the board reads as a menu
/// with a real size chart instead of an admin's own words for one — every
/// shop uses the same three names, the same way every shop uses the same
/// currency for [BrewMenuItem.price].
enum BrewItemSize {
  small,
  medium,
  large;

  String get label => switch (this) {
    BrewItemSize.small => 'Small',
    BrewItemSize.medium => 'Medium',
    BrewItemSize.large => 'Large',
  };

  /// The stored value, which is the enum name. Unrecognised and missing
  /// values both come back null, the same as no size having been set at all
  /// — see [BrewOrderStage.parse], which this mirrors.
  static BrewItemSize? parse(Object? value) {
    if (value is! String) return null;
    final wanted = value.trim().toLowerCase();
    for (final size in values) {
      if (size.name == wanted) return size;
    }
    return null;
  }

  String get storedValue => name;
}

/// One thing a shop sells.
///
/// Deliberately thin: a name, a line about it, a price — either one flat price,
/// or one price per size it comes in. No modifiers, no availability — this
/// build browses a menu, it does not build an order out of one, and modelling
/// milk choices that nothing can act on would be three fields of fiction.
class BrewMenuItem {
  const BrewMenuItem({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.subCategory,
    this.sizePrices = const {},
    this.priceCents,
    this.sort,
    this.imageBytes,
  });

  /// Null when the document has no usable name, which is the only field the row
  /// cannot be drawn without.
  static BrewMenuItem? read(String id, Map<String, Object?> data) {
    final name = switch (data['name']) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };
    if (name == null) return null;

    return BrewMenuItem(
      id: id,
      name: name,
      description: switch (data['description']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => null,
      },
      category: _trimmedOrNull(data['category']),
      subCategory: _trimmedOrNull(data['subCategory']),
      sizePrices: _readSizePrices(data['sizePrices']),
      priceCents: switch (data['priceCents']) {
        final num value when value >= 0 => value.round(),
        _ => null,
      },
      sort: switch (data['sort']) {
        final num value => value.toDouble(),
        _ => null,
      },
      imageBytes: _decodeBase64Image(_trimmedOrNull(data['imageBase64'])),
    );
  }

  /// Unrecognised keys and negative or non-numeric values are dropped rather
  /// than failing the whole item — the same leniency [BrewItemSize.parse] and
  /// the `priceCents` branch above extend to every other field on this
  /// document, so one bad entry in the map cannot blank a product that
  /// otherwise reads fine.
  static Map<BrewItemSize, int> _readSizePrices(Object? raw) {
    if (raw is! Map) return const {};
    final result = <BrewItemSize, int>{};
    for (final entry in raw.entries) {
      final size = BrewItemSize.parse(entry.key);
      final value = entry.value;
      if (size != null && value is num && value >= 0) {
        result[size] = value.round();
      }
    }
    return Map.unmodifiable(result);
  }

  /// Board order, lowest first. See [BrewCounter.menu].
  static int byBoardOrder(BrewMenuItem a, BrewMenuItem b) {
    final (left, right) = (a.sort, b.sort);
    if (left != null && right != null && left != right) {
      return left.compareTo(right);
    }
    // Unsorted items fall behind sorted ones, and ties settle on the name so the
    // list cannot reshuffle between two snapshots that say the same thing.
    if (left == null && right != null) return 1;
    if (left != null && right == null) return -1;
    return a.name.compareTo(b.name);
  }

  /// What the filter row offers, in the order the board itself is in.
  ///
  /// Derived from the items rather than stored on the shop: a category exists
  /// exactly as long as something is filed under it, so deleting the last
  /// Milktea takes the Milktea chip with it and no admin has to remember to
  /// tidy up a second list. Items are expected pre-sorted by [byBoardOrder],
  /// which is what makes the chips run in board order too.
  static List<String> categoriesOf(Iterable<BrewMenuItem> items) {
    final seen = <String>[];
    for (final item in items) {
      final category = item.category;
      if (category != null && !seen.contains(category)) seen.add(category);
    }
    return List.unmodifiable(seen);
  }

  /// The sub-categories filed under [category], in board order. Empty when
  /// that category has no subdivisions — the filter row then has nothing
  /// finer to offer and draws only the categories above it.
  static List<String> subCategoriesOf(
    Iterable<BrewMenuItem> items,
    String category,
  ) {
    final seen = <String>[];
    for (final item in items) {
      if (item.category != category) continue;
      final sub = item.subCategory;
      // A sub-category that merely repeats its category — "Hot Beverages"
      // under "Hot Beverages", which is how the source data spells a category
      // that has no real subdivisions — is not a choice, so it is not offered
      // as one.
      if (sub != null && sub != category && !seen.contains(sub)) seen.add(sub);
    }
    return List.unmodifiable(seen);
  }

  final String id;
  final String name;
  final String? description;

  /// What section of the board this item belongs to — "Iced Coffee",
  /// "Milktea", "Hot Beverages". Free text rather than an enum: the two shops
  /// here sell different things and a fixed set would either be one shop's
  /// vocabulary imposed on the other or a list nobody could extend without a
  /// release. Null for an item nobody has filed yet, which is what the
  /// filters call "Uncategorised".
  final String? category;

  /// The finer grouping inside [category] — "Frappe Series" under "Iced
  /// Blended", "Cream Cheese" under "Milktea". Null when the category has no
  /// subdivisions worth drawing, and ignored entirely when [category] is null:
  /// a sub-category of nothing is not a fact this board can place.
  final String? subCategory;

  /// Empty when the shop has not priced this item by size — not every product
  /// has one, a muffin least of all. Non-empty means the flat [priceCents]
  /// below is ignored: a sized item is priced per size, not once.
  final Map<BrewItemSize, int> sizePrices;

  /// The shop's own position for this item, if they set one.
  final double? sort;

  /// Minor units, so nothing here is ever a rounded double. Null when the shop
  /// has not priced the item, which prints nothing rather than "$0.00". Only
  /// read when [sizePrices] is empty — a sized item has no single price to
  /// fall back to.
  final int? priceCents;

  /// An uploaded picture, already decoded out of the base64 the document
  /// stores. The same scheme [BrewShop.logoBytes] uses, and for the same
  /// reason: this build has no Storage bucket, and a downscaled picture is
  /// small enough to live in the item's own document.
  final Uint8List? imageBytes;

  /// Philippine Peso, the one currency this build prices in.
  ///
  /// Whole pesos print bare — ₱38, not ₱38.00 — because that is how the
  /// boards these prices were transcribed from write them, and a menu of
  /// round numbers rendered with two decimal places reads as a spreadsheet.
  /// Centavos still print when an item actually has them, so the format
  /// never lies about the stored value.
  static String _formatCents(int cents) {
    final pesos = cents ~/ 100;
    final centavos = cents % 100;
    if (centavos == 0) return '₱$pesos';
    return '₱$pesos.${centavos.toString().padLeft(2, '0')}';
  }

  /// Formatted by hand rather than through `intl`: one currency, one locale's
  /// worth of formatting, and a whole package to pull in for it.
  ///
  /// Null for a sized item — there is no one price to print on the line a flat
  /// item prints its price on. [sizeLines] carries each size's own price
  /// instead.
  String? get price {
    if (sizePrices.isNotEmpty) return null;
    final cents = priceCents;
    if (cents == null) return null;
    return _formatCents(cents);
  }

  /// One line per priced size, cheapest first, for the board row to lay out
  /// the way it already lays out a flat price beside a name.
  List<(BrewItemSize, String)> get sizeLines {
    final sizes = sizePrices.keys.toList()
      ..sort((a, b) => sizePrices[a]!.compareTo(sizePrices[b]!));
    return [for (final size in sizes) (size, _formatCents(sizePrices[size]!))];
  }
}

/// One extra a shop will put in a drink, priced — an espresso shot, oat milk,
/// a scoop of pearls.
///
/// Per shop rather than shipped with the app, unlike [BrewPartner]'s names.
/// The two shops here sell different things and price the same extra
/// differently, so a fixed list in code would be one shop's board imposed on
/// the other — the same reasoning [BrewMenuItem.category] gives for being free
/// text. A shop with nothing in this collection sells no add-ons, which the
/// wizard reads as a step with only a quantity on it.
///
/// [group] is the heading the shop's board prints this under — "Sinkers",
/// "Toppings", "Milk choice". Free text for the same reason as
/// [BrewMenuItem.category], and it is what
/// [BrewAddOn.groupsOf] turns into the wizard's collapsible sections.
class BrewAddOn {
  const BrewAddOn({
    required this.id,
    required this.name,
    required this.priceCents,
    this.group,
    this.sort,
  });

  /// Null when the document has no usable name, or no usable price. Unlike a
  /// menu item — which can sit on a board unpriced while the shop decides — an
  /// add-on's whole job is to add a number to a total, and one that cannot say
  /// how much it costs would silently add nothing.
  static BrewAddOn? read(String id, Map<String, Object?> data) {
    final name = _trimmedOrNull(data['name']);
    if (name == null) return null;

    final priceCents = switch (data['priceCents']) {
      final num value when value >= 0 => value.round(),
      _ => null,
    };
    if (priceCents == null) return null;

    return BrewAddOn(
      id: id,
      name: name,
      priceCents: priceCents,
      group: _trimmedOrNull(data['group']),
      sort: switch (data['sort']) {
        final num value => value.toDouble(),
        _ => null,
      },
    );
  }

  /// Board order, lowest first — the same rule [BrewMenuItem.byBoardOrder]
  /// follows, and for the same reason: the shop chose this sequence.
  static int byBoardOrder(BrewAddOn a, BrewAddOn b) {
    final (left, right) = (a.sort, b.sort);
    if (left != null && right != null && left != right) {
      return left.compareTo(right);
    }
    if (left == null && right != null) return 1;
    if (left != null && right == null) return -1;
    return a.name.compareTo(b.name);
  }

  /// The headings the wizard draws a section for, in board order.
  ///
  /// Derived from the add-ons rather than stored on the shop, exactly as
  /// [BrewMenuItem.categoriesOf] is: a group exists as long as something is
  /// filed under it, so deleting the last topping takes the Toppings heading
  /// with it. Ungrouped add-ons are not represented here — [ungroupedOf] is
  /// what collects those, so they get a section of their own rather than
  /// vanishing.
  static List<String> groupsOf(Iterable<BrewAddOn> addOns) {
    final seen = <String>[];
    for (final addOn in addOns) {
      final group = addOn.group;
      if (group != null && !seen.contains(group)) seen.add(group);
    }
    return List.unmodifiable(seen);
  }

  /// The add-ons filed under [group], in board order.
  static List<BrewAddOn> inGroup(Iterable<BrewAddOn> addOns, String group) =>
      List.unmodifiable(addOns.where((addOn) => addOn.group == group));

  /// The add-ons nobody filed under a heading. Kept as its own list rather
  /// than folded into the first group: an admin who has not got round to
  /// grouping should still see their add-ons offered, not lose them to a
  /// heading they never typed.
  static List<BrewAddOn> ungroupedOf(Iterable<BrewAddOn> addOns) =>
      List.unmodifiable(addOns.where((addOn) => addOn.group == null));

  final String id;
  final String name;

  /// Minor units, so nothing here is ever a rounded double — the same rule
  /// [BrewMenuItem.priceCents] follows.
  final int priceCents;

  final String? group;

  /// The shop's own position for this add-on, if they set one.
  final double? sort;

  /// What the option row prints on its right — "+₱15". The plus is part of the
  /// reading: this is a surcharge on a price already stated, not a price.
  String get priceLabel => '+${BrewMenuItem._formatCents(priceCents)}';
}

/// One line of a saved order, as the draft document stores it.
///
/// Ids, not resolved objects — and that is the whole design of this class. A
/// draft may sit for a day before the reader comes back to it, and in that time
/// the shop can reprice oat milk, rename an item or stop selling it. Storing
/// the *choices* rather than the priced result means a resumed draft is
/// re-costed against the board as it stands when they resume, which is the only
/// figure the counter will actually honour. See [BrewDraft.staleAgainst], which
/// is what lets the wizard say so out loud rather than silently changing the
/// total.
///
/// [unitCents] is stored anyway, as what this line cost when it was saved. Not
/// to charge from — nothing reads it as a price — but so the wizard can compare
/// and tell the reader that something moved.
class BrewDraftLine {
  const BrewDraftLine({
    required this.itemId,
    required this.size,
    required this.extraIds,
    required this.quantity,
    required this.unitCents,
  });

  /// Null when the document is missing the one field a line cannot be rebuilt
  /// without. Dropped rather than throwing, the same leniency [BrewOrder.read]
  /// extends: one unreadable line should cost that line, not the whole draft.
  static BrewDraftLine? read(Object? raw) {
    if (raw is! Map) return null;
    final itemId = _trimmedOrNull(raw['itemId']);
    if (itemId == null) return null;

    return BrewDraftLine(
      itemId: itemId,
      size: BrewItemSize.parse(raw['size']),
      extraIds: switch (raw['extraIds']) {
        final List<Object?> list => List<String>.unmodifiable([
          for (final id in list) ?_trimmedOrNull(id),
        ]),
        _ => const <String>[],
      },
      // Clamped to the stepper's own range rather than trusted: a document
      // hand-edited to 5000 would put a quantity on the cart row that no
      // counter is going to make.
      quantity: switch (raw['quantity']) {
        final num value when value >= 1 && value <= 5 => value.round(),
        _ => 1,
      },
      unitCents: switch (raw['unitCents']) {
        final num value when value >= 0 => value.round(),
        _ => 0,
      },
    );
  }

  final String itemId;
  final BrewItemSize? size;
  final List<String> extraIds;
  final int quantity;

  /// What one of these cost when the draft was saved. Compared against, never
  /// charged from — see the note on this class.
  final int unitCents;

  Map<String, Object?> get stored => {
    'itemId': itemId,
    if (size != null) 'size': size!.storedValue,
    'extraIds': extraIds,
    'quantity': quantity,
    'unitCents': unitCents,
  };
}

/// An order the reader started, left, and can come back to.
///
/// One per reader, at `drafts/{uid}`, because this is not a list of parked
/// baskets — it is *the* order in progress. A reader who starts a second one at
/// the other shop has changed their mind about what they are buying, and two
/// saved drafts would mean the home screen has to ask which, on a screen whose
/// whole job is to answer "which coffee shop?" in one tap. Saving overwrites.
///
/// It is deliberately not an order. Nothing in `orders` is written until the
/// reader confirms, so a draft cannot appear at the counter, cannot be
/// prepared, and cannot be paid for. That is the line this class exists to keep:
/// the Orders tab lists things the shop knows about, and this is not one of
/// them.
class BrewDraft {
  const BrewDraft({
    required this.partner,
    required this.step,
    required this.lines,
    required this.pickupName,
    required this.pickupPhone,
    required this.pickupNote,
    required this.paymentMethod,
    this.scheduledFor,
    this.savedAt,
  });

  /// Null when the draft names a shop this build does not know, or has no lines
  /// left to rebuild. Either way there is nothing to resume, and a card
  /// offering to resume nothing is worse than no card.
  static BrewDraft? read(Map<String, Object?> data) {
    final partner = BrewPartner.values
        .where((partner) => partner.id == data['shop'])
        .firstOrNull;
    if (partner == null) return null;

    final lines = <BrewDraftLine>[
      for (final raw in switch (data['lines']) {
        final List<Object?> list => list,
        _ => const <Object?>[],
      })
        ?BrewDraftLine.read(raw),
    ];
    if (lines.isEmpty) return null;

    return BrewDraft(
      partner: partner,
      // An unrecognised step resumes at the cart, which is the one step that
      // can always be drawn from lines alone — it needs no size choice held
      // open and no form filled in.
      step: _trimmedOrNull(data['step']) ?? 'cart',
      lines: List.unmodifiable(lines),
      pickupName: _trimmedOrNull(data['pickupName']) ?? '',
      pickupPhone: _trimmedOrNull(data['pickupPhone']) ?? '',
      pickupNote: _trimmedOrNull(data['pickupNote']) ?? '',
      paymentMethod: _trimmedOrNull(data['paymentMethod']) ?? '',
      scheduledFor: switch (data['scheduledFor']) {
        final Timestamp stamp => stamp.toDate(),
        _ => null,
      },
      savedAt: switch (data['savedAt']) {
        final Timestamp stamp => stamp.toDate(),
        _ => null,
      },
    );
  }

  final BrewPartner partner;

  /// Which wizard step the reader was on, as [_Step]'s own enum name. Stored as
  /// a string because the step enum is private to the wizard — the counter has
  /// no business knowing how many steps there are or what they are called, only
  /// that it is holding one reader's place.
  final String step;

  final List<BrewDraftLine> lines;
  final String pickupName;
  final String pickupPhone;
  final String pickupNote;

  /// [_Payment.label] as it was stored on the way out, matched back by label on
  /// the way in. An unrecognised one falls back to pay-at-counter, which is the
  /// method that is always true in this build.
  final String paymentMethod;

  /// The pickup time the reader chose, or null for an order to be made now.
  /// Same reading as [BrewOrder.scheduledFor].
  final DateTime? scheduledFor;

  final DateTime? savedAt;

  /// How many drinks are in it, quantities counted. The figure the card prints.
  ///
  /// The accumulators below are named `total` rather than the `sum` the wizard
  /// uses for the same fold: `cloud_firestore` exports an aggregate-query type
  /// called `Sum`, and a parameter shadowing a visible type name is a lint this
  /// file cannot dodge the way a screen that does not import Firestore can.
  int get drinkCount => lines.fold(0, (total, line) => total + line.quantity);

  /// What it cost when it was saved. Only ever used to compare against a fresh
  /// costing — see [BrewDraftLine.unitCents].
  int get savedTotalCents => lines.fold(
    0,
    (total, line) => total + line.unitCents * line.quantity,
  );

  /// Whether re-costing these lines against [items] and [addOns] gives a
  /// different figure from the one saved.
  ///
  /// A line whose item has left the board counts as stale on its own: it is not
  /// a price that moved, it is a drink that is no longer sold, and the reader
  /// has to be told before they are walked to a confirm button.
  bool staleAgainst(List<BrewMenuItem> items, List<BrewAddOn> addOns) {
    for (final line in lines) {
      final item = items.where((item) => item.id == line.itemId).firstOrNull;
      if (item == null) return true;
      final base = switch (line.size) {
        final size? => item.sizePrices[size],
        null => item.priceCents ?? 0,
      };
      if (base == null) return true;
      var unit = base;
      for (final id in line.extraIds) {
        final extra = addOns.where((addOn) => addOn.id == id).firstOrNull;
        if (extra == null) return true;
        unit += extra.priceCents;
      }
      if (unit != line.unitCents) return true;
    }
    return false;
  }

  Map<String, Object?> get stored => {
    'shop': partner.id,
    'step': step,
    'lines': [for (final line in lines) line.stored],
    'pickupName': pickupName,
    'pickupPhone': pickupPhone,
    'pickupNote': pickupNote,
    'paymentMethod': paymentMethod,
    if (scheduledFor case final at?) 'scheduledFor': Timestamp.fromDate(at),
    'savedAt': FieldValue.serverTimestamp(),
  };
}

/// A trimmed non-empty string, or null. A field cleared to `''` from the admin
/// side means "go back to the built-in" or "print nothing", never a blank
/// line where a name or picture goes.
///
/// Top-level rather than a method on either [BrewShop] or [BrewMenuItem],
/// since [BrewCounter._readShop] and [BrewMenuItem.read] both need it and
/// neither owns the other.
String? _trimmedOrNull(Object? value) => switch (value) {
  final String text when text.trim().isNotEmpty => text.trim(),
  _ => null,
};

/// The stored base64 as bytes, or null if there is none or it will not decode.
///
/// Tolerates a `data:image/png;base64,` prefix as well as bare base64: the
/// app writes bare, but a data URI is what anything else that ever writes one
/// of these fields is likely to produce, and half-reading a picture is worse
/// than accepting both spellings.
///
/// A malformed value returns null rather than throwing — one shop's corrupt
/// logo, or one item's corrupt picture, is not worth the screen it sits on.
Uint8List? _decodeBase64Image(String? encoded) {
  if (encoded == null) return null;
  final comma = encoded.indexOf(',');
  final payload = encoded.startsWith('data:') && comma != -1
      ? encoded.substring(comma + 1)
      : encoded;
  try {
    return base64Decode(payload.trim());
  } catch (error) {
    debugPrint('QuickBrew → unreadable image: $error');
    return null;
  }
}

/// The counter: everything the signed-in screens read out of Firestore, and
/// nothing else.
///
/// The same bargain [BrewAuth](brew_auth.dart) strikes for accounts — no screen
/// imports `cloud_firestore`, and every read arrives as a plain Dart object or a
/// stated absence. Errors are logged and swallowed at this boundary rather than
/// escaping into a `StreamBuilder`, because a permission-denied on the hours
/// lookup should cost the reader the word "Open", not the home screen.
///
/// ## The documents this reads
///
/// ```
/// shops/coffee-shop-a          { open: true, logoUrl: "https://…",
///                                payQrBase64: "…" }
/// shops/coffee-shop-b          { open: false }
///
/// shops/{shop}/menu/{autoId}   { name: "Iced Latte",
///                                description: "Double shot over ice",
///                                size: "medium",
///                                priceCents: 450,
///                                sort: 10,
///                                imageBase64: "…" }
///
/// shops/{shop}/addons/{autoId} { name: "Oat milk",
///                                priceCents: 4000,
///                                group: "Milk choice",
///                                sort: 10 }
///
/// orders/{autoId}              { uid: "<firebase uid>",
///                                shop: "coffee-shop-a",
///                                items: ["Iced Latte", "Croissant"],
///                                stage: "preparing",
///                                paymentMethod: "Scan to pay",
///                                receiptBase64: "…",
///                                etaLowMinutes: 10,
///                                etaHighMinutes: 15,
///                                placedAt: <server timestamp> }
///
/// drafts/{uid}                 { shop: "coffee-shop-a",
///                                step: "pickup",
///                                lines: [ { itemId, size, extraIds,
///                                           quantity, unitCents } ],
///                                pickupName / pickupPhone / pickupNote,
///                                paymentMethod: "Pay at counter",
///                                savedAt: <server timestamp> }
/// ```
///
/// `shops` and `menu` are only ever read here. `orders` and `drafts` are the two
/// this app writes, and they are different kinds of thing: an order is a promise
/// to a shop, a draft is a bookmark in the reader's own flow that no shop can
/// see. Until the two `shops` documents exist the cards say "Hours unavailable",
/// which is the truthful reading of an empty collection and is meant to be
/// noticed.
class BrewCounter {
  BrewCounter(this._db);

  /// Null when Firestore cannot be reached at all, for the same reason
  /// [BrewAuth.connect] returns null: the plugin is missing on this platform, or
  /// no Firebase app came up. The screens then show their absent states instead
  /// of the app failing to build.
  static BrewCounter? connect() {
    try {
      return BrewCounter(FirebaseFirestore.instance);
    } catch (error) {
      debugPrint('QuickBrew → Firestore unavailable: $error');
      return null;
    }
  }

  final FirebaseFirestore _db;

  String _currentUid(String fallbackUid) {
    String? currentUid;
    try {
      currentUid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      currentUid = null;
    }
    assert(
      currentUid == null || currentUid == fallbackUid,
      'User-owned Firestore access must use the authenticated uid.',
    );
    return currentUid ?? fallbackUid;
  }

  static const _shops = 'shops';
  static const _menu = 'menu';
  static const _addOns = 'addons';
  static const _orders = 'orders';
  static const _drafts = 'drafts';

  /// The most recent answer [shops] gave, or null before the first one lands.
  ///
  /// Every screen that draws a shop opens on [BrewShop.pending] — the enum's
  /// built-in "Drip & Co" under a "Checking hours" mark — because a card
  /// with no name at all is worse than a card with a placeholder one. The cost
  /// is that a reader arriving *mid-session* watches both cards correct
  /// themselves a beat after they appear, every single time, which does not read
  /// as loading: it reads as the app changing its mind about what the shops are
  /// called.
  ///
  /// This is what pays that back. The last snapshot is kept, so the next screen
  /// to mount can hand it straight to its `StreamBuilder` as `initialData` and
  /// paint the real names on its first frame. It is stale by at most one
  /// snapshot and is never what a screen renders *from* — the live stream still
  /// is, and it overwrites this within a frame or two of the screen appearing —
  /// so a shop renamed while nobody was looking is wrong for no longer than it
  /// would have been blank.
  ///
  /// Null until something has listened. See `_shopsWarm` in main.dart, which is
  /// what makes sure that happens during the splash rather than in front of the
  /// reader.
  List<BrewShop>? get lastShops => _lastShops;
  List<BrewShop>? _lastShops;

  /// Both partners with live hours, in enum order, forever.
  ///
  /// The list is built from the enum and *annotated* with the snapshot rather
  /// than built from the snapshot: a `shops` collection that is empty, partial,
  /// or has picked up a third document cannot change how many cards the home
  /// screen shows or which order they sit in. Equal billing for the two partners
  /// is a layout fact, not something the database gets a vote on.
  Stream<List<BrewShop>> shops() {
    return _db
        .collection(_shops)
        .snapshots()
        .map((snapshot) {
          final docs = {
            for (final doc in snapshot.docs) doc.id: doc.data(),
          };
          final shops = [
            for (final partner in BrewPartner.values)
              _readShop(partner, docs[partner.id]),
          ];
          // Written on the way past rather than by each subscriber, so every
          // stream this hands out feeds the same cache — including the one in
          // main.dart that exists only to fill it. See [lastShops].
          _lastShops = shops;
          return shops;
        })
        .handleError((Object error) {
          debugPrint('QuickBrew → hours unavailable: $error');
        });
  }

  static BrewShop _readShop(BrewPartner partner, Map<String, Object?>? data) {
    final url = data?['logoUrl'];
    return BrewShop(
      partner: partner,
      // A missing document and a document without a boolean `open` are the same
      // thing from here: nobody has said. Only a real `false` reads as Closed.
      status: switch (data?['open']) {
        true => BrewShopStatus.open,
        false => BrewShopStatus.closed,
        _ => BrewShopStatus.unknown,
      },
      name: _trimmedOrNull(data?['name']),
      description: _trimmedOrNull(data?['description']),
      logoUrl: url is String && url.trim().isNotEmpty ? url.trim() : null,
      logoBytes: _decodeBase64Image(_trimmedOrNull(data?['logoBase64'])),
      payQrBytes: _decodeBase64Image(_trimmedOrNull(data?['payQrBase64'])),
    );
  }

  /// Every order the reader is currently waiting on, newest first.
  ///
  /// Queried on `uid` alone and then filtered and sorted here. The obvious query
  /// — equality on uid, `whereIn` on stage, `orderBy placedAt` —
  /// needs a composite index that has to be created in the console before it
  /// returns anything, and a home screen whose main card silently stays empty
  /// until someone notices an index error in the logs is not worth the round
  /// trip it saves. A reader has a handful of orders.
  ///
  /// Newest first, so an order placed while an older one is still open sorts
  /// ahead of it. Orders with no `placedAt` sort *first*: the server stamp is
  /// written asynchronously, so a just-placed order briefly has none, and
  /// treating a null as ancient would flip it to the back of the list for a
  /// frame. See [_newestFirst], which is where that happens — this sentence
  /// used to say "last", which is the opposite of both the code below it and
  /// the reason given for it in the same breath.
  Stream<List<BrewOrder>> activeOrders(String uid) {
    return _ordersFor(_currentUid(uid)).map((orders) {
      return orders.where((order) => order.stage.isActive).toList();
    });
  }

  /// Every order this reader has placed, newest first. The Orders tab.
  Stream<List<BrewOrder>> orders(String uid) => _ordersFor(_currentUid(uid));

  /// One order, live — what [OrderTrackingScreen] watches after Track order.
  ///
  /// Filtered out of the same [_ordersFor] read the Orders tab and the home
  /// screen's own card already subscribe to, rather than a `doc(id).snapshots()`
  /// of its own: Firestore keeps one watch per query, so a reader who opens
  /// tracking while Home is still mounted behind it rides the subscription
  /// that is already open instead of paying for a second one.
  ///
  /// Null once the order stops being in this reader's list at all — which
  /// Firestore rules make the only way it can disappear, since nothing in this
  /// app deletes an order — so the screen can tell "not this reader's" apart
  /// from "still loading" the same way every other stream on it does.
  Stream<BrewOrder?> order(String uid, String id) {
    return _ordersFor(_currentUid(uid)).map(
      (orders) => orders.where((order) => order.id == id).firstOrNull,
    );
  }

  /// What one shop sells, in the order the shop put it in.
  ///
  /// Ordered by an explicit `sort` field rather than by name: a menu is a
  /// sequence the shop chose — espresso before filter, drinks before food — and
  /// alphabetising it would reorganise their board for them.
  ///
  /// Sorted here rather than with `orderBy('sort')`, which drops every document
  /// that has no `sort` field instead of putting it last. A menu that silently
  /// hides the items nobody got round to numbering is the worse failure.
  ///
  /// A failed read is logged and then rethrown, so it reaches the listener as an
  /// error rather than as silence. Logging alone swallows it: the stream then
  /// never emits and never closes, and a `StreamBuilder` holding it sits on a
  /// null snapshot forever — which is why a refused board used to read as
  /// "Loading the board…" with no end. See the same rethrow in [_ordersFor].
  Stream<List<BrewMenuItem>> menu(BrewPartner partner) {
    return _db
        .collection(_shops)
        .doc(partner.id)
        .collection(_menu)
        .snapshots()
        .map((snapshot) {
          final items = [
            for (final doc in snapshot.docs)
              ?BrewMenuItem.read(doc.id, doc.data()),
          ];
          items.sort(BrewMenuItem.byBoardOrder);
          return items;
        })
        .handleError((Object error) {
          debugPrint('QuickBrew → ${partner.id} menu unavailable: $error');
          throw error;
        });
  }

  /// What one shop will add to a drink, in the order the shop put it in.
  ///
  /// The same shape as [menu] and sorted the same way, because it is the same
  /// kind of fact: a list the shop chose the order of. An empty collection is
  /// the truthful reading of a shop that sells no extras, and the wizard draws
  /// no add-ons section at all rather than an empty heading.
  Stream<List<BrewAddOn>> addOns(BrewPartner partner) {
    return _db
        .collection(_shops)
        .doc(partner.id)
        .collection(_addOns)
        .snapshots()
        .map((snapshot) {
          final addOns = [
            for (final doc in snapshot.docs) ?BrewAddOn.read(doc.id, doc.data()),
          ];
          addOns.sort(BrewAddOn.byBoardOrder);
          return addOns;
        })
        .handleError((Object error) {
          debugPrint('QuickBrew → ${partner.id} add-ons unavailable: $error');
          throw error;
        });
  }

  /// The ceiling on an encoded receipt, in characters of base64.
  ///
  /// Smaller than [BrewAdmin.maxLogoChars]'s 700KB, because this one shares its
  /// document with the order itself — the lines, the pickup fields, the stamps —
  /// and a Firestore document may not exceed 1 MiB in total. 500KB of base64 is
  /// about 375KB of picture, which is far more than the 1024px-at-quality-70
  /// screenshot the wizard actually uploads, and still leaves the rest of the
  /// order a wide margin.
  static const maxReceiptChars = 500 * 1024;

  /// Writes one order and returns null, or the sentence to show the reader.
  ///
  /// The one write this class does. Everything else here reads, and the split is
  /// deliberate: an order is the only thing a customer creates, so it is the
  /// only method that can fail in a way the reader has to be told about — hence
  /// a returned message rather than the `debugPrint`-and-swallow every stream
  /// above does. A failed read costs a word on a card; a failed order costs the
  /// reader their coffee, and they need to know it did not go through.
  ///
  /// `stage` is written as [BrewOrderStage.received], which is where every order
  /// starts, and `placedAt` as a server stamp rather than a device clock — the
  /// orders list sorts on it, and a phone with a wrong clock would otherwise
  /// file today's order under last year.
  ///
  /// `items` is the same list of plain strings [BrewOrder.read] expects back,
  /// so an order this writes is one the home screen can read without a
  /// migration.
  ///
  /// `receipt` is the picture of the reader's transfer, already downscaled by
  /// whoever picked it — see [maxReceiptChars] for the ceiling and why an
  /// oversized one is refused here with a sentence rather than by the server
  /// with an INVALID_ARGUMENT nobody can act on.
  Future<String?> placeOrder({
    required String uid,
    required BrewPartner partner,
    required List<String> items,
    required int totalCents,
    required String pickupName,
    required String pickupPhone,
    String? pickupNote,
    required String paymentMethod,
    Uint8List? receipt,
    DateTime? scheduledFor,
  }) async {
    if (items.isEmpty) return 'That order has nothing in it.';

    // Encoded before the write rather than inside it, so a picture that cannot
    // fit is refused without a round trip — and so the sentence the reader gets
    // names the actual problem instead of the generic failure below.
    String? encodedReceipt;
    if (receipt != null) {
      encodedReceipt = base64Encode(receipt);
      if (encodedReceipt.length > maxReceiptChars) {
        final kb = (encodedReceipt.length / 1024).round();
        return 'That receipt is too large at ${kb}KB. Upload a smaller picture.';
      }
    }

    try {
      final ownerUid = _currentUid(uid);
      await _db.collection(_orders).add({
        'uid': ownerUid,
        'shop': partner.id,
        'items': items,
        'stage': BrewOrderStage.received.name,
        'totalCents': totalCents,
        'pickupName': pickupName,
        'pickupPhone': pickupPhone,
        if (pickupNote != null && pickupNote.isNotEmpty) 'pickupNote': pickupNote,
        'paymentMethod': paymentMethod,
        // Absent rather than null on an order with no receipt, the same way
        // `scheduledFor` is below: nothing was uploaded, which is not the same
        // fact as an upload that came back empty.
        'receiptBase64': ?encodedReceipt,
        // Absent, not null, for an order to be made now — see
        // [BrewOrder.scheduledFor].
        if (scheduledFor case final at?) 'scheduledFor': Timestamp.fromDate(at),
        // The window the shop quotes for a pickup order. Written here rather
        // than left absent so the home screen's card has an estimate to print
        // from the moment the order lands, instead of a card that says nothing
        // until someone at the counter fills one in.
        'etaLowMinutes': 10,
        'etaHighMinutes': 15,
        'placedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (error) {
      debugPrint('QuickBrew → order not placed: $error');
      return 'We could not place that order. Check your connection and try again.';
    }
  }

  /// The order this reader started and left, or null.
  ///
  /// A stream rather than a one-shot read, so the home screen's card appears the
  /// moment a draft is saved and goes the moment it is resumed or discarded —
  /// the reader walks back out of the wizard onto the screen the card is on, and
  /// a card that needed a refresh to notice would still be offering to resume an
  /// order they are now holding.
  Stream<BrewDraft?> draft(String uid) {
    return _db
        .collection(_drafts)
        .doc(_currentUid(uid))
        .snapshots()
        .map((doc) {
          final data = doc.data();
          return data == null ? null : BrewDraft.read(data);
        })
        .handleError((Object error) {
          debugPrint('QuickBrew → draft unavailable: $error');
        });
  }

  /// Saves the order in progress, replacing whatever was there.
  ///
  /// Returns a sentence on failure like [placeOrder] does, and for the same
  /// reason: the reader pressed a button that promised to keep their order, and
  /// a save that silently failed would lose the cart they were told was safe.
  ///
  /// One document per uid, overwritten — see [BrewDraft] on why there is not a
  /// list of these.
  Future<String?> saveDraft({
    required String uid,
    required BrewDraft draft,
  }) async {
    if (draft.lines.isEmpty) return 'That order has nothing in it yet.';
    try {
      final ownerUid = _currentUid(uid);
      await _db.collection(_drafts).doc(ownerUid).set({
        ...draft.stored,
        'uid': ownerUid,
      });
      return null;
    } catch (error) {
      debugPrint('QuickBrew → draft not saved: $error');
      return 'We could not save that order. Check your connection and try again.';
    }
  }

  /// Throws the saved order away.
  ///
  /// Errors are swallowed here rather than returned, unlike [saveDraft]. A
  /// delete that fails leaves the card on the home screen, which is a state the
  /// reader can see and press again — where a failed *save* leaves them
  /// believing something was kept that was not.
  Future<void> discardDraft(String uid) async {
    try {
      await _db.collection(_drafts).doc(_currentUid(uid)).delete();
    } catch (error) {
      debugPrint('QuickBrew → draft not discarded: $error');
    }
  }

  /// Every order filed under one uid, newest first.
  ///
  /// Rethrows a failed read for the reason [menu] gives: a swallowed error is
  /// indistinguishable from a read that has not answered yet, and the bell's
  /// panel would spin on "Looking up your orders…" rather than say what went
  /// wrong.
  Stream<List<BrewOrder>> _ordersFor(String uid) {
    return _db
        .collection(_orders)
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final orders = [
            // Null-aware element: a document this app cannot make an order out of
            // is dropped, and drops nothing else with it.
            for (final doc in snapshot.docs) ?BrewOrder.read(doc.id, doc.data()),
          ];
          orders.sort(_newestFirst);
          return orders;
        })
        .handleError((Object error) {
          debugPrint('QuickBrew → orders unavailable: $error');
          throw error;
        });
  }

  /// Drops the warm cache that exists only to hide the first reload frame.
  void clearCache() {
    _lastShops = null;
  }

  /// The same stream, except that a listener arriving late is handed the most
  /// recent event immediately instead of waiting for the next one.
  ///
  /// Every stream on this class is a Firestore `snapshots()` — a *broadcast*
  /// stream, which by definition replays nothing. Its controller starts the
  /// native listener when the first subscriber arrives (which emits the
  /// current answer straight from the cache) and stops it when the last one
  /// leaves. That is exactly right for one listener and quietly wrong for
  /// several: a second listener that subscribes while the first is still
  /// attached starts the controller from nowhere — no native listen, so no
  /// emission — and sits on a null snapshot until something in the collection
  /// happens to change.
  ///
  /// Which is what the Orders tab did. One `orders` stream is held for the
  /// life of home_screen.dart and read by three panels, and the tab cross-fade
  /// keeps the outgoing panel mounted for its whole 420ms — so the incoming
  /// panel *always* subscribed while the one it replaced was still listening,
  /// and always missed the reply. "Looking up your orders…" then stayed until
  /// an order changed under it. Leaving the tab and coming back looked like a
  /// fix because it was the one sequence that empties the listener list: the
  /// last subscriber cancels, the controller stops, and the next subscribe
  /// starts it over and gets the cache.
  ///
  /// [Stream.multi] rather than a broadcast controller, because the cached
  /// event has to go to *one* new listener — a broadcast controller can only
  /// add to all of them, which would replay the history into everybody
  /// already watching. The recording rides on the upstream events themselves,
  /// so nothing here holds a subscription open on its own: when the last
  /// listener cancels, so does the Firestore read.
  static Stream<T> latest<T>(Stream<T> source) {
    var known = false;
    late T current;
    final recorded = source.map((event) {
      current = event;
      known = true;
      return event;
    });

    return Stream<T>.multi(
      (controller) {
        if (known) controller.add(current);
        final subscription = recorded.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
        controller.onPause = subscription.pause;
        controller.onResume = subscription.resume;
      },
      isBroadcast: true,
    );
  }

  /// Descending by `placedAt`, with an unstamped order counted as the newest
  /// thing there is — which is what it almost always is. See [_ordersFor].
  static int _newestFirst(BrewOrder a, BrewOrder b) {
    final (left, right) = (a.placedAt, b.placedAt);
    if (left == null && right == null) return 0;
    // Negative puts `a` first, so a null on the left sorts ahead of any stamp.
    if (left == null) return -1;
    if (right == null) return 1;
    return right.compareTo(left);
  }
}
