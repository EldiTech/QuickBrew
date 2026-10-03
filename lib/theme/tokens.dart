import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Colour roles are fixed. Do not swap them.
///
/// Cream — not white — is the default ink. White appears exactly once per
/// screen, on the wordmark, which is what makes it read as a brand signal
/// instead of filler. Sage is never a full-screen background: it measures
/// 4.47:1 against white body text, and a mid-tone flat green field is the
/// most generic choice available here.
abstract final class BrewColor {
  /// Dominant background, both screens. Cream on this measures 7.9:1.
  static const field = Color(0xFF2A3D28);

  /// Deep luxury dark green for landing hero.
  static const darkField = Color(0xFF102216);

  /// Bottom of the splash gradient only.
  static const fieldDeep = Color(0xFF1E2C1D);

  /// Cup fill, pressed states, mid-tone plane.
  static const sage = Color(0xFF588157);

  /// Meta text, icon strokes, hairlines. 4.2:1 on field, so 12px+ only —
  /// never body copy.
  static const sageLight = Color(0xFFA8C695);

  /// Primary ink and primary button fill.
  static const cream = Color(0xFFE8DCC4);

  /// The wordmark, and nothing else.
  static const mark = Color(0xFFFFFFFF);

  /// Letterpress rule for the ledger: cream at 14%, full bleed to the gutter.
  static final hairline = cream.withValues(alpha: 0.14);

  /// The one raised surface in the app: the active order's card.
  ///
  /// Cream at 4% — a shade rather than a fill, and it exists for exactly one
  /// job. The shop cards below it are choices and are drawn as outlines on the
  /// field; the order card is not a choice, it is the thing already happening,
  /// and it has to read as sitting on top of the screen rather than as a third
  /// option. Everything else on a signed-in panel stays unfilled.
  static final panel = cream.withValues(alpha: 0.04);

  /// Benefit row descriptions, held under their titles.
  static final rowInk = cream.withValues(alpha: 0.76); // 5.7:1 on field

  /// The secondary action, deliberately lighter than the primary.
  static final secondaryInk = cream.withValues(alpha: 0.8); // 6.1:1 on field

  /// The ledger icons, drawn as a set.
  static final iconInk = sageLight.withValues(alpha: 0.82);

  /// Pressed fills darken rather than shifting hue, which keeps the label's
  /// contrast intact — a flat sage fill would drop it to 3.3:1.
  static Color pressed(Color fill) => darken(fill, 0.06);

  /// Scales RGB toward black while preserving alpha.
  static Color darken(Color color, double amount) => Color.from(
    alpha: color.a,
    red: color.r * (1 - amount),
    green: color.g * (1 - amount),
    blue: color.b * (1 - amount),
  );

  /// The crema band riding the top edge of the fill.
  static final crema = cream.withValues(alpha: 0.4);

  /// The splash loading state, held back so it reads as machine status rather
  /// than as copy.
  static final loading = cream.withValues(alpha: 0.55);

  /// Validation messages and the rule under a field that failed one. A warm
  /// terracotta rather than a signal red: it still belongs to the roast-bag
  /// palette. 5.4:1 on field, so it holds at the 12.5px the messages set.
  static const alert = Color(0xFFE9A178);

  /// What a field's own hairline brightens to while it holds focus. Cream, so
  /// the focused field reads as the one the keyboard is pointed at.
  static const fieldFocus = cream;
}

abstract final class BrewGradient {
  /// 165°: a hair off vertical, deepening toward the bottom-right. CSS measures
  /// gradient angles clockwise from "to top", so 165° is 15° short of straight
  /// down — hence the negative rotation applied to a top-to-bottom axis.
  static const _tilt = -15 * math.pi / 180;

  /// Splash only. The landing field stays flat.
  static const splash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [BrewColor.field, BrewColor.fieldDeep],
    transform: GradientRotation(_tilt),
  );
}

abstract final class BrewMotion {
  /// Four durations, and every animation in the app is one of them. Which one
  /// is a question about *what kind of change* is happening, not about which
  /// screen it is happening on — a card and a tab and a field's rule all react
  /// to a thumb on [press], so they all read as the same material.
  ///
  /// | Token          | What it is for                                      |
  /// |----------------|-----------------------------------------------------|
  /// | [press]        | A control reacting to a thumb, or to being selected |
  /// | [reveal]       | Something appearing or leaving *in place*           |
  /// | [staggerItem]  | Content entering a screen                           |
  /// | [transit]      | Crossing between screens                            |
  ///
  /// Stated here for the reason [brewBlockGap](../widgets/brew_sheet.dart)
  /// exists: this used to be a literal `Duration(milliseconds: 90)` written out
  /// nine times across seven files, which is nine places for one of them to
  /// drift and produce a card that settles at a different speed from the button
  /// beside it. Nobody spots that; everybody feels it.

  /// A control changing state: pressed, released, selected, focused. The fill
  /// darkens, the hairline brightens, the label's ink shifts — all on this.
  static const press = Duration(milliseconds: 90);
  static const pressCurve = Curves.easeOut;

  /// The 1px drop a pressed control takes. Suppressed under reduced motion,
  /// which leaves colour as the whole signal.
  static const pressDrop = 1.0;

  /// Something that exists in one state and not in the other, animated where it
  /// stands: a validation message under a field, a store picker that only a
  /// promoted account needs, the Remove button that only a shop with a logo
  /// has. Longer than [press] because it moves the layout around it, and a
  /// message that shoves the button below it down in 90ms reads as a jolt.
  ///
  /// See [BrewReveal](../widgets/brew_reveal.dart), which is the one
  /// implementation of it.
  static const reveal = Duration(milliseconds: 180);
  static const revealCurve = Curves.easeOut;

  /// The splash runs in three beats before it hands over: the container fades
  /// in, the mark draws its own outline, then the cup fills.
  static const containerFade = Duration(milliseconds: 200);
  static const strokeDraw = Duration(milliseconds: 320);

  /// Fast then settling — the way real extraction behaves.
  static const extraction = Duration(milliseconds: 1900);
  static const extractionCurve = Cubic(0.33, 0, 0.15, 1);

  /// 200 + 320 + 1900. The 420ms handoff runs after this, not inside it.
  static const splashRun = Duration(
    milliseconds: 200 + 320 + 1900,
  );

  /// Where each beat sits inside [splashRun], as a 0..1 fraction.
  static const fadeEnd = 200 / 2420;
  static const drawEnd = 520 / 2420;

  /// The cup's flight from splash centre to landing top-left, and — because it
  /// is the same kind of change — the duration every route push fades over and
  /// the one the signed-in tabs cross-fade on. A tab is a screen the reader
  /// crossed to; it should cost what crossing to one costs.
  static const transit = Duration(milliseconds: 420);
  static const transitCurve = Cubic(0.22, 1, 0.36, 1);

  /// Crossing between two things that occupy the same box: one route fading
  /// over another, one panel replacing another under the nav, one shop's mark
  /// replacing another's. [transitCurve] is the cup's own easing and belongs to
  /// the flight; a cross-fade is not travelling anywhere.
  static const crossFadeCurve = Curves.easeOut;

  static const staggerStep = Duration(milliseconds: 60);
  static const staggerItem = Duration(milliseconds: 260);
  static const staggerRise = 12.0;

  /// Reduced motion: the splash holds, then hands over on opacity alone.
  static const reducedHold = Duration(milliseconds: 1200);

  /// Fill fraction at which EXTRACTING becomes READY.
  static const readyAt = 0.92;

  static const cupSplashSize = 120.0;
  static const cupLandingSize = 40.0;
  static const cupSplashStroke = 1.75;

  /// 1.75 scaled to 40px would render at 0.58px and disappear, so the landed
  /// mark keeps a printable hairline instead.
  static const cupLandingStroke = 1.25;
}

abstract final class BrewSpace {
  static const gutter = 24.0;

  /// Floor for safe-area insets.
  static const minInset = 20.0;

  /// The bottom button group clears the edge by at least this much.
  static const bottomGroupInset = 28.0;

  /// Air below the safe-area inset. The inset is a floor, not a margin — on a
  /// real device the header lockup otherwise sits hard against the status bar.
  static const headerClearance = 16.0;

  /// Baseline grid. Every vertical value is a multiple of this.
  static const grid = 8.0;

  /// Committed, not the 8px no-opinion default.
  static const radius = 4.0;

  /// Icon column in the ledger, and the ceiling on how large a glyph may grow.
  ///
  /// The glyph is no longer a 20px bullet sat beside the copy: it squares up
  /// with the text block it labels, so it reads as that row's mark rather than
  /// as decoration. 64 is that block at the shipped sizes — a 16/1.3 title
  /// (20.8), the 4px gap, and two lines of 13.5/1.45 body (39.2) — which is
  /// also why the column stops there. Past it the glyph would eat the width the
  /// copy needs to stay at two lines, so a taller block caps rather than grows.
  static const iconColumn = 64.0;

  /// Air between the glyph column and the row's text block. Previously implicit
  /// in the 32px column, which held a 20px glyph; the glyph now fills its
  /// column, so the gap has to be stated.
  static const iconGap = 16.0;

  /// Below this height the display drops to 28 and row padding to 13. Nothing
  /// else changes, and it still must not scroll.
  static const compactHeight = 667.0;
  static const rowPadding = 16.0;
  static const rowPaddingCompact = 13.0;

  /// Keyboard focus ring: 2px, 2px clear of the control.
  static const focusRing = 2.0;
  static const focusOffset = 2.0;
}
