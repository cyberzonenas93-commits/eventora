import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/account_models.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/ticket_models.dart';

class VennuzoPaymentException implements Exception {
  const VennuzoPaymentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VennuzoCheckoutSession {
  const VennuzoCheckoutSession({
    required this.order,
    required this.checkoutUrl,
    required this.launched,
  });

  final TicketOrder order;
  final String checkoutUrl;
  final bool launched;
}

class VennuzoPaymentService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<VennuzoCheckoutSession> startPaidCheckout({
    required EventModel event,
    required Map<String, int> selections,
    required VennuzoViewer viewer,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const VennuzoPaymentException(
        'Sign in before starting ticket payment.',
      );
    }

    final selectedTiers = _buildSelections(event, selections);
    final totalAmount = selectedTiers.fold<double>(
      0,
      (runningTotal, selection) => runningTotal + selection.subtotal,
    );
    if (selectedTiers.isEmpty || totalAmount <= 0) {
      throw const VennuzoPaymentException(
        'Select at least one paid ticket tier.',
      );
    }

    final buyerName = _firstNonEmpty(
      viewer.displayName,
      user.displayName,
      'Vennuzo guest',
    );
    final buyerPhone = _normalizePhone(viewer.phone ?? user.phoneNumber);
    final buyerEmail = _firstNonEmpty(viewer.email, user.email);
    final orderRef = _firestore.collection('event_ticket_orders').doc();
    final now = DateTime.now();

    await _ensureUserProfile(
      uid: user.uid,
      displayName: buyerName,
      email: buyerEmail,
      phone: buyerPhone,
    );

    await orderRef.set(<String, Object?>{
      'eventId': event.id,
      'occurrenceId': '${event.id}_primary',
      'organizationId': 'org_${event.createdBy}',
      'eventTitle': event.title,
      'buyerId': user.uid,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'buyerEmail': buyerEmail,
      'selectedTiers': selectedTiers
          .map(
            (selection) => <String, Object?>{
              'tierId': selection.tierId,
              'name': selection.name,
              'price': selection.price,
              'quantity': selection.quantity,
            },
          )
          .toList(),
      'totalAmount': totalAmount,
      'currency': event.ticketing.currency,
      'status': 'pending',
      'paymentStatus': 'initiated',
      'source': 'app',
      'eventSnapshot': _eventSnapshot(event),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final callable = _functions.httpsCallable(
      'createEventTicketPaymentForOrder',
    );
    final result = await callable.call(<String, Object?>{
      'orderId': orderRef.id,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final checkoutUrl = (data['checkoutUrl'] as String? ?? '').trim();
    if (checkoutUrl.isEmpty) {
      throw const VennuzoPaymentException(
        'Hubtel did not return a checkout link.',
      );
    }

    final launched = await _launchCheckoutUrl(checkoutUrl);
    final order = TicketOrder(
      id: orderRef.id,
      eventId: event.id,
      eventTitle: event.title,
      buyerUserId: user.uid,
      buyerName: buyerName,
      buyerPhone: buyerPhone,
      buyerEmail: buyerEmail,
      selectedTiers: selectedTiers,
      totalAmount: totalAmount,
      status: TicketOrderStatus.pending,
      paymentStatus: TicketPaymentStatus.pending,
      source: 'app',
      createdAt: now,
      updatedAt: now,
      tickets: const [],
    );

    return VennuzoCheckoutSession(
      order: order,
      checkoutUrl: checkoutUrl,
      launched: launched,
    );
  }

  static Future<String> startPaymentForExistingOrder(String orderId) async {
    final callable = _functions.httpsCallable(
      'createEventTicketPaymentForOrder',
    );
    final result = await callable.call(<String, Object?>{'orderId': orderId});
    final data = Map<String, dynamic>.from(result.data as Map);
    final checkoutUrl = (data['checkoutUrl'] as String? ?? '').trim();
    if (checkoutUrl.isEmpty) {
      throw const VennuzoPaymentException('Payment link unavailable.');
    }
    await _launchCheckoutUrl(checkoutUrl);
    return checkoutUrl;
  }

  static Future<TicketOrder?> refreshOrderFromServer(String orderId) async {
    final snapshot = await _firestore
        .collection('event_ticket_orders')
        .doc(orderId)
        .get(const GetOptions(source: Source.server));
    return orderFromDocument(snapshot);
  }

  static Future<TicketOrder?> checkHubtelTicketStatus(String orderId) async {
    await _functions.httpsCallable('checkHubtelTicketStatus').call(
      <String, Object?>{'orderId': orderId},
    );
    return refreshOrderFromServer(orderId);
  }

  static TicketOrder? orderFromDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) {
      return null;
    }
    final data = snapshot.data();
    if (data == null) {
      return null;
    }

    final selectedTiers = _parseSelections(data['selectedTiers']);
    final createdAt = _timestampToDate(data['createdAt']) ?? DateTime.now();
    final updatedAt =
        _timestampToDate(data['updatedAt']) ??
        _timestampToDate(data['paidAt']) ??
        createdAt;
    final paymentStatus = _paymentStatusFromValue(data['paymentStatus']);
    final status = _orderStatusFromValue(data['status']);
    final buyerName = (data['buyerName'] as String? ?? '').trim();
    final eventId = (data['eventId'] as String? ?? '').trim();
    final parsedTickets = _parseTickets(
      orderId: snapshot.id,
      eventId: eventId,
      buyerName: buyerName,
      selectedTiers: selectedTiers,
      createdAt: createdAt,
      rawTickets: data['tickets'],
      paymentStatus: paymentStatus,
    );

    return TicketOrder(
      id: snapshot.id,
      eventId: eventId,
      eventTitle: (data['eventTitle'] as String? ?? '').trim(),
      buyerUserId: (data['buyerId'] as String?)?.trim(),
      buyerName: buyerName,
      buyerPhone: (data['buyerPhone'] as String? ?? '').trim(),
      buyerEmail: (data['buyerEmail'] as String? ?? '').trim(),
      selectedTiers: selectedTiers,
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0,
      status: status,
      paymentStatus: paymentStatus,
      source: (data['source'] as String? ?? 'app').trim(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      tickets: parsedTickets,
    );
  }

  static List<TicketSelection> _buildSelections(
    EventModel event,
    Map<String, int> selections,
  ) {
    final selectedTiers = <TicketSelection>[];
    for (final tier in event.ticketing.tiers) {
      final quantity = selections[tier.tierId] ?? 0;
      if (quantity <= 0) {
        continue;
      }
      selectedTiers.add(
        TicketSelection(
          tierId: tier.tierId,
          name: tier.name,
          price: tier.price,
          quantity: quantity,
        ),
      );
    }
    return selectedTiers;
  }

  static Future<void> _ensureUserProfile({
    required String uid,
    required String displayName,
    required String email,
    required String phone,
  }) async {
    await _firestore.collection('users').doc(uid).set(<String, Object?>{
      'displayName': displayName,
      'email': email,
      'phone': phone,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Map<String, Object?> _eventSnapshot(EventModel event) {
    return <String, Object?>{
      'id': event.id,
      'title': event.title,
      'description': event.description,
      'venue': event.venue,
      'city': event.city,
      'organizationId': 'org_${event.createdBy}',
      'createdBy': event.createdBy,
      'visibility': event.isPrivate ? 'private' : 'public',
      'status': 'published',
      'timezone': 'Africa/Accra',
      'startAt': Timestamp.fromDate(event.startDate),
      'endAt': event.endDate == null
          ? null
          : Timestamp.fromDate(event.endDate!),
      'ticketing': <String, Object?>{
        'enabled': event.ticketing.enabled,
        'requireTicket': event.ticketing.requireTicket,
        'currency': event.ticketing.currency,
        'tiers': event.ticketing.tiers
            .map(
              (tier) => <String, Object?>{
                'tierId': tier.tierId,
                'name': tier.name,
                'price': tier.price,
                'maxQuantity': tier.maxQuantity,
                'sold': tier.sold,
                'description': tier.description,
              },
            )
            .toList(),
      },
      'distribution': <String, Object?>{
        'allowSharing': event.allowSharing,
        'sendPushNotification': event.sendPushNotification,
        'sendSmsNotification': event.sendSmsNotification,
      },
      'lineup': <String, Object?>{
        'performers': event.performers,
        'djs': event.djs,
        'mcs': event.mcs,
      },
      'mood': event.mood.name,
      'tags': event.tags,
      'metrics': <String, Object?>{
        'likesCount': event.likesCount,
        'rsvpCount': event.rsvpCount,
        'ticketCount': event.ticketing.totalSold,
        'grossRevenue': 0,
      },
    };
  }

  static Future<bool> _launchCheckoutUrl(String checkoutUrl) async {
    final uri = Uri.tryParse(checkoutUrl);
    if (uri == null) {
      throw const VennuzoPaymentException('Checkout URL is invalid.');
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static List<TicketSelection> _parseSelections(Object? rawSelections) {
    final selections = <TicketSelection>[];
    for (final raw in (rawSelections as List<dynamic>? ?? const <dynamic>[])) {
      final map = Map<String, dynamic>.from(raw as Map);
      selections.add(
        TicketSelection(
          tierId: (map['tierId'] as String? ?? '').trim(),
          name: (map['name'] as String? ?? 'General').trim(),
          price: (map['price'] as num?)?.toDouble() ?? 0,
          quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return selections.where((selection) => selection.quantity > 0).toList();
  }

  static List<EventTicket> _parseTickets({
    required String orderId,
    required String eventId,
    required String buyerName,
    required List<TicketSelection> selectedTiers,
    required DateTime createdAt,
    required Object? rawTickets,
    required TicketPaymentStatus paymentStatus,
  }) {
    final tickets = <EventTicket>[];
    final ticketMaps = <Map<String, dynamic>>[];
    if (rawTickets is Map) {
      for (final entry in rawTickets.entries) {
        ticketMaps.add(
          Map<String, dynamic>.from(entry.value as Map)
            ..putIfAbsent('ticketId', () => entry.key),
        );
      }
    } else if (rawTickets is Iterable) {
      for (final rawTicket in rawTickets) {
        ticketMaps.add(Map<String, dynamic>.from(rawTicket as Map));
      }
    }

    for (final raw in ticketMaps) {
      final issuedAt = _timestampToDate(raw['issuedAt']) ?? createdAt;
      tickets.add(
        EventTicket(
          ticketId: (raw['ticketId'] as String? ?? '').trim(),
          orderId: orderId,
          eventId: eventId,
          tierId: (raw['tierId'] as String? ?? '').trim(),
          tierName: (raw['tierName'] as String? ?? 'General').trim(),
          qrToken: (raw['qrToken'] as String? ?? '').trim(),
          status: _ticketStatusFromValue(raw['status']),
          attendeeName: (raw['attendeeName'] as String? ?? buyerName).trim(),
          price: (raw['price'] as num?)?.toDouble() ?? 0,
          issuedAt: issuedAt,
          admittedAt: _timestampToDate(raw['admittedAt']),
        ),
      );
    }

    if (tickets.isNotEmpty || paymentStatus != TicketPaymentStatus.cashAtGate) {
      return tickets;
    }

    var sequence = 1;
    for (final selection in selectedTiers) {
      for (var index = 0; index < selection.quantity; index++) {
        tickets.add(
          EventTicket(
            ticketId: '${orderId}_${selection.tierId}_$sequence',
            orderId: orderId,
            eventId: eventId,
            tierId: selection.tierId,
            tierName: selection.name,
            qrToken: 'reservation_${orderId}_$sequence',
            status: TicketStatus.unpaid,
            attendeeName: buyerName,
            price: selection.price,
            issuedAt: createdAt,
          ),
        );
        sequence += 1;
      }
    }
    return tickets;
  }

  static TicketOrderStatus _orderStatusFromValue(Object? value) {
    return switch ((value as String? ?? '').trim().toLowerCase()) {
      'reserved' => TicketOrderStatus.reserved,
      'paid' => TicketOrderStatus.paid,
      _ => TicketOrderStatus.pending,
    };
  }

  static TicketPaymentStatus _paymentStatusFromValue(Object? value) {
    final normalized = (value as String? ?? '')
        .trim()
        .replaceAll(RegExp(r'[_\s-]+'), '')
        .toLowerCase();
    return switch (normalized) {
      'pending' => TicketPaymentStatus.pending,
      'paid' => TicketPaymentStatus.paid,
      'cashatgate' => TicketPaymentStatus.cashAtGate,
      'cashatgatepaid' => TicketPaymentStatus.cashAtGatePaid,
      'complimentary' => TicketPaymentStatus.complimentary,
      'failed' || 'cancelled' || 'canceled' => TicketPaymentStatus.failed,
      _ => TicketPaymentStatus.initiated,
    };
  }

  static TicketStatus _ticketStatusFromValue(Object? value) {
    return switch ((value as String? ?? '').trim().toLowerCase()) {
      'admitted' => TicketStatus.admitted,
      'unpaid' => TicketStatus.unpaid,
      _ => TicketStatus.issued,
    };
  }

  static DateTime? _timestampToDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static String _firstNonEmpty(
    String? first,
    String? second, [
    String fallback = '',
  ]) {
    final one = (first ?? '').trim();
    if (one.isNotEmpty) {
      return one;
    }
    final two = (second ?? '').trim();
    if (two.isNotEmpty) {
      return two;
    }
    return fallback;
  }

  static String _normalizePhone(String? phone) {
    final digits = (phone ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) {
      return '';
    }
    if (digits.startsWith('+233')) {
      return digits;
    }
    if (digits.startsWith('233') && digits.length == 12) {
      return '+$digits';
    }
    if (digits.startsWith('0') && digits.length == 10) {
      return '+233${digits.substring(1)}';
    }
    if (digits.length == 9) {
      return '+233$digits';
    }
    return digits.startsWith('+') ? digits : '+$digits';
  }
}
