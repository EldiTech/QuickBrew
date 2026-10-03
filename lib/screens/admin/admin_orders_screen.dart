import 'dart:math' as math;

import 'package:flutter/material.dart' show Material, showModalBottomSheet;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../brew_admin.dart';
import '../../brew_counter.dart';
import '../../theme/brew_type.dart';
import '../../theme/tokens.dart';
import '../../widgets/brew_background.dart';
import '../../widgets/brew_buttons.dart';
import '../../widgets/brew_field.dart';
import '../../widgets/brew_filter_row.dart';
import '../../widgets/brew_reveal.dart';
import '../../widgets/brew_sheet.dart';
import '../../widgets/stagger.dart';
import 'admin_transitions.dart';

/// The Active section's own filter chips: every active phase by name, plus
/// "All" for the unfiltered queue a counter usually wants. Completed and
/// Rejected orders stay out of this row entirely — they already sit in the
/// Completed section below, which has no filter of its own to hide behind.
const _kAllPhases = 'All';
List<String> get _phaseOptions => [
      _kAllPhases,
      for (final stage in BrewOrderStage.values)
        if (stage.isActive) stage.label,
    ];

/// One store's queue, admin side: every order it has taken, and the one
/// place an order moves from received to ready to completed.
///
/// Reached only from [StoreConfigScreen](store_config_screen.dart)'s orders
/// card, so it never has to ask which store's orders it is showing and never
/// has to query across partners — a store's counter staff only ever cares about
/// the line in front of them.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({
    super.key,
    required this.partner,
    this.admin,
  });

  final BrewPartner partner;

  /// Null if Firestore is unreachable. The queue still renders; nothing on it
  /// can be advanced.
  final BrewAdmin? admin;

  static Route<void> route({
    bool reduced = false,
    required BrewPartner partner,
    BrewAdmin? admin,
  }) {
    return adminPageRoute<void>(
      reduced: reduced,
      builder: (context) => AdminOrdersScreen(partner: partner, admin: admin),
    );
  }

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  /// Subscribed once. A stream built inside `build` would be a fresh
  /// Firestore listener on every frame — the same note every other admin
  /// screen here makes.
  Stream<List<BrewOrder>>? _orders;

  /// Which order is mid-advance or mid-reject, so its own row — and its own
  /// open detail sheet, if it has one — can hold a busy state without
  /// freezing the rest of the queue. A second order finishing while the
  /// first is still in flight is the ordinary case at a counter, not an edge
  /// one.
  final Set<String> _busy = <String>{};

  /// Fires whenever [_busy] changes, so [_openDetail]'s sheet — a separate
  /// route this State's own `setState` cannot reach — has something to
  /// listen to. The row list beneath it already rebuilds from `setState`
  /// the ordinary way; this exists only for the sheet.
  final _busyNotifier = _BusyNotifier();

  String? _error;

  /// Which chip is lit on the Active section's filter row — one of
  /// [BrewOrderStage.label] for an active stage, or [_kAllPhases]. Held here,
  /// not derived, for the same reason [BrewFilterRow] leaves selection to its
  /// caller: the filter decides what the section below draws.
  String _phaseFilter = _kAllPhases;

  @override
  void initState() {
    super.initState();
    _orders = widget.admin?.ordersFor(widget.partner);
  }

  @override
  void dispose() {
    _busyNotifier.dispose();
    super.dispose();
  }

  Future<void> _advance(BrewOrder order) async {
    final admin = widget.admin;
    final next = order.stage.next;
    if (admin == null || next == null) return;

    setState(() {
      _busy.add(order.id);
      _error = null;
    });
    _busyNotifier.ping();
    final failure = await admin.advanceOrderStage(order.id, next);
    if (!mounted) return;
    setState(() {
      _busy.remove(order.id);
      _error = failure;
    });
    _busyNotifier.ping();
  }

  /// Asks for a reason, then declines the order — the sheet's own Reject
  /// button is what actually calls [BrewAdmin.rejectOrder]; this just opens
  /// the prompt and folds a failure back into the same [_error] line every
  /// other write on this screen reports through.
  Future<void> _reject(BuildContext context, BrewOrder order) async {
    final admin = widget.admin;
    if (admin == null) return;

    final reason = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrewColor.field,
      builder: (context) => const _RejectSheet(),
    );
    // Null return from a dismissed sheet is indistinguishable from an empty
    // reason typed and confirmed — `_RejectSheet` pops `''` for the latter
    // rather than null, which is what lets this tell "backed out" from "sent
    // with nothing typed" apart.
    if (reason == null || !mounted) return;

    setState(() {
      _busy.add(order.id);
      _error = null;
    });
    _busyNotifier.ping();
    final failure = await admin.rejectOrder(
      order.id,
      reason: reason.isEmpty ? null : reason,
    );
    if (!mounted) return;
    setState(() {
      _busy.remove(order.id);
      _error = failure;
    });
    _busyNotifier.ping();
  }

  Future<void> _openDetail(BuildContext context, BrewOrder order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrewColor.field,
      builder: (sheetContext) => AnimatedBuilder(
        // The sheet is a separate route, not a child of this State's own
        // build — so the setState calls `_advance`/`_reject` make while it is
        // open never reach it on their own. Rebuilding it from `_busyNotifier`
        // as well as `_orders` is what makes the button actually clear once
        // the write finishes: without this, the only thing that could repaint
        // the sheet was the stream, and Firestore emits from the *local*
        // cache the instant the write is issued and then stays quiet until
        // the next unrelated change — so the sheet caught the busy flag
        // turning on but never saw it turn back off, and sat on "Saving"
        // forever even though the write had already landed.
        animation: _busyNotifier,
        builder: (context, _) => StreamBuilder<List<BrewOrder>>(
          // The same stream this screen already holds open, not a second read
          // — so the sheet's own Advance/Reject buttons reflect a stage
          // change the moment it lands, instead of freezing the order at
          // whatever it was when the sheet opened.
          stream: _orders,
          initialData: [order],
          builder: (context, snapshot) {
            final current = (snapshot.data ?? const <BrewOrder>[])
                    .where((candidate) => candidate.id == order.id)
                    .firstOrNull ??
                order;
            return _OrderDetailSheet(
              order: current,
              busy: _busy.contains(current.id),
              onAdvance: widget.admin == null
                  ? null
                  : () => _advance(current),
              // Only an active order — not completed or already rejected — has
              // anywhere to be rejected from. The drink behind a completed
              // one is already made, and a rejected one is already rejected.
              onReject: (widget.admin == null || !current.stage.isActive)
                  ? null
                  : () => _reject(sheetContext, current),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.height <= BrewSpace.compactHeight;

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
          child: StreamBuilder<List<BrewOrder>>(
            stream: _orders,
            builder: (context, snapshot) => _sheet(
              context,
              compact: compact,
              orders: snapshot.data,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheet(
    BuildContext context, {
    required bool compact,
    required List<BrewOrder>? orders,
  }) {
    final active = [
      for (final order in orders ?? const <BrewOrder>[])
        if (order.stage.isActive) order,
    ];
    final visibleActive = [
      for (final order in active)
        if (_phaseFilter == _kAllPhases || order.stage.label == _phaseFilter)
          order,
    ];
    final completed = [
      for (final order in orders ?? const <BrewOrder>[])
        if (!order.stage.isActive) order,
    ]..sort((a, b) {
        final (left, right) = (a.placedAt, b.placedAt);
        if (left == null && right == null) return 0;
        if (left == null) return -1;
        if (right == null) return 1;
        return right.compareTo(left);
      });

    // The same running-counter idiom orders_panel.dart uses: every slot is
    // allocated in the order the rows are actually built, so a stagger index
    // can never disagree with how many rows this build produced — including
    // across the two sections, which a fixed arithmetic expression would have
    // to re-derive correctly for a null history, an empty one and every
    // length in between.
    var next = 0;
    int slot() => next++;

    final masthead = slot();
    final headline = slot();
    final subtitle = slot();
    final activeLabel = slot();
    final activeFilter = orders != null && active.isNotEmpty ? slot() : null;
    final activeRowSlots = [
      if (orders != null) for (final _ in visibleActive) slot(),
    ];
    final completedLabel = orders != null && completed.isNotEmpty ? slot() : null;
    final completedRowSlots = [
      if (completedLabel != null) for (final _ in completed) slot(),
    ];
    final staggerCount = math.max(1, next);

    return BrewSheet(
      staggerCount: staggerCount,
      children: [
        StaggerItem(index: masthead, child: _header(context)),
        SizedBox(height: brewBlockGap(compact)),
        StaggerItem(
          index: headline,
          child: Text(
            widget.partner.name,
            style: BrewType.displayAt(compact ? 28 : 34),
          ),
        ),
        const SizedBox(height: BrewSpace.grid),
        StaggerItem(
          index: subtitle,
          child: Text(
            'Every order this shop has taken, oldest first.',
            style: BrewType.rowBody,
          ),
        ),
        SizedBox(height: brewBlockGap(compact)),
        BrewReveal(
          gap: BrewSpace.grid,
          child: switch (_error) {
            final message? => Semantics(
              liveRegion: true,
              child: Text(message, style: BrewType.fieldError),
            ),
            null => null,
          },
        ),
        StaggerItem(index: activeLabel, child: const _SectionLabel('Active')),
        const SizedBox(height: BrewSpace.grid * 1.5),
        if (activeFilter != null) ...[
          StaggerItem(
            index: activeFilter,
            child: BrewFilterRow.bled(
              context,
              options: _phaseOptions,
              selected: _phaseFilter,
              onSelected: (value) => setState(() => _phaseFilter = value),
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 1.5),
        ],
        if (orders == null)
          Text('Looking up orders…', style: BrewType.rowBody)
        else if (active.isEmpty)
          Text(
            'Nothing yet. Orders land here the moment someone buys from this '
            'shop.',
            style: BrewType.rowBody,
          )
        else if (visibleActive.isEmpty)
          Text(
            'No orders in this phase right now.',
            style: BrewType.rowBody,
          )
        else
          for (final (index, order) in visibleActive.indexed)
            StaggerItem(
              index: activeRowSlots[index],
              child: _OrderRow(
                order: order,
                onTap: () => _openDetail(context, order),
              ),
            ),
        if (completedLabel != null) ...[
          SizedBox(height: brewBlockGap(compact)),
          StaggerItem(
            index: completedLabel,
            child: const _SectionLabel('Completed'),
          ),
          const SizedBox(height: BrewSpace.grid * 1.5),
          for (final (index, order) in completed.indexed)
            StaggerItem(
              index: completedRowSlots[index],
              child: _OrderRow(
                order: order,
                onTap: () => _openDetail(context, order),
              ),
            ),
        ],
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        const BrewWordmarkRow(),
        const Spacer(),
        BrewMonoButton(
          label: 'Back',
          semanticsLabel: 'Back to the store',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// A [ChangeNotifier] with nothing on it but a public way to fire —
/// [_AdminOrdersScreenState] doesn't hold any state worth listening to on
/// this object itself, only [_AdminOrdersScreenState._busy], which lives on
/// the State and can't be a [Listenable]'s own field. `notifyListeners` is
/// `@protected`, so a bare `ChangeNotifier` can't be pinged from outside its
/// own subclass; this exists only to open that door.
class _BusyNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// A section's name, in the mono label voice every other admin list uses.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(label.toUpperCase(), style: BrewType.mono),
    );
  }
}

/// What the forward button says, named for the stage it is about to reach
/// rather than a generic "Next" — the same reason the order wizard's own
/// forward button changes its label on every step.
String _actionLabel(BrewOrderStage next) => switch (next) {
      BrewOrderStage.preparing => 'Start preparing',
      BrewOrderStage.ready => 'Mark ready',
      BrewOrderStage.completed => 'Mark completed',
      BrewOrderStage.received => 'Advance',
      BrewOrderStage.rejected => 'Reject',
    };

/// An order's stage as the ink the whole screen shows it in — the active mono
/// voice for anything still moving, the loading grey [orders_panel.dart]
/// already uses for a completed customer order, and the alert ink for a
/// rejected one, since that is the one outcome here that is a problem for
/// somebody rather than a step in the ordinary flow.
TextStyle _stageStyle(BrewOrderStage stage) => switch (stage) {
      BrewOrderStage.rejected => BrewType.mono.copyWith(color: BrewColor.alert),
      final stage when stage.isActive => BrewType.mono,
      _ => BrewType.mono.copyWith(color: BrewColor.loading),
    };

/// One order, summarised: who it is for, what is in it, what it comes to, and
/// its current stage. Tapping it opens [_OrderDetailSheet], where the rest of
/// what it holds — phone, note, payment method, placed time, and the actions
/// that move or decline it — actually lives.
///
/// The ruled-row material [orders_panel.dart]'s own `_OrderRow` uses, not a
/// bounded block: this is a list to scan down, the same reasoning that gave
/// the customer's own history hairlines instead of boxes.
class _OrderRow extends StatefulWidget {
  const _OrderRow({required this.order, this.onTap});

  final BrewOrder order;
  final VoidCallback? onTap;

  @override
  State<_OrderRow> createState() => _OrderRowState();
}

class _OrderRowState extends State<_OrderRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final order = widget.order;
    final name = order.pickupName;
    final displayName = name == null || name.isEmpty ? 'Unnamed order' : name;
    final total = order.totalLabel;

    return BrewPressable(
      onPressed: widget.onTap,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: 0,
      pressed: _pressed,
      reduced: reduced,
      semanticsLabel:
          '$displayName. ${order.stage.label}. View order details.',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: BrewColor.hairline)),
          ),
          padding: const EdgeInsets.symmetric(vertical: BrewSpace.rowPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(displayName, style: BrewType.rowTitle),
                  ),
                  const SizedBox(width: BrewSpace.grid),
                  Text(
                    order.stage.label.toUpperCase(),
                    style: _stageStyle(order.stage),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(order.itemLine, style: BrewType.rowBody),
              if (order.scheduledFor case final at?) ...[
                const SizedBox(height: 4),
                // On the row, not just the detail sheet: a booking the counter
                // only learns about by opening every order is a booking missed.
                Text(
                  'FOR ${BrewOrder.formatWhen(at).toUpperCase()}',
                  style: BrewType.mono,
                ),
              ],
              if (total != null) ...[
                const SizedBox(height: 4),
                Text(total, style: BrewType.rowBody),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything one order holds, and the two controls that act on it: the
/// forward button that moves it a stage, and Reject.
///
/// Opened from [_OrderRow] as a bottom sheet rather than a pushed screen —
/// this is a look-then-act panel on data the list behind it already has, not
/// a destination of its own, which is the same reasoning
/// [admin_addons_screen.dart]'s own edit sheet follows.
///
/// Grouped into bounded cards — the hairline border and 4px radius
/// [profile_panel.dart]'s own account panel uses — rather than one column of
/// loose lines under mono eyebrows. Everything here is a fixed set of fields
/// about one order, which is exactly the shape that block is for, and the
/// person reading it is standing at a counter looking for one fact at a time:
/// what to make, who to hand it to, when it is wanted. Ruled loose, the
/// items ran into the pickup name and the schedule ran into the placed time,
/// and every gap between them was the same gap.
class _OrderDetailSheet extends StatelessWidget {
  const _OrderDetailSheet({
    required this.order,
    required this.busy,
    this.onAdvance,
    this.onReject,
  });

  final BrewOrder order;

  /// True while either [onAdvance] or [onReject] is in flight — both actions
  /// on this sheet hold together, the same way the row list they came from
  /// only ever has one write outstanding per order.
  final bool busy;

  /// Null when there is nowhere further to advance to — [BrewOrderStage.next]
  /// is null on a completed or rejected order — or when there is no admin
  /// layer to save to.
  final VoidCallback? onAdvance;

  /// Null once an order is no longer active, or with no admin layer to save
  /// to. Rejecting a completed order is not a decision this sheet offers —
  /// the drink is already made.
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final next = order.stage.next;
    final name = order.pickupName;
    final displayName = name == null || name.isEmpty ? 'Unnamed order' : name;
    final reason = order.rejectionReason;

    return Padding(
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 3,
        bottom: media.padding.bottom + BrewSpace.grid * 4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(displayName, style: BrewType.displayAt(24)),
                ),
                const SizedBox(width: BrewSpace.grid),
                Padding(
                  padding: const EdgeInsets.only(top: BrewSpace.grid),
                  child: Text(
                    order.stage.label.toUpperCase(),
                    style: _stageStyle(order.stage),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BrewSpace.grid * 3),
            _DetailCard(
              label: 'ITEMS',
              // Ruled between, not merely spaced: an item that wraps to two
              // lines — which the common one does, a drink with two add-ons —
              // is otherwise indistinguishable from two items, and "how many
              // cups am I making" is the first question this card answers.
              children: _ruled([
                // An order with nothing in it should not read as a card that
                // failed to draw — the same reasoning behind `_Detail`'s own
                // "Not set" in profile_panel.dart.
                if (order.items.isEmpty)
                  Text('No items listed', style: BrewType.body),
                for (final item in order.items)
                  Text(item, style: BrewType.body),
                if (order.totalLabel != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('TOTAL', style: BrewType.mono),
                      const Spacer(),
                      Text(order.totalLabel!, style: BrewType.rowTitle),
                    ],
                  ),
              ]),
            ),
            const SizedBox(height: BrewSpace.grid * 2),
            _pickupAndWhen(displayName),
            if (order.receiptBytes case final receipt?) ...[
              const SizedBox(height: BrewSpace.grid * 2),
              _receiptCard(receipt),
            ],
            if (reason != null) ...[
              const SizedBox(height: BrewSpace.grid * 2),
              // The one card bordered in the alert ink rather than the
              // hairline: a declined order is the outcome somebody has to
              // explain at the counter, and it should not look like another
              // field.
              _DetailCard(
                label: 'WHY IT WAS DECLINED',
                ink: BrewColor.alert,
                children: [Text(reason, style: BrewType.body)],
              ),
            ],
            if (next != null || onReject != null) ...[
              const SizedBox(height: BrewSpace.grid * 4),
              if (next != null)
                BrewPrimaryButton(
                  label: _actionLabel(next),
                  busyLabel: busy ? 'Saving' : null,
                  onPressed: (busy || onAdvance == null) ? null : onAdvance,
                ),
              if (next != null && onReject != null)
                const SizedBox(height: BrewSpace.grid),
              if (onReject != null)
                BrewTextButton(
                  label: 'Reject order',
                  ink: BrewColor.alert,
                  onPressed: (busy || onReject == null) ? null : onReject,
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// The picture the customer uploaded against the shop's payment code.
  ///
  /// Full width and large, unlike the thumbnails elsewhere in the admin side:
  /// this is a screenshot of a transfer with a reference number and an amount on
  /// it that somebody has to actually read before handing over a cup, and a
  /// 56px version of it would be a picture of a payment nobody can verify.
  ///
  /// Absent entirely on an order without one — every order placed before this
  /// step existed, and every order from a shop with no code on file, both of
  /// which the PAYMENT line above already accounts for. An empty RECEIPT card
  /// would read as a receipt that failed to load.
  ///
  /// Nothing here says the payment cleared. It says a customer sent a picture,
  /// which is exactly as much as this app knows.
  Widget _receiptCard(Uint8List receipt) {
    return _DetailCard(
      label: 'RECEIPT',
      children: [
        Text(
          'What the customer sent as proof of payment. Check it before you '
          'hand the order over.',
          style: BrewType.rowBody,
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        ClipRRect(
          borderRadius: BorderRadius.circular(BrewSpace.radius),
          child: Image.memory(
            receipt,
            width: double.infinity,
            fit: BoxFit.contain,
            // Bounded so a tall screenshot cannot push the queue's own controls
            // off the end of the sheet.
            height: 280,
            alignment: Alignment.topCenter,
            errorBuilder: (context, error, stack) => Text(
              'That picture will not open.',
              style: BrewType.rowBody,
            ),
          ),
        ),
      ],
    );
  }

  /// PICKUP and WHEN, side by side rather than stacked — the two cards a
  /// counter reads together (who it's for, when it's wanted) share a row
  /// instead of running one under the other.
  ///
  /// Falls back to PICKUP alone, full width, when there is no WHEN card to
  /// pair it with — an order with neither a schedule nor a placed time is
  /// nothing this sheet has ever shown, but the fallback keeps this honest
  /// about it rather than leaving half a row of empty space.
  Widget _pickupAndWhen(String displayName) {
    final pickup = _DetailCard(
      label: 'PICKUP',
      children: _ruled([
        _DetailLine(label: 'Name', value: displayName),
        if (order.pickupPhone != null)
          _DetailLine(label: 'Phone', value: order.pickupPhone!),
        if (order.pickupNote != null)
          _DetailLine(label: 'Note', value: order.pickupNote!),
        if (order.paymentMethod != null)
          _DetailLine(label: 'Payment', value: order.paymentMethod!),
      ]),
    );

    if (order.scheduledFor == null && order.placedAt == null) return pickup;

    final when = _DetailCard(
      label: 'WHEN',
      children: _ruled([
        if (order.scheduledFor case final at?)
          // Bolder than the Placed line under it, because this is the one
          // the counter acts on — a booked order made the moment it lands
          // is a drink going cold on the shelf.
          _DetailLine(
            label: 'Scheduled for',
            value: BrewOrder.formatWhen(at),
            style: BrewType.rowTitle,
          ),
        if (order.placedAt case final at?)
          _DetailLine(label: 'Placed', value: BrewOrder.formatWhen(at)),
      ]),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: pickup),
        const SizedBox(width: BrewSpace.grid * 2),
        Expanded(child: when),
      ],
    );
  }
}

/// The mono eyebrow over a group of lines on the detail sheet — the same
/// voice [_SectionLabel] sets for the queue's own Active/Completed headings,
/// scaled down to a field within one order rather than a section of the list.
class _DetailLabel extends StatelessWidget {
  const _DetailLabel(this.label, {this.ink});

  final String label;

  /// Overrides the mono voice's own sage. Set only by the declined card, which
  /// is bordered in [BrewColor.alert] and would otherwise carry a heading in a
  /// colour its own frame contradicts.
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        label,
        style: ink == null ? BrewType.mono : BrewType.mono.copyWith(color: ink),
      ),
    );
  }
}

/// One group of an order's facts, boxed: the eyebrow that names the group and
/// the lines under it, inside the hairline-bordered block
/// [profile_panel.dart]'s account panel established for a fixed set of fields.
///
/// A card, not a run of ruled rows, for the reason that panel gives: the
/// ledger hairline is for a list that grows — the queue behind this sheet is
/// one — and a bounded block is for a known set of fields that belong
/// together. Every card here is the latter.
class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.label,
    required this.children,
    this.ink,
  });

  final String label;
  final List<Widget> children;

  /// The border and eyebrow colour. Defaults to the 14% cream hairline every
  /// other bounded block in the app is drawn in.
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BrewSpace.grid * 2),
      decoration: BoxDecoration(
        border: Border.all(color: ink ?? BrewColor.hairline),
        borderRadius: BorderRadius.circular(BrewSpace.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailLabel(label, ink: ink),
          const SizedBox(height: BrewSpace.grid * 1.5),
          ...children,
        ],
      ),
    );
  }
}

/// The rows of a [_DetailCard], separated by the card's own hairline.
///
/// Takes the rows already built — including the `if` that dropped an absent
/// one — so a card never draws a rule above a line it does not have. Building
/// the separators inside the list literal instead would mean each row knowing
/// whether anything before it survived, which is exactly the arithmetic the
/// stagger slots on this screen avoid for the same reason.
List<Widget> _ruled(List<Widget> rows) => [
      for (final (index, row) in rows.indexed) ...[
        if (index > 0) const _CardRule(),
        row,
      ],
    ];

/// A full-width hairline between two rows inside a card.
class _CardRule extends StatelessWidget {
  const _CardRule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BrewSpace.grid * 1.5),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: BrewColor.hairline),
      ),
    );
  }
}

/// A mono label over its value, inside a card — the shape
/// [profile_panel.dart]'s `_Detail` sets for a fact that cannot be typed in.
///
/// The label is what makes a boxed group scannable rather than merely boxed:
/// a phone number and a payment method stacked as bare body lines are two
/// facts the reader has to work out from their contents.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value, this.style});

  /// Uppercased here, so callers pass it in sentence case.
  final String label;

  final String value;

  /// Overrides the body voice — the scheduled time is set in [BrewType.rowTitle]
  /// because it is the one line on this sheet the counter acts on.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: BrewType.mono),
        const SizedBox(height: 6),
        Text(value, style: style ?? BrewType.body),
      ],
    );
  }
}

/// The confirmation for declining an order: an optional reason, and the one
/// button that sends it. Pops the typed text (possibly empty) on Reject, or
/// null if the admin backs out — see the note on
/// [_AdminOrdersScreenState._reject] for why those two are told apart.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet();

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 3,
        bottom: media.viewInsets.bottom + media.padding.bottom + BrewSpace.grid * 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reject this order?', style: BrewType.displayAt(24)),
          const SizedBox(height: BrewSpace.grid * 2),
          Text(
            'This tells the customer their order will not be made. It cannot '
            'be undone.',
            style: BrewType.rowBody,
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          BrewField(
            label: 'Reason',
            controller: _reasonController,
            hint: 'Optional — shown with the order later',
            helper: 'Optional',
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: BrewSpace.grid * 4),
          BrewPrimaryButton(
            label: 'Reject order',
            onPressed: () =>
                Navigator.of(context).pop(_reasonController.text.trim()),
          ),
          const SizedBox(height: BrewSpace.grid),
          BrewTextButton(
            label: 'Keep the order',
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ],
      ),
    );
  }
}
