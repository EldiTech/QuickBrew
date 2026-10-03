import 'package:flutter/material.dart' show Material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/brew_buttons.dart';
import '../widgets/brew_icons.dart';
import '../widgets/brew_sheet.dart';
import '../widgets/order_track.dart';
import '../widgets/shop_mark.dart';
import '../widgets/stagger.dart';

/// Where Track order leads: one order, full screen, live.
///
/// The home screen's card already says everything here — it is drawn from the
/// same shared pieces in widgets/order_track.dart — but a card on a scrolling
/// panel has to share the frame with a greeting and two shop cards, which is
/// what caps its item list at three and holds the facts to two. This screen
/// has the frame to itself, so both limits lift: every drink gets its own row,
/// and what the reader paid and when they placed the order join pickup and the
/// estimate rather than being left off.
///
/// Still watches the same order the card does. [BrewCounter.order] rides the
/// one Firestore subscription this reader's orders already keep open, so a
/// stage the shop advances while this screen is on top updates it exactly as
/// live as the card underneath — there is no second source of truth to fall
/// out of step with the first.
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({
    super.key,
    required this.order,
    this.shop,
    this.session,
    this.counter,
  });

  /// The order as the card that opened this screen already had it, so the
  /// first frame renders instantly rather than waiting on a second read of
  /// something the reader just tapped.
  final BrewOrder order;

  /// The board's record of the shop this order is with — its logo, and
  /// whatever it currently calls itself. See the same field on the home
  /// screen's own card, which this mirrors.
  final BrewShop? shop;

  /// Whose order this is. Needed to open the live subscription; without a
  /// session the screen still renders [order] exactly as handed to it, just
  /// without anything moving after that.
  final BrewSession? session;

  final BrewCounter? counter;

  static Route<void> route({
    bool reduced = false,
    required BrewOrder order,
    BrewShop? shop,
    BrewSession? session,
    BrewCounter? counter,
  }) {
    final duration = reduced ? Duration.zero : BrewMotion.transit;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          OrderTrackingScreen(
        order: order,
        shop: shop,
        session: session,
        counter: counter,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  /// Held for the life of the screen rather than rebuilt in [build] — the
  /// same reasoning the home screen gives for its own subscriptions.
  Stream<BrewOrder?>? _order;

  @override
  void initState() {
    super.initState();
    final counter = widget.counter;
    final uid = widget.session?.uid;
    if (counter == null || uid == null) return;
    _order = BrewCounter.latest(counter.order(uid, widget.order.id));
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
          child: StreamBuilder<BrewOrder?>(
            stream: _order,
          builder: (context, snapshot) {
            // Falls back to what the card already knew rather than to a
            // loading state: the reader just tapped this order, so there is
            // never a moment this screen knows less about it than they do.
            // A live answer of null would mean the order left this reader's
            // own list, which nothing in this app does — see the note on
            // [BrewCounter.order] — so it is read as "not live yet" rather
            // than as the order having vanished.
            final order = snapshot.data ?? widget.order;
            // No subscription at all — no counter, no session — reads the
            // same as one that failed: either way, nothing is going to move
            // on this screen after this frame.
            final stale = _order == null || snapshot.hasError;
            return _sheet(context, compact: compact, order: order, stale: stale);
          },
        ),
      ),
    ),
  );
}

  Widget _sheet(
    BuildContext context, {
    required bool compact,
    required BrewOrder order,
    required bool stale,
  }) {
    final shop = widget.shop;
    final name = shop?.displayName ?? order.shopName;
    final estimate = order.estimate;
    final scheduled = order.scheduledFor;
    final rejected = order.stage == BrewOrderStage.rejected;
    final now = DateTime.now();

    var next = 0;
    int slot() => next++;

    final header = slot();
    final headline = slot();
    final summary = slot();
    final track = slot();
    final itemSlots = [for (final _ in order.items) slot()];
    final facts = slot();
    final reasonSlot = rejected ? slot() : null;
    final metaSlot = slot();

    return BrewSheet(
      staggerCount: next,
      children: [
        StaggerItem(index: header, child: _header(context)),
        SizedBox(height: brewBlockGap(compact)),
        StaggerItem(
          index: headline,
          child: Text(
            'Tracking your order.',
            style: BrewType.displayAt(compact ? 28 : 34),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 3),
        StaggerItem(
          index: summary,
          child: _Summary(shop: shop, name: name, order: order),
        ),
        const SizedBox(height: BrewSpace.grid * 2),
        StaggerItem(
          index: track,
          child: StageTrack(step: order.step, steps: BrewOrder.steps),
        ),
        const SizedBox(height: BrewSpace.grid * 2),
        const CardRule(),
        for (final (index, line) in order.items.indexed) ...[
          if (index > 0) ...[
            const SizedBox(height: BrewSpace.grid * 1.5),
            const CardRule(dashed: true),
          ],
          const SizedBox(height: BrewSpace.grid * 1.5),
          StaggerItem(
            index: itemSlots[index],
            child: OrderItemRow(split: splitOrderLine(line)),
          ),
          const SizedBox(height: BrewSpace.grid * 1.5),
        ],
        const CardRule(),
        const SizedBox(height: BrewSpace.grid * 3),
        StaggerItem(
          index: facts,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: OrderFact(
                    icon: BrewIcon.calendar,
                    label: 'Pickup',
                    value: switch (scheduled) {
                      final at? =>
                        '${BrewOrder.formatDay(at, now)} · '
                            '${BrewOrder.formatClock(at)}',
                      null => 'As soon as ready',
                    },
                    meta: switch (scheduled) {
                      final at? => BrewOrder.formatDate(at, year: true),
                      null => 'No time set',
                    },
                  ),
                ),
                if (estimate != null) ...[
                  const SizedBox(width: BrewSpace.grid * 1.5),
                  Container(width: 1, color: BrewColor.hairline),
                  const SizedBox(width: BrewSpace.grid * 1.5),
                  Expanded(
                    child: OrderFact(
                      icon: BrewIcon.clock,
                      label: 'Estimated time',
                      value: estimate,
                      meta: 'Preparation time',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (rejected && reasonSlot != null) ...[
          const SizedBox(height: BrewSpace.grid * 3),
          StaggerItem(
            index: reasonSlot,
            child: _RejectionNote(reason: order.rejectionReason),
          ),
        ],
        const SizedBox(height: BrewSpace.grid * 3),
        StaggerItem(
          index: metaSlot,
          child: _Meta(order: order),
        ),
        if (stale) ...[
          const SizedBox(height: BrewSpace.grid * 2),
          // Not staggered and not blocking: the reader already has every fact
          // above from the order the card handed over, so a failed
          // subscription is a footnote here rather than a reason to hide the
          // screen behind an error the way a first-ever read would be.
          Text(
            'Live updates are unavailable. Pull down or reopen this order '
            'to check for changes.',
            style: BrewType.rowBody.copyWith(color: BrewColor.loading),
          ),
        ],
      ],
    );
  }

  /// The same lockup every pushed screen carries, so the cup does not move.
  Widget _header(BuildContext context) {
    return Row(
      children: [
        const BrewWordmarkRow(),
        const Spacer(),
        BrewMonoButton(
          label: 'Back',
          semanticsLabel: 'Back to Home',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// The shop's mark, its name, the order's reference, and where it has got to
/// — the same header the home screen's card carries, just not wrapped in a
/// press: this whole screen already is where Track order goes, so there is
/// nothing further for the block itself to lead to.
class _Summary extends StatelessWidget {
  const _Summary({required this.shop, required this.name, required this.order});

  final BrewShop? shop;
  final String name;
  final BrewOrder order;

  static const _markSize = 40.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shop != null) ...[
          BrewShopMark(shop: shop!, dimension: _markSize),
          const SizedBox(width: BrewSpace.grid * 1.5),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: BrewType.rowTitle),
              const SizedBox(height: 4),
              Text('ORDER #${order.reference}', style: BrewType.mono),
            ],
          ),
        ),
        const SizedBox(width: BrewSpace.grid),
        Flexible(child: StagePill(stage: order.stage)),
      ],
    );
  }
}

/// What the shop said when it turned this order down, if it said anything —
/// see [BrewOrder.rejectionReason]. Tinted into the alert ink rather than
/// boxed in the panel fill everything else on this screen sits on: this is the
/// one fact here the reader has to act on rather than simply read.
class _RejectionNote extends StatelessWidget {
  const _RejectionNote({required this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BrewSpace.grid * 2),
      decoration: BoxDecoration(
        border: Border.all(color: BrewColor.alert.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(BrewSpace.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHY IT WAS DECLINED',
            style: BrewType.mono.copyWith(color: BrewColor.alert),
          ),
          const SizedBox(height: BrewSpace.grid),
          Text(
            reason ?? 'The shop did not give a reason.',
            style: BrewType.rowBody,
          ),
        ],
      ),
    );
  }
}

/// When this order was placed and what it came to — the two facts a card on a
/// shared panel has no room for but a screen about one order does.
class _Meta extends StatelessWidget {
  const _Meta({required this.order});

  final BrewOrder order;

  @override
  Widget build(BuildContext context) {
    final placedAt = order.placedAt;
    final total = order.totalLabel;
    if (placedAt == null && total == null) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (placedAt != null)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PLACED', style: BrewType.mono),
                const SizedBox(height: 4),
                Text(BrewOrder.formatWhen(placedAt), style: BrewType.bodyMedium),
              ],
            ),
          ),
        if (total != null)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOTAL', style: BrewType.mono),
                const SizedBox(height: 4),
                Text(total, style: BrewType.bodyMedium),
              ],
            ),
          ),
      ],
    );
  }
}
