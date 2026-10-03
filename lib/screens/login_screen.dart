import 'dart:math' as math;

import 'package:flutter/material.dart'
    show Colors, Icons, Material, showModalBottomSheet;
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

/// Where Log in goes.
///
/// Same ledger as the landing screen — left-aligned, hairline-ruled, no cards —
/// so the two read as one document rather than two designs. The header lockup
/// repeats in place, which is what carries the cup across the push.
///
/// The create-account screen's twin in how it behaves as well as how it looks:
/// this screen does not sign anybody in, [onSubmit] does, and the screen owns
/// what that costs — the wait, and where the answer is displayed. It fires once
/// the form is locally valid and resolves to null on success or to the
/// [BrewAuthFailure] to show. It does not navigate on success and is not told
/// where success goes; the session appearing is what moves the reader.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onSubmit,
    this.onResetPassword,
    this.onForgotPassword,
    this.onCreateAccount,
  });

  /// Fired with a trimmed email and the raw password once both pass validation.
  /// Resolves to null when the session exists, or to the failure to hang on the
  /// form.
  final Future<BrewAuthFailure?> Function(String email, String password)?
      onSubmit;

  final Future<BrewAuthFailure?> Function(String email)? onResetPassword;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onCreateAccount;

  /// Pushed as a fade, not a platform slide: the landing screen handed the cup
  /// over on opacity, and the header lockup sits in the same place on both
  /// screens, so a slide would drag a mark that should hold still.
  static Route<void> route({
    bool reduced = false,
    Future<BrewAuthFailure?> Function(String email, String password)? onSubmit,
    Future<BrewAuthFailure?> Function(String email)? onResetPassword,
    VoidCallback? onForgotPassword,
    VoidCallback? onCreateAccount,
  }) {
    final duration = reduced ? Duration.zero : BrewMotion.transit;
    return PageRouteBuilder<void>(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) => LoginScreen(
        onSubmit: onSubmit,
        onResetPassword: onResetPassword,
        onForgotPassword: onForgotPassword,
        onCreateAccount: onCreateAccount,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailNode = FocusNode();
  final _passwordNode = FocusNode();

  bool _obscure = true;
  bool _submitting = false;
  String? _emailError;
  String? _passwordError;

  /// A rejection that belongs to neither field. Log-in's most common one lives
  /// here: with email-enumeration protection on, a wrong address and a wrong
  /// password come back as the same code, and hanging that under either field
  /// would point at the half that may well have been right.
  String? _formError;

  /// Header, tagline, headline, sub, both fields, forgot, Log in, footer.
  static const _staggerCount = 9;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailNode.dispose();
    _passwordNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // The button is already inert while a submit is in flight; this covers the
    // other way in, which is the keyboard's done key on the password field.
    if (_submitting) return;

    final email = _email.text.trim();
    final password = _password.text;

    final emailError = BrewRules.email(
      email,
      ifEmpty: 'Enter the email you signed up with.',
    );
    final passwordError = BrewRules.password(
      password,
      ifEmpty: 'Enter your password.',
    );

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      // Whatever the server said last time is about the values it was given, so
      // it does not survive a fresh attempt.
      _formError = null;
    });

    // Focus the first field that failed, so the fix is one tap from the error.
    if (emailError != null) {
      _emailNode.requestFocus();
      return;
    }
    if (passwordError != null) {
      _passwordNode.requestFocus();
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _submitting = true);
    final failure = await widget.onSubmit?.call(email, password);

    // A successful log in takes this screen off the stack, so there may be
    // nothing left to report to.
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

    // Put the caret where the fix is. A form-level failure has no field to fix,
    // so nothing moves and the message does the talking.
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
                TextSpan(text: 'Welcome '),
                TextSpan(
                  text: 'back.',
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
            'Log in and the next cup starts on the walk over.',
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.8),
            ),
          ),
        ),
        const Spacer(flex: 3),
        StaggerItem(index: 4, child: _emailField()),
        const SizedBox(height: BrewSpace.grid * 2),
        StaggerItem(index: 5, child: _passwordField()),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            StaggerItem(
              index: 6,
              child: BrewMonoButton(
                label: 'Forgot password',
                onPressed: _handleForgotPassword,
              ),
            ),
            BrewMonoButton(
              label: _obscure ? 'Show' : 'Hide',
              semanticsLabel: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ],
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
          index: 7,
          child: BrewPrimaryButton(
            label: 'Log in',
            asPill: true,
            trailing: const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: Color(0xFF13251A),
            ),
            busyLabel: _submitting ? 'Logging in…' : null,
            onPressed: _submit,
          ),
        ),
        const Spacer(flex: 2),
        StaggerItem(index: 8, child: _footer()),
      ],
    );
  }

  /// The landing header, repeated: the cup at its landed size and stroke, the
  /// wordmark beside it.
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
                semanticsLabel: 'Back to the start',
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
      errorText: _passwordError,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
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
              onTap: _submitting ? null : widget.onCreateAccount,
              child: Text(
                'Create an account',
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

  void _handleForgotPassword() {
    if (widget.onForgotPassword != null) {
      widget.onForgotPassword!();
    } else if (widget.onResetPassword != null) {
      _openPasswordReset();
    }
  }

  Future<void> _openPasswordReset() async {
    final onReset = widget.onResetPassword;
    if (onReset == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PasswordResetSheet(
        initialEmail: _email.text.trim(),
        onReset: onReset,
      ),
    );
  }
}

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({
    required this.initialEmail,
    required this.onReset,
  });

  final String initialEmail;
  final Future<BrewAuthFailure?> Function(String email) onReset;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  late final TextEditingController _email;
  bool _submitting = false;
  String? _error;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final validation = BrewRules.email(email, ifEmpty: 'Enter your email address.');
    if (validation != null) {
      setState(() {
        _error = validation;
        _success = false;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _success = false;
    });

    final failure = await widget.onReset(email);
    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _submitting = false;
        _error = failure.message;
      });
    } else {
      setState(() {
        _submitting = false;
        _success = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return Container(
      decoration: const BoxDecoration(
        color: BrewColor.field,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        BrewSpace.grid * 3,
        BrewSpace.grid * 3,
        BrewSpace.grid * 3,
        BrewSpace.grid * 3 + insets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'RESET PASSWORD',
                style: BrewType.mono.copyWith(
                  letterSpacing: 1.4,
                  fontSize: 11,
                  color: BrewColor.sageLight,
                ),
              ),
              const Spacer(),
              BrewMonoButton(
                label: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 1.5),
          Text(
            'We will send a password reset link to your email address.',
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2.5),
          BrewField(
            label: 'Email',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: BrewSpace.grid),
            Text(_error!, style: BrewType.fieldError),
          ],
          if (_success) ...[
            const SizedBox(height: BrewSpace.grid * 1.5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: BrewColor.sage.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BrewColor.sageLight.withValues(alpha: 0.5)),
              ),
              child: Text(
                'Reset link sent! Check your inbox to choose a new password.',
                style: BrewType.rowBody.copyWith(color: BrewColor.sageLight),
              ),
            ),
          ],
          const SizedBox(height: BrewSpace.grid * 3),
          BrewPrimaryButton(
            label: _success ? 'Sent' : 'Send reset link',
            asPill: true,
            busyLabel: _submitting ? 'Sending…' : null,
            onPressed: _success ? null : _submit,
          ),
        ],
      ),
    );
  }
}
