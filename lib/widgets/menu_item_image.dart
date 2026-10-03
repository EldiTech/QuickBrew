import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';

/// One item's picture, drawn identically everywhere it appears: the admin's
/// add/edit sheet, the board row underneath it, and the customer-facing menu.
///
/// Unlike [BrewShopMark](shop_mark.dart), there is no letter to fall back to
/// — a latte has no monogram — so an item with no picture draws nothing at
/// all, the same way a missing [BrewMenuItem.description] or
/// [BrewMenuItem.price] prints nothing rather than a placeholder.
///
/// The one exception is [placeholder], for the admin sheet: a *form* needs
/// somewhere to press even when there is nothing to show yet, and collapsing
/// to zero width there left the upload control as a bare 10px mono label
/// stacked under an identically-styled caption — see the sheet's picture row.
/// Read-only surfaces (the board, the customer menu) leave it false and keep
/// drawing nothing.
class BrewMenuItemImage extends StatelessWidget {
  const BrewMenuItemImage({
    super.key,
    required this.bytes,
    required this.dimension,
    this.placeholder = false,
  });

  final Uint8List? bytes;
  final double dimension;

  /// Draws an empty frame rather than nothing when [bytes] is null.
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    if (image == null) {
      if (!placeholder) return const SizedBox.shrink();

      return Container(
        width: dimension,
        height: dimension,
        decoration: BoxDecoration(
          border: Border.all(color: BrewColor.hairline),
          borderRadius: BorderRadius.circular(BrewSpace.radius),
        ),
        alignment: Alignment.center,
        // A single glyph rather than a word: at 56px there is room for one
        // mark, and the row's own label already says NO PICTURE in words.
        child: Text(
          '+',
          style: BrewType.mono.copyWith(fontSize: 20, letterSpacing: 0),
        ),
      );
    }

    return Container(
      width: dimension,
      height: dimension,
      decoration: BoxDecoration(
        border: Border.all(color: BrewColor.hairline),
        borderRadius: BorderRadius.circular(BrewSpace.radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BrewSpace.radius),
        child: Image.memory(
          image,
          width: dimension,
          height: dimension,
          fit: BoxFit.cover,
          // Already-decoded bytes still fail if they are not an image format
          // the engine knows.
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
