import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';

/// The three ledger glyphs, sourced from assets/icons/ rather than drawn as
/// paths. Each still tints to the ledger's ink and runs the same small
/// breathing loop, so they read as a set. Coffee and Like are stock
/// Streamline Platinum outlines; Order-Approve is hand-drawn at a matching
/// stroke weight, since the pack's own version of that glyph is solid-filled
/// and read heavier than the other two.
enum BrewGlyph {
  /// A receipt with a check — placing the order.
  orderApprove,

  /// The cup itself.
  coffeeCup,

  /// A thumbs-up — the "ready" signal.
  thumbsUp;

  String get asset => switch (this) {
    BrewGlyph.orderApprove => 'assets/icons/Order-Approve.svg',
    BrewGlyph.coffeeCup => 'assets/icons/Coffee--Streamline-Platinum.png',
    BrewGlyph.thumbsUp => 'assets/icons/Like--Streamline-Platinum.png',
  };

  /// Where the drawn ink actually sits inside the asset's own box, as fractions
  /// of that box.
  ///
  /// The three assets frame themselves quite differently — Like bleeds to all
  /// four edges, Coffee holds a 12.5% margin on the left, Order-Approve nearly
  /// a quarter — which cost nothing while these were 20px bullets and does not
  /// survive being scaled to the height of a paragraph: rendered box-to-box at
  /// 64px, the receipt sat 15px right of the gutter that the thumb was flush
  /// with, and its ink stood 16px shorter. [LedgerIcon] fits the ink rather
  /// than the box, so the set squares up on the ink instead.
  ///
  /// Measured, not eyeballed: the PNGs by scanning their alpha channel, the SVG
  /// off its own path extents plus half its stroke. test/ledger_ink_test.dart
  /// re-measures the rasters and fails if an asset is ever swapped for one that
  /// frames itself differently.
  Rect get ink => switch (this) {
    // Paths span x 6..19.2, y 3..20 of 24, and the 0.75 stroke is centred on
    // that, so half of it sits outside on each side.
    BrewGlyph.orderApprove =>
      const Rect.fromLTWH(5.625 / 24, 2.625 / 24, 13.95 / 24, 17.75 / 24),
    // 48x48, ink l=6 t=1 w=36 h=46.
    BrewGlyph.coffeeCup =>
      const Rect.fromLTWH(6 / 48, 1 / 48, 36 / 48, 46 / 48),
    // 48x48, edge to edge.
    BrewGlyph.thumbsUp => const Rect.fromLTWH(0, 0, 1, 1),
  };
}

extension on BrewGlyph {
  bool get _isVector => this == BrewGlyph.orderApprove;
}

/// One shared tint, one shared loop period, for all three glyphs — the same
/// unifying role the shared stroke setup played for the old hand-drawn paths.
class LedgerIcon extends StatefulWidget {
  const LedgerIcon({super.key, required this.glyph, this.dimension = 20});

  final BrewGlyph glyph;
  final double dimension;

  @override
  State<LedgerIcon> createState() => _LedgerIconState();
}

class _LedgerIconState extends State<LedgerIcon>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 2400);
  static const _rest = 1.0;
  static const _peak = 1.08;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: _rest, end: _peak)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(begin: _peak, end: _rest)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
  ]).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = ColorFilter.mode(BrewColor.iconInk, BlendMode.srcIn);
    final glyph = widget.glyph;

    final image = glyph._isVector
        ? SvgPicture.asset(
            glyph.asset,
            width: widget.dimension,
            height: widget.dimension,
            colorFilter: tint,
          )
        : ColorFiltered(
            colorFilter: tint,
            child: Image.asset(
              glyph.asset,
              width: widget.dimension,
              height: widget.dimension,
              // The rasters are 48px sources and the ledger now paints them at
              // 64, so the sampling is an upscale either way; cubic is the one
              // that doesn't turn these hairlines to mush.
              filterQuality: FilterQuality.high,
            ),
          );

    final ink = glyph.ink;

    // Both paint-only: the widget still measures [dimension] square, so nothing
    // downstream has to know the assets disagree about their own margins.
    // Enlarge the asset until its ink — not its box — fills the square on the
    // ink's longer side, then slide the ink's corner onto the square's.
    final fill = 1 / math.max(ink.width, ink.height);
    final fitted = Transform.translate(
      offset: -ink.topLeft * widget.dimension * fill,
      child: Transform.scale(
        scale: fill,
        alignment: Alignment.topLeft,
        child: image,
      ),
    );

    return ScaleTransition(scale: _scale, child: fitted);
  }
}
