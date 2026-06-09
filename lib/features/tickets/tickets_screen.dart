import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../domain/models/ticket_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../account/auth_prompt_sheet.dart';
import 'vennuzo_ticket_payment_status_screen.dart';

class TicketsScreen extends StatelessWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final session = context.watch<VennuzoSessionController>();
    final orders = repository.orders;
    final admittedCount = orders.fold<int>(
      0,
      (sum, order) =>
          sum +
          order.tickets
              .where((ticket) => ticket.status == TicketStatus.admitted)
              .length,
    );
    final openGateCount = orders.fold<int>(
      0,
      (sum, order) =>
          sum +
          order.tickets
              .where((ticket) => ticket.status != TicketStatus.admitted)
              .length,
    );
    final paidCount = orders
        .where((order) => order.status == TicketOrderStatus.paid)
        .length;
    final reservedCount = orders
        .where((order) => order.status == TicketOrderStatus.reserved)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      children: [
        _TicketsHero(
          ticketCount: orders.length,
          paidCount: paidCount,
          reservedCount: reservedCount,
          isGuest: session.isGuest,
          onGuestAction: () => _promptForAccess(context),
        ),
        const SizedBox(height: 18),
        if (!session.isGuest) ...[
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              MetricTile(
                label: 'Orders',
                value: '${orders.length}',
                icon: Icons.shopping_bag_outlined,
              ),
              MetricTile(
                label: 'Used already',
                value: '$admittedCount',
                icon: Icons.verified_outlined,
                highlight: context.palette.teal,
              ),
              MetricTile(
                label: 'Ready or waiting',
                value: '$openGateCount',
                icon: Icons.qr_code_scanner_outlined,
                highlight: context.palette.coral,
              ),
            ],
          ),
          const SizedBox(height: 28),
          SectionHeading(title: 'Ready at the door', subtitle: null),
          const SizedBox(height: 14),
          _GateQueue(),
          const SizedBox(height: 26),
          SectionHeading(title: 'Saved orders', subtitle: null),
          const SizedBox(height: 14),
          if (orders.isEmpty)
            const EmptyStateCard(
              title: 'No orders yet',
              icon: Icons.receipt_long_outlined,
            )
          else
            ...orders.map(
              (order) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _OrderCard(order: order),
              ),
            ),
        ],
      ],
    );
  }

  void _promptForAccess(BuildContext context) {
    showAuthPromptSheet(
      context,
      title: 'Continue to save tickets',
      body:
          'Sign in or create an account to keep every QR code ready at the door.',
    );
  }
}

class _TicketsHero extends StatelessWidget {
  const _TicketsHero({
    required this.ticketCount,
    required this.paidCount,
    required this.reservedCount,
    required this.isGuest,
    required this.onGuestAction,
  });

  final int ticketCount;
  final int paidCount;
  final int reservedCount;
  final bool isGuest;
  final VoidCallback onGuestAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
            border: Border.all(color: palette.border),
            boxShadow: VennuzoTheme.shadowResting,
          ),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PassHeroIcon(color: palette.primaryStart),
                    const SizedBox(width: 18),
                    Expanded(child: _TicketsHeroCopy(isGuest: isGuest)),
                    const SizedBox(width: 18),
                    _TicketsHeroActions(
                      ticketCount: ticketCount,
                      paidCount: paidCount,
                      reservedCount: reservedCount,
                      isGuest: isGuest,
                      onGuestAction: onGuestAction,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PassHeroIcon(color: palette.primaryStart),
                    const SizedBox(height: 18),
                    _TicketsHeroCopy(isGuest: isGuest),
                    const SizedBox(height: 18),
                    _TicketsHeroActions(
                      ticketCount: ticketCount,
                      paidCount: paidCount,
                      reservedCount: reservedCount,
                      isGuest: isGuest,
                      onGuestAction: onGuestAction,
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _PassHeroIcon extends StatelessWidget {
  const _PassHeroIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
      ),
      child: Icon(Icons.confirmation_num_outlined, color: color),
    );
  }
}

class _TicketsHeroCopy extends StatelessWidget {
  const _TicketsHeroCopy({required this.isGuest});

  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pass wallet',
          style: context.text.bodyLarge?.copyWith(
            color: context.palette.primaryStart,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          isGuest ? 'Your passes stay ready.' : 'Everything for the door.',
          style: context.text.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          isGuest
              ? 'Sign in to access purchased tickets, saved reservations, and QR codes.'
              : 'See QR codes, payment state, and check-in status without opening each order.',
          style: context.text.bodyLarge,
        ),
      ],
    );
  }
}

class _TicketsHeroActions extends StatelessWidget {
  const _TicketsHeroActions({
    required this.ticketCount,
    required this.paidCount,
    required this.reservedCount,
    required this.isGuest,
    required this.onGuestAction,
  });

  final int ticketCount;
  final int paidCount;
  final int reservedCount;
  final bool isGuest;
  final VoidCallback onGuestAction;

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _InfoPill(label: 'QR codes'),
              _InfoPill(label: 'Reservations'),
              _InfoPill(label: 'Door scan'),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: ElevatedButton.icon(
              onPressed: onGuestAction,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in / Create account'),
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _HeroStat(value: '$paidCount', label: 'Paid'),
        _HeroStat(value: '$reservedCount', label: 'Pay at door'),
        _HeroStat(value: '$ticketCount', label: 'Orders'),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
        border: Border.all(
          color: context.palette.border.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.text.titleLarge?.copyWith(
              color: context.palette.primaryStart,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

class _GateQueue extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final session = context.watch<VennuzoSessionController>();
    final canCheckIn =
        (session.viewer.isAdminWorkspace && session.viewer.hasAdminAccess) ||
        (session.viewer.isOrganizerWorkspace &&
            session.viewer.hasOrganizerAccess);
    final entries = [
      for (final order in repository.orders)
        for (final ticket in order.tickets)
          if (ticket.status != TicketStatus.admitted)
            _GateEntry(order: order, ticket: ticket),
    ];

    if (entries.isEmpty) {
      return const EmptyStateCard(
        title: 'Nothing waiting at the gate',
        icon: Icons.check_circle_outline,
      );
    }

    return Column(
      children: entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GatePassCard(entry: entry, canCheckIn: canCheckIn),
            ),
          )
          .toList(),
    );
  }
}

class _GatePassCard extends StatelessWidget {
  const _GatePassCard({required this.entry, required this.canCheckIn});

  final _GateEntry entry;
  final bool canCheckIn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final statusColor = entry.ticket.status == TicketStatus.unpaid
        ? palette.coral
        : palette.teal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 520;

            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusPill(
                      label: _ticketStatusLabel(entry.ticket.status),
                      color: statusColor,
                    ),
                    _InfoPill(
                      label: _paymentStatusLabel(entry.order.paymentStatus),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  entry.ticket.attendeeName,
                  style: context.text.titleLarge?.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.order.eventTitle,
                  style: context.text.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InfoPill(label: entry.ticket.tierName),
                    _QrPill(
                      qrToken: entry.ticket.qrToken,
                      label: entry.ticket.tierName,
                    ),
                  ],
                ),
              ],
            );

            final action = canCheckIn
                ? ElevatedButton(
                    onPressed: () {
                      context.read<VennuzoRepository>().admitTicket(
                        entry.order.id,
                        entry.ticket.ticketId,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${entry.ticket.attendeeName} is now checked in.',
                          ),
                        ),
                      );
                    },
                    child: Text(
                      entry.ticket.status == TicketStatus.unpaid
                          ? 'Pay at door and check in'
                          : 'Mark as checked in',
                    ),
                  )
                : Text(
                    entry.ticket.status == TicketStatus.unpaid
                        ? 'Pay at the door, then let gate staff scan this pass.'
                        : 'Show this QR code to gate staff for check-in.',
                    style: context.text.bodyMedium?.copyWith(
                      color: palette.slate,
                    ),
                  );

            final qrMark = Container(
              width: wide ? 84 : 56,
              height: wide ? 84 : 56,
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
                border: Border.all(
                  color: palette.border.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(
                Icons.qr_code_2_rounded,
                color: palette.primaryStart,
                size: wide ? 42 : 30,
              ),
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  qrMark,
                  const SizedBox(width: 16),
                  Expanded(child: details),
                  const SizedBox(width: 16),
                  SizedBox(width: 210, child: action),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    qrMark,
                    const SizedBox(width: 14),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: action),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  const _OrderCard({required this.order});

  final TicketOrder order;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _linkCopied = false;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<VennuzoRepository>();
    final order = widget.order;
    final publicLink = repository.buildPublicTicketLink(order.id);
    // A failed payment (or a stuck pending one that never issued tickets) needs
    // a way back into checkout instead of looking like an in-progress order.
    final canReopenPayment =
        order.paymentStatus == TicketPaymentStatus.failed ||
        ((order.paymentStatus == TicketPaymentStatus.pending ||
                order.paymentStatus == TicketPaymentStatus.initiated) &&
            order.tickets.isEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.eventTitle,
                        style: context.text.titleLarge?.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Booked by ${order.buyerName}',
                        style: context.text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: _orderStatusLabel(order.status),
                  color: order.status == TicketOrderStatus.paid
                      ? context.palette.teal
                      : context.palette.coral,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(label: 'Order ${order.id}'),
                _InfoPill(label: formatMoney(order.totalAmount)),
                _InfoPill(label: _paymentStatusLabel(order.paymentStatus)),
              ],
            ),
            const SizedBox(height: 14),
            ...order.selectedTiers.map(
              (selection) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selection.name,
                        style: context.text.bodyLarge,
                      ),
                    ),
                    Text(
                      'x${selection.quantity}',
                      style: context.text.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.palette.canvas,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tickets in this order',
                    style: context.text.titleLarge?.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 10),
                  ...order.tickets.map(
                    (ticket) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OrderTicketRow(ticket: ticket),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: publicLink));
                    if (context.mounted) {
                      setState(() => _linkCopied = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Order link copied.')),
                      );
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) {
                          setState(() => _linkCopied = false);
                        }
                      });
                    }
                  },
                  icon: Icon(
                    _linkCopied
                        ? Icons.check_circle_outline
                        : Icons.copy_outlined,
                  ),
                  label: Text(_linkCopied ? 'Copied' : 'Copy order link'),
                ),
                if (canReopenPayment)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VennuzoTicketPaymentStatusScreen(
                            orderId: order.id,
                            initialOrder: order,
                            checkoutUrl: '',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reopen payment'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTicketRow extends StatelessWidget {
  const _OrderTicketRow({required this.ticket});

  final EventTicket ticket;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
        border: Border.all(
          color: context.palette.border.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.palette.primaryStart.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.confirmation_num_outlined,
              color: context.palette.primaryStart,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ticket.attendeeName, style: context.text.bodyLarge),
                const SizedBox(height: 4),
                Text(ticket.tierName, style: context.text.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusPill(
                      label: _ticketStatusLabel(ticket.status),
                      color: ticket.status == TicketStatus.admitted
                          ? context.palette.teal
                          : context.palette.ink,
                    ),
                    _QrPill(qrToken: ticket.qrToken, label: ticket.tierName),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(color: context.palette.ink),
      ),
    );
  }
}

class _GateEntry {
  const _GateEntry({required this.order, required this.ticket});

  final TicketOrder order;
  final EventTicket ticket;
}

// ── QR pill — tappable chip that opens a full-screen QR dialog ───────────────

class _QrPill extends StatelessWidget {
  const _QrPill({required this.qrToken, required this.label});

  final String qrToken;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Show QR code',
      child: GestureDetector(
        onTap: () => _showQrDialog(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.palette.canvas,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.palette.border.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.qr_code_2_outlined,
                size: 16,
                color: context.palette.ink,
              ),
              const SizedBox(width: 6),
              Text(
                'Show QR',
                style: context.text.bodySmall?.copyWith(
                  color: context.palette.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQrDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _QrDialog(qrToken: qrToken, label: label),
    );
  }
}

class _QrDialog extends StatelessWidget {
  const _QrDialog({required this.qrToken, required this.label});

  final String qrToken;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Show this at the door',
              style: context.text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: qrToken.isEmpty
                  ? const _QrNotReady(size: 240)
                  : QrImageView(
                      data: qrToken,
                      version: QrVersions.auto,
                      size: 240,
                      backgroundColor: Colors.white,
                      semanticsLabel: 'Ticket QR code',
                      errorStateBuilder: (context, error) =>
                          const _QrRenderFailed(size: 240),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              qrToken,
              style: context.text.bodySmall?.copyWith(fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrNotReady extends StatelessWidget {
  const _QrNotReady({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.hourglass_empty_rounded,
            color: context.palette.slate,
            size: 40,
          ),
          const SizedBox(height: 8),
          Text(
            'QR not ready yet',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.slate,
            ),
          ),
        ],
      ),
    );
  }
}

class _QrRenderFailed extends StatelessWidget {
  const _QrRenderFailed({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: context.palette.coral,
            size: 40,
          ),
          const SizedBox(height: 8),
          Text(
            "Couldn't render code",
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.coral,
            ),
          ),
        ],
      ),
    );
  }
}

String _orderStatusLabel(TicketOrderStatus status) => switch (status) {
  TicketOrderStatus.pending => 'On the way',
  TicketOrderStatus.reserved => 'Reserved',
  TicketOrderStatus.paid => '✓ Paid',
};

String _paymentStatusLabel(TicketPaymentStatus status) => switch (status) {
  TicketPaymentStatus.initiated => 'Started',
  TicketPaymentStatus.pending => 'Pending',
  TicketPaymentStatus.paid => '✓ Paid',
  TicketPaymentStatus.cashAtGate => 'Pay at door',
  TicketPaymentStatus.cashAtGatePaid => '✓ Paid at door',
  TicketPaymentStatus.complimentary => 'Free pass',
  TicketPaymentStatus.failed => 'Failed',
};

String _ticketStatusLabel(TicketStatus status) => switch (status) {
  TicketStatus.issued => 'Ready to use',
  TicketStatus.unpaid => 'Pay at door',
  TicketStatus.admitted => 'Checked in',
};
