import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'cup_mark.dart';

/// The landed mark, made live: tap it and the cup drains and re-extracts on the
/// same curve the splash used.
///
/// This is the only playful thing on the screen, and it is deliberately the
/// signature element rather than a new one — the reward for touching the logo is
/// the logo doing the thing it is known for. It carries no function, so it stays
/// out of the semantics tree; the wordmark beside it is what assistive tech
/// reads.
class RebrewCupMark extends StatefulWidget {
  const RebrewCupMark({
    super.key,
    required this.dimension,
    required this.strokeWidth,
  });

  final double dimension;
  final double strokeWidth;

  @override
  State<RebrewCupMark> createState() => _RebrewCupMarkState();
}

class _RebrewCupMarkState extends State<RebrewCupMark>
    with SingleTickerProviderStateMixin {
  /// Draining is quick and mechanical; refilling uses the extraction curve.
  static const _drain = 260;
  static const _cycle = _drain + 1900;
  static const _drainEnd = _drain / _cycle;

  static const _drainWindow = Interval(0, _drainEnd, curve: Curves.easeIn);
  static const _fillWindow = Interval(
    _drainEnd,
    1,
    curve: BrewMotion.extractionCurve,
  );

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _cycle),
    value: 1, // At rest the cup is full.
  );

  /// Full at both ends of the cycle, empty at the handover between them.
  double get _progress {
    final t = _controller.value;
    return t < _drainEnd
        ? 1 - _drainWindow.transform(t)
        : _fillWindow.transform(t);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _rebrew() {
    HapticFeedback.selectionClick();
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    return ExcludeSemantics(
      child: MouseRegion(
        cursor: reduced ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          // The cup is a CustomPaint with no child, so it has nothing to defer
          // hit testing to; without this the mark is untappable.
          behavior: HitTestBehavior.opaque,
          onTap: reduced ? null : _rebrew,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CupMark(
              dimension: widget.dimension,
              progress: reduced ? 1 : _progress,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}
