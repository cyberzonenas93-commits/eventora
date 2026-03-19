import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../data/services/vennuzo_payment_service.dart';
import '../../data/services/vennuzo_ticket_order_monitor.dart';
import '../../domain/models/ticket_models.dart';

class VennuzoTicketPaymentStatusScreen extends StatefulWidget {
  const VennuzoTicketPaymentStatusScreen({
    super.key,
    required this.orderId,
    required this.initialOrder,
    required this.checkoutUrl,
  });

  final String orderId;
  final TicketOrder initialOrder;
  final String checkoutUrl;

  @override
  State<VennuzoTicketPaymentStatusScreen> createState() =>
      _VennuzoTicketPaymentStatusScreenState();
}

class _VennuzoTicketPaymentStatusScreenState
    extends State<VennuzoTicketPaymentStatusScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _orderSubscription;
  late TicketOrder _order;
  bool _refreshing = false;
  int _autoChecks = 0;

  bool get _paymentConfirmed =>
      _order.status == TicketOrderStatus.paid &&
      _order.paymentStatus == TicketPaymentStatus.paid;
  bool get _ticketsReady => _order.tickets.isNotEmpty;
  bool get _isPaid => _paymentConfirmed && _ticketsReady;
  bool get _isFailed => _order.paymentStatus == TicketPaymentStatus.failed;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _subscribeToOrder();
    _scheduleWarmRefreshes();
    VennuzoTicketOrderMonitor.startMonitoring(
      orderId: widget.orderId,
      onPoll: _refreshFromHubtel,
    );
  }

  @override
  void dispose() {
    VennuzoTicketOrderMonitor.stopMonitoring(widget.orderId);
    _orderSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToOrder() {
    _orderSubscription = FirebaseFirestore.instance
        .collection('event_ticket_orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((snapshot) {
          final remoteOrder = VennuzoPaymentService.orderFromDocument(
            snapshot,
          );
          if (remoteOrder == null) {
            return;
          }
          _applyOrder(remoteOrder);
        });
  }

  void _scheduleWarmRefreshes() {
    for (final delay in const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ]) {
      Future<void>.delayed(delay, () {
        if (!mounted || _isPaid) {
          return;
        }
        unawaited(_refreshFromHubtel());
      });
    }
  }

  void _applyOrder(TicketOrder order) {
    context.read<VennuzoRepository>().upsertOrder(order);
    if (!mounted) {
      return;
    }
    setState(() => _order = order);
    if (_isPaid || _isFailed) {
      VennuzoTicketOrderMonitor.stopMonitoring(widget.orderId);
    }
  }

  Future<void> _refreshFromHubtel() async {
    if (_refreshing) {
      return;
    }

    setState(() {
      _refreshing = true;
      _autoChecks += 1;
    });
    try {
      final order = await VennuzoPaymentService.checkHubtelTicketStatus(
        widget.orderId,
      );
      if (order != null) {
        _applyOrder(order);
      }
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      if (_autoChecks > 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not refresh ticket payment.'),
          ),
        );
      }
    } on VennuzoPaymentException catch (error) {
      if (!mounted) {
        return;
      }
      if (_autoChecks > 3) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _openCheckoutAgain() async {
    try {
      await VennuzoPaymentService.startPaymentForExistingOrder(widget.orderId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hubtel checkout opened again.')),
      );
    } on VennuzoPaymentException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not reopen payment.')),
      );
    }
  }

  Future<void> _copyTicketLink() async {
    final link = context.read<VennuzoRepository>().buildPublicTicketLink(
      widget.orderId,
    );
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ticket link copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final statusColor = _isPaid
        ? palette.teal
        : _isFailed
        ? palette.coral
        : _paymentConfirmed
        ? palette.teal
        : palette.gold;
    final statusTitle = _isPaid
        ? 'Payment confirmed'
        : _isFailed
        ? 'Payment not completed'
        : _paymentConfirmed
        ? 'Issuing tickets'
        : 'Waiting for Hubtel';
    final statusBody = _isPaid
        ? 'Hubtel has confirmed the payment and Vennuzo has issued the tickets for this order.'
        : _isFailed
        ? 'This order is still open. You can reopen Hubtel and try again.'
        : _paymentConfirmed
        ? 'Hubtel has confirmed the payment. Vennuzo is still attaching the QR tickets to the order.'
        : 'Hubtel sometimes takes a few seconds to call back. Keep this screen open and refresh if needed.';

    return Scaffold(
      appBar: AppBar(title: const Text('Ticket payment status')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: [statusColor, statusColor.withValues(alpha: 0.76)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusTitle,
                  style: context.text.headlineSmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _order.eventTitle,
                  style: context.text.titleLarge?.copyWith(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  statusBody,
                  style: context.text.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeroPill(label: 'Order ${widget.orderId}'),
                    _HeroPill(label: _paymentStatusLabel(_order.paymentStatus)),
                    _HeroPill(label: formatMoney(_order.totalAmount)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected tiers',
                    style: context.text.titleLarge?.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  ..._order.selectedTiers.map(
                    (selection) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
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
                          const SizedBox(width: 12),
                          Text(
                            formatMoney(selection.subtotal),
                            style: context.text.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Issued tickets',
                    style: context.text.titleLarge?.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  if (_order.tickets.isEmpty)
                    Text(
                      _isPaid
                          ? 'Hubtel confirmed the payment, but ticket issuance is still syncing.'
                          : 'Tickets are issued only after Hubtel confirms the payment callback.',
                      style: context.text.bodyMedium,
                    )
                  else
                    ..._order.tickets.map(
                      (ticket) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ticket.tierName,
                                    style: context.text.bodyLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    ticket.qrToken,
                                    style: context.text.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _ticketStatusLabel(ticket.status),
                              style: context.text.bodyMedium?.copyWith(
                                color: palette.slate,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _autoChecks == 0
                ? 'Vennuzo will keep checking Hubtel in the background while this screen is open.'
                : 'Automatic checks so far: $_autoChecks',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: 18),
          if (_isPaid) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _copyTicketLink,
                child: const Text('Copy ticket link'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _refreshing ? null : _refreshFromHubtel,
                child: Text(
                  _refreshing ? 'Checking Hubtel...' : 'Refresh status',
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _openCheckoutAgain,
                child: const Text('Open Hubtel again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _paymentStatusLabel(TicketPaymentStatus status) => switch (status) {
  TicketPaymentStatus.initiated => 'Initiated',
  TicketPaymentStatus.pending => 'Pending',
  TicketPaymentStatus.paid => 'Paid',
  TicketPaymentStatus.cashAtGate => 'Cash at gate',
  TicketPaymentStatus.cashAtGatePaid => 'Gate settled',
  TicketPaymentStatus.complimentary => 'Complimentary',
  TicketPaymentStatus.failed => 'Failed',
};

String _ticketStatusLabel(TicketStatus status) => switch (status) {
  TicketStatus.issued => 'Issued',
  TicketStatus.unpaid => 'Awaiting gate payment',
  TicketStatus.admitted => 'Admitted',
};
