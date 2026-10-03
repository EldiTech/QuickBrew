import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';

/// The board's category filter: one scrolling row of chips, exactly one of
/// them chosen.
///
/// Related to [BrewChoice](brew_choice.dart) but deliberately not it. That
/// control is a fixed set of two or three options laid out in `Expanded`s
/// across the full width — a store picker, a role picker — and it centres and
/// pads accordingly. A category list is neither fixed nor small: this board
/// carries eight of them and the next one may carry twenty, so these chips
/// shrink-wrap their labels and the row scrolls rather than dividing the
/// width into ever-thinner columns.
///
/// Selection is held by the caller for the same reason [BrewChoice] leaves it
/// there: the filter decides what the screen below draws, so the screen owns
/// it.
class BrewFilterRow extends StatelessWidget {
  const BrewFilterRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.padding,
  });

  /// The chips, in the order they are drawn. The caller puts "All" at the
  /// front rather than this widget inventing one, because only the caller
  /// knows what "all" means for the list it is filtering.
  final List<String> options;

  /// Which chip is lit. A value not in [options] simply lights nothing, which
  /// is the right reading of a filter whose category has just been deleted
  /// out from under it.
  final String selected;

  final ValueChanged<String> onSelected;

  /// Bled to the gutter rather than inset, on the screens that want the row
  /// to run off both edges the way a menu board's own sections do.
  final EdgeInsetsGeometry? padding;

  /// The row as it should appear inside a gutter-padded scroll view: shifted
  /// back out over the gutter and given the full width, so the chips start
  /// where the text above them starts and the last one runs off the edge
  /// instead of being clipped short of it.
  ///
  /// Both boards do this, so it is stated once here rather than as the same
  /// Transform-inside-a-SizedBox written out on each. Flutter has no negative
  /// margin; this is what stands in for one.
  static Widget bled(
    BuildContext context, {
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
    double gutter = BrewSpace.gutter,
  }) {
    return Transform.translate(
      offset: Offset(-gutter, 0),
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        child: BrewFilterRow(
          options: options,
          selected: selected,
          onSelected: onSelected,
          padding: EdgeInsets.symmetric(horizontal: gutter),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final (index, option) in options.indexed) ...[
            if (index > 0) const SizedBox(width: BrewSpace.grid),
            _FilterChip(
              label: option,
              selected: option == selected,
              onSelected: () => onSelected(option),
            ),
          ],
        ],
      ),
    );
  }
}

/// One chip. The mono label voice, so the row reads as machine-set section
/// headings rather than as a second rank of buttons competing with the items
/// underneath it.
class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final selected = widget.selected;

    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '${widget.label}, showing' : 'Show ${widget.label}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onSelected();
          },
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.95 : (_hovered && !selected ? 1.03 : 1.0),
            child: AnimatedContainer(
              duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                horizontal: BrewSpace.grid * 1.75,
                vertical: BrewSpace.grid * 1.1,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? BrewColor.sage.withValues(alpha: 0.32)
                    : (_hovered
                        ? BrewColor.cream.withValues(alpha: 0.1)
                        : const Color(0xEB132218)),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? BrewColor.sageLight.withValues(alpha: 0.75)
                      : (_hovered
                          ? BrewColor.cream.withValues(alpha: 0.28)
                          : BrewColor.cream.withValues(alpha: 0.14)),
                  width: 1.0,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: BrewColor.sage.withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                widget.label.toUpperCase(),
                style: BrewType.mono.copyWith(
                  color: selected
                      ? BrewColor.cream
                      : BrewColor.cream.withValues(alpha: _hovered ? 0.95 : 0.68),
                  fontSize: 10.5,
                  letterSpacing: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
