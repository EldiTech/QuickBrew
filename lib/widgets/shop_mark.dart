import 'package:flutter/widgets.dart';

import '../brew_counter.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';

/// A shop's logo, or its monogram until there is one.
///
/// Three sources in a fixed order, and the order is the whole point: an
/// uploaded logo ([BrewShop.logoBytes]) wins, then a hosted one
/// ([BrewShop.logoUrl]), then the partner's monogram. Every step down that
/// chain is a fallback that renders *something* — never a broken-image glyph
/// and never an empty box, because a shop card with a hole in it reads as a
/// bug the reader has to look at rather than as a shop that has not sent
/// artwork yet.
///
/// Shared rather than reimplemented per screen: the home screen, the admin
/// dashboard and the store editor all draw this, and three copies of a
/// fallback chain is three places for one of them to forget the last step.
class BrewShopMark extends StatelessWidget {
  const BrewShopMark({
    super.key,
    required this.shop,
    required this.dimension,
  });

  final BrewShop shop;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final bytes = shop.logoBytes;
    final url = shop.logoUrl;

    return Container(
      width: dimension,
      height: dimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: BrewColor.hairline),
        borderRadius: BorderRadius.circular(BrewSpace.radius),
      ),
      // The border stays under a real logo, so supplied artwork and a monogram
      // occupy the identical box and two cards cannot end up different shapes
      // depending on which partner has uploaded something.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BrewSpace.radius),
        child: switch ((bytes, url)) {
          (final bytes?, _) => Image.memory(
            bytes,
            width: dimension,
            height: dimension,
            fit: BoxFit.cover,
            // Already-decoded bytes still fail if they are not an image format
            // the engine knows.
            errorBuilder: (context, error, stack) => _monogram(),
          ),
          (_, final url?) => Image.network(
            url,
            width: dimension,
            height: dimension,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _monogram(),
            // The monogram holds the slot while the bytes are in flight, so the
            // card does not reflow when they land.
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _monogram(),
          ),
          _ => _monogram(),
        },
      ),
    );
  }

  Widget _monogram() => Center(
    child: Text(
      shop.partner.monogram,
      style: BrewType.displayAt(dimension * 0.46)
          .copyWith(color: BrewColor.sageLight),
    ),
  );
}
