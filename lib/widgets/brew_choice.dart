import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import 'brew_buttons.dart';

/// One option out of a small fixed set, as a choice rather than a card —
/// selected reads the way a focused field does: its hairline brightens to
/// cream.
///
/// There is no third state and no way to select neither. A row of these always
/// has exactly one chosen, which is what makes them a choice rather than a set
/// of checkboxes, and it is why the caller holds the selection rather than this
/// widget.
///
/// Shared rather than copied. It began as the store picker on the create-admin
/// form; the moment the users screen needed the same control for picking a role
/// out of three, the alternative was a second sixty-line copy sitting one
/// padding value away from drifting out of step with the first — which is
/// exactly the drift [brewBlockGap](brew_sheet.dart) exists to prevent.
class BrewChoice extends StatefulWidget {
  const BrewChoice({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
  });

  /// What this option is called, in sentence case — resolved by the caller,
  /// since a live shop name lives in Firestore and an enum only carries its
  /// identity.
  final String label;

  final bool selected;

  /// Null disables the option: nothing to save to, or a save already in
  /// flight.
  final VoidCallback? onSelected;

  @override
  State<BrewChoice> createState() => _BrewChoiceState();
}

class _BrewChoiceState extends State<BrewChoice> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final rule = (widget.selected || _pressed)
        ? BrewColor.fieldFocus
        : BrewColor.hairline;

    return BrewPressable(
      onPressed: widget.onSelected,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      // Deliberately not `_pressed`: the hairline above is the whole press
      // signal here, and a 1px drop on one of a pair of side-by-side options
      // reads as the row losing its baseline rather than as a press.
      pressed: false,
      reduced: reduced,
      semanticsLabel:
          widget.selected ? '${widget.label}, selected' : widget.label,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : BrewMotion.press,
          curve: BrewMotion.pressCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: BrewSpace.grid * 2,
            vertical: BrewSpace.grid * 2,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: rule),
            borderRadius: BorderRadius.circular(BrewSpace.radius),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: widget.selected
                ? BrewType.rowTitle
                : BrewType.rowTitle.copyWith(color: BrewColor.sageLight),
          ),
        ),
      ),
    );
  }
}
