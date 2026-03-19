import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../domain/models/ticket_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';

class AdminTicketsScreen extends StatefulWidget {
  const AdminTicketsScreen({super.key});

  @override
  State<AdminTicketsScreen> createState() => _AdminTicketsScreenState();
}

class _AdminTicketsScreenState extends State<AdminTicketsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final orders = repository.adminVisibleOrders;
    final outstandingEntries = [
      for (final order in orders)
        for (final ticket in order.tickets)
          if (ticket.status != TicketStatus.admitted)
            _GateEntry(order: order, ticket: ticket),
    ];
    final filteredEntries = outstandingEntries.where(_matchesQuery).toList();
    final filteredOrders = orders.where(_orderMatchesQuery).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _TicketsOpsHero(openGateCount: repository.openGateTicketCount),
        const SizedBox(height: 22),
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
              label: 'Admitted',
              value: '${repository.totalAdmittedTickets}',
              icon: Icons.verified_outlined,
              highlight: context.palette.teal,
            ),
            MetricTile(
              label: 'Awaiting entry',
              value: '${repository.openGateTicketCount}',
              icon: Icons.qr_code_scanner_outlined,
              highlight: context.palette.coral,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Lookup and validation',
          subtitle:
              'Search by ticket code, attendee, buyer, or order ID, then admit directly from the admin desk.',
        ),
        const SizedBox(height: 14),
        TextField(
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search attendee, order ID, QR token, or event',
          ),
        ),
        const SizedBox(height: 16),
        if (filteredEntries.isEmpty)
          EmptyStateCard(
            title: _query.isEmpty
                ? 'Gate queue is clear'
                : 'No gate entries match that search',
            body: _query.isEmpty
                ? 'Every unpaid or not-yet-admitted ticket will show up here for the check-in team.'
                : 'Try another attendee name, order ID, or QR token.',
            icon: Icons.qr_code_scanner_outlined,
          )
        else
          ...filteredEntries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GateEntryCard(entry: entry),
            ),
          ),
        const SizedBox(height: 24),
        SectionHeading(
          title: 'Order ledger',
          subtitle:
              'A compact admin view of public links, payment state, and buyer details for each order.',
        ),
        const SizedBox(height: 14),
        if (filteredOrders.isEmpty)
          const SizedBox.shrink()
        else
          ...filteredOrders.map(
            (order) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AdminOrderCard(order: order),
            ),
          ),
      ],
    );
  }

  bool _matchesQuery(_GateEntry entry) {
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      entry.order.id,
      entry.order.eventTitle,
      entry.order.buyerName,
      entry.ticket.attendeeName,
      entry.ticket.qrToken,
      entry.ticket.tierName,
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  bool _orderMatchesQuery(TicketOrder order) {
    if (_query.isEmpty) {
      return true;
    }
    final haystack = [
      order.id,
      order.eventTitle,
      order.buyerName,
      order.buyerEmail,
      order.buyerPhone,
    ].join(' ').toLowerCase();
    return haystack.contains(_query);
  }
}

class _TicketsOpsHero extends StatelessWidget {
  const _TicketsOpsHero({required this.openGateCount});

  final int openGateCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [context.palette.gold, context.palette.coral],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ticket desk',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$openGateCount tickets still need action at the gate.',
            style: context.text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            'This admin lane keeps lookup, cash-at-gate collection, QR validation, and ticket-link copying together.',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }
}

class _GateEntryCard extends StatelessWidget {
  const _GateEntryCard({required this.entry});

  final _GateEntry entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.ticket.attendeeName,
                        style: context.text.titleLarge?.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.order.eventTitle,
                        style: context.text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: entry.ticket.status == TicketStatus.unpaid
                      ? 'Collect and admit'
                      : 'Ready to admit',
                  color: entry.ticket.status == TicketStatus.unpaid
                      ? context.palette.coral
                      : context.palette.teal,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatusPill(label: entry.order.id),
                _StatusPill(label: entry.ticket.qrToken),
                _StatusPill(label: entry.ticket.tierName),
                _StatusPill(
                  label: _paymentStatusLabel(entry.order.paymentStatus),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      context.read<VennuzoRepository>().admitTicket(
                        entry.order.id,
                        entry.ticket.ticketId,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${entry.ticket.attendeeName} admitted.',
                          ),
                        ),
                      );
                    },
                    child: Text(
                      entry.ticket.status == TicketStatus.unpaid
                          ? 'Collect and admit'
                          : 'Admit ticket',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: entry.ticket.qrToken),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied ${entry.ticket.qrToken}.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Copy QR token',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({required this.order});

  final TicketOrder order;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<VennuzoRepository>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.eventTitle,
                        style: context.text.titleLarge?.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${order.buyerName} • ${formatMoney(order.totalAmount)}',
                        style: context.text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                _StatusPill(label: _paymentStatusLabel(order.paymentStatus)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatusPill(label: order.id, color: context.palette.ink),
                _StatusPill(label: '${order.ticketCount} tickets'),
                _StatusPill(
                  label: repository.buildPublicTicketLink(order.id),
                  color: context.palette.teal,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GateEntry {
  const _GateEntry({required this.order, required this.ticket});

  final TicketOrder order;
  final EventTicket ticket;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.palette.canvas;
    final foreground = color == null ? context.palette.ink : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _paymentStatusLabel(TicketPaymentStatus status) {
  return switch (status) {
    TicketPaymentStatus.initiated => 'Initiated',
    TicketPaymentStatus.pending => 'Pending',
    TicketPaymentStatus.paid => 'Paid',
    TicketPaymentStatus.cashAtGate => 'Cash at gate',
    TicketPaymentStatus.cashAtGatePaid => 'Gate settled',
    TicketPaymentStatus.complimentary => 'Complimentary',
    TicketPaymentStatus.failed => 'Failed',
  };
}
