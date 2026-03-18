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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _TicketsHero(
          ticketCount: orders.length,
          paidCount: paidCount,
          reservedCount: reservedCount,
          isGuest: session.isGuest,
        ),
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
        SectionHeading(
          title: 'Ready at the door',
          subtitle: session.isGuest
              ? 'Sign in to keep your tickets, reservations, and entry links in one place.'
              : 'See which tickets are ready to use and which ones still need payment at the door.',
        ),
        const SizedBox(height: 14),
        if (session.isGuest)
          EmptyStateCard(
            title: 'Save your tickets to your account',
            body:
                'Sign in to keep every order, reservation, and ticket link together in your Eventora wallet.',
            icon: Icons.qr_code_scanner_outlined,
            actionLabel: 'Sign in',
            onAction: () => _promptForAccess(context),
          )
        else
          _GateQueue(),
        const SizedBox(height: 26),
        SectionHeading(
          title: 'Saved orders',
          subtitle:
              'Every order keeps the details, attendee names, and shareable link together so reopening it later is effortless.',
        ),
        const SizedBox(height: 14),
        if (session.isGuest)
          const SizedBox.shrink()
        else if (orders.isEmpty)
          const EmptyStateCard(
            title: 'No orders yet',
            body:
                'As soon as you reserve or buy a ticket, it will show up here with all of the details you need.',
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
      title: 'Tickets are easier to manage with an account',
      body:
          'Create an Eventora account to save orders, ticket links, and reservations in one place.',
    );
  }
}

class _TicketsHero extends StatelessWidget {
  const _TicketsHero({
    required this.ticketCount,
    required this.paidCount,
    required this.reservedCount,
    required this.isGuest,
  });

  final int ticketCount;
  final int paidCount;
  final int reservedCount;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [palette.primaryStart, palette.gold, palette.primaryEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primaryStart.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your tickets and reservations',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'Sign in once and keep every RSVP, order, and ticket link together.'
                : '$ticketCount orders are saved in your wallet right now.',
            style: context.text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            isGuest
                ? 'You can keep browsing as a guest. When you are ready, sign in to save tickets and open them quickly at the door.'
                : 'Open any order to see who it is for, whether it is paid, and what is ready to scan at entry.',
            style: context.text.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
          if (!isGuest) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoPill(label: '$paidCount paid'),
                _InfoPill(label: '$reservedCount pay-at-door'),
                _InfoPill(label: '$ticketCount saved orders'),
              ],
            ),
          ],
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
          if (ticket.status != TicketStatus.admitted)
            _GateEntry(order: order, ticket: ticket),
    ];

    if (entries.isEmpty) {
      return const EmptyStateCard(
        title: 'Nothing needs attention right now',
        body: 'Every saved ticket in your account has already been checked in.',
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
                                Text(
                                  entry.ticket.attendeeName,
                                  style: context.text.titleLarge?.copyWith(
                                    fontSize: 20,
                                  ),
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
                          _InfoPill(
                            label: _paymentStatusLabel(
                              entry.order.paymentStatus,
                            ),
                          ),
                          _InfoPill(label: 'Code ${entry.ticket.qrToken}'),
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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ticket.attendeeName,
                                  style: context.text.bodyLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${ticket.tierName} • Code ${ticket.qrToken}',
                                  style: context.text.bodyMedium,
                                ),
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
                        const SnackBar(content: Text('Order link copied.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy order link'),
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

String _orderStatusLabel(TicketOrderStatus status) => switch (status) {
  TicketOrderStatus.pending => 'On the way',
  TicketOrderStatus.reserved => 'Reserved',
  TicketOrderStatus.paid => 'Paid',
};

String _paymentStatusLabel(TicketPaymentStatus status) => switch (status) {
  TicketPaymentStatus.initiated => 'Started',
  TicketPaymentStatus.pending => 'Pending',
  TicketPaymentStatus.paid => 'Paid',
  TicketPaymentStatus.cashAtGate => 'Pay at door',
  TicketPaymentStatus.cashAtGatePaid => 'Paid at door',
  TicketPaymentStatus.complimentary => 'Free pass',
  TicketPaymentStatus.failed => 'Failed',
};

String _ticketStatusLabel(TicketStatus status) => switch (status) {
  TicketStatus.issued => 'Ready to use',
  TicketStatus.unpaid => 'Pay at door',
  TicketStatus.admitted => 'Checked in',
};
