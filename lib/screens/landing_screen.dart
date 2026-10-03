import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/brew_buttons.dart';
import '../widgets/rebrew_cup.dart';
import '../widgets/stagger.dart';

/// A step item definition: number, title, description, and clean mono tag.
typedef _StepItem = ({
  String stepNumber,
  String title,
  String description,
  String tag,
});

/// QuickBrew Landing Screen redesigned with an editorial, premium cafe aesthetic:
/// - Branded header with QuickBrew™ wordmark.
/// - Hero section with tagline, Fraunces serif headline, and subtitle.
/// - Visual 3-step cards: Order ahead, Barista crafts, Grab & go.
/// - Pill-shaped warm oat "Log in" primary action and "Create account" entrypoint.
class LandingScreen extends StatelessWidget {
  const LandingScreen({
    super.key,
    required this.cupSlotKey,
    required this.showCupInSlot,
    required this.reveal,
    required this.reduced,
    this.onGetStarted,
    this.onCreateAccount,
  });

  /// Measured by the flow as the cup's destination.
  final Key cupSlotKey;

  /// False while the cup is in flight and drawn by the flow's overlay instead.
  final bool showCupInSlot;

  /// Flip to true once the cup has landed, to play the entrance.
  final bool reveal;

  final bool reduced;

  /// Fired by Log in — the screen's primary action.
  final VoidCallback? onGetStarted;

  /// Fired by Create account.
  final VoidCallback? onCreateAccount;

  static const _steps = <_StepItem>[
    (
      stepNumber: '01',
      title: 'Order ahead',
      description: 'Dial your roast, milk, and temperature on your walk over.',
      tag: 'ZERO WAIT',
    ),
    (
      stepNumber: '02',
      title: 'Barista crafts',
      description: 'Fresh single-origin beans ground and pulled to your recipe.',
      tag: 'DIALED IN',
    ),
    (
      stepNumber: '03',
      title: 'Grab & go',
      description: 'Waiting on the bar at peak temperature. No register queue.',
      tag: 'EXPRESS',
    ),
  ];

  /// Wordmark, hero section, each step card, then bottom CTA group.
  static final _staggerCount = 2 + _steps.length + 1;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.height <= BrewSpace.compactHeight;
    final textScale = media.textScaler.scale(1.0);
    final isEnlargedText = textScale > 1.05;

    final headerClearance = (isEnlargedText && compact) ? 4.0 : BrewSpace.headerClearance;
    final bottomInset = (isEnlargedText && compact) ? 14.0 : BrewSpace.bottomGroupInset;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Brand Header Row
        Row(
          children: [
            SizedBox.square(
              key: cupSlotKey,
              dimension: BrewMotion.cupLandingSize,
              child: showCupInSlot
                  ? const RebrewCupMark(
                      dimension: BrewMotion.cupLandingSize,
                      strokeWidth: BrewMotion.cupLandingStroke,
                    )
                  : null,
            ),
            const SizedBox(width: BrewSpace.grid * 1.5),
            StaggerItem(
              index: 0,
              child: Text.rich(
                TextSpan(
                  text: 'QuickBrew',
                  style: BrewType.wordmark(20, color: BrewColor.cream),
                  children: const [
                    TextSpan(
                      text: '™',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        Spacer(flex: compact ? 1 : 2),

        // Hero Block: Tagline + Editorial Serif Title + Subtitle + Product photo
        StaggerItem(
          index: 1,
          child: _HeroSection(
            compact: compact,
            hideSubtitle: compact && isEnlargedText,
            hideTagline: compact && isEnlargedText,
          ),
        ),

        Spacer(flex: compact ? 1 : 2),

        // Visual 3-Step Flow cards
        for (final (index, step) in _steps.indexed) ...[
          _StepCard(
            staggerIndex: 2 + index,
            step: step,
            compact: compact,
          ),
          if (index < _steps.length - 1)
            SizedBox(height: compact ? 8 : 12),
        ],

        Spacer(flex: compact ? 1 : 2),

        // Bottom CTAs: Pill "Log in" + "Create account"
        StaggerItem(
          index: 2 + _steps.length,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrewTextButton(
                label: 'Log in',
                asPill: true,
                pillHeight: (compact && isEnlargedText) ? 44.0 : 54.0,
                pillColor: const Color(0xFFEADBCA),
                pillTextColor: const Color(0xFF13251A),
                onPressed: onGetStarted,
              ),
              if (!compact || !isEnlargedText) ...[
                const SizedBox(height: 14),
                _CreateAccountRow(
                  onCreateAccount: onCreateAccount ?? onGetStarted,
                ),
              ],
            ],
          ),
        ),

        if (!compact || !isEnlargedText) const Spacer(flex: 1),
      ],
    );

    // Responsive centering for desktop / tablet web views
    if (media.size.width > 540) {
      content = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: content,
        ),
      );
    }

    return Material(
      color: BrewColor.darkField,
      child: BrewBackground(
        child: StaggerGroup(
            itemCount: _staggerCount,
            reveal: reveal,
            reduced: reduced,
            child: Padding(
              padding: EdgeInsets.only(
                left: BrewSpace.gutter,
                right: BrewSpace.gutter,
                top: math.max(media.padding.top, BrewSpace.minInset) +
                    headerClearance,
                bottom: math.max(
                  media.padding.bottom,
                  bottomInset,
                ),
              ),
              child: content,
          ),
        ),
      ),
    );
  }
}

/// Hero block with editorial typography.
class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.compact,
    this.hideSubtitle = false,
    this.hideTagline = false,
  });

  final bool compact;
  final bool hideSubtitle;
  final bool hideTagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hideTagline) ...[
          Text('GOOD COFFEE. LESS WAIT.', style: BrewType.tagline),
          SizedBox(height: compact ? 6 : 10),
        ],
        Text(
          'Made before you get there.',
          style: BrewType.displayAt(compact ? 28 : 34),
        ),
        if (!hideSubtitle) ...[
          SizedBox(height: compact ? 8 : 12),
          Text(
            'Skip the line and get your favorite drinks, made fresh and ready when you arrive.',
            style: BrewType.heroSubtitle.copyWith(
              fontSize: compact ? 13 : 14.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Modern frosted glass step card with architectural number badge and clean mono tag.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.staggerIndex,
    required this.step,
    required this.compact,
  });

  final int staggerIndex;
  final _StepItem step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StaggerItem(
      index: staggerIndex,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 13 : 16,
          vertical: compact ? 10 : 13,
        ),
        decoration: BoxDecoration(
          color: const Color(0x380A170F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: BrewColor.cream.withValues(alpha: 0.12),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Architectural step index badge
            Container(
              width: compact ? 34 : 38,
              height: compact ? 34 : 38,
              decoration: BoxDecoration(
                color: BrewColor.cream.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: BrewColor.cream.withValues(alpha: 0.14),
                  width: 1.0,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                step.stepNumber,
                style: BrewType.mono.copyWith(
                  fontSize: compact ? 12 : 13.5,
                  fontWeight: FontWeight.w700,
                  color: BrewColor.cream,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            SizedBox(width: compact ? 12 : 14),
            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: BrewType.rowTitleSerif.copyWith(
                            fontSize: compact ? 14.5 : 16,
                            fontWeight: FontWeight.w600,
                            color: BrewColor.cream,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Clean typographic mono tag
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: BrewColor.sageLight.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: BrewColor.sageLight.withValues(alpha: 0.25),
                            width: 0.75,
                          ),
                        ),
                        child: Text(
                          step.tag,
                          style: BrewType.mono.copyWith(
                            fontSize: compact ? 8.5 : 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: BrewColor.sageLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    step.description,
                    style: BrewType.rowBody.copyWith(
                      fontSize: compact ? 11 : 12,
                      color: BrewColor.cream.withValues(alpha: 0.72),
                      height: 1.28,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Hairline divider flanked "Create account" row.
class _CreateAccountRow extends StatelessWidget {
  const _CreateAccountRow({required this.onCreateAccount});

  final VoidCallback? onCreateAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 0.75,
            color: BrewColor.cream.withValues(alpha: 0.18),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onCreateAccount,
              child: Text(
                'Create account',
                style: TextStyle(
                  fontFamily: 'Hanken Grotesk',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: BrewColor.sageLight.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 0.75,
            color: BrewColor.cream.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}
