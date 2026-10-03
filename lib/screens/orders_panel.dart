import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons, Icon;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_buttons.dart';
import '../widgets/brew_sheet.dart';
import '../widgets/shop_mark.dart';
import '../widgets/stagger.dart';

/// Which of the two histories this tab is showing.
enum _OrdersFilter {
  placed('Orders'),
  saved('Saved');

  const _OrdersFilter(this.label);

  final String label;
}

/// Every order this account has placed, newest first — and, behind the Saved
/// filter, the one order it left half-made.
class OrdersPanel extends StatefulWidget {
  const OrdersPanel({
    super.key,
    required this.compact,
    required this.orders,
    this.draft,
    this.shopsForDraft,
    this.onResumeDraft,
    this.onDiscardDraft,
    this.onTrackOrder,
    this.onBrowseShops,
  });

  /// Short frame: the display line drops to 28.
  final bool compact;

  /// Null on a build with no Firestore behind it, which reads as "nothing known
  /// yet" rather than as an empty history.
  final Stream<List<BrewOrder>>? orders;

  /// The order the reader saved part-way through, if there is one.
  final Stream<BrewDraft?>? draft;

  /// What the shops were last called, so the saved-order card can name the shop
  /// the draft is from — see [BrewShop.nameOf].
  final List<BrewShop>? shopsForDraft;

  final void Function(BrewDraft draft)? onResumeDraft;
  final void Function(BrewDraft draft)? onDiscardDraft;
  final void Function(BrewOrder order, BrewShop? shop)? onTrackOrder;
  final VoidCallback? onBrowseShops;

  @override
  State<OrdersPanel> createState() => _OrdersPanelState();
}

class _OrdersPanelState extends State<OrdersPanel> {
  _OrdersFilter _filter = _OrdersFilter.placed;

  void _select(_OrdersFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BrewDraft?>(
      stream: widget.draft,
      builder: (context, draftSnapshot) {
        final saved = draftSnapshot.data;

        return StreamBuilder<List<BrewOrder>>(
          stream: widget.orders,
          builder: (context, snapshot) {
            final placed = snapshot.data;
            return _sheet(placed: placed, saved: saved);
          },
        );
      },
    );
  }

  Widget _sheet({required List<BrewOrder>? placed, required BrewDraft? saved}) {
    var next = 0;
    int slot() => next++;

    final masthead = slot();
    final tagSlot = slot();
    final headline = slot();
    final subSlot = slot();
    final filterSlot = slot();
    final showPlaced = _filter == _OrdersFilter.placed;

    final int? emptySlot;
    final int? draftSlot;
    final List<int> rowSlots;

    if (showPlaced) {
      draftSlot = null;
      if (placed == null || placed.isEmpty) {
        emptySlot = slot();
        rowSlots = const [];
      } else {
        emptySlot = null;
        rowSlots = [for (final _ in placed) slot()];
      }
    } else {
      rowSlots = const [];
      if (saved == null) {
        emptySlot = slot();
        draftSlot = null;
      } else {
        emptySlot = null;
        draftSlot = slot();
      }
    }

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
                      Icons.receipt_long_rounded,
                      size: 12,
                      color: BrewColor.sageLight,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'ACTIVITY & HISTORY',
                      style: BrewType.mono.copyWith(
                        fontSize: 9.5,
                        letterSpacing: 1.4,
                        color: BrewColor.sageLight,
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
            'Your orders.',
            style: BrewType.displayAt(widget.compact ? 28 : 34),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 0.75),
        StaggerItem(
          index: subSlot,
          child: Text(
            'Live brewing updates, order tickets, and your saved draft.',
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.74),
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 2.5),
        StaggerItem(
          index: filterSlot,
          child: _FilterRow(
            current: _filter,
            placedCount: placed?.length ?? 0,
            savedCount: saved != null ? 1 : 0,
            onSelect: _select,
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 2.5),
        if (showPlaced) ...[
          if (placed == null)
            StaggerItem(
              index: emptySlot!,
              child: const _LoadingOrdersState(),
            )
          else if (placed.isEmpty)
            StaggerItem(
              index: emptySlot!,
              child: _EmptyOrdersState(
                isSavedTab: false,
                onAction: widget.onBrowseShops,
              ),
            )
          else
            for (final (index, order) in placed.indexed) ...[
              if (index > 0) const SizedBox(height: BrewSpace.grid * 1.5),
              StaggerItem(
                index: rowSlots[index],
                child: _OrderCard(
                  order: order,
                  shop: widget.shopsForDraft
                          ?.where((s) => s.partner == order.partner)
                          .firstOrNull ??
                      BrewShop(
                        partner: order.partner ?? BrewPartner.a,
                        status: BrewShopStatus.open,
                      ),
                  onTrack: widget.onTrackOrder == null
                      ? null
                      : () => widget.onTrackOrder!(
                            order,
                            widget.shopsForDraft
                                ?.where((s) => s.partner == order.partner)
                                .firstOrNull,
                          ),
                ),
              ),
            ],
        ] else ...[
          if (saved == null)
            StaggerItem(
              index: emptySlot!,
              child: _EmptyOrdersState(
                isSavedTab: true,
                onAction: widget.onBrowseShops,
              ),
            )
          else
            StaggerItem(
              index: draftSlot!,
              child: _DraftCard(
                draft: saved,
                shop: widget.shopsForDraft
                        ?.where((s) => s.partner == saved.partner)
                        .firstOrNull ??
                    BrewShop(
                      partner: saved.partner,
                      status: BrewShopStatus.open,
                    ),
                shopName: BrewShop.nameOf(saved.partner, widget.shopsForDraft),
                onResume: widget.onResumeDraft == null
                    ? null
                    : () => widget.onResumeDraft!(saved),
                onDiscard: widget.onDiscardDraft == null
                    ? null
                    : () => widget.onDiscardDraft!(saved),
              ),
            ),
        ],
        const SizedBox(height: BrewSpace.grid * 4),
      ],
    );
  }
}

/// An elevated luxury frosted segmented pill bar for filtering Orders and Saved drafts.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.current,
    required this.placedCount,
    required this.savedCount,
    required this.onSelect,
  });

  final _OrdersFilter current;
  final int placedCount;
  final int savedCount;
  final ValueChanged<_OrdersFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC0D1C12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.14),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterTab(
            filter: _OrdersFilter.placed,
            label: 'Orders',
            count: placedCount,
            selected: current == _OrdersFilter.placed,
            onPressed: () => onSelect(_OrdersFilter.placed),
          ),
          const SizedBox(width: 4),
          _FilterTab(
            filter: _OrdersFilter.saved,
            label: 'Saved',
            count: savedCount,
            hasAlert: savedCount > 0,
            selected: current == _OrdersFilter.saved,
            onPressed: () => onSelect(_OrdersFilter.saved),
          ),
        ],
      ),
    );
  }
}

class _FilterTab extends StatefulWidget {
  const _FilterTab({
    required this.filter,
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
    this.hasAlert = false,
  });

  final _OrdersFilter filter;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onPressed;
  final bool hasAlert;

  @override
  State<_FilterTab> createState() => _FilterTabState();
}

class _FilterTabState extends State<_FilterTab> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final selected = widget.selected;

    return Semantics(
      button: true,
      selected: selected,
      label: '${widget.label}, ${widget.count} items',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
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
            scale: _pressed ? 0.96 : (_hovered && !selected ? 1.03 : 1.0),
            child: AnimatedContainer(
              duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? BrewColor.sage.withValues(alpha: 0.32)
                    : (_hovered
                        ? BrewColor.cream.withValues(alpha: 0.08)
                        : const Color(0x00000000)),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? BrewColor.sageLight.withValues(alpha: 0.7)
                      : const Color(0x00000000),
                  width: 1.0,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: BrewColor.sage.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label.toUpperCase(),
                    style: BrewType.mono.copyWith(
                      fontSize: 10.5,
                      letterSpacing: 1.2,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected
                          ? BrewColor.cream
                          : BrewColor.cream.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: selected
                          ? BrewColor.sageLight
                          : (widget.hasAlert
                              ? BrewColor.alert.withValues(alpha: 0.25)
                              : BrewColor.cream.withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(999),
                      border: widget.hasAlert && !selected
                          ? Border.all(
                              color: BrewColor.alert.withValues(alpha: 0.5),
                              width: 0.8,
                            )
                          : null,
                    ),
                    child: Text(
                      '${widget.count}',
                      style: BrewType.mono.copyWith(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? const Color(0xFF0D1B12)
                            : (widget.hasAlert
                                ? BrewColor.alert
                                : BrewColor.cream.withValues(alpha: 0.85)),
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

/// A luxury empty state card with glowing icon medallion and call-to-action button.
class _EmptyOrdersState extends StatefulWidget {
  const _EmptyOrdersState({
    required this.isSavedTab,
    this.onAction,
  });

  final bool isSavedTab;
  final VoidCallback? onAction;

  @override
  State<_EmptyOrdersState> createState() => _EmptyOrdersStateState();
}

class _EmptyOrdersStateState extends State<_EmptyOrdersState> {
  bool _btnPressed = false;
  bool _btnHovered = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final isSaved = widget.isSavedTab;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: BrewSpace.grid * 3,
        vertical: BrewSpace.grid * 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.12),
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
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BrewColor.sage.withValues(alpha: 0.14),
              border: Border.all(
                color: BrewColor.sageLight.withValues(alpha: 0.35),
                width: 1.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33A8C695),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              isSaved
                  ? Icons.bookmark_border_rounded
                  : Icons.local_cafe_rounded,
              size: 26,
              color: BrewColor.sageLight,
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          Text(
            isSaved ? 'Nothing saved' : 'Nothing yet',
            style: BrewType.rowTitle.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: BrewColor.cream,
            ),
          ),
          const SizedBox(height: BrewSpace.grid),
          Text(
            isSaved
                ? 'An order you leave mid-way will stay saved right here, ready to pick up whenever you want.'
                : 'Pick a shop on Home and craft your custom brew. Your live progress ticket and receipt will land right here.',
            textAlign: TextAlign.center,
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
          if (widget.onAction != null) ...[
            const SizedBox(height: BrewSpace.grid * 3),
            MouseRegion(
              onEnter: (_) => setState(() => _btnHovered = true),
              onExit: (_) => setState(() => _btnHovered = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onAction!();
                },
                onTapDown: (_) => setState(() => _btnPressed = true),
                onTapUp: (_) => setState(() => _btnPressed = false),
                onTapCancel: () => setState(() => _btnPressed = false),
                child: AnimatedScale(
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  scale: _btnPressed ? 0.95 : (_btnHovered ? 1.04 : 1.0),
                  child: AnimatedContainer(
                    duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      color: _btnPressed
                          ? BrewColor.cream.withValues(alpha: 0.85)
                          : BrewColor.cream,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: _btnHovered
                              ? const Color(0x66E8DCC4)
                              : const Color(0x33000000),
                          blurRadius: _btnHovered ? 14 : 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isSaved ? 'START A NEW BREW' : 'EXPLORE COFFEE SHOPS',
                          style: BrewType.buttonLabel.copyWith(
                            color: const Color(0xFF13251A),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSlide(
                          duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
                          curve: Curves.easeOutCubic,
                          offset: Offset((_btnPressed || _btnHovered) ? 0.25 : 0.0, 0.0),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: Color(0xFF13251A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingOrdersState extends StatelessWidget {
  const _LoadingOrdersState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BrewSpace.grid * 3),
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            size: 18,
            color: BrewColor.sageLight,
          ),
          const SizedBox(width: 12),
          Text(
            'Looking up your orders…',
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

/// An elevated frosted glass card for placed orders with live status beacon and tracking.
class _OrderCard extends StatefulWidget {
  const _OrderCard({
    required this.order,
    required this.shop,
    this.onTrack,
  });

  final BrewOrder order;
  final BrewShop shop;
  final VoidCallback? onTrack;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _cardHovered = false;
  bool _pressed = false;
  bool _trackHovered = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final order = widget.order;
    final isActive = order.stage.isActive;
    final isRejected = order.stage == BrewOrderStage.rejected;
    final isCompleted = order.stage == BrewOrderStage.completed;

    return Semantics(
      button: isActive,
      label: '${order.shopName}, ${order.stage.label}. ${order.itemLine}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _cardHovered = true),
        onExit: (_) => setState(() => _cardHovered = false),
        cursor: isActive ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isActive && widget.onTrack != null) {
              HapticFeedback.lightImpact();
              widget.onTrack!();
            }
          },
          onTapDown: (_) {
            if (isActive) setState(() => _pressed = true);
          },
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.985 : (_cardHovered && isActive ? 1.006 : 1.0),
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
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pressed
                      ? BrewColor.fieldFocus
                      : (_cardHovered && isActive
                          ? BrewColor.cream.withValues(alpha: 0.22)
                          : BrewColor.cream.withValues(alpha: 0.12)),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _cardHovered && isActive
                        ? const Color(0x55000000)
                        : const Color(0x40000000),
                    blurRadius: _cardHovered && isActive ? 20 : 16,
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
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: BrewColor.cream.withValues(alpha: 0.12),
                            width: 1.0,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: BrewShopMark(shop: widget.shop, dimension: 42),
                        ),
                      ),
                      const SizedBox(width: BrewSpace.grid * 1.5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.shopName,
                              style: BrewType.rowTitle.copyWith(
                                fontWeight: FontWeight.w600,
                                color: BrewColor.cream,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: BrewColor.cream.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: BrewColor.cream.withValues(alpha: 0.14),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    order.reference,
                                    style: BrewType.mono.copyWith(
                                      fontSize: 9.5,
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.w700,
                                      color: BrewColor.sageLight,
                                    ),
                                  ),
                                ),
                                if (order.placedAt case final placedAt?)
                                  Text(
                                    _formatTime(placedAt),
                                    style: BrewType.mono.copyWith(
                                      fontSize: 9.5,
                                      color: BrewColor.cream.withValues(alpha: 0.55),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: BrewSpace.grid),
                      _buildStageBadge(order, isActive, isRejected, isCompleted),
                    ],
                  ),
                  const SizedBox(height: BrewSpace.grid * 1.5),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x40000000),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: BrewColor.cream.withValues(alpha: 0.08),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.local_cafe_rounded,
                            size: 14,
                            color: BrewColor.sageLight,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            order.itemLine,
                            style: BrewType.rowBody.copyWith(
                              color: BrewColor.cream.withValues(alpha: 0.9),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: BrewSpace.grid * 1.5),
                  Row(
                    children: [
                      if (order.totalLabel case final total?) ...[
                        Text(
                          total,
                          style: BrewType.mono.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: BrewColor.cream,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (isActive && widget.onTrack != null)
                        MouseRegion(
                          onEnter: (_) => setState(() => _trackHovered = true),
                          onExit: (_) => setState(() => _trackHovered = false),
                          child: AnimatedContainer(
                            duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: (_trackHovered || _pressed)
                                  ? BrewColor.sage.withValues(alpha: 0.35)
                                  : BrewColor.sage.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: (_trackHovered || _pressed)
                                    ? BrewColor.sageLight
                                    : BrewColor.sage.withValues(alpha: 0.45),
                                width: 1.0,
                              ),
                              boxShadow: (_trackHovered || _pressed)
                                  ? const [
                                      BoxShadow(
                                        color: Color(0x55B7D5B0),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Track order',
                                  style: BrewType.mono.copyWith(
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w600,
                                    color: BrewColor.cream,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                AnimatedSlide(
                                  duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
                                  curve: Curves.easeOutCubic,
                                  offset: Offset((_trackHovered || _pressed) ? 0.3 : 0.0, 0.0),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 13,
                                    color: BrewColor.sageLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (isCompleted)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 13,
                              color: BrewColor.sageLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Fulfilled',
                              style: BrewType.mono.copyWith(
                                fontSize: 10,
                                letterSpacing: 0.8,
                                color: BrewColor.cream.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStageBadge(
    BrewOrder order,
    bool isActive,
    bool isRejected,
    bool isCompleted,
  ) {
    if (isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: BrewColor.sage.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: BrewColor.sage.withValues(alpha: 0.45),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: BrewColor.sageLight,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x88B7D5B0),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              order.stage.name.toUpperCase(),
              style: BrewType.mono.copyWith(
                fontSize: 9.5,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
                color: BrewColor.sageLight,
              ),
            ),
          ],
        ),
      );
    }

    if (isRejected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: BrewColor.alert.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: BrewColor.alert.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Text(
          'DECLINED',
          style: BrewType.mono.copyWith(
            fontSize: 9.5,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
            color: BrewColor.alert,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BrewColor.cream.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      child: Text(
        'COMPLETED',
        style: BrewType.mono.copyWith(
          fontSize: 9.5,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w600,
          color: BrewColor.cream.withValues(alpha: 0.65),
        ),
      ),
    );
  }

  static String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

/// The order the reader started and left, rendered as an elevated warm-accented luxury card.
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.shop,
    required this.shopName,
    this.onResume,
    this.onDiscard,
  });

  final BrewDraft draft;
  final BrewShop shop;
  final String shopName;
  final VoidCallback? onResume;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final count = draft.drinkCount;

    return Container(
      padding: const EdgeInsets.all(BrewSpace.grid * 2.5),
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: BrewColor.alert.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: BrewColor.alert.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: BrewColor.alert.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.edit_note_rounded,
                      size: 13,
                      color: BrewColor.alert,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'IN PROGRESS DRAFT',
                      style: BrewType.mono.copyWith(
                        fontSize: 9.5,
                        letterSpacing: 1.1,
                        color: BrewColor.alert,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 1.5),
          Row(
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
                  child: BrewShopMark(shop: shop, dimension: 40),
                ),
              ),
              const SizedBox(width: BrewSpace.grid * 1.5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      style: BrewType.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: BrewColor.cream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count == 1
                          ? '1 drink, not yet ordered'
                          : '$count drinks, not yet ordered',
                      style: BrewType.rowBody.copyWith(
                        color: BrewColor.cream.withValues(alpha: 0.7),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 1.5),
          Text(
            'SAVED · PICK UP WHERE YOU LEFT OFF',
            style: BrewType.mono.copyWith(
              fontSize: 10,
              letterSpacing: 1.2,
              color: BrewColor.cream.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          BrewPrimaryButton(
            label: 'RESUME ORDER →',
            asPill: true,
            onPressed: onResume,
          ),
          const SizedBox(height: BrewSpace.grid),
          Center(
            child: BrewTextButton(
              label: 'Discard order',
              ink: BrewColor.alert,
              onPressed: onDiscard,
            ),
          ),
        ],
      ),
    );
  }
}
