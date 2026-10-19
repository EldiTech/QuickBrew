import 'package:flutter/material.dart'
    show Colors, Material, showModalBottomSheet;
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

enum AdminTransactionLogKind { pending, completed }

/// The superadmin's transaction ledger, split into pending and completed
/// destinations so history never competes with the live queue.
class AdminTransactionLogsScreen extends StatefulWidget {
  const AdminTransactionLogsScreen({
    super.key,
    required this.kind,
    this.partner,
    this.admin,
  });

  final AdminTransactionLogKind kind;
  final BrewPartner? partner;
  final BrewAdmin? admin;

  static Route<void> route({
    bool reduced = false,
    required AdminTransactionLogKind kind,
    BrewPartner? partner,
    BrewAdmin? admin,
  }) {
    return adminPageRoute<void>(
      reduced: reduced,
      builder: (context) => AdminTransactionLogsScreen(
        kind: kind,
        partner: partner,
        admin: admin,
      ),
    );
  }

  @override
  State<AdminTransactionLogsScreen> createState() =>
      _AdminTransactionLogsScreenState();
}

class _AdminTransactionLogsScreenState
    extends State<AdminTransactionLogsScreen> {
  late final Stream<List<BrewOrder>>? _orders = _orderStream();

  Stream<List<BrewOrder>>? _orderStream() {
    final admin = widget.admin;
    if (admin == null) return null;
    final partner = widget.partner;
    return partner == null ? admin.allOrders() : admin.ordersFor(partner);
  }

  bool get _completed => widget.kind == AdminTransactionLogKind.completed;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).height <= BrewSpace.compactHeight;
    final title = _completed
        ? 'Completed transactions.'
        : 'Pending transactions.';
    final subtitle = _completed
        ? 'A record of orders that reached the counter as completed.'
        : 'Orders still moving through preparation or waiting for the counter.';

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
              final all = snapshot.data;
              final visible = all == null
                  ? null
                  : [
                      for (final order in all)
                        if ((_completed &&
                                order.stage == BrewOrderStage.completed) ||
                            (!_completed && order.stage.isActive))
                          order,
                    ];
              final rows = visible?.length ?? 0;
              return BrewSheet(
                staggerCount: 7 + rows,
                children: [
                  StaggerItem(index: 0, child: _header(context)),
                  SizedBox(height: brewBlockGap(compact)),
                  StaggerItem(
                    index: 1,
                    child: Text(
                      title,
                      style: BrewType.displayAt(compact ? 28 : 34),
                    ),
                  ),
                  const SizedBox(height: BrewSpace.grid * 0.75),
                  StaggerItem(
                    index: 2,
                    child: Text(subtitle, style: BrewType.rowBody),
                  ),
                  SizedBox(height: brewBlockGap(compact)),
                  StaggerItem(index: 3, child: _switcher(context)),
                  const SizedBox(height: BrewSpace.grid * 2),
                  StaggerItem(index: 4, child: _summary(visible)),
                  const SizedBox(height: BrewSpace.grid * 2),
                  if (_orders == null)
                    StaggerItem(
                      index: 5,
                      child: Text(
                        'Transactions are not connected in this build.',
                        style: BrewType.rowBody,
                      ),
                    )
                  else if (all == null)
                    StaggerItem(
                      index: 5,
                      child: Text(
                        'Looking up transactions…',
                        style: BrewType.rowBody,
                      ),
                    )
                  else if (visible!.isEmpty)
                    StaggerItem(
                      index: 5,
                      child: Text(
                        _completed
                            ? 'No completed transactions yet.'
                            : 'No pending transactions right now.',
                        style: BrewType.rowBody,
                      ),
                    )
                  else
                    for (final (index, order) in visible.indexed)
                      StaggerItem(
                        index: 5 + index,
                        child: _TransactionRow(
                          order: order,
                          onTap: () => _openDetail(context, order),
                        ),
                      ),
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
          semanticsLabel: 'Back to accounts',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        Text('TRANSACTIONS', style: BrewType.mono),
      ],
    );
  }

  Widget _switcher(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Row(
      children: [
        Expanded(
          child: _LogDestination(
            label: 'PENDING',
            selected: !_completed,
            reduced: reduced,
            onTap: _completed
                ? () => Navigator.of(context).pushReplacement(
                    AdminTransactionLogsScreen.route(
                      reduced: reduced,
                      kind: AdminTransactionLogKind.pending,
                      partner: widget.partner,
                      admin: widget.admin,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(width: BrewSpace.grid),
        Expanded(
          child: _LogDestination(
            label: 'COMPLETED',
            selected: _completed,
            reduced: reduced,
            onTap: !_completed
                ? () => Navigator.of(context).pushReplacement(
                    AdminTransactionLogsScreen.route(
                      reduced: reduced,
                      kind: AdminTransactionLogKind.completed,
                      partner: widget.partner,
                      admin: widget.admin,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _summary(List<BrewOrder>? orders) {
    if (orders == null) return const SizedBox.shrink();
    final totalCents = orders.fold<int>(
      0,
      (sum, order) => sum + (order.totalCents ?? 0),
    );
    final label = orders.length == 1
        ? '1 transaction'
        : '${orders.length} transactions';
    return Row(
      children: [
        Expanded(child: Text(label.toUpperCase(), style: BrewType.mono)),
        Text(_formatCents(totalCents), style: BrewType.displayAt(20)),
      ],
    );
  }

  Future<void> _openDetail(BuildContext context, BrewOrder order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrewColor.field,
      builder: (context) => _TransactionDetailSheet(order: order),
    );
  }
}

class _LogDestination extends StatelessWidget {
  const _LogDestination({
    required this.label,
    required this.selected,
    required this.reduced,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool reduced;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BrewPressable(
      onPressed: onTap,
      radius: BrewSpace.radius,
      onPressedChanged: (_) {},
      reduced: reduced,
      pressed: false,
      semanticsLabel: '$label transactions',
      child: Container(
        height: BrewSpace.grid * 6,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? BrewColor.sage.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(BrewSpace.radius),
          border: Border.all(
            color: selected
                ? BrewColor.sageLight.withValues(alpha: 0.5)
                : BrewColor.cream.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          label,
          style: BrewType.mono.copyWith(
            color: selected
                ? BrewColor.sageLight
                : BrewColor.cream.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.order, required this.onTap});

  final BrewOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrewPressable(
      onPressed: onTap,
      radius: BrewSpace.radius,
      onPressedChanged: (_) {},
      reduced: MediaQuery.disableAnimationsOf(context),
      pressed: false,
      semanticsLabel: 'Open transaction ${order.reference}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: BrewSpace.grid * 1.5),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: BrewColor.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.pickupName ?? 'Unnamed order',
                    style: BrewType.rowTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(order.itemLine, style: BrewType.rowBody),
                  const SizedBox(height: 4),
                  Text(
                    '${order.shopName} · ${order.reference}',
                    style: BrewType.mono,
                  ),
                ],
              ),
            ),
            const SizedBox(width: BrewSpace.grid),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(order.totalLabel ?? '—', style: BrewType.rowTitle),
                const SizedBox(height: 4),
                Text(
                  order.placedAt == null
                      ? 'TIME PENDING'
                      : BrewOrder.formatWhen(order.placedAt!).toUpperCase(),
                  style: BrewType.mono,
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionDetailSheet extends StatelessWidget {
  const _TransactionDetailSheet({required this.order});

  final BrewOrder order;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: BrewSpace.gutter,
        right: BrewSpace.gutter,
        top: BrewSpace.grid * 3,
        bottom: media.padding.bottom + BrewSpace.grid * 4,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(order.reference, style: BrewType.mono),
            const SizedBox(height: BrewSpace.grid),
            Text(
              order.pickupName ?? 'Unnamed order',
              style: BrewType.displayAt(24),
            ),
            const SizedBox(height: BrewSpace.grid * 2),
            _DetailLine(label: 'Store', value: order.shopName),
            _DetailLine(label: 'Items', value: order.itemLine),
            if (order.pickupPhone != null)
              _DetailLine(label: 'Phone', value: order.pickupPhone!),
            _DetailLine(label: 'Status', value: order.stage.label),
            if (order.paymentMethod != null)
              _DetailLine(label: 'Payment', value: order.paymentMethod!),
            _DetailLine(label: 'Total', value: order.totalLabel ?? 'Not set'),
            if (order.placedAt != null)
              _DetailLine(
                label: 'Placed',
                value: BrewOrder.formatWhen(order.placedAt!),
              ),
            const SizedBox(height: BrewSpace.grid * 3),
            BrewTextButton(
              label: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BrewSpace.grid * 0.75),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(label.toUpperCase(), style: BrewType.mono),
          ),
          Expanded(child: Text(value, style: BrewType.body)),
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
