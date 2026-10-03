import 'package:flutter/material.dart' show Material, Icons, Icon;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../brew_admin.dart';
import '../../brew_counter.dart';
import '../../theme/brew_type.dart';
import '../../theme/tokens.dart';
import '../../widgets/brew_background.dart';
import '../../widgets/brew_buttons.dart';
import '../../widgets/brew_field.dart';
import '../../widgets/brew_reveal.dart';
import '../../widgets/brew_sheet.dart';
// The QR preview, borrowed from the board: a payment code and a menu picture
// are the same widget's job — bounded bytes in a hairline frame, with a
// placeholder for the not-yet-uploaded case a form needs.
import '../../widgets/menu_item_image.dart';
import '../../widgets/shop_mark.dart';
import '../../widgets/stagger.dart';
import 'admin_addons_screen.dart';
import 'admin_menu_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_transitions.dart';

/// One store, end to end: whether it is taking orders, its logo, and the
/// board — the three things [BrewCounter] reads for the customer side, now
/// with a write beside each.
///
/// Reached only from [AdminHomeScreen](admin_home_screen.dart)'s store card,
/// so it never has to ask again which store it is configuring, and never asks
/// whether the signed-in account may configure it — that question was
/// answered by which card was tappable.
class StoreConfigScreen extends StatefulWidget {
  const StoreConfigScreen({
    super.key,
    required this.partner,
    this.admin,
    this.counter,
  });

  final BrewPartner partner;

  /// Null if Firestore is unreachable. Every control still renders; none of
  /// them can save.
  final BrewAdmin? admin;
  final BrewCounter? counter;

  static Route<void> route({
    bool reduced = false,
    required BrewPartner partner,
    BrewAdmin? admin,
    BrewCounter? counter,
  }) {
    return adminPageRoute<void>(
      reduced: reduced,
      builder: (context) =>
          StoreConfigScreen(partner: partner, admin: admin, counter: counter),
    );
  }

  @override
  State<StoreConfigScreen> createState() => _StoreConfigScreenState();
}

class _StoreConfigScreenState extends State<StoreConfigScreen> {
  Stream<List<BrewShop>>? _shops;

  /// Subscribed once, the same reason every other stream on this screen is:
  /// this is what the Orders tile reads its unattended-orders count from,
  /// so opening a fresh listener on every rebuild would ask Firestore for
  /// the same query on every frame.
  Stream<List<BrewOrder>>? _orders;

  /// The last snapshot anything on this run took, as the first frame's answer.
  ///
  /// Worth more here than on a card: without it this screen opens on the enum's
  /// built-in name in the display line and two empty fields, then fills all three
  /// in a beat later — and the empty fields are the state [_identityPrimed]
  /// refuses to save from, so the Save button starts out disabled saying
  /// "Loading…" for a screen whose data the app already had. Read once: an admin
  /// editing this shop is the reason the stream will change, and priming has to
  /// happen from a value that is not moving under them.
  late final List<BrewShop>? _known = widget.counter?.lastShops;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  /// Set once the identity fields have been primed from the first snapshot.
  ///
  /// Without it, every later snapshot — including the one the admin's own save
  /// produces — would overwrite the text they are part-way through typing. The
  /// stream is the source of truth for what is *stored*; the controllers are
  /// the source of truth for what is being *edited*, and only the first
  /// snapshot is allowed to cross between them.
  bool _identityPrimed = false;

  bool _savingIdentity = false;
  bool _savingLogo = false;
  bool _savingQr = false;

  /// What the last save or pick had to say, if it was not simply "done".
  ///
  /// One per section rather than one per screen: a refused board write reported
  /// at the top of the page would be commenting on something the reader did three
  /// blocks down, and the section that took the press is the section that owes
  /// them the answer.
  String? _identityError;
  String? _logoError;
  String? _qrError;
  String? _hoursError;

  @override
  void initState() {
    super.initState();
    _shops = widget.counter?.shops();
    _orders = widget.admin?.ordersFor(widget.partner);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  BrewShop? _shopOf(List<BrewShop>? shops) =>
      shops?.where((shop) => shop.partner == widget.partner).firstOrNull;

  Future<void> _saveIdentity() async {
    final admin = widget.admin;
    if (admin == null) return;

    // Refuses to save until the fields have been filled from Firestore.
    //
    // This is a data-loss guard, not a nicety. Before the first snapshot lands
    // both controllers are empty while the screen still *looks* populated — the
    // hint prints the built-in name in grey and the display line above falls
    // back to it too — so a save inside that window would send two empty
    // strings, which [BrewAdmin.setShopIdentity] stores as null, wiping the
    // shop's real name and description for every customer. The window is a
    // round trip on a cold cache and unbounded while offline.
    if (!_identityPrimed) return;

    setState(() {
      _savingIdentity = true;
      _identityError = null;
    });
    try {
      await admin.setShopIdentity(
        widget.partner,
        name: _nameController.text,
        description: _descriptionController.text,
      );
    } catch (error) {
      debugPrint('QuickBrew → could not save ${widget.partner.id}: $error');
      if (mounted) {
        setState(() => _identityError = 'That did not save. Try again.');
      }
    }
    if (!mounted) return;
    setState(() => _savingIdentity = false);
  }

  /// Picks an image, downscales it on the way in, and stores it as base64.
  ///
  /// The resizing is done by the picker rather than after the fact: `maxWidth`,
  /// `maxHeight` and `imageQuality` are handled natively on each platform, so a
  /// 12-megapixel phone photo never reaches Dart as 40MB of pixels only to be
  /// thrown away. 512 square at quality 75 lands around 40–80KB, which encodes
  /// well inside [BrewAdmin.maxLogoChars] — and the mark it feeds is 56px, so
  /// there is nothing to gain from more.
  Future<void> _pickLogo() async {
    final admin = widget.admin;
    if (admin == null) return;

    setState(() => _logoError = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      // Null means they backed out of the picker, which is not a failure and
      // should say nothing.
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _savingLogo = true);
      final failure = await admin.setShopLogoBase64(widget.partner, bytes);
      if (!mounted) return;
      setState(() {
        _savingLogo = false;
        _logoError = failure;
      });
    } catch (error) {
      debugPrint('QuickBrew → logo pick failed: $error');
      if (!mounted) return;
      setState(() {
        _savingLogo = false;
        _logoError = 'Could not read that image. Try another.';
      });
    }
  }

  Future<void> _removeLogo() async {
    final admin = widget.admin;
    if (admin == null) return;
    setState(() {
      _savingLogo = true;
      _logoError = null;
    });
    String? failure;
    try {
      failure = await admin.setShopLogoBase64(widget.partner, null);
      // The hosted URL goes too. Leaving it behind would have "Remove" reveal an
      // old logo the admin thought they had deleted, which is worse than either
      // keeping or clearing both.
      await admin.setShopLogo(widget.partner, null);
    } catch (error) {
      // Without this the throw skips the setState below, leaving _savingLogo
      // true for the life of the screen — which holds Replace and Remove
      // disabled with the label stuck on "Saving", and there is no way back
      // except leaving and returning.
      debugPrint('QuickBrew → could not clear ${widget.partner.id} logo: $error');
      failure = 'That did not go through. Try again.';
    }
    if (!mounted) return;
    setState(() {
      _savingLogo = false;
      _logoError = failure;
    });
  }

  /// Picks the shop's payment QR, the same way [_pickLogo] picks its mark, at
  /// twice the resolution and higher quality.
  ///
  /// 1024 at quality 90 rather than 512 at 75, because the two pictures are
  /// asked to survive completely different things. A logo has to look right at
  /// 56px, where compression artefacts are invisible; a QR has to be *read by a
  /// camera* at whatever size the customer's phone draws it, and the blocking
  /// that a heavy JPEG pass leaves along a code's edges is what turns a scan
  /// into three failed scans and a trip to the counter. It still encodes well
  /// inside [BrewAdmin.maxLogoChars].
  Future<void> _pickQr() async {
    final admin = widget.admin;
    if (admin == null) return;

    setState(() => _qrError = null);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _savingQr = true);
      final failure = await admin.setShopPayQrBase64(widget.partner, bytes);
      if (!mounted) return;
      setState(() {
        _savingQr = false;
        _qrError = failure;
      });
    } catch (error) {
      debugPrint('QuickBrew → QR pick failed: $error');
      if (!mounted) return;
      setState(() {
        _savingQr = false;
        _qrError = 'Could not read that image. Try another.';
      });
    }
  }

  Future<void> _removeQr() async {
    final admin = widget.admin;
    if (admin == null) return;
    setState(() {
      _savingQr = true;
      _qrError = null;
    });
    String? failure;
    try {
      failure = await admin.setShopPayQrBase64(widget.partner, null);
    } catch (error) {
      // Same guard [_removeLogo] explains: without it a throw leaves _savingQr
      // true for the life of the screen, and both controls stuck on "Saving".
      debugPrint('QuickBrew → could not clear ${widget.partner.id} QR: $error');
      failure = 'That did not go through. Try again.';
    }
    if (!mounted) return;
    setState(() {
      _savingQr = false;
      _qrError = failure;
    });
  }

  /// Whether a store is taking orders, and what Firestore said about being told.
  ///
  /// The toggle draws itself from the stream rather than from a local flag, so a
  /// refused write leaves it exactly where it was — correct, and completely
  /// silent unless the failure is reported. Hence the sentence.
  Future<void> _setOpen(bool open) async {
    final admin = widget.admin;
    if (admin == null) return;

    setState(() => _hoursError = null);
    final failure = await admin.setShopOpen(widget.partner, open);
    if (!mounted) return;
    setState(() => _hoursError = failure);
  }

  void _openOrders(BuildContext context) {
    Navigator.of(context).push(
      AdminOrdersScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        partner: widget.partner,
        admin: widget.admin,
      ),
    );
  }

  void _openMenu(BuildContext context) {
    Navigator.of(context).push(
      AdminMenuScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        partner: widget.partner,
        admin: widget.admin,
        counter: widget.counter,
      ),
    );
  }

  void _openAddOns(BuildContext context) {
    Navigator.of(context).push(
      AdminAddOnsScreen.route(
        reduced: MediaQuery.disableAnimationsOf(context),
        partner: widget.partner,
        admin: widget.admin,
        counter: widget.counter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.height <= BrewSpace.compactHeight;

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
          child: StreamBuilder<List<BrewShop>>(
            stream: _shops,
            initialData: _known,
            builder: (context, snapshot) {
              final shop = _shopOf(snapshot.data);

              if (!_identityPrimed && shop != null) {
                _nameController.text = shop.name ?? shop.partner.name;
                _descriptionController.text =
                    shop.description ?? shop.partner.description;
                _identityPrimed = true;
              }

              final preview = shop ??
                  BrewShop(
                    partner: widget.partner,
                    status: BrewShopStatus.pending,
                  );

              return BrewSheet(
                staggerCount: 6,
                children: [
                  StaggerItem(index: 0, child: _header(context, preview)),
                  SizedBox(height: brewBlockGap(compact)),
                  StaggerItem(index: 1, child: _titleLockup(compact, preview)),
                  SizedBox(height: brewBlockGap(compact)),
                  StaggerItem(index: 2, child: _buildIdentityCard(preview)),
                  const SizedBox(height: BrewSpace.grid * 2),
                  StaggerItem(
                    index: 3,
                    child: _buildOperationsSection(preview, context),
                  ),
                  const SizedBox(height: BrewSpace.grid * 2),
                  StaggerItem(index: 4, child: _buildCatalogSection(context)),
                  const SizedBox(height: BrewSpace.grid * 2),
                  StaggerItem(index: 5, child: _buildPaymentCard(preview)),
                  const SizedBox(height: BrewSpace.grid * 4),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, BrewShop preview) {
    final isOpen = preview.status == BrewShopStatus.open;

    return Row(
      children: [
        _BackPillButton(
          label: 'DASHBOARD',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        GestureDetector(
          onTap: widget.admin == null ? null : () => _setOpen(!isOpen),
          child: AnimatedContainer(
            duration: BrewMotion.press,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isOpen
                  ? BrewColor.sage.withValues(alpha: 0.20)
                  : BrewColor.alert.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isOpen
                    ? BrewColor.sage.withValues(alpha: 0.6)
                    : BrewColor.alert.withValues(alpha: 0.5),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOpen ? BrewColor.sageLight : BrewColor.alert,
                    boxShadow: isOpen
                        ? [
                            BoxShadow(
                              color: BrewColor.sageLight.withValues(alpha: 0.6),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  (isOpen ? 'OPEN' : 'CLOSED'),
                  style: BrewType.mono.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: isOpen ? BrewColor.sageLight : BrewColor.alert,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleLockup(bool compact, BrewShop preview) {
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
                'STORE SETTINGS',
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
        Text(
          preview.displayName,
          style: BrewType.displayAt(compact ? 28 : 34),
        ),
        const SizedBox(height: BrewSpace.grid * 0.75),
        Text(
          'Manage your store profile, operating hours, active orders, and customer payment QR.',
          style: BrewType.rowBody.copyWith(
            color: BrewColor.cream.withValues(alpha: 0.76),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityCard(BrewShop preview) {
    final hasPicture = preview.logoBytes != null || preview.logoUrl != null;

    return _AdminGlassCard(
      label: 'Store Identity & Branding',
      icon: Icons.storefront_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(BrewSpace.grid * 2),
            decoration: BoxDecoration(
              color: const Color(0x40000000),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: BrewColor.cream.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0x33000000),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: BrewColor.cream.withValues(alpha: 0.18),
                    ),
                  ),
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  child: BrewShopMark(shop: preview, dimension: 76),
                ),
                const SizedBox(width: BrewSpace.grid * 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store Logo',
                        style: BrewType.rowTitle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Shown on customer app, menu, and checkout receipts.',
                        style: BrewType.rowBody.copyWith(
                          fontSize: 12,
                          color: BrewColor.cream.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: BrewSpace.grid * 1.5),
                      Wrap(
                        spacing: BrewSpace.grid * 1.5,
                        runSpacing: BrewSpace.grid,
                        children: [
                          BrewMonoButton(
                            label: _savingLogo
                                ? 'Saving…'
                                : (hasPicture ? 'Replace logo' : 'Upload logo'),
                            semanticsLabel: hasPicture
                                ? 'Replace the shop picture'
                                : 'Upload a shop picture',
                            onPressed: (_savingLogo || widget.admin == null)
                                ? null
                                : _pickLogo,
                          ),
                          if (hasPicture)
                            BrewMonoButton(
                              label: 'Remove',
                              semanticsLabel: 'Remove the shop picture',
                              ink: BrewColor.alert,
                              onPressed: (_savingLogo || widget.admin == null)
                                  ? null
                                  : _removeLogo,
                            ),
                        ],
                      ),
                      BrewReveal(
                        gap: BrewSpace.grid,
                        child: switch (_logoError) {
                          final message? => Semantics(
                              liveRegion: true,
                              child: Text(message, style: BrewType.fieldError),
                            ),
                          null => null,
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: BrewSpace.grid * 2.5),
          BrewField(
            label: 'Store Name',
            controller: _nameController,
            hint: widget.partner.name,
            cardStyle: true,
            leading: const Icon(
              Icons.badge_outlined,
              size: 20,
              color: BrewColor.sageLight,
            ),
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _saveIdentity(),
          ),
          const SizedBox(height: BrewSpace.grid * 2),
          BrewField(
            label: 'Store Description',
            controller: _descriptionController,
            hint: widget.partner.description,
            cardStyle: true,
            leading: const Icon(
              Icons.description_outlined,
              size: 20,
              color: BrewColor.sageLight,
            ),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveIdentity(),
          ),
          BrewReveal(
            gap: BrewSpace.grid,
            child: switch (_identityError) {
              final message? => Semantics(
                  liveRegion: true,
                  child: Text(message, style: BrewType.fieldError),
                ),
              null => null,
            },
          ),
          const SizedBox(height: BrewSpace.grid * 2.5),
          BrewPrimaryButton(
            label: 'Save profile changes',
            asPill: true,
            leading: const Icon(
              Icons.check_circle_outline_rounded,
              size: 18,
              color: Color(0xFF13251A),
            ),
            busyLabel: _savingIdentity
                ? 'Saving profile changes…'
                : (_identityPrimed ? null : 'Loading profile…'),
            onPressed: (widget.admin == null || !_identityPrimed)
                ? null
                : _saveIdentity,
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsSection(BrewShop preview, BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _ordersCard(context)),
          const SizedBox(width: BrewSpace.grid * 2),
          Expanded(child: _hoursCard(preview.status)),
        ],
      ),
    );
  }

  Widget _ordersCard(BuildContext context) {
    return StreamBuilder<List<BrewOrder>>(
      stream: _orders,
      builder: (context, snapshot) {
        final unattended = (snapshot.data ?? const <BrewOrder>[])
            .where((order) => order.stage == BrewOrderStage.received)
            .length;

        return _AdminGlassCard(
          label: 'Live Orders',
          icon: Icons.receipt_long_rounded,
          onTap: widget.admin == null ? null : () => _openOrders(context),
          semanticsLabel: unattended == 0
              ? 'Orders. View and fulfil orders for this shop.'
              : 'Orders. $unattended waiting. View and fulfil orders for this shop.',
          trailing: (unattended > 0) ? _CountBadge(count: unattended) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                unattended > 0 ? '$unattended waiting' : 'Active queue',
                style: BrewType.rowTitle.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                unattended > 0
                    ? 'Orders pending counter action'
                    : 'Fulfill customer orders',
                style: BrewType.rowBody.copyWith(
                  fontSize: 12,
                  color: BrewColor.cream.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: BrewSpace.grid * 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'View orders',
                      style: BrewType.mono.copyWith(
                        fontSize: 11,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                        color: BrewColor.sageLight,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: BrewColor.sageLight,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _hoursCard(BrewShopStatus status) {
    final open = status == BrewShopStatus.open;

    return _AdminGlassCard(
      label: 'Hours & Status',
      icon: Icons.access_time_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OpenToggle(
            open: open,
            onChanged: widget.admin == null ? null : _setOpen,
          ),
          const SizedBox(height: 8),
          Text(
            open ? 'Accepting incoming orders' : 'Ordering currently paused',
            style: BrewType.rowBody.copyWith(
              fontSize: 12,
              color: BrewColor.cream.withValues(alpha: 0.65),
            ),
          ),
          BrewReveal(
            gap: BrewSpace.grid,
            child: switch (_hoursError) {
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

  Widget _buildCatalogSection(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _AdminGlassCard(
              label: 'The Board',
              icon: Icons.restaurant_menu_rounded,
              onTap: widget.admin == null ? null : () => _openMenu(context),
              semanticsLabel: 'The board. Manage products.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Menu products',
                    style: BrewType.rowTitle.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pricing, recipes & availability',
                    style: BrewType.rowBody.copyWith(
                      fontSize: 12,
                      color: BrewColor.cream.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: BrewSpace.grid * 2),
                  Row(
                    children: [
                      Text(
                        'Manage',
                        style: BrewType.mono.copyWith(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                          color: BrewColor.sageLight,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: BrewColor.sageLight,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: BrewSpace.grid * 2),
          Expanded(
            child: _AdminGlassCard(
              label: 'Add-ons',
              icon: Icons.tune_rounded,
              onTap: widget.admin == null ? null : () => _openAddOns(context),
              semanticsLabel: 'Add-ons. Manage the extras this shop offers.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Extras & options',
                    style: BrewType.rowTitle.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Milk, syrups, shots & modifiers',
                    style: BrewType.rowBody.copyWith(
                      fontSize: 12,
                      color: BrewColor.cream.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: BrewSpace.grid * 2),
                  Row(
                    children: [
                      Text(
                        'Manage',
                        style: BrewType.mono.copyWith(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                          color: BrewColor.sageLight,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: BrewColor.sageLight,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(BrewShop preview) {
    final qr = preview.payQrBytes;

    return _AdminGlassCard(
      label: 'Payment QR Code',
      icon: Icons.qr_code_2_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(BrewSpace.grid * 2),
            decoration: BoxDecoration(
              color: const Color(0x40000000),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: BrewColor.cream.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: BrewColor.cream.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  child: qr != null
                      ? BrewMenuItemImage(
                          bytes: qr,
                          dimension: 100,
                          placeholder: false,
                        )
                      : Container(
                          color: const Color(0x1A000000),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 34,
                                color: BrewColor.field.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'NO CODE',
                                style: BrewType.mono.copyWith(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: BrewColor.field.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(width: BrewSpace.grid * 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Direct Payment QR',
                        style: BrewType.rowTitle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        qr == null
                            ? 'No code uploaded yet. Customers are told to pay at the counter.'
                            : 'Customers scan this code during checkout and upload receipt proof.',
                        style: BrewType.rowBody.copyWith(
                          fontSize: 12,
                          color: BrewColor.cream.withValues(alpha: 0.65),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: BrewSpace.grid * 1.5),
                      Wrap(
                        spacing: BrewSpace.grid * 1.5,
                        runSpacing: BrewSpace.grid,
                        children: [
                          BrewMonoButton(
                            label: _savingQr
                                ? 'Saving…'
                                : (qr == null ? 'Upload QR' : 'Replace QR'),
                            semanticsLabel: qr == null
                                ? 'Upload a payment QR code'
                                : 'Replace the payment QR code',
                            onPressed: (_savingQr || widget.admin == null)
                                ? null
                                : _pickQr,
                          ),
                          if (qr != null)
                            BrewMonoButton(
                              label: 'Remove',
                              semanticsLabel: 'Remove the payment QR code',
                              ink: BrewColor.alert,
                              onPressed: (_savingQr || widget.admin == null)
                                  ? null
                                  : _removeQr,
                            ),
                        ],
                      ),
                      BrewReveal(
                        gap: BrewSpace.grid,
                        child: switch (_qrError) {
                          final message? => Semantics(
                              liveRegion: true,
                              child: Text(message, style: BrewType.fieldError),
                            ),
                          null => null,
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A smooth back button with subtle slide, scale, and haptic feedback.
class _BackPillButton extends StatefulWidget {
  const _BackPillButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  State<_BackPillButton> createState() => _BackPillButtonState();
}

class _BackPillButtonState extends State<_BackPillButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _isNavigating = false;

  Future<void> _handleTap() async {
    if (_isNavigating) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pressed = true;
      _isNavigating = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 90));

    if (!mounted) return;
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      enabled: true,
      label: 'Back to ${widget.label}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            if (!_isNavigating) setState(() => _pressed = false);
          },
          onTapCancel: () {
            if (!_isNavigating) setState(() => _pressed = false);
          },
          child: AnimatedScale(
            duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.94 : (_hovered ? 1.04 : 1.0),
            child: AnimatedContainer(
              duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _pressed
                    ? const Color(0xB308140C)
                    : (_hovered
                        ? const Color(0x8808140C)
                        : const Color(0x6608140C)),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _pressed
                      ? BrewColor.cream.withValues(alpha: 0.45)
                      : (_hovered
                          ? BrewColor.cream.withValues(alpha: 0.28)
                          : BrewColor.cream.withValues(alpha: 0.16)),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSlide(
                    duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    offset: Offset((_pressed || _hovered) ? -0.25 : 0.0, 0.0),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      size: 15,
                      color: BrewColor.cream,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.label.toUpperCase(),
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
        ),
      ),
    );
  }
}

/// A reusable luxury glassmorphic card for admin sections with smooth tactile feedback.
class _AdminGlassCard extends StatefulWidget {
  const _AdminGlassCard({
    this.label,
    this.icon,
    this.trailing,
    this.onTap,
    this.semanticsLabel,
    required this.child,
  });

  final String? label;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final Widget child;

  @override
  State<_AdminGlassCard> createState() => _AdminGlassCardState();
}

class _AdminGlassCardState extends State<_AdminGlassCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final isInteractive = widget.onTap != null;

    Widget card = AnimatedScale(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      scale: (_pressed && isInteractive) ? 0.985 : 1.0,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : BrewMotion.press,
        curve: BrewMotion.pressCurve,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: BrewSpace.grid * 2,
          vertical: BrewSpace.grid * 2.25,
        ),
        decoration: BoxDecoration(
          color: (_pressed && isInteractive)
              ? const Color(0xF5182D20)
              : const Color(0xEB132218),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (_pressed && isInteractive)
                ? BrewColor.fieldFocus
                : BrewColor.cream.withValues(alpha: 0.12),
            width: 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null || widget.icon != null || widget.trailing != null) ...[
              Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 14, color: BrewColor.sageLight),
                    const SizedBox(width: 8),
                  ],
                  if (widget.label != null)
                    Expanded(
                      child: Text(
                        widget.label!.toUpperCase(),
                        style: BrewType.mono.copyWith(
                          fontSize: 10.5,
                          letterSpacing: 1.4,
                          color: BrewColor.sageLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ?widget.trailing,
                ],
              ),
              const SizedBox(height: BrewSpace.grid * 2),
            ],
            widget.child,
          ],
        ),
      ),
    );

    if (isInteractive) {
      card = BrewPressable(
        onPressed: widget.onTap,
        radius: 16,
        haptic: HapticFeedback.lightImpact,
        onPressedChanged: (value) => setState(() => _pressed = value),
        reduced: reduced,
        pressed: _pressed,
        semanticsLabel: widget.semanticsLabel,
        child: card,
      );
    }

    return card;
  }
}

/// Upgraded open/closed toggle with haptic feedback, glowing state, and clear status.
class _OpenToggle extends StatefulWidget {
  const _OpenToggle({required this.open, this.onChanged});

  final bool open;
  final ValueChanged<bool>? onChanged;

  @override
  State<_OpenToggle> createState() => _OpenToggleState();
}

class _OpenToggleState extends State<_OpenToggle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final open = widget.open;

    return BrewPressable(
      onPressed:
          widget.onChanged == null ? null : () => widget.onChanged!(!open),
      onPressedChanged: (value) => setState(() => _pressed = value),
      radius: 12,
      pressed: _pressed,
      reduced: reduced,
      haptic: HapticFeedback.lightImpact,
      semanticsLabel: open ? 'Open. Tap to close.' : 'Closed. Tap to open.',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : BrewMotion.press,
          curve: BrewMotion.pressCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: open
                ? BrewColor.sage.withValues(alpha: 0.18)
                : BrewColor.alert.withValues(alpha: 0.14),
            border: Border.all(
              color: _pressed
                  ? BrewColor.fieldFocus
                  : (open
                      ? BrewColor.sage.withValues(alpha: 0.5)
                      : BrewColor.alert.withValues(alpha: 0.4)),
              width: 1.0,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: open ? BrewColor.sageLight : BrewColor.alert,
                  boxShadow: open
                      ? [
                          BoxShadow(
                            color: BrewColor.sageLight.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                (open ? 'OPEN' : 'CLOSED'),
                style: BrewType.mono.copyWith(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: open ? BrewColor.sageLight : BrewColor.alert,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A count badge for unattended orders.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BrewColor.sage,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: BrewType.mono.copyWith(
          color: BrewColor.field,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
