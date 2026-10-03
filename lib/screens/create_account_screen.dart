import 'dart:math' as math;

import 'package:flutter/material.dart' show Material, Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../brew_auth.dart';
import '../form_rules.dart';
import '../theme/brew_type.dart';
import '../theme/tokens.dart';
import '../widgets/brew_background.dart';
import '../widgets/brew_buttons.dart';
import '../widgets/brew_field.dart';
import '../widgets/brew_reveal.dart';
import '../widgets/cup_mark.dart';
import '../widgets/stagger.dart';

/// Where Create an account goes.
///
/// The login screen's twin, deliberately: same masthead, same ruled fields,
/// same footer — one field more and one word different on the button. A sign-up
/// form that looked like a different product would be doing the reverse of what
/// this flow is for.
///
/// Three fields and no fourth. There is no confirm-password field, because the
/// password already has a reveal toggle beside it and asking twice is how you
/// get two typos instead of one. There is no terms checkbox either: this build
/// has no terms to agree to, and shipping a link to a document that doesn't
/// exist is worse than shipping neither.
///
/// This screen does not create the account; [onSubmit] does, and the screen owns
/// what that costs — the wait, and where the answer is displayed. It fires once
/// the form is locally valid and resolves to null on success or to the
/// [BrewAuthFailure] to show. The local rules in form_rules.dart are still only
/// shape checks: whether an address is already taken is not something this screen
/// can know, and it does not pretend to.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    super.key,
    this.onSubmit,
    this.onLogIn,
  });

  /// Fired with a trimmed name and email and the raw password. Resolves to null
  /// when the account exists, or to the failure to hang on the form.
  final Future<BrewAuthFailure?> Function(
    String name,
    String email,
    String password,
  )? onSubmit;

  /// The footer: the reader is already registered and took a wrong turn.
  final VoidCallback? onLogIn;

  /// Fades in like the login screen, and for the same reason: the header lockup
  /// sits in the same place on all three screens, so nothing should slide it.
  static Route<void> route({
    bool reduced = false,
    Future<BrewAuthFailure?> Function(
      String name,
      String email,
      String password,
    )? onSubmit,
    VoidCallback? onLogIn,
  }) {
    final duration = reduced ? Duration.zero : BrewMotion.transit;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          CreateAccountScreen(onSubmit: onSubmit, onLogIn: onLogIn),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _nameNode = FocusNode();
  final _emailNode = FocusNode();
  final _passwordNode = FocusNode();

  bool _obscure = true;
  bool _submitting = false;
  String? _nameError;
  String? _emailError;
  String? _passwordError;

  /// A rejection that belongs to neither field — no network, sign-up disabled.
  /// Held separately because it has nowhere to hang: the three field messages
  /// each have a rule to sit under, and this one does not.
  String? _formError;

  /// Header, tagline, headline, sub, three fields, show, Create account, footer.
  static const _staggerCount = 10;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _nameNode.dispose();
    _emailNode.dispose();
    _passwordNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // The button is already inert while a submit is in flight; this covers the
    // other way in, which is the keyboard's done key on the password field.
    if (_submitting) return;

    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;

    final nameError = BrewRules.name(name);
    final emailError = BrewRules.email(email, ifEmpty: 'Enter your email.');
    final passwordError = BrewRules.password(
      password,
      ifEmpty: 'Pick a password.',
    );

    setState(() {
      _nameError = nameError;
      _emailError = emailError;
      _passwordError = passwordError;
      // Whatever the server said last time is about the values it was given, so
      // it does not survive a fresh attempt.
      _formError = null;
    });

    // Every field reports at once — three separate round trips to find out
    // three things were wrong is the worst version of this form. Focus goes to
    // the first of them, so the fix starts where the reading does.
    final firstFailure = <(String?, FocusNode)>[
      (nameError, _nameNode),
      (emailError, _emailNode),
      (passwordError, _passwordNode),
    ].firstWhere((entry) => entry.$1 != null, orElse: () => (null, _nameNode));

    if (firstFailure.$1 != null) {
      firstFailure.$2.requestFocus();
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _submitting = true);
    final failure = await widget.onSubmit?.call(name, email, password);

    // The caller may well have navigated away on success — this screen is not
    // the one that decides what a created account leads to.
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _emailError = failure?.field == BrewAuthField.email
          ? failure!.message
          : null;
      _passwordError = failure?.field == BrewAuthField.password
          ? failure!.message
          : null;
      _formError = failure?.field == BrewAuthField.form
          ? failure!.message
          : null;
    });

    // Same rule as the local checks: put the caret where the fix is. A form-level
    // failure has no field to fix, so nothing moves and the message does the
    // talking.
    switch (failure?.field) {
      case BrewAuthField.email:
        _emailNode.requestFocus();
      case BrewAuthField.password:
        _passwordNode.requestFocus();
      case BrewAuthField.form:
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.height <= BrewSpace.compactHeight;
    final reduced = MediaQuery.disableAnimationsOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: BrewColor.field,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Material(
        color: BrewColor.field,
        child: BrewBackground(
          child: StaggerGroup(
              itemCount: _staggerCount,
              reveal: true,
              reduced: reduced,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final padding = EdgeInsets.only(
                    left: BrewSpace.gutter,
                    right: BrewSpace.gutter,
                    top: math.max(media.padding.top, BrewSpace.minInset) +
                        BrewSpace.headerClearance,
                    bottom: math.max(
                          media.padding.bottom,
                          BrewSpace.bottomGroupInset,
                        ) +
                        media.viewInsets.bottom,
                  );

                  final minHeight =
                      math.max(0.0, constraints.maxHeight - padding.vertical);

                  return SingleChildScrollView(
                    padding: padding,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: IntrinsicHeight(
                        child: AutofillGroup(child: _form(compact)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
  }

  Widget _form(bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaggerItem(index: 0, child: _header()),
        SizedBox(height: BrewSpace.grid * (compact ? 3 : 4)),
        StaggerItem(
          index: 1,
          child: Row(
            children: [
              Container(
                width: 18,
                height: 1.5,
                color: BrewColor.sageLight,
              ),
              const SizedBox(width: 8),
              Text(
                'GOOD COFFEE. BETTER DAYS.',
                style: BrewType.tagline.copyWith(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: BrewColor.sageLight,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        StaggerItem(
          index: 2,
          child: Text.rich(
            TextSpan(
              style: BrewType.displayAt(compact ? 30 : 38),
              children: const [
                TextSpan(text: 'Start ordering '),
                TextSpan(
                  text: 'ahead.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: BrewColor.sageLight,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 1.5),
        StaggerItem(
          index: 3,
          child: Text(
            'A name, an email, a password. Nothing else.',
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.8),
            ),
          ),
        ),
        const Spacer(flex: 3),
        StaggerItem(index: 4, child: _nameField()),
        const SizedBox(height: BrewSpace.grid * 2),
        StaggerItem(index: 5, child: _emailField()),
        const SizedBox(height: BrewSpace.grid * 2),
        StaggerItem(index: 6, child: _passwordField()),
        const SizedBox(height: 4),
        StaggerItem(
          index: 7,
          child: Align(
            alignment: Alignment.centerRight,
            child: BrewMonoButton(
              label: _obscure ? 'Show' : 'Hide',
              semanticsLabel: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 2),
        BrewReveal(
          child: switch (_formError) {
            final message? => Padding(
              padding: const EdgeInsets.only(bottom: BrewSpace.grid * 1.5),
              child: Semantics(
                liveRegion: true,
                child: Text(message, style: BrewType.fieldError),
              ),
            ),
            null => null,
          },
        ),
        StaggerItem(
          index: 8,
          child: BrewPrimaryButton(
            label: 'Create account',
            asPill: true,
            leading: const Icon(
              Icons.person_add_alt_1_outlined,
              size: 20,
              color: Color(0xFF13251A),
            ),
            trailing: const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: Color(0xFF13251A),
            ),
            busyLabel: _submitting ? 'Creating account…' : null,
            onPressed: _submit,
          ),
        ),
        const Spacer(flex: 2),
        StaggerItem(index: 9, child: _footer()),
      ],
    );
  }

  /// The same lockup as the other two screens, so the cup does not move.
  Widget _header() {
    final canPop = Navigator.of(context).canPop();

    return Row(
      children: [
        const ExcludeSemantics(
          child: CupMark(
            dimension: BrewMotion.cupLandingSize,
            progress: 1,
            strokeWidth: BrewMotion.cupLandingStroke,
          ),
        ),
        const SizedBox(width: BrewSpace.grid * 1.5),
        Text('QuickBrew', style: BrewType.wordmarkRow),
        if (canPop) ...[
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrewMonoButton(
                label: 'Back',
                semanticsLabel: 'Back to log in',
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_left_rounded,
                size: 18,
                color: BrewColor.sageLight,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _nameField() {
    return BrewField(
      label: 'Name',
      controller: _name,
      focusNode: _nameNode,
      hint: 'What the counter calls out',
      errorText: _nameError,
      keyboardType: TextInputType.name,
      textCapitalization: TextCapitalization.words,
      autofillHints: const [AutofillHints.name],
      cardStyle: true,
      leading: const Icon(
        Icons.person_outline_rounded,
        size: 20,
        color: BrewColor.cream,
      ),
      onChanged: (_) {
        if (_nameError != null) setState(() => _nameError = null);
      },
      onSubmitted: (_) => _emailNode.requestFocus(),
    );
  }

  Widget _emailField() {
    return BrewField(
      label: 'Email',
      controller: _email,
      focusNode: _emailNode,
      hint: 'you@work.com',
      errorText: _emailError,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email, AutofillHints.username],
      cardStyle: true,
      leading: const Icon(
        Icons.mail_outline_rounded,
        size: 20,
        color: BrewColor.cream,
      ),
      onChanged: (_) {
        if (_emailError != null) setState(() => _emailError = null);
      },
      onSubmitted: (_) => _passwordNode.requestFocus(),
    );
  }

  Widget _passwordField() {
    return BrewField(
      label: 'Password',
      controller: _password,
      focusNode: _passwordNode,
      hint: '••••••••',
      helper: 'AT LEAST ${BrewRules.minPassword} CHARACTERS',
      errorText: _passwordError,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newPassword],
      cardStyle: true,
      leading: const Icon(
        Icons.lock_outline_rounded,
        size: 20,
        color: BrewColor.cream,
      ),
      trailing: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() => _obscure = !_obscure),
          child: Icon(
            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 20,
            color: BrewColor.cream.withValues(alpha: 0.75),
          ),
        ),
      ),
      onChanged: (_) {
        if (_passwordError != null) setState(() => _passwordError = null);
      },
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _footer() {
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
              onTap: _submitting
                  ? null
                  : (widget.onLogIn ?? () => Navigator.of(context).maybePop()),
              child: Text(
                'I already have an account',
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
