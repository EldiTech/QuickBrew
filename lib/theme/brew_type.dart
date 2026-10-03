import 'package:flutter/painting.dart';

import 'tokens.dart';

/// Three voices, no substitutions. Weight is driven through [FontVariation]
/// rather than [TextStyle.fontWeight] so the variable axes stay authoritative
/// and the engine never synthesises a fake bold over them.
abstract final class BrewType {
  static const _display = 'Fraunces';
  static const _body = 'Hanken Grotesk';
  static const _utility = 'Martian Mono';

  static const _displayFallback = <String>['Playfair Display', 'Georgia', 'serif'];
  static const _bodyFallback = <String>['Söhne', 'system-ui', 'sans-serif'];

  /// The body face leads the mono fallback, ahead of the generic monospaced
  /// names, for one glyph: Martian Mono has no ₱ (U+20B1), and every price in
  /// this app is set in mono. Without a face that has it in front of the
  /// platform's guesses, all 116 prices on the board render as tofu — which is
  /// exactly what the menu golden caught.
  ///
  /// Only the peso falls through to it. A fallback is consulted per glyph, so
  /// the digits, the labels and the size names all stay in Martian Mono; the
  /// currency sign alone is set in Hanken Grotesk, which is a far better
  /// outcome than a box where the price should be.
  static const _utilityFallback = <String>[
    _body,
    'ui-monospace',
    'monospace',
  ];

  static const _frauncesAxes = <FontVariation>[
    FontVariation('wght', 600),
    FontVariation('SOFT', 100),
    FontVariation('WONK', 1),
    FontVariation('opsz', 48),
  ];

  /// 34 / 1.02 / -0.02em. The wonk is what keeps it off-the-shelf.
  static const display = TextStyle(
    fontFamily: _display,
    fontFamilyFallback: _displayFallback,
    fontSize: 34,
    height: 1.02,
    letterSpacing: -0.68, // -0.02em at 34px
    color: BrewColor.cream,
    fontVariations: _frauncesAxes,
  );

  /// The display at a size other than 34; -0.02em tracking holds throughout.
  static TextStyle displayAt(double size) =>
      display.copyWith(fontSize: size, letterSpacing: size * -0.02);

  /// The splash wordmark, per §4: Fraunces 34 in cream.
  static TextStyle wordmark(double size, {Color color = BrewColor.mark}) =>
      TextStyle(
        fontFamily: _display,
        fontFamilyFallback: _displayFallback,
        fontSize: size,
        height: 1.02,
        letterSpacing: size * -0.02,
        color: color,
        fontVariations: _frauncesAxes,
      );

  /// The landing header lockup: §5 sets this in the body face, not Fraunces.
  static const wordmarkRow = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 16,
    height: 1.3,
    color: BrewColor.cream,
    fontVariations: <FontVariation>[FontVariation('wght', 600)],
  );

  /// Eyebrow tagline: GOOD COFFEE. LESS WAIT.
  static const tagline = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 11,
    height: 1.2,
    letterSpacing: 2.2,
    color: BrewColor.sageLight,
    fontVariations: <FontVariation>[FontVariation('wght', 600)],
  );

  /// Hero description text.
  static final heroSubtitle = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 14.5,
    height: 1.45,
    color: BrewColor.cream.withValues(alpha: 0.82),
    fontVariations: const <FontVariation>[FontVariation('wght', 400)],
  );

  /// A benefit row's title in serif.
  static const rowTitleSerif = TextStyle(
    fontFamily: _display,
    fontFamilyFallback: _displayFallback,
    fontSize: 16.5,
    height: 1.3,
    color: BrewColor.cream,
    fontVariations: <FontVariation>[
      FontVariation('wght', 600),
      FontVariation('SOFT', 40),
      FontVariation('WONK', 1),
      FontVariation('opsz', 24),
    ],
  );

  /// A benefit row's title.
  static const rowTitle = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 16,
    height: 1.3,
    color: BrewColor.cream,
    fontVariations: <FontVariation>[FontVariation('wght', 500)],
  );

  /// A benefit row's description.
  static final rowBody = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 13.5,
    height: 1.45,
    color: BrewColor.rowInk,
    fontVariations: const <FontVariation>[FontVariation('wght', 400)],
  );

  /// Two lines of [rowBody], for a slot that must hold the same height whether
  /// its copy runs to one line or two — the shop cards, where the alternative is
  /// two partners' blocks at two different heights.
  ///
  /// Derived from the style rather than written as a number so it follows the
  /// type: [TextStyle.height] is a multiple of [TextStyle.fontSize], which is
  /// what a line box measures.
  static final rowBodyTwoLineHeight = rowBody.fontSize! * rowBody.height! * 2;

  /// The primary action.
  static const buttonLabel = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 16,
    height: 1.3,
    color: BrewColor.field,
    fontVariations: <FontVariation>[FontVariation('wght', 600)],
  );

  /// The secondary action, at 500 rather than 600 so the primary wins.
  static final secondaryLabel = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 16,
    height: 1.3,
    color: BrewColor.secondaryInk,
    fontVariations: const <FontVariation>[FontVariation('wght', 500)],
  );

  /// 16 / 1.3 / 500.
  static const title = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 16,
    height: 1.3,
    color: BrewColor.cream,
    fontVariations: <FontVariation>[FontVariation('wght', 500)],
  );

  /// 13.5 / 1.45 / 400.
  static const body = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 13.5,
    height: 1.45,
    color: BrewColor.cream,
    fontVariations: <FontVariation>[FontVariation('wght', 400)],
  );

  /// 13.5 / 1.45 / 500. Interactive labels that sit in body copy.
  static const bodyMedium = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 13.5,
    height: 1.45,
    color: BrewColor.cream,
    fontVariations: <FontVariation>[FontVariation('wght', 500)],
  );

  /// What the user types. 16, not 13.5: a field's own ink is the one place on
  /// the login screen the reader is looking hardest, and iOS zooms a smaller
  /// field on focus.
  static const fieldInk = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 16,
    height: 1.3,
    color: BrewColor.cream,
    fontVariations: <FontVariation>[FontVariation('wght', 400)],
  );

  /// The placeholder, at the same metrics so nothing shifts once typing starts.
  static final fieldHint = fieldInk.copyWith(color: BrewColor.sageLight);

  /// A field's validation message. Kept in the body voice, not [mono] — these
  /// are sentences, and mono is never sentences.
  static const fieldError = TextStyle(
    fontFamily: _body,
    fontFamilyFallback: _bodyFallback,
    fontSize: 12.5,
    height: 1.35,
    color: BrewColor.alert,
    fontVariations: <FontVariation>[FontVariation('wght', 500)],
  );

  /// 10 / 1 / 0.14em, uppercase. The label voice of the roast bag: eyebrows,
  /// the loading state, timers. Never sentences.
  static const mono = TextStyle(
    fontFamily: _utility,
    fontFamilyFallback: _utilityFallback,
    fontSize: 10,
    height: 1,
    letterSpacing: 1.4, // 0.14em at 10px
    color: BrewColor.sageLight,
    fontVariations: <FontVariation>[FontVariation('wght', 500)],
  );

  /// The splash loading state: same utility voice, cream held at 55%.
  static final monoLoading = mono.copyWith(color: BrewColor.loading);
}
