import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The marks the home screen draws: two in its header, and four more on the
/// active order's card.
///
/// [cup], [calendar], [clock] and [check] arrived with that card, which needs a
/// glyph per ordered drink, one each on its pickup and estimate facts, and a
/// tick inside the stage the counter has already passed. Drawn here rather
/// than reached for from Material for the reason the header pair were: see the
/// note on [BrewIconMark].
enum BrewIcon {
  notifications,
  profile,

  /// A lidded takeaway cup — one ordered drink.
  cup,

  /// The pickup fact. A page with a tick on it, not a date: the card prints the
  /// date beside it, and a glyph repeating the number would be the only thing
  /// on the screen saying it twice.
  calendar,

  /// The estimate fact.
  clock,

  /// Inside a stage the order has reached. Never on its own — it sits in a
  /// filled disc, so the stage reads as done by shape as well as by ink.
  check,
}

/// A header mark: outline only, round caps, one continuous weight — the cup's
/// drawing vocabulary at a smaller size.
///
/// Drawn rather than imported. The three glyphs in the ledger are supplied
/// artwork and the cup is a path; dropping a Material `Icons.notifications` in
/// beside them would put a filled, 24px-grid, different-cornered icon set on the
/// same screen as a 1.5px hairline outline, which is the one thing that makes a
/// custom design system look like a theme over a stock app.
///
/// The paths are authored against a unit box and scaled, so [dimension] can be
/// anything without the geometry drifting.
class BrewIconMark extends StatelessWidget {
  const BrewIconMark({
    super.key,
    required this.icon,
    this.dimension = 22,
    this.color,
    this.strokeWidth = 1.5,
  });

  final BrewIcon icon;
  final double dimension;

  /// Defaults to [BrewColor.iconInk] — the same sage-light-at-82% the ledger
  /// glyphs are drawn in, so a header mark and a row mark are the same ink. Cream
  /// is the pressed state, which the caller passes in.
  final Color? color;

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: dimension,
      child: CustomPaint(
        painter: _IconPainter(
          icon: icon,
          color: color ?? BrewColor.iconInk,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter({
    required this.icon,
    required this.color,
    required this.strokeWidth,
  });

  final BrewIcon icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    for (final path in switch (icon) {
      BrewIcon.notifications => _bell(size),
      BrewIcon.profile => _person(size),
      BrewIcon.cup => _cup(size),
      BrewIcon.calendar => _calendar(size),
      BrewIcon.clock => _clock(size),
      BrewIcon.check => _check(size),
    }) {
      canvas.drawPath(path, ink);
    }
  }

  /// A dome closed across its rim, plus the clapper hanging under it. Two paths,
  /// because the clapper is not part of the outline and joining them would draw a
  /// line from the rim down to it.
  List<Path> _bell(Size size) {
    double x(double v) => v * size.width;
    double y(double v) => v * size.height;

    final body = Path()
      ..moveTo(x(0.17), y(0.71))
      // Up the left flare into the wall.
      ..cubicTo(x(0.27), y(0.63), x(0.26), y(0.54), x(0.26), y(0.45))
      // Over the dome.
      ..cubicTo(x(0.26), y(0.28), x(0.36), y(0.17), x(0.50), y(0.17))
      ..cubicTo(x(0.64), y(0.17), x(0.74), y(0.28), x(0.74), y(0.45))
      // Down the right wall and out into its flare.
      ..cubicTo(x(0.74), y(0.54), x(0.73), y(0.63), x(0.83), y(0.71))
      // The rim, which closes the silhouette.
      ..close();

    final clapper = Path()
      ..moveTo(x(0.41), y(0.78))
      ..cubicTo(x(0.41), y(0.88), x(0.59), y(0.88), x(0.59), y(0.78));

    return [body, clapper];
  }

  /// A head and a pair of shoulders, open at the bottom — the shoulders are a
  /// line the frame cuts off, not a closed blob.
  List<Path> _person(Size size) {
    double x(double v) => v * size.width;
    double y(double v) => v * size.height;

    final head = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(x(0.50), y(0.33)),
          radius: size.shortestSide * 0.155,
        ),
      );

    final shoulders = Path()
      ..moveTo(x(0.19), y(0.85))
      ..cubicTo(x(0.19), y(0.63), x(0.33), y(0.56), x(0.50), y(0.56))
      ..cubicTo(x(0.67), y(0.56), x(0.81), y(0.63), x(0.81), y(0.85));

    return [head, shoulders];
  }

  /// Lid, tapered body, straw. Three paths for the same reason the bell is
  /// two: the straw does not touch the body, and one path would run a line
  /// between them.
  List<Path> _cup(Size size) {
    double x(double v) => v * size.width;
    double y(double v) => v * size.height;

    final lid = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x(0.18), y(0.22), x(0.82), y(0.34)),
          Radius.circular(size.shortestSide * 0.05),
        ),
      );

    // Walls that draw in toward a narrower base, with the base itself rounded
    // off — a paper cup, not a tumbler.
    final body = Path()
      ..moveTo(x(0.25), y(0.38))
      ..lineTo(x(0.32), y(0.84))
      ..cubicTo(x(0.33), y(0.89), x(0.36), y(0.91), x(0.41), y(0.91))
      ..lineTo(x(0.59), y(0.91))
      ..cubicTo(x(0.64), y(0.91), x(0.67), y(0.89), x(0.68), y(0.84))
      ..lineTo(x(0.75), y(0.38));

    final straw = Path()
      ..moveTo(x(0.57), y(0.22))
      ..lineTo(x(0.66), y(0.07));

    return [lid, body, straw];
  }

  /// A page with two rings over it and a tick inside.
  List<Path> _calendar(Size size) {
    double x(double v) => v * size.width;
    double y(double v) => v * size.height;

    final page = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x(0.13), y(0.22), x(0.87), y(0.88)),
          Radius.circular(size.shortestSide * 0.08),
        ),
      );

    // The rule under the month, which is what makes the box a calendar rather
    // than a note.
    final head = Path()
      ..moveTo(x(0.13), y(0.41))
      ..lineTo(x(0.87), y(0.41));

    // Drawn through the top edge rather than butted onto it, so they read as
    // rings the page hangs from.
    final rings = Path()
      ..moveTo(x(0.34), y(0.12))
      ..lineTo(x(0.34), y(0.30))
      ..moveTo(x(0.66), y(0.12))
      ..lineTo(x(0.66), y(0.30));

    final tick = Path()
      ..moveTo(x(0.32), y(0.63))
      ..lineTo(x(0.44), y(0.74))
      ..lineTo(x(0.68), y(0.52));

    return [page, head, rings, tick];
  }

  /// A ring and one bent hand, drawn as a single stroke from twelve through the
  /// centre to four.
  List<Path> _clock(Size size) {
    double x(double v) => v * size.width;
    double y(double v) => v * size.height;

    final ring = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(x(0.50), y(0.50)),
          radius: size.shortestSide * 0.36,
        ),
      );

    final hands = Path()
      ..moveTo(x(0.50), y(0.28))
      ..lineTo(x(0.50), y(0.52))
      ..lineTo(x(0.69), y(0.63));

    return [ring, hands];
  }

  List<Path> _check(Size size) {
    double x(double v) => v * size.width;
    double y(double v) => v * size.height;

    return [
      Path()
        ..moveTo(x(0.22), y(0.52))
        ..lineTo(x(0.42), y(0.71))
        ..lineTo(x(0.78), y(0.30)),
    ];
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
