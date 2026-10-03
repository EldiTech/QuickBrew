import 'dart:math' as math;

import 'package:flutter/material.dart' show Material, Icons, Icon;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../brew_admin.dart';
import '../../brew_counter.dart';
import '../../form_rules.dart';
import '../../theme/brew_type.dart';
import '../../theme/tokens.dart';
import '../../widgets/brew_background.dart';
import '../../widgets/brew_buttons.dart';
import '../../widgets/brew_choice.dart';
import '../../widgets/brew_field.dart';
import '../../widgets/brew_reveal.dart';
import '../../widgets/shop_mark.dart';
import '../../widgets/stagger.dart';
import 'admin_transitions.dart';

/// The one screen that makes "the super admin assigns the credentials" real:
/// an email, a password and a store, which together become a working admin
/// account the moment the button is pressed.
///
/// The super admin choosing the password is the point — they have to know it to
/// hand it over. It is worth being clear-eyed about what that means: from here
/// on, whoever created the account knows its password, so the admin should be
/// told to change it. This is the ordinary trade of provisioning somebody an
/// account rather than inviting them to make their own, and it is what "the
/// super admin will be the one who will assign that credentials" asks for.
///
/// See [BrewAdmin.createAdmin] for why creating an account here does not sign
/// the super admin out of their own session — the short version is that it
/// happens on a second, throwaway Firebase app.
class InviteAdminScreen extends StatefulWidget {
  const InviteAdminScreen({super.key, this.admin, this.shops, this.store});

  final BrewAdmin? admin;

  /// The shops as the dashboard last saw them, so the two options are labelled
  /// with what each store is actually called. Assigning somebody "Coffee Shop
  /// A" when the shop has been renamed is the kind of mismatch that has a super
  /// admin inviting the wrong person to the wrong place.
  final List<BrewShop>? shops;

  /// Which store the picker opens on. Null is the first of the two — the
  /// dashboard's own "Create an admin", which is not about either shop in
  /// particular.
  ///
  /// The Team screen passes one: it offers this form from inside the container
  /// of the shop that has nobody running it, and a form that opened on the other
  /// store would quietly undo the choice the reader had already made by pressing
  /// that button rather than the one above it.
  final BrewPartner? store;

  static Route<void> route({
    bool reduced = false,
    BrewAdmin? admin,
    List<BrewShop>? shops,
    BrewPartner? store,
  }) {
    return adminPageRoute<void>(
      reduced: reduced,
      builder: (context) =>
          InviteAdminScreen(admin: admin, shops: shops, store: store),
    );
  }

  @override
  State<InviteAdminScreen> createState() => _InviteAdminScreenState();
}

class _InviteAdminScreenState extends State<InviteAdminScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailNode = FocusNode();
  final _passwordNode = FocusNode();

  late BrewPartner _store = widget.store ?? BrewPartner.a;
  bool _obscure = true;
  bool _submitting = false;
  String? _emailError;
  String? _passwordError;
  String? _formError;

  /// The address the last admin account was created for, held only so the
  /// confirmation line can say it back — cleared the moment a field is touched.
  String? _createdFor;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailNode.dispose();
    _passwordNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final email = _email.text.trim();
    final password = _password.text;

    // The same two rules the create-account form applies, from the same place —
    // an admin's password is not a lesser password for being handed over.
    final emailError = BrewRules.email(
      email,
      ifEmpty: 'Enter their email.',
    );
    final passwordError = BrewRules.password(
      password,
      ifEmpty: 'Pick a password for them.',
    );

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _formError = null;
    });

    // Both report at once, and focus lands on the first that failed.
    if (emailError != null) {
      _emailNode.requestFocus();
      return;
    }
    if (passwordError != null) {
      _passwordNode.requestFocus();
      return;
    }

    final admin = widget.admin;
    if (admin == null) {
      setState(() => _formError = 'Accounts are not connected in this build.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submitting = true);
    final failure = await admin.createAdmin(
      email: email,
      password: password,
      store: _store,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _formError = failure;
      _createdFor = failure == null ? email : null;
      if (failure == null) {
        _email.clear();
        // Cleared on success so the next account cannot be created with the
        // previous one's password by a distracted second press.
        _password.clear();
      }
    });
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
            itemCount: 6,
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

                return SingleChildScrollView(
                  padding: padding,
                  child: _form(context, compact),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaggerItem(index: 0, child: _header(context)),
        SizedBox(height: BrewSpace.grid * (compact ? 3 : 4)),
        StaggerItem(index: 1, child: _titleLockup(compact)),
        SizedBox(height: BrewSpace.grid * (compact ? 3 : 3.5)),
        StaggerItem(index: 2, child: _storeCard(compact)),
        const SizedBox(height: BrewSpace.grid * 2.5),
        StaggerItem(index: 3, child: _credentialsCard()),
        const SizedBox(height: BrewSpace.grid * 3),
        StaggerItem(index: 4, child: _actionBlock()),
        const SizedBox(height: BrewSpace.grid * 3),
        StaggerItem(index: 5, child: _footer()),
      ],
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        BrewPressable(
          onPressed: _submitting ? null : () => Navigator.of(context).maybePop(),
          radius: 999,
          onPressedChanged: (_) {},
          reduced: MediaQuery.disableAnimationsOf(context),
          pressed: false,
          semanticsLabel: 'Back to team screen',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x6608140C),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: BrewColor.cream.withValues(alpha: 0.16),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back_rounded,
                  size: 15,
                  color: BrewColor.cream,
                ),
                const SizedBox(width: 6),
                Text(
                  'TEAM',
                  style: BrewType.mono.copyWith(
                    fontSize: 10.5,
                    letterSpacing: 1.1,
                    color: BrewColor.cream,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: BrewColor.sage.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: BrewColor.sage.withValues(alpha: 0.5),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings_rounded,
                size: 14,
                color: BrewColor.sageLight,
              ),
              const SizedBox(width: 5),
              Text(
                'SUPERADMIN',
                style: BrewType.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: BrewColor.sageLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _titleLockup(bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BrewColor.cream.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: BrewColor.cream.withValues(alpha: 0.14),
                ),
              ),
              child: Text(
                'ONBOARDING & PROVISIONING',
                style: BrewType.mono.copyWith(
                  fontSize: 9.5,
                  letterSpacing: 1.5,
                  color: BrewColor.sageLight,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: BrewSpace.grid),
        Text('Create an admin.', style: BrewType.displayAt(compact ? 28 : 34)),
        const SizedBox(height: BrewSpace.grid * 0.75),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            'Provision login credentials and associate them directly with a store location.',
            style: BrewType.rowBody.copyWith(
              color: BrewColor.cream.withValues(alpha: 0.76),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  /// The shop currently selected, as the dashboard last saw it.
  BrewShop get _selectedShop =>
      widget.shops?.where((shop) => shop.partner == _store).firstOrNull ??
      BrewShop(partner: _store, status: BrewShopStatus.pending);

  Widget _storeCard(bool compact) {
    final shop = _selectedShop;
    final reduced = MediaQuery.disableAnimationsOf(context);

    return _AdminGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 15,
                color: BrewColor.sageLight,
              ),
              const SizedBox(width: 7),
              Text(
                'TARGET LOCATION',
                style: BrewType.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: BrewColor.sageLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: BrewColor.cream.withValues(alpha: 0.18),
                    width: 1.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: AnimatedSwitcher(
                  duration: reduced ? Duration.zero : BrewMotion.transit,
                  switchInCurve: BrewMotion.crossFadeCurve,
                  switchOutCurve: BrewMotion.crossFadeCurve,
                  child: BrewShopMark(
                    key: ValueKey(shop.partner),
                    shop: shop,
                    dimension: 50,
                  ),
                ),
              ),
              const SizedBox(width: BrewSpace.grid * 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.displayName,
                      style: BrewType.rowTitle.copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      shop.description ?? 'Assigned Store Location',
                      style: BrewType.rowBody.copyWith(
                        fontSize: 12,
                        color: BrewColor.cream.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 2.5),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, partner) in BrewPartner.values.indexed) ...[
                  if (index > 0) const SizedBox(width: BrewSpace.grid * 1.5),
                  Expanded(
                    child: BrewChoice(
                      label: BrewShop.nameOf(partner, widget.shops),
                      selected: partner == _store,
                      onSelected: _submitting
                          ? null
                          : () => setState(() {
                              _store = partner;
                              _createdFor = null;
                            }),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _credentialsCard() {
    return _AdminGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.badge_outlined,
                size: 15,
                color: BrewColor.sageLight,
              ),
              const SizedBox(width: 7),
              Text(
                'ACCOUNT CREDENTIALS',
                style: BrewType.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: BrewColor.sageLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          BrewField(
            label: 'Admin Email',
            controller: _email,
            focusNode: _emailNode,
            hint: 'admin@work.com',
            errorText: _emailError,
            cardStyle: true,
            leading: const Icon(
              Icons.mail_outline_rounded,
              size: 16,
              color: BrewColor.sageLight,
            ),
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) {
              if (_emailError != null || _createdFor != null) {
                setState(() {
                  _emailError = null;
                  _createdFor = null;
                });
              }
            },
            onSubmitted: (_) => _passwordNode.requestFocus(),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          BrewField(
            label: 'Initial Password',
            controller: _password,
            focusNode: _passwordNode,
            hint: '••••••••',
            helper: 'At least ${BrewRules.minPassword} characters',
            errorText: _passwordError,
            obscureText: _obscure,
            cardStyle: true,
            leading: const Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: BrewColor.sageLight,
            ),
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_passwordError != null || _createdFor != null) {
                setState(() {
                  _passwordError = null;
                  _createdFor = null;
                });
              }
            },
            onSubmitted: (_) => _submit(),
            trailing: BrewMonoButton(
              label: _obscure ? 'Show' : 'Hide',
              semanticsLabel: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2.5),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: BrewSpace.grid * 2,
              vertical: BrewSpace.grid * 1.75,
            ),
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: BrewColor.cream.withValues(alpha: 0.1),
                width: 1.0,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: BrewColor.sageLight,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You are provisioning this account directly. Share the temporary password securely and instruct the admin to update it upon first login.',
                    style: BrewType.rowBody.copyWith(
                      fontSize: 12,
                      color: BrewColor.cream.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrewReveal(
          child: switch (_createdFor) {
            final email? => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: BrewSpace.grid * 2),
                padding: const EdgeInsets.all(BrewSpace.grid * 2),
                decoration: BoxDecoration(
                  color: const Color(0xEB132218),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: BrewColor.sageLight.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: BrewColor.sageLight,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$email is now an active administrator for ${BrewShop.nameOf(_store, widget.shops)}.',
                        style: BrewType.rowBody.copyWith(
                          fontSize: 13,
                          color: BrewColor.cream,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            null => null,
          },
        ),
        BrewReveal(
          child: switch (_formError) {
            final message? => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: BrewSpace.grid * 2),
                padding: const EdgeInsets.all(BrewSpace.grid * 2),
                decoration: BoxDecoration(
                  color: BrewColor.alert.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: BrewColor.alert.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 20,
                      color: BrewColor.alert,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: BrewType.fieldError,
                      ),
                    ),
                  ],
                ),
              ),
            null => null,
          },
        ),
        BrewPrimaryButton(
          label: 'Create admin account',
          asPill: true,
          busyLabel: _submitting ? 'Creating admin…' : null,
          leading: const Icon(
            Icons.person_add_alt_1_rounded,
            size: 18,
            color: Color(0xFF13251A),
          ),
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }

  Widget _footer() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 14,
          color: BrewColor.cream.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Created admins can immediately be managed on the Team screen.',
            style: BrewType.rowBody.copyWith(
              fontSize: 12,
              color: BrewColor.cream.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _AdminGlassCard extends StatelessWidget {
  const _AdminGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BrewSpace.grid * 2.5),
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.12),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
