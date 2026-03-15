import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/eventora_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/ticket_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_heading.dart';
import '../account/auth_prompt_sheet.dart';

class TicketsScreen extends StatelessWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final session = context.watch<EventoraSessionController>();
    final orders = repository.orders;
    final admittedCount = orders.fold<int>(
      0,
      (sum, order) => sum + order.tickets.where((ticket) => ticket.status == TicketStatus.admitted).length,
    );
    final openGateCount = orders.fold<int>(
      0,
      (sum, order) => sum + order.tickets.where((ticket) => ticket.status != TicketStatus.admitted).length,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _TicketsHero(ticketCount: orders.length, isGuest: session.isGuest),
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
              value: '$admittedCount',
              icon: Icons.verified_outlined,
              highlight: context.palette.teal,
            ),
            MetricTile(
              label: 'Waiting at gate',
              value: '$openGateCount',
              icon: Icons.qr_code_scanner_outlined,
              highlight: context.palette.coral,
            ),
          ],
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Gate desk',
          subtitle: session.isGuest
              ? 'Sign in before you start validating tickets or collecting pay-at-gate reservations.'
              : 'Simulate QR validation and pay-at-gate collection from the same order model.',
        ),
        const SizedBox(height: 14),
        if (session.isGuest)
          EmptyStateCard(
            title: 'Ticket operations need an account',
            body: 'Sign in to access attendee orders, gate validation, and public ticket links.',
            icon: Icons.qr_code_scanner_outlined,
            actionLabel: 'Sign in',
            onAction: () => _promptForAccess(context),
          )
        else
          _GateQueue(),
        const SizedBox(height: 26),
        SectionHeading(
          title: 'Orders & ticket links',
          subtitle: 'Public ticket links stay attached to each order, which makes web and app flows consistent.',
        ),
        const SizedBox(height: 14),
        if (session.isGuest)
          const SizedBox.shrink()
        else if (orders.isEmpty)
          const EmptyStateCard(
            title: 'No ticket orders yet',
            body: 'Once a checkout happens, orders and issued tickets will show up here.',
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
    );
  }

  void _promptForAccess(BuildContext context) {
    showAuthPromptSheet(
      context,
      title: 'Ticket desks live behind sign-in',
      body: 'Create an Eventora account to see attendee orders, validate QR codes, and manage pay-at-gate entries.',
    );
  }
}

class _TicketsHero extends StatelessWidget {
  const _TicketsHero({
    required this.ticketCount,
    required this.isGuest,
  });

  final int ticketCount;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [palette.gold, palette.coral],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ticket operations',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'Guest access stops before gate operations, so reviewers can browse safely without touching live attendee data.'
                : '$ticketCount orders live in your wallet and gate flow.',
            style: context.text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'Sign in when you are ready to manage ticket orders, QR validation, and pay-at-gate reservations.'
                : 'The same order object handles paid tickets, complimentary issues later, and cash-at-gate reservations.',
            style: context.text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.86)),
          ),
        ],
      ),
    );
  }
}

class _GateQueue extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final entries = [
      for (final order in repository.orders)
        for (final ticket in order.tickets)
          if (ticket.status != TicketStatus.admitted) _GateEntry(order: order, ticket: ticket),
    ];

    if (entries.isEmpty) {
      return const EmptyStateCard(
        title: 'Gate queue is clear',
        body: 'Every ticket in the current local dataset has already been admitted.',
        icon: Icons.check_circle_outline,
      );
    }

    return Column(
      children: entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
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
                                Text(entry.ticket.attendeeName, style: context.text.titleLarge?.copyWith(fontSize: 20)),
                                const SizedBox(height: 6),
                                Text(entry.order.eventTitle, style: context.text.bodyMedium),
                              ],
                            ),
                          ),
                          _StatusPill(
                            label: _ticketStatusLabel(entry.ticket.status),
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
                          _InfoPill(label: entry.ticket.tierName),
                          _InfoPill(label: _paymentStatusLabel(entry.order.paymentStatus)),
                          _InfoPill(label: entry.ticket.qrToken),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<EventoraRepository>().admitTicket(
                                  entry.order.id,
                                  entry.ticket.ticketId,
                                );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${entry.ticket.attendeeName} admitted.')),
                            );
                          },
                          child: Text(
                            entry.ticket.status == TicketStatus.unpaid ? 'Collect and admit' : 'Admit ticket',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final TicketOrder order;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<EventoraRepository>();
    final publicLink = repository.buildPublicTicketLink(order.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.eventTitle, style: context.text.titleLarge?.copyWith(fontSize: 22)),
                      const SizedBox(height: 6),
                      Text(order.buyerName, style: context.text.bodyMedium),
                    ],
                  ),
                ),
                _StatusPill(
                  label: _orderStatusLabel(order.status),
                  color: order.status == TicketOrderStatus.paid ? context.palette.teal : context.palette.coral,
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
                    Expanded(child: Text(selection.name, style: context.text.bodyLarge)),
                    Text('x${selection.quantity}', style: context.text.bodyMedium),
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
                  Text('Issued tickets', style: context.text.titleLarge?.copyWith(fontSize: 18)),
                  const SizedBox(height: 10),
                  ...order.tickets.map(
                    (ticket) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ticket.attendeeName, style: context.text.bodyLarge),
                                const SizedBox(height: 4),
                                Text('${ticket.tierName} • ${ticket.qrToken}', style: context.text.bodyMedium),
                              ],
                            ),
                          ),
                          _StatusPill(
                            label: _ticketStatusLabel(ticket.status),
                            color: ticket.status == TicketStatus.admitted
                                ? context.palette.teal
                                : context.palette.ink,
                          ),
                        ],
                      ),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Public ticket link copied.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy ticket link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

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
      child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.palette.ink)),
    );
  }
}

class _GateEntry {
  const _GateEntry({
    required this.order,
    required this.ticket,
  });

  final TicketOrder order;
  final EventTicket ticket;
}

String _orderStatusLabel(TicketOrderStatus status) => switch (status) {
      TicketOrderStatus.pending => 'Pending',
      TicketOrderStatus.reserved => 'Reserved',
      TicketOrderStatus.paid => 'Paid',
    };

String _paymentStatusLabel(TicketPaymentStatus status) => switch (status) {
      TicketPaymentStatus.initiated => 'Initiated',
      TicketPaymentStatus.pending => 'Pending',
      TicketPaymentStatus.paid => 'Paid',
      TicketPaymentStatus.cashAtGate => 'Cash at gate',
      TicketPaymentStatus.cashAtGatePaid => 'Cash collected',
      TicketPaymentStatus.complimentary => 'Complimentary',
      TicketPaymentStatus.failed => 'Failed',
    };

String _ticketStatusLabel(TicketStatus status) => switch (status) {
      TicketStatus.issued => 'Issued',
      TicketStatus.unpaid => 'Unpaid',
      TicketStatus.admitted => 'Admitted',
    };
