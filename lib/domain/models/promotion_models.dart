enum PromotionStatus { draft, scheduled, live, completed }

enum PromotionChannel { push, sms, shareLink, featured, announcement }

class PromotionCampaign {
  const PromotionCampaign({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.name,
    this.createdByUserId,
    required this.status,
    required this.channels,
    required this.scheduledAt,
    required this.pushAudience,
    required this.smsAudience,
    required this.shareLinkEnabled,
    required this.budget,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String eventId;
  final String eventTitle;
  final String name;
  final String? createdByUserId;
  final PromotionStatus status;
  final List<PromotionChannel> channels;
  final DateTime? scheduledAt;
  final int pushAudience;
  final int smsAudience;
  final bool shareLinkEnabled;
  final double budget;
  final String message;
  final DateTime createdAt;

  PromotionCampaign copyWith({
    String? createdByUserId,
    bool clearCreatedByUserId = false,
    PromotionStatus? status,
    DateTime? scheduledAt,
    List<PromotionChannel>? channels,
    int? pushAudience,
    int? smsAudience,
    bool? shareLinkEnabled,
    double? budget,
    String? message,
  }) {
    return PromotionCampaign(
      id: id,
      eventId: eventId,
      eventTitle: eventTitle,
      name: name,
      createdByUserId: clearCreatedByUserId
          ? null
          : createdByUserId ?? this.createdByUserId,
      status: status ?? this.status,
      channels: channels ?? this.channels,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      pushAudience: pushAudience ?? this.pushAudience,
      smsAudience: smsAudience ?? this.smsAudience,
      shareLinkEnabled: shareLinkEnabled ?? this.shareLinkEnabled,
      budget: budget ?? this.budget,
      message: message ?? this.message,
      createdAt: createdAt,
    );
  }
}

class RsvpRecord {
  const RsvpRecord({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    this.attendeeUserId,
    required this.name,
    required this.phone,
    required this.guestCount,
    required this.bookTable,
    required this.createdAt,
  });

  final String id;
  final String eventId;
  final String eventTitle;
  final String? attendeeUserId;
  final String name;
  final String phone;
  final int guestCount;
  final bool bookTable;
  final DateTime createdAt;
}
