import 'package:flutter/material.dart'
    show
        Colors,
        Icon,
        Icons,
        Material,
        SelectableText,
        showModalBottomSheet;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../brew_admin.dart';
import '../../brew_counter.dart';
import '../../theme/brew_type.dart';
import '../../theme/tokens.dart';
import '../../widgets/brew_background.dart';
import '../../widgets/brew_buttons.dart';
import '../../widgets/brew_choice.dart';
import '../../widgets/brew_field.dart';
import '../../widgets/brew_reveal.dart';
import '../../widgets/brew_sheet.dart';
import '../../widgets/person_mark.dart';
import '../../widgets/shop_mark.dart';
import '../../widgets/stagger.dart';
import 'admin_transitions.dart';
import 'invite_admin_screen.dart';

/// Who runs the two coffee shops, and the app's own customers — the super
/// admin's answer to "who can touch what", and the one place it gets changed.
///
/// Two blocks, behind a tab bar reading Admin and User rather than both
/// stacked down the page — the two questions rarely get asked in the same
/// breath. Neither is picked for the reader: the screen opens blank, with only
/// the tab bar and a sentence naming what each button is for, because a
/// default of "Admin" would be answering a question nobody had asked yet on
/// every visit that came here for the other one.
///
/// Admin shows the pair of shops, each a bounded container holding the accounts
/// assigned to run it — the same block the dashboard's store cards and the
/// profile panel's account panel are drawn as, because two shops is a fixed pair
/// of equal-weight facts rather than a list that grows. The flat roster this
/// replaced answered "who runs each shop" badly: it meant reading a store name
/// off the end of every row and keeping a tally in your head to notice that one
/// of the two shops had nobody running it at all.
///
/// User shows the roster: every customer, each held in its own bounded card —
/// the same border and radius the shop block draws two of. A customer is a fact
/// this screen acts on, not a history to read the way the Orders screen's
/// hairline-ruled rows are, so it takes the shops' contained shape instead of
/// that one. Admins and the super admin are deliberately left out of it —
/// this block is the app's answer to "who are the actual users", and restating
/// who runs a shop would be answering a different question in the same list.
/// The tally beside its heading counts what is on screen, which under this
/// block is always the whole roster.
///
/// Every row in both blocks carries the same three controls: View, which
/// expands the row in place to show the one fact neither block otherwise
/// prints — the account's uid and when it first signed up — and changes
/// nothing; Edit, which sets a person's role and the store that goes with it;
/// and Remove, which takes their record off whichever block is showing it.
/// Edit and Remove were once "do it in the Firebase console"; the console is
/// still where an account's *sign-in* lives, which is why [_RemoveSheet] is
/// careful about the difference. One account has one editor regardless of
/// which block opened it, because it is the same three fields either way.
///
/// A super admin is not listed under either shop, and is not in the roster
/// either. They configure both blocks and are assigned to neither, so a
/// container claiming one of them would be answering "who runs this shop" with
/// somebody who equally runs the other — and there is deliberately no in-app
/// path to the superadmin role at all, so the last one to demote or delete
/// themselves would leave nobody able to grant it again. firestore.rules
/// refuses both writes independently; keeping their own row off both blocks
/// means that refusal is never something the reader has to discover by being
/// denied.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, this.admin, this.shops, this.currentUid});

  final BrewAdmin? admin;

  /// The shops as the dashboard last saw them, so a container can name the store
  /// it is about — and a row the store an admin is assigned to — using whatever
  /// that store is currently called rather than [BrewPartner]'s built-in copy.
  final List<BrewShop>? shops;

  /// Who is reading. Their own row loses its controls — see the class comment.
  final String? currentUid;

  static Route<void> route({
    bool reduced = false,
    BrewAdmin? admin,
    List<BrewShop>? shops,
    String? currentUid,
  }) {
    return adminPageRoute<void>(
      reduced: reduced,
      builder: (context) => UsersScreen(
        admin: admin,
        shops: shops,
        currentUid: currentUid,
      ),
    );
  }

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  /// What the last edit or removal had to say, if it was not simply "done", and
  /// which account it was about.
  ///
  /// Held by the screen rather than by the sheet that started it: the sheet is
  /// closed and disposed the moment it hands back a draft, so it is not around
  /// to report what Firestore said about the write it asked for.
  ///
  /// It carries the uid because one account is now drawn in two places — under
  /// its shop, and in the roster — and a single message parked at the bottom of
  /// the screen would be reporting on a write the reader started two blocks up,
  /// out of sight. Whichever row was pressed is the row that says what happened.
  ({String uid, String message})? _failure;

  /// The account a write is in flight for, so that one row goes quiet while it
  /// lands instead of every row in the list going unresponsive.
  String? _busy;

  /// Which of the two blocks below is on screen. Toggled by [_sectionBar].
  /// Opens null (blank) until the reader selects a filter.
  _TeamSection? _section;

  /// The roster, subscribed to once.
  late final Stream<List<BrewUserProfile>>? _people = widget.admin?.users();

  String? _failureFor(String uid) {
    final failure = _failure;
    return (failure != null && failure.uid == uid) ? failure.message : null;
  }

  /// The accounts assigned to run one shop.
  List<BrewUserProfile>? _adminsOf(
    BrewPartner partner,
    List<BrewUserProfile>? people,
  ) {
    return people
        ?.where(
          (person) =>
              person.role == BrewRole.admin && person.assignedStore == partner,
        )
        .toList();
  }

  BrewShop _shopFor(BrewPartner partner) {
    return widget.shops?.where((shop) => shop.partner == partner).firstOrNull ??
        BrewShop(partner: partner, status: BrewShopStatus.pending);
  }

  Future<void> _edit(BrewUserProfile person) async {
    final draft = await showModalBottomSheet<_StandingDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF5101E15),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _StandingSheet(person: person, shops: widget.shops),
    );

    final admin = widget.admin;
    if (draft == null || admin == null || !mounted) return;

    setState(() {
      _busy = person.uid;
      _failure = null;
    });
    final failure = await admin.setUserStanding(
      uid: person.uid,
      role: draft.role,
      store: draft.store,
      name: draft.name,
    );

    if (!mounted) return;
    setState(() {
      _busy = null;
      _failure = failure == null ? null : (uid: person.uid, message: failure);
    });
  }

  Future<void> _remove(BrewUserProfile person) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF5101E15),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _RemoveSheet(person: person),
    );

    final admin = widget.admin;
    if (confirmed != true || admin == null || !mounted) return;

    setState(() {
      _busy = person.uid;
      _failure = null;
    });
    final failure = await admin.deleteUser(person.uid);

    if (!mounted) return;
    setState(() {
      _busy = null;
      _failure = failure == null ? null : (uid: person.uid, message: failure);
    });
  }

  void _createAdminFor(BrewPartner store) {
    Navigator.of(context).push(
      InviteAdminScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        admin: widget.admin,
        shops: widget.shops,
        store: store,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.height <= BrewSpace.compactHeight;

    const tabIndex = 3;
    const shopsLabelIndex = tabIndex + 1;
    const shopsBase = shopsLabelIndex + 1;
    const rosterIndex = tabIndex + 1;

    final staggerCount = switch (_section) {
      null => tabIndex + 2,
      _TeamSection.admin => shopsBase + BrewPartner.values.length,
      _TeamSection.user => rosterIndex + 1,
    };

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
          child: StreamBuilder<List<BrewUserProfile>>(
            stream: _people,
            builder: (context, snapshot) {
              final people = snapshot.data;
              final adminCount = people
                      ?.where((p) => p.role == BrewRole.admin)
                      .length ??
                  0;
              final userCount = people
                      ?.where((p) => p.role == BrewRole.customer)
                      .length ??
                  0;

              return BrewSheet(
                staggerCount: staggerCount,
                children: [
                  StaggerItem(index: 0, child: _header(context)),
                  SizedBox(height: brewBlockGap(compact)),
                  StaggerItem(index: 1, child: _titleLockup(compact)),
                  SizedBox(height: brewBlockGap(compact)),
                  StaggerItem(
                    index: tabIndex,
                    child: _sectionBar(adminCount, userCount),
                  ),
                  SizedBox(height: brewBlockGap(compact)),
                  switch (_section) {
                    null => StaggerItem(
                        index: tabIndex + 1,
                        child: Text(
                          'Pick Admin to see who runs each shop, or User to inspect the customer roster.',
                          style: BrewType.rowBody.copyWith(
                            color: BrewColor.cream.withValues(alpha: 0.76),
                          ),
                        ),
                      ),
                    _TeamSection.admin => Column(
                        key: const ValueKey(_TeamSection.admin),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StaggerItem(
                            index: shopsLabelIndex,
                            child: const _SectionLabel('Store Administrators'),
                          ),
                          const SizedBox(height: BrewSpace.grid * 1.5),
                          _shopsSection(people, shopsBase),
                        ],
                      ),
                    _TeamSection.user => Column(
                        key: const ValueKey(_TeamSection.user),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StaggerItem(
                            index: rosterIndex,
                            child: _rosterSection(people),
                          ),
                        ],
                      ),
                  },
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        BrewPressable(
          onPressed: () => Navigator.of(context).maybePop(),
          radius: 999,
          onPressedChanged: (_) {},
          reduced: MediaQuery.disableAnimationsOf(context),
          pressed: false,
          semanticsLabel: 'Back to admin dashboard',
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
                  'DASHBOARD',
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
                'TEAM ROSTER & ROLES',
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
        Text('Team & Access.', style: BrewType.displayAt(compact ? 28 : 34)),
        const SizedBox(height: BrewSpace.grid * 0.75),
        Text(
          'Who runs each shop, and what every account may configure.',
          style: BrewType.rowBody.copyWith(
            color: BrewColor.cream.withValues(alpha: 0.76),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _shopsSection(List<BrewUserProfile>? people, int base) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (position, partner) in BrewPartner.values.indexed) ...[
          if (position > 0) const SizedBox(height: BrewSpace.grid * 2),
          StaggerItem(
            index: base + position,
            child: _ShopTeamCard(
              shop: _shopFor(partner),
              admins: _adminsOf(partner, people),
              connected: widget.admin != null,
              currentUid: widget.currentUid,
              busyUid: _busy,
              failureFor: _failureFor,
              onEdit: widget.admin == null ? null : _edit,
              onRemove: widget.admin == null ? null : _remove,
              onCreate: widget.admin == null
                  ? null
                  : () => _createAdminFor(partner),
            ),
          ),
        ],
      ],
    );
  }

  Widget _rosterSection(List<BrewUserProfile>? people) {
    final customers = people
        ?.where((person) => person.role == BrewRole.customer)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionLabel('Customer Accounts')),
            if (customers != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: BrewColor.sage.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _accounts(customers.length).toUpperCase(),
                  style: BrewType.mono.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: BrewColor.sageLight,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: BrewSpace.grid),
        Text(
          'Edit sets an account role and store assignment. Remove deletes their profile from the roster.',
          style: BrewType.rowBody.copyWith(
            fontSize: 13,
            color: BrewColor.cream.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: BrewSpace.grid * 2.5),
        _roster(customers),
      ],
    );
  }

  void _selectSection(_TeamSection section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  Widget _sectionBar(int adminCount, int userCount) {
    final isReduced = MediaQuery.disableAnimationsOf(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x6608140C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentTab(
              label: 'ADMIN',
              icon: Icons.storefront_rounded,
              count: adminCount,
              selected: _section == _TeamSection.admin,
              onTap: () => _selectSection(_TeamSection.admin),
              reduced: isReduced,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SegmentTab(
              label: 'USER',
              icon: Icons.people_alt_rounded,
              count: userCount,
              selected: _section == _TeamSection.user,
              onTap: () => _selectSection(_TeamSection.user),
              reduced: isReduced,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roster(List<BrewUserProfile>? people) {
    if (widget.admin == null) {
      return Text(
        'Accounts are not connected in this build.',
        style: BrewType.rowBody,
      );
    }
    if (people == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Checking accounts…', style: BrewType.rowBody),
        ),
      );
    }
    if (people.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(BrewSpace.grid * 3),
        decoration: BoxDecoration(
          color: const Color(0xEB132218),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BrewColor.cream.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 36,
              color: BrewColor.cream.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text('No accounts yet.', style: BrewType.rowBody),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, person) in people.indexed) ...[
          if (index > 0) const SizedBox(height: BrewSpace.grid * 2),
          _PersonCard(
            person: person,
            you: person.uid == widget.currentUid,
            busy: _busy == person.uid,
            failure: _failureFor(person.uid),
            onEdit: () => _edit(person),
            onRemove: () => _remove(person),
          ),
        ],
      ],
    );
  }
}

String _accounts(int count) => count == 1 ? '1 account' : '$count accounts';

class _AccountDetail extends StatelessWidget {
  const _AccountDetail({required this.person});

  final BrewUserProfile person;

  @override
  Widget build(BuildContext context) {
    final joined = person.createdAt;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: BrewSpace.grid * 1.5),
      padding: const EdgeInsets.all(BrewSpace.grid * 1.5),
      decoration: BoxDecoration(
        color: const Color(0x4D000000),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: BrewColor.cream.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fingerprint_rounded,
                size: 14,
                color: BrewColor.sageLight,
              ),
              const SizedBox(width: 6),
              Text(
                'UID',
                style: BrewType.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: BrewColor.sageLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            person.uid,
            style: BrewType.mono.copyWith(
              fontSize: 11,
              color: BrewColor.cream.withValues(alpha: 0.85),
            ),
          ),
          if (joined != null) ...[
            const SizedBox(height: BrewSpace.grid * 1.5),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 13,
                  color: BrewColor.sageLight,
                ),
                const SizedBox(width: 6),
                Text(
                  'JOINED',
                  style: BrewType.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: BrewColor.sageLight,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _joinedOn(joined),
                  style: BrewType.rowBody.copyWith(
                    fontSize: 12,
                    color: BrewColor.cream,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _joinedOn(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

enum _TeamSection { admin, user }

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.reduced,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return BrewPressable(
      onPressed: onTap,
      radius: 12,
      onPressedChanged: (_) {},
      reduced: reduced,
      pressed: false,
      semanticsLabel:
          '$label, ${count == 1 ? '1 account' : '$count accounts'}, ${selected ? 'showing' : 'tap to show'}',
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : BrewMotion.press,
        curve: BrewMotion.pressCurve,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3224) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? BrewColor.cream.withValues(alpha: 0.25)
                : Colors.transparent,
            width: 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? BrewColor.sageLight
                  : BrewColor.cream.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrewType.mono.copyWith(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? BrewColor.cream
                      : BrewColor.cream.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: selected
                    ? BrewColor.sage.withValues(alpha: 0.3)
                    : BrewColor.cream.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: BrewType.mono.copyWith(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? BrewColor.sageLight
                      : BrewColor.cream.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(label.toUpperCase(), style: BrewType.mono),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider({this.gap = BrewSpace.grid * 1.5});

  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: BrewColor.hairline),
      ),
    );
  }
}

class _ShopTeamCard extends StatelessWidget {
  const _ShopTeamCard({
    required this.shop,
    required this.admins,
    required this.connected,
    this.currentUid,
    this.busyUid,
    required this.failureFor,
    this.onEdit,
    this.onRemove,
    this.onCreate,
  });

  final BrewShop shop;
  final List<BrewUserProfile>? admins;
  final bool connected;
  final String? currentUid;
  final String? busyUid;
  final String? Function(String uid) failureFor;
  final ValueChanged<BrewUserProfile>? onEdit;
  final ValueChanged<BrewUserProfile>? onRemove;
  final VoidCallback? onCreate;

  static const _markSize = 48.0;

  String get _staffing {
    if (!connected) return 'Staffing unavailable';
    final admins = this.admins;
    if (admins == null) return 'Checking';
    return switch (admins.length) {
      0 => 'No admin assigned',
      1 => '1 admin',
      final count => '$count admins',
    };
  }

  @override
  Widget build(BuildContext context) {
    final admins = this.admins;
    final hasAdmins = admins?.isNotEmpty ?? false;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: BrewColor.cream.withValues(alpha: 0.15),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: BrewShopMark(shop: shop, dimension: _markSize),
              ),
              const SizedBox(width: BrewSpace.grid * 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.displayName,
                      style: BrewType.rowTitle.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: hasAdmins
                            ? BrewColor.sage.withValues(alpha: 0.18)
                            : BrewColor.alert.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hasAdmins
                              ? BrewColor.sage.withValues(alpha: 0.4)
                              : BrewColor.alert.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _staffing.toUpperCase(),
                        style: BrewType.mono.copyWith(
                          fontSize: 9.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: hasAdmins
                              ? BrewColor.sageLight
                              : BrewColor.alert,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (admins != null) ...[
            const _RowDivider(gap: BrewSpace.grid * 2),
            if (admins.isEmpty) ...[
              Text(
                'No administrators assigned to this location yet.',
                style: BrewType.rowBody.copyWith(
                  fontSize: 13,
                  color: BrewColor.cream.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: BrewSpace.grid * 2),
              BrewPrimaryButton(
                label: 'CREATE AN ADMIN',
                asPill: true,
                leading: const Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 18,
                  color: Color(0xFF13251A),
                ),
                onPressed: onCreate,
              ),
            ] else ...[
              for (final (index, person) in admins.indexed) ...[
                if (index > 0) const _RowDivider(gap: BrewSpace.grid * 2),
                _ShopAdminRow(
                  person: person,
                  you: person.uid == currentUid,
                  busy: busyUid == person.uid,
                  failure: failureFor(person.uid),
                  onEdit: onEdit == null ? null : () => onEdit!(person),
                  onRemove: onRemove == null ? null : () => onRemove!(person),
                ),
              ],
              const SizedBox(height: BrewSpace.grid * 2),
              BrewPressable(
                onPressed: onCreate,
                radius: 8,
                onPressedChanged: (_) {},
                reduced: MediaQuery.disableAnimationsOf(context),
                pressed: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x33000000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: BrewColor.cream.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: BrewColor.sageLight,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ASSIGN ANOTHER ADMIN',
                        style: BrewType.mono.copyWith(
                          fontSize: 10.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                          color: BrewColor.sageLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ShopAdminRow extends StatefulWidget {
  const _ShopAdminRow({
    required this.person,
    this.you = false,
    this.busy = false,
    this.failure,
    this.onEdit,
    this.onRemove,
  });

  final BrewUserProfile person;
  final bool you;
  final bool busy;
  final String? failure;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  State<_ShopAdminRow> createState() => _ShopAdminRowState();
}

class _ShopAdminRowState extends State<_ShopAdminRow> {
  bool _expanded = false;
  static const _markSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final person = widget.person;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: BrewColor.cream.withValues(alpha: 0.18),
                ),
              ),
              child: BrewPersonMark(
                name: person.name,
                email: person.email,
                dimension: _markSize,
              ),
            ),
            const SizedBox(width: BrewSpace.grid * 1.5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          person.name ?? person.identifier,
                          style: BrewType.rowTitle.copyWith(fontSize: 14.5),
                        ),
                      ),
                      if (widget.you)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: BrewColor.cream.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'YOU',
                            style: BrewType.mono.copyWith(
                              fontSize: 9,
                              color: BrewColor.cream,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (person.name != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      person.identifier,
                      style: BrewType.rowBody.copyWith(
                        fontSize: 12,
                        color: BrewColor.cream.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                  const SizedBox(height: BrewSpace.grid * 1.5),
                  Row(
                    children: [
                      if (widget.you)
                        _UserActionButton(
                          icon: _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.info_outline_rounded,
                          label: _expanded ? 'HIDE' : 'VIEW',
                          onTap: () => setState(() => _expanded = !_expanded),
                        )
                      else ...[
                        Expanded(
                          child: _UserActionButton(
                            icon: _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.info_outline_rounded,
                            label: _expanded ? 'HIDE' : 'VIEW',
                            onTap: () => setState(() => _expanded = !_expanded),
                          ),
                        ),
                        const SizedBox(width: BrewSpace.grid),
                        Expanded(
                          child: _UserActionButton(
                            icon: Icons.edit_outlined,
                            label: widget.busy ? 'SAVING…' : 'EDIT',
                            onTap: widget.busy ? null : widget.onEdit,
                          ),
                        ),
                        const SizedBox(width: BrewSpace.grid),
                        Expanded(
                          child: _UserActionButton(
                            icon: Icons.delete_outline_rounded,
                            label: 'REMOVE',
                            alert: true,
                            onTap: widget.busy ? null : widget.onRemove,
                          ),
                        ),
                      ],
                    ],
                  ),
                  BrewReveal(
                    gap: BrewSpace.grid,
                    child: _expanded ? _AccountDetail(person: person) : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        BrewReveal(
          gap: BrewSpace.grid,
          child: switch (widget.failure) {
            final message? => Semantics(
                liveRegion: true,
                child: Text(message, style: BrewType.fieldError),
              ),
            null => null,
          },
        ),
      ],
    );
  }
}

class _PersonCard extends StatefulWidget {
  const _PersonCard({
    required this.person,
    this.you = false,
    this.busy = false,
    this.failure,
    this.onEdit,
    this.onRemove,
  });

  final BrewUserProfile person;
  final bool you;
  final bool busy;
  final String? failure;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard> {
  bool _expanded = false;
  static const _markSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final person = widget.person;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x33000000),
                  border: Border.all(
                    color: BrewColor.cream.withValues(alpha: 0.2),
                  ),
                ),
                child: BrewPersonMark(
                  name: person.name,
                  email: person.email,
                  dimension: _markSize,
                ),
              ),
              const SizedBox(width: BrewSpace.grid * 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            person.name ?? person.identifier,
                            style: BrewType.rowTitle.copyWith(fontSize: 15),
                          ),
                        ),
                        if (widget.you) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: BrewColor.cream.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'YOU',
                              style: BrewType.mono.copyWith(
                                fontSize: 9.5,
                                color: BrewColor.cream,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (person.role != BrewRole.customer)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: BrewColor.sage.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: BrewColor.sage.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              person.role.label.toUpperCase(),
                              style: BrewType.mono.copyWith(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: BrewColor.sageLight,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (person.name != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.mail_outline_rounded,
                            size: 13,
                            color: BrewColor.cream.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              person.identifier,
                              style: BrewType.rowBody.copyWith(
                                fontSize: 12.5,
                                color: BrewColor.cream.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (person.createdAt case final joined?) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: BrewColor.cream.withValues(alpha: 0.4),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Joined ${_joinedOn(joined)}',
                            style: BrewType.mono.copyWith(
                              fontSize: 10,
                              color: BrewColor.cream.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          Row(
            children: [
              if (widget.you)
                _UserActionButton(
                  icon: _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.info_outline_rounded,
                  label: _expanded ? 'HIDE' : 'VIEW',
                  onTap: () => setState(() => _expanded = !_expanded),
                )
              else ...[
                Expanded(
                  child: _UserActionButton(
                    icon: _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.info_outline_rounded,
                    label: _expanded ? 'HIDE' : 'VIEW',
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
                ),
                const SizedBox(width: BrewSpace.grid),
                Expanded(
                  child: _UserActionButton(
                    icon: Icons.edit_outlined,
                    label: widget.busy ? 'SAVING…' : 'EDIT',
                    onTap: widget.busy ? null : widget.onEdit,
                  ),
                ),
                const SizedBox(width: BrewSpace.grid),
                Expanded(
                  child: _UserActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'REMOVE',
                    alert: true,
                    onTap: widget.busy ? null : widget.onRemove,
                  ),
                ),
              ],
            ],
          ),
          BrewReveal(
            gap: BrewSpace.grid * 1.5,
            child: _expanded ? _AccountDetail(person: person) : null,
          ),
          BrewReveal(
            gap: BrewSpace.grid,
            child: switch (widget.failure) {
              final message? => Semantics(
                  liveRegion: true,
                  child: Text(message, style: BrewType.fieldError),
                ),
              null => null,
            },
          ),
        ],
      ),
    );
  }
}

class _UserActionButton extends StatefulWidget {
  const _UserActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.alert = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool alert;

  @override
  State<_UserActionButton> createState() => _UserActionButtonState();
}

class _UserActionButtonState extends State<_UserActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onTap != null;
    final color = widget.alert
        ? BrewColor.alert
        : (widget.label == 'EDIT' ? BrewColor.sageLight : BrewColor.cream);

    return BrewPressable(
      onPressed: widget.onTap,
      onPressedChanged: (v) => setState(() => _pressed = v),
      radius: 8,
      pressed: _pressed,
      reduced: reduced,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : BrewMotion.press,
        curve: BrewMotion.pressCurve,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          color: _pressed
              ? color.withValues(alpha: 0.15)
              : (widget.alert
                  ? BrewColor.alert.withValues(alpha: 0.08)
                  : const Color(0x33000000)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.alert
                ? BrewColor.alert.withValues(alpha: 0.35)
                : BrewColor.cream.withValues(alpha: 0.14),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 12.5, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrewType.mono.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: enabled ? color : color.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StandingDraft {
  const _StandingDraft({required this.role, this.store, this.name});

  final BrewRole role;
  final BrewPartner? store;
  final String? name;
}

class _StandingSheet extends StatefulWidget {
  const _StandingSheet({required this.person, this.shops});

  final BrewUserProfile person;
  final List<BrewShop>? shops;

  @override
  State<_StandingSheet> createState() => _StandingSheetState();
}

class _StandingSheetState extends State<_StandingSheet> {
  late final _name = TextEditingController(text: widget.person.name ?? '');
  late BrewRole _role = widget.person.role;
  late BrewPartner _store = widget.person.assignedStore ?? BrewPartner.a;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      _StandingDraft(role: _role, store: _store, name: _name.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 2,
        bottom: media.viewInsets.bottom + BrewSpace.grid * 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: BrewColor.cream.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          Text('Edit access.', style: BrewType.displayAt(24)),
          const SizedBox(height: BrewSpace.grid),
          Row(
            children: [
              Icon(
                Icons.mail_outline_rounded,
                size: 14,
                color: BrewColor.cream.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                widget.person.identifier,
                style: BrewType.rowBody.copyWith(
                  color: BrewColor.cream.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          BrewField(
            label: 'Name',
            controller: _name,
            hint: 'Not set',
            helper: 'Display greeting name.',
            cardStyle: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          _rolePicker(),
          BrewReveal(
            gap: BrewSpace.grid * 3,
            child: _role == BrewRole.admin ? _storePicker() : null,
          ),
          const SizedBox(height: BrewSpace.grid * 4),
          BrewPrimaryButton(
            label: 'Save',
            asPill: true,
            leading: const Icon(
              Icons.check_circle_outline_rounded,
              size: 18,
              color: Color(0xFF13251A),
            ),
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _rolePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ASSIGN ROLE', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        for (final (index, role) in BrewRole.values.indexed) ...[
          if (index > 0) const SizedBox(height: BrewSpace.grid),
          SizedBox(
            width: double.infinity,
            child: BrewChoice(
              label: role.label,
              selected: role == _role,
              onSelected: () => setState(() => _role = role),
            ),
          ),
        ],
      ],
    );
  }

  Widget _storePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ASSIGN STORE', style: BrewType.mono),
        const SizedBox(height: BrewSpace.grid),
        Row(
          children: [
            for (final (index, partner) in BrewPartner.values.indexed) ...[
              if (index > 0) const SizedBox(width: BrewSpace.grid * 1.5),
              Expanded(
                child: BrewChoice(
                  label: BrewShop.nameOf(partner, widget.shops),
                  selected: partner == _store,
                  onSelected: () => setState(() => _store = partner),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RemoveSheet extends StatelessWidget {
  const _RemoveSheet({required this.person});

  final BrewUserProfile person;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 2,
        bottom: media.viewInsets.bottom + BrewSpace.grid * 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: BrewColor.cream.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          Text('Remove this record.', style: BrewType.displayAt(24)),
          const SizedBox(height: BrewSpace.grid),
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 15,
                color: BrewColor.cream.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                person.identifier,
                style: BrewType.rowTitle.copyWith(fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: BrewSpace.grid * 2.5),
          Container(
            padding: const EdgeInsets.all(BrewSpace.grid * 2),
            decoration: BoxDecoration(
              color: BrewColor.alert.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BrewColor.alert.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: BrewColor.alert,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'CONSEQUENCE',
                      style: BrewType.mono.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: BrewColor.alert,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${person.role.label} standing is revoked, along with any store assigned to it, and this row leaves the roster.',
                  style: BrewType.rowBody.copyWith(fontSize: 13),
                ),
                const SizedBox(height: BrewSpace.grid * 1.5),
                Text(
                  'Their login credentials are not deleted — they can still log in as a customer with no store. Remove login credentials in Firebase console.',
                  style: BrewType.rowBody.copyWith(
                    fontSize: 12,
                    color: BrewColor.cream.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 3),
          BrewPrimaryButton(
            label: 'Remove record',
            asPill: true,
            leading: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: Color(0xFF13251A),
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: BrewSpace.grid * 1.5),
          BrewTextButton(
            label: 'Keep it',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
