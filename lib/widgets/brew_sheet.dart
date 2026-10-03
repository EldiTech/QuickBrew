import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import 'cup_mark.dart';
import 'stagger.dart';

/// The page every signed-in panel is laid out on: gutter, top inset, a scroll
/// view, and one stagger group.
///
/// Every one of them scrolls. Unlike the splash and landing pair, nothing here is
/// promised to fit a viewport — the shop cards grow with the text scaler, and an
/// active order adds a block above them — so the honest structure is a page that
/// gets longer rather than one that clamps the reader's text size.
///
/// It reads its own [MediaQuery] rather than being handed one. Each panel then
/// only needs to know whether it is on a short frame, which is a typography
/// decision it makes itself; the insets are the page's business and are the same
/// on all of them.
class BrewSheet extends StatelessWidget {
  const BrewSheet({
    super.key,
    required this.staggerCount,
    required this.children,
  });

  /// How many [StaggerItem]s the children contain. Wrong here and the last item
  /// in the sequence never finishes fading in.
  final int staggerCount;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return StaggerGroup(
      itemCount: staggerCount,
      reveal: true,
      reduced: MediaQuery.disableAnimationsOf(context),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: BrewSpace.gutter,
          right: BrewSpace.gutter,
          top: math.max(media.padding.top, BrewSpace.minInset) +
              BrewSpace.headerClearance,
          // The nav owns the bottom safe area, so the sheet only owes the last
          // block a little air above it.
          bottom: BrewSpace.grid * 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

/// The cup and the wordmark, as the splash puts them down and as the login and
/// create-account screens repeat them.
///
/// Used by every signed-in panel except Home, whose masthead is the greeting. The
/// cup is at its landed size and stroke and sits at the same 24px gutter on all of
/// them, which is what stops the mark moving as the reader crosses the app.
class BrewWordmarkRow extends StatelessWidget {
  const BrewWordmarkRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ExcludeSemantics(
          child: CupMark(
            dimension: BrewMotion.cupLandingSize,
            progress: 1,
            strokeWidth: BrewMotion.cupLandingStroke,
          ),
        ),
        const SizedBox(width: BrewSpace.grid * 1.5),
        Text('QuickBrew', style: BrewType.wordmarkRow),
      ],
    );
  }
}

/// Vertical air between two blocks on a sheet, tightened a step on a short frame.
///
/// Every signed-in panel opens the same way — mark, gap, display line — and
/// separates its sections on the same measure. Stated once because five copies of
/// the same conditional is five places for one of them to drift a step out, and a
/// gap that is 32 on one panel and 24 on the next is the kind of thing nobody
/// spots and everybody feels.
double brewBlockGap(bool compact) => BrewSpace.grid * (compact ? 3 : 4);
