import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A fixed two-column grid, laid out as rows rather than as a [GridView].
///
/// A GridView here would be a scrollable inside the scrollable both boards
/// already are, which means either nesting two scroll views or handing this
/// one a shrink-wrapped viewport that measures every cell twice. These boards
/// are already built as a Column inside one SingleChildScrollView — the
/// stagger group depends on that — so the grid is the same Column with its
/// children paired up.
///
/// Cells in a row are stretched to the tallest of the pair via
/// [IntrinsicHeight], so two cells beside each other read as one band rather
/// than as two blocks that happen to be adjacent. An odd last cell keeps its
/// column width instead of stretching across both, which is what stops the
/// final item on a board of 117 looking like a section heading.
class BrewGrid extends StatelessWidget {
  const BrewGrid({super.key, required this.children, this.gap = BrewSpace.grid * 1.5});

  final List<Widget> children;

  /// Between columns and between rows alike, so the grid reads as an even
  /// field rather than as columns that were spaced apart afterwards.
  final double gap;

  /// Two, everywhere. Not derived from the width: the boards this lays out
  /// are read on phones, and a third column at this text size is narrower
  /// than the longest drink name on the menu.
  static const columns = 2;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      final end = (start + columns).clamp(0, children.length);
      final row = children.sublist(start, end);

      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) SizedBox(width: gap),
                Expanded(
                  // The empty half of a short final row still claims its
                  // column, so the one cell above it keeps its width instead
                  // of growing to the full measure.
                  child: column < row.length ? row[column] : const SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) SizedBox(height: gap),
          row,
        ],
      ],
    );
  }
}
