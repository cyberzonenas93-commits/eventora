enum TicketOrderStatus { pending, reserved, paid }

enum TicketPaymentStatus {
  initiated,
  pending,
  paid,
  cashAtGate,
  cashAtGatePaid,
  complimentary,
  failed,
}

enum TicketStatus { issued, unpaid, admitted }

class TicketSelection {
  const TicketSelection({
    required this.tierId,
    required this.name,
    required this.price,
    required this.quantity,
  });

  final String tierId;
  final String name;
  final double price;
  final int quantity;

  double get subtotal => price * quantity;
}

class EventTicket {
  const EventTicket({
    required this.ticketId,
    required this.orderId,
    required this.eventId,
    required this.tierId,
    required this.tierName,
    required this.qrToken,
    required this.status,
    required this.attendeeName,
    required this.price,
    required this.issuedAt,
    this.admittedAt,
  });

  final String ticketId;
  final String orderId;
  final String eventId;
  final String tierId;
  final String tierName;
  final String qrToken;
  final TicketStatus status;
  final String attendeeName;
  final double price;
  final DateTime issuedAt;
  final DateTime? admittedAt;

  EventTicket copyWith({
    TicketStatus? status,
    DateTime? admittedAt,
    String? attendeeName,
  }) {
    return EventTicket(
      ticketId: ticketId,
      orderId: orderId,
      eventId: eventId,
      tierId: tierId,
      tierName: tierName,
      qrToken: qrToken,
      status: status ?? this.status,
      attendeeName: attendeeName ?? this.attendeeName,
      price: price,
      issuedAt: issuedAt,
      admittedAt: admittedAt ?? this.admittedAt,
    );
  }
}

class TicketOrder {
  const TicketOrder({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    this.buyerUserId,
    required this.buyerName,
    required this.buyerPhone,
    required this.buyerEmail,
    required this.selectedTiers,
    required this.totalAmount,
    required this.status,
    required this.paymentStatus,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.tickets,
  });

  final String id;
  final String eventId;
  final String eventTitle;
  final String? buyerUserId;
  final String buyerName;
  final String buyerPhone;
  final String buyerEmail;
  final List<TicketSelection> selectedTiers;
  final double totalAmount;
  final TicketOrderStatus status;
  final TicketPaymentStatus paymentStatus;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<EventTicket> tickets;

  bool get isPaid => status == TicketOrderStatus.paid;
  int get ticketCount => tickets.isNotEmpty
      ? tickets.length
      : selectedTiers.fold<int>(
          0,
          (sum, selection) => sum + selection.quantity,
        );

  TicketOrder copyWith({
    String? buyerUserId,
    bool clearBuyerUserId = false,
    TicketOrderStatus? status,
    TicketPaymentStatus? paymentStatus,
    DateTime? updatedAt,
    List<EventTicket>? tickets,
  }) {
    return TicketOrder(
      id: id,
      eventId: eventId,
      eventTitle: eventTitle,
      buyerUserId: clearBuyerUserId ? null : buyerUserId ?? this.buyerUserId,
      buyerName: buyerName,
      buyerPhone: buyerPhone,
      buyerEmail: buyerEmail,
      selectedTiers: selectedTiers,
      totalAmount: totalAmount,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      source: source,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tickets: tickets ?? this.tickets,
    );
  }
}
