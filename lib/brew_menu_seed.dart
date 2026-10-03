import 'package:flutter/services.dart' show rootBundle;

import 'brew_counter.dart';

/// One row of the bundled price list, already parsed into the shape
/// [BrewAdmin.importMenu] writes.
///
/// Deliberately not a [BrewMenuItem]: that type carries a Firestore document
/// id and this has never been to Firestore. It is the *contents* of an item,
/// which is what an import has before the write and what the write turns into
/// a document.
class BrewSeedItem {
  const BrewSeedItem({
    required this.name,
    required this.category,
    this.subCategory,
    this.description,
    this.sizePrices = const {},
    this.priceCents,
    required this.sort,
  });

  final String name;
  final String category;
  final String? subCategory;
  final String? description;
  final Map<BrewItemSize, int> sizePrices;
  final int? priceCents;

  /// Position on the board, handed out in file order — see
  /// [BrewMenuSeed.parse] for why the source order is the right order.
  final double sort;
}

/// One add-on of the bundled list, in the shape [BrewAdmin.importAddOns]
/// writes. The same relationship to [BrewAddOn] that [BrewSeedItem] has to
/// [BrewMenuItem]: contents that have never been to Firestore, and so carry no
/// document id.
class BrewSeedAddOn {
  const BrewSeedAddOn({
    required this.name,
    required this.priceCents,
    required this.group,
    required this.sort,
  });

  final String name;
  final int priceCents;
  final String group;
  final double sort;
}

/// Seven Coffee & Tea's add-ons board, as the shop prints it.
///
/// In code rather than in a CSV beside the menu, because unlike the 116-drink
/// board this is twenty lines that were never transcribed from a spreadsheet —
/// and a second asset file to parse for twenty rows is a parser to maintain
/// for no reader's benefit. It is still only a *seed*: once imported these are
/// ordinary documents in that shop's `addons` collection, and the shop can
/// rename, reprice or delete any of them without touching this list. The other
/// partner never sees them unless an admin imports them there too.
///
/// The price sits on each option rather than on its group because the board
/// itself prices two of them out of step with their heading: Coffee jelly and
/// Popping boba are ₱15 under a SINKERS heading that says ₱10. A group-level
/// price would have to either overcharge for pearls or undercharge for boba,
/// and both are the app lying about a number the reader can read off the wall.
abstract final class BrewAddOnSeed {
  /// Every add-on the shop's board lists, in board order — Coffee, Drizzle,
  /// Syrup, Sinkers down the left, Toppings and Milk choice down the right.
  /// File order becomes [BrewSeedAddOn.sort], the same bargain the menu
  /// seed strikes.
  static List<BrewSeedAddOn> get all {
    const rows = <(String, int, String)>[
      // COFFEE — ₱10
      ('Espresso shot', 1000, 'Coffee'),

      // DRIZZLE — ₱10
      ('Chocolate drizzle', 1000, 'Drizzle'),
      ('Caramel drizzle', 1000, 'Drizzle'),
      ('Strawberry drizzle', 1000, 'Drizzle'),

      // SYRUP — ₱10
      ('Flavored syrup', 1000, 'Syrup'),

      // SINKERS — ₱10, except the last two, which the board prices at ₱15.
      ('Pearls', 1000, 'Sinkers'),
      ('Nata', 1000, 'Sinkers'),
      ('Crushed Oreo', 1000, 'Sinkers'),
      ('Coffee jelly', 1500, 'Sinkers'),
      ('Popping boba SB', 1500, 'Sinkers'),

      // TOPPINGS — ₱15
      ('Cream cheese', 1500, 'Toppings'),
      ('Cheesecake', 1500, 'Toppings'),
      ('Whipping cream', 1500, 'Toppings'),
      ('Salty cream', 1500, 'Toppings'),
      ('Sea salt cream', 1500, 'Toppings'),
      ('Fresh jam — Strawberry', 1500, 'Toppings'),
      ('Fresh jam — Blueberry', 1500, 'Toppings'),

      // MILK CHOICE — ₱40
      ('Oat milk', 4000, 'Milk choice'),
    ];

    return [
      for (final (index, (name, priceCents, group)) in rows.indexed)
        BrewSeedAddOn(
          name: name,
          priceCents: priceCents,
          group: group,
          sort: index.toDouble(),
        ),
    ];
  }
}

/// The Seven Coffee & Tea board, read out of the CSV bundled at
/// `assets/menu/seven_coffee_and_tea.csv`.
///
/// The file is the transcription of two physical menu boards, so it is the
/// authority on what the shop sells and in what order — an import that
/// re-sorted it alphabetically would scatter the Frappe Series through the
/// Milkteas and produce a board no customer standing in that shop would
/// recognise. File order becomes [BrewSeedItem.sort].
abstract final class BrewMenuSeed {
  static const asset = 'assets/menu/seven_coffee_and_tea.csv';

  /// Every priced row in the bundled list, in board order.
  static Future<List<BrewSeedItem>> load() async {
    return parse(await rootBundle.loadString(asset));
  }

  /// The parse, split out from the load so it can be exercised without a
  /// bundle behind it.
  ///
  /// Tolerant by design. This file was transcribed by hand from photographs
  /// and carries a title line, a note line, a blank line, a header row, a
  /// blank separator and two footer rows around the actual data — none of
  /// which is a product. Rather than hard-coding "skip 4 rows", every row is
  /// judged on whether it has the two things an item cannot exist without: a
  /// name and at least one price. Everything else is passed over in silence,
  /// which is also what keeps a re-transcribed file with an extra note line
  /// at the top from importing that note as a drink.
  static List<BrewSeedItem> parse(String csv) {
    final items = <BrewSeedItem>[];
    var sort = 0.0;

    for (final line in csv.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;

      final cells = _splitRow(line);
      // Board, Category, Sub-Category, Item, Medium, Large, Notes.
      if (cells.length < 6) continue;

      final category = cells[1].trim();
      final subCategory = cells[2].trim();
      final name = cells[3].trim();
      final medium = _pesosToCents(cells[4]);
      final large = _pesosToCents(cells[5]);
      final notes = cells.length > 6 ? cells[6].trim() : '';

      // The header row reads "Item / Flavor" in the name column and has no
      // price anywhere, so it falls out here along with every other line that
      // is not a product.
      if (name.isEmpty || category.isEmpty) continue;
      if (medium == null && large == null) continue;

      final sizePrices = <BrewItemSize, int>{
        BrewItemSize.medium: ?medium,
        BrewItemSize.large: ?large,
      };

      // A row priced in one size only is a flat-priced item, not an item that
      // happens to come in Medium — see the doc on [BrewMenuItem.sizePrices]
      // for why the two are never both set. "Medium only" and "One size only"
      // in the notes column say the same thing the blank Large cell does.
      final onlyOneSize = sizePrices.length == 1;

      items.add(
        BrewSeedItem(
          name: name,
          category: category,
          // The source spells a category with no subdivisions by repeating
          // the category in this column. That is not a sub-category, and
          // storing it as one would draw a filter chip that selects
          // everything already on screen.
          subCategory:
              (subCategory.isEmpty || subCategory == category)
                  ? null
                  : subCategory,
          description: _descriptionFrom(notes),
          sizePrices: onlyOneSize ? const {} : sizePrices,
          priceCents: onlyOneSize ? sizePrices.values.first : null,
          sort: sort,
        ),
      );
      sort += 1;
    }

    return items;
  }

  /// Notes worth printing under an item, and nothing else.
  ///
  /// Most of the notes column is bookkeeping about the transcription rather
  /// than anything a customer would want read to them — "Individually
  /// priced", "One size only" and "Medium only" all restate what the price
  /// columns already say, and the "confirm with store" line is a message to
  /// whoever typed the file. Those are dropped; a genuine descriptor like
  /// "Coffee based" is kept.
  static String? _descriptionFrom(String notes) {
    if (notes.isEmpty) return null;
    const skip = {
      'individually priced',
      'one size only',
      'medium only',
    };
    final lower = notes.toLowerCase();
    if (skip.contains(lower)) return null;
    if (lower.contains('confirm with store')) return null;
    return notes;
  }

  /// A peso figure as minor units, or null for a blank cell.
  ///
  /// Strips the peso sign, thousands separators and stray spaces before
  /// parsing, so "₱1,250" and "₱45" both land. Anything that does not parse
  /// is treated as absent rather than as zero: a price of ₱0 would put a free
  /// drink on the board, which is a far worse reading of a typo than no price
  /// at all.
  static int? _pesosToCents(String cell) {
    final cleaned = cell.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final pesos = double.tryParse(cleaned);
    if (pesos == null || !pesos.isFinite || pesos < 0) return null;
    return (pesos * 100).round();
  }

  /// One CSV row into its cells, honouring double-quoted fields.
  ///
  /// Written out rather than pulled from the `csv` package: this is the only
  /// CSV this app will ever read, the grammar it needs is quotes and commas,
  /// and a dependency for that is a dependency to keep updated forever.
  static List<String> _splitRow(String line) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var quoted = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        // A doubled quote inside a quoted field is one literal quote.
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
          continue;
        }
        quoted = !quoted;
        continue;
      }
      if (char == ',' && !quoted) {
        cells.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    cells.add(buffer.toString());
    return cells;
  }
}
