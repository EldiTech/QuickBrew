import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show
        Icons,
        InputBorder,
        InputDecoration,
        Material,
        MaterialType,
        TextField,
        showDialog,
        showModalBottomSheet;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../brew_auth.dart';
import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/brew_buttons.dart';
import '../widgets/brew_filter_row.dart';
import '../widgets/brew_grid.dart';
import '../widgets/brew_sheet.dart';
import '../widgets/stagger.dart';
import 'order_wizard_screen.dart';

/// Where View menu goes: one shop's board, live from Firestore.
///
/// This is a menu to read, so it is the ledger again — ruled rows, no cards. The
/// blocks on the home screen were bounded because they were two choices; these
/// are a list of one shop's items, which is exactly what the landing screen's
/// hairline rows are for.
///
/// Each item has a View, which opens the same facts the card already shows —
/// picture, name, description, price — full size in a sheet, and a Buy, which
/// starts the order.
///
/// Buy used to open a sheet admitting that ordering was not live. It now pushes
/// [OrderWizardScreen], which is where the size choice, the quantity stepper and
/// the cart went: those three belong to one drink being configured, not to a
/// board of a hundred being browsed, and putting a stepper on every cell would
/// have asked the reader to build an order out of a grid. The board's job stays
/// what the brief asked for — select a partner and begin browsing its menu in
/// one step — and the wizard is what happens after they have chosen.
class MenuScreen extends StatefulWidget {
  const MenuScreen({
    super.key,
    required this.shop,
    this.session,
    this.counter,
  });

  /// The shop as the card the reader just tapped had it — its name and its
  /// hours included. Handed over whole rather than as a partner plus a status
  /// so this screen prints whatever the shop currently calls itself: a name an
  /// admin edited would otherwise change on the home screen and stay stale
  /// here, one tap away from it.
  final BrewShop shop;

  /// Who is reading. Carried only so Buy can hand it to the wizard, which needs
  /// a uid to file the order under — this screen itself has nothing to do with
  /// who is signed in, and a board renders identically for everybody.
  final BrewSession? session;

  final BrewCounter? counter;

  static Route<void> route({
    bool reduced = false,
    required BrewShop shop,
    BrewSession? session,
    BrewCounter? counter,
  }) {
    final duration = reduced ? Duration.zero : BrewMotion.transit;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          MenuScreen(shop: shop, session: session, counter: counter),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  /// Subscribed once. A stream built inside `build` would be a fresh Firestore
  /// listener on every frame — see the same note on the home screen's reads.
  Stream<List<BrewMenuItem>>? _menu;

  /// Which section of the board is showing. See the same pair on
  /// [AdminMenuScreen](admin/admin_menu_screen.dart) for why these hold the
  /// category's own name rather than an index into a list that can change
  /// under them.
  String _category = _allCategories;
  String _subCategory = _allCategories;

  static const _allCategories = ' All';

  /// What the search field holds, lower-cased once here rather than on every
  /// item compared against it in [_visible].
  final _search = TextEditingController();
  String _query = '';

  /// Which page of the filtered board is showing, zero-based. Reset to the
  /// first page whenever the filter or search narrows the board to a
  /// different set of items, so a page number left over from a longer list
  /// never strands the reader past the end of a shorter one.
  int _page = 0;

  static const _pageSize = 10;

  /// The most orders one reader can have open at once — the same figure as
  /// [OrderWizardScreen]'s own cap, restated here rather than shared because
  /// that screen's constant is private to it, the way every duplicated
  /// private member between these boards already is (see [_PageRow]).
  ///
  /// This screen checks it at Buy so a reader at the cap is told before the
  /// wizard opens, not six steps into it: the wizard's own gate on Confirm
  /// still stands behind this one, but a flow a reader can walk all the way
  /// down before learning it was closed is the wrong place to say so first.
  static const _maxActiveOrders = 5;

  /// How many orders this reader has open, as of the last snapshot. Null
  /// until the first one lands — which [_atOrderCap] reads as "not known
  /// yet", so a reader is never turned away on a count this screen has not
  /// actually seen. The wizard makes the same choice for the same reason.
  int? _activeOrderCount;

  StreamSubscription<List<BrewOrder>>? _activeOrdersSubscription;

  /// Whether Buy should refuse rather than open the wizard.
  bool get _atOrderCap => switch (_activeOrderCount) {
        final count? => count >= _maxActiveOrders,
        null => false,
      };

  @override
  void initState() {
    super.initState();
    _menu = widget.counter?.menu(widget.shop.partner);

    // Watched rather than checked once, like the wizard's own subscription:
    // an order finishing at the counter while the reader browses should
    // reopen Buy without them having to leave and come back.
    final counter = widget.counter;
    final session = widget.session;
    if (counter != null && session != null) {
      _activeOrdersSubscription =
          counter.activeOrders(session.uid).listen((orders) {
        if (!mounted) return;
        setState(() => _activeOrderCount = orders.length);
      });
    }
  }

  @override
  void dispose() {
    _activeOrdersSubscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The items the filter admits. A selection whose category has since left
  /// the board falls back to the whole thing rather than to an empty screen.
  List<BrewMenuItem> _visible(List<BrewMenuItem> items) {
    final byCategory = _byCategory(items);
    if (_query.isEmpty) return byCategory;
    return byCategory
        .where(
          (item) =>
              item.name.toLowerCase().contains(_query) ||
              (item.description?.toLowerCase().contains(_query) ?? false),
        )
        .toList();
  }

  List<BrewMenuItem> _byCategory(List<BrewMenuItem> items) {
    if (_category == _allCategories) return items;
    final inCategory =
        items.where((item) => item.category == _category).toList();
    if (inCategory.isEmpty) return items;
    if (_subCategory == _allCategories) return inCategory;
    final inSub =
        inCategory.where((item) => item.subCategory == _subCategory).toList();
    return inSub.isEmpty ? inCategory : inSub;
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim().toLowerCase();
      _page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.height <= BrewSpace.compactHeight;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final shop = widget.shop;

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
          child: StreamBuilder<List<BrewMenuItem>>(
            stream: _menu,
          builder: (context, snapshot) {
            final items = snapshot.data;
            final failed = snapshot.hasError || _menu == null;
            final categories = BrewMenuItem.categoriesOf(items ?? const []);
            final filtered = categories.length > 1;

            // Sliced to the current page here rather than inside [_board], so
            // this frame's stagger count — which has to be fixed before the
            // first [StaggerItem] below reads it — reflects the row count that
            // will actually be drawn, not the whole filtered board.
            final visible = items == null ? null : _visible(items);
            final pageCount =
                visible == null ? 0 : (visible.length / _pageSize).ceil();
            final page =
                pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
            final pageItems =
                visible?.skip(page * _pageSize).take(_pageSize).toList();

            // Header, context tag, headline, status line, search field, filter
            // row where there is one, then a row each of the current page.
            final tagIndex = 1;
            final headlineIndex = 2;
            final statusIndex = 3;
            final searchIndex = 4;
            final filterIndex = searchIndex + 1;
            final base = filterIndex + (filtered ? 1 : 0);

            return StaggerGroup(
              itemCount: base + (pageItems?.length ?? 1),
              reveal: true,
              reduced: reduced,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: BrewSpace.gutter,
                  right: BrewSpace.gutter,
                  top: math.max(media.padding.top, BrewSpace.minInset) +
                      BrewSpace.headerClearance,
                  bottom: math.max(
                    media.padding.bottom,
                    BrewSpace.bottomGroupInset,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StaggerItem(index: 0, child: _header(context)),
                    SizedBox(height: brewBlockGap(compact)),
                    StaggerItem(
                      index: tagIndex,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: BrewColor.cream.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: BrewColor.cream.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_cafe_rounded,
                              size: 12,
                              color: BrewColor.sageLight,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'ROASTER CATALOG • LIVE MENU',
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
                    ),
                    const SizedBox(height: BrewSpace.grid),
                    StaggerItem(
                      index: headlineIndex,
                      child: Text(
                        shop.displayName,
                        style: BrewType.displayAt(compact ? 28 : 34),
                      ),
                    ),
                    const SizedBox(height: BrewSpace.grid),
                    StaggerItem(
                      index: statusIndex,
                      child: Text(
                        shop.displayDescription.isEmpty
                            ? shop.status.label
                            : '${shop.displayDescription} · ${shop.status.label}',
                        style: BrewType.rowBody.copyWith(
                          color: BrewColor.cream.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    const SizedBox(height: BrewSpace.grid * 2),
                    StaggerItem(
                      index: searchIndex,
                      child: _MenuSearchField(
                        controller: _search,
                        onChanged: _onQueryChanged,
                      ),
                    ),
                    if (filtered) ...[
                      const SizedBox(height: BrewSpace.grid * 2),
                      StaggerItem(
                        index: filterIndex,
                        child: _filters(items!, categories),
                      ),
                    ],
                    const SizedBox(height: BrewSpace.grid * 3),
                    ..._board(
                      items,
                      pageItems: pageItems,
                      failed: failed,
                      base: base,
                      page: page,
                      pageCount: pageCount,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

  /// The section chips, bled past the gutter so the row runs off both edges —
  /// the one place on this screen where something is allowed to, because a
  /// scrolling row that stopped short of the margin would read as a list that
  /// had simply run out rather than one that continues.
  Widget _filters(List<BrewMenuItem> items, List<String> categories) {
    final subCategories = _category == _allCategories
        ? const <String>[]
        : BrewMenuItem.subCategoriesOf(items, _category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrewFilterRow.bled(
          context,
          options: [_allCategories, ...categories],
          selected: _category,
          onSelected: (value) => setState(() {
            _category = value;
            _subCategory = _allCategories;
          }),
        ),
        if (subCategories.isNotEmpty) ...[
          const SizedBox(height: BrewSpace.grid),
          BrewFilterRow.bled(
            context,
            options: [_allCategories, ...subCategories],
            selected: _subCategory,
            onSelected: (value) => setState(() => _subCategory = value),
          ),
        ],
      ],
    );
  }

  List<Widget> _board(
    List<BrewMenuItem>? items, {
    required List<BrewMenuItem>? pageItems,
    required bool failed,
    required int base,
    required int page,
    required int pageCount,
  }) {
    // Checked before the null: a refused read and a read still in flight both
    // arrive here with no items, and only this flag tells them apart. Saying
    // "loading" for the first is the bug that left this screen spinning.
    if (failed && items == null) {
      return [
        Text(
          'Could not load the board. Check your connection and try again.',
          style: BrewType.rowBody,
        ),
      ];
    }
    if (items == null) {
      return [Text('Loading the board…', style: BrewType.rowBody)];
    }
    if (items.isEmpty) {
      // The truthful reading of an empty collection, and one a reader can act on
      // — as opposed to a spinner that never stops.
      return [
        Text(
          '${widget.shop.displayName} has not published a menu yet.',
          style: BrewType.rowBody,
        ),
      ];
    }
    if (pageItems == null || pageItems.isEmpty) {
      // No product on the board matches the search or filter in play, as
      // opposed to the board itself being empty — the case just above.
      return [
        Text('No drinks match that search.', style: BrewType.rowBody),
      ];
    }

    return [
      BrewGrid(
        children: [
          for (final (index, item) in pageItems.indexed)
            StaggerItem(
              // Clamped to the group's own length: the stagger timeline was
              // sized from this page's row count, and an index past the end of
              // it asserts inside Interval rather than merely animating oddly.
              index: math.min(base + index, base + pageItems.length - 1),
              child: _MenuRow(
                item: item,
                shop: widget.shop,
                session: widget.session,
                counter: widget.counter,
                atOrderCap: _atOrderCap,
                activeOrders: _activeOrderCount ?? 0,
              ),
            ),
        ],
      ),
      if (pageCount > 1) ...[
        const SizedBox(height: BrewSpace.grid * 2),
        _PageRow(
          page: page,
          pageCount: pageCount,
          onPrevious: page > 0 ? () => setState(() => _page = page - 1) : null,
          onNext:
              page < pageCount - 1 ? () => setState(() => _page = page + 1) : null,
        ),
      ],
    ];
  }

  /// The same lockup as every other screen, so the cup does not move.
  Widget _header(BuildContext context) {
    return Row(
      children: [
        const BrewWordmarkRow(),
        const Spacer(),
        BrewPressable(
          onPressed: () => Navigator.of(context).maybePop(),
          onPressedChanged: (_) {},
          pressed: false,
          reduced: MediaQuery.disableAnimationsOf(context),
          semanticsLabel: 'Back to the coffee shops',
          radius: 999,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: BrewColor.cream.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: BrewColor.cream.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back_rounded,
                  size: 14,
                  color: BrewColor.cream,
                ),
                const SizedBox(width: 6),
                Text(
                  'BACK',
                  style: BrewType.mono.copyWith(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: BrewColor.cream,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuSearchField extends StatefulWidget {
  const _MenuSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_MenuSearchField> createState() => _MenuSearchFieldState();
}

class _MenuSearchFieldState extends State<_MenuSearchField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: BrewMotion.press,
        curve: Curves.easeOut,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xCC132218),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _focused
                ? BrewColor.sage
                : BrewColor.cream.withValues(alpha: 0.16),
            width: _focused ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (_focused)
              BoxShadow(
                color: BrewColor.sage.withValues(alpha: 0.2),
                blurRadius: 10,
                spreadRadius: 1,
              ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 20,
              color: _focused
                  ? BrewColor.sageLight
                  : BrewColor.cream.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: widget.controller,
                onChanged: (val) {
                  widget.onChanged(val);
                  setState(() {});
                },
                textInputAction: TextInputAction.search,
                style: BrewType.rowBody.copyWith(
                  color: BrewColor.cream,
                  fontSize: 14,
                ),
                cursorColor: BrewColor.sageLight,
                decoration: InputDecoration(
                  hintText: 'Find a drink by name or description...',
                  hintStyle: BrewType.rowBody.copyWith(
                    color: BrewColor.cream.withValues(alpha: 0.38),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (hasText)
              BrewPressable(
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
                onPressedChanged: (_) {},
                pressed: false,
                reduced: MediaQuery.disableAnimationsOf(context),
                radius: 999,
                semanticsLabel: 'Clear search',
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: BrewColor.cream.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: BrewColor.cream,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The board's pager: Previous and Next either side of "Page X of Y", shown
/// only once the board — or what a filter or search has narrowed it to —
/// runs past one page. Ten drinks a page rather than a single long list, so
/// a hundred-odd product board never asks the reader to scroll past all of it
/// to find the one item they are after.
///
/// Duplicated from [AdminMenuScreen]'s identical private widget rather than
/// shared, for the reason `_MenuCardImage` above already duplicates that
/// screen's — two files, neither owning the other's private types.
class _PageRow extends StatelessWidget {
  const _PageRow({
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BrewMonoButton(
          label: 'Previous',
          semanticsLabel: 'Previous page',
          onPressed: onPrevious,
        ),
        Expanded(
          child: Text(
            'Page ${page + 1} of $pageCount',
            textAlign: TextAlign.center,
            style: BrewType.mono,
          ),
        ),
        BrewMonoButton(
          label: 'Next',
          semanticsLabel: 'Next page',
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// One item as a grid cell: a full-bleed picture on top, filed under a
/// category tag, then its name and what it costs.
///
/// Photo-forward rather than the ruled row the rest of the app draws
/// elsewhere: a menu a reader is choosing from is browsed by picture first,
/// the way the till card and the home screen's shop cards already are. An
/// item with no picture keeps the same footprint — see [_MenuCardImage] —
/// so a half-photographed board still lines up as one grid rather than
/// alternating tall and short cells.
class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.item,
    required this.shop,
    this.session,
    this.counter,
    this.atOrderCap = false,
    this.activeOrders = 0,
  });

  final BrewMenuItem item;
  final BrewShop shop;
  final BrewSession? session;
  final BrewCounter? counter;
  final bool atOrderCap;
  final int activeOrders;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final sizeLines = item.sizeLines;
    final price = item.price;
    final category = item.category;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: BrewMotion.press,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0.0, _hovered ? -3.0 : 0.0, 0.0),
        decoration: BoxDecoration(
          color: const Color(0xEB132218),
          border: Border.all(
            color: _hovered
                ? BrewColor.sageLight.withValues(alpha: 0.45)
                : BrewColor.cream.withValues(alpha: 0.12),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            const BoxShadow(
              color: Color(0x40000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
            if (_hovered)
              BoxShadow(
                color: BrewColor.sage.withValues(alpha: 0.18),
                blurRadius: 20,
                spreadRadius: 1,
              ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MenuCardImage(bytes: item.imageBytes, category: category),
            Padding(
              padding: const EdgeInsets.all(BrewSpace.grid * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: BrewType.rowTitle.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: BrewColor.cream,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: BrewSpace.grid * 1.25),
                  if (price != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: BrewColor.cream.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: BrewColor.cream.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        price,
                        style: BrewType.mono.copyWith(
                          color: BrewColor.cream,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (sizeLines.isNotEmpty)
                    _MenuCardPrices(sizeLines: sizeLines),
                  if (price != null || sizeLines.isNotEmpty)
                    const SizedBox(height: BrewSpace.grid * 1.5),
                  Row(
                    children: [
                      Expanded(
                        child: _SecondaryCardPill(
                          icon: Icons.visibility_outlined,
                          label: 'VIEW',
                          onPressed: () => _showDetail(context, item),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PrimaryCardPill(
                          icon: Icons.bolt_rounded,
                          label: 'BUY',
                          onPressed: () => _startOrder(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, BrewMenuItem item) {
    showDialog<void>(
      context: context,
      barrierColor: BrewColor.fieldDeep.withValues(alpha: 0.92),
      builder: (context) => _MenuItemDetailDialog(item: item),
    );
  }

  void _startOrder(BuildContext context) {
    if (widget.atOrderCap) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: BrewColor.field,
        builder: (context) => _OrderCapSheet(activeOrders: widget.activeOrders),
      );
      return;
    }
    Navigator.of(context).push(
      OrderWizardScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        shop: widget.shop,
        item: widget.item,
        session: widget.session,
        counter: widget.counter,
      ),
    );
  }
}

class _SecondaryCardPill extends StatefulWidget {
  const _SecondaryCardPill({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_SecondaryCardPill> createState() => _SecondaryCardPillState();
}

class _SecondaryCardPillState extends State<_SecondaryCardPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return BrewPressable(
      onPressed: () {
        HapticFeedback.selectionClick();
        widget.onPressed();
      },
      onPressedChanged: (p) => setState(() => _pressed = p),
      pressed: _pressed,
      reduced: MediaQuery.disableAnimationsOf(context),
      radius: 999,
      semanticsLabel: widget.label,
      child: AnimatedContainer(
        duration: BrewMotion.press,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _pressed
              ? BrewColor.cream.withValues(alpha: 0.14)
              : BrewColor.cream.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: BrewColor.cream.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              size: 13,
              color: BrewColor.cream.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 5),
            Text(
              widget.label,
              style: BrewType.mono.copyWith(
                fontSize: 11,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
                color: BrewColor.cream.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryCardPill extends StatefulWidget {
  const _PrimaryCardPill({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_PrimaryCardPill> createState() => _PrimaryCardPillState();
}

class _PrimaryCardPillState extends State<_PrimaryCardPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return BrewPressable(
      onPressed: () {
        HapticFeedback.selectionClick();
        widget.onPressed();
      },
      onPressedChanged: (p) => setState(() => _pressed = p),
      pressed: _pressed,
      reduced: MediaQuery.disableAnimationsOf(context),
      radius: 999,
      semanticsLabel: widget.label,
      child: AnimatedContainer(
        duration: BrewMotion.press,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _pressed
                ? const [Color(0xFF386343), Color(0xFF2E5338)]
                : const [Color(0xFF4C8058), Color(0xFF386343)],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFF72A880),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40386343),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              size: 13,
              color: BrewColor.cream,
            ),
            const SizedBox(width: 4),
            Text(
              widget.label,
              style: BrewType.mono.copyWith(
                fontSize: 11,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
                color: BrewColor.cream,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pop-up a press on Buy gets once this reader already has
/// [_MenuScreenState._maxActiveOrders] orders open.
///
/// Duplicated in spirit from [OrderWizardScreen]'s own private cap sheet
/// rather than shared, for the reason every duplicated private widget between
/// these boards gives — two files, neither owning the other's private types.
/// A sheet rather than a dead button or an inline line of text: the reader
/// just pressed Buy expecting a wizard, and what answers that press should
/// interrupt them the way the press itself did.
class _OrderCapSheet extends StatelessWidget {
  const _OrderCapSheet({required this.activeOrders});

  final int activeOrders;

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
          Text(
            'You already have $activeOrders orders open.',
            style: BrewType.displayAt(24),
          ),
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

/// A sized item's prices on the grid cell: one chip per size, in a single
/// row split evenly across the cell's width — the same equal-[Expanded]
/// device [_PriceCardGrid] uses on the wide detail dialog, sized down for a
/// cell roughly a third that width. A fixed row rather than a [Wrap]: three
/// chips that wrapped here would stack three deep and blow out the card's
/// height past its neighbour's, which [BrewGrid]'s shared-height rows would
/// then stretch that neighbour to match. [FittedBox] inside each chip is
/// what keeps three of them from overlapping instead — the label shrinks
/// before it collides with the chip beside it.
class _MenuCardPrices extends StatelessWidget {
  const _MenuCardPrices({required this.sizeLines});

  final List<(BrewItemSize, String)> sizeLines;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, (size, price)) in sizeLines.indexed) ...[
            if (index > 0) const SizedBox(width: BrewSpace.grid * 0.5),
            Expanded(child: _MenuCardPriceChip(size: size, price: price)),
          ],
        ],
      ),
    );
  }
}

/// One size's price, boxed to its own cell in [_MenuCardPrices]'s row.
/// [FittedBox] scales the label down to fit that cell exactly, so a chip
/// never grows past its share of the row and never clips or overlaps the
/// chip beside it.
class _MenuCardPriceChip extends StatelessWidget {
  const _MenuCardPriceChip({required this.size, required this.price});

  final BrewItemSize size;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: BrewSpace.grid * 4.5),
      padding: const EdgeInsets.symmetric(
        horizontal: BrewSpace.grid * 0.5,
        vertical: BrewSpace.grid,
      ),
      decoration: BoxDecoration(
        color: BrewColor.sage.withValues(alpha: 0.18),
        border: Border.all(color: BrewColor.hairline),
        borderRadius: BorderRadius.circular(BrewSpace.radius),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${size.label.characters.first.toUpperCase()} $price',
          style: BrewType.mono
              .copyWith(color: BrewColor.cream, fontSize: 13, height: 1.2),
          maxLines: 1,
        ),
      ),
    );
  }
}

/// The full-size reading of one item: its picture uncropped with a close mark
/// riding its top-right corner, then the category, the name, its sub-category
/// as a chip, a hairline rule, and what it costs — one card, centred over the
/// board, rather than a sheet climbing from the edge.
///
/// The board's own dark field carries through rather than switching to a light
/// card: cream is reserved for the one-per-screen wordmark elsewhere in this
/// app, and a white card here would be a second surface colour the palette
/// does not otherwise have. What this borrows from the reference is the
/// arrangement, not the paint.
class _MenuItemDetailDialog extends StatelessWidget {
  const _MenuItemDetailDialog({required this.item});

  final BrewMenuItem item;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sizeLines = item.sizeLines;
    final price = item.price;
    final category = item.category;
    final subCategory = item.subCategory;

    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: BrewSpace.gutter,
              vertical: math.max(media.padding.top, BrewSpace.minInset),
            ),
            child: Center(
              // Swallows the tap so only the field around the card closes it.
              child: GestureDetector(
                onTap: () {},
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xF2132218),
                      border: Border.all(
                        color: BrewColor.cream.withValues(alpha: 0.16),
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 28,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              AspectRatio(
                                aspectRatio: 16 / 11,
                                child: item.imageBytes == null
                                    ? _DetailPlaceholder(category: category)
                                    : Image.memory(
                                        item.imageBytes!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stack) =>
                                            _DetailPlaceholder(category: category),
                                      ),
                              ),
                              Positioned(
                                top: BrewSpace.grid,
                                right: BrewSpace.grid,
                                child: _CloseMark(
                                  onPressed: () => Navigator.of(context).maybePop(),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              BrewSpace.gutter,
                              BrewSpace.grid * 2.5,
                              BrewSpace.gutter,
                              BrewSpace.grid * 2.5,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (category != null) ...[
                                  Text(category.toUpperCase(), style: BrewType.mono),
                                  const SizedBox(height: BrewSpace.grid),
                                ],
                                Text(item.name, style: BrewType.displayAt(24)),
                                if (item.description case final description?) ...[
                                  const SizedBox(height: BrewSpace.grid),
                                  Text(description, style: BrewType.rowBody),
                                ],
                                if (subCategory != null &&
                                    subCategory != category) ...[
                                  const SizedBox(height: BrewSpace.grid * 1.5),
                                  _Chip(label: subCategory),
                                ],
                                if (price != null || sizeLines.isNotEmpty) ...[
                                  SizedBox(height: BrewSpace.grid * 2.5),
                                  Container(height: 1, color: BrewColor.hairline),
                                  SizedBox(height: BrewSpace.grid * 2.5),
                                  if (price != null)
                                    Text(
                                      price,
                                      style: BrewType.displayAt(20),
                                    ),
                                  if (sizeLines.isNotEmpty)
                                    _PriceCardGrid(sizeLines: sizeLines),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder({required this.category});

  final String? category;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1B3524),
            Color(0xFF0F1E14),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BrewColor.sage.withValues(alpha: 0.14),
            border: Border.all(
              color: BrewColor.sageLight.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: BrewColor.sage.withValues(alpha: 0.25),
                blurRadius: 18,
              ),
            ],
          ),
          child: Icon(
            _MenuCardImage.iconForCategory(category),
            size: 34,
            color: BrewColor.sageLight,
          ),
        ),
      ),
    );
  }
}

/// The circle-and-cross that dismisses the detail card, drawn over the photo
/// the way the reference marks its own close control.
class _CloseMark extends StatelessWidget {
  const _CloseMark({required this.onPressed});

  final VoidCallback onPressed;

  static const _dimension = 32.0;

  @override
  Widget build(BuildContext context) {
    return BrewPressable(
      onPressed: onPressed,
      onPressedChanged: (_) {},
      pressed: false,
      reduced: MediaQuery.disableAnimationsOf(context),
      radius: _dimension / 2,
      semanticsLabel: 'Close',
      child: Container(
        width: _dimension,
        height: _dimension,
        decoration: BoxDecoration(
          color: BrewColor.field.withValues(alpha: 0.72),
          shape: BoxShape.circle,
        ),
        child: CustomPaint(painter: _CrossPainter()),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BrewColor.cream
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    const half = 5.0;
    canvas
      ..drawLine(
        center.translate(-half, -half),
        center.translate(half, half),
        paint,
      )
      ..drawLine(
        center.translate(half, -half),
        center.translate(-half, half),
        paint,
      );
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => false;
}

/// One tile per size, in one evenly-split row — [BrewItemSize] only ever
/// carries three, which is exactly what fits beside each other at this
/// card's width without wrapping. Each cell is the same width and the same
/// height as its neighbours: an [IntrinsicHeight] over equal [Expanded]s, the
/// same device [BrewGrid] uses for the board's own cells, so a two-line size
/// name never leaves the tile beside it looking unfinished.
class _PriceCardGrid extends StatelessWidget {
  const _PriceCardGrid({required this.sizeLines});

  final List<(BrewItemSize, String)> sizeLines;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, (size, price)) in sizeLines.indexed) ...[
            if (index > 0) const SizedBox(width: BrewSpace.grid),
            Expanded(child: _PriceCard(size: size, price: price)),
          ],
        ],
      ),
    );
  }
}

/// One size's own card: the size name as the eyebrow, the price beneath it
/// in the same weight the card's headline price prints in, so a sized item
/// reads as three small versions of the same fact a flat-priced item states
/// once above the rule.
class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.size, required this.price});

  final BrewItemSize size;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: BrewSpace.grid,
        vertical: BrewSpace.grid * 1.5,
      ),
      decoration: BoxDecoration(
        color: BrewColor.sage.withValues(alpha: 0.18),
        border: Border.all(color: BrewColor.hairline),
        borderRadius: BorderRadius.circular(BrewSpace.radius * 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(size.label.toUpperCase(), style: BrewType.mono, maxLines: 1),
          const SizedBox(height: BrewSpace.grid),
          // Scaled down rather than clipped or wrapped: a four-figure peso
          // price is exactly the case that would otherwise run past this
          // tile's width and either overlap the tile beside it or truncate —
          // the same guard [_MenuCardPriceChip] applies on the board cell.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              price,
              style: BrewType.bodyMedium.copyWith(color: BrewColor.cream),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sub-category pill under the title — the one filing fact the card has
/// room for beyond the category eyebrow already over the photo.
class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BrewSpace.grid * 1.5,
        vertical: BrewSpace.grid,
      ),
      decoration: BoxDecoration(
        color: BrewColor.sage.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(BrewSpace.radius * 3),
      ),
      child: Text(label, style: BrewType.bodyMedium),
    );
  }
}

/// The card's photo band: a fixed-height frame so every cell in the row
/// stretches to the same picture height whether or not its product has one,
/// with the item's category set as a badge over the top-left corner the way
/// the reference board marks its featured dishes.
class _MenuCardImage extends StatelessWidget {
  const _MenuCardImage({required this.bytes, required this.category});

  final Uint8List? bytes;
  final String? category;

  static const _height = 136.0;

  static IconData iconForCategory(String? category) {
    final cat = (category ?? '').toLowerCase();
    if (cat.contains('iced') || cat.contains('blended') || cat.contains('frappe')) {
      return Icons.ac_unit_rounded;
    }
    if (cat.contains('tea') || cat.contains('refresher') || cat.contains('matcha')) {
      return Icons.emoji_food_beverage_rounded;
    }
    return Icons.local_cafe_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bytes != null)
            Image.memory(
              bytes!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => _placeholder(),
            )
          else
            _placeholder(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0x00000000),
                    const Color(0xEB132218),
                  ],
                ),
              ),
            ),
          ),
          if (category != null)
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xD90D1A12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: BrewColor.cream.withValues(alpha: 0.16),
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
                      category!.toUpperCase(),
                      style: BrewType.mono.copyWith(
                        fontSize: 9.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: BrewColor.cream,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1B3524),
            Color(0xFF0F1E14),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.8,
                colors: [
                  BrewColor.sage.withValues(alpha: 0.25),
                  const Color(0x00000000),
                ],
              ),
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BrewColor.sage.withValues(alpha: 0.14),
              border: Border.all(
                color: BrewColor.sageLight.withValues(alpha: 0.3),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: BrewColor.sage.withValues(alpha: 0.2),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Icon(
              iconForCategory(category),
              size: 24,
              color: BrewColor.sageLight,
            ),
          ),
        ],
      ),
    );
  }
}
