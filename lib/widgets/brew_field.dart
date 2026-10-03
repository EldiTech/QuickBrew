import 'package:flutter/material.dart'
    show TextField, InputDecoration, InputBorder, Icons, Icon;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import 'brew_reveal.dart';

/// One ruled input, in the ledger's vernacular: a mono label, the typed ink,
/// and a hairline under it. No filled box, no rounded container, no floating
/// label — the same rule that separates the benefit rows on the landing screen
/// is what a field sits on.
///
/// The hairline is the whole state model. Cream while the field holds focus,
/// alert while it holds an error, 14% cream at rest.
class BrewField extends StatefulWidget {
  const BrewField({
    super.key,
    required this.label,
    required this.controller,
    this.focusNode,
    this.hint,
    this.helper,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.leading,
    this.cardStyle = false,
  });

  /// Uppercased here, so callers pass it in sentence case.
  final String label;

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hint;

  /// A standing note under the rule, in the mono label voice — the password
  /// requirement stated before it is broken rather than after. Yields to
  /// [errorText], since the two occupy the same line.
  final String? helper;

  /// Non-null puts the field in its error state: the rule turns alert and the
  /// message is hung under it.
  final String? errorText;

  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Sits inside the rule, right of the ink — the password toggle.
  final Widget? trailing;
  final Widget? leading;
  final bool cardStyle;

  @override
  State<BrewField> createState() => _BrewFieldState();
}

class _BrewFieldState extends State<BrewField> {
  FocusNode? _owned;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_owned ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(BrewField old) {
    super.didUpdateWidget(old);
    if (old.focusNode == widget.focusNode) return;
    old.focusNode?.removeListener(_onFocusChanged);
    _owned?.removeListener(_onFocusChanged);
    _node.addListener(_onFocusChanged);
    _onFocusChanged();
  }

  @override
  void dispose() {
    // Only the listener comes off a caller-owned node; the caller disposes it.
    widget.focusNode?.removeListener(_onFocusChanged);
    _owned?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted || _focused == _node.hasFocus) return;
    setState(() => _focused = _node.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final error = widget.errorText;

    // Error outranks focus: a field the user is fixing has to keep saying so
    // while they are typing in it.
    final rule = error != null
        ? BrewColor.alert
        : _focused
            ? BrewColor.fieldFocus
            : BrewColor.hairline;

    if (widget.cardStyle) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: reduced ? Duration.zero : BrewMotion.press,
            curve: BrewMotion.pressCurve,
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: rule, width: 1.0),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.leading case final leading?) ...[
                  leading,
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label.toUpperCase(),
                        style: BrewType.mono.copyWith(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: BrewColor.sageLight.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      TextField(
                        controller: widget.controller,
                        focusNode: _node,
                        obscureText: widget.obscureText,
                        obscuringCharacter: '•',
                        keyboardType: widget.keyboardType,
                        textInputAction: widget.textInputAction,
                        textCapitalization: widget.textCapitalization,
                        autofillHints: widget.autofillHints,
                        onChanged: widget.onChanged,
                        onSubmitted: widget.onSubmitted,
                        style: BrewType.fieldInk,
                        cursorColor: BrewColor.cream,
                        cursorWidth: 1.5,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: widget.hint,
                          hintStyle: BrewType.fieldHint.copyWith(
                            color: BrewColor.cream.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.trailing case final trailing?) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
              ],
            ),
          ),
          BrewReveal(
            gap: BrewSpace.grid * 0.75,
            child: switch ((error, widget.helper)) {
              (final error?, _) => Semantics(
                  liveRegion: true,
                  child: Text(error, style: BrewType.fieldError),
                ),
              (null, final helper?) => Padding(
                  padding: const EdgeInsets.only(top: 6.0, left: 4.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 13,
                        color: BrewColor.sageLight.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        helper,
                        style: BrewType.mono.copyWith(
                          fontSize: 10,
                          letterSpacing: 0.6,
                          color: BrewColor.cream.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              (null, null) => null,
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label.toUpperCase(), style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        AnimatedContainer(
          // The rule is a state change on a control, so it settles at the same
          // speed a button's fill does.
          duration: reduced ? Duration.zero : BrewMotion.press,
          curve: BrewMotion.pressCurve,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: rule)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _node,
                  obscureText: widget.obscureText,
                  obscuringCharacter: '•',
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  textCapitalization: widget.textCapitalization,
                  autofillHints: widget.autofillHints,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: BrewType.fieldInk,
                  cursorColor: BrewColor.cream,
                  cursorWidth: 1.5,
                  // The container owns the rule, so the field draws none of its
                  // own chrome in any state — including error, which is why the
                  // message below is hung by hand rather than through
                  // InputDecoration.errorText.
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.only(
                      top: BrewSpace.grid * 1.5,
                      bottom: BrewSpace.grid * 1.5,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: BrewType.fieldHint,
                  ),
                ),
              ),
              if (widget.trailing case final trailing?) ...[
                const SizedBox(width: BrewSpace.grid * 1.5),
                trailing,
              ],
            ],
          ),
        ),
        // One line under the rule, holding whichever of the two has something to
        // say. Revealed rather than switched on: the message pushes everything
        // below the field down, and on the login form that is the Log in button
        // moving out from under a thumb already travelling towards it.
        BrewReveal(
          gap: BrewSpace.grid * 0.75,
          child: switch ((error, widget.helper)) {
            // Announced, which it was not before. The message is hung here by
            // hand rather than through InputDecoration.errorText — see the note
            // on the decoration above — and hand-hung text is not something a
            // screen reader has any reason to read out: a reader who submitted
            // the form got silence and a caret in a field, with the one sentence
            // saying why sitting unspoken underneath it. Every form-level failure
            // in this app is already a live region; a field-level one is the same
            // kind of answer to the same press.
            (final error?, _) => Semantics(
              liveRegion: true,
              child: Text(error, style: BrewType.fieldError),
            ),
            (null, final helper?) => Text(
              helper.toUpperCase(),
              style: BrewType.mono,
            ),
            (null, null) => null,
          },
        ),
      ],
    );
  }
}
