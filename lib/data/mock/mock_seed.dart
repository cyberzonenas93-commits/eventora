import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../domain/models/ticket_models.dart';

class MockSeed {
  static const organizerId = 'organizer_angel';
  static const organizerName = 'Angel Artey';
  static const organizerPhone = '+233 24 000 0000';
  static const organizerEmail = 'angel@eventora.app';

  static List<EventModel> events() {
    final now = DateTime.now();
    return [
      EventModel(
        id: 'event_after_dark',
        title: 'Pulse Summit After Dark',
        description:
            'A headline event for founders, creators, and tastemakers with tiered ticketing, sponsor zones, and entry validation.',
        venue: 'Forum Hall',
        city: 'Accra',
        startDate: now.add(const Duration(days: 6, hours: 4)),
        endDate: now.add(const Duration(days: 6, hours: 10)),
        visibility: EventVisibility.publicEvent,
        createdBy: organizerId,
        createdAt: now.subtract(const Duration(days: 9)),
        ticketing: const EventTicketing(
          enabled: true,
          requireTicket: true,
          currency: 'GHS',
          tiers: [
            TicketTier(
              tierId: 'early',
              name: 'Early Access',
              price: 120,
              maxQuantity: 120,
              sold: 78,
              description: 'Fast-lane entry and welcome drink.',
            ),
            TicketTier(
              tierId: 'standard',
              name: 'Standard',
              price: 220,
              maxQuantity: 300,
              sold: 154,
              description: 'Main event access.',
            ),
            TicketTier(
              tierId: 'vip',
              name: 'VIP Circle',
              price: 480,
              maxQuantity: 60,
              sold: 24,
              description: 'Backstage lounge, premium seating, and artist meet window.',
            ),
          ],
        ),
        recurrence: const RecurrenceRule(),
        sendPushNotification: true,
        sendSmsNotification: true,
        allowSharing: true,
        djs: 'DJ Loft, Hype Monk',
        mcs: 'Naa Mingle',
        performers: 'Sefa, Kxng Joey',
        likesCount: 412,
        rsvpCount: 190,
        mood: EventMood.night,
        tags: const ['Ticketed', 'Featured', 'Music'],
      ),
      EventModel(
        id: 'event_rooftop',
        title: 'Open Canvas Rooftop Jam',
        description:
            'A community rooftop gathering with open RSVPs, optional support tickets, and creator booths.',
        venue: 'Kukun Skydeck',
        city: 'Accra',
        startDate: now.add(const Duration(days: 2, hours: 2)),
        endDate: now.add(const Duration(days: 2, hours: 8)),
        visibility: EventVisibility.publicEvent,
        createdBy: organizerId,
        createdAt: now.subtract(const Duration(days: 5)),
        ticketing: const EventTicketing(
          enabled: true,
          requireTicket: false,
          currency: 'GHS',
          tiers: [
            TicketTier(
              tierId: 'support',
              name: 'Support Pass',
              price: 40,
              maxQuantity: 200,
              sold: 61,
              description: 'Helps fund artist performance fees.',
            ),
            TicketTier(
              tierId: 'gate',
              name: 'Reserve & Pay at Gate',
              price: 0,
              maxQuantity: 80,
              sold: 12,
              description: 'Reserve now and settle at the entrance.',
            ),
          ],
        ),
        recurrence: const RecurrenceRule(),
        sendPushNotification: true,
        sendSmsNotification: false,
        allowSharing: true,
        djs: 'DJ Lali',
        mcs: 'Poet K',
        performers: 'Open mic rotation',
        likesCount: 129,
        rsvpCount: 246,
        mood: EventMood.sunrise,
        tags: const ['RSVP', 'Optional Tickets', 'Community'],
      ),
      EventModel(
        id: 'event_market',
        title: 'Sunday Loop Market',
        description:
            'A recurring neighborhood market with vendor booths, live sets, and promo SMS follow-ups to past attendees.',
        venue: 'Cantonments Yard',
        city: 'Accra',
        startDate: now.add(const Duration(days: 9, hours: 1)),
        endDate: now.add(const Duration(days: 9, hours: 7)),
        visibility: EventVisibility.publicEvent,
        createdBy: organizerId,
        createdAt: now.subtract(const Duration(days: 24)),
        ticketing: const EventTicketing(
          enabled: false,
          requireTicket: false,
          currency: 'GHS',
          tiers: [],
        ),
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          endType: RecurrenceEndType.afterOccurrences,
          endAfterOccurrences: 10,
        ),
        sendPushNotification: true,
        sendSmsNotification: true,
        allowSharing: true,
        djs: 'Market Sound Cartel',
        mcs: 'Host Ama',
        performers: 'Vendors and acoustic guests',
        likesCount: 86,
        rsvpCount: 74,
        mood: EventMood.garden,
        tags: const ['Recurring', 'Market', 'Family Friendly'],
      ),
      EventModel(
        id: 'event_private',
        title: 'Investor Listening Session',
        description:
            'A private event for selected guests, proof that private visibility and event-scoped permissions matter.',
        venue: 'Embassy House',
        city: 'Accra',
        startDate: now.add(const Duration(days: 13, hours: 3)),
        endDate: now.add(const Duration(days: 13, hours: 5)),
        visibility: EventVisibility.privateEvent,
        createdBy: organizerId,
        createdAt: now.subtract(const Duration(days: 3)),
        ticketing: const EventTicketing(
          enabled: true,
          requireTicket: true,
          currency: 'GHS',
          tiers: [
            TicketTier(
              tierId: 'invite',
              name: 'Invite Seat',
              price: 0,
              maxQuantity: 40,
              sold: 7,
              description: 'Complimentary seats controlled by the organizer.',
            ),
          ],
        ),
        recurrence: const RecurrenceRule(),
        sendPushNotification: false,
        sendSmsNotification: true,
        allowSharing: false,
        djs: 'None',
        mcs: 'Private moderator',
        performers: 'Panel only',
        likesCount: 12,
        rsvpCount: 11,
        mood: EventMood.electric,
        tags: const ['Private', 'Invite Only'],
      ),
    ];
  }

  static List<TicketOrder> orders() {
    final now = DateTime.now();
    return [
      TicketOrder(
        id: 'order_001',
        eventId: 'event_after_dark',
        eventTitle: 'Pulse Summit After Dark',
        buyerName: organizerName,
        buyerPhone: organizerPhone,
        buyerEmail: organizerEmail,
        selectedTiers: const [
          TicketSelection(
            tierId: 'vip',
            name: 'VIP Circle',
            price: 480,
            quantity: 2,
          ),
        ],
        totalAmount: 960,
        status: TicketOrderStatus.paid,
        paymentStatus: TicketPaymentStatus.paid,
        source: 'app',
        createdAt: now.subtract(const Duration(days: 1, hours: 8)),
        updatedAt: now.subtract(const Duration(days: 1, hours: 8)),
        tickets: [
          EventTicket(
            ticketId: 'order_001_vip_1',
            orderId: 'order_001',
            eventId: 'event_after_dark',
            tierId: 'vip',
            tierName: 'VIP Circle',
            qrToken: 'qr_vip_1',
            status: TicketStatus.issued,
            attendeeName: organizerName,
            price: 480,
            issuedAt: now.subtract(const Duration(days: 1, hours: 8)),
          ),
          EventTicket(
            ticketId: 'order_001_vip_2',
            orderId: 'order_001',
            eventId: 'event_after_dark',
            tierId: 'vip',
            tierName: 'VIP Circle',
            qrToken: 'qr_vip_2',
            status: TicketStatus.issued,
            attendeeName: 'Guest of Angel',
            price: 480,
            issuedAt: now.subtract(const Duration(days: 1, hours: 8)),
          ),
        ],
      ),
      TicketOrder(
        id: 'order_002',
        eventId: 'event_rooftop',
        eventTitle: 'Open Canvas Rooftop Jam',
        buyerName: organizerName,
        buyerPhone: organizerPhone,
        buyerEmail: organizerEmail,
        selectedTiers: const [
          TicketSelection(
            tierId: 'gate',
            name: 'Reserve & Pay at Gate',
            price: 0,
            quantity: 1,
          ),
        ],
        totalAmount: 0,
        status: TicketOrderStatus.reserved,
        paymentStatus: TicketPaymentStatus.cashAtGate,
        source: 'app',
        createdAt: now.subtract(const Duration(hours: 20)),
        updatedAt: now.subtract(const Duration(hours: 20)),
        tickets: [
          EventTicket(
            ticketId: 'order_002_gate_1',
            orderId: 'order_002',
            eventId: 'event_rooftop',
            tierId: 'gate',
            tierName: 'Reserve & Pay at Gate',
            qrToken: 'qr_gate_1',
            status: TicketStatus.unpaid,
            attendeeName: organizerName,
            price: 0,
            issuedAt: now.subtract(const Duration(hours: 20)),
          ),
        ],
      ),
    ];
  }

  static List<RsvpRecord> rsvps() {
    final now = DateTime.now();
    return [
      RsvpRecord(
        id: 'rsvp_001',
        eventId: 'event_rooftop',
        eventTitle: 'Open Canvas Rooftop Jam',
        name: organizerName,
        phone: organizerPhone,
        guestCount: 3,
        bookTable: false,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ];
  }

  static List<PromotionCampaign> campaigns() {
    final now = DateTime.now();
    return [
      PromotionCampaign(
        id: 'promo_001',
        eventId: 'event_after_dark',
        eventTitle: 'Pulse Summit After Dark',
        name: '48-hour ticket push',
        status: PromotionStatus.live,
        channels: const [PromotionChannel.push, PromotionChannel.sms, PromotionChannel.shareLink],
        scheduledAt: now.subtract(const Duration(hours: 3)),
        pushAudience: 4300,
        smsAudience: 920,
        shareLinkEnabled: true,
        budget: 1250,
        message:
            'Doors open soon. Push VIP urgency to ticket buyers and send recovery links to warm SMS audience.',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      PromotionCampaign(
        id: 'promo_002',
        eventId: 'event_market',
        eventTitle: 'Sunday Loop Market',
        name: 'Recurring Sunday reminder',
        status: PromotionStatus.scheduled,
        channels: const [PromotionChannel.sms, PromotionChannel.featured],
        scheduledAt: now.add(const Duration(days: 4, hours: 10)),
        pushAudience: 0,
        smsAudience: 1200,
        shareLinkEnabled: true,
        budget: 380,
        message: 'Weekly reminder to market regulars with vendor spotlight and share QR.',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ];
  }
}
