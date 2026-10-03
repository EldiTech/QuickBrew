import 'package:flutter/material.dart'
    show BoxShadow, Icon, Icons, Material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../brew_admin.dart';
import '../../brew_counter.dart';
import '../../theme/brew_type.dart';
import '../../theme/tokens.dart';
import '../../widgets/brew_background.dart';
import '../../widgets/brew_buttons.dart';
import '../../widgets/brew_sheet.dart';
import '../../widgets/shop_mark.dart';
import '../../widgets/stagger.dart';
import 'invite_admin_screen.dart';
import 'store_config_screen.dart';
import 'users_screen.dart';

/// Where an admin or a super admin lands instead of [HomeScreen](../home_screen.dart).
///
/// One screen, shaped by [profile.role]: an admin sees the one store an invite
/// assigned it and nothing else; a super admin sees both stores and the two
/// things only a super admin can do — see every account, and hand a new one
/// admin credentials for a store. There is no shared "dashboard" chrome around
/// role-specific widgets, because there is nothing here two roles both partly
/// see — an admin's screen is a strict subset of a super admin's, so the subset
/// is what gets built rather than the whole thing with parts hidden.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({
    super.key,
    required this.profile,
    this.admin,
    this.counter,
    this.onSignOut,
  });

  /// Who is signed in and what they may configure. This screen exists because
  /// [BrewRole.canConfigureStores] is true for it.
  final BrewUserProfile profile;

  /// The write side — null if Firestore is unreachable, in which case the
  /// store cards still render but nothing on them can be saved.
  final BrewAdmin? admin;

  /// Read side, shared with the customer home screen: a store's open/closed
  /// mark is a fact an admin wants to see here for the same reason a customer
  /// wants to see it there.
  final BrewCounter? counter;

  final VoidCallback? onSignOut;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  Stream<List<BrewShop>>? _shops;

  /// One unattended-orders stream per store this role configures, opened
  /// once in [initState] for the same reason [_shops] is: a fresh listener
  /// on every rebuild would ask Firestore for the same query on every frame.
  /// Keyed by partner rather than held as a list, since [_StoreCard] below
  /// needs to look one up by the store it is drawing.
  final Map<BrewPartner, Stream<List<BrewOrder>>> _orders = {};

  /// The most recent snapshot, so a screen pushed from here can name a store
  /// by what it is currently called. Null until the first one lands, at which
  /// point [BrewShop.nameOf] falls back to the built-in copy — the same answer
  /// the card itself shows at that moment.
  List<BrewShop>? _latestShops;

  @override
  void initState() {
    super.initState();
    _shops = widget.counter?.shops();
    // Seeded from the last snapshot anything took, so the cards below — and the
    // Team screens that borrow this list to name a store — open on the real
    // names rather than on the enum's built-in pair. See [BrewCounter.lastShops].
    _latestShops = widget.counter?.lastShops;
    // Creates the shop documents the first time an admin ever opens this, so
    // "Hours unavailable" is a state the admin can move off rather than the
    // permanent look of an empty collection. A no-op once they exist, and
    // scoped to the stores this role may write — see [BrewAdmin.ensureShops].
    widget.admin?.ensureShops(only: _stores);

    final admin = widget.admin;
    if (admin != null) {
      for (final partner in _stores) {
        _orders[partner] = admin.ordersFor(partner);
      }
    }
  }

  bool get _superadmin => widget.profile.role == BrewRole.superadmin;

  /// Both stores for a super admin; the one store an invite named for an
  /// admin, or none at all if a super admin created the account by hand
  /// without assigning one yet.
  List<BrewPartner> get _stores {
    if (_superadmin) return BrewPartner.values;
    final store = widget.profile.assignedStore;
    return store == null ? const [] : [store];
  }

  String get _subtitle {
    if (_superadmin) {
      return 'Configure both coffee shops, and invite the admins who run them.';
    }
    // Deliberately does not name the store. It used to print
    // `store.name` — the enum's built-in copy — which went stale the moment an
    // admin renamed their shop, and it was saying the name twice anyway: the
    // card directly below this carries the live one.
    return widget.profile.assignedStore == null
        ? 'No store is assigned to this account yet. Ask your super admin.'
        : 'Hours, profile and the board.';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.height <= BrewSpace.compactHeight;

    // Every stagger index is worked out here, up front, from the two things
    // that decide the shape of this screen — how many stores this role
    // configures, and whether it is the role that also manages people. Both
    // are known synchronously from the profile, before any Firestore snapshot
    // arrives.
    final stores = _stores;
    const storeBase = 4; // masthead, display line, subtitle, stores eyebrow
    final teamBase = storeBase + stores.length;
    final staggerCount = teamBase + (_superadmin ? 3 : 0);

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
          child: BrewSheet(
            staggerCount: staggerCount,
            children: [
              StaggerItem(
                index: 0,
                child: _Masthead(
                  onSignOut: widget.onSignOut,
                  isSuperadmin: _superadmin,
                ),
              ),
              SizedBox(height: brewBlockGap(compact)),
              StaggerItem(
                index: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: BrewColor.cream.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: BrewColor.cream.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Text(
                            'ADMIN CONSOLE',
                            style: BrewType.mono.copyWith(
                              fontSize: 9.5,
                              letterSpacing: 1.5,
                              color: BrewColor.sageLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BrewSpace.grid),
                    Text(
                      'Admin dashboard.',
                      style: BrewType.displayAt(compact ? 28 : 34),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BrewSpace.grid * 0.75),
              StaggerItem(
                index: 2,
                child: Text(
                  _subtitle,
                  style: BrewType.rowBody.copyWith(
                    color: BrewColor.cream.withValues(alpha: 0.76),
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: brewBlockGap(compact)),
              StaggerItem(
                index: 3,
                child: _SectionLabel(
                  _superadmin ? 'Your stores' : 'Your store',
                  icon: Icons.storefront_rounded,
                ),
              ),
              const SizedBox(height: BrewSpace.grid * 1.5),
              if (stores.isEmpty)
                Text('Nothing assigned.', style: BrewType.rowBody)
              else
                // Only the open/closed mark comes from the stream; which cards
                // there are and where they sit does not, which is why the
                // indices are handed in from above rather than worked out here.
                StreamBuilder<List<BrewShop>>(
                  stream: _shops,
                  initialData: _latestShops,
                  builder: (context, snapshot) {
                    final live = snapshot.data;
                    // Kept so the Team screens can label a store with its live
                    // name. Assigned rather than setState-ed: this is already a
                    // rebuild caused by the snapshot, and calling setState here
                    // would schedule a second one for a value nothing on this
                    // screen renders.
                    _latestShops = live ?? _latestShops;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (position, partner) in stores.indexed) ...[
                          if (position > 0)
                            const SizedBox(height: BrewSpace.grid * 1.5),
                          StaggerItem(
                            index: storeBase + position,
                            child: _StoreCard(
                              shop: live
                                      ?.where((shop) => shop.partner == partner)
                                      .firstOrNull ??
                                  BrewShop(
                                    partner: partner,
                                    status: BrewShopStatus.pending,
                                  ),
                              orders: _orders[partner],
                              onTap: () => _openStore(context, partner),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              if (_superadmin) ...[
                SizedBox(height: brewBlockGap(compact)),
                StaggerItem(
                  index: teamBase,
                  child: const _SectionLabel(
                    'Team & Access',
                    icon: Icons.group_rounded,
                  ),
                ),
                const SizedBox(height: BrewSpace.grid * 1.5),
                StaggerItem(
                  index: teamBase + 1,
                  child: _ActionRow(
                    icon: Icons.people_alt_rounded,
                    label: 'See all users',
                    detail: 'Who runs each shop, and every account behind them.',
                    onTap: () => _openUsers(context),
                  ),
                ),
                const SizedBox(height: BrewSpace.grid * 1.5),
                StaggerItem(
                  index: teamBase + 2,
                  child: _ActionRow(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Create an admin',
                    detail: 'Make an account that manages one of the two stores.',
                    onTap: () => _openInvite(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openStore(BuildContext context, BrewPartner partner) {
    Navigator.of(context).push(
      StoreConfigScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        partner: partner,
        admin: widget.admin,
        counter: widget.counter,
      ),
    );
  }

  void _openUsers(BuildContext context) {
    Navigator.of(context).push(
      UsersScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        admin: widget.admin,
        shops: _latestShops,
        // So the roster can tell which row is the reader's own and withhold the
        // two controls that would lock them out of their own role.
        currentUid: widget.profile.uid,
      ),
    );
  }

  void _openInvite(BuildContext context) {
    Navigator.of(context).push(
      InviteAdminScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        admin: widget.admin,
        shops: _latestShops,
      ),
    );
  }
}

/// The wordmark, role badge, and session controls.
class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.onSignOut,
    this.isSuperadmin = false,
  });

  final VoidCallback? onSignOut;
  final bool isSuperadmin;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Flexible(
          child: BrewWordmarkRow(),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSuperadmin) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: BrewColor.sage.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: BrewColor.sage.withValues(alpha: 0.5),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_rounded,
                      size: 12,
                      color: BrewColor.sageLight,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'SUPERADMIN',
                      style: BrewType.mono.copyWith(
                        fontSize: 8.5,
                        letterSpacing: 0.8,
                        color: BrewColor.sageLight,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
            BrewPressable(
              onPressed: onSignOut,
              radius: 999,
              onPressedChanged: (_) {},
              reduced: MediaQuery.disableAnimationsOf(context),
              pressed: false,
              semanticsLabel: 'Log out',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x6608140C),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: BrewColor.cream.withValues(alpha: 0.16),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      size: 12,
                      color: BrewColor.cream,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'LOG OUT',
                      style: BrewType.mono.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        color: BrewColor.cream,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A section's name, in the mono label voice with an icon.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: BrewColor.sageLight),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: BrewType.mono.copyWith(
              fontSize: 11,
              letterSpacing: 1.4,
              color: BrewColor.sageLight,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}


/// One store, as an elevated luxury frosted card with live status and unattended count.
class _StoreCard extends StatefulWidget {
  const _StoreCard({required this.shop, this.orders, this.onTap});

  final BrewShop shop;

  /// This store's orders, for the unattended-count badge — null when there is
  /// no admin layer to read from, which draws no badge rather than a stuck
  /// zero.
  final Stream<List<BrewOrder>>? orders;

  final VoidCallback? onTap;

  @override
  State<_StoreCard> createState() => _StoreCardState();
}

class _StoreCardState extends State<_StoreCard> {
  bool _pressed = false;
  bool _cardHovered = false;
  bool _configureHovered = false;
  bool _isNavigating = false;

  static const _markSize = 48.0;

  Future<void> _handleTap() async {
    if (_isNavigating || widget.onTap == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pressed = true;
      _isNavigating = true;
    });

    // 110ms gives the tactile compression and glowing sage response time to
    // visibly finish before the page transition glides in.
    await Future<void>.delayed(const Duration(milliseconds: 110));

    if (!mounted) return;
    widget.onTap!();

    if (mounted) {
      setState(() {
        _pressed = false;
        _isNavigating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final shop = widget.shop;
    final open = shop.status == BrewShopStatus.open;

    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: '${shop.displayName}. ${shop.status.label}. Configure.',
      child: MouseRegion(
        onEnter: (_) => setState(() => _cardHovered = true),
        onExit: (_) => setState(() => _cardHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            if (!_isNavigating) setState(() => _pressed = false);
          },
          onTapCancel: () {
            if (!_isNavigating) setState(() => _pressed = false);
          },
          child: AnimatedScale(
            duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.985 : (_cardHovered ? 1.006 : 1.0),
            child: AnimatedContainer(
              duration: reduced ? Duration.zero : BrewMotion.press,
              curve: BrewMotion.pressCurve,
              padding: const EdgeInsets.all(BrewSpace.grid * 2),
              decoration: BoxDecoration(
                color: _pressed
                    ? const Color(0xF5182D20)
                    : (_cardHovered
                        ? const Color(0xF216271C)
                        : const Color(0xEB132218)),
                border: Border.all(
                  color: _pressed
                      ? BrewColor.fieldFocus
                      : (_cardHovered
                          ? BrewColor.cream.withValues(alpha: 0.22)
                          : BrewColor.cream.withValues(alpha: 0.12)),
                  width: 1.0,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _cardHovered
                        ? const Color(0x55000000)
                        : const Color(0x40000000),
                    blurRadius: _cardHovered ? 20 : 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: BrewColor.cream.withValues(alpha: 0.12),
                        width: 1.0,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: BrewShopMark(shop: shop, dimension: _markSize),
                    ),
                  ),
                  const SizedBox(width: BrewSpace.grid * 1.5),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.displayName,
                          style: BrewType.rowTitle.copyWith(
                            fontWeight: FontWeight.w600,
                            color: BrewColor.cream,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: open
                                ? BrewColor.sage.withValues(alpha: 0.18)
                                : BrewColor.alert.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: open
                                  ? BrewColor.sage.withValues(alpha: 0.4)
                                  : BrewColor.alert.withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: open ? BrewColor.sageLight : BrewColor.alert,
                                  boxShadow: open
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x66B7D5B0),
                                            blurRadius: 4,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  shop.status.label.toUpperCase(),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: BrewType.mono.copyWith(
                                    fontSize: 9.5,
                                    letterSpacing: 1.0,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        open ? BrewColor.sageLight : BrewColor.alert,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: BrewSpace.grid),
                  StreamBuilder<List<BrewOrder>>(
                    stream: widget.orders,
                    builder: (context, snapshot) {
                      final unattended = (snapshot.data ?? const <BrewOrder>[])
                          .where((order) => order.stage == BrewOrderStage.received)
                          .length;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unattended > 0) ...[
                            _UnattendedBadge(count: unattended),
                            const SizedBox(width: 8),
                          ],
                          MouseRegion(
                            onEnter: (_) => setState(() => _configureHovered = true),
                            onExit: (_) => setState(() => _configureHovered = false),
                            cursor: SystemMouseCursors.click,
                            child: AnimatedScale(
                              duration: reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 140),
                              curve: Curves.easeOutCubic,
                              scale: _pressed
                                  ? 0.94
                                  : (_configureHovered ? 1.05 : 1.0),
                              child: AnimatedContainer(
                                duration: reduced
                                    ? Duration.zero
                                    : const Duration(milliseconds: 140),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _pressed
                                      ? BrewColor.sage.withValues(alpha: 0.40)
                                      : (_configureHovered
                                          ? BrewColor.sage.withValues(alpha: 0.28)
                                          : BrewColor.sage.withValues(alpha: 0.12)),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _pressed
                                        ? BrewColor.sageLight
                                        : (_configureHovered
                                            ? BrewColor.sageLight
                                            : BrewColor.sage.withValues(alpha: 0.35)),
                                    width: 1.0,
                                  ),
                                  boxShadow: (_pressed || _configureHovered)
                                      ? [
                                          BoxShadow(
                                            color: BrewColor.sage.withValues(
                                              alpha: _pressed ? 0.45 : 0.25,
                                            ),
                                            blurRadius: _pressed ? 12 : 8,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Configure',
                                      style: BrewType.mono.copyWith(
                                        fontSize: 11,
                                        letterSpacing: 0.8,
                                        fontWeight: FontWeight.w600,
                                        color: BrewColor.cream,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    AnimatedSlide(
                                      duration: reduced
                                          ? Duration.zero
                                          : const Duration(milliseconds: 140),
                                      curve: Curves.easeOutCubic,
                                      offset: Offset(
                                        (_pressed || _configureHovered) ? 0.30 : 0.0,
                                        0.0,
                                      ),
                                      child: const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 13,
                                        color: BrewColor.sageLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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

/// A count badge for unattended orders with glowing status.
class _UnattendedBadge extends StatelessWidget {
  const _UnattendedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BrewColor.sage,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55B7D5B0),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: BrewType.mono.copyWith(
              color: const Color(0xFF0D1B12),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            'WAITING',
            style: BrewType.mono.copyWith(
              color: const Color(0xFF0D1B12),
              fontSize: 8.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// A super admin's team navigation card with icon tile, typography, and chevron indicator.
class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.detail,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onTap;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _pressed = false;
  bool _hovered = false;
  bool _isNavigating = false;

  Future<void> _handleTap() async {
    if (_isNavigating || widget.onTap == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pressed = true;
      _isNavigating = true;
    });

    // 110ms tactile response before navigation begins
    await Future<void>.delayed(const Duration(milliseconds: 110));

    if (!mounted) return;
    widget.onTap!();

    if (mounted) {
      setState(() {
        _pressed = false;
        _isNavigating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: '${widget.label}. ${widget.detail}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            if (!_isNavigating) setState(() => _pressed = false);
          },
          onTapCancel: () {
            if (!_isNavigating) setState(() => _pressed = false);
          },
          child: AnimatedScale(
            duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.985 : (_hovered ? 1.006 : 1.0),
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
                border: Border.all(
                  color: _pressed
                      ? BrewColor.fieldFocus
                      : (_hovered
                          ? BrewColor.cream.withValues(alpha: 0.22)
                          : BrewColor.cream.withValues(alpha: 0.12)),
                  width: 1.0,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _hovered
                        ? const Color(0x55000000)
                        : const Color(0x40000000),
                    blurRadius: _hovered ? 20 : 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: BrewColor.sage.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: BrewColor.sage.withValues(alpha: 0.3),
                        width: 1.0,
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 20,
                      color: BrewColor.sageLight,
                    ),
                  ),
                  const SizedBox(width: BrewSpace.grid * 1.5),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: BrewType.rowTitle.copyWith(
                            fontWeight: FontWeight.w600,
                            color: BrewColor.cream,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.detail,
                          style: BrewType.rowBody.copyWith(
                            color: BrewColor.cream.withValues(alpha: 0.65),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: BrewSpace.grid),
                  AnimatedContainer(
                    duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_pressed || _hovered)
                          ? BrewColor.sage.withValues(alpha: 0.28)
                          : BrewColor.sage.withValues(alpha: 0.1),
                      border: Border.all(
                        color: (_pressed || _hovered)
                            ? BrewColor.sageLight
                            : BrewColor.sage.withValues(alpha: 0.25),
                        width: 1.0,
                      ),
                      boxShadow: (_pressed || _hovered)
                          ? const [
                              BoxShadow(
                                color: Color(0x44B7D5B0),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: AnimatedSlide(
                      duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      offset: Offset((_pressed || _hovered) ? 0.25 : 0.0, 0.0),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: BrewColor.sageLight,
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
