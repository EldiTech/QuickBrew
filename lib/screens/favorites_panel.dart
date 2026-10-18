import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../services/favorites_service.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_buttons.dart';
import '../widgets/brew_sheet.dart';
import '../widgets/stagger.dart';
import 'order_wizard_screen.dart';

/// Screen / Tab displaying all customer favorited coffee and beverage products.
///
/// Features:
/// - Header matching QuickBrew's artisanal design language and StaggerGroup reveal
/// - Realtime reactive listener on [FavoritesService.instance]
/// - Combined catalog resolution across both partner stores (Seven Coffee & Tea & Drip & Co)
/// - Shop origin badge ("Seven Coffee & Tea" / "Drip & Co"), price tags, and description
/// - Tap to immediately open the item in the 6-step [OrderWizardScreen]
/// - Quick heart un-favorite button with smooth removal animations and haptic feedback
/// - Polished empty state with "EXPLORE SHOPS" CTA navigating back to the Home tab
class FavoritesPanel extends StatefulWidget {
  const FavoritesPanel({
    super.key,
    required this.compact,
    this.session,
    this.counter,
    this.shops,
    this.onBrowseShops,
  });

  final bool compact;
  final BrewSession? session;
  final BrewCounter? counter;
  final Stream<List<BrewShop>>? shops;
  final VoidCallback? onBrowseShops;

  @override
  State<FavoritesPanel> createState() => _FavoritesPanelState();
}

class _FavoritesPanelState extends State<FavoritesPanel> {
  final FavoritesService _favoritesService = FavoritesService.instance;
  StreamSubscription<List<BrewMenuItem>>? _menuSubA;
  StreamSubscription<List<BrewMenuItem>>? _menuSubB;
  List<BrewMenuItem> _menuA = const [];
  List<BrewMenuItem> _menuB = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _favoritesService.addListener(_onFavoritesChanged);
    _favoritesService.initForUser(widget.session?.uid);
    _subscribeMenus();
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  void _subscribeMenus() {
    final counter = widget.counter;
    if (counter == null) {
      _loading = false;
      return;
    }

    _menuSubA = counter
        .menu(BrewPartner.a)
        .listen(
          (items) {
            if (mounted) {
              setState(() {
                _menuA = items;
                _loading = false;
              });
            }
          },
          onError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        );

    _menuSubB = counter
        .menu(BrewPartner.b)
        .listen(
          (items) {
            if (mounted) {
              setState(() {
                _menuB = items;
                _loading = false;
              });
            }
          },
          onError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        );
  }

  @override
  void didUpdateWidget(FavoritesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.uid != widget.session?.uid) {
      _favoritesService.initForUser(widget.session?.uid);
    }
  }

  @override
  void dispose() {
    _favoritesService.removeListener(_onFavoritesChanged);
    _menuSubA?.cancel();
    _menuSubB?.cancel();
    super.dispose();
  }

  /// Finds the item and its owning partner. First checks live menus, then fallback items.
  (BrewMenuItem, BrewPartner)? _resolveItem(String id) {
    for (final item in _menuA) {
      if (item.id == id) return (item, BrewPartner.a);
    }
    for (final item in _menuB) {
      if (item.id == id) return (item, BrewPartner.b);
    }

    // Fallback checks from CategoryMenuScreen definitions
    for (final item in const <BrewMenuItem>[]) {
      if (item.id == id) {
        final isDrip =
            item.id.startsWith('drip_') ||
            (item.category == 'Cà Phê' ||
                item.category == 'Hello Vietnam' ||
                item.category == 'Tiramisu' ||
                item.category == 'Premium' ||
                item.category == 'Milky Series');
        return (item, isDrip ? BrewPartner.a : BrewPartner.b);
      }
    }
    return null;
  }

  void _openOrderWizard(BrewMenuItem item, BrewPartner partner) {
    HapticFeedback.lightImpact();
    final shop =
        widget.counter?.lastShops
            ?.where((s) => s.partner == partner)
            .firstOrNull ??
        BrewShop(partner: partner, status: BrewShopStatus.open);

    Navigator.of(context).push(
      OrderWizardScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        shop: shop,
        session: widget.session,
        counter: widget.counter,
        item: item,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final favIds = _favoritesService.favoriteIds;
    final List<(BrewMenuItem, BrewPartner)> resolvedItems = [];
    for (final id in favIds) {
      final found = _resolveItem(id);
      if (found != null) {
        resolvedItems.add(found);
      }
    }

    var next = 0;
    int slot() => next++;

    final masthead = slot();
    final tagSlot = slot();
    final headline = slot();
    final subSlot = slot();
    final countPillSlot = slot();

    final List<int> rowSlots = [for (final _ in resolvedItems) slot()];
    final emptySlot = resolvedItems.isEmpty ? slot() : null;

    final staggerCount = math.max(1, next);

    return BrewSheet(
      staggerCount: staggerCount,
      children: [
        StaggerItem(index: masthead, child: const BrewWordmarkRow()),
        SizedBox(height: brewBlockGap(widget.compact)),
        StaggerItem(
          index: tagSlot,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x22E56B6F),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0x55E56B6F)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.favorite_rounded,
                      size: 12,
                      color: Color(0xFFFFA5AB),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'SAVED PRODUCTS',
                      style: BrewType.mono.copyWith(
                        fontSize: 9.5,
                        letterSpacing: 1.4,
                        color: const Color(0xFFFFA5AB),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BrewSpace.grid),
        StaggerItem(
          index: headline,
          child: Text(
            'Your favorites.',
            style: BrewType.displayAt(widget.compact ? 28 : 34),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 0.75),
        StaggerItem(
          index: subSlot,
          child: Text(
            'Your curated drinks and brews across both roasters, ready to reorder anytime.',
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.74),
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 2),

        // Count indicator
        StaggerItem(
          index: countPillSlot,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x1F132B1E),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: BrewColor.cream.withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${resolvedItems.length} ${resolvedItems.length == 1 ? 'ITEM' : 'ITEMS'} SAVED',
                      style: BrewType.mono.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: BrewColor.cream.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (resolvedItems.isNotEmpty)
                _ClearAllFavoritesButton(onPressed: _favoritesService.clearAll),
            ],
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 2),

        if (resolvedItems.isEmpty)
          StaggerItem(
            index: emptySlot!,
            child: _EmptyFavoritesState(onBrowse: widget.onBrowseShops),
          )
        else
          for (final (index, (item, partner)) in resolvedItems.indexed) ...[
            if (index > 0) const SizedBox(height: BrewSpace.grid * 1.5),
            StaggerItem(
              index: rowSlots[index],
              child: _FavoriteDrinkCard(
                item: item,
                partner: partner,
                onTap: () => _openOrderWizard(item, partner),
                onRemove: () {
                  HapticFeedback.selectionClick();
                  _favoritesService.toggleFavorite(item.id);
                },
              ),
            ),
          ],
      ],
    );
  }
}

class _ClearAllFavoritesButton extends StatefulWidget {
  const _ClearAllFavoritesButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_ClearAllFavoritesButton> createState() =>
      _ClearAllFavoritesButtonState();
}

class _ClearAllFavoritesButtonState extends State<_ClearAllFavoritesButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    return BrewPressable(
      onPressed: widget.onPressed,
      onPressedChanged: (value) => setState(() => _pressed = value),
      haptic: HapticFeedback.mediumImpact,
      radius: 999,
      pressed: _pressed,
      reduced: reduced,
      semanticsLabel: 'Clear all favorites',
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : BrewMotion.press,
        curve: BrewMotion.pressCurve,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: BrewColor.alert.withValues(alpha: _pressed ? 0.24 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: BrewColor.alert.withValues(alpha: _pressed ? 0.78 : 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_sweep_outlined,
              size: 15,
              color: BrewColor.alert.withValues(alpha: 0.95),
            ),
            const SizedBox(width: 6),
            Text(
              'CLEAR ALL',
              style: BrewType.mono.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: BrewColor.alert,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A favorited product card with photo/emblem, roaster chip, pricing, and buy action.
class _FavoriteDrinkCard extends StatelessWidget {
  const _FavoriteDrinkCard({
    required this.item,
    required this.partner,
    required this.onTap,
    required this.onRemove,
  });

  final BrewMenuItem item;
  final BrewPartner partner;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  String _formatPrice() {
    if (item.sizePrices.isNotEmpty) {
      final sorted = item.sizePrices.entries.toList()
        ..sort((a, b) => a.key.index.compareTo(b.key.index));
      return sorted
          .map((e) => '₱${(e.value / 100).toStringAsFixed(0)}')
          .join(' | ');
    } else if (item.priceCents != null) {
      return '₱${(item.priceCents! / 100).toStringAsFixed(0)}';
    }
    return '₱80';
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = item.imageBytes;
    final partnerName = partner == BrewPartner.a
        ? 'Drip & Co'
        : 'Seven Coffee & Tea';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xD90F2418),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: BrewColor.cream.withValues(alpha: 0.14),
            width: 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Drink visual emblem
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x333A9E7C), Color(0x1A091A11)],
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Builder(
                  builder: (context) {
                    if (imageBytes != null) {
                      return Image.memory(
                        imageBytes,
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                      );
                    }
                    return const Center(
                      child: Icon(
                        Icons.local_cafe_rounded,
                        size: 32,
                        color: Color(0xFF6FD3AA),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Content column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Partner shop pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x2E102B1D),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: BrewColor.cream.withValues(alpha: 0.15),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      partnerName.toUpperCase(),
                      style: BrewType.mono.copyWith(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: const Color(0xFFD4A373),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrewType.title.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: BrewColor.cream,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description ??
                        item.category ??
                        'Artisanal coffee blend',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrewType.rowBody.copyWith(
                      fontSize: 11.5,
                      color: BrewColor.sageLight.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatPrice(),
                    style: BrewType.mono.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6FD3AA),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Action buttons: Unfavorite heart + Buy button
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    child: const Icon(
                      Icons.favorite_rounded,
                      size: 20,
                      color: Color(0xFFE56B6F),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3A9E7C),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x443A9E7C), blurRadius: 8),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state when no items are favorited yet.
class _EmptyFavoritesState extends StatelessWidget {
  const _EmptyFavoritesState({this.onBrowse});

  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: BrewSpace.grid * 3,
        vertical: BrewSpace.grid * 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.12),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x22E56B6F),
              border: Border.all(color: const Color(0x55E56B6F), width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22E56B6F),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              size: 26,
              color: Color(0xFFFFA5AB),
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          Text(
            'No favorites yet',
            style: BrewType.rowTitle.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: BrewColor.cream,
            ),
          ),
          const SizedBox(height: BrewSpace.grid),
          Text(
            'Tap the heart icon on any beverage across the stores to keep your go-to coffees right here for quick re-ordering.',
            textAlign: TextAlign.center,
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
          if (onBrowse != null) ...[
            const SizedBox(height: BrewSpace.grid * 3),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onBrowse!();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: BrewColor.cream,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'EXPLORE COFFEE SHOPS',
                      style: BrewType.buttonLabel.copyWith(
                        color: const Color(0xFF13251A),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: Color(0xFF13251A),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
