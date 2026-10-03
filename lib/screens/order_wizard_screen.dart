import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Uint8List, debugPrint;
import 'package:flutter/material.dart' show Material, showModalBottomSheet;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/brew_buttons.dart';
import '../widgets/brew_field.dart';
import '../widgets/brew_reveal.dart';
// Only [BrewWordmarkRow] and [brewBlockGap] — this screen lays itself out
// rather than using BrewSheet, because it owns a pinned footer the sheet's
// single scroll view has no place for.
import '../widgets/brew_sheet.dart';
// The QR and the uploaded receipt are both bounded bytes in a hairline frame —
// the same widget the board already draws its pictures with.
import '../widgets/menu_item_image.dart';
import '../widgets/stagger.dart';

/// The buying flow, as one screen the reader walks forward through.
///
/// Six steps, in the order the flowchart names them: pick the coffee and its
/// size, customise it, add it to the cart, enter pickup details, choose how to
/// pay, confirm. A wizard rather than one long form because those are six
/// different kinds of question — a picker, a set of options, a review, two
/// forms and a summary — and stacking them on one page would ask the reader to
/// scroll past decisions they have already made to reach the one they are on.
///
/// ## Why the cart lives here
///
/// The cart is held by this screen's state and dies with the route. The app has
/// no cart tab — see the note on the navigation in
/// [HomeScreen](home_screen.dart) — so a cart that outlived this screen with no
/// way back to it would be a basket the reader could fill and then lose. Held
/// for the length of one order, it is what lets Add another return to step one
/// with the first drink already banked, which is the whole reason the flowchart
/// has an add-to-cart step rather than going straight from customise to pickup.
///
/// ## Save for later
///
/// The one exception to that, and it is an exception with a way back. Save for
/// later writes the whole flow — lines, pickup details, payment choice and which
/// step the reader was on — to `drafts/{uid}` and pops. The home screen then
/// carries a Saved order card that reopens this screen exactly where they left
/// it. See [BrewDraft], and [_restore] for the one thing a resumed draft cannot
/// promise: its prices are re-read from the board, not restored, so a shop that
/// repriced overnight is charged at today's figure and the reader is told on the
/// cart step rather than at the confirm button.
///
/// ## What it can and cannot promise
///
/// The last step writes a real order through [BrewCounter.placeOrder], which is
/// what puts it on the home screen's active-order card. Payment is still not
/// *taken* by this app — there is no processor behind it — but it is no longer
/// merely promised either: step five shows the shop's own QR, the reader pays
/// against it in whatever app they bank with, and the picture of that transfer
/// is uploaded here and attached to the order. The forward button is held until
/// it is, because that picture is the only evidence the counter will ever have.
///
/// The exception is a shop whose admin has not uploaded a code — see
/// [StoreConfigScreen](admin/store_config_screen.dart). There is nothing to
/// scan, so nothing is asked for, and the order is filed as one to settle at the
/// counter. Holding a reader at an upload for a payment they had no way to make
/// would be a dead end, and inventing a code would be worse.
class OrderWizardScreen extends StatefulWidget {
  const OrderWizardScreen({
    super.key,
    required this.shop,
    required this.item,
    this.session,
    this.counter,
    this.draft,
    this.pickReceipt,
  });

  /// Whose board this order is from. Carried whole for its live name, the same
  /// reason [MenuScreen](menu_screen.dart) takes one.
  final BrewShop shop;

  /// The item the reader pressed Buy on. Step one opens on it, and it is the
  /// first thing in the cart once they have sized it.
  ///
  /// On a resumed draft this is the first line's item instead, resolved by
  /// whoever opened the screen — the reader did not press Buy on anything, so
  /// what step one opens on is the drink they were already ordering.
  final BrewMenuItem item;

  /// The order to pick back up, or null for a fresh one.
  ///
  /// Its lines are rebuilt against the live menu in [_restore] rather than
  /// trusted as saved, which is why this arrives beside [item] rather than
  /// instead of it: the draft names item ids, and resolving them needs the board
  /// this screen does not read.
  final BrewDraft? draft;

  /// Who is ordering. Null means nobody is signed in, which this screen states
  /// on the confirm step rather than discovering at the moment of the write —
  /// a reader who has filled in six steps should not be told at the end that
  /// none of it could be sent.
  final BrewSession? session;

  /// Null when Firestore never came up. Same treatment as a null session.
  final BrewCounter? counter;

  /// How the payment step gets the receipt's bytes. Null uses the gallery.
  ///
  /// A seam rather than a hard call to [ImagePicker], because the receipt is the
  /// one thing on this screen that *gates* a step, and a gate whose only key is
  /// a native platform channel is a gate no widget test can turn — which would
  /// leave the most consequential rule in the flow covered by nothing. Returning
  /// null stands for backing out of the picker.
  ///
  /// Nothing in the app passes this; it exists so the rule can be tested through
  /// the same controls a reader presses.
  final Future<Uint8List?> Function()? pickReceipt;

  static Route<void> route({
    bool reduced = false,
    required BrewShop shop,
    required BrewMenuItem item,
    BrewSession? session,
    BrewCounter? counter,
    BrewDraft? draft,
  }) {
    final duration = reduced ? Duration.zero : BrewMotion.transit;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          OrderWizardScreen(
        shop: shop,
        item: item,
        session: session,
        counter: counter,
        draft: draft,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  State<OrderWizardScreen> createState() => _OrderWizardScreenState();
}

/// The six steps, in flowchart order.
///
/// An enum rather than an int because every one of the four things this screen
/// needs per step — the eyebrow, the heading, what the forward button says,
/// whether it is allowed to be pressed — is a fact about *which* step it is,
/// and reading those off `switch (_step)` keeps them in one place each instead
/// of in six branches of a builder. The index doubles as the progress, the same
/// way [BrewOrderStage] does for the order that comes out of this.
enum _Step {
  select('Step 1 of 6', 'Select coffee & size'),
  customise('Step 2 of 6', 'Customise your drink'),
  cart('Step 3 of 6', 'Your cart'),
  pickup('Step 4 of 6', 'Enter pickup details'),
  // Not "Choose payment method" any more: there is nothing to choose. The step
  // is a task — scan the code, upload what you paid — and a heading naming a
  // decision the reader is not being offered would be the screen describing an
  // older version of itself. See [_paymentLabel].
  payment('Step 5 of 6', 'Pay for your order'),
  confirm('Step 6 of 6', 'Confirm order');

  const _Step(this.eyebrow, this.heading);

  final String eyebrow;
  final String heading;

  static _Step get first => _Step.values.first;

  _Step? get next =>
      index + 1 < _Step.values.length ? _Step.values[index + 1] : null;

  _Step? get previous => index > 0 ? _Step.values[index - 1] : null;

  /// The step a saved draft names, or the cart if it names one this build does
  /// not have.
  ///
  /// The cart rather than step one, because the cart is the only step that can
  /// always be drawn from saved lines alone — it needs no size held open and no
  /// form filled in — and because a reader resuming an order wants to see what
  /// is in it before being asked anything else. [_Step.confirm] resumes at
  /// [_Step.payment] instead: the summary step's whole job is to show figures
  /// the reader is about to commit to, and those may have been re-costed since
  /// they left, so it is one press away rather than under their thumb.
  static _Step restore(String name) {
    final wanted = name.trim().toLowerCase();
    for (final step in _Step.values) {
      if (step.name == wanted) {
        return step == _Step.confirm ? _Step.payment : step;
      }
    }
    return _Step.cart;
  }
}

/// The add-ons this shop offers, as one section per heading it files them
/// under.
///
/// Read from `shops/{shop}/addons` rather than hard-coded — see [BrewAddOn].
/// They used to be an enum in this file, which meant both partners printed one
/// shop's board and neither could reprice a thing without a release. Now each
/// shop owns its own list, an admin edits it on
/// [AdminAddOnsScreen](admin/admin_addons_screen.dart), and a shop with an
/// empty collection simply has no add-ons section on this step.
///
/// The grouping is what makes twenty options readable: twenty rows under one
/// EXTRAS heading is a list the reader scrolls past; the same twenty under six
/// headings is six short decisions. Ungrouped add-ons get a section of their
/// own at the foot rather than being dropped.
typedef _ExtraSectionData = (String heading, List<BrewAddOn> options);

/// The sections to draw, in board order, with anything ungrouped last.
List<_ExtraSectionData> _extraSections(List<BrewAddOn> addOns) {
  final sections = <_ExtraSectionData>[
    for (final group in BrewAddOn.groupsOf(addOns))
      (group, BrewAddOn.inGroup(addOns, group)),
  ];
  final ungrouped = BrewAddOn.ungroupedOf(addOns);
  if (ungrouped.isNotEmpty) sections.add(('Extras', ungrouped));
  return sections;
}

/// What goes on the order document's `paymentMethod`, and what the summary
/// prints.
///
/// There is one method now — the shop's own QR — where there used to be a choice
/// of three. The other two were a choice in name only: pay-at-counter and
/// card-on-pickup both meant "this app took nothing and somebody at the till
/// will sort it out", which is not a decision worth a step of a wizard. A single
/// method with a code to scan and a receipt to show is one the reader actually
/// acts on before they press Confirm.
///
/// A constant rather than an enum because there is nothing left to choose
/// between; if a second method ever comes back, it comes back as an enum again.
///
/// Nothing migrates the orders already on record. An order placed under the old
/// step still reads "Pay at counter", "GCash" or "Card on pickup" wherever it is
/// printed, because that is what was true when it was placed — relabelling a
/// past receipt to say the reader scanned a code they were never shown would be
/// the one lie this flow has avoided. The admin queue prints
/// [BrewOrder.paymentMethod] verbatim, which is what makes that work without a
/// lookup table here.
const _paymentLabel = 'Scan to pay';

/// One drink as the reader configured it, priced.
///
/// Immutable and built once at the add-to-cart step: a line the reader can
/// remove but not edit in place. Editing would need the wizard to walk
/// backwards into a step already left behind and come back out holding a
/// different line, which is a second flow through the same six screens for a
/// case the reader can already handle by removing the line and adding it again.
class _CartLine {
  const _CartLine({
    required this.item,
    required this.size,
    required this.extras,
    required this.quantity,
    required this.unitCents,
  });

  final BrewMenuItem item;

  /// Null for an item the shop prices flat — a muffin has no size, and
  /// inventing one would put a word on the receipt the counter cannot fill.
  final BrewItemSize? size;

  /// In board order, not the order the reader happened to tap them: two
  /// identical drinks configured in a different sequence should produce the
  /// same line, or the counter reads them as two different orders. The list is
  /// built from the shop's own sorted add-ons — see [_draftExtras].
  final List<BrewAddOn> extras;

  final int quantity;

  /// One drink including its extras, before quantity.
  final int unitCents;

  int get totalCents => unitCents * quantity;

  /// The line as the order document carries it and as the counter reads it:
  /// "2× Iced Latte (Large) + Extra shot, Oat milk". One string, because
  /// that is the shape [BrewOrder.items] already stores and the shape the home
  /// screen's card already prints.
  String get orderLine {
    final qualifiers = <String>[if (size != null) size!.label];
    final buffer = StringBuffer();
    if (quantity > 1) buffer.write('$quantity× ');
    buffer.write(item.name);
    if (qualifiers.isNotEmpty) {
      buffer.write(' (${qualifiers.join(', ')})');
    }
    if (extras.isNotEmpty) {
      buffer.write(' + ${extras.map((extra) => extra.name).join(', ')}');
    }
    return buffer.toString();
  }

  /// This line as the draft document stores it: the choices that made it, not
  /// the priced result. See [BrewDraftLine] for why the price travels only as
  /// something to compare against.
  BrewDraftLine get draftLine => BrewDraftLine(
        itemId: item.id,
        size: size,
        extraIds: [for (final extra in extras) extra.id],
        quantity: quantity,
        unitCents: unitCents,
      );

  /// The qualifiers alone, for the cart row that already prints the name above
  /// them. Empty string when there is nothing to qualify.
  String get detailLine {
    final parts = <String>[
      if (size != null) size!.label,
      for (final extra in extras) extra.name,
    ];
    return parts.join(' · ');
  }
}

class _OrderWizardScreenState extends State<OrderWizardScreen> {
  _Step _step = _Step.first;

  /// What step one and two are building. Reset to the defaults for the current
  /// [_draftItem] every time the reader returns to step one, so Add another
  /// starts from a clean drink rather than from the last one's extras.
  late BrewMenuItem _draftItem;
  BrewItemSize? _size;

  /// The chosen add-ons, held as document ids rather than as [BrewAddOn]s.
  ///
  /// The list behind them is a live stream: an admin repricing oat milk while
  /// the reader is on this step hands us a new object for the same add-on, and
  /// a set of objects would then hold a stale copy that prices the drink at
  /// yesterday's figure. Ids survive that — every read resolves against the
  /// current snapshot, so the price charged is the price showing.
  ///
  /// An id whose add-on has since been deleted resolves to nothing and is
  /// simply not charged for, which is the truthful reading: the shop has
  /// stopped selling it.
  final Set<String> _extraIds = <String>{};

  /// This shop's add-ons, as the last snapshot had them. Empty both before the
  /// first one lands and for a shop that sells no extras — the customise step
  /// draws no add-ons section in either case, which is right for the second
  /// and briefly right for the first.
  List<BrewAddOn> _addOns = const [];

  Stream<List<BrewAddOn>>? _addOnStream;

  /// Null until the board is needed. Two things need it: a resumed draft, whose
  /// saved lines name item ids this turns back into drinks (see [_restore]), and
  /// Add another drink, which opens step one as a picker over the whole board
  /// rather than over the one item the reader arrived on. Subscribed on demand
  /// in [_watchMenu] so a straight-through order opens no listener it never
  /// reads.
  Stream<List<BrewMenuItem>>? _menuStream;

  /// The shop's board as the last snapshot had it, for the step one picker.
  /// Empty before the first one lands, which [_selectBody] draws as the waiting
  /// line rather than as an empty board.
  List<BrewMenuItem> _menu = const [];

  /// This shop as of the last snapshot, for the one field on it that a
  /// checkout cannot use a stale reading of: the payment QR.
  ///
  /// [widget.shop] is a snapshot taken on the home screen and carried down
  /// through the menu, which is fine for a name and a logo — those change
  /// between releases, not between screens. The QR is different in kind: it is
  /// what the reader is about to pay against, and it is also the gate on this
  /// step. A shop whose admin uploaded a code while the reader was choosing a
  /// size would otherwise show them "no code on file" and let them past the
  /// upload; one that removed a code would hold them at a picture that no
  /// longer resolves anywhere.
  ///
  /// Falls back to [widget.shop] until the first snapshot lands, so the step
  /// draws from the reading the rest of the app is already using rather than
  /// from nothing.
  StreamSubscription<List<BrewShop>>? _shopSubscription;
  BrewShop? _liveShop;

  BrewShop get _shop => _liveShop ?? widget.shop;

  /// The code to pay against, or null for a shop that has not uploaded one.
  Uint8List? get _shopQr => _shop.payQrBytes;

  /// How many orders this reader already has sitting at a stage other than
  /// completed or declined, as of the last snapshot. Null until the first one
  /// lands, which [_canPlaceOrder] reads as "not known yet" rather than as
  /// zero, so a reader is never waved through on a count this screen has not
  /// actually seen.
  int? _activeOrderCount;

  StreamSubscription<List<BrewOrder>>? _activeOrdersSubscription;

  /// True once the reader has pressed Add another drink, for as long as they are
  /// on the drink it started.
  ///
  /// What it changes is step one: the first drink was chosen on the board they
  /// pressed Buy on, so that step only confirms it and asks the size, but a
  /// second drink was chosen nowhere yet — sending them back to the menu screen
  /// to pick it would leave this cart behind, so the picker comes to them.
  /// Cleared on [_addDraftToCart], because the line is banked and the next thing
  /// stepped back into is that line's own drink.
  bool _picking = false;

  /// True until a resumed draft's lines have been rebuilt.
  ///
  /// Both streams have to have answered before that can happen — a line's price
  /// is its item's size price plus its add-ons' surcharges — so this is what
  /// keeps the cart step from drawing an empty basket for the frame or two
  /// between mounting and the second snapshot landing.
  bool _restoring = false;

  /// Which add-ons section is expanded, or null for none. Held as the heading's
  /// own name rather than an index, for the same reason the menu screens hold
  /// their category that way: the list under it can change.
  String? _openGroup;

  int _quantity = 1;

  final List<_CartLine> _cart = <_CartLine>[];

  /// The most lines one order can hold.
  ///
  /// This build is early-dev: the counter side of a cart this size has not
  /// been exercised yet, so the cap exists to keep a reader from finding that
  /// out for us. [_addDraftToCart] refuses past it and shows [_CartCapSheet]
  /// instead of banking a sixth line.
  static const _maxCartLines = 5;

  /// How many drinks are already banked, quantities counted.
  ///
  /// The figure the caps are actually about. [_maxCartLines] bounds how many
  /// *rows* the cart has, which is a different question and a much weaker one:
  /// a line can hold up to five drinks, so five lines is only five drinks in the
  /// one case where every line holds one.
  int get _bankedQuantity => _cart.fold(0, (sum, line) => sum + line.quantity);

  /// Whether there is room in this order for another drink at all.
  ///
  /// Both budgets, which is the point. [_quantityCap] already enforces the
  /// five-drink ceiling *within* one line — the stepper will not go past it —
  /// but a reader who banks four and then presses Add another drink starts a
  /// fresh line whose stepper begins at one, and nothing was checking that the
  /// order as a whole still had room. Four plus one plus one is six drinks
  /// assembled out of steppers that each refused to build six.
  ///
  /// Counted in drinks against [_maxActiveOrders] and in rows against
  /// [_maxCartLines], because both are real limits and the tighter one wins.
  bool get _hasRoomForAnother =>
      _cart.length < _maxCartLines && _quantityCap > 0;

  /// The lines that have been removed but are still collapsing.
  ///
  /// Identity, not equality: two identical drinks added twice are two distinct
  /// [_CartLine] objects and only one of them is going. `Set` over a `List` here
  /// is just membership — the order they leave in does not matter, only whether
  /// a given row is on its way out. See [_removeLine].
  final Set<_CartLine> _leaving = Set<_CartLine>.identity();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();

  /// Null until the reader has pressed forward off the pickup step once.
  ///
  /// Validation that fired on every keystroke would put an error under a phone
  /// number the reader is three digits into typing, which is the field telling
  /// them they are wrong before they have finished being right. Once they have
  /// submitted, it updates live — at that point they are fixing something, and
  /// a message that only refreshes on the next press is a message that lies.
  bool _pickupSubmitted = false;

  /// What the order document's `paymentMethod` gets, and what the summary
  /// prints.
  ///
  /// Derived rather than stored, and derived from the *shop* rather than from
  /// anything the reader picked, because it is no longer a choice — it is a fact
  /// about whether there was a code to pay against. A field set when the step
  /// was drawn could also disagree with a QR that arrived or left while the
  /// reader sat on the confirm step, and a receipt line saying one thing over an
  /// order filed as another is worse than either.
  ///
  /// A resumed draft's saved label is deliberately not carried through here for
  /// the same reason: what the reader agreed to yesterday is not what this
  /// screen is showing them today. Orders *already placed* keep their stored
  /// label untouched — see [_paymentLabel].
  String get _payment => switch (_shopQr) {
        null => 'Pay at counter',
        _ => _paymentLabel,
      };

  /// The picture of the transfer the reader uploaded, or null until they have.
  ///
  /// Held in memory for the length of this screen rather than written anywhere
  /// on the way past: it goes to Firestore as part of the order document in
  /// [_placeOrder], and an order that is never confirmed should leave no receipt
  /// behind for a payment the shop was never told about.
  ///
  /// This is also the gate on the payment step — see [_canAdvance]. Nothing here
  /// verifies it: it is a picture the reader chose, and the counter is what
  /// checks a payment actually landed.
  Uint8List? _receipt;

  /// Set while the picker or the encode is in flight, so a second tap cannot
  /// open two pickers.
  bool _pickingReceipt = false;

  /// What the last upload attempt had to say, or null. Shown under the control
  /// that took the press, the same bargain every other failure on this screen
  /// strikes.
  String? _receiptError;

  /// The tallest the payment QR may be drawn, in logical pixels.
  ///
  /// A ceiling on height alone — the width follows the picture's own ratio, for
  /// the reason [_qrSection] explains. 260 is a compromise between two things
  /// pulling opposite ways: a portrait GCash card needs the height to render its
  /// code at a scannable size, and this step also has to get the reader down to
  /// the receipt control the forward button is waiting on. Much taller and the
  /// upload falls below the fold on a 390×844 phone, which hides the one thing
  /// on the step that is actually required.
  static const _qrHeight = 260.0;

  /// Set while the QR is being written to the gallery, and what came back.
  bool _savingQr = false;

  /// The answer to Download this QR code — a sentence either way.
  ///
  /// Success is stated rather than silent: a download that writes a file
  /// somewhere the reader is not looking and says nothing is indistinguishable
  /// from a button that does not work, and they are about to leave for their
  /// banking app expecting to find the picture there.
  String? _qrNotice;

  /// Whether the reader chose a pickup time rather than ordering now.
  ///
  /// Held as a flag plus a day/minute pair rather than a `DateTime?`, because
  /// the two steppers below edit day and time-of-day independently and a
  /// DateTime would have to be taken apart and rebuilt on every press.
  /// [_scheduledFor] is the assembled reading everything else uses.
  bool _scheduling = false;

  /// Days from today, 0..[_maxScheduleDays].
  int _scheduleDays = 0;

  /// Minutes since midnight, in steps of [_scheduleStep].
  int _scheduleMinutes = 0;

  /// Set once the first switch to scheduling has seeded a sensible default,
  /// so toggling back and forth does not keep resetting a time the reader
  /// already dialled in.
  bool _scheduleInitialised = false;

  /// A week out is the longest a coffee order can sensibly be booked; past
  /// that it is a catering enquiry, which this screen is not.
  static const _maxScheduleDays = 7;

  /// Quarter hours. A counter reads "9:15", not "9:07".
  static const _scheduleStep = 15;

  /// The most orders one reader can have open — placed but not yet completed
  /// or declined — at once.
  ///
  /// This build is early-dev, the same reason [_maxCartLines] exists: a reader
  /// five orders deep in the counter's queue is a case nothing downstream of
  /// this screen has been proven against yet, so the wizard stops them here
  /// rather than at whatever breaks first past it.
  static const _maxActiveOrders = 5;

  /// Whether this reader is clear to place the order sitting in this wizard,
  /// by [_activeOrderCount] alone.
  ///
  /// True while the count is still unknown — the first snapshot has not
  /// landed, or there is no session or counter to ask — so a reader who is
  /// not signed in reaches the sign-in message [_placeOrder] already gives
  /// rather than this one, and a reader whose count has not arrived yet is
  /// not blocked by a number this screen has not actually seen.
  bool get _canPlaceOrder =>
      switch (_activeOrderCount) { final count? => count < _maxActiveOrders, null => true };

  /// How many of one drink the stepper on step two allows right now.
  ///
  /// Two separate budgets apply, and the stepper shows whichever leaves less
  /// room:
  ///
  /// - [_maxActiveOrders] against the orders already at the counter — five
  ///   open at once, counting the one being built here as one more. A reader
  ///   with none open gets the full five; one with three open gets two,
  ///   because three of the five are already spoken for. Unknown reads as
  ///   none open, the same optimism [_canPlaceOrder] shows while the first
  ///   snapshot is still in flight — a number this screen has not actually
  ///   seen yet should not narrow a control the reader can see.
  /// - [_maxActiveOrders] again, this time against the drinks already banked
  ///   into [_cart] this order — otherwise a reader could bank five lines at
  ///   quantity five apiece and place a single order for twenty-five drinks,
  ///   the same order-sized problem [_maxCartLines] exists for, just counted
  ///   in drinks instead of lines.
  ///
  /// Both floored at zero rather than letting the subtraction go negative: a
  /// reader at or past either cap has nothing left to give the stepper.
  int get _quantityCap {
    final activeOrderRoom =
        switch (_activeOrderCount) { final count? => _maxActiveOrders - count, null => _maxActiveOrders };
    final cartRoom = _maxActiveOrders - _bankedQuantity;
    return math.min(activeOrderRoom, cartRoom).clamp(0, _maxActiveOrders);
  }

  /// Set while [BrewCounter.placeOrder] is in flight, so the confirm button
  /// holds its pressed state and a second tap cannot place the order twice.
  bool _placing = false;

  /// The sentence the write failed with, or null. Shown on the confirm step,
  /// which is the only step that can fail.
  String? _failure;

  /// True once the order is in. The screen then shows the done state rather
  /// than a seventh step: the flowchart ends at confirm, and what follows is
  /// not a decision the reader makes.
  bool _placed = false;

  /// Set while [BrewCounter.saveDraft] is in flight, so Save for later holds and
  /// a second tap cannot write the draft twice.
  bool _saving = false;

  /// The sentence a failed save failed with, or null. Shown on the footer rather
  /// than the body, because the button that failed is in the footer and this is
  /// the answer to pressing it — every step can be saved from, so there is no one
  /// body to put it in.
  String? _saveFailure;

  /// Set once a resumed draft's lines cost something other than what was saved.
  ///
  /// Stated on the cart step rather than corrected silently. A reader who parked
  /// an order at ₱310 and comes back to one at ₱335 has to be told which figure
  /// is real before they are walked to a confirm button — see the note on
  /// [BrewDraft].
  bool _repriced = false;

  /// How many of a resumed draft's lines could not be rebuilt at all, because
  /// the shop has stopped selling them. Nothing to charge for and nothing to
  /// print, so they are dropped — and counted, so the cart step can say so.
  int _droppedLines = 0;

  @override
  void initState() {
    super.initState();
    _draftItem = widget.item;
    _size = _defaultSize(_draftItem);
    _nameController.text = widget.session?.name ?? '';
    // Subscribed once, for the same reason every other screen here does it in
    // initState: a stream built inside `build` would be a fresh Firestore
    // listener on every frame.
    _addOnStream = widget.counter?.addOns(widget.shop.partner);
    // Only needed to rebuild a draft's lines, so a fresh order does not open a
    // second listener on the board it already came from. Add another drink
    // opens one later, when the reader asks for a board to pick from.
    if (widget.draft != null) _watchMenu();

    // The shop itself, for the payment QR — see [_liveShop] for why this one
    // field cannot be read off the snapshot the reader arrived holding.
    _shopSubscription = widget.counter?.shops().listen((shops) {
      final shop = shops
          .where((shop) => shop.partner == widget.shop.partner)
          .firstOrNull;
      if (!mounted || shop == null) return;
      setState(() => _liveShop = shop);
    });

    // Watched for the length of this screen rather than checked once: a
    // reader can sit on the confirm step for a while, and an order of theirs
    // finishing at the counter while they are on it should reopen the door
    // this cap closed rather than leave them stuck behind a count that is no
    // longer true. See [_canPlaceOrder].
    final counter = widget.counter;
    final session = widget.session;
    if (counter != null && session != null) {
      _activeOrdersSubscription =
          counter.activeOrders(session.uid).listen((orders) {
        if (!mounted) return;
        setState(() {
          _activeOrderCount = orders.length;
          // Another order of this reader's landing mid-flow can pull
          // [_quantityCap] down below whatever the stepper was already
          // showing — a quantity of 5 with the cap now at 4 is a number the
          // stepper can no longer have produced, and a display that
          // disagrees with its own control is worse than one that quietly
          // settled to what the control still allows.
          if (_quantity > _quantityCap) {
            _quantity = _quantityCap == 0 ? 1 : _quantityCap;
          }
        });
      });
    }

    final draft = widget.draft;
    if (draft != null) {
      // Nothing to rebuild the lines from on a build with no Firestore, so the
      // wait would never end. The cart then opens empty and says so, which the
      // empty-cart state already does.
      _restoring = widget.counter != null;
      // Everything that does not need the board, now: the forms and the payment
      // choice are the reader's own words and restore exactly. The lines wait
      // for the menu — see [_restore].
      _step = _Step.restore(draft.step);
      _nameController.text = draft.pickupName.isEmpty
          ? widget.session?.name ?? ''
          : draft.pickupName;
      _phoneController.text = draft.pickupPhone;
      _noteController.text = draft.pickupNote;
      // The payment method is deliberately *not* restored — see [_payment], which
      // derives it from whether the shop has a code today rather than from what
      // was true when the draft was parked. Neither is the receipt: the picture
      // is proof of a payment made against a code, and a reader who parked an
      // order for a day should upload a fresh one rather than have this screen
      // re-present an old transfer as payment for today's order. The payment step
      // opens with nothing uploaded and says so.
      // A saved pickup time comes back as the day/minute pair the steppers
      // edit. A time that has passed while the draft sat restores as it was
      // saved — [_scheduleError] then says so rather than the screen silently
      // moving an appointment the reader made.
      if (draft.scheduledFor case final at?) {
        _scheduling = true;
        _scheduleInitialised = true;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        _scheduleDays = DateTime(at.year, at.month, at.day)
            .difference(today)
            .inDays
            .clamp(0, _maxScheduleDays);
        _scheduleMinutes = at.hour * 60 + at.minute;
      }
      // A draft resumed past the pickup step has already been through its
      // validation once, so the messages are live from the first frame rather
      // than waiting for a press the reader has already made.
      _pickupSubmitted = _step.index > _Step.pickup.index;
    }
  }

  @override
  void dispose() {
    _activeOrdersSubscription?.cancel();
    _shopSubscription?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Subscribes to the shop's board, once.
  ///
  /// Idempotent because both callers can happen in one order — a resumed draft
  /// whose reader then presses Add another drink — and a second assignment would
  /// be a second Firestore listener on the same collection. Does nothing on a
  /// build with no counter; [_selectBody] says so rather than waiting forever.
  void _watchMenu() {
    _menuStream ??= widget.counter?.menu(widget.shop.partner);
  }

  /// The board as step one's picker offers it: everything the shop sells, in
  /// board order, with the drink already being configured included.
  ///
  /// [widget.item] is folded in when the snapshot has not landed yet, so the
  /// picker opens on the drink the reader came from rather than on nothing —
  /// and folded in by id, so the board's own copy wins once it arrives.
  List<BrewMenuItem> get _pickable {
    if (_menu.any((item) => item.id == widget.item.id)) return _menu;
    return [widget.item, ..._menu];
  }

  /// The cheapest size, or null for a flat-priced item.
  ///
  /// Preselected rather than left empty so step one opens on a valid choice and
  /// the forward button is live from the first frame. Cheapest rather than
  /// medium because it is the only one of the three that is always present —
  /// a shop that prices only Small and Large has no medium to default to.
  static BrewItemSize? _defaultSize(BrewMenuItem item) =>
      item.sizeLines.isEmpty ? null : item.sizeLines.first.$1;

  /// The chosen add-ons resolved against the current snapshot, in board order.
  ///
  /// Board order rather than tap order, so two identical drinks produce the
  /// same order line — [_addOns] arrives already sorted by
  /// [BrewAddOn.byBoardOrder], and filtering preserves that. An id whose
  /// add-on has been deleted since it was chosen falls out here, which is what
  /// keeps a removed extra from being priced or printed on the receipt.
  List<BrewAddOn> get _draftExtras =>
      [for (final addOn in _addOns) if (_extraIds.contains(addOn.id)) addOn];

  /// What one of the current draft costs, extras included.
  ///
  /// Falls back to the flat price when the item has no sizes, and to zero when
  /// the shop has priced neither — an unpriced item still orders, and the
  /// counter settles it. Better than blocking the flow on a field the reader
  /// cannot fill.
  int get _draftUnitCents {
    final base = switch (_size) {
      final size? => _draftItem.sizePrices[size] ?? 0,
      null => _draftItem.priceCents ?? 0,
    };
    return base + _draftExtras.fold(0, (sum, extra) => sum + extra.priceCents);
  }

  /// The lines that are actually being bought — everything in the cart that is
  /// not on its way out of it.
  ///
  /// This, rather than [_cart], is what the total, the gate and the order
  /// document are all read off. A line the reader has pressed Remove on is gone
  /// as far as every one of those is concerned the instant they press it; it
  /// stays in [_cart] only long enough to collapse, and a total that waited for
  /// the animation would be a figure that disagreed with the reader for 180ms.
  List<_CartLine> get _liveCart =>
      [for (final line in _cart) if (!_leaving.contains(line)) line];

  int get _cartTotalCents =>
      _liveCart.fold(0, (sum, line) => sum + line.totalCents);

  /// What to tell a reader whose saved order came back different, or null when
  /// it came back exactly as they left it.
  ///
  /// One sentence covering both cases rather than two stacked notices: they have
  /// the same cause — the board moved while the order sat — and the reader's
  /// question is the same either way, which is whether the figure under the lines
  /// is the one they will be charged. It says that the prices are current rather
  /// than naming the old ones: a total they no longer have to compare against is
  /// not information, and the lines above it already show what each drink now
  /// costs.
  String? get _resumeNotice {
    final dropped = _droppedLines;
    if (dropped > 0) {
      final drinks = dropped == 1 ? 'One drink' : '$dropped drinks';
      final verb = dropped == 1 ? 'is' : 'are';
      return '$drinks from your saved order $verb no longer on the menu, so '
          '${dropped == 1 ? 'it has' : 'they have'} been left out. Everything '
          'below is priced as the shop has it today.';
    }
    if (_repriced) {
      return 'Some prices have changed since you saved this order. The total '
          'below is what the shop charges today.';
    }
    return null;
  }

  /// The pickup time the reader dialled in, or null for an order made now.
  DateTime? get _scheduledFor {
    if (!_scheduling) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .add(Duration(days: _scheduleDays, minutes: _scheduleMinutes));
  }

  /// Why the dialled-in time cannot be ordered for, or null when it can.
  /// Live rather than gated on [_pickupSubmitted]: a past time is wrong the
  /// moment it is showing, not only once the reader tries to walk on.
  String? get _scheduleError {
    final at = _scheduledFor;
    if (at == null) return null;
    if (at.isAfter(DateTime.now())) return null;
    return 'That time has already passed. Pick a later one.';
  }

  /// Switches to a scheduled pickup, seeding the steppers on the first switch
  /// with the next quarter hour at least half an hour out — a time that is
  /// always valid and always worth adjusting, rather than midnight today,
  /// which would open the section on an error.
  void _startScheduling() {
    setState(() {
      _scheduling = true;
      if (_scheduleInitialised) return;
      _scheduleInitialised = true;
      final at = DateTime.now().add(const Duration(minutes: 30));
      final rounded =
          ((at.hour * 60 + at.minute) / _scheduleStep).ceil() * _scheduleStep;
      // Rounding up can spill past midnight; the spill becomes tomorrow.
      _scheduleDays = rounded >= 24 * 60 ? 1 : 0;
      _scheduleMinutes = rounded % (24 * 60);
    });
  }

  /// "Today", "Tomorrow", then "Mon 4 Aug" — near days by name because that is
  /// how the reader thinks about them, dates only once a name would be a
  /// count on their fingers.
  static String _dayLabel(DateTime day, int daysFromToday) {
    if (daysFromToday == 0) return 'Today';
    if (daysFromToday == 1) return 'Tomorrow';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${weekdays[day.weekday - 1]} ${day.day} ${months[day.month - 1]}';
  }

  /// "9:15 AM", from minutes since midnight.
  static String _timeLabel(int minutes) {
    final hour24 = minutes ~/ 60;
    final hour12 = switch (hour24 % 12) { 0 => 12, final h => h };
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour12:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
  }

  /// Whether the forward button on the current step is allowed to be pressed.
  ///
  /// One expression per step rather than a flag each step sets: a gate the
  /// steps wrote into shared state could be left true by a step the reader
  /// walked back out of, and a forward button that is live because of a
  /// condition two steps ago is the classic wizard bug.
  bool get _canAdvance => switch (_step) {
        // A sized item needs one picked; a flat one has nothing to pick.
        _Step.select => _draftItem.sizeLines.isEmpty || _size != null,
        _Step.customise => true,
        _Step.cart => _liveCart.isNotEmpty,
        _Step.pickup =>
          _nameError == null && _phoneError == null && _scheduleError == null,
        // The receipt is the whole step. Nothing was paid in the app, so the
        // uploaded picture is the only evidence the counter will ever have that
        // this order was settled, and a Review button that opened without one
        // would walk the reader to a Confirm that promises the shop a payment
        // nobody can find.
        //
        // A shop with no QR on file is the exception, and has to be: there is
        // nothing to pay against, so demanding proof of paying it would be a
        // door with no key. Those orders go through as pay-at-counter — see
        // [_shopQr] and the sentence [_paymentBody] prints in its place.
        _Step.payment => _receipt != null || _shopQr == null,
        // Left true at the order cap rather than folding in [_canPlaceOrder]:
        // a dead button here would have nothing to answer a press with, and
        // [_placeOrder] is what shows [_OrderCapSheet] instead of writing —
        // the same shape [_addDraftToCart] uses for the cart's own cap.
        _Step.confirm => !_placing && !_placed,
      };

  String? get _nameError {
    final value = _nameController.text.trim();
    if (value.isEmpty) return 'Tell us whose name to call out.';
    if (value.length < 2) return 'That is too short to call out.';
    return null;
  }

  /// Digits only, and enough of them to be a phone number.
  ///
  /// Deliberately loose about *which* digits: this build is Philippine, but
  /// rejecting anything that is not 09-something would turn a reader with a
  /// landline or a foreign mobile into someone who cannot order coffee. The
  /// counter phones them; the counter can read a number in any shape.
  String? get _phoneError {
    final value = _phoneController.text.trim();
    if (value.isEmpty) return 'We need a number to reach you on.';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return 'That does not look like a full number.';
    return null;
  }

  void _advance() {
    if (_step == _Step.pickup && !_pickupSubmitted) {
      // Turn the messages on before testing the gate, so a first press on an
      // empty form shows why it did nothing rather than appearing to drop.
      setState(() => _pickupSubmitted = true);
      if (!_canAdvance) return;
    }
    // The receipt gate answers a press rather than swallowing it. The button is
    // deliberately left live on this step — see [_actions] — so this is where a
    // reader who has not uploaded anything finds out why they are not moving,
    // the same bargain [_addDraftToCart] and [_placeOrder] strike for the two
    // caps.
    if (_step == _Step.payment && !_canAdvance) {
      _showReceiptNeeded();
      return;
    }
    if (!_canAdvance) return;

    if (_step == _Step.customise) {
      _addDraftToCart();
      return;
    }
    if (_step == _Step.confirm) {
      _placeOrder();
      return;
    }

    final next = _step.next;
    if (next != null) setState(() => _step = next);
  }

  void _back() {
    final previous = _step.previous;
    if (previous == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step = previous);
  }

  /// What a press on the stepper's plus does once [_quantity] is already at
  /// [_quantityCap]. A pop-up rather than nothing, the same reasoning
  /// [_addDraftToCart] gives for the cart's own cap.
  Future<void> _showQuantityCap() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrewColor.field,
      builder: (context) => _QuantityCapSheet(
        max: _quantityCap,
        activeOrders: _activeOrderCount ?? 0,
        bankedQuantity: _bankedQuantity,
      ),
    );
  }

  /// Banks the draft and lands on the cart, which is step three saying what
  /// just happened. The draft is not cleared here — [_addAnother] does that,
  /// because the reader may come back to step two from the cart to change the
  /// drink they just added.
  Future<void> _addDraftToCart() async {
    // Both budgets, checked against what banking this line would actually
    // produce rather than against the row count alone. The second half is the
    // one the row count missed: a draft of two drinks landing on a cart that
    // already holds four is a six-drink order, and it arrives through a stepper
    // that was within its own limit the whole time.
    //
    // Kept here as well as on the button, because this is not the only door —
    // a resumed draft opens on its own customise step with an Add to cart that
    // never passed through the cart body's conditional.
    if (_cart.length >= _maxCartLines ||
        _bankedQuantity + _quantity > _maxActiveOrders) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: BrewColor.field,
        builder: (context) => _CartCapSheet(max: _maxCartLines),
      );
      return;
    }
    setState(() {
      _cart.add(
        _CartLine(
          item: _draftItem,
          size: _size,
          // Resolved and frozen here rather than kept as ids: a banked line is
          // what the reader agreed to buy, so an admin renaming or repricing
          // an add-on afterwards must not silently rewrite a line already in
          // the cart. The draft above still tracks the live list.
          extras: List<BrewAddOn>.unmodifiable(_draftExtras),
          quantity: _quantity,
          unitCents: _draftUnitCents,
        ),
      );
      _step = _Step.cart;
      // The drink is banked, so step one is back to confirming the line the
      // reader is on rather than choosing a new one.
      _picking = false;
    });
  }

  /// Back to step one with the cart intact and the draft reset, and step one
  /// opened as a picker over the shop's whole board.
  ///
  /// A second drink has been chosen nowhere yet. Reopening on the same item
  /// would let the reader add that one drink again and nothing else, and sending
  /// them back to the menu screen to choose would leave this cart behind — so
  /// the board comes here, and [_picking] is what step one reads to draw it.
  ///
  /// The item is left as it was until they pick: it is the only drink this
  /// screen is certain of, so it is what the picker opens selected on and what
  /// the step costs itself against while the board is still in flight.
  void _addAnother() {
    _watchMenu();
    setState(() {
      _picking = true;
      _size = _defaultSize(_draftItem);
      _extraIds.clear();
      _openGroup = null;
      _quantity = 1;
      _step = _Step.select;
    });
  }

  /// Swaps the drink being configured for another off the picker.
  ///
  /// The size goes with it rather than carrying over: sizes are priced per item,
  /// and a Large held open across a swap to an item that has no Large is a
  /// selection that prices at nothing. Extras and quantity are the reader's own
  /// and survive — they chose an extra shot for the drink they are building, not
  /// for the name that was on it.
  void _selectItem(BrewMenuItem item) {
    if (item.id == _draftItem.id) return;
    setState(() {
      _draftItem = item;
      _size = _defaultSize(item);
    });
  }

  /// Rebuilds a resumed draft's cart against the board as it now stands.
  ///
  /// Called from the build path once both snapshots have landed, and exactly
  /// once — [_restoring] is what makes it once, and it is cleared here whether
  /// or not anything was recovered.
  ///
  /// Every line is re-costed rather than restored at its saved price. An item
  /// that has left the board, or lost the size the reader picked, cannot be
  /// rebuilt at all and is dropped: there is no drink to make and no price to
  /// charge, so carrying it forward would put a line on the counter's ticket
  /// that nobody can fill. An add-on that has gone falls out of its line the same
  /// way [_draftExtras] already drops one mid-order, leaving the drink itself
  /// intact — losing the whole latte because the oat milk was discontinued would
  /// be the worse reading.
  ///
  /// [_repriced] and [_droppedLines] are what the cart step says out loud about
  /// both cases.
  void _restore(List<BrewMenuItem> menu, List<BrewAddOn> addOns) {
    final draft = widget.draft;
    if (draft == null) return;

    final lines = <_CartLine>[];
    var dropped = 0;
    var repriced = false;

    for (final saved in draft.lines) {
      final item = menu.where((item) => item.id == saved.itemId).firstOrNull;
      if (item == null) {
        dropped++;
        continue;
      }
      // A sized item whose size the shop has stopped pricing has no figure to
      // charge — the reader picked Large and there is no Large any more.
      final base = switch (saved.size) {
        final size? => item.sizePrices[size],
        null => item.priceCents ?? 0,
      };
      if (base == null) {
        dropped++;
        continue;
      }
      // Board order, not the order the ids were stored in, so a resumed line
      // reads identically to the one that was saved — see [_CartLine.extras].
      final extras = [
        for (final addOn in addOns)
          if (saved.extraIds.contains(addOn.id)) addOn,
      ];
      if (extras.length != saved.extraIds.length) repriced = true;

      final unitCents =
          base + extras.fold<int>(0, (sum, extra) => sum + extra.priceCents);
      if (unitCents != saved.unitCents) repriced = true;

      lines.add(
        _CartLine(
          item: item,
          size: saved.size,
          extras: List<BrewAddOn>.unmodifiable(extras),
          quantity: saved.quantity,
          unitCents: unitCents,
        ),
      );
    }

    setState(() {
      _restoring = false;
      _cart
        ..clear()
        ..addAll(lines);
      _droppedLines = dropped;
      _repriced = repriced;
      // The draft is only worth resuming if something in it survived. An empty
      // cart cannot go forward — [_canAdvance] blocks the cart step on exactly
      // that — so the reader is put back on step one to build the drink again
      // rather than left looking at a basket with nothing in it.
      if (lines.isEmpty) _step = _Step.select;
    });
  }

  /// Takes a line out in two beats: marked as leaving now, gone once the reveal
  /// that collapses it has run.
  ///
  /// A straight `removeAt` is a row that is there on one frame and not on the
  /// next, with everything under it — the total, Add another, the whole footer —
  /// jumping up to fill the hole. The reader pressed Remove on a specific row;
  /// the collapse is what shows them it was that row that went rather than
  /// leaving them to work it out from a list that is suddenly shorter.
  ///
  /// The line stays in [_cart] while it collapses, so it is still priced into
  /// the total for those 180ms. That is why the total is discounted separately
  /// below rather than waiting for the list — see [_cartTotalCents].
  void _removeLine(int index) {
    if (index >= _cart.length) return;
    final line = _cart[index];
    if (_leaving.contains(line)) return;

    setState(() => _leaving.add(line));

    Future<void>.delayed(BrewMotion.reveal, () {
      // The reader may have walked off this step, or popped the route
      // altogether, in the time the row took to close up.
      if (!mounted) return;
      setState(() {
        _cart.remove(line);
        _leaving.remove(line);
      });
    });
  }

  /// Whether there is anything worth saving.
  ///
  /// The banked cart, not the draft in progress. A reader on step one or two has
  /// chosen a size and maybe an extra but has not said they want the drink — the
  /// press that says so is Add to cart — and saving a half-configured drink they
  /// never added would resume into a cart holding something they did not put
  /// there. Which is also why the button is absent rather than disabled on those
  /// two steps: see [_actions].
  bool get _canSave =>
      _liveCart.isNotEmpty &&
      widget.counter != null &&
      widget.session != null &&
      !_placed &&
      !_placing;

  /// Writes the order in progress to `drafts/{uid}` and leaves.
  ///
  /// Pops on success rather than staying with a confirmation, because leaving is
  /// what the reader asked for — a screen that saved and then sat there would
  /// make them press Cancel as well, and Cancel is the control that throws the
  /// order away. The home screen's Saved order card is the acknowledgement.
  Future<void> _saveForLater() async {
    final counter = widget.counter;
    final session = widget.session;
    if (counter == null || session == null) {
      setState(
        () => _saveFailure = 'You are not connected, so this order cannot be '
            'saved. Sign in and try again.',
      );
      return;
    }
    if (_liveCart.isEmpty) return;

    setState(() {
      _saving = true;
      _saveFailure = null;
    });

    final failure = await counter.saveDraft(
      uid: session.uid,
      draft: BrewDraft(
        partner: widget.shop.partner,
        step: _step.name,
        lines: [for (final line in _liveCart) line.draftLine],
        pickupName: _nameController.text.trim(),
        pickupPhone: _phoneController.text.trim(),
        pickupNote: _noteController.text.trim(),
        paymentMethod: _payment,
        scheduledFor: _scheduledFor,
      ),
    );

    // The await crossed a frame boundary and the reader may have popped this
    // route themselves in the meantime.
    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _saving = false;
        _saveFailure = failure;
      });
      return;
    }
    // Not cleared before popping: the route is going, and a setState that put
    // the footer back to its resting state for one frame on the way out would be
    // a flicker on a screen the reader has already left.
    Navigator.of(context).maybePop();
  }

  // ------------------------------------------------------------ step five

  /// Writes the shop's QR to the phone's gallery.
  ///
  /// A gallery write rather than a share sheet or a file picker, because of
  /// where the picture is going next: the reader is about to leave for GCash or
  /// their bank, and every one of those apps opens Photos when it asks for a QR
  /// to scan. A code saved into an app-private directory would be a download
  /// that technically happened and practically cannot be used.
  ///
  /// The result is stated either way — see [_qrNotice].
  Future<void> _downloadQr() async {
    final qr = _shopQr;
    if (qr == null) return;

    setState(() {
      _savingQr = true;
      _qrNotice = null;
    });

    String notice;
    try {
      // Named after the shop rather than left to a timestamp, so a reader who
      // has saved both partners' codes can tell them apart in Photos.
      final result = await ImageGallerySaverPlus.saveImage(
        qr,
        quality: 100,
        name: 'quickbrew-${_shop.partner.id}-pay',
      );
      // The plugin answers with a map rather than a bool, and an `isSuccess`
      // that is false is the ordinary shape of a refused permission — which is
      // a thing the reader can fix, so it gets its own sentence rather than the
      // generic one below.
      final saved = result is Map && result['isSuccess'] == true;
      notice = saved
          ? 'Saved to your photos.'
          : 'Could not save it. Allow QuickBrew to save photos, or take a '
              'screenshot instead.';
    } catch (error) {
      debugPrint('QuickBrew → QR download failed: $error');
      notice = 'Could not save it. Take a screenshot of the code instead.';
    }

    if (!mounted) return;
    setState(() {
      _savingQr = false;
      _qrNotice = notice;
    });
  }

  /// What a press on Review your order gets while no receipt is uploaded.
  ///
  /// A sheet rather than an inline line of text, and rather than the dead button
  /// this used to be. The reader pressed the one control on the step expecting
  /// it to work; what answers that press should interrupt them the way the press
  /// itself did — the same reasoning [_CartCapSheet] and [_OrderCapSheet] give
  /// for the two caps, and the reason this step's gate is the only one in the
  /// flow that was previously silent.
  ///
  /// It offers the upload itself, not just an explanation. A pop-up that says
  /// what is missing and then makes the reader find the control behind it is a
  /// sentence where a door would do.
  Future<void> _showReceiptNeeded() async {
    final upload = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrewColor.field,
      builder: (context) => const _ReceiptNeededSheet(),
    );
    if (upload == true && mounted) await _pickReceipt();
  }

  /// The gallery, downscaled on the way out — what [widget.pickReceipt] stands
  /// in for.
  Future<Uint8List?> _pickFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );
    return picked == null ? null : await picked.readAsBytes();
  }

  /// Picks the receipt, downscaled on the way in.
  ///
  /// 1024 at quality 70 for the same reason the admin's QR upload is 1024: this
  /// is a screenshot of a transfer with a reference number on it that somebody
  /// at the counter has to read, and 512px of it would be a picture of a number
  /// nobody can make out. Quality can go lower than the QR's, because a receipt
  /// only has to be legible to a person, not resolvable by a camera.
  ///
  /// The bytes stay in memory — see [_receipt]. The size check happens at the
  /// write, in [BrewCounter.placeOrder], which is the one place that knows what
  /// a document has room for.
  Future<void> _pickReceipt() async {
    setState(() {
      _pickingReceipt = true;
      _receiptError = null;
    });

    try {
      final bytes = await (widget.pickReceipt ?? _pickFromGallery)();
      // Backing out of the picker is not a failure and should say nothing.
      if (bytes == null) {
        if (mounted) setState(() => _pickingReceipt = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        _pickingReceipt = false;
        _receipt = bytes;
      });
    } catch (error) {
      debugPrint('QuickBrew → receipt pick failed: $error');
      if (!mounted) return;
      setState(() {
        _pickingReceipt = false;
        _receiptError = 'Could not read that image. Try another.';
      });
    }
  }

  Future<void> _placeOrder() async {
    final counter = widget.counter;
    final session = widget.session;
    if (counter == null || session == null) {
      setState(
        () => _failure = 'You are not connected, so this order cannot be sent. '
            'Sign in and try again.',
      );
      return;
    }
    if (!_canPlaceOrder) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: BrewColor.field,
        builder: (context) => _OrderCapSheet(max: _maxActiveOrders),
      );
      return;
    }

    setState(() {
      _placing = true;
      _failure = null;
    });

    final failure = await counter.placeOrder(
      uid: session.uid,
      partner: widget.shop.partner,
      items: [for (final line in _liveCart) line.orderLine],
      totalCents: _cartTotalCents,
      pickupName: _nameController.text.trim(),
      pickupPhone: _phoneController.text.trim(),
      pickupNote: _noteController.text.trim(),
      paymentMethod: _payment,
      receipt: _receipt,
      scheduledFor: _scheduledFor,
    );

    // The order is in, so the draft of it is no longer an order in progress —
    // it is a duplicate of something already at the counter, and leaving it
    // behind would put a Resume card on the home screen beside the active order
    // it would create a second copy of.
    //
    // Fired without awaiting and deliberately not gated on `mounted`: the delete
    // must happen whether or not this screen is still alive to see it, and
    // [BrewCounter.discardDraft] swallows its own failures. A draft that outlives
    // its order is the one case the reader can fix themselves, from the card's
    // own Discard.
    if (failure == null) {
      counter.discardDraft(session.uid);
    }

    // The await crossed a frame boundary, and the reader may have popped this
    // route while it was in flight — setState on a dead State throws.
    if (!mounted) return;

    setState(() {
      _placing = false;
      _failure = failure;
      _placed = failure == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.height <= BrewSpace.compactHeight;
    final reduced = MediaQuery.disableAnimationsOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: BrewColor.field,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Material(
        color: BrewColor.field,
        child: BrewBackground(
          child: StreamBuilder<List<BrewAddOn>>(
            stream: _addOnStream,
          builder: (context, addOnSnapshot) {
            _addOns = addOnSnapshot.data ?? const <BrewAddOn>[];

            // A fresh order that has not asked for the board has no menu stream
            // and no lines to rebuild, so it goes straight through — the board
            // it came from is already in [widget.item].
            if (_menuStream == null) {
              return _scaffold(
                context,
                media,
                compact: compact,
                reduced: reduced,
              );
            }

            return StreamBuilder<List<BrewMenuItem>>(
              stream: _menuStream,
              builder: (context, menuSnapshot) {
                final menu = menuSnapshot.data;
                // Assigned on the way past, like [_addOns] above and for the
                // same reason: this rebuild is the snapshot arriving, and a
                // setState here would schedule a second one for a result this
                // frame already has. Step one's picker reads it.
                _menu = menu ?? const <BrewMenuItem>[];

                final draft = widget.draft;
                // A stream opened by Add another drink has no draft behind it
                // and nothing to rebuild — the board is only being watched so
                // the reader can pick from it.
                if (draft == null) {
                  return _scaffold(
                    context,
                    media,
                    compact: compact,
                    reduced: reduced,
                  );
                }
                // The menu is always waited for; the add-ons only when the draft
                // names one.
                //
                // Both would stall a draft from a shop that sells no extras: an
                // empty `addons` collection may have no snapshot to deliver at
                // all, so the cart would sit on "Fetching your saved order"
                // forever. The menu alone would be wrong the other way — a draft
                // whose add-ons had not landed yet would rebuild without them,
                // dropping surcharges the reader chose and then reporting the
                // shortfall as the shop having repriced.
                //
                // Which stream a given draft needs is a fact about that draft, so
                // that is what the gate reads.
                final needsAddOns =
                    draft.lines.any((line) => line.extraIds.isNotEmpty);
                // Rebuilt after this frame rather than during it: [_restore]
                // calls setState, which inside a builder would schedule a second
                // build for a result this one could have had. The same reason
                // [_addOns] above is assigned on the way past.
                if (_restoring &&
                    menu != null &&
                    (!needsAddOns || addOnSnapshot.hasData)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _restoring) _restore(menu, _addOns);
                  });
                }
                return _scaffold(
                  context,
                  media,
                  compact: compact,
                  reduced: reduced,
                );
              },
            );
          },
        ),
      ),
    ),
  );
}

  Widget _scaffold(
    BuildContext context,
    MediaQueryData media, {
    required bool compact,
    required bool reduced,
  }) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: BrewSpace.gutter,
              right: BrewSpace.gutter,
              top: math.max(media.padding.top, BrewSpace.minInset) +
                  BrewSpace.headerClearance,
              bottom: BrewSpace.grid * 3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context),
                SizedBox(height: brewBlockGap(compact)),
                _StepRule(step: _step, reduced: reduced),
                const SizedBox(height: BrewSpace.grid * 2),
                Text(
                  _placed ? 'Order placed' : _step.heading,
                  style: BrewType.displayAt(compact ? 26 : 30),
                ),
                const SizedBox(height: BrewSpace.grid * 3),
                // Keyed on the step so the body cross-fades as the reader
                // walks the flow, rather than the new step's content
                // appearing inside the old one's box. Reduced motion gets
                // the cut, which is what it asked for.
                AnimatedSwitcher(
                  duration: reduced ? Duration.zero : BrewMotion.reveal,
                  switchInCurve: BrewMotion.crossFadeCurve,
                  switchOutCurve: BrewMotion.crossFadeCurve,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.topStart,
                    children: [
                      for (final child in previous)
                        ExcludeSemantics(
                          child: IgnorePointer(child: child),
                        ),
                      ?current,
                    ],
                  ),
                  // The group is inside the key, not around the switcher: a
                  // new step is a new StaggerGroup with its own controller,
                  // which is what makes the entrance replay on every step
                  // rather than once for the first one. Its length is the
                  // step's own row count — see [_bodyLength].
                  child: KeyedSubtree(
                    key: ValueKey((_step, _placed)),
                    child: StaggerGroup(
                      itemCount: _bodyLength,
                      reveal: true,
                      reduced: reduced,
                      child: _body(compact),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _Footer(media: media, child: _actions()),
      ],
    );
  }

  /// How many rows the current body deals out, for the timeline the group sizes
  /// itself from.
  ///
  /// Counted rather than measured because [StaggerGroup] needs the length before
  /// the children exist. It only has to be an upper bound that the indices below
  /// stay inside — a count that is too high stretches the timeline by 60ms a row
  /// and is otherwise harmless, where one that is too low asserts inside
  /// [Interval]. The lists that can change under it (the add-on sections, the
  /// cart) are read here from the same state the body reads a frame later, so
  /// the two cannot disagree.
  int get _bodyLength => switch (_placed) {
        true => 2 + _cart.length,
        false => switch (_step) {
            // The headline, a heading and a row per size — plus, while Add
            // another drink is open, a heading and a row per pickable item
            // ahead of all that.
            _Step.select =>
              2 + _draftItem.sizeLines.length + (_picking ? 1 + _pickable.length : 0),
            // The add-ons blurb and one row per section, then the stepper and
            // the total.
            _Step.customise => 4 + _extraSections(_addOns).length,
            // A row per line, then the total and Add another — plus the resume
            // notice above them when a saved order came back changed. The empty
            // cart is the one sentence, which the max keeps from being a
            // zero-length timeline.
            _Step.cart => math.max(
                1,
                _cart.length + 2 + (_resumeNotice == null ? 0 : 1),
              ),
            // The blurb, three fields, and the pickup-time section.
            _Step.pickup => 5,
            // The QR block and the receipt block, or the two lines that stand in
            // for them when the shop has no code on file.
            _Step.payment => 2,
            // The summary is one block; the failure line reveals itself.
            _Step.confirm => 1,
          },
      };

  Widget _body(bool compact) => switch (_placed) {
        true => _DoneBody(
            shop: widget.shop,
            lines: _liveCart,
            totalCents: _cartTotalCents,
            pickupName: _nameController.text.trim(),
            scheduledFor: _scheduledFor,
          ),
        false => switch (_step) {
            _Step.select => _selectBody(),
            _Step.customise => _customiseBody(),
            _Step.cart => _cartBody(),
            _Step.pickup => _pickupBody(),
            _Step.payment => _paymentBody(),
            _Step.confirm => _confirmBody(),
          },
      };

  // ---------------------------------------------------------------- step one

  /// Select coffee & size.
  ///
  /// On a fresh order the item is already chosen — the reader pressed Buy on it
  /// — so this step just confirms that choice and asks the one question the
  /// board could not: which size. Reopened by Add another drink, there is no
  /// second choice on record yet, so a picker over the whole board goes in
  /// ahead of the same size question — see [_picking].
  Widget _selectBody() {
    final sizeLines = _draftItem.sizeLines;
    final pickable = _picking ? _pickable : const <BrewMenuItem>[];
    // Everything below the picker shifts down by however many rows it drew —
    // its own heading plus one per item, or nothing at all when it is closed.
    final offset = pickable.isEmpty ? 0 : 1 + pickable.length;

    return Column(
      key: const ValueKey(_Step.select),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_picking) ...[
          StaggerItem(index: 0, child: Text('DRINK', style: BrewType.mono)),
          const SizedBox(height: BrewSpace.grid * 1.5),
          if (pickable.length <= 1)
            StaggerItem(
              index: 1,
              child: Text(
                'Fetching the rest of the board…',
                style: BrewType.rowBody,
              ),
            )
          else
            for (final (index, item) in pickable.indexed) ...[
              StaggerItem(
                index: 1 + index,
                child: _OptionRow(
                  label: item.name,
                  trailing: item.price,
                  selected: item.id == _draftItem.id,
                  onSelected: () => _selectItem(item),
                ),
              ),
              const SizedBox(height: BrewSpace.grid),
            ],
          const SizedBox(height: BrewSpace.grid * 2),
        ],
        StaggerItem(
          index: offset,
          child: _ItemHeadline(item: _draftItem, shop: widget.shop),
        ),
        const SizedBox(height: BrewSpace.grid * 3),
        if (sizeLines.isEmpty)
          StaggerItem(
            index: offset + 1,
            child: Text(
              '${_draftItem.name} comes one way, so there is no size to pick.',
              style: BrewType.rowBody,
            ),
          )
        else ...[
          StaggerItem(
            index: offset + 1,
            child: Text('SIZE', style: BrewType.mono),
          ),
          const SizedBox(height: BrewSpace.grid * 1.5),
          for (final (index, (size, price)) in sizeLines.indexed) ...[
            StaggerItem(
              index: offset + 2 + index,
              child: _OptionRow(
                label: size.label,
                trailing: price,
                selected: _size == size,
                onSelected: () => setState(() => _size = size),
              ),
            ),
            const SizedBox(height: BrewSpace.grid),
          ],
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- step two

  /// Customise your drink: what goes in it, how many.
  ///
  /// Every option here states its own surcharge. A reader who adds oat milk and
  /// then finds the total ₱25 higher than they expected was not customising —
  /// they were guessing.
  ///
  /// The add-ons come from this shop's own list, so the whole section is absent
  /// for a shop that sells no extras — the step is then a quantity and a total,
  /// which is the truthful reading rather than an empty ADD ONS heading over
  /// nothing.
  Widget _customiseBody() {
    final sections = _extraSections(_addOns);

    return Column(
      key: const ValueKey(_Step.customise),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sections.isNotEmpty) ...[
          StaggerItem(
            index: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ADD ONS', style: BrewType.mono),
                const SizedBox(height: BrewSpace.grid),
                Text(
                  'Optional. Each one is added to the price of this drink.',
                  style: BrewType.rowBody,
                ),
              ],
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          // One collapsed section per heading on the shop's board. Collapsed by
          // default because twenty rows open at once is a step the reader has to
          // scroll through to reach the quantity stepper below it — and the
          // common order has no add-ons at all, so the closed state is the one
          // most readers want.
          for (final (index, (heading, options)) in sections.indexed) ...[
            StaggerItem(
              index: 1 + index,
              child: _ExtraSection(
                heading: heading,
                options: options,
                selected: _extraIds,
                open: _openGroup == heading,
                // One at a time: two open sections put the stepper below a
                // screen and a half of options, which is the flat list again by
                // another route.
                onToggleOpen: () => setState(
                  () => _openGroup = _openGroup == heading ? null : heading,
                ),
                // A set, not a choice: add-ons are independent of each other, so
                // each one toggles rather than deselecting its neighbours.
                onToggleExtra: (extra) => setState(() {
                  if (!_extraIds.remove(extra.id)) _extraIds.add(extra.id);
                }),
              ),
            ),
            const SizedBox(height: BrewSpace.grid),
          ],
          const SizedBox(height: BrewSpace.grid * 2),
        ],
        StaggerItem(
          index: sections.length + 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HOW MANY', style: BrewType.mono),
              const SizedBox(height: BrewSpace.grid * 1.5),
              _Stepper(
                value: _quantity,
                // Down to one, not to zero: a quantity of zero is not a drink
                // with none of it, it is the reader having left this step, and
                // Back is where they do that.
                onChanged: (value) => setState(() => _quantity = value),
                onMaxTapped: _showQuantityCap,
                max: _quantityCap,
              ),
            ],
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 3),
        StaggerItem(
          index: sections.length + 2,
          child: _TotalRule(
            label: 'This drink',
            cents: _draftUnitCents * _quantity,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- step three

  /// Add to cart: what is in it, and the one place a line can be taken back
  /// out. Empty only if the reader removed everything, which is why the empty
  /// state points at the button that fixes it rather than at the board.
  Widget _cartBody() {
    if (_cart.isEmpty) {
      return Column(
        key: const ValueKey(_Step.cart),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StaggerItem(
            index: 0,
            child: Text(
              // A resumed draft whose board has not landed yet is not an empty
              // cart, and saying it is would be this screen guessing. The
              // sentence is the same length either way, so nothing moves when
              // the lines arrive.
              _restoring
                  ? 'Fetching your saved order…'
                  : 'Your cart is empty. Add a drink to carry on.',
              style: BrewType.rowBody,
            ),
          ),
        ],
      );
    }

    final notice = _resumeNotice;
    // The notice takes the first slot when there is one, so everything under it
    // deals one later. Read once here rather than written into each index below,
    // which is how the two that follow drifted apart from [_bodyLength] before.
    final offset = notice == null ? 0 : 1;

    return Column(
      key: const ValueKey(_Step.cart),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // What changed while the order was parked, said before the lines rather
        // than after the total: the reader is about to read figures, and this is
        // what tells them why they are not the ones they left.
        if (notice != null) ...[
          StaggerItem(
            index: 0,
            child: Semantics(
              liveRegion: true,
              child: Text(notice, style: BrewType.rowBody),
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
        ],
        for (final (index, line) in _cart.indexed)
          // Null once the line is leaving, which is what collapses this row and
          // the gap under it on the app's own reveal ramp. The row stays
          // mounted through it — see [BrewReveal] — so what the reader watches
          // close is the row they pressed Remove on rather than the last one in
          // the list. [_removeLine] drops it from _cart when the ramp is spent.
          BrewReveal(
            key: ObjectKey(line),
            child: _leaving.contains(line)
                ? null
                : Padding(
                    padding: const EdgeInsets.only(bottom: BrewSpace.grid),
                    child: StaggerItem(
                      index: offset + index,
                      child: _CartRow(
                        line: line,
                        onRemove: () => _removeLine(index),
                      ),
                    ),
                  ),
          ),
        const SizedBox(height: BrewSpace.grid * 2),
        StaggerItem(
          index: offset + _cart.length,
          child: _TotalRule(label: 'Cart total', cents: _cartTotalCents),
        ),
        const SizedBox(height: BrewSpace.grid * 2),
        // Hidden at the cap rather than left live: step one has no way back
        // to the cart except through a line actually getting banked — see
        // [_Step.previous] — so a button that opened a picker with nowhere
        // for [_addDraftToCart] to land the drink would strand the reader
        // there with their five lines still in [_cart] but no way back to
        // look at them short of leaving the wizard. [_CartCapSheet] still
        // answers a press reaching [_addDraftToCart] some other way — a
        // resumed draft's customise step, say — but this is the door that
        // matters, and it simply is not offered once there is nowhere for it
        // to lead.
        //
        // Gated on drinks as well as lines — see [_hasRoomForAnother]. Lines
        // alone left the door open on a cart of five drinks banked as two rows,
        // which is the same over-sized order the stepper refuses inside one
        // line, just assembled across several.
        if (_hasRoomForAnother)
          StaggerItem(
            index: offset + _cart.length + 1,
            child: BrewMonoButton(
              label: 'Add another drink',
              semanticsLabel: 'Add another drink to this order',
              onPressed: _addAnother,
            ),
          ),
      ],
    );
  }

  // --------------------------------------------------------------- step four

  /// Enter pickup details. Three fields: who to call out for, a number to reach
  /// them on, and anything the counter should know. No address, because there
  /// is no delivery in this build and a field nobody acts on is a field that
  /// misleads.
  Widget _pickupBody() {
    return Column(
      key: const ValueKey(_Step.pickup),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaggerItem(
          index: 0,
          child: Text(
            'Collect from ${widget.shop.displayName}. We will call your name '
            'when it is ready.',
            style: BrewType.rowBody,
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 3),
        StaggerItem(
          index: 1,
          child: BrewField(
            label: 'Name for the order',
            controller: _nameController,
            hint: 'Who we call out',
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            errorText: _pickupSubmitted ? _nameError : null,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 2.5),
        StaggerItem(
          index: 2,
          child: BrewField(
            label: 'Mobile number',
            controller: _phoneController,
            hint: '09XX XXX XXXX',
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            errorText: _pickupSubmitted ? _phoneError : null,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 2.5),
        StaggerItem(
          index: 3,
          child: BrewField(
            label: 'Note for the counter',
            controller: _noteController,
            hint: 'Optional',
            helper: 'Optional',
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 3),
        StaggerItem(index: 4, child: _pickupTimeSection()),
      ],
    );
  }

  /// Order now, or book a collection time. One section rather than a step of
  /// its own: it is a pickup detail like the name and the number, and most
  /// readers want the default.
  Widget _pickupTimeSection() {
    final scheduleDay = DateTime.now().add(Duration(days: _scheduleDays));
    final error = _scheduleError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PICKUP TIME', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid * 1.5),
        _OptionRow(
          label: 'Order now',
          note: 'The shop starts on it right away.',
          selected: !_scheduling,
          onSelected: () => setState(() => _scheduling = false),
        ),
        const SizedBox(height: BrewSpace.grid),
        _OptionRow(
          label: 'Schedule pickup',
          note: _scheduling
              ? '${_dayLabel(scheduleDay, _scheduleDays)}, '
                  '${_timeLabel(_scheduleMinutes)}'
              : 'Book a day and time up to a week out.',
          selected: _scheduling,
          onSelected: _startScheduling,
        ),
        // The dials, only while they mean something. BrewReveal so the section
        // opens and closes the way every other conditional block here does.
        BrewReveal(
          gap: BrewSpace.grid * 2,
          child: !_scheduling
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DAY', style: BrewType.mono),
                    const SizedBox(height: BrewSpace.grid),
                    Row(
                      children: [
                        _StepperButton(
                          label: '−',
                          semanticsLabel: 'A day earlier',
                          onPressed: _scheduleDays > 0
                              ? () => setState(() => _scheduleDays--)
                              : null,
                        ),
                        SizedBox(
                          width: BrewSpace.grid * 17,
                          child: Center(
                            child: Text(
                              _dayLabel(scheduleDay, _scheduleDays),
                              style: BrewType.bodyMedium,
                            ),
                          ),
                        ),
                        _StepperButton(
                          label: '+',
                          semanticsLabel: 'A day later',
                          onPressed: _scheduleDays < _maxScheduleDays
                              ? () => setState(() => _scheduleDays++)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: BrewSpace.grid * 2),
                    Text('TIME', style: BrewType.mono),
                    const SizedBox(height: BrewSpace.grid),
                    Row(
                      children: [
                        _StepperButton(
                          label: '−',
                          semanticsLabel: 'Fifteen minutes earlier',
                          onPressed: _scheduleMinutes >= _scheduleStep
                              ? () => setState(
                                    () => _scheduleMinutes -= _scheduleStep,
                                  )
                              : null,
                        ),
                        SizedBox(
                          width: BrewSpace.grid * 17,
                          child: Center(
                            child: Text(
                              _timeLabel(_scheduleMinutes),
                              style: BrewType.bodyMedium,
                            ),
                          ),
                        ),
                        _StepperButton(
                          label: '+',
                          semanticsLabel: 'Fifteen minutes later',
                          onPressed:
                              _scheduleMinutes < 24 * 60 - _scheduleStep
                                  ? () => setState(
                                        () =>
                                            _scheduleMinutes += _scheduleStep,
                                      )
                                  : null,
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        // A live region like every other form-level failure: the reader
        // pressed a stepper and this sentence is the answer.
        BrewReveal(
          gap: BrewSpace.grid * 1.5,
          child: error == null
              ? null
              : Semantics(
                  liveRegion: true,
                  child: Text(error, style: BrewType.fieldError),
                ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- step five

  /// Scan and pay: the shop's code, a way to keep it, and the receipt that lets
  /// the reader move on.
  ///
  /// There is nothing to choose here any more — see [_paymentLabel] — so the
  /// step is not a picker but a task with two halves, in the order they happen:
  /// pay against the code, then show what you paid. The forward button stays
  /// dead until the second half is done, which is the one thing on this screen
  /// that is not merely stated but enforced, because it is the only evidence the
  /// counter will have.
  ///
  /// A shop with no code on file gets the other body — [_noQrSection] — where
  /// there is nothing to scan, nothing to upload, and nothing held back.
  Widget _paymentBody() {
    final qr = _shopQr;

    return Column(
      key: const ValueKey(_Step.payment),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: qr == null
          ? _noQrSection()
          : [
              StaggerItem(index: 0, child: _qrSection(qr)),
              const SizedBox(height: BrewSpace.grid * 2.5),
              StaggerItem(index: 1, child: _receiptSection()),
            ],
    );
  }

  /// The code, centred, with the control that saves it underneath.
  ///
  /// Centred rather than left-aligned like everything else on this screen, and
  /// deliberately: this is the one block on the flow that is not read but
  /// *pointed at*, by a camera held by a second person as often as not, and a
  /// code hugging the left margin is a code the reader has to angle their phone
  /// for. On a cream ground rather than the field's own dark green — a scanner
  /// wants the quiet zone a QR is specified with, and a dark surround eats it.
  ///
  /// ## Why the frame is not a square
  ///
  /// Admins do not upload bare QR codes. They upload what their banking app
  /// gave them, which for GCash is a tall portrait card with the code sitting
  /// in the middle of it. Boxed into a fixed square with `BoxFit.contain`, that
  /// card shrinks until its *height* fits — and the code inside it, already only
  /// a fraction of the card, ends up small enough to be awkward to scan, with
  /// wide bands of cream either side where the square had width to spare.
  ///
  /// So the frame takes its shape from the picture rather than imposing one:
  /// [_qrHeight] caps how tall it may get, the width follows from the image's
  /// own ratio, and a portrait card is drawn as a portrait card at the largest
  /// size the step can give it. A bare square code still comes out square.
  Widget _qrSection(Uint8List qr) {
    final notice = _qrNotice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SCAN TO PAY', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid * 1.5),
        Text(
          'Scan this with GCash or your bank, pay '
          '${_formatCents(_cartTotalCents)}, then upload the receipt below.',
          style: BrewType.rowBody,
        ),
        const SizedBox(height: BrewSpace.grid * 2),
        Center(
          child: Semantics(
            label: '${_shop.displayName} payment QR code',
            image: true,
            child: Container(
              // Tighter than the block padding elsewhere: the cream is standing
              // in for a QR's quiet zone, not framing a picture, and every pixel
              // it takes is a pixel off the code itself on a step that is
              // already long.
              padding: const EdgeInsets.all(BrewSpace.grid),
              decoration: BoxDecoration(
                color: BrewColor.cream,
                borderRadius: BorderRadius.circular(BrewSpace.radius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BrewSpace.radius),
                child: ConstrainedBox(
                  // Height-capped only. The width is whatever the image's own
                  // ratio makes it, which is what keeps a portrait card from
                  // being letterboxed inside a square — see the note above.
                  constraints: const BoxConstraints(maxHeight: _qrHeight),
                  child: Image.memory(
                    qr,
                    fit: BoxFit.contain,
                    // Bytes that decoded out of base64 can still be something the
                    // engine cannot draw. One shop's unreadable code should cost
                    // the frame, not the step — and [_canAdvance] still lets the
                    // reader past, since a code they cannot see is a code they
                    // cannot pay.
                    errorBuilder: (context, error, stack) => const SizedBox(
                      width: _qrHeight,
                      height: _qrHeight,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        Center(
          child: BrewMonoButton(
            label: _savingQr ? 'Saving' : 'Download this QR code',
            semanticsLabel: 'Save this QR code to your photos',
            onPressed: _savingQr ? null : _downloadQr,
          ),
        ),
        // Announced rather than merely drawn: the reader pressed a button whose
        // whole result happens somewhere else, and this sentence is the only
        // evidence either way.
        BrewReveal(
          gap: BrewSpace.grid,
          child: notice == null
              ? null
              : Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(notice, style: BrewType.rowBody),
                  ),
                ),
        ),
      ],
    );
  }

  /// Upload the receipt — the control the forward button is waiting on.
  ///
  /// The uploaded picture is shown back rather than replaced with a tick,
  /// because the reader is being asked to vouch for something: a thumbnail is
  /// what lets them notice they picked last week's transfer, and a tick is not.
  Widget _receiptSection() {
    final receipt = _receipt;
    final error = _receiptError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('YOUR RECEIPT', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid * 1.5),
        // Short on purpose. The long version of this sentence sat at the bottom
        // of a step whose QR had already used most of the screen, so the reader
        // met it half-clipped by the footer — and a required instruction that
        // has to be scrolled to finish reading is one that does not get read.
        Text(
          receipt == null
              ? 'Upload proof of payment to continue.'
              : 'The counter checks this when you collect.',
          style: BrewType.rowBody,
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrewMenuItemImage(bytes: receipt, dimension: 88, placeholder: true),
            const SizedBox(width: BrewSpace.grid * 2),
            Expanded(
              child: Wrap(
                spacing: BrewSpace.grid * 3,
                runSpacing: BrewSpace.grid,
                children: [
                  BrewMonoButton(
                    label: _pickingReceipt
                        ? 'Opening'
                        : (receipt == null ? 'Upload receipt' : 'Replace'),
                    semanticsLabel: receipt == null
                        ? 'Upload a picture of your receipt'
                        : 'Replace the receipt you uploaded',
                    onPressed: _pickingReceipt ? null : _pickReceipt,
                  ),
                  // Only an uploaded receipt has one to remove, the same way the
                  // admin's picture tile only offers Remove once there is a
                  // picture. Removing it puts the forward button back to sleep,
                  // which is the honest consequence of taking the evidence away.
                  if (receipt != null)
                    BrewMonoButton(
                      label: 'Remove',
                      semanticsLabel: 'Remove the receipt you uploaded',
                      ink: BrewColor.alert,
                      onPressed: _pickingReceipt
                          ? null
                          : () => setState(() {
                                _receipt = null;
                                _receiptError = null;
                              }),
                    ),
                ],
              ),
            ),
          ],
        ),
        BrewReveal(
          gap: BrewSpace.grid * 1.5,
          child: error == null
              ? null
              : Semantics(
                  liveRegion: true,
                  child: Text(error, style: BrewType.fieldError),
                ),
        ),
      ],
    );
  }

  /// What this step becomes for a shop with no QR uploaded.
  ///
  /// Stated plainly rather than dressed up as a second payment method: the
  /// reader is not choosing this, it is what is left when there is nothing to
  /// scan. Nothing is held back here — no code means no receipt to ask for, and
  /// a Review button blocked on a picture of a payment that could not be made
  /// would be a dead end with no way out but Cancel.
  List<Widget> _noQrSection() => [
        StaggerItem(
          index: 0,
          child: Text('PAY AT THE COUNTER', style: BrewType.mono),
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        StaggerItem(
          index: 1,
          child: Text(
            '${_shop.displayName} has not put up a payment code yet, so there '
            'is nothing to scan. Settle up at the counter when you collect — '
            'cash or card, whichever they take.',
            style: BrewType.rowBody,
          ),
        ),
      ];

  // ---------------------------------------------------------------- step six

  /// Confirm order: every decision the reader made, in one place, above the
  /// button that acts on it. Nothing new is asked for here — a wizard that
  /// introduces a question on its summary step has mislabelled the step.
  Widget _confirmBody() {
    final failure = _failure;

    return Column(
      key: const ValueKey(_Step.confirm),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaggerItem(
          index: 0,
          child: _SummaryBlock(
            shop: widget.shop,
            lines: _liveCart,
            totalCents: _cartTotalCents,
            pickupName: _nameController.text.trim(),
            pickupPhone: _phoneController.text.trim(),
            pickupNote: _noteController.text.trim(),
            payment: _payment,
            receipt: _receipt,
            scheduledFor: _scheduledFor,
          ),
        ),
        // A live region, the same treatment every other form-level failure in
        // this app gets: the reader pressed a button and this sentence is the
        // answer, so it has to be announced rather than merely drawn.
        BrewReveal(
          gap: BrewSpace.grid * 2.5,
          child: failure == null
              ? null
              : Semantics(
                  liveRegion: true,
                  child: Text(failure, style: BrewType.fieldError),
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ chrome

  Widget _header(BuildContext context) {
    return Row(
      children: [
        const BrewWordmarkRow(),
        const Spacer(),
        BrewMonoButton(
          label: _placed ? 'Done' : 'Cancel',
          semanticsLabel:
              _placed ? 'Back to the menu' : 'Cancel this order and go back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  /// The two controls under the fold: forward, and the way back out of the step
  /// it sits on. Pinned rather than scrolled with the body — the reader is
  /// walking a flow, and a Continue that moves depending on how many extras a
  /// step happens to list is a Continue they have to hunt for on every screen.
  Widget _actions() {
    if (_placed) {
      return BrewPrimaryButton(
        label: 'Back to the menu',
        onPressed: () => Navigator.of(context).maybePop(),
      );
    }

    final forward = switch (_step) {
      _Step.select => 'Customise your drink',
      _Step.customise => 'Add to cart',
      _Step.cart => 'Enter pickup details',
      _Step.pickup => 'Pay for your order',
      _Step.payment => 'Review your order',
      _Step.confirm => 'Confirm order',
    };

    final saveFailure = _saveFailure;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The answer to a Save for later that did not work. A live region for
        // the same reason the confirm step's failure is one: the reader pressed
        // a button and this sentence is what happened.
        BrewReveal(
          gap: BrewSpace.grid * 1.5,
          child: saveFailure == null
              ? null
              : Semantics(
                  liveRegion: true,
                  child: Text(saveFailure, style: BrewType.fieldError),
                ),
        ),
        BrewPrimaryButton(
          label: forward,
          busyLabel: _placing ? 'Placing your order' : null,
          // Null rather than a live button that refuses: a control the reader
          // can press and watch do nothing is the one thing worse than a
          // control they can see is not ready.
          //
          // Two steps are exceptions, both because a press there has something
          // to *say*. The pickup step stays live so the first press is what
          // turns its validation messages on. The payment step stays live so a
          // press with no receipt uploaded pops up [_ReceiptNeededSheet] —
          // without it, the one hard gate in the flow answers a press with
          // nothing at all, which reads as a broken button rather than as a
          // step that is not finished. See [_advance].
          onPressed: (_placing || _saving)
              ? null
              : (_canAdvance ||
                      _step == _Step.pickup ||
                      _step == _Step.payment)
                  ? _advance
                  : null,
        ),
        const SizedBox(height: BrewSpace.grid),
        BrewTextButton(
          label: _step == _Step.first ? 'Back to the menu' : 'Back',
          onPressed: (_placing || _saving) ? null : _back,
        ),
        // Revealed rather than always drawn, so the footer is two controls on
        // the steps where there is nothing banked to save and three where there
        // is. A Save for later that is permanently disabled on steps one and two
        // would be a third control the reader has to learn is usually dead — and
        // the cart is what makes it live, which is a fact the button appearing
        // states better than a greyed label does. See [_canSave].
        BrewReveal(
          child: !_canSave
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: BrewSpace.grid * 0.5),
                  child: BrewMonoButton(
                    label: _saving ? 'Saving' : 'Save for later',
                    semanticsLabel: _saving
                        ? 'Saving this order'
                        : 'Save this order and finish it later',
                    onPressed: _saving ? null : _saveForLater,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Pesos from minor units, the same format [BrewMenuItem] prints in.
///
/// Duplicated deliberately rather than reaching into that class's private
/// helper: the extras priced in this file are not menu items and have no
/// document behind them, so making [BrewMenuItem] format them would be a menu
/// item formatting something that is not one.
String _formatCents(int cents) {
  final pesos = cents ~/ 100;
  final centavos = cents % 100;
  if (centavos == 0) return '₱$pesos';
  return '₱$pesos.${centavos.toString().padLeft(2, '0')}';
}

/// The progress rule: one segment per step, filled up to the current one.
///
/// The same device the home screen's order card uses for [BrewOrderStage], and
/// for the same reason — a wizard whose only statement of where you are is the
/// words "Step 4 of 6" makes the reader read to find out, where a rule is
/// something they see.
class _StepRule extends StatelessWidget {
  const _StepRule({required this.step, required this.reduced});

  final _Step step;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // The segments are decorative; the label is the fact.
      label: step.eyebrow,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final (index, _) in _Step.values.indexed) ...[
                  if (index > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedContainer(
                      duration: reduced ? Duration.zero : BrewMotion.reveal,
                      curve: BrewMotion.revealCurve,
                      height: 2,
                      color: index <= step.index
                          ? BrewColor.cream
                          : BrewColor.hairline,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: BrewSpace.grid * 1.5),
            Text(step.eyebrow.toUpperCase(), style: BrewType.mono),
          ],
        ),
      ),
    );
  }
}

/// The pinned action bar, on the field colour with a hairline over it.
///
/// The rule matters: without it the buttons float over whatever the body
/// happens to have scrolled to, and a Continue sitting on top of a half-cut
/// cart row reads as part of the list rather than as the screen's own control.
class _Footer extends StatelessWidget {
  const _Footer({required this.media, required this.child});

  final MediaQueryData media;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BrewColor.field,
        border: Border(top: BorderSide(color: BrewColor.hairline)),
      ),
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 2,
        // The keyboard's inset is added to the safe area rather than replacing
        // it, so the action bar rides above an open keyboard instead of sitting
        // underneath it while the reader types a phone number.
        bottom: math.max(media.padding.bottom, BrewSpace.grid * 2) +
            media.viewInsets.bottom,
      ),
      child: child,
    );
  }
}

/// The item as step one states it: its picture small, its name, and the line
/// the shop wrote about it.
class _ItemHeadline extends StatelessWidget {
  const _ItemHeadline({required this.item, required this.shop});

  final BrewMenuItem item;
  final BrewShop shop;

  static const _thumb = 72.0;

  @override
  Widget build(BuildContext context) {
    final bytes = item.imageBytes;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(BrewSpace.radius),
          child: SizedBox.square(
            dimension: _thumb,
            child: bytes == null
                ? ColoredBox(color: BrewColor.sage.withValues(alpha: 0.35))
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => ColoredBox(
                      color: BrewColor.sage.withValues(alpha: 0.35),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: BrewSpace.grid * 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(shop.displayName.toUpperCase(), style: BrewType.mono),
              const SizedBox(height: BrewSpace.grid),
              Text(item.name, style: BrewType.rowTitle),
              if (item.description case final description?) ...[
                const SizedBox(height: BrewSpace.grid * 0.5),
                Text(
                  description,
                  style: BrewType.rowBody,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One section of the add-ons board: a heading that opens, and the options
/// under it once it has.
///
/// The heading carries a count of what is already chosen inside it, which is
/// what makes a closed section safe — a reader who picked pearls and collapsed
/// Sinkers can still see that something in there is on their drink, so the
/// collapse hides the options rather than the decision.
class _ExtraSection extends StatelessWidget {
  const _ExtraSection({
    required this.heading,
    required this.options,
    required this.selected,
    required this.open,
    required this.onToggleOpen,
    required this.onToggleExtra,
  });

  final String heading;
  final List<BrewAddOn> options;

  /// The chosen add-ons by document id — see [_OrderWizardScreenState._extraIds]
  /// for why the selection is held that way rather than as objects.
  final Set<String> selected;

  final bool open;
  final VoidCallback onToggleOpen;
  final ValueChanged<BrewAddOn> onToggleExtra;

  @override
  Widget build(BuildContext context) {
    final chosen =
        options.where((option) => selected.contains(option.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          label: heading,
          chosen: chosen,
          open: open,
          onPressed: onToggleOpen,
        ),
        // Revealed rather than switched on, so the options push the stepper
        // down on the same ramp the rest of this app moves layout on.
        BrewReveal(
          gap: BrewSpace.grid,
          child: !open
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, extra) in options.indexed) ...[
                      if (index > 0) const SizedBox(height: BrewSpace.grid),
                      _OptionRow(
                        label: extra.name,
                        trailing: extra.priceLabel,
                        selected: selected.contains(extra.id),
                        onSelected: () => onToggleExtra(extra),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// A section heading that is also the control that opens it: the name, how
/// many of its options are on the drink, and a mark that turns.
class _SectionHeading extends StatefulWidget {
  const _SectionHeading({
    required this.label,
    required this.chosen,
    required this.open,
    required this.onPressed,
  });

  final String label;
  final int chosen;
  final bool open;
  final VoidCallback onPressed;

  @override
  State<_SectionHeading> createState() => _SectionHeadingState();
}

class _SectionHeadingState extends State<_SectionHeading> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final chosen = widget.chosen;

    return BrewPressable(
      onPressed: widget.onPressed,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      pressed: false,
      reduced: reduced,
      semanticsLabel: [
        widget.label,
        if (chosen > 0) '$chosen chosen',
        widget.open ? 'expanded' : 'collapsed',
      ].join(', '),
      child: ExcludeSemantics(
        child: Container(
          // The whole row is the target, so the padding is the tap area rather
          // than air around a smaller one.
          padding: const EdgeInsets.symmetric(vertical: BrewSpace.grid * 1.5),
          child: Row(
            children: [
              Text(
                widget.label.toUpperCase(),
                style: BrewType.mono.copyWith(
                  color: (widget.open || _pressed || chosen > 0)
                      ? BrewColor.cream
                      : BrewColor.sageLight,
                ),
              ),
              if (chosen > 0) ...[
                const SizedBox(width: BrewSpace.grid),
                Text(
                  '$chosen',
                  style: BrewType.mono.copyWith(color: BrewColor.cream),
                ),
              ],
              const Spacer(),
              _Chevron(open: widget.open, reduced: reduced),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mark that says which way a section goes. A plus that becomes a minus
/// rather than a rotating arrow: this app draws no Material iconography, and
/// two strokes are the same letterpress vocabulary [_SelectionMark] is in.
class _Chevron extends StatelessWidget {
  const _Chevron({required this.open, required this.reduced});

  final bool open;
  final bool reduced;

  static const _dimension = 12.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _dimension,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: _dimension, height: 1.5, color: BrewColor.sageLight),
          // The upright stroke of the plus, collapsed to nothing when open —
          // which leaves the horizontal one, so a plus becomes a minus.
          AnimatedContainer(
            duration: reduced ? Duration.zero : BrewMotion.reveal,
            curve: BrewMotion.revealCurve,
            width: 1.5,
            height: open ? 0 : _dimension,
            color: BrewColor.sageLight,
          ),
        ],
      ),
    );
  }
}

/// A full-width selectable row: a label, an optional note under it, and an
/// optional figure on the right.
///
/// `BrewChoice` is the two-or-three-across version of the same idea. This is
/// its stacked form, for the lists where each option carries a price or a
/// sentence — a row of three centred chips has nowhere to put "+₱25" without
/// the label shrinking to fit around it.
class _OptionRow extends StatefulWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.trailing,
    this.note,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  /// The price or figure on the right, in mono.
  final String? trailing;

  /// One line under the label, for an option that needs explaining.
  final String? note;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final rule = (widget.selected || _pressed)
        ? BrewColor.fieldFocus
        : BrewColor.hairline;

    return BrewPressable(
      onPressed: widget.onSelected,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      pressed: false,
      reduced: reduced,
      semanticsLabel:
          widget.selected ? '${widget.label}, selected' : widget.label,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : BrewMotion.press,
          curve: BrewMotion.pressCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: BrewSpace.grid * 2,
            vertical: BrewSpace.grid * 2,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: rule),
            borderRadius: BorderRadius.circular(BrewSpace.radius),
          ),
          child: Row(
            children: [
              _SelectionMark(selected: widget.selected, reduced: reduced),
              const SizedBox(width: BrewSpace.grid * 1.5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: widget.selected
                          ? BrewType.rowTitle
                          : BrewType.rowTitle
                              .copyWith(color: BrewColor.sageLight),
                    ),
                    if (widget.note case final note?) ...[
                      const SizedBox(height: BrewSpace.grid * 0.5),
                      Text(note, style: BrewType.rowBody),
                    ],
                  ],
                ),
              ),
              if (widget.trailing case final trailing?) ...[
                const SizedBox(width: BrewSpace.grid),
                Text(
                  trailing,
                  style: BrewType.mono.copyWith(
                    color: widget.selected
                        ? BrewColor.cream
                        : BrewColor.sageLight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The square that fills when a row is selected.
///
/// A square rather than a tick or a radio dot: this app draws no Material
/// iconography anywhere, and a filled 16px square in cream is the same
/// letterpress vocabulary the rest of the set is set in.
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected, required this.reduced});

  final bool selected;
  final bool reduced;

  static const _dimension = 16.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: reduced ? Duration.zero : BrewMotion.press,
      curve: BrewMotion.pressCurve,
      width: _dimension,
      height: _dimension,
      decoration: BoxDecoration(
        color: selected ? BrewColor.cream : const Color(0x00000000),
        border: Border.all(
          color: selected ? BrewColor.cream : BrewColor.hairline,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Minus, the figure, plus. The minus is clamped to 1 at the edge by going
/// dead — a quantity of zero is not a state this row has to explain — but the
/// plus stays live past [max] and calls [onMaxTapped] instead: see the note
/// there for why a dead plus is the wrong answer at this particular cap.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.onChanged,
    required this.onMaxTapped,
    required this.max,
  });

  final int value;
  final ValueChanged<int> onChanged;

  /// What a press on plus does once [value] has already reached [max]. A
  /// pop-up rather than a dead button, the same reasoning [_CartCapSheet]
  /// gives for the cart's own cap: the reader just pressed a button expecting
  /// a result, and a control that quietly stops responding leaves them
  /// re-pressing it wondering if it registered.
  final VoidCallback onMaxTapped;

  /// The most of this one drink the reader can add right now — see
  /// [_OrderWizardScreenState._quantityCap], which is where this comes from
  /// and where the five-total reasoning lives. Passed in rather than held as
  /// a constant here because it moves with how many orders this reader
  /// already has open: it is not a fact about the stepper, it is a fact about
  /// the reader.
  final int max;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepperButton(
          label: '−',
          semanticsLabel: 'One fewer',
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: BrewSpace.grid * 7,
          child: Center(
            child: Text(
              '$value',
              style: BrewType.displayAt(22),
              semanticsLabel: '$value in this order',
            ),
          ),
        ),
        _StepperButton(
          label: '+',
          semanticsLabel: 'One more',
          // `value < max` alone would also fire the pop-up on the very first
          // frame of a reader who is already at the order cap — [max] is 0
          // there and [value] starts at 1, so `value < max` is false without
          // a press ever having landed. onMaxTapped is for presses, not for
          // paint, which is why this only reaches it from onPressed.
          onPressed: value < max ? () => onChanged(value + 1) : onMaxTapped,
        ),
      ],
    );
  }
}

class _StepperButton extends StatefulWidget {
  const _StepperButton({
    required this.label,
    required this.semanticsLabel,
    this.onPressed,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback? onPressed;

  @override
  State<_StepperButton> createState() => _StepperButtonState();
}

class _StepperButtonState extends State<_StepperButton> {
  bool _pressed = false;

  static const _dimension = 44.0;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onPressed != null;

    return BrewPressable(
      onPressed: widget.onPressed,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      pressed: _pressed,
      reduced: reduced,
      semanticsLabel: widget.semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          width: _dimension,
          height: _dimension,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              // A spent end of the range keeps its box and loses its contrast,
              // so the row holds its shape while saying which way it can move.
              color: enabled ? BrewColor.hairline : BrewColor.hairline,
            ),
            borderRadius: BorderRadius.circular(BrewSpace.radius),
          ),
          child: Text(
            widget.label,
            style: BrewType.rowTitle.copyWith(
              color: enabled ? BrewColor.cream : BrewColor.sageLight,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }
}

/// One line in the cart: what it is, how it was configured, what it costs, and
/// the one control that takes it back out.
class _CartRow extends StatelessWidget {
  const _CartRow({required this.line, required this.onRemove});

  final _CartLine line;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final detail = line.detailLine;

    return Container(
      padding: const EdgeInsets.all(BrewSpace.grid * 2),
      decoration: BoxDecoration(
        border: Border.all(color: BrewColor.hairline),
        borderRadius: BorderRadius.circular(BrewSpace.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  line.quantity > 1
                      ? '${line.quantity}× ${line.item.name}'
                      : line.item.name,
                  style: BrewType.rowTitle,
                ),
              ),
              const SizedBox(width: BrewSpace.grid),
              Text(
                _formatCents(line.totalCents),
                style: BrewType.mono.copyWith(color: BrewColor.cream),
              ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: BrewSpace.grid * 0.5),
            Text(detail, style: BrewType.rowBody),
          ],
          const SizedBox(height: BrewSpace.grid * 0.5),
          Align(
            alignment: Alignment.centerLeft,
            child: BrewMonoButton(
              label: 'Remove',
              semanticsLabel: 'Remove ${line.item.name} from the cart',
              // Alert ink, the same signal the roster's Remove carries: this
              // is the only irreversible control on the screen.
              ink: BrewColor.alert,
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pop-up a press on Review your order gets with no receipt uploaded.
///
/// Pops `true` when the reader takes the upload it offers, so the caller can
/// open the picker straight away — see
/// [_OrderWizardScreenState._showReceiptNeeded]. Dismissing any other way pops
/// null, which changes nothing and leaves them on the step.
///
/// Unlike the two cap sheets, this one is not telling the reader they have hit
/// a limit. It is telling them the step is not finished, which is a thing they
/// can act on — hence a primary button that acts rather than a "Got it" that
/// only closes.
class _ReceiptNeededSheet extends StatelessWidget {
  const _ReceiptNeededSheet();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 3,
        bottom: media.padding.bottom + BrewSpace.grid * 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Upload your receipt first.', style: BrewType.displayAt(24)),
          const SizedBox(height: BrewSpace.grid * 2),
          Text(
            'Nothing is charged in the app, so the picture of your payment is '
            'the only proof the counter has that this order was paid for. '
            'Scan the code, pay, then upload what your banking app gave you.',
            style: BrewType.rowBody,
          ),
          const SizedBox(height: BrewSpace.grid * 4),
          BrewPrimaryButton(
            label: 'Upload receipt',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: BrewSpace.grid),
          BrewTextButton(
            label: 'Not yet',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// The pop-up a press on Add to cart gets once the cart already holds
/// [_OrderWizardScreenState._maxCartLines] lines.
///
/// A sheet rather than the inline notices this used to carry: the reader just
/// pressed a button expecting it to work, so what answers that press should
/// interrupt them the way the press itself did, not print a line of text
/// under a control they have already looked away from. The same reasoning
/// [_ConfirmImportSheet](admin/admin_menu_screen.dart) gives for the admin
/// board's own confirmation.
class _CartCapSheet extends StatelessWidget {
  const _CartCapSheet({required this.max});

  final int max;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 3,
        bottom: media.padding.bottom + BrewSpace.grid * 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This order is full.', style: BrewType.displayAt(24)),
          const SizedBox(height: BrewSpace.grid * 2),
          Text(
            "This app is early in development, so one order is capped at "
            '$max drinks for now. Place this order and start a new one for '
            'anything past that.',
            style: BrewType.rowBody,
          ),
          const SizedBox(height: BrewSpace.grid * 4),
          BrewPrimaryButton(
            label: 'Got it',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// The pop-up a press on the stepper's plus gets once one drink's quantity
/// already stands at [_OrderWizardScreenState._quantityCap].
///
/// See [_CartCapSheet] for why this interrupts rather than a dead plus button
/// — the same press, the same kind of answer, one step earlier in the flow:
/// this is what a reader trying to order six of one drink hits before they
/// would ever reach the cart's own cap on a sixth *line*.
class _QuantityCapSheet extends StatelessWidget {
  const _QuantityCapSheet({
    required this.max,
    required this.activeOrders,
    required this.bankedQuantity,
  });

  final int max;

  /// How many orders this reader already has open, which [max] may have been
  /// shrunk by — see [_OrderWizardScreenState._quantityCap]. Zero draws the
  /// plain cap sentence; anything above it names the reason the number is
  /// smaller than the flat five, because a reader who has never seen five
  /// drinks in one line before will otherwise read this as an arbitrary
  /// change from the last one they hit.
  final int activeOrders;

  /// How many drinks are already banked into this order's cart, the other
  /// thing [max] may have been shrunk by. A reader who has added five drinks
  /// across a few lines already needs this named, or the sheet reads as
  /// contradicting itself: nothing at the counter, yet still no room.
  final int bankedQuantity;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final orders = activeOrders == 1 ? '1 order' : '$activeOrders orders';

    return Padding(
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 3,
        bottom: media.padding.bottom + BrewSpace.grid * 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            max == 0
                ? 'You have no room left for this order.'
                : 'That is as many as one line can hold right now.',
            style: BrewType.displayAt(24),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          Text(
            switch ((activeOrders, bankedQuantity)) {
              (0, 0) => "This app is early in development, so one drink is "
                  'capped at $max at a time. Add this line and use Add '
                  'another drink for more of the same.',
              (0, _) => "This app is early in development, so one reader can "
                  'have five drinks in one order. This order already has '
                  '$bankedQuantity, which leaves room for $max here.',
              _ => "This app is early in development, so one reader can have "
                  'five drinks in play at once, counting both what is '
                  'already at the counter and what is in this order. You '
                  'have $orders open, which leaves room for $max here.',
            },
            style: BrewType.rowBody,
          ),
          const SizedBox(height: BrewSpace.grid * 4),
          BrewPrimaryButton(
            label: 'Got it',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// The pop-up a press on Review your order or Confirm order gets once this
/// reader already has [_OrderWizardScreenState._maxActiveOrders] orders open.
///
/// See [_CartCapSheet] for why this interrupts rather than printing a line
/// under the button — the same press, the same kind of answer.
class _OrderCapSheet extends StatelessWidget {
  const _OrderCapSheet({required this.max});

  final int max;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 3,
        bottom: media.padding.bottom + BrewSpace.grid * 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You already have $max orders open.', style: BrewType.displayAt(24)),
          const SizedBox(height: BrewSpace.grid * 2),
          Text(
            'This app is early in development, so it asks you to wait for '
            'one of your open orders to finish before starting another.',
            style: BrewType.rowBody,
          ),
          const SizedBox(height: BrewSpace.grid * 4),
          BrewPrimaryButton(
            label: 'Got it',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// A hairline with a label on the left and a figure on the right — what a
/// total looks like in this vernacular.
///
/// The figure counts rather than cuts. A total is the one number on these steps
/// that answers something the reader just did — added an extra, took a line back
/// out — and a peso figure that simply reads differently on the next frame is a
/// change they have to notice by comparing it against a number they no longer
/// have. Running it up the ramp makes the movement itself the answer.
///
/// Takes cents rather than a formatted string so the tween has something to
/// interpolate: [_formatCents] then runs on each intermediate value, which is
/// what keeps the intervening frames in the same peso vernacular as the ends.
class _TotalRule extends StatelessWidget {
  const _TotalRule({required this.label, required this.cents});

  final String label;
  final int cents;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: BrewColor.hairline),
        const SizedBox(height: BrewSpace.grid * 1.5),
        Row(
          children: [
            Text(label.toUpperCase(), style: BrewType.mono),
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: cents.toDouble()),
              duration: reduced ? Duration.zero : BrewMotion.containerFade,
              curve: BrewMotion.revealCurve,
              builder: (context, value, child) => Text(
                _formatCents(value.round()),
                style: BrewType.displayAt(20),
                // The count is a flourish, not a fact a screen reader should be
                // read every frame of: the settled figure is what is announced.
                semanticsLabel: _formatCents(cents),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Everything the reader decided, as the confirm step lays it out.
class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.shop,
    required this.lines,
    required this.totalCents,
    required this.pickupName,
    required this.pickupPhone,
    required this.pickupNote,
    required this.payment,
    required this.receipt,
    required this.scheduledFor,
  });

  final BrewShop shop;
  final List<_CartLine> lines;
  final int totalCents;
  final String pickupName;
  final String pickupPhone;
  final String pickupNote;

  /// The label the order will be filed under — see `_payment` on the state.
  final String payment;

  /// What was uploaded on the payment step, or null for an order the counter
  /// collects on. Shown here as a thumbnail rather than named in words, because
  /// this step's whole job is to let the reader check what they are about to
  /// commit to, and "Receipt uploaded" is a claim rather than a check.
  final Uint8List? receipt;

  /// Null for an order made now — the summary then says "As soon as it is
  /// ready" rather than omitting the line, because a decision the reader made
  /// (even by default) belongs on the step that restates their decisions.
  final DateTime? scheduledFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FROM', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        Text(shop.displayName, style: BrewType.rowTitle),
        const SizedBox(height: BrewSpace.grid * 3),
        Text('ORDER', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        for (final line in lines) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(line.orderLine, style: BrewType.body)),
              const SizedBox(width: BrewSpace.grid),
              Text(
                _formatCents(line.totalCents),
                style: BrewType.mono.copyWith(color: BrewColor.cream),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid),
        ],
        const SizedBox(height: BrewSpace.grid),
        _TotalRule(label: 'Total', cents: totalCents),
        const SizedBox(height: BrewSpace.grid * 3),
        Text('PICKUP', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        Text(pickupName, style: BrewType.body),
        Text(pickupPhone, style: BrewType.rowBody),
        if (pickupNote.isNotEmpty) ...[
          const SizedBox(height: BrewSpace.grid * 0.5),
          Text(pickupNote, style: BrewType.rowBody),
        ],
        const SizedBox(height: BrewSpace.grid * 3),
        Text('PICKUP TIME', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        Text(
          switch (scheduledFor) {
            final at? => BrewOrder.formatWhen(at),
            null => 'As soon as it is ready',
          },
          style: BrewType.body,
        ),
        const SizedBox(height: BrewSpace.grid * 3),
        Text('PAYMENT', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        Text(payment, style: BrewType.body),
        if (receipt case final bytes?) ...[
          const SizedBox(height: BrewSpace.grid),
          Text('Receipt attached to this order.', style: BrewType.rowBody),
          const SizedBox(height: BrewSpace.grid),
          BrewMenuItemImage(bytes: bytes, dimension: 72),
        ] else
          Text(
            'Nothing was charged in the app. You settle up at the counter when '
            'you collect.',
            style: BrewType.rowBody,
          ),
      ],
    );
  }
}

/// What the reader is shown once the order is in.
///
/// Not a seventh step — the flowchart ends at confirm — but the answer to the
/// press that ended it. It restates what was ordered rather than only saying
/// "thanks", because the reader's next question is which cup is coming and to
/// what name, and the home screen's order card is a route away.
class _DoneBody extends StatelessWidget {
  const _DoneBody({
    required this.shop,
    required this.lines,
    required this.totalCents,
    required this.pickupName,
    required this.scheduledFor,
  });

  final BrewShop shop;
  final List<_CartLine> lines;
  final int totalCents;
  final String pickupName;
  final DateTime? scheduledFor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StaggerItem(
            index: 0,
            child: Text(
              switch (scheduledFor) {
                final at? =>
                  '${shop.displayName} has your order for '
                      '${BrewOrder.formatWhen(at)}. We will call for '
                      '$pickupName when it is ready — track it from the home '
                      'screen.',
                null =>
                  '${shop.displayName} has your order. We will call for '
                      '$pickupName when it is ready — track it from the home '
                      'screen.',
              },
              style: BrewType.rowBody,
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          for (final (index, line) in lines.indexed) ...[
            StaggerItem(
              index: 1 + index,
              child: Text(line.orderLine, style: BrewType.body),
            ),
            const SizedBox(height: BrewSpace.grid),
          ],
          const SizedBox(height: BrewSpace.grid),
          StaggerItem(
            index: 1 + lines.length,
            child: _TotalRule(label: 'Paid at counter', cents: totalCents),
          ),
        ],
      ),
    );
  }
}
