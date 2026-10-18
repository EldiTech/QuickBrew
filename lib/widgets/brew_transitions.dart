import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The shared route motion for the customer flow: a quiet fade with a very
/// small rise so the new screen feels placed rather than pushed at the reader.
Route<T> brewPageRoute<T>({required Widget child, bool reduced = false}) {
  final duration = reduced ? Duration.zero : BrewMotion.pageTransition;

  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (duration == Duration.zero) return child;

      final curved = CurvedAnimation(
        parent: animation,
        curve: BrewMotion.pageTransitionCurve,
        reverseCurve: BrewMotion.pageTransitionCurve,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
