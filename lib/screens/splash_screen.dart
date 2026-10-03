import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/cup_mark.dart';

/// Centred, because it is a mark and centring is correct for a mark.
///
/// No card, no ring around the mark, no drop shadow. The mark sits directly on
/// the field.
class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    required this.progress,
    required this.strokeProgress,
    required this.cupSlotKey,
    required this.showCupInSlot,
  });

  /// Eased extraction progress, 0..1.
  final double progress;

  /// How much of the outline has drawn itself, 0..1.
  final double strokeProgress;

  /// Measured by the flow to launch the cup on its travel.
  final Key cupSlotKey;

  /// False while the cup is in flight and drawn by the flow's overlay instead.
  final bool showCupInSlot;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);

    return BrewBackground(
      child: Padding(
        padding: EdgeInsets.only(
          left: BrewSpace.gutter,
          right: BrewSpace.gutter,
          top: math.max(insets.top, BrewSpace.minInset),
          bottom: math.max(insets.bottom, BrewSpace.minInset),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    key: cupSlotKey,
                    dimension: BrewMotion.cupSplashSize,
                    child: showCupInSlot
                        ? CupMark(
                            dimension: BrewMotion.cupSplashSize,
                            progress: progress,
                            strokeProgress: strokeProgress,
                            strokeWidth: BrewMotion.cupSplashStroke,
                          )
                        : null,
                  ),
                  const SizedBox(height: BrewSpace.grid * 3),
                  Text(
                    'QuickBrew',
                    textAlign: TextAlign.center,
                    style: BrewType.wordmark(34, color: BrewColor.cream),
                  ),
                  const SizedBox(height: BrewSpace.grid * 2),
                  const Text(
                    'COFFEE, ORDERED AHEAD',
                    textAlign: TextAlign.center,
                    style: BrewType.mono,
                  ),
                ],
              ),
            ),
            // The loading state belongs to the machine, not to the mark, so it
            // sits away from the centred group.
            Positioned(
              left: 0,
              right: 0,
              bottom: BrewSpace.grid * 4,
              child: Text(
                progress >= BrewMotion.readyAt ? 'READY' : 'EXTRACTING',
                textAlign: TextAlign.center,
                style: BrewType.monoLoading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
