import 'package:flutter/material.dart' show Icons, Icon;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_sheet.dart';
import '../widgets/stagger.dart';

/// The account, and the way out of it.
///
/// Elevated with the Frosted Glass Luxury Forest aesthetic, featuring an illuminated
/// monogram avatar, verified credentials card with quick-copy actions, roaster
/// network synchronization indicators, and a tactile luxury logout action.
class ProfilePanel extends StatelessWidget {
  const ProfilePanel({
    super.key,
    required this.compact,
    required this.session,
    this.shops,
    this.knownShops,
    this.onSignOut,
  });

  /// Short frame: display typography adjusts gracefully.
  final bool compact;

  final BrewSession session;

  /// Live shops stream from Firestore.
  final Stream<List<BrewShop>>? shops;

  /// Initial or fallback shops.
  final List<BrewShop>? knownShops;

  /// Log out callback.
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BrewShop>>(
      stream: shops,
      initialData: knownShops,
      builder: (context, snapshot) {
        final currentShops = snapshot.data ??
            (shops == null ? BrewShop.unavailable : BrewShop.pending);
        return _sheet(context, currentShops);
      },
    );
  }

  Widget _sheet(BuildContext context, List<BrewShop> currentShops) {
    return BrewSheet(
      staggerCount: 6,
      children: [
        const StaggerItem(index: 0, child: BrewWordmarkRow()),
        SizedBox(height: brewBlockGap(compact)),
        StaggerItem(
          index: 1,
          child: _MastheadTag(compact: compact),
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        StaggerItem(
          index: 2,
          child: _AccountHeader(compact: compact, session: session),
        ),
        const SizedBox(height: BrewSpace.grid * 3.5),
        StaggerItem(
          index: 3,
          child: _AccountDetailsCard(session: session),
        ),
        const SizedBox(height: BrewSpace.grid * 2),
        StaggerItem(
          index: 4,
          child: _DualShopsAccessCard(shops: currentShops),
        ),
        const SizedBox(height: BrewSpace.grid * 3.5),
        StaggerItem(
          index: 5,
          child: Column(
            children: [
              _LuxuryLogOutButton(onSignOut: onSignOut),
              const SizedBox(height: BrewSpace.grid * 2),
              const _SessionSecurityFooter(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Upper contextual pill tag matching the Orders and Admin panels.
class _MastheadTag extends StatelessWidget {
  const _MastheadTag({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
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
                Icons.verified_user_rounded,
                size: 12,
                color: BrewColor.sageLight,
              ),
              const SizedBox(width: 5),
              Text(
                'AUTHENTICATED PROFILE',
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
                'ACTIVE',
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
      ],
    );
  }
}

/// The luxury avatar mark and headline in unified balance.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.compact, required this.session});

  final bool compact;
  final BrewSession session;

  @override
  Widget build(BuildContext context) {
    final avatarDimension = compact ? 56.0 : 64.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _LuxuryAvatar(
          name: session.name,
          email: session.email,
          dimension: avatarDimension,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your account.',
                style: BrewType.displayAt(compact ? 26 : 32),
              ),
              const SizedBox(height: 4),
              Text(
                'One account, both coffee shops.',
                style: BrewType.rowBody.copyWith(
                  color: BrewColor.cream.withValues(alpha: 0.74),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Elevated frosted monogram avatar with halo glow and verification indicator.
class _LuxuryAvatar extends StatelessWidget {
  const _LuxuryAvatar({
    this.name,
    this.email,
    required this.dimension,
  });

  final String? name;
  final String? email;
  final double dimension;

  static String _lead(String value, int count) =>
      String.fromCharCodes(value.runes.take(count)).toUpperCase();

  String get _initials {
    final named = name?.trim();
    if (named != null && named.isNotEmpty) {
      final parts = named.split(RegExp(r'\s+'));
      final first = _lead(parts.first, 1);
      final last = parts.length > 1 ? _lead(parts.last, 1) : '';
      return first + last;
    }

    final local = email?.trim().split('@').first ?? '';
    if (local.isNotEmpty) {
      return _lead(local, 1);
    }
    return 'Q';
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials;

    return SizedBox(
      width: dimension + 6,
      height: dimension + 6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Frosted circular avatar disc
          Container(
            width: dimension,
            height: dimension,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E3524),
                  Color(0xFF102115),
                ],
              ),
              border: Border.all(
                color: BrewColor.sageLight.withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: BrewColor.sage.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
                const BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              initials,
              textScaler: TextScaler.noScaling,
              maxLines: 1,
              style: BrewType.displayAt(dimension * 0.38).copyWith(
                color: BrewColor.sageLight,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Verified checkmark badge anchored bottom-right
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xFF102216),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  color: BrewColor.sage,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: BrewColor.sage.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 10,
                  color: BrewColor.cream,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Primary frosted card containing credentials and quick copy tools.
class _AccountDetailsCard extends StatelessWidget {
  const _AccountDetailsCard({required this.session});

  final BrewSession session;

  @override
  Widget build(BuildContext context) {
    final hasName = session.name != null && session.name!.trim().isNotEmpty;
    final nameValue = hasName ? session.name!.trim() : 'Not set';

    final hasEmail = session.email != null && session.email!.trim().isNotEmpty;
    final emailValue = hasEmail ? session.email!.trim() : 'Not set';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.14),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(BrewSpace.grid * 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.badge_outlined,
                    size: 14,
                    color: BrewColor.sageLight,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ACCOUNT CREDENTIALS',
                    style: BrewType.mono.copyWith(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: BrewColor.sageLight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: BrewColor.sage.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: BrewColor.sageLight.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                      'VERIFIED',
                      style: BrewType.mono.copyWith(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: BrewColor.sageLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 2.5),
          // Name Field
          _AccountFieldTile(
            icon: Icons.person_rounded,
            label: 'NAME',
            value: nameValue,
            isPlaceholder: !hasName,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: BrewSpace.grid * 1.5),
            child: Container(
              height: 1,
              width: double.infinity,
              color: BrewColor.cream.withValues(alpha: 0.1),
            ),
          ),
          // Email Field with Copy Micro-Action
          _AccountFieldTile(
            icon: Icons.alternate_email_rounded,
            label: 'EMAIL',
            value: emailValue,
            isPlaceholder: !hasEmail,
            copyable: hasEmail,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: BrewSpace.grid * 1.5),
            child: Container(
              height: 1,
              width: double.infinity,
              color: BrewColor.cream.withValues(alpha: 0.1),
            ),
          ),
          // Membership Access Row
          _AccountFieldTile(
            icon: Icons.local_cafe_rounded,
            label: 'MEMBERSHIP TIER',
            value: 'Unified Roaster Pass',
            subtitle: 'Direct queueing & counter tracking at both stores',
            isPlaceholder: false,
          ),
        ],
      ),
    );
  }
}

/// A structured field row with an icon capsule, label, and copy tool.
class _AccountFieldTile extends StatefulWidget {
  const _AccountFieldTile({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.isPlaceholder,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final bool isPlaceholder;
  final bool copyable;

  @override
  State<_AccountFieldTile> createState() => _AccountFieldTileState();
}

class _AccountFieldTileState extends State<_AccountFieldTile> {
  bool _copied = false;
  bool _copyHovered = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.value));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Leading Icon Capsule
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BrewColor.cream.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: BrewColor.cream.withValues(alpha: 0.12),
              width: 1.0,
            ),
          ),
          child: Icon(
            widget.icon,
            size: 18,
            color: BrewColor.sageLight,
          ),
        ),
        const SizedBox(width: 14),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: BrewType.mono.copyWith(
                  fontSize: 9.5,
                  letterSpacing: 1.1,
                  color: BrewColor.sageLight.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.value,
                style: widget.isPlaceholder
                    ? BrewType.fieldInk.copyWith(
                        color: BrewColor.cream.withValues(alpha: 0.4),
                        fontStyle: FontStyle.italic,
                      )
                    : BrewType.fieldInk.copyWith(
                        color: BrewColor.cream,
                        fontWeight: FontWeight.w600,
                      ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: BrewType.mono.copyWith(
                    fontSize: 9.5,
                    color: BrewColor.cream.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Trailing Copy Button
        if (widget.copyable) ...[
          const SizedBox(width: 8),
          MouseRegion(
            onEnter: (_) => setState(() => _copyHovered = true),
            onExit: (_) => setState(() => _copyHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _copy,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _copied
                      ? BrewColor.sage.withValues(alpha: 0.3)
                      : (_copyHovered
                          ? BrewColor.cream.withValues(alpha: 0.14)
                          : BrewColor.cream.withValues(alpha: 0.07)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _copied
                        ? BrewColor.sageLight
                        : BrewColor.cream.withValues(alpha: 0.16),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 13,
                      color: _copied ? BrewColor.sageLight : BrewColor.cream,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _copied ? 'COPIED' : 'COPY',
                      style: BrewType.mono.copyWith(
                        fontSize: 9,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w700,
                        color: _copied ? BrewColor.sageLight : BrewColor.cream,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Dual-shop synchronization card illustrating multi-roaster connectivity.
class _DualShopsAccessCard extends StatelessWidget {
  const _DualShopsAccessCard({this.shops});

  final List<BrewShop>? shops;

  @override
  Widget build(BuildContext context) {
    final list = (shops != null && shops!.isNotEmpty) ? shops! : BrewShop.pending;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.14),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(BrewSpace.grid * 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      size: 14,
                      color: BrewColor.sageLight,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'CONNECTED COFFEE SHOPS',
                      style: BrewType.mono.copyWith(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: BrewColor.sageLight,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Text(
                  '${list.length} OF ${list.length} LINKED',
                  style: BrewType.mono.copyWith(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: BrewColor.cream.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          for (final (index, shop) in list.indexed) ...[
            if (index > 0) const SizedBox(height: BrewSpace.grid * 1.25),
            _ShopSyncTile(
              shop: shop,
              accent: shop.partner == BrewPartner.a
                  ? const Color(0xFF588157)
                  : const Color(0xFFA8C695),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShopSyncTile extends StatelessWidget {
  const _ShopSyncTile({
    required this.shop,
    required this.accent,
  });

  final BrewShop shop;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isOpen = shop.status == BrewShopStatus.open;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: BrewColor.cream.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOpen ? accent : BrewColor.cream.withValues(alpha: 0.3),
              shape: BoxShape.circle,
              boxShadow: isOpen
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shop.displayName,
                  style: BrewType.title.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: BrewColor.cream,
                  ),
                ),
                Text(
                  shop.displayDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrewType.mono.copyWith(
                    fontSize: 9.5,
                    color: BrewColor.cream.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
            decoration: BoxDecoration(
              color: isOpen
                  ? BrewColor.sage.withValues(alpha: 0.18)
                  : BrewColor.cream.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sync_rounded,
                  size: 11,
                  color: isOpen
                      ? BrewColor.sageLight
                      : BrewColor.cream.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  isOpen ? 'SYNCED' : shop.status.label.toUpperCase(),
                  style: BrewType.mono.copyWith(
                    fontSize: 8.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: isOpen
                        ? BrewColor.sageLight
                        : BrewColor.cream.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tactile luxury log out action button replacing the plain text link.
class _LuxuryLogOutButton extends StatefulWidget {
  const _LuxuryLogOutButton({this.onSignOut});

  final VoidCallback? onSignOut;

  @override
  State<_LuxuryLogOutButton> createState() => _LuxuryLogOutButtonState();
}

class _LuxuryLogOutButtonState extends State<_LuxuryLogOutButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onSignOut != null;

    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  HapticFeedback.mediumImpact();
                  widget.onSignOut!();
                }
              : null,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          child: AnimatedScale(
            duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.97 : (_hovered ? 1.02 : 1.0),
            child: AnimatedContainer(
              duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _pressed
                    ? BrewColor.alert.withValues(alpha: 0.22)
                    : (_hovered
                        ? BrewColor.alert.withValues(alpha: 0.14)
                        : BrewColor.alert.withValues(alpha: 0.07)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _pressed || _hovered
                      ? BrewColor.alert.withValues(alpha: 0.7)
                      : BrewColor.alert.withValues(alpha: 0.3),
                  width: 1.0,
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: BrewColor.alert.withValues(alpha: 0.2),
                          blurRadius: 14,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.logout_rounded,
                    size: 16,
                    color: BrewColor.alert.withValues(alpha: enabled ? 1.0 : 0.4),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Log out',
                    style: BrewType.buttonLabel.copyWith(
                      color: BrewColor.alert.withValues(alpha: enabled ? 1.0 : 0.4),
                      letterSpacing: 1.2,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

/// Discreet security and encryption note at the base of the sheet.
class _SessionSecurityFooter extends StatelessWidget {
  const _SessionSecurityFooter();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 11,
            color: BrewColor.cream.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 5),
          Text(
            'End-to-end authenticated • QuickBrew v1.2.0',
            style: BrewType.mono.copyWith(
              fontSize: 9.5,
              color: BrewColor.cream.withValues(alpha: 0.45),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
