import 'dart:math' as math;

import 'package:flutter/material.dart' show Material, showModalBottomSheet;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../brew_admin.dart';
import '../../brew_counter.dart';
import '../../brew_menu_seed.dart';
import '../../theme/brew_type.dart';
import '../../theme/tokens.dart';
import '../../widgets/brew_background.dart';
import '../../widgets/brew_buttons.dart';
import '../../widgets/brew_choice.dart';
import '../../widgets/brew_field.dart';
import '../../widgets/brew_filter_row.dart';
import '../../widgets/brew_grid.dart';
import '../../widgets/brew_reveal.dart';
import '../../widgets/brew_sheet.dart';
import '../../widgets/menu_item_image.dart';
import '../../widgets/stagger.dart';
import 'admin_transitions.dart';

/// One store's board, admin side: add, edit and delete a product — the write
/// half of [MenuScreen](../menu_screen.dart), which only ever reads.
///
/// Reached from [StoreConfigScreen](store_config_screen.dart)'s "Manage
/// products" button, so — like that screen — it never has to ask which store
/// it is configuring or whether the signed-in account may.
class AdminMenuScreen extends StatefulWidget {
  const AdminMenuScreen({
    super.key,
    required this.partner,
    this.admin,
    this.counter,
  });

  final BrewPartner partner;

  /// Null if Firestore is unreachable. The board still renders; none of it
  /// can save.
  final BrewAdmin? admin;
  final BrewCounter? counter;

  static Route<void> route({
    bool reduced = false,
    required BrewPartner partner,
    BrewAdmin? admin,
    BrewCounter? counter,
  }) {
    return adminPageRoute<void>(
      reduced: reduced,
      builder: (context) =>
          AdminMenuScreen(partner: partner, admin: admin, counter: counter),
    );
  }

  @override
  State<AdminMenuScreen> createState() => _AdminMenuScreenState();
}

class _AdminMenuScreenState extends State<AdminMenuScreen> {
  Stream<List<BrewMenuItem>>? _menu;

  String? _menuError;

  /// Which category the board below is showing. [_allCategories] is the
  /// unfiltered board, and is what this holds until an admin narrows it.
  ///
  /// Held as the category's own name rather than as an index, so a chip that
  /// disappears — the last item in a category deleted, or an import replacing
  /// the whole list — leaves this pointing at a category that no longer
  /// exists, which [_visible] reads as "show everything" rather than as an
  /// index into a list that has since got shorter.
  String _category = _allCategories;
  String _subCategory = _allCategories;

  /// The chip that clears the filter. Not a category any item can hold — an
  /// admin typing "All" into the category field would collide with it, which
  /// is a real if unlikely edge, so it is spelled with a leading space that
  /// [BrewAdmin._tidy] trims off anything stored.
  static const _allCategories = ' All';

  /// What the search field holds, lower-cased once here rather than on every
  /// item compared against it in [_visible].
  final _search = TextEditingController();
  String _query = '';

  /// Which page of the filtered board is showing, zero-based. Reset to the
  /// first page whenever the filter or search narrows the board to a
  /// different set of items — see [_visible] — so a page number left over
  /// from a longer list never strands the admin past the end of a shorter one.
  int _page = 0;

  static const _pageSize = 10;

  bool _importing = false;

  /// The board the last snapshot carried, for the item sheet to offer as
  /// category and sub-category picks.
  ///
  /// Assigned from inside the stream builder rather than set with setState:
  /// that is already a rebuild caused by the snapshot, and calling setState
  /// there would schedule a second one for a value nothing on this screen
  /// draws directly — the same note [AdminHomeScreen] makes about the shop
  /// list it keeps for the Team screens.
  List<BrewMenuItem> _knownItems = const [];

  @override
  void initState() {
    super.initState();
    _menu = widget.counter?.menu(widget.partner);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Replaces this shop's board with the bundled Seven Coffee & Tea list.
  ///
  /// Confirmed first, and the confirmation names the count rather than asking
  /// a vague "are you sure": this wipes every product the shop currently has,
  /// including any an admin typed by hand, and that is not a consequence to
  /// leave a reader to infer from the word "import".
  Future<void> _importSeed() async {
    final admin = widget.admin;
    if (admin == null) return;

    final List<BrewSeedItem> seed;
    try {
      seed = await BrewMenuSeed.load();
    } catch (error) {
      debugPrint('QuickBrew → could not read the bundled menu: $error');
      if (!mounted) return;
      setState(() => _menuError = 'Could not read the bundled menu.');
      return;
    }
    if (!mounted) return;

    // `this.context` rather than one passed in from the builder: the guard
    // above is a check on *this State*, and that is only a valid guard for
    // the State's own context.
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: BrewColor.field,
      builder: (context) => _ConfirmImportSheet(count: seed.length),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _importing = true;
      _menuError = null;
    });
    final failure = await admin.importMenu(widget.partner, seed);
    if (!mounted) return;
    setState(() {
      _importing = false;
      _menuError = failure;
      // The filter is scoped to a board that has just been replaced wholesale,
      // so it goes back to showing everything rather than to a category the
      // new list may not have.
      _category = _allCategories;
      _subCategory = _allCategories;
    });
  }

  Future<void> _addItem(BuildContext context) => _editSheet(context);

  Future<void> _editSheet(BuildContext context, {BrewMenuItem? existing}) async {
    final draft = await showModalBottomSheet<_MenuItemDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrewColor.field,
      builder: (context) => _MenuItemSheet(
        existing: existing,
        // Read off the last snapshot rather than the live stream: the sheet
        // is a form the admin is filling in, and a category list that
        // reshuffled underneath them because another device saved something
        // would move the buttons under their thumb.
        items: _knownItems,
      ),
    );
    final admin = widget.admin;
    // Null is the sheet being dismissed rather than saved, which is not a
    // failure and should say nothing.
    if (draft == null || admin == null || !mounted) return;

    setState(() => _menuError = null);
    final failure = existing == null
        ? await admin.addMenuItem(
            widget.partner,
            name: draft.name,
            description: draft.description,
            category: draft.category,
            subCategory: draft.subCategory,
            sizePrices: draft.sizePrices,
            priceCents: draft.priceCents,
            sort: draft.sort,
            image: draft.image,
          )
        : await admin.updateMenuItem(
            widget.partner,
            existing.id,
            name: draft.name,
            description: draft.description,
            category: draft.category,
            subCategory: draft.subCategory,
            sizePrices: draft.sizePrices,
            priceCents: draft.priceCents,
            sort: draft.sort,
            image: draft.image,
          );

    if (!mounted) return;
    setState(() => _menuError = failure);
  }

  Future<void> _deleteItem(BrewMenuItem item) async {
    final admin = widget.admin;
    if (admin == null) return;

    setState(() => _menuError = null);
    final failure = await admin.deleteMenuItem(widget.partner, item.id);
    if (!mounted) return;
    setState(() => _menuError = failure);
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
          child: BrewSheet(
            staggerCount: 4,
          children: [
            StaggerItem(index: 0, child: _header(context)),
            SizedBox(height: brewBlockGap(compact)),
            StaggerItem(
              index: 1,
              child: Text(
                widget.partner.name,
                style: BrewType.displayAt(compact ? 28 : 34),
              ),
            ),
            const SizedBox(height: BrewSpace.grid),
            StaggerItem(
              index: 2,
              child: Text(
                'Add, edit or remove what this shop sells.',
                style: BrewType.rowBody,
              ),
            ),
            SizedBox(height: brewBlockGap(compact)),
            StaggerItem(index: 3, child: _board(context)),
          ],
        ),
      ),
    ),
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

  /// The items the filter currently admits, out of the whole board.
  ///
  /// A selection naming a category that is no longer on the board shows
  /// everything rather than nothing — see [_category] for why that is the
  /// right reading rather than an empty screen an admin cannot get out of.
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

  Widget _board(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionLabel('The board')),
            BrewMonoButton(
              label: 'Add product',
              onPressed: widget.admin == null ? null : () => _addItem(context),
            ),
          ],
        ),
        BrewReveal(
          gap: BrewSpace.grid,
          child: switch (_menuError) {
            final message? => Semantics(
              liveRegion: true,
              child: Text(message, style: BrewType.fieldError),
            ),
            null => null,
          },
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        BrewField(
          label: 'Search',
          controller: _search,
          hint: 'Find a product by name or description',
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        StreamBuilder<List<BrewMenuItem>>(
          stream: _menu,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <BrewMenuItem>[];
            if (items.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nothing on the board yet.', style: BrewType.rowBody),
                  const SizedBox(height: BrewSpace.grid * 2),
                  _importRow(),
                ],
              );
            }

            final categories = BrewMenuItem.categoriesOf(items);
            _knownItems = items;
            final subCategories = _category == _allCategories
                ? const <String>[]
                : BrewMenuItem.subCategoriesOf(items, _category);
            final visible = _visible(items);

            // Clamped rather than reset in a setState here: a snapshot arriving
            // mid-build is not the admin's own action, and calling setState
            // from inside this builder would schedule a second, needless
            // rebuild for a value only this frame's slice below actually reads.
            final pageCount = (visible.length / _pageSize).ceil();
            final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
            final pageStart = page * _pageSize;
            final pageItems = visible.skip(pageStart).take(_pageSize).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Only drawn once there is more than one category to choose
                // between: a filter row over a board that is entirely one
                // category is a control whose every setting shows the same
                // thing.
                if (categories.length > 1) ...[
                  BrewFilterRow.bled(
                    context,
                    options: [_allCategories, ...categories],
                    selected: _category,
                    onSelected: (value) => setState(() {
                      _category = value;
                      // The sub-filter belonged to the old category, so it
                      // cannot survive the change.
                      _subCategory = _allCategories;
                      _page = 0;
                    }),
                  ),
                  const SizedBox(height: BrewSpace.grid),
                ],
                if (subCategories.isNotEmpty) ...[
                  BrewFilterRow.bled(
                    context,
                    options: [_allCategories, ...subCategories],
                    selected: _subCategory,
                    onSelected: (value) => setState(() {
                      _subCategory = value;
                      _page = 0;
                    }),
                  ),
                  const SizedBox(height: BrewSpace.grid),
                ],
                Text(
                  visible.length == items.length
                      ? '${items.length} on the board'
                      : '${visible.length} of ${items.length}',
                  style: BrewType.mono,
                ),
                const SizedBox(height: BrewSpace.grid * 1.5),
                if (visible.isEmpty)
                  Text('No products match that search.', style: BrewType.rowBody)
                else
                  BrewGrid(
                    children: [
                      for (final item in pageItems)
                        _MenuItemRow(
                          item: item,
                          onEdit: widget.admin == null
                              ? null
                              : () => _editSheet(context, existing: item),
                          onDelete: widget.admin == null
                              ? null
                              : () => _deleteItem(item),
                        ),
                    ],
                  ),
                if (pageCount > 1) ...[
                  const SizedBox(height: BrewSpace.grid * 2),
                  _PageRow(
                    page: page,
                    pageCount: pageCount,
                    onPrevious: page > 0
                        ? () => setState(() => _page = page - 1)
                        : null,
                    onNext: page < pageCount - 1
                        ? () => setState(() => _page = page + 1)
                        : null,
                  ),
                ],
                const SizedBox(height: BrewSpace.grid * 3),
                _importRow(),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The bundled-list import, kept at the foot of the board rather than up
  /// beside Add product: it replaces everything above it, and a destructive
  /// action sitting next to the ordinary one is a mis-tap waiting to happen.
  Widget _importRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Replace this board with the Seven Coffee & Tea list.',
            style: BrewType.rowBody,
          ),
        ),
        const SizedBox(width: BrewSpace.grid),
        BrewMonoButton(
          label: _importing ? 'Importing' : 'Import',
          semanticsLabel: 'Import the Seven Coffee and Tea menu',
          onPressed:
              (_importing || widget.admin == null) ? null : _importSeed,
        ),
      ],
    );
  }
}

/// A section's name, in the mono label voice.
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

/// The board's pager: Previous and Next either side of "Page X of Y", shown
/// only once a board — or what a filter or search has narrowed it to — runs
/// past one page. Ten items a page rather than a single long list, so a board
/// of a hundred-odd products never asks a phone to lay out and scroll past
/// all of them at once.
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

/// The one question the import has to ask before it wipes a board.
///
/// A sheet rather than an [AlertDialog] for the reason the item editor is one
/// too: this app draws its own chrome, and a Material dialog would arrive with
/// a different radius, a different fill and a different pair of buttons from
/// everything around it.
class _ConfirmImportSheet extends StatelessWidget {
  const _ConfirmImportSheet({required this.count});

  final int count;

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
          Text('Replace the board?', style: BrewType.displayAt(24)),
          const SizedBox(height: BrewSpace.grid * 2),
          Text(
            'This removes every product on this board and puts $count in '
            'their place. Anything typed by hand goes with it.',
            style: BrewType.rowBody,
          ),
          const SizedBox(height: BrewSpace.grid * 4),
          BrewPrimaryButton(
            label: 'Replace with $count products',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: BrewSpace.grid),
          BrewTextButton(
            label: 'Keep what is there',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

/// One item on the board, with the two things an admin can do to it.
///
/// Cards the same photo-forward shape as the customer menu's — see
/// [MenuScreen]'s `_MenuRow` — so an admin previews a product the way a
/// customer will actually see it, with Edit and Delete appended below as the
/// one difference between the two boards.
class _MenuItemRow extends StatelessWidget {
  const _MenuItemRow({required this.item, this.onEdit, this.onDelete});

  final BrewMenuItem item;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// The one line naming where this item sits, or null when there is nothing
  /// left to say that the filter row is not already saying.
  ///
  /// The sub-category wins when there is one, because it is the more specific
  /// fact and a cell this narrow fits exactly one of them: "ICED BLENDED ·
  /// FRAPPE SERIES" truncates to "ICED BLENDED ·…", which spends the whole
  /// line on the half the reader could already see on the lit chip and elides
  /// the half they could not.
  String? get filing {
    final category = item.category;
    if (category == null) return 'Uncategorised';
    return item.subCategory ?? category;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: BrewColor.hairline),
        borderRadius: BorderRadius.circular(BrewSpace.radius * 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MenuCardImage(bytes: item.imageBytes, category: filing),
          Padding(
            padding: const EdgeInsets.all(BrewSpace.grid * 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: BrewType.rowTitle),
                if (item.description case final description?) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: BrewType.rowBody,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: BrewSpace.grid),
                if (item.price case final price?)
                  Text(price, style: BrewType.bodyMedium),
                // One boxed chip per size, wrapped rather than run onto a
                // line this narrow a cell cannot spare — "M ₱80 · L ₱90" runs
                // past the edge once the peso figure gets a second digit, and
                // an ellipsis there loses the admin the exact figure they
                // opened this board to check. See [MenuScreen]'s matching
                // `_MenuCardPriceChip`, which this mirrors so the two boards
                // read as one system.
                if (item.sizeLines.isNotEmpty)
                  _MenuCardPrices(sizeLines: item.sizeLines),
                const SizedBox(height: BrewSpace.grid * 1.5),
                Row(
                  children: [
                    BrewMonoButton(label: 'Edit', onPressed: onEdit),
                    const SizedBox(width: BrewSpace.grid * 2),
                    BrewMonoButton(label: 'Delete', onPressed: onDelete),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A sized item's prices on the board cell: one chip per size, wrapped rather
/// than forced onto a line the cell is not wide enough for.
///
/// Duplicated from [MenuScreen]'s identical private widget rather than
/// shared, for the reason `_MenuCardImage` below already duplicates that
/// screen's — two files, neither owning the other's private types.
/// A fixed row split evenly across the cell's width rather than a [Wrap]:
/// three chips that wrapped here would stack three deep and blow out the
/// card's height past its neighbour's, which [BrewGrid]'s shared-height rows
/// would then stretch that neighbour to match.
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
      // Scales up to this larger chip's own room and back down again if a
      // third size or a wider text scale would otherwise crowd the chip
      // beside it — the one rule that keeps "bigger" from meaning "overlapping".
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

/// The card's photo band: a fixed-height frame so every cell in the row
/// stretches to the same picture height whether or not its product has one,
/// with where the item is filed set as a badge over the top-left corner —
/// the same treatment [MenuScreen]'s card gives its category.
class _MenuCardImage extends StatelessWidget {
  const _MenuCardImage({required this.bytes, required this.category});

  final Uint8List? bytes;
  final String? category;

  static const _height = 120.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: _height,
          width: double.infinity,
          child: bytes == null
              ? ColoredBox(color: BrewColor.sage.withValues(alpha: 0.35))
              : Image.memory(
                  bytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      ColoredBox(color: BrewColor.sage.withValues(alpha: 0.35)),
                ),
        ),
        if (category != null)
          Positioned(
            left: BrewSpace.grid,
            top: BrewSpace.grid,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: BrewSpace.grid,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: BrewColor.field.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(BrewSpace.radius),
              ),
              child: Text(
                category!.toUpperCase(),
                style: BrewType.mono.copyWith(color: BrewColor.cream),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}

/// The item picture as a control: the 56px frame itself takes the tap.
///
/// Built on [BrewPressable] rather than a bare [GestureDetector] so it presses,
/// focuses and announces exactly like the buttons around it — the note on that
/// widget makes the same argument for the home screen's shop cards, which are
/// also controls the size of a block rather than of a label.
class _PictureTarget extends StatefulWidget {
  const _PictureTarget({
    required this.child,
    required this.onPressed,
    required this.semanticsLabel,
  });

  final Widget child;
  final VoidCallback onPressed;
  final String semanticsLabel;

  @override
  State<_PictureTarget> createState() => _PictureTargetState();
}

class _PictureTargetState extends State<_PictureTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return BrewPressable(
      onPressed: widget.onPressed,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      pressed: _pressed,
      reduced: MediaQuery.disableAnimationsOf(context),
      semanticsLabel: widget.semanticsLabel,
      child: widget.child,
    );
  }
}

/// What a saved item sheet resolves to. Parsed here rather than in
/// [BrewAdmin], because "0.00" and "" are shapes a form produces, not shapes
/// the write layer should have to make sense of.
class _MenuItemDraft {
  const _MenuItemDraft({
    required this.name,
    this.description,
    this.category,
    this.subCategory,
    this.sizePrices = const {},
    this.priceCents,
    this.sort,
    this.image,
  });

  final String name;
  final String? description;
  final String? category;
  final String? subCategory;
  final Map<BrewItemSize, int> sizePrices;
  final int? priceCents;
  final double? sort;
  final Uint8List? image;
}

/// Add or edit one item, as a sheet rather than a screen: the board is a
/// list an admin adjusts a row at a time, and a full-screen push for that
/// would outrank the board itself.
class _MenuItemSheet extends StatefulWidget {
  const _MenuItemSheet({this.existing, this.items = const []});

  final BrewMenuItem? existing;

  /// The board this item belongs to, for the category and sub-category
  /// pickers to offer what already exists.
  ///
  /// Picked from a grid rather than typed free: "Milktea" typed afresh as
  /// "Milk tea" would split one section of the board into two chips that
  /// look identical to nobody reading carefully. A picker still needs a way
  /// to add to it — a new product is often the first of a new category — so
  /// both grids carry an "Add new" tile alongside what is already here.
  final List<BrewMenuItem> items;

  @override
  State<_MenuItemSheet> createState() => _MenuItemSheetState();
}

class _MenuItemSheetState extends State<_MenuItemSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');

  /// The category and sub-category picks, held as plain strings rather than
  /// controllers: both are now chosen off a grid, not typed, so there is no
  /// cursor or selection state a controller would need to carry.
  String? _category;
  String? _subCategory;

  /// The "Add new" tile's own field, one for each grid. Only visible once
  /// that tile is picked — see [_CategoryGrid] — and read back into
  /// [_category] or [_subCategory] on save rather than as the admin types,
  /// so a category typed and abandoned mid-word never briefly overwrites a
  /// pick already made.
  final _newCategory = TextEditingController();
  final _newSubCategory = TextEditingController();

  bool _addingCategory = false;
  bool _addingSubCategory = false;

  late final _price = TextEditingController(
    text: switch (widget.existing?.priceCents) {
      final cents? => (cents / 100).toStringAsFixed(2),
      null => '',
    },
  );

  /// One price field per size, built once so a size toggled on and back off
  /// does not lose what was typed into it. Unused entries just never leave
  /// the map on save — see [_save].
  final Map<BrewItemSize, TextEditingController> _sizePrice = {
    for (final size in BrewItemSize.values) size: TextEditingController(),
  };

  /// Which sizes this product is priced by. Empty means the flat [_price]
  /// field above is the one in play — see the doc on [BrewMenuItem.sizePrices]
  /// for why the two never both apply.
  late final Set<BrewItemSize> _sizes = {
    ...?widget.existing?.sizePrices.keys,
  };

  /// Carried forward from the item being edited, then replaced or cleared in
  /// place — the same "prime once, edit locally" shape the text fields use,
  /// except there is no controller for either to hold it in.
  Uint8List? _image;

  String? _nameError;
  String? _imageError;

  @override
  void initState() {
    super.initState();
    _image = widget.existing?.imageBytes;
    _category = widget.existing?.category;
    _subCategory = widget.existing?.subCategory;
    widget.existing?.sizePrices.forEach((size, cents) {
      _sizePrice[size]!.text = (cents / 100).toStringAsFixed(2);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _newCategory.dispose();
    _newSubCategory.dispose();
    _price.dispose();
    for (final controller in _sizePrice.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _toggleSize(BrewItemSize size) {
    setState(() {
      if (!_sizes.remove(size)) _sizes.add(size);
    });
  }

  /// Every category already on this board, in board order.
  List<String> get _categoryOptions => BrewMenuItem.categoriesOf(widget.items);

  /// The sub-categories filed under the chosen category. Empty — and so is
  /// the grid it feeds — until a category is picked, since a sub-category
  /// with no category above it is not a place on the board; [_save] drops
  /// one that somehow survives to here for the same reason.
  List<String> get _subCategoryOptions {
    final category = _category;
    if (category == null) return const [];
    return BrewMenuItem.subCategoriesOf(widget.items, category);
  }

  void _pickCategory(String value) {
    setState(() {
      _category = value;
      _addingCategory = false;
      // The sub-category belonged to the old category, so it cannot survive
      // the change — the same rule the board's own filter row follows.
      _subCategory = null;
      _addingSubCategory = false;
      _newSubCategory.clear();
    });
  }

  void _addCategory() {
    final value = _newCategory.text.trim();
    if (value.isEmpty) return;
    _newCategory.clear();
    _pickCategory(value);
  }

  void _pickSubCategory(String value) {
    setState(() {
      _subCategory = value;
      _addingSubCategory = false;
    });
  }

  void _addSubCategory() {
    final value = _newSubCategory.text.trim();
    if (value.isEmpty) return;
    _newSubCategory.clear();
    _pickSubCategory(value);
  }

  /// Picks and downscales an image the way
  /// [_StoreConfigScreenState._pickLogo](store_config_screen.dart) does for
  /// the shop's own logo, kept in memory here rather than written anywhere
  /// until Save is pressed — a picked item picture that is thrown away by
  /// backing out of the sheet should cost Firestore nothing.
  ///
  /// 160 square rather than the 640 this used to ask for. Every surface that
  /// draws an item picture does it at 56px or less (this sheet, the board row
  /// at 40, the customer menu at 56), so the extra pixels were never visible
  /// — but they were stored, because [BrewAdmin] keeps the picture inline in
  /// the item's own document as base64. The whole board streams on every
  /// snapshot, so at 640 a fully-photographed 116-item menu is tens of
  /// megabytes decoded on the main thread each time anything changes. 160 at
  /// quality 75 lands in the single-digit KB and looks identical at 56px.
  Future<void> _pickImage() async {
    setState(() => _imageError = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 160,
        maxHeight: 160,
        imageQuality: 75,
      );
      // Null means they backed out of the picker, which is not a failure and
      // should say nothing.
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _image = bytes);
    } catch (error) {
      debugPrint('QuickBrew → item image pick failed: $error');
      if (!mounted) return;
      setState(() => _imageError = 'Could not read that image. Try another.');
    }
  }

  void _removeImage() => setState(() => _image = null);

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name the product.');
      return;
    }

    final description = _description.text.trim();
    // A category or sub-category typed into the "Add new" tile but never
    // confirmed there is still what the admin meant to save — Save is the
    // one action on this sheet that reads as "I am done", so it commits
    // whatever is sitting in an open Add field rather than discarding it.
    final category = (_addingCategory ? _newCategory.text : (_category ?? '')).trim();
    final subCategory =
        (_addingSubCategory ? _newSubCategory.text : (_subCategory ?? '')).trim();
    // `isFinite`, not just non-null: tryParse happily returns Infinity for
    // "1e999" or a few hundred pasted digits, and (Infinity * 100).round()
    // throws UnsupportedError out of a gesture callback — an uncaught exception
    // with the sheet still open and nothing said.
    double? finite(String text) {
      final parsed = double.tryParse(text.trim());
      return (parsed != null && parsed.isFinite) ? parsed : null;
    }

    final sizePrices = <BrewItemSize, int>{};
    for (final size in _sizes) {
      final price = finite(_sizePrice[size]!.text);
      if (price != null) sizePrices[size] = (price * 100).round();
    }

    final flatPrice = sizePrices.isEmpty ? finite(_price.text) : null;

    Navigator.of(context).pop(
      _MenuItemDraft(
        name: name,
        description: description.isEmpty ? null : description,
        category: category.isEmpty ? null : category,
        // A sub-category with no category above it is not a place on the
        // board — [BrewMenuItem.subCategory] says as much — so it is dropped
        // rather than stored as an orphan the filters could never reach.
        subCategory:
            (category.isEmpty || subCategory.isEmpty) ? null : subCategory,
        sizePrices: sizePrices,
        priceCents: flatPrice == null ? null : (flatPrice * 100).round(),
        // No field on this sheet changes it — see the doc on
        // [BrewMenuItem.sort] via [BrewCounter.byBoardOrder] for how an item
        // with no position sorts.
        sort: widget.existing?.sort,
        image: _image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return SingleChildScrollView(
      // The sheet's own scroll: `isScrollControlled` only lets the sheet grow
      // past the default half-screen cap, it does not make the content
      // inside scroll. Without this, a form this long — picture row, six
      // fields, size choices, price fields — overflows the moment the
      // keyboard's inset eats into the space it had, rather than letting the
      // reader scroll the rest of it into view.
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        // The same floor every other screen's header clears the status bar
        // and notch by — see [MenuScreen]'s header padding for the same sum.
        // A flat 24px here was fine while the sheet stayed short of the top
        // of the screen; a full-length form reaches it, and 24px alone sits
        // the title under the status bar rather than clear of it.
        top: math.max(media.padding.top, BrewSpace.minInset) +
            BrewSpace.headerClearance,
        bottom: media.viewInsets.bottom + BrewSpace.grid * 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.existing == null ? 'Add a product.' : 'Edit product.',
                  style: BrewType.displayAt(24),
                ),
              ),
              BrewMonoButton(
                label: 'Back',
                semanticsLabel: 'Close without saving',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The frame is the upload control, not just a preview. With no
              // picture yet the mono button beside it is a 10px sage label
              // sitting under an identically-styled caption, which does not
              // read as something to press — so the 56px square takes the tap
              // too, and is the whole target in the state that needs one most.
              _PictureTarget(
                onPressed: _pickImage,
                semanticsLabel: _image != null
                    ? 'Replace the product picture'
                    : 'Upload a product picture',
                child: BrewMenuItemImage(
                  bytes: _image,
                  dimension: 56,
                  placeholder: true,
                ),
              ),
              const SizedBox(width: BrewSpace.iconGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _image != null ? 'PICTURE' : 'NO PICTURE',
                      style: BrewType.mono,
                    ),
                    const SizedBox(height: BrewSpace.grid),
                    Row(
                      children: [
                        BrewMonoButton(
                          label: _image != null ? 'Replace' : 'Upload',
                          semanticsLabel: _image != null
                              ? 'Replace the product picture'
                              : 'Upload a product picture',
                          onPressed: _pickImage,
                        ),
                        // Only a product with a picture has one to remove, so
                        // this comes and goes with the upload — see the same
                        // control on the shop's own logo in Store Config.
                        BrewReveal(
                          axis: Axis.horizontal,
                          gap: BrewSpace.grid * 3,
                          child: _image != null
                              ? BrewMonoButton(
                                  label: 'Remove',
                                  semanticsLabel: 'Remove the product picture',
                                  onPressed: _removeImage,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          BrewReveal(
            gap: BrewSpace.grid,
            child: switch (_imageError) {
              final message? => Semantics(
                liveRegion: true,
                child: Text(message, style: BrewType.fieldError),
              ),
              null => null,
            },
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          BrewField(
            label: 'Name',
            controller: _name,
            hint: 'Iced Latte',
            errorText: _nameError,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          BrewField(
            label: 'Description',
            controller: _description,
            hint: 'Optional',
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          _CategoryGrid(
            label: 'Category',
            noun: 'category',
            options: _categoryOptions,
            selected: _category,
            adding: _addingCategory,
            newController: _newCategory,
            onSelected: _pickCategory,
            onAddTapped: () => setState(() => _addingCategory = true),
            onAddSubmitted: _addCategory,
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          // Only once a category is chosen: a sub-category with no category
          // above it is not a place on the board — see [_subCategoryOptions].
          if (_category != null) ...[
            _CategoryGrid(
              label: 'Sub-category (optional)',
              noun: 'sub-category',
              options: _subCategoryOptions,
              selected: _subCategory,
              adding: _addingSubCategory,
              newController: _newSubCategory,
              onSelected: _pickSubCategory,
              onAddTapped: () => setState(() => _addingSubCategory = true),
              onAddSubmitted: _addSubCategory,
            ),
            const SizedBox(height: BrewSpace.grid * 3),
          ],
          // "Optional" carried in the label rather than a sentence under the
          // row: the choices themselves already read as a set of sizes, so the
          // only thing left to say is that skipping them is allowed.
          Text('Size (optional)'.toUpperCase(), style: BrewType.mono),
          const SizedBox(height: BrewSpace.grid),
          Row(
            children: [
              for (final (index, size) in BrewItemSize.values.indexed) ...[
                if (index > 0) const SizedBox(width: BrewSpace.grid * 1.5),
                Expanded(
                  child: BrewChoice(
                    label: size.label,
                    selected: _sizes.contains(size),
                    // Each size toggles on its own — a product can come in
                    // several, unlike the single choice this control makes
                    // elsewhere (the store or role picker), so tapping one
                    // never clears another.
                    onSelected: () => _toggleSize(size),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          // A size in play prices this product per size, so the one flat
          // price below would have nothing left to mean — [_save] drops it
          // whenever a size is chosen, and the field hides in step with that.
          if (_sizes.isEmpty)
            BrewField(
              label: 'Price',
              controller: _price,
              hint: '0.00',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            )
          else
            for (final size in BrewItemSize.values)
              if (_sizes.contains(size))
                Padding(
                  padding: const EdgeInsets.only(bottom: BrewSpace.grid * 3),
                  child: BrewField(
                    label: '${size.label} price',
                    controller: _sizePrice[size]!,
                    hint: '0.00',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                  ),
                ),
          const SizedBox(height: BrewSpace.grid * 4),
          BrewPrimaryButton(label: 'Save', onPressed: _save),
        ],
      ),
    );
  }
}

/// A category or sub-category, picked off a 2-column grid of what the board
/// already uses rather than typed free — see [_MenuItemSheet.items] for why
/// a picker still needs its own way to add to the set it offers.
///
/// One "Add new" tile is appended to the grid. Picked, it swaps itself for a
/// field and a Confirm button, in place, rather than opening a second sheet —
/// this is already a sheet an admin is two taps from cancelling out of
/// entirely, and a picker that pushed another one on top of it to add one
/// word would outrank the form it belongs to.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.label,
    required this.noun,
    required this.options,
    required this.selected,
    required this.adding,
    required this.newController,
    required this.onSelected,
    required this.onAddTapped,
    required this.onAddSubmitted,
  });

  final String label;

  /// What this grid is offering, in sentence case with no "(optional)" —
  /// [label] is the on-screen heading, this is what the trailing Add
  /// button's own announcement names.
  final String noun;

  final List<String> options;
  final String? selected;
  final bool adding;
  final TextEditingController newController;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddTapped;
  final VoidCallback onAddSubmitted;

  @override
  Widget build(BuildContext context) {
    // A category just typed into the Add tile and confirmed is the pick
    // before it is anything Firestore has ever seen — [options] only knows
    // what is already on the board, so the freshly-added value would have no
    // tile to render as selected without being appended here.
    final selected = this.selected;
    final allOptions = [
      ...options,
      if (selected != null && !options.contains(selected)) selected,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        BrewGrid(
          children: [
            for (final option in allOptions)
              BrewChoice(
                label: option,
                selected: option == selected,
                onSelected: () => onSelected(option),
              ),
            if (adding)
              BrewField(
                label: 'New',
                controller: newController,
                hint: noun == 'sub-category' ? 'Frappe Series' : 'Iced Coffee',
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAddSubmitted(),
                trailing: BrewMonoButton(
                  label: 'Add',
                  semanticsLabel: 'Add this $noun',
                  onPressed: onAddSubmitted,
                ),
              )
            else
              BrewChoice(
                label: '+ Add new',
                selected: false,
                onSelected: onAddTapped,
              ),
          ],
        ),
      ],
    );
  }
}
