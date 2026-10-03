import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import 'brew_icons.dart';

/// One account, drawn as a mark: initials on a ring.
///
/// [BrewShopMark](shop_mark.dart)'s counterpart, and deliberately a different
/// shape — the 14% hairline closed into a circle rather than the shop's square
/// — so a person and a shop can sit in the same block without the reader having
/// to work out which of the two a given box is.
///
/// Three sources in a fixed order, the way [BrewShopMark] takes a logo: the
/// initials of [name], then the first letter of [email], then the header's
/// person glyph. Every step down renders *something*, because a row with a hole
/// in it reads as a fault the reader has to look at rather than as an account
/// that has not filled in a name yet.
///
/// Shared rather than copied. It began as the profile panel's monogram; the
/// moment the roster wanted the same mark on every row, the alternative was a
/// second copy of the initials logic one edge case away from disagreeing with
/// the first about what an account with no name looks like.
class BrewPersonMark extends StatelessWidget {
  const BrewPersonMark({
    super.key,
    this.name,
    this.email,
    required this.dimension,
  });

  /// What they are called, if the account has said. First and last initial.
  final String? name;

  /// The fallback, as the first letter of the local part.
  ///
  /// Only a list of accounts passes this. The profile panel hands over a name
  /// alone and takes the glyph when there is none, because one mark at the top
  /// of a screen about a single account has nothing to be told apart from; a
  /// column of a dozen identical glyphs is no help in reading one row against
  /// the next.
  final String? email;

  final double dimension;

  /// The first [count] characters of [value], upper-cased.
  ///
  /// Code points rather than `substring`, which counts UTF-16 units and would cut
  /// an astral character in half — a name beginning with one drew a lone
  /// surrogate, which renders as a replacement box: a mark that looks like the
  /// rendering fault this widget's whole fallback chain exists to avoid.
  static String _lead(String value, int count) =>
      String.fromCharCodes(value.runes.take(count)).toUpperCase();

  String? get _initials {
    final named = name?.trim();
    if (named != null && named.isNotEmpty) {
      final parts = named.split(RegExp(r'\s+'));
      final first = _lead(parts.first, 1);
      final last = parts.length > 1 ? _lead(parts.last, 1) : '';
      return first + last;
    }

    // The local part, not the whole address: every account at one company would
    // otherwise draw whatever letter its shared domain starts with.
    final local = email?.trim().split('@').first ?? '';
    if (local.isEmpty) return null;

    // Two characters, not one. One is what a real roster breaks on: an account
    // list holding quickbrew@gmail.com and qldespino02@tip.edu.ph drew Q for
    // both, so the mark was actively unhelpful on exactly the screen it exists
    // to make scannable — and telling rows apart is the only thing it is for.
    // Two matches the width a named account already draws (first and last
    // initial), so a roster of mixed accounts reads as one column of marks
    // rather than a column of two different sizes of thing.
    return _lead(local, 2);
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials;

    return Container(
      width: dimension,
      height: dimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: BrewColor.hairline),
      ),
      child: initials == null
          ? BrewIconMark(
              icon: BrewIcon.profile,
              dimension: dimension * 0.4,
              color: BrewColor.iconInk,
            )
          : Text(
              initials,
              // Held at its drawn size, like the glyph it stands in for.
              //
              // The ring is a fixed box, so at 2x system text two initials wrap
              // inside it and the second one is clipped off the bottom — a mark
              // that reads as a rendering fault, which is the one thing this
              // widget's fallback chain exists to avoid. Exempting it costs the
              // reader nothing: every fact it draws is printed in full, at full
              // scale, in the row beside it.
              textScaler: TextScaler.noScaling,
              maxLines: 1,
              style: BrewType.displayAt(dimension * 0.36)
                  .copyWith(color: BrewColor.sageLight),
            ),
    );
  }
}
