import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import 'brew_icons.dart';

/// The stages as an order's progress names them, indexed by
/// [BrewOrderStage.index].
///
/// Two words at most. They label the points of a track four across, and the
/// first of them also sits in a pill beside the shop's own name — on the home
/// screen's card and, full size, on [OrderTrackingScreen]. Deliberately not
/// [BrewOrderStage.label], which is a whole sentence about the reader's cup —
/// "Preparing your order" — and needs a line of its own to be set on. The
/// Orders tab still says it in full, and so does the card's one
/// screen-reader announcement; what neither the pill nor a quarter of the
/// track can afford is twenty characters of it.
///
/// Positional, coupled to the enum's order exactly as [BrewOrder.step]
/// already is — see the note on [BrewOrderStage.rejected] for why the fifth
/// entry is last rather than beside Received. Only the first [BrewOrder.steps]
/// of them are ever drawn on the track; Declined is here so the pill has a
/// word for an order the shop turned down, which is a stage neither of these
/// widgets draws a track point for but which the type still has.
const orderStageNames = <String>[
  'Received',
  'Preparing',
  'Ready',
  'Picked up',
  'Declined',
];

/// Where an order has got to, as one word in a bordered pill.
///
/// The pill's dot is filled while the order is still moving and hollow once it
/// has stopped, the same filled-or-hollow reading a shop's own hours mark
/// gives — and for the same reason: the word is the signal, the dot is what
/// makes two states tell each other apart across a room without asking anyone
/// to separate two hues.
class StagePill extends StatelessWidget {
  const StagePill({super.key, required this.stage});

  final BrewOrderStage stage;

  static const _dot = 6.0;

  @override
  Widget build(BuildContext context) {
    final moving = stage.isActive;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BrewSpace.grid,
        vertical: BrewSpace.grid * 0.75,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: BrewColor.hairline),
        // A pill, not the committed 4px: this is a label rather than a panel,
        // and a stadium says so without needing a second colour to.
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _dot,
            height: _dot,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: moving ? BrewColor.sageLight : null,
              border: moving ? null : Border.all(color: BrewColor.iconInk),
            ),
          ),
          const SizedBox(width: BrewSpace.grid * 0.75),
          Flexible(
            child: Text(
              orderStageNames[stage.index].toUpperCase(),
              style: BrewType.mono.copyWith(color: BrewColor.cream),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Received, preparing, ready, picked up — as four points on one track.
///
/// A disc per stage rather than four segments of a rule. The segments said how
/// far along the order was; the discs say the same thing and also name the
/// four places it can be, which is the question a reader staring at
/// "Preparing" actually has — what comes after this, and how many more of
/// them are there.
///
/// It does not slide. The stage changes when the counter says it does, which
/// is an event arriving from Firestore: a track that travelled would imply the
/// order is continuously progressing, when in fact it sits in Preparing for
/// several minutes and then jumps.
///
/// What it does do is ink the next disc and the rail into it on the same 90ms
/// ramp every other rule in the app changes on — the field's hairline, a
/// card's border, the tab bar's indicator. That is a crossfade in place, not
/// travel, so the reasoning above survives intact; the disc simply stops being
/// the one thing on the screen that changes between two frames with nothing in
/// between. A reader watching when the counter moves their order on sees it
/// happen rather than finding it already happened.
class StageTrack extends StatelessWidget {
  const StageTrack({super.key, required this.step, required this.steps});

  /// 1-based, so [step] discs are inked.
  final int step;
  final int steps;

  static const _disc = 22.0;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced ? Duration.zero : BrewMotion.press;

    return Column(
      children: [
        SizedBox(
          height: _disc,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The rail, under the discs. Its segments are flexed 2 against a
              // 1 at each end, which puts the run from the first disc's centre
              // to the last's — the same centres the equal-width columns below
              // put the discs and their labels on. Each segment then insets
              // itself by a radius so it meets the discs rather than crossing
              // through the hollow ones.
              Row(
                children: [
                  const Spacer(),
                  for (var index = 0; index < steps - 1; index++)
                    Expanded(
                      flex: 2,
                      child: AnimatedContainer(
                        duration: duration,
                        curve: BrewMotion.pressCurve,
                        height: 2,
                        margin: const EdgeInsets.symmetric(
                          horizontal: _disc / 2 + 3,
                        ),
                        color: index < step
                            ? BrewColor.sageLight
                            : BrewColor.hairline,
                      ),
                    ),
                  const Spacer(),
                ],
              ),
              Row(
                children: [
                  for (var index = 0; index < steps; index++)
                    Expanded(
                      child: Center(
                        child: _StageDisc(
                          done: index < step,
                          duration: duration,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: BrewSpace.grid),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < steps; index++)
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: BrewMotion.pressCurve,
                  style: BrewType.rowBody.copyWith(
                    fontSize: 11.5,
                    color: index < step ? BrewColor.cream : BrewColor.rowInk,
                  ),
                  textAlign: TextAlign.center,
                  child: Text(orderStageNames[index], maxLines: 2),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One point on the track: filled with a tick once passed, hollow until then.
class _StageDisc extends StatelessWidget {
  const _StageDisc({required this.done, required this.duration});

  final bool done;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: BrewMotion.pressCurve,
      width: StageTrack._disc,
      height: StageTrack._disc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? BrewColor.sageLight : null,
        border: done
            ? null
            : Border.all(color: BrewColor.sageLight.withValues(alpha: 0.45)),
      ),
      // Cross-faded rather than switched, so a stage the counter moves on does
      // not pop a tick into place a frame before the disc behind it has
      // finished filling.
      child: AnimatedOpacity(
        duration: duration,
        curve: BrewMotion.pressCurve,
        opacity: done ? 1 : 0,
        child: const BrewIconMark(
          icon: BrewIcon.check,
          dimension: 12,
          // On the filled disc, so it takes the field's own ink.
          color: BrewColor.field,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

/// One drink: its mark, its name, and what was done to it.
class OrderItemRow extends StatelessWidget {
  const OrderItemRow({super.key, required this.split});

  /// The drink and its extras — see [splitOrderLine].
  final (String, String?) split;

  static const _markSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final (drink, extras) = split;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The same bordered, 4px box a shop's logo sits in, so a drink and a
        // shop are the same kind of thing here rather than a glyph floating
        // beside some text.
        Container(
          width: _markSize,
          height: _markSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: BrewColor.hairline),
            borderRadius: BorderRadius.circular(BrewSpace.radius),
          ),
          child: const BrewIconMark(icon: BrewIcon.cup, dimension: 20),
        ),
        const SizedBox(width: BrewSpace.grid * 1.5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(drink, style: BrewType.rowTitle),
              if (extras != null) ...[
                const SizedBox(height: 2),
                Text(
                  extras,
                  style: BrewType.rowBody.copyWith(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "5× Dirty Avalanche (Small) + Espresso shot, Oat milk" split into the drink
/// and what was done to it, which is how [OrderItemRow] draws them: name on
/// top, extras underneath.
///
/// The separator is the one `_CartLine.orderLine` writes in
/// order_wizard_screen.dart, which is the only thing that composes these
/// strings. A line with no ' + ' in it is a drink with no extras, which is
/// most of them, and it simply gets no second line.
(String, String?) splitOrderLine(String line) {
  final at = line.indexOf(' + ');
  if (at < 0) return (line, null);
  final extras = [
    for (final extra in line.substring(at + 3).split(','))
      if (extra.trim().isNotEmpty) extra.trim(),
  ];
  if (extras.isEmpty) return (line.substring(0, at), null);
  return (line.substring(0, at), extras.join(' · '));
}

/// One order fact: a mark, a mono caption, the answer, and the small print
/// under it.
///
/// Two of them side by side rather than four stacked mono lines. Pickup and
/// the estimate are the two questions a reader opens either the home screen's
/// card or [OrderTrackingScreen] to answer, and a row of two answers is read
/// in one glance where a stack of four is read in four.
class OrderFact extends StatelessWidget {
  const OrderFact({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.meta,
  });

  final BrewIcon icon;

  /// Uppercased here, so callers pass it in sentence case — the same contract
  /// [BrewMonoButton] holds to.
  final String label;

  final String value;

  /// The line under the answer, which qualifies it rather than repeating it:
  /// the calendar date behind "Today", the fact that an estimate is
  /// preparation time and not a promise about the queue.
  final String meta;

  static const _markSize = 30.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: _markSize,
              height: _markSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: BrewColor.hairline),
                borderRadius: BorderRadius.circular(BrewSpace.radius),
              ),
              child: BrewIconMark(icon: icon, dimension: 16),
            ),
            const SizedBox(width: BrewSpace.grid),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: BrewType.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: BrewType.rowBody.copyWith(
                      fontSize: 11.5,
                      color: BrewColor.loading,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A rule, solid between blocks and dashed between the drinks inside one.
class CardRule extends StatelessWidget {
  const CardRule({super.key, this.dashed = false});

  final bool dashed;

  @override
  Widget build(BuildContext context) {
    if (!dashed) {
      return Container(height: 1, color: BrewColor.hairline);
    }
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: const _DashPainter()),
    );
  }
}

/// The dashed variant, painted rather than composed out of boxes: a row of
/// three-pixel [Container]s across a card is fifty widgets for one line.
class _DashPainter extends CustomPainter {
  const _DashPainter();

  static const _dash = 3.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..strokeWidth = 1
      ..color = BrewColor.hairline;

    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      canvas.drawLine(
        Offset(x, 0.5),
        // Clipped to the last whole dash rather than run past the edge, so the
        // line ends on the card's padding instead of under it.
        Offset(math.min(x + _dash, size.width), 0.5),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}
