import 'dart:math' as math;

import 'package:flutter/material.dart' show Material, Icons, Icon;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/brew_buttons.dart';
import '../widgets/brew_icons.dart';
import '../widgets/brew_sheet.dart';
import '../widgets/cup_mark.dart';
import '../widgets/order_track.dart';
import '../widgets/shop_mark.dart';
import '../widgets/stagger.dart';
import 'order_tracking_screen.dart';
import 'orders_panel.dart';
import 'profile_panel.dart';

/// Which of the three tabs is showing.
enum BrewTab {
  home('Home'),
  orders('Orders'),
  profile('Profile');

  const BrewTab(this.label);

  final String label;
}

/// Where a session goes. One screen, one question: which coffee shop?
///
/// Everything on it is either the answer to that question or the one thing that
/// outranks it — an order already being made. There are no rewards, no
/// promotions, no nearby locations, no recent orders, no recommendations, no
/// favourites, no reorder, no deals, no points, and no banners. Each of those was
/// available to put here and each would have pushed the two shop cards further
/// down a screen whose entire job is to get a thumb onto one of them.
///
/// ## About the cards
///
/// The landing screen's ledger is explicitly not cards — no fills, no rounded
/// containers, no shadows — and that holds for reading. This screen is not for
/// reading: it asks the reader to pick one of exactly two things, and two ruled
/// rows in a list of rows do not read as two choices of equal weight. So the
/// shops get bounded blocks, drawn in the ledger's own materials: the 14% cream
/// hairline as a border rather than a rule, the committed 4px radius, and no fill
/// or shadow anywhere. A panel, in other words, not a Material card. Each block
/// is one control end to end, so the whole thing is the tap target and there is no
/// small button inside a big one competing for the same press.
///
/// ## Cart
///
/// Not in the navigation. The brief makes it conditional on readers needing
/// frequent access to a cart, and nothing in this build has a cart to access — a
/// fourth tab leading to a screen that cannot exist yet is worse than three that
/// work.
///
/// An order the reader saved part-way through does now outlive the wizard, but
/// it does not live here — see the Saved filter on `OrdersPanel`. A draft is an
/// order too, just one that has not been placed yet, so it sits behind the same
/// tab as the rest of the reader's orders rather than adding a section to this
/// screen or a fourth tab of its own.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    this.counter,
    this.onViewMenu,
    this.onResumeDraft,
    this.onDiscardDraft,
    this.onSignOut,
    this.now,
  });

  /// Who is signed in. The greeting's name and the uid every order lookup is
  /// keyed on.
  final BrewSession session;

  /// The Firestore layer, or null if it could not come up. Null renders the
  /// stated absences — "Hours unavailable", no active order — rather than an
  /// error, because a reader who cannot be told whether a shop is open can still
  /// be shown which two shops there are.
  final BrewCounter? counter;

  /// Fired by a shop card. The one path off this screen that matters.
  final void Function(BrewShop shop)? onViewMenu;

  /// Fired by the Saved order card on the Orders tab. Reopens the wizard on the
  /// step the reader left, which needs the board resolved first — so it is
  /// handled where the counter lives rather than here. See `_resumeDraft` in
  /// main.dart. Passed straight through to `OrdersPanel`.
  final void Function(BrewDraft draft)? onResumeDraft;

  /// The Saved order card's other control. Throws the draft away, which makes the
  /// card go. Also passed straight through to `OrdersPanel`.
  final void Function(BrewDraft draft)? onDiscardDraft;

  /// The Profile tab's one action.
  final VoidCallback? onSignOut;

  /// Injectable clock, so the greeting can be tested at 9am and at 9pm without
  /// waiting twelve hours. Read once per build, not cached: a screen left open
  /// past noon should not still be saying good morning the next time it rebuilds.
  final DateTime? now;

  /// Fades in, like the login and create-account screens, and for the same
  /// reason: the cup sits in the identical slot here as it does where the splash
  /// puts it down, so anything that slid the page would drag a mark that has to
  /// hold still.
  static Route<void> route({
    bool reduced = false,
    required BrewSession session,
    BrewCounter? counter,
    void Function(BrewShop shop)? onViewMenu,
    void Function(BrewDraft draft)? onResumeDraft,
    void Function(BrewDraft draft)? onDiscardDraft,
    VoidCallback? onSignOut,
  }) {
    final duration = reduced ? Duration.zero : BrewMotion.transit;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(
        session: session,
        counter: counter,
        onViewMenu: onViewMenu,
        onResumeDraft: onResumeDraft,
        onDiscardDraft: onDiscardDraft,
        onSignOut: onSignOut,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BrewTab _tab = BrewTab.home;

  /// Opened by the header's bell, and not a tab: notices are something that
  /// happened, not one of the three places the reader lives. It sits over the
  /// current tab and closes back onto it, so the nav selection never lies about
  /// where they are.
  bool _notices = false;

  /// Held for the life of the screen rather than rebuilt in [build].
  ///
  /// A `StreamBuilder` handed a fresh stream every build re-subscribes every
  /// build, and a Firestore subscription that is torn down and remade on each
  /// frame both refetches and flickers back through its no-data state. These are
  /// created once, in [initState], from a uid that cannot change while this
  /// widget is mounted — a different account is a different screen.
  ///
  /// Held once and read by more than one panel, which is why every one of them
  /// is wrapped in [BrewCounter.latest]: a bare Firestore stream replays
  /// nothing, so the second panel to subscribe hears silence. Read the note on
  /// that method — it is the whole reason the Orders tab used to sit on
  /// "Looking up your orders…" until the reader left the tab and came back.
  Stream<List<BrewShop>>? _shops;
  Stream<List<BrewOrder>>? _activeOrders;
  Stream<List<BrewOrder>>? _orders;
  Stream<BrewDraft?>? _draft;

  /// The notices this reader has already had in front of them, as
  /// "orderId:stage" pairs, loaded from and written back to this device.
  ///
  /// Pairs rather than a last-seen timestamp, because an order carries no
  /// "stage changed at" field — an order placed last week that turns ready
  /// today has nothing newer than a week-old [BrewOrder.placedAt] to compare,
  /// and a timestamp cut would sleep straight through the one moment worth
  /// waking for. The pair changes when the stage does, which is exactly when
  /// the notice is new again.
  ///
  /// On-device rather than in Firestore: which notices this reader has laid
  /// eyes on is a fact about this screen, not about the order, and it is not
  /// worth a write per bell press to make two phones agree the badge is gone.
  Set<String> _seenNotices = <String>{};

  SharedPreferences? _prefs;

  String get _seenKey => 'noticesSeen:${widget.session.uid}';

  @override
  void initState() {
    super.initState();
    _loadSeenNotices();
    final counter = widget.counter;
    if (counter == null) return;
    _shops = BrewCounter.latest(counter.shops());
    _activeOrders =
        BrewCounter.latest(counter.activeOrders(widget.session.uid));
    _orders = BrewCounter.latest(counter.orders(widget.session.uid));
    _draft = BrewCounter.latest(counter.draft(widget.session.uid));
  }

  /// Best-effort: a device whose preference store will not open simply counts
  /// every current notice as unseen, which errs on the side of telling the
  /// reader something is there.
  Future<void> _loadSeenNotices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _seenNotices = (prefs.getStringList(_seenKey) ?? const []).toSet();
      });
    } catch (error) {
      debugPrint('QuickBrew → seen notices unavailable: $error');
    }
  }

  /// Called by the notices panel with whatever it is currently showing — a
  /// notice on that panel has been seen by definition, so this is the one
  /// place the set grows. Fired again as data lands while the panel is open,
  /// which is what keeps an order that turns ready mid-look from badging the
  /// moment the panel closes.
  void _markNoticesSeen(List<BrewOrder> notices) {
    // Fired from a post-frame callback, which can outlive this screen.
    if (!mounted) return;
    final keys = {for (final order in notices) '${order.id}:${order.stage.name}'};
    if (_seenNotices.containsAll(keys)) return;
    setState(() => _seenNotices.addAll(keys));
    _prefs?.setStringList(_seenKey, _seenNotices.toList());
  }

  /// Morning until noon, afternoon until six, evening after that. Read off the
  /// device clock, because the alternative is a screen that says good morning at
  /// nine in the evening — which is the exact kind of detail that tells a reader
  /// the greeting is decoration rather than someone speaking to them.
  String get _greeting {
    final hour = (widget.now ?? DateTime.now()).hour;
    final part = switch (hour) {
      >= 5 && < 12 => 'Good morning',
      >= 12 && < 18 => 'Good afternoon',
      _ => 'Good evening',
    };
    // No name, no address. "Good morning, there" is worse than "Good morning".
    return switch (widget.session.firstName) {
      final name? => '$part, $name!',
      null => '$part!',
    };
  }

  void _select(BrewTab tab) {
    if (_tab == tab && !_notices) return;
    setState(() {
      _tab = tab;
      _notices = false;
    });
  }

  /// What Track order does: pushes the order's own screen rather than
  /// switching to the Orders tab, which is where it used to land.
  ///
  /// [shop] comes from the same resolved list the card itself drew its logo
  /// and name from, so the tracking screen opens already agreeing with the
  /// card the reader just pressed rather than waiting on its own read of the
  /// board to catch up.
  void _openTracking(BrewOrder order, BrewShop? shop) {
    Navigator.of(context).push(
      OrderTrackingScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        order: order,
        shop: shop,
        session: widget.session,
        counter: widget.counter,
      ),
    );
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
          child: Column(
            children: [
            // The nav is outside the scroll view, so it is on the screen at every
            // scroll offset and at every text scale. Nothing here clamps the text
            // scaler the way the landing screen has to: this screen scrolls, so
            // 200% text makes it longer rather than making Home unreachable.
            Expanded(
              child: AnimatedSwitcher(
                // A tab is a screen the reader crossed to, so crossing to it
                // costs what crossing to one costs: the same 420ms fade every
                // route in this app is pushed on.
                //
                // The outgoing panel is the half that was missing. The incoming
                // one always animated — each panel is its own widget type, so
                // switching tabs unmounts the old and mounts a new [BrewSheet]
                // whose [StaggerGroup] plays from zero — but the old panel simply
                // stopped existing on the frame the new one appeared. Half a
                // transition reads worse than none: content rising into place
                // over something that vanished.
                //
                // Fading a route in while the screen inside it staggers is
                // already this app's grammar — see [LoginScreen.route], where the
                // 420ms fade and the form's own entrance overlap by design. This
                // is that, for the three destinations that are not routes.
                duration: reduced ? Duration.zero : BrewMotion.transit,
                switchInCurve: BrewMotion.crossFadeCurve,
                switchOutCurve: BrewMotion.crossFadeCurve,
                // The default centres its children under loose constraints,
                // which would hand a scroll view a viewport the height of its own
                // content and let the two panels change size under the crossfade.
                // Expanded, so both are laid out in exactly the box they occupy
                // alone.
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [
                    // The panel on its way out is still mounted for the length
                    // of the fade, and for that time it must be neither
                    // touchable nor readable: it is under the incoming one, so a
                    // press landing in a gap between the new panel's elements
                    // would otherwise reach the old panel's control, and a screen
                    // reader would be handed two tabs' worth of content at once.
                    // The same pair of guards the splash holds over the landing
                    // screen, for the same reason.
                    for (final child in previous)
                      ExcludeSemantics(child: IgnorePointer(child: child)),
                    ?current,
                  ],
                ),
                child: _body(compact),
              ),
            ),
            _BrewNav(
              current: _notices ? null : _tab,
              onSelect: _select,
              bottomInset: media.padding.bottom,
            ),
          ],
        ),
      ),
    ),
  );
  }

  /// Which panel is under the nav.
  ///
  /// The three tabs live in their own files — this is a switch over four
  /// destinations, not a place to lay any of them out. Each takes only [compact],
  /// because insets are [BrewSheet]'s business and a panel's one size decision is
  /// how large to set its display line.
  Widget _body(bool compact) {
    if (_notices) {
      return _NoticesPanel(
        compact: compact,
        orders: _orders,
        onSeen: _markNoticesSeen,
        onClose: () => setState(() => _notices = false),
      );
    }
    return switch (_tab) {
      BrewTab.home => _HomePanel(
        compact: compact,
        session: widget.session,
        greeting: _greeting,
        // The same injectable clock the greeting reads, for the same reason:
        // the order card's pickup line says "Today" or "Tomorrow", and that is
        // only true relative to a clock a test can set.
        now: widget.now,
        shops: _shops,
        // What the shops were the last time anything asked, so the cards open on
        // the real names instead of renaming themselves a beat later. Read on
        // every build rather than captured in initState: the reader can leave
        // this tab and come back, and the later visit should start from the
        // fresher answer.
        knownShops: widget.counter?.lastShops,
        activeOrders: _activeOrders,
        orders: _orders,
        seenNotices: _seenNotices,
        onViewMenu: widget.onViewMenu,
        onNotices: () => setState(() => _notices = true),
        onProfile: () => _select(BrewTab.profile),
        onTrackOrder: _openTracking,
      ),
      BrewTab.orders => OrdersPanel(
        compact: compact,
        orders: _orders,
        draft: _draft,
        shopsForDraft: widget.counter?.lastShops,
        onResumeDraft: widget.onResumeDraft,
        onDiscardDraft: widget.onDiscardDraft,
        onTrackOrder: _openTracking,
        onBrowseShops: () => _select(BrewTab.home),
      ),
      BrewTab.profile => ProfilePanel(
        compact: compact,
        session: widget.session,
        shops: _shops,
        knownShops: widget.counter?.lastShops,
        onSignOut: widget.onSignOut,
      ),
    };
  }
}

/// The screen the brief is about.
class _HomePanel extends StatelessWidget {
  const _HomePanel({
    required this.compact,
    required this.session,
    required this.greeting,
    required this.now,
    required this.shops,
    required this.knownShops,
    required this.activeOrders,
    required this.orders,
    required this.seenNotices,
    required this.onViewMenu,
    required this.onNotices,
    required this.onProfile,
    required this.onTrackOrder,
  });

  final bool compact;
  final BrewSession session;
  final String greeting;

  /// See [HomeScreen.now]. Null is the device clock.
  final DateTime? now;

  final Stream<List<BrewShop>>? shops;

  /// The last snapshot [BrewCounter] saw, if it has seen one. Only ever the
  /// first frame's answer — [shops] is what the cards actually follow.
  final List<BrewShop>? knownShops;

  /// Every order this reader is currently waiting on, newest first — not just
  /// the one closest to done. A reader with two open orders should see both
  /// cards and be able to Track either, rather than the older one silently
  /// dropping off the screen until the newer one finishes.
  final Stream<List<BrewOrder>>? activeOrders;

  /// Every order, for the bell's badge — the same stream the notices panel
  /// reads, so the number on the bell and the rows behind it cannot disagree.
  final Stream<List<BrewOrder>>? orders;

  /// See `_HomeScreenState._seenNotices`.
  final Set<String> seenNotices;

  final void Function(BrewShop shop)? onViewMenu;
  final VoidCallback onNotices;
  final VoidCallback onProfile;

  /// Fired with the order and the board's own record of the shop it is
  /// with — see the note on [_OrderCard.shop] for why the shop travels
  /// alongside the order rather than being looked up again downstream.
  final void Function(BrewOrder order, BrewShop? shop) onTrackOrder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BrewOrder>>(
      stream: activeOrders,
      builder: (context, orderSnapshot) {
        // Absent, not empty. There is no "no active orders" panel to render,
        // because a section that only ever says nothing is happening is a section
        // the reader has to read past every single time to get to the shops.
        final activeOrders = orderSnapshot.data ?? const <BrewOrder>[];
        return StreamBuilder<List<BrewOrder>>(
          stream: orders,
          builder: (context, ordersSnapshot) {
            final unseen = [
              for (final each in ordersSnapshot.data ?? const <BrewOrder>[])
                if (_NoticesPanel._isNotice(each.stage) &&
                    !seenNotices.contains('${each.id}:${each.stage.name}'))
                  each,
            ].length;
            // Subscribed once for the whole sheet rather than around the shop
            // column alone, which is where it used to sit. The order card names
            // the shop the order is with and draws its logo, so the two blocks
            // are reading the same board — and two subscriptions to it is two
            // chances for the card to still say "Drip & Co" while the block
            // below it has already been renamed.
            return StreamBuilder<List<BrewShop>>(
              stream: shops,
              initialData: knownShops,
              builder: (context, shopsSnapshot) {
                final both = shopsSnapshot.data ??
                    (shops == null ? BrewShop.unavailable : BrewShop.pending);
                return _sheet(
                  activeOrders: activeOrders,
                  shops: both,
                  unseenNotices: unseen,
                );
              },
            );
          },
        );
      },
    );
  }

  /// The panel, with however many of its optional blocks are showing.
  ///
  /// The stagger indices are dealt from a running counter rather than written
  /// out, which they were until this screen had two optional blocks instead of
  /// one. With two, every index below the first of them is a different arithmetic
  /// expression per combination — four of them — and `staggerCount` has to agree
  /// with all four or [StaggerGroup] asserts inside [Interval]. A counter cannot
  /// disagree with itself: it is incremented at each row in the order the rows
  /// are built, and the total it ends on is the count.
  Widget _sheet({
    required List<BrewOrder> activeOrders,
    required List<BrewShop> shops,
    required int unseenNotices,
  }) {
    var next = 0;
    int slot() => next++;

    // Header, greeting, sub.
    final masthead = slot();
    final tagSlot = slot();
    final greetingSlot = slot();
    final subSlot = slot();
    final orderLabel = activeOrders.isEmpty ? null : slot();
    // One slot per active order, in the same order the cards are drawn in.
    final orderCardSlots = [for (final _ in activeOrders) slot()];
    final shopsLabel = slot();
    // Both shops, always two — see [BrewShop.pending].
    final shopSlots = [for (final _ in BrewPartner.values) slot()];

    // The board's own record of the shop each active order is with, or null
    // for an order naming a partner this build does not know — see
    // [_OrderCard.shop]. Resolved once here and handed to both the card and
    // Track order, so the screen Track order opens cannot name the shop any
    // differently than the card the reader just pressed did.
    BrewShop? shopFor(BrewOrder order) =>
        shops.where((shop) => shop.partner == order.partner).firstOrNull;

    return BrewSheet(
      staggerCount: next,
      children: [
        StaggerItem(
          index: masthead,
          child: _Masthead(
            session: session,
            unseenNotices: unseenNotices,
            onNotices: onNotices,
            onProfile: onProfile,
          ),
        ),
        SizedBox(height: brewBlockGap(compact)),
        StaggerItem(
          index: tagSlot,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: BrewColor.cream.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: BrewColor.cream.withValues(alpha: 0.14),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.coffee_rounded,
                    size: 12,
                    color: BrewColor.sageLight,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'QUICKBREW NETWORK',
                    style: BrewType.mono.copyWith(
                      fontSize: 9.5,
                      letterSpacing: 1.4,
                      color: BrewColor.sageLight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: BrewColor.sageLight,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'DUAL PASS',
                    style: BrewType.mono.copyWith(
                      fontSize: 8.5,
                      letterSpacing: 1.0,
                      color: BrewColor.cream.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        StaggerItem(
          index: greetingSlot,
          child: Text(greeting, style: BrewType.displayAt(compact ? 28 : 34)),
        ),
        const SizedBox(height: BrewSpace.grid * 0.75),
        StaggerItem(
          index: subSlot,
          child: Text(
            'What would you like today?',
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.76),
            ),
          ),
        ),
        SizedBox(height: brewBlockGap(compact)),
        // Keyed, every one of them, because these blocks appear and disappear
        // underneath the ones that follow them.
        //
        // A Column's children are matched to their elements by position when
        // they carry no keys, so an order arriving mid-session slid the shops
        // eyebrow into the slot the order eyebrow now wants — and Flutter,
        // seeing the same widget type in the same slot, reused its element.
        // The reused [StaggerItem] has already played its entrance, so
        // "Active order" arrived at full opacity while the eyebrow it pushed
        // down animated in as though *it* were the new thing. Keys tell the
        // truth about which is which: the order block is new and enters, the
        // eyebrow below it is the same widget that was already on screen and
        // simply moves.
        if (orderLabel != null) ...[
          StaggerItem(
            key: const ValueKey('order-label'),
            index: orderLabel,
            child: _SectionLabel(
              activeOrders.length > 1 ? 'Active orders' : 'Active order',
              icon: Icons.receipt_long_rounded,
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 1.5),
          for (final (index, order) in activeOrders.indexed) ...[
            if (index > 0) const SizedBox(height: BrewSpace.grid * 1.5),
            StaggerItem(
              // Keyed on the order's own id rather than position: with more
              // than one card, position alone cannot tell a card that moved
              // (a newer order overtaking an older one — see [_newestFirst])
              // apart from one that was replaced, and the note above on why
              // these blocks are keyed at all applies just as much between
              // them as it does to the block below them.
              key: ValueKey('order-card-${order.id}'),
              index: orderCardSlots[index],
              child: _OrderCard(
                order: order,
                shop: shopFor(order),
                now: now,
                onTrack: () => onTrackOrder(order, shopFor(order)),
              ),
            ),
          ],
          SizedBox(height: brewBlockGap(compact)),
        ],
        StaggerItem(
          key: const ValueKey('shops-label'),
          index: shopsLabel,
          child: const _SectionLabel(
            'Choose a coffee shop',
            icon: Icons.storefront_rounded,
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        // Both shops, always, in a fixed order, laid out identically. See
        // BrewCounter.shops: which two there are and where they sit is not
        // something the network gets a vote on.
        for (final (index, shop) in shops.indexed) ...[
          if (index > 0) const SizedBox(height: BrewSpace.grid * 1.5),
          StaggerItem(
            // Clamped, because [shops] comes from a snapshot and the slots were
            // dealt from the enum: a third `shops` document cannot reach past
            // the end of the timeline. It cannot change how many cards are
            // drawn either — see [BrewCounter.shops] — this is the belt to that
            // braces.
            index: shopSlots[math.min(index, shopSlots.length - 1)],
            child: _ShopCard(
              shop: shop,
              onViewMenu: onViewMenu == null ? null : () => onViewMenu!(shop),
            ),
          ),
        ],
      ],
    );
  }
}

/// Cup, then the two header actions. No wordmark: the greeting under it is this
/// screen's masthead, and a signed-in reader does not need to be told which app
/// they opened. The cup stays because it is the same 40px mark in the same slot
/// the splash puts it down in, which is what makes the handover onto this screen
/// look like the cup never moved.
class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.session,
    required this.unseenNotices,
    required this.onNotices,
    required this.onProfile,
  });

  final BrewSession session;
  final int unseenNotices;
  final VoidCallback onNotices;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ExcludeSemantics(
          child: CupMark(
            dimension: BrewMotion.cupLandingSize,
            progress: 1,
            strokeWidth: BrewMotion.cupLandingStroke,
          ),
        ),
        const Spacer(),
        _HeaderActionButton(
          icon: BrewIcon.notifications,
          badgeCount: unseenNotices,
          semanticsLabel: unseenNotices == 0
              ? 'Notifications'
              : 'Notifications, $unseenNotices new',
          onPressed: onNotices,
        ),
        const SizedBox(width: 8),
        _HeaderActionButton(
          icon: BrewIcon.profile,
          semanticsLabel: 'Your profile',
          onPressed: onProfile,
        ),
      ],
    );
  }
}

class _HeaderActionButton extends StatefulWidget {
  const _HeaderActionButton({
    required this.icon,
    this.badgeCount = 0,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final BrewIcon icon;
  final int badgeCount;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  State<_HeaderActionButton> createState() => _HeaderActionButtonState();
}

class _HeaderActionButtonState extends State<_HeaderActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: ExcludeSemantics(
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPressed();
            },
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              scale: _pressed ? 0.94 : (_hovered ? 1.05 : 1.0),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _pressed
                          ? const Color(0xF5182D20)
                          : (_hovered
                              ? BrewColor.cream.withValues(alpha: 0.12)
                              : const Color(0xEB132218)),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _hovered
                            ? BrewColor.cream.withValues(alpha: 0.3)
                            : BrewColor.cream.withValues(alpha: 0.14),
                      ),
                    ),
                    child: BrewIconMark(
                      icon: widget.icon,
                      dimension: 17,
                      color: BrewColor.cream,
                    ),
                  ),
                  if (widget.badgeCount > 0)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: BrewColor.alert,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF132218), width: 1.5),
                        ),
                        child: Text(
                          widget.badgeCount > 9 ? '9+' : '${widget.badgeCount}',
                          style: BrewType.mono.copyWith(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF102015),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileHeaderButton extends StatefulWidget {
  const _ProfileHeaderButton({
    required this.session,
    required this.onPressed,
  });

  final BrewSession session;
  final VoidCallback onPressed;

  @override
  State<_ProfileHeaderButton> createState() => _ProfileHeaderButtonState();
}

class _ProfileHeaderButtonState extends State<_ProfileHeaderButton> {
  bool _hovered = false;
  bool _pressed = false;

  String get _initial {
    final name = widget.session.name?.trim();
    if (name != null && name.isNotEmpty) {
      return String.fromCharCodes(name.runes.take(1)).toUpperCase();
    }
    final email = widget.session.email?.trim() ?? '';
    if (email.isNotEmpty) {
      return String.fromCharCodes(email.runes.take(1)).toUpperCase();
    }
    return 'Q';
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      label: 'Your profile',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onPressed();
          },
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.94 : (_hovered ? 1.05 : 1.0),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _pressed
                    ? const Color(0xF5182D20)
                    : (_hovered
                        ? BrewColor.sage.withValues(alpha: 0.3)
                        : const Color(0xEB132218)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _hovered
                      ? BrewColor.sageLight
                      : BrewColor.sageLight.withValues(alpha: 0.5),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: BrewColor.sage.withValues(alpha: 0.25),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                _initial,
                style: BrewType.mono.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: BrewColor.sageLight,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section's name, in the mono label voice.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12.5, color: BrewColor.sageLight),
              const SizedBox(width: 6),
            ],
            Text(
              label.toUpperCase(),
              style: BrewType.mono.copyWith(
                fontSize: 10,
                letterSpacing: 1.3,
                color: BrewColor.sageLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One partner, elevated as a frosted luxury control.
class _ShopCard extends StatefulWidget {
  const _ShopCard({required this.shop, this.onViewMenu});

  final BrewShop shop;
  final VoidCallback? onViewMenu;

  @override
  State<_ShopCard> createState() => _ShopCardState();
}

class _ShopCardState extends State<_ShopCard> {
  bool _pressed = false;
  bool _hovered = false;

  static const _markSize = 58.0;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final shop = widget.shop;
    final status = shop.status;

    return Semantics(
      button: true,
      label:
          '${shop.displayName}. ${shop.displayDescription}. '
          '${status.label}. View menu.',
      child: ExcludeSemantics(
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onViewMenu?.call();
            },
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              scale: _pressed ? 0.985 : (_hovered ? 1.012 : 1.0),
              child: AnimatedContainer(
                duration: reduced ? Duration.zero : BrewMotion.press,
                curve: BrewMotion.pressCurve,
                padding: const EdgeInsets.all(BrewSpace.grid * 2),
                decoration: BoxDecoration(
                  color: _pressed
                      ? const Color(0xF5182D20)
                      : (_hovered
                          ? const Color(0xF216271C)
                          : const Color(0xEB132218)),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _pressed
                        ? BrewColor.fieldFocus
                        : (_hovered
                            ? BrewColor.cream.withValues(alpha: 0.28)
                            : BrewColor.cream.withValues(alpha: 0.14)),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _hovered
                          ? const Color(0x60000000)
                          : const Color(0x40000000),
                      blurRadius: _hovered ? 22 : 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: BrewColor.cream.withValues(alpha: 0.14),
                              width: 1.0,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: BrewShopMark(shop: shop, dimension: _markSize),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shop.displayName,
                                style: BrewType.title.copyWith(
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w700,
                                  color: BrewColor.cream,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: BrewType.rowBodyTwoLineHeight,
                                child: Text(
                                  shop.displayDescription,
                                  style: BrewType.rowBody.copyWith(
                                    color: BrewColor.cream.withValues(alpha: 0.72),
                                    height: 1.35,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BrewSpace.grid * 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _StatusMark(status: status),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _ViewMenuPill(
                            hovered: _hovered,
                            pressed: _pressed,
                            reduced: reduced,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewMenuPill extends StatelessWidget {
  const _ViewMenuPill({
    required this.hovered,
    required this.pressed,
    required this.reduced,
  });

  final bool hovered;
  final bool pressed;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
      decoration: BoxDecoration(
        color: pressed
            ? BrewColor.cream.withValues(alpha: 0.22)
            : (hovered
                ? BrewColor.cream.withValues(alpha: 0.16)
                : BrewColor.cream.withValues(alpha: 0.09)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: hovered
              ? BrewColor.cream.withValues(alpha: 0.35)
              : BrewColor.cream.withValues(alpha: 0.16),
          width: 0.9,
        ),
        boxShadow: hovered
            ? [
                BoxShadow(
                  color: BrewColor.cream.withValues(alpha: 0.1),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Text(
        'View menu →',
        style: BrewType.mono.copyWith(
          fontSize: 10,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: BrewColor.cream,
        ),
      ),
    );
  }
}

/// Open, closed, or pending: illuminated capsule.
class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.status});

  final BrewShopStatus status;

  @override
  Widget build(BuildContext context) {
    final open = status == BrewShopStatus.open;
    final pending = status == BrewShopStatus.pending;

    final Color pillBg;
    final Color pillBorder;
    final Color dotColor;
    final Color textColor;

    if (open) {
      pillBg = BrewColor.sage.withValues(alpha: 0.2);
      pillBorder = BrewColor.sageLight.withValues(alpha: 0.4);
      dotColor = BrewColor.sageLight;
      textColor = BrewColor.sageLight;
    } else if (pending) {
      pillBg = BrewColor.cream.withValues(alpha: 0.08);
      pillBorder = BrewColor.cream.withValues(alpha: 0.15);
      dotColor = BrewColor.loading;
      textColor = BrewColor.loading;
    } else {
      pillBg = BrewColor.alert.withValues(alpha: 0.15);
      pillBorder = BrewColor.alert.withValues(alpha: 0.3);
      dotColor = BrewColor.alert;
      textColor = BrewColor.alert;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: pillBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5.5,
            height: 5.5,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: open
                  ? [
                      BoxShadow(
                        color: BrewColor.sageLight.withValues(alpha: 0.6),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 5.5),
          Text(
            status.label.toUpperCase(),
            style: BrewType.mono.copyWith(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// The order already being made. Outranks the shop cards, so it sits above them.
///
/// The one block on a signed-in panel that is not a choice — everything else on
/// this screen is something the reader might tap instead of something else, and
/// this is the thing already happening. That is what earns it the app's only
/// raised surface ([BrewColor.panel]) and the only filled button inside a card.
///
/// ## One control, several things that look like controls
///
/// The whole card takes the press, exactly as a shop card does. The Track order
/// button drawn at the bottom of it is a cream fill and a label and nothing
/// else: it darkens with the card under a thumb because it is part of the card,
/// not because it is separately pressable. A real button nested inside a
/// card-sized button is two hit targets for one destination, and the smaller one
/// wins the press that the reader aimed at the larger — which is the bug the
/// shop cards were built to avoid and this card has no more right to.
///
/// The stage track and the two fact columns are the same: readouts, drawn with
/// borders and discs because that is what makes them legible at a glance, not
/// because any of them does something.
class _OrderCard extends StatefulWidget {
  const _OrderCard({
    required this.order,
    required this.shop,
    required this.now,
    required this.onTrack,
  });

  final BrewOrder order;

  /// The board's record of the shop this order is with: its logo, and the name
  /// an admin may have changed since the order was placed.
  ///
  /// Null before the first snapshot lands and for an order naming a partner
  /// this build does not know. The card then falls back to [BrewOrder.shopName]
  /// and draws no mark at all — a bordered box with nothing in it would read as
  /// a logo that failed to load rather than as one nobody has asked for yet.
  final BrewShop? shop;

  /// See [HomeScreen.now]. Read once per build, because a card left on screen
  /// past midnight should stop saying the pickup is Today.
  final DateTime? now;

  /// Opens [OrderTrackingScreen] on this order. Passed in rather than built
  /// here because the push needs the session and the counter to keep the
  /// tracking screen live, and neither belongs on a card whose own job is
  /// just to draw what it was handed.
  final VoidCallback onTrack;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _pressed = false;

  /// Squares up with the shop's name and the order reference under it, the same
  /// way [_ShopCardState._markSize] squares up with its own two lines. Smaller
  /// than the shop card's 56 because this header carries a third thing — the
  /// stage pill — on the same row, and the reference has to stay on one line
  /// beside it.
  static const _markSize = 36.0;

  /// How many drinks get a row of their own before the card stops listing and
  /// starts counting.
  ///
  /// Three, because the card's job here is recognition — "yes, that is my
  /// order" — and not the receipt. A ten-drink order listed in full would push
  /// the two shop cards off the bottom of the screen, which is the one thing
  /// this screen's layout is not allowed to do. The full list is one tap away
  /// on the Orders tab, which is where the card already goes.
  static const _maxItems = 3;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final order = widget.order;
    final shop = widget.shop;
    final estimate = order.estimate;
    final scheduled = order.scheduledFor;
    final now = widget.now ?? DateTime.now();
    final name = shop?.displayName ?? order.shopName;

    final shown = order.items.take(_maxItems).toList();
    final hidden = order.items.length - shown.length;

    return BrewPressable(
      onPressed: widget.onTrack,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      pressed: _pressed,
      reduced: reduced,
      haptic: HapticFeedback.lightImpact,
      // One announcement for the whole block, and the only place the card says
      // everything: the full stage sentence rather than the pill's one word, and
      // every drink rather than the first three. A screen reader is not short of
      // room the way a 322px card is.
      semanticsLabel: [
        name,
        'Order ${order.reference}',
        order.stage.label,
        order.itemLine,
        switch (scheduled) {
          final at? =>
            'Pickup ${BrewOrder.formatDay(at, now)} at '
                '${BrewOrder.formatClock(at)}',
          null => 'Pickup as soon as it is ready',
        },
        if (estimate != null) 'Estimated time $estimate',
        'Track order.',
      ].join('. '),
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : BrewMotion.press,
          curve: BrewMotion.pressCurve,
          padding: const EdgeInsets.all(BrewSpace.grid * 2),
          decoration: BoxDecoration(
            color: _pressed ? const Color(0xF5182D20) : const Color(0xEB132218),
            border: Border.all(
              color: _pressed
                  ? BrewColor.fieldFocus
                  : BrewColor.cream.withValues(alpha: 0.16),
              width: 1.0,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 18,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (shop != null) ...[
                    BrewShopMark(shop: shop, dimension: _markSize),
                    const SizedBox(width: BrewSpace.grid * 1.5),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: BrewType.rowTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Mono, because this is a serial number the reader
                        // reads out at a counter rather than something the shop
                        // is saying to them.
                        //
                        // One line, always. A reference broken over two — which
                        // is what an unconstrained [Text] does at the hyphen —
                        // reads as two half-numbers, and this is the one string
                        // on the card that has to be said out loud correctly.
                        Text(
                          'ORDER #${order.reference}',
                          style: BrewType.mono,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: BrewSpace.grid),
                  // Flexible rather than fixed: at a large text scale the pill
                  // is allowed to take two lines and push the card taller, which
                  // is what every other block on this scrolling panel does.
                  Flexible(child: StagePill(stage: order.stage)),
                ],
              ),
              const SizedBox(height: BrewSpace.grid * 2),
              StageTrack(step: order.step, steps: BrewOrder.steps),
              const SizedBox(height: BrewSpace.grid * 2),
              const CardRule(),
              for (final (index, line) in shown.indexed) ...[
                if (index > 0) ...[
                  const SizedBox(height: BrewSpace.grid * 1.5),
                  // Dashed between drinks, solid around the block. One order
                  // that happens to have two lines in it, rather than two
                  // things that happen to be next to each other.
                  const CardRule(dashed: true),
                ],
                const SizedBox(height: BrewSpace.grid * 1.5),
                OrderItemRow(split: splitOrderLine(line)),
                const SizedBox(height: BrewSpace.grid * 1.5),
              ],
              if (hidden > 0) ...[
                Text(
                  hidden == 1 ? '+ 1 more item' : '+ $hidden more items',
                  style: BrewType.rowBody.copyWith(color: BrewColor.loading),
                ),
                const SizedBox(height: BrewSpace.grid * 1.5),
              ],
              const CardRule(),
              const SizedBox(height: BrewSpace.grid * 2),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Even, and the marks beside them are 30px rather than the
                    // item rows' 36 to pay for it: at a 390pt frame that is what
                    // fits "Today · 5:45 PM" and "Preparation time" each on one
                    // line. Weighting the columns to suit one of the two answers
                    // only moves which of them wraps.
                    Expanded(
                      child: OrderFact(
                        icon: BrewIcon.calendar,
                        label: 'Pickup',
                        // Never absent. An order with no `scheduledFor` is one
                        // the reader asked for now — see [BrewOrder
                        // .scheduledFor] — so the fact is "as soon as it is
                        // ready", which is a real answer, not a missing one.
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
              const SizedBox(height: BrewSpace.grid * 2),
              _TrackAffordance(pressed: _pressed, reduced: reduced),
            ],
          ),
        ),
      ),
    );
  }
}

/// What Track order looks like. Not a button — see the note on [_OrderCard].
///
/// It takes the card's own pressed state rather than holding one, which is the
/// whole point: a thumb anywhere on the block darkens this fill, so the reader
/// is told the press landed without the fill ever being a second thing to
/// aim at.
class _TrackAffordance extends StatelessWidget {
  const _TrackAffordance({required this.pressed, required this.reduced});

  final bool pressed;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: reduced ? Duration.zero : BrewMotion.press,
      curve: BrewMotion.pressCurve,
      height: BrewSpace.grid * 6,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: BrewSpace.grid * 2),
      decoration: BoxDecoration(
        color: pressed ? BrewColor.pressed(BrewColor.cream) : BrewColor.cream,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'Track order',
            style: BrewType.buttonLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: const Color(0xFF13251A),
            ),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 15,
              color: Color(0xFF13251A),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the bell opens: every order that has moved somewhere the reader has
/// not necessarily seen — ready, completed, or declined — newest first.
///
/// Derived from the same [BrewOrder] stream the Orders tab reads rather than
/// a notifications collection of its own: there is nothing on this build that
/// writes one, and an order's stage already says everything a notice here
/// would say. Nothing is marked read. A reader who opens this panel has seen
/// everything on it by definition, and the alternative — a per-notice read
/// flag stored somewhere — is state this app would have to invent a place to
/// keep, for a distinction ("seen" vs "not seen, but already looked at once")
/// that a coffee counter has no real use for.
class _NoticesPanel extends StatelessWidget {
  const _NoticesPanel({
    required this.compact,
    required this.orders,
    required this.onSeen,
    required this.onClose,
  });

  final bool compact;

  /// Null on a build with no Firestore behind it — reads as "nothing known
  /// yet", the same as every other stream this screen holds.
  final Stream<List<BrewOrder>>? orders;

  /// Fired with whatever this panel is showing, whenever that changes — a
  /// notice on an open panel has been seen by definition. What the bell's
  /// badge counts against; see `_HomeScreenState._markNoticesSeen`.
  final void Function(List<BrewOrder> notices) onSeen;

  final VoidCallback onClose;

  /// [ready], [completed], and [BrewOrderStage.rejected] are the three
  /// moments a reader needs telling about even if they were not looking:
  /// their drink is waiting, their order is done, or the shop is not making
  /// it. [BrewOrderStage.isActive] is the wrong test here — it excludes only
  /// [completed] and [rejected], so an order that just became [ready] would
  /// still read as "active" and never appear as a notice, even though it is
  /// the single most useful moment to be told about.
  static bool _isNotice(BrewOrderStage stage) => switch (stage) {
    BrewOrderStage.ready ||
    BrewOrderStage.completed ||
    BrewOrderStage.rejected => true,
    BrewOrderStage.received || BrewOrderStage.preparing => false,
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BrewOrder>>(
      stream: orders,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        final notices = [
          for (final order in loaded ?? const <BrewOrder>[])
            if (_isNotice(order.stage)) order,
        ];
        // After the frame, not during it: onSeen reaches setState on the
        // screen this panel sits in, and a setState inside a builder is a
        // build scheduled from a build.
        if (notices.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onSeen(notices);
          });
        }
        return _sheet(
          loaded: loaded != null,
          // A refused or failed read, and a panel opened on a build with no
          // Firestore behind it at all. Both used to be indistinguishable from
          // a read still in flight, which is what left this panel showing
          // "Looking up your orders…" with nothing ever arriving.
          failed: snapshot.hasError || orders == null,
          notices: notices,
        );
      },
    );
  }

  Widget _sheet({
    required bool loaded,
    required bool failed,
    required List<BrewOrder> notices,
  }) {
    var next = 0;
    int slot() => next++;

    final header = slot();
    final headline = slot();
    // The failed line takes a stagger slot of its own, so it fades in with the
    // rest of the sheet rather than appearing flat under an animated headline.
    final bodySlot = (failed && !loaded) || (loaded && notices.isEmpty)
        ? slot()
        : null;
    final noticeSlots = [for (final _ in notices) slot()];

    return BrewSheet(
      staggerCount: next,
      children: [
        StaggerItem(
          index: header,
          child: Row(
            children: [
              const BrewWordmarkRow(),
              const Spacer(),
              BrewMonoButton(
                label: 'Close',
                semanticsLabel: 'Close notifications',
                onPressed: onClose,
              ),
            ],
          ),
        ),
        SizedBox(height: brewBlockGap(compact)),
        StaggerItem(
          index: headline,
          child: Text(
            'Notifications.',
            style: BrewType.displayAt(compact ? 28 : 34),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 2),
        if (failed && !loaded)
          StaggerItem(
            index: bodySlot!,
            child: Text(
              'Could not load your orders. Check your connection and try '
              'again.',
              style: BrewType.rowBody,
            ),
          )
        else if (!loaded)
          Text('Looking up your orders…', style: BrewType.rowBody)
        else if (bodySlot != null)
          StaggerItem(
            index: bodySlot,
            child: Text(
              'Nothing yet. When an order is ready, this is where it will '
              'say so.',
              style: BrewType.rowBody,
            ),
          )
        else
          for (final (index, order) in notices.indexed)
            StaggerItem(
              index: noticeSlots[index],
              child: _NoticeRow(order: order, isLast: index == notices.length - 1),
            ),
      ],
    );
  }
}

/// One notice: what happened to an order, in the past tense a notification
/// speaks in rather than [BrewOrderStage.label]'s present-tense "Ready for
/// pickup" — the same order the tracking card already says while it is still
/// live. This is the after: the reader was not necessarily looking when it
/// happened, so the line says so happened rather than so is.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.order, required this.isLast});

  final BrewOrder order;
  final bool isLast;

  /// The declined reason if there is one, folded onto the same line a
  /// rejection notice reads — the admin queue's own [BrewOrder.rejectionReason]
  /// doc comment describes where this comes from.
  String get _headline => switch (order.stage) {
    BrewOrderStage.ready => 'Your order from ${order.shopName} is ready.',
    BrewOrderStage.completed => 'Your order from ${order.shopName} is done.',
    BrewOrderStage.rejected => switch (order.rejectionReason) {
      final reason? => '${order.shopName} declined your order: $reason',
      null => '${order.shopName} declined your order.',
    },
    // Neither reachable here — `notices` only ever holds inactive orders —
    // but `BrewOrderStage` has five values and a switch over it is exhaustive
    // by the analyser's own rule, not by this class's.
    BrewOrderStage.received || BrewOrderStage.preparing => order.stage.label,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: BrewColor.hairline),
          bottom:
              isLast ? BorderSide(color: BrewColor.hairline) : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: BrewSpace.rowPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _headline,
            style: order.stage == BrewOrderStage.rejected
                ? BrewType.rowBody.copyWith(color: BrewColor.alert)
                : BrewType.rowBody,
          ),
          const SizedBox(height: 4),
          Text(order.itemLine, style: BrewType.rowBody.copyWith(color: BrewColor.loading)),
        ],
      ),
    );
  }
}

/// Home, Orders, Profile. Three, and no icons.
///
/// Labels only, because there is no icon set here that could carry them: the app
/// draws one cup and ships three supplied glyphs, and a bottom bar of borrowed
/// Material pictograms under a hand-drawn cup is the tell this design system
/// exists to avoid. The active tab is named in cream over a 2px cream segment —
/// the ledger's rule doing the job a filled pill would do elsewhere, so position
/// and weight both say where the reader is and colour is not carrying it alone.
class _BrewNav extends StatelessWidget {
  const _BrewNav({
    required this.current,
    required this.onSelect,
    required this.bottomInset,
  });

  /// Null while the notices panel is over a tab: nothing is highlighted, because
  /// the reader is not in any of the three.
  final BrewTab? current;

  final ValueChanged<BrewTab> onSelect;
  final double bottomInset;

  static const _height = 56.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: BrewColor.hairline)),
      ),
      padding: EdgeInsets.only(
        bottom: math.max(bottomInset, BrewSpace.grid),
      ),
      child: Row(
        children: [
          for (final tab in BrewTab.values)
            Expanded(
              child: _NavItem(
                tab: tab,
                selected: tab == current,
                height: _height,
                onPressed: () => onSelect(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.height,
    required this.onPressed,
  });

  final BrewTab tab;
  final bool selected;
  final double height;
  final VoidCallback onPressed;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final ink = widget.selected || _pressed
        ? BrewColor.cream
        : BrewColor.sageLight;

    return BrewPressable(
      onPressed: widget.onPressed,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      // No 1px drop on a tab: the whole bar would appear to flex under a thumb.
      pressed: false,
      reduced: reduced,
      semanticsLabel: widget.selected
          ? '${widget.tab.label}, current tab'
          : widget.tab.label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.height,
          child: Column(
            children: [
              // The indicator sits on the bar's own top rule, so the selected tab
              // reads as the segment of it that has been inked in.
              //
              // Inked on the same 90ms ramp as the label above it, because the
              // two are one control saying one thing. The rule used to appear
              // between frames while the label eased — so a tab change read as a
              // hard cut with a fade attached to it, which is the tell of two
              // states drawn by two different hands. It fades in place rather
              // than sliding across the bar: the order card's own progress
              // mark (`StageTrack` in widgets/order_track.dart) deliberately
              // does not slide either, and for the same reason — the reader
              // jumped to this tab, they did not travel to it.
              AnimatedContainer(
                duration: reduced ? Duration.zero : BrewMotion.press,
                curve: BrewMotion.pressCurve,
                height: 2,
                // Transparent rather than null: a null colour is nothing to
                // tween from, and the segment would snap back on deselection
                // however long the ramp says.
                color: widget.selected
                    ? BrewColor.cream
                    : const Color(0x00000000),
              ),
              Expanded(
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: reduced ? Duration.zero : BrewMotion.press,
                    curve: BrewMotion.pressCurve,
                    style: BrewType.mono.copyWith(color: ink),
                    child: Text(widget.tab.label.toUpperCase()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
