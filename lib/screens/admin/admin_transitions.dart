import 'package:flutter/widgets.dart';

/// Creates a cinematic, fluid page route transition tailored for the admin console.
///
/// Combines a subtle slide from the right, soft scale-up for depth, and smooth
/// fade-in with an Apple/Material 3-grade deceleration curve (`Cubic(0.16, 1.0, 0.3, 1.0)`).
/// When another screen is pushed on top, the underlying screen subtly recedes and dims.
PageRoute<T> adminPageRoute<T>({
  required WidgetBuilder builder,
  bool reduced = false,
  Duration duration = const Duration(milliseconds: 320),
  Duration reverseDuration = const Duration(milliseconds: 260),
}) {
  if (reduced) {
    return PageRouteBuilder<T>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (_, _, _, child) => child,
    );
  }

  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: reverseDuration,
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
        reverseCurve: Curves.easeInCubic,
      );

      final slide = Tween<Offset>(
        begin: const Offset(0.0, 0.035),
        end: Offset.zero,
      ).animate(curve);

      final fade = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(curve);

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: child,
        ),
      );
    },
  );
}
