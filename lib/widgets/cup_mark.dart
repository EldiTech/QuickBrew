import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The one memorable thing. An outline-only cup that fills with sage from 0%
/// to 100% of its own silhouette, with a cream crema band riding the top edge
/// of the rising surface.
///
/// This is also the loading indicator. There are no three animated dots.
class CupMark extends StatelessWidget {
  const CupMark({
    super.key,
    required this.dimension,
    required this.progress,
    this.strokeProgress = 1,
    this.strokeWidth = BrewMotion.cupSplashStroke,
  });

  final double dimension;

  /// 0 = empty outline, 1 = fully extracted.
  final double progress;

  /// How much of the outline has drawn itself, 0..1.
  final double strokeProgress;

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: dimension,
      child: CustomPaint(
        painter: _CupPainter(
          progress: progress,
          strokeProgress: strokeProgress,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _CupPainter extends CustomPainter {
  const _CupPainter({
    required this.progress,
    required this.strokeProgress,
    required this.strokeWidth,
  });

  final double progress;
  final double strokeProgress;
  final double strokeWidth;

  /// The cup is drawn against this box, so the crema band scales with the mark.
  static const _designSize = BrewMotion.cupSplashSize;
  static const _cremaBand = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final body = _bodyPath(size);
    final fill = progress.clamp(0.0, 1.0);

    if (fill > 0) {
      // Clip to the silhouette and stroke afterwards, so the fill meets the
      // cream stroke exactly and the taper is respected without an inset path.
      final bounds = body.getBounds();
      final surface = bounds.bottom - bounds.height * fill;
      final scale = size.width / _designSize;

      canvas.save();
      canvas.clipPath(body);
      canvas.drawRect(
        Rect.fromLTRB(bounds.left, surface, bounds.right, bounds.bottom),
        Paint()..color = BrewColor.sage,
      );
      canvas.drawRect(
        Rect.fromLTRB(
          bounds.left,
          surface,
          bounds.right,
          surface + _cremaBand * scale,
        ),
        Paint()..color = BrewColor.crema,
      );
      canvas.restore();
    }

    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = BrewColor.cream;

    _strokeOutline(canvas, body, _handlePath(size), ink);
  }

  /// The outline draws itself as one continuous line: down the left wall, round
  /// the base, up the right wall, across the rim, then out into the handle.
  void _strokeOutline(Canvas canvas, Path body, Path handle, Paint ink) {
    final drawn = strokeProgress.clamp(0.0, 1.0);
    if (drawn >= 1) {
      canvas.drawPath(body, ink);
      canvas.drawPath(handle, ink);
      return;
    }
    if (drawn <= 0) return;

    final bodyLength = _lengthOf(body);
    final handleLength = _lengthOf(handle);
    final pen = (bodyLength + handleLength) * drawn;

    canvas.drawPath(_upTo(body, pen / bodyLength), ink);
    if (pen > bodyLength) {
      canvas.drawPath(_upTo(handle, (pen - bodyLength) / handleLength), ink);
    }
  }

  double _lengthOf(Path path) => path
      .computeMetrics()
      .fold(0, (total, metric) => total + metric.length);

  Path _upTo(Path path, double fraction) {
    if (fraction >= 1) return path;
    final partial = Path();
    for (final metric in path.computeMetrics()) {
      partial.addPath(
        metric.extractPath(0, metric.length * fraction.clamp(0.0, 1.0)),
        Offset.zero,
      );
    }
    return partial;
  }

  /// A tapered cup, closed across the rim so the interior can be filled.
  Path _bodyPath(Size size) {
    double x(double v) => v * size.width;
    double y(double v) => v * size.height;

    final topLeft = Offset(x(0.17), y(0.20));
    final topRight = Offset(x(0.71), y(0.20));
    final bottomLeft = Offset(x(0.27), y(0.82));
    final bottomRight = Offset(x(0.61), y(0.82));
    final radius = 0.075 * size.width;

    final leftWall = bottomLeft - topLeft;
    final rightWall = topRight - bottomRight;
    final leftDir = leftWall / leftWall.distance;
    final rightDir = rightWall / rightWall.distance;

    final enterLeftCorner = bottomLeft - leftDir * radius;
    final leaveLeftCorner = bottomLeft + Offset(radius, 0);
    final enterRightCorner = bottomRight - Offset(radius, 0);
    final leaveRightCorner = bottomRight + rightDir * radius;

    return Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(enterLeftCorner.dx, enterLeftCorner.dy)
      ..quadraticBezierTo(
        bottomLeft.dx,
        bottomLeft.dy,
        leaveLeftCorner.dx,
        leaveLeftCorner.dy,
      )
      ..lineTo(enterRightCorner.dx, enterRightCorner.dy)
      ..quadraticBezierTo(
        bottomRight.dx,
        bottomRight.dy,
        leaveRightCorner.dx,
        leaveRightCorner.dy,
      )
      ..lineTo(topRight.dx, topRight.dy)
      ..close();
  }

  /// Stroked only — the handle is outside the fill clip, so it never takes sage.
  Path _handlePath(Size size) {
    double x(double v) => v * size.width;
    double y(double v) => v * size.height;

    return Path()
      ..moveTo(x(0.69), y(0.33))
      ..cubicTo(x(0.94), y(0.34), x(0.92), y(0.60), x(0.65), y(0.60));
  }

  @override
  bool shouldRepaint(_CupPainter old) =>
      old.progress != progress ||
      old.strokeProgress != strokeProgress ||
      old.strokeWidth != strokeWidth;
}
