import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';

/// One item's Firebase-sourced picture, drawn consistently wherever it appears.
///
/// Read-only surfaces draw nothing when Firebase has no stored image. The
/// optional [placeholder] is reserved for the admin upload control.
class BrewMenuItemImage extends StatelessWidget {
  const BrewMenuItemImage({
    super.key,
    required this.bytes,
    required this.dimension,
    this.itemName,
    this.placeholder = false,
  });

  final Uint8List? bytes;
  final double dimension;
  final String? itemName;
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
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
