import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import 'brew_icons.dart';

/// Press feedback for both actions: down 1px, fill darkens 6%, 90ms.
///
/// There are deliberately no hover states and no scale. This is a touch target,
/// and hover polish shipped to a phone is a tell. The only pointer-specific
/// affordance kept is the cursor, which is not a visual state on the control.
///
/// The two numbers now live in [BrewMotion] rather than here. They were always
/// the whole app's press behaviour and not this file's — the shop cards, the tab
/// bar, the choice pickers and the field rules all had their own copy of the 90 —
/// so the value belongs beside the rest of the motion vocabulary.

/// The primary action: cream fill, field ink, 56px, full width inside the
/// gutter, 4px radius — committed, matching the letterpress-label vernacular.
///
/// Its label is centred, matching every other button in the set.
class BrewPrimaryButton extends StatefulWidget {
  const BrewPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busyLabel,
    this.asPill = false,
    this.leading,
    this.trailing,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? busyLabel;
  final bool asPill;
  final Widget? leading;
  final Widget? trailing;

  @override
  State<BrewPrimaryButton> createState() => _BrewPrimaryButtonState();
}

class _BrewPrimaryButtonState extends State<BrewPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final busyLabel = widget.busyLabel;
    final busy = busyLabel != null;

    final radius = widget.asPill ? 999.0 : BrewSpace.radius;
    final bg = widget.asPill ? const Color(0xFFEADBCA) : BrewColor.cream;
    final height = widget.asPill ? 54.0 : BrewSpace.grid * 7;

    return BrewPressable(
      onPressed: busy ? null : widget.onPressed,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: radius,
      haptic: HapticFeedback.lightImpact,
      pressed: _pressed || busy,
      reduced: reduced,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : BrewMotion.press,
        curve: BrewMotion.pressCurve,
        height: height,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (_pressed || busy)
              ? BrewColor.darken(bg, 0.08)
              : bg,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.leading case final leading?) ...[
              leading,
              const SizedBox(width: 8),
            ],
            Text(
              busyLabel ?? widget.label,
              style: BrewType.buttonLabel.copyWith(
                color: widget.asPill ? const Color(0xFF13251A) : BrewColor.field,
                fontWeight: widget.asPill ? FontWeight.w600 : FontWeight.w700,
              ),
            ),
            if (widget.trailing case final trailing?) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}

/// The secondary action: text only, cream at 80%, 48px, centred. Two filled
/// buttons of near-equal weight would destroy the hierarchy.
class BrewTextButton extends StatefulWidget {
  const BrewTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.ink,
    this.asPill = false,
    this.pillColor,
    this.pillTextColor,
    this.pillHeight,
  });

  final String label;
  final VoidCallback? onPressed;

  /// The resting ink, for the one case where secondary cream is the wrong
  /// answer: a control that destroys something. Null keeps
  /// [BrewType.secondaryLabel]'s cream at 80% — see [BrewMonoButton.ink],
  /// which this mirrors.
  final Color? ink;

  /// Whether to render as a prominent pill-shaped button.
  final bool asPill;
  final Color? pillColor;
  final Color? pillTextColor;
  final double? pillHeight;

  @override
  State<BrewTextButton> createState() => _BrewTextButtonState();
}

class _BrewTextButtonState extends State<BrewTextButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    if (widget.asPill) {
      final bg = widget.pillColor ?? const Color(0xFFEADBCA);
      final fg = widget.pillTextColor ?? const Color(0xFF13251A);

      return BrewPressable(
        onPressed: widget.onPressed,
        onPressedChanged: (value) => setState(() => _pressed = value),
        radius: 999,
        pressed: _pressed,
        reduced: reduced,
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : BrewMotion.press,
          curve: BrewMotion.pressCurve,
          height: widget.pillHeight ?? 54,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _pressed ? BrewColor.darken(bg, 0.08) : bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'Hanken Grotesk',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      );
    }

    final ink = widget.ink;
    final label = ink == null
        ? BrewType.secondaryLabel
        : BrewType.secondaryLabel.copyWith(color: ink);

    return BrewPressable(
      onPressed: widget.onPressed,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      pressed: _pressed,
      reduced: reduced,
      child: SizedBox(
        height: BrewSpace.grid * 6,
        width: double.infinity,
        child: Align(
          child: AnimatedDefaultTextStyle(
            duration: reduced ? Duration.zero : BrewMotion.press,
            curve: BrewMotion.pressCurve,
            style: _pressed
                ? label.copyWith(color: BrewColor.darken(label.color!, 0.06))
                : label,
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}

/// The utility action: the mono label voice, sage-light, in a 44px tap target.
/// The password toggle and the forgot-password link, and nothing heavier —
/// putting either in the secondary button's 16px cream would have them
/// competing with Log in.
///
/// The label is uppercased here, so callers pass it in sentence case.
class BrewMonoButton extends StatefulWidget {
  const BrewMonoButton({
    super.key,
    required this.label,
    this.onPressed,
    this.semanticsLabel,
    this.ink,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Read instead of the label, which is a four-letter abbreviation once
  /// uppercased and does not say enough on its own.
  final String? semanticsLabel;

  /// The resting ink, for the one case where sage-light is the wrong answer:
  /// a control that destroys something.
  ///
  /// Null is the ordinary utility action and keeps [BrewType.mono]'s sage-light.
  /// Passing [BrewColor.alert] is how Remove on the roster tells itself apart
  /// from the Edit sitting beside it — see `_PersonRow` in
  /// screens/admin/users_screen.dart, where the two were previously identical
  /// down to the pixel despite one of them being irreversible.
  ///
  /// The pressed state is cream either way: brightening to the primary ink is
  /// what every mono label in the set does under a thumb, and a destructive
  /// control is not exempt from behaving like a control.
  final Color? ink;

  @override
  State<BrewMonoButton> createState() => _BrewMonoButtonState();
}

class _BrewMonoButtonState extends State<BrewMonoButton> {
  bool _pressed = false;

  /// Below the 44px minimum the mono label would be a 10px tap target.
  static const _tapTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final ink = widget.ink;
    final label = ink == null ? BrewType.mono : BrewType.mono.copyWith(color: ink);

    return BrewPressable(
      onPressed: widget.onPressed,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      pressed: _pressed,
      reduced: reduced,
      child: SizedBox(
        height: _tapTarget,
        // Shrink-wrapped, unlike the other two: a full-width tap target here
        // would mean the whole row under the password field activates Forgot
        // password. The 44px is height only.
        child: IntrinsicWidth(
          child: Align(
            child: AnimatedDefaultTextStyle(
              duration: reduced ? Duration.zero : BrewMotion.press,
              curve: BrewMotion.pressCurve,
              style: _pressed
                  ? label.copyWith(color: BrewColor.cream)
                  : label,
              child: Text(
                widget.label.toUpperCase(),
                semanticsLabel: widget.semanticsLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The header action: a mark in a 44px target, and no label.
///
/// The only control in the set with nothing to read, which is why
/// [semanticsLabel] is required rather than optional — an unlabelled icon button
/// is announced as "button" and nothing else. The mark brightens to cream on
/// press, the same move the mono label makes, because a 22px outline has no fill
/// to darken.
class BrewIconButton extends StatefulWidget {
  const BrewIconButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    this.onPressed,
  });

  final BrewIcon icon;

  /// A sentence fragment naming the destination — "Notifications", "Your
  /// profile" — not a description of the drawing.
  final String semanticsLabel;

  final VoidCallback? onPressed;

  /// Matches [BrewMonoButton]: below this the mark would be a 22px target.
  static const tapTarget = 44.0;

  @override
  State<BrewIconButton> createState() => _BrewIconButtonState();
}

class _BrewIconButtonState extends State<BrewIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return BrewPressable(
      onPressed: widget.onPressed,
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: BrewSpace.radius,
      pressed: _pressed,
      reduced: MediaQuery.disableAnimationsOf(context),
      semanticsLabel: widget.semanticsLabel,
      child: SizedBox.square(
        dimension: BrewIconButton.tapTarget,
        child: Center(
          child: BrewIconMark(
            icon: widget.icon,
            color: _pressed ? BrewColor.cream : BrewColor.iconInk,
          ),
        ),
      ),
    );
  }
}

/// Shared gesture, focus and press-offset behaviour for every action in the set.
///
/// Public because the home screen's shop cards are controls too: a card is one
/// button the size of a block, and it has to take a press, a focus ring and a
/// screen-reader announcement identically to a 56px one. Reimplementing that on
/// the card is how a design system grows two press behaviours.
class BrewPressable extends StatelessWidget {
  const BrewPressable({
    super.key,
    required this.child,
    required this.pressed,
    required this.reduced,
    required this.radius,
    required this.onPressedChanged,
    this.onPressed,
    this.haptic,
    this.semanticsLabel,
  });

  final Widget child;
  final bool pressed;
  final bool reduced;
  final double radius;
  final ValueChanged<bool> onPressedChanged;
  final VoidCallback? onPressed;
  final VoidCallback? haptic;

  /// For a control whose child has no text of its own to be announced.
  final String? semanticsLabel;

  void _activate() {
    if (onPressed == null) return;
    haptic?.call();
    onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    // A 1px drop is not the motion prefers-reduced-motion is guarding against,
    // but suppressing it costs nothing and leaves colour as the whole signal.
    final offset = (pressed && !reduced) ? BrewMotion.pressDrop : 0.0;
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: _FocusRing(
        radius: radius,
        onActivate: _activate,
        enabled: enabled,
        child: GestureDetector(
          // Without this only the label glyphs are tappable, not the block.
          behavior: HitTestBehavior.opaque,
          // Gated on `enabled`, so a disabled control neither reports a press
          // nor animates as though it took one.
          onTap: enabled ? _activate : null,
          onTapDown: enabled ? (_) => onPressedChanged(true) : null,
          onTapUp: enabled ? (_) => onPressedChanged(false) : null,
          onTapCancel: enabled ? () => onPressedChanged(false) : null,
          child: AnimatedContainer(
            duration: reduced ? Duration.zero : BrewMotion.press,
            curve: BrewMotion.pressCurve,
            transform: Matrix4.translationValues(0, offset, 0),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A 2px sage-light ring, 2px clear of the control, shown only for keyboard
/// focus. Painted outside the child's bounds so it never shifts layout.
class _FocusRing extends StatefulWidget {
  const _FocusRing({
    required this.child,
    required this.radius,
    required this.onActivate,
    required this.enabled,
  });

  final Widget child;
  final double radius;
  final VoidCallback onActivate;
  final bool enabled;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  bool _showRing = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: widget.enabled,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) {
        if (_showRing != value) setState(() => _showRing = value);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
      },
      child: CustomPaint(
        foregroundPainter: _RingPainter(
          visible: _showRing,
          radius: widget.radius,
        ),
        child: widget.child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.visible, required this.radius});

  final bool visible;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;

    // Offset by the gap plus half the stroke so the ring sits fully clear.
    final inflate = BrewSpace.focusOffset + BrewSpace.focusRing / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ).inflate(inflate),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = BrewSpace.focusRing
        ..color = BrewColor.sageLight,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.visible != visible || old.radius != radius;
}
