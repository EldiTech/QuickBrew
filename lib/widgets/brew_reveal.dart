import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Something that is there in one state and not in the other, animated where it
/// stands rather than snapping in and shoving the layout.
///
/// This is the app's fourth and last motion: a validation message arriving under
/// a field, the store picker that appears only once a role is set to admin, the
/// Remove button a shop only has while it has a logo, the line that confirms an
/// admin was created. Every one of those used to be a bare `if (x) ...[widget]`
/// inside a [Column] — which is a hard cut *and* an instant reflow of everything
/// below it, so the button the reader was about to press moves out from under
/// their thumb between one frame and the next.
///
/// Fades and grows together, from the top edge, on [BrewMotion.reveal]. The
/// growth is the point as much as the fade: the message is what pushed the
/// button down, so the two have to happen on the same ramp or the reader sees
/// the layout move before they see the reason for it. On the way out the old
/// child stays mounted and fades as it collapses — which is why this is a
/// switcher rather than an [AnimatedSize] around a conditional, where the child
/// would vanish on the first frame and leave an empty space to close over
/// nothing.
///
/// A null [child] is the absent state, and it collapses to nothing — this widget
/// occupies no height and reserves none, so it can be dropped into a Column
/// wherever a conditional spread used to be without changing the resting layout.
/// Swapping one non-null child for another of the same shape (one error message
/// for the next) updates in place rather than crossfading, which is right: the
/// line is already there and only its words changed.
class BrewReveal extends StatelessWidget {
  const BrewReveal({
    super.key,
    this.child,
    this.gap = 0,
    this.axis = Axis.vertical,
  });

  /// The thing that comes and goes. Null is "not right now".
  final Widget? child;

  /// Air before [child] along [axis], carried inside the reveal rather than left
  /// beside it as a sibling [SizedBox].
  ///
  /// A gap outside would be the one part of the change that did not animate:
  /// present at full size on the frame the message appeared and gone on the
  /// frame it left, which is exactly the reflow this widget exists to smooth.
  final double gap;

  /// Which way the space closes up.
  ///
  /// [Axis.vertical] is the common case — a message under a field, a section
  /// under a heading — and collapses downward from the top edge. [Axis.horizontal]
  /// is for a control that comes and goes inside a [Row], where the vertical
  /// version's full-width absent state would ask a Row for infinite width.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    final present = child == null
        // Full width in a Column so the cross-axis extent does not twitch as the
        // child comes and goes; nothing at all in a Row, where a width is
        // precisely what must not be claimed.
        ? (axis == Axis.vertical
              ? const SizedBox(width: double.infinity)
              : const SizedBox.shrink())
        : Padding(
            padding: axis == Axis.vertical
                ? EdgeInsets.only(top: gap)
                : EdgeInsetsDirectional.only(start: gap),
            child: child,
          );

    // Nothing to animate, and nothing gained by mounting a switcher to hold one
    // child: reduced motion wants the layout it would have settled at.
    if (MediaQuery.disableAnimationsOf(context)) return present;

    return AnimatedSwitcher(
      duration: BrewMotion.reveal,
      switchInCurve: BrewMotion.revealCurve,
      switchOutCurve: BrewMotion.revealCurve,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axis: axis,
        // Grows from its own leading edge, so what comes before it holds still
        // and only what comes after it moves.
        alignment: axis == Axis.vertical
            ? Alignment.topCenter
            : AlignmentDirectional.centerStart,
        child: FadeTransition(opacity: animation, child: child),
      ),
      // The default stacks its children centred, which would slide a message
      // sideways as the box around it grows. Held to the leading edge instead,
      // where every line on every one of these screens starts.
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [
          // A message on its way out is held out of the semantics tree while it
          // fades. These are live regions: leaving the old one readable for
          // another 180ms risks a screen reader announcing the failure the
          // reader has just fixed alongside the state that replaced it.
          for (final child in previous)
            ExcludeSemantics(child: IgnorePointer(child: child)),
          ?current,
        ],
      ),
      child: present,
    );
  }
}
