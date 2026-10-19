import 'package:flutter/material.dart' show Icon, Icons, Material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../brew_admin.dart';
import '../../brew_counter.dart';
import '../../theme/brew_type.dart';
import '../../theme/tokens.dart';
import '../../widgets/brew_background.dart';
import '../../widgets/brew_buttons.dart';
import '../../widgets/brew_sheet.dart';
import '../../widgets/stagger.dart';
import 'admin_transitions.dart';

/// Profit report for one store admin or all stores for a superadmin.
///
/// Only completed orders count. The stored order total already includes the
/// platform fee, so the report removes one fixed fee per completed transaction
/// before presenting the coffee shop's net amount.
class AdminProfitScreen extends StatefulWidget {
  const AdminProfitScreen({super.key, required this.partners, this.admin});

  final List<BrewPartner> partners;
  final BrewAdmin? admin;

  static Route<void> route({
    bool reduced = false,
    required List<BrewPartner> partners,
    BrewAdmin? admin,
  }) {
    return adminPageRoute<void>(
      reduced: reduced,
      builder: (context) => AdminProfitScreen(partners: partners, admin: admin),
    );
  }

  @override
  State<AdminProfitScreen> createState() => _AdminProfitScreenState();
}

class _AdminProfitScreenState extends State<AdminProfitScreen> {
  late final Stream<List<BrewOrder>>? _orders = _buildOrderStream();

  Stream<List<BrewOrder>>? _buildOrderStream() {
    final admin = widget.admin;
    if (admin == null || widget.partners.isEmpty) return null;
    if (widget.partners.length == BrewPartner.values.length) {
      return admin.allOrders();
    }
    return admin.ordersFor(widget.partners.first);
  }

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).height <= BrewSpace.compactHeight;

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
          child: StreamBuilder<List<BrewOrder>>(
            stream: _orders,
            builder: (context, snapshot) {
              final completed = snapshot.data == null
                  ? null
                  : [
                      for (final order in snapshot.data!)
                        if (order.stage == BrewOrderStage.completed) order,
                    ];
              final storeGroups = completed == null
                  ? const <BrewPartner, List<BrewOrder>>{}
                  : {
                      for (final partner in widget.partners)
                        partner: [
                          for (final order in completed)
                            if (order.partner == partner) order,
                        ],
                    };

              return BrewSheet(
                staggerCount: 8 + storeGroups.length,
                children: [
                  StaggerItem(index: 0, child: _header(context)),
                  SizedBox(height: brewBlockGap(compact)),
                  StaggerItem(
                    index: 1,
                    child: Text(
                      'Profit report.',
                      style: BrewType.displayAt(compact ? 28 : 34),
                    ),
                  ),
                  const SizedBox(height: BrewSpace.grid * 0.75),
                  StaggerItem(
                    index: 2,
                    child: Text(
                      'Completed sales after the QuickBrew platform fee.',
                      style: BrewType.rowBody,
                    ),
                  ),
                  SizedBox(height: brewBlockGap(compact)),
                  StaggerItem(index: 3, child: _feeNotice()),
                  const SizedBox(height: BrewSpace.grid * 2),
                  if (_orders == null)
                    StaggerItem(
                      index: 4,
                      child: Text(
                        'Profit data is not connected in this build.',
                        style: BrewType.rowBody,
                      ),
                    )
                  else if (completed == null)
                    StaggerItem(
                      index: 4,
                      child: Text(
                        'Looking up completed orders…',
                        style: BrewType.rowBody,
                      ),
                    )
                  else ...[
                    StaggerItem(index: 4, child: _totals(completed)),
                    const SizedBox(height: BrewSpace.grid * 2),
                    for (final (index, entry) in storeGroups.entries.indexed)
                      StaggerItem(
                        index: 5 + index,
                        child: _storeProfitCard(entry.key, entry.value),
                      ),
                    if (completed.isEmpty)
                      StaggerItem(
                        index: 5,
                        child: Text(
                          'No completed orders yet.',
                          style: BrewType.rowBody,
                        ),
                      ),
                  ],
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
        BrewMonoButton(
          label: 'Back',
          semanticsLabel: 'Back to admin dashboard',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        Text('REPORTS', style: BrewType.mono),
      ],
    );
  }

  Widget _feeNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BrewSpace.grid * 1.5),
      decoration: BoxDecoration(
        color: BrewColor.sage.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BrewSpace.radius),
        border: Border.all(color: BrewColor.sageLight.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: BrewColor.sageLight,
          ),
          const SizedBox(width: BrewSpace.grid),
          Expanded(
            child: Text(
              'Every completed transaction includes a ₱5 platform fee. '
              'That fee is deducted from the shop total below.',
              style: BrewType.rowBody,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totals(List<BrewOrder> orders) {
    final gross = _gross(orders);
    final fees = quickBrewPlatformFeeCents * orders.length;
    return _ProfitCard(
      title: 'ALL COMPLETED STORES',
      children: [
        _MoneyLine(label: 'Gross completed sales', cents: gross),
        _MoneyLine(
          label: 'Platform fees (₱5 × ${orders.length})',
          cents: -fees,
        ),
        _MoneyLine(
          label: 'Net shop profit',
          cents: gross - fees,
          emphasized: true,
        ),
      ],
    );
  }

  Widget _storeProfitCard(BrewPartner partner, List<BrewOrder> orders) {
    final gross = _gross(orders);
    final fees = quickBrewPlatformFeeCents * orders.length;
    return _ProfitCard(
      title: partner.name,
      children: [
        _MetricLine(label: 'Completed transactions', value: '${orders.length}'),
        _MoneyLine(label: 'Gross sales', cents: gross),
        _MoneyLine(label: 'Platform fees', cents: -fees),
        _MoneyLine(
          label: 'Net shop profit',
          cents: gross - fees,
          emphasized: true,
        ),
      ],
    );
  }

  int _gross(List<BrewOrder> orders) =>
      orders.fold<int>(0, (sum, order) => sum + (order.totalCents ?? 0));
}

class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BrewSpace.grid * 2),
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(BrewSpace.radius),
        border: Border.all(color: BrewColor.cream.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: BrewType.mono),
          const SizedBox(height: BrewSpace.grid * 1.5),
          ...children,
        ],
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.cents,
    this.emphasized = false,
  });

  final String label;
  final int cents;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final value = cents < 0 ? '-${_formatCents(-cents)}' : _formatCents(cents);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BrewSpace.grid * 0.75),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasized ? BrewType.rowTitle : BrewType.rowBody,
            ),
          ),
          Text(
            value,
            style: emphasized
                ? BrewType.displayAt(20)
                : BrewType.mono.copyWith(color: BrewColor.cream),
          ),
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BrewSpace.grid * 0.75),
      child: Row(
        children: [
          Expanded(child: Text(label, style: BrewType.rowBody)),
          Text(value, style: BrewType.mono.copyWith(color: BrewColor.cream)),
        ],
      ),
    );
  }
}

String _formatCents(int cents) {
  final pesos = cents ~/ 100;
  final centavos = cents % 100;
  if (centavos == 0) return '₱$pesos';
  return '₱$pesos.${centavos.toString().padLeft(2, '0')}';
}
