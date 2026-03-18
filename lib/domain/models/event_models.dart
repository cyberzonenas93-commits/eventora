import 'package:flutter/material.dart';

enum EventVisibility { publicEvent, privateEvent }

enum RecurrenceFrequency { none, daily, weekly, monthly }

enum RecurrenceEndType { never, onDate, afterOccurrences }

enum ReminderTiming {
  onDay,
  oneDayBefore,
  twoDaysBefore,
  oneWeekBefore,
  custom,
}

enum EventMood { night, sunrise, electric, garden }

class RecurrenceRule {
  const RecurrenceRule({
    this.frequency = RecurrenceFrequency.none,
    this.interval = 1,
    this.endType = RecurrenceEndType.never,
    this.endDate,
    this.endAfterOccurrences,
  });

  final RecurrenceFrequency frequency;
  final int interval;
  final RecurrenceEndType endType;
  final DateTime? endDate;
  final int? endAfterOccurrences;

  bool get isRecurring => frequency != RecurrenceFrequency.none;

  String get description {
    if (!isRecurring) return 'No recurrence';
    final base = switch (frequency) {
      RecurrenceFrequency.daily => 'Every day',
      RecurrenceFrequency.weekly => 'Every week',
      RecurrenceFrequency.monthly => 'Every month',
      RecurrenceFrequency.none => 'No recurrence',
    };
    if (endType == RecurrenceEndType.onDate && endDate != null) {
      return '$base until ${endDate!.month}/${endDate!.day}/${endDate!.year}';
    }
    if (endType == RecurrenceEndType.afterOccurrences &&
        endAfterOccurrences != null) {
      return '$base for $endAfterOccurrences occurrences';
    }
    return base;
  }

  RecurrenceRule copyWith({
    RecurrenceFrequency? frequency,
    int? interval,
    RecurrenceEndType? endType,
    DateTime? endDate,
    int? endAfterOccurrences,
    bool clearEndDate = false,
  }) {
    return RecurrenceRule(
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      endType: endType ?? this.endType,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      endAfterOccurrences: endAfterOccurrences ?? this.endAfterOccurrences,
    );
  }
}

class TicketTier {
  const TicketTier({
    required this.tierId,
    required this.name,
    required this.price,
    required this.maxQuantity,
    required this.sold,
    this.description,
  });

  final String tierId;
  final String name;
  final double price;
  final int maxQuantity;
  final int sold;
  final String? description;

  int get remaining =>
      maxQuantity <= 0 ? 9999 : (maxQuantity - sold).clamp(0, maxQuantity);
  bool get soldOut => maxQuantity > 0 && sold >= maxQuantity;

  TicketTier copyWith({
    String? tierId,
    String? name,
    double? price,
    int? maxQuantity,
    int? sold,
    String? description,
  }) {
    return TicketTier(
      tierId: tierId ?? this.tierId,
      name: name ?? this.name,
      price: price ?? this.price,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      sold: sold ?? this.sold,
      description: description ?? this.description,
    );
  }
}

class EventTicketing {
  const EventTicketing({
    required this.enabled,
    required this.requireTicket,
    required this.currency,
    required this.tiers,
  });

  final bool enabled;
  final bool requireTicket;
  final String currency;
  final List<TicketTier> tiers;

  double? get minimumPrice {
    final priced = tiers.where((tier) => tier.price > 0).toList();
    if (priced.isEmpty) return null;
    return priced.map((tier) => tier.price).reduce((a, b) => a < b ? a : b);
  }

  int get totalSold => tiers.fold(0, (sum, tier) => sum + tier.sold);

  EventTicketing copyWith({
    bool? enabled,
    bool? requireTicket,
    String? currency,
    List<TicketTier>? tiers,
  }) {
    return EventTicketing(
      enabled: enabled ?? this.enabled,
      requireTicket: requireTicket ?? this.requireTicket,
      currency: currency ?? this.currency,
      tiers: tiers ?? this.tiers,
    );
  }
}

class EventLocation {
  const EventLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.placeId,
  });

  final String address;
  final double latitude;
  final double longitude;
  final String? placeId;

  EventLocation copyWith({
    String? address,
    double? latitude,
    double? longitude,
    String? placeId,
    bool clearPlaceId = false,
  }) {
    return EventLocation(
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      placeId: clearPlaceId ? null : placeId ?? this.placeId,
    );
  }
}

class EventModel {
  const EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.venue,
    required this.city,
    required this.startDate,
    required this.endDate,
    required this.visibility,
    required this.createdBy,
    required this.createdAt,
    required this.ticketing,
    required this.recurrence,
    required this.sendPushNotification,
    required this.sendSmsNotification,
    required this.allowSharing,
    required this.djs,
    required this.mcs,
    required this.performers,
    required this.likesCount,
    required this.rsvpCount,
    required this.mood,
    required this.tags,
    this.location,
  });

  final String id;
  final String title;
  final String description;
  final String venue;
  final String city;
  final DateTime startDate;
  final DateTime? endDate;
  final EventVisibility visibility;
  final String createdBy;
  final DateTime createdAt;
  final EventTicketing ticketing;
  final RecurrenceRule recurrence;
  final bool sendPushNotification;
  final bool sendSmsNotification;
  final bool allowSharing;
  final String djs;
  final String mcs;
  final String performers;
  final int likesCount;
  final int rsvpCount;
  final EventMood mood;
  final List<String> tags;
  final EventLocation? location;

  bool get isPrivate => visibility == EventVisibility.privateEvent;
  bool get isTicketed => ticketing.enabled;
  bool get hasLocation => location != null;

  EventModel copyWith({
    String? id,
    String? title,
    String? description,
    String? venue,
    String? city,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    EventVisibility? visibility,
    String? createdBy,
    DateTime? createdAt,
    EventTicketing? ticketing,
    RecurrenceRule? recurrence,
    bool? sendPushNotification,
    bool? sendSmsNotification,
    bool? allowSharing,
    String? djs,
    String? mcs,
    String? performers,
    int? likesCount,
    int? rsvpCount,
    EventMood? mood,
    List<String>? tags,
    EventLocation? location,
    bool clearLocation = false,
  }) {
    return EventModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      venue: venue ?? this.venue,
      city: city ?? this.city,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      visibility: visibility ?? this.visibility,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      ticketing: ticketing ?? this.ticketing,
      recurrence: recurrence ?? this.recurrence,
      sendPushNotification: sendPushNotification ?? this.sendPushNotification,
      sendSmsNotification: sendSmsNotification ?? this.sendSmsNotification,
      allowSharing: allowSharing ?? this.allowSharing,
      djs: djs ?? this.djs,
      mcs: mcs ?? this.mcs,
      performers: performers ?? this.performers,
      likesCount: likesCount ?? this.likesCount,
      rsvpCount: rsvpCount ?? this.rsvpCount,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
      location: clearLocation ? null : location ?? this.location,
    );
  }
}

class EventDraft {
  const EventDraft({
    required this.title,
    required this.description,
    required this.venue,
    required this.city,
    required this.startDate,
    this.endDate,
    required this.visibility,
    required this.ticketing,
    required this.recurrence,
    required this.sendPushNotification,
    required this.sendSmsNotification,
    required this.allowSharing,
    required this.djs,
    required this.mcs,
    required this.performers,
    required this.mood,
    required this.tags,
    this.location,
  });

  final String title;
  final String description;
  final String venue;
  final String city;
  final DateTime startDate;
  final DateTime? endDate;
  final EventVisibility visibility;
  final EventTicketing ticketing;
  final RecurrenceRule recurrence;
  final bool sendPushNotification;
  final bool sendSmsNotification;
  final bool allowSharing;
  final String djs;
  final String mcs;
  final String performers;
  final EventMood mood;
  final List<String> tags;
  final EventLocation? location;
}

extension EventMoodPalette on EventMood {
  List<Color> get colors => switch (this) {
    EventMood.night => const [Color(0xFF112A46), Color(0xFFE86B43)],
    EventMood.sunrise => const [Color(0xFFFFC56E), Color(0xFFFF7F50)],
    EventMood.electric => const [Color(0xFF2B7A78), Color(0xFF10212A)],
    EventMood.garden => const [Color(0xFF7EBB74), Color(0xFFF4E7B6)],
  };
}

extension ReminderTimingLabel on ReminderTiming {
  String get label => switch (this) {
    ReminderTiming.onDay => 'On the day',
    ReminderTiming.oneDayBefore => '1 day before',
    ReminderTiming.twoDaysBefore => '2 days before',
    ReminderTiming.oneWeekBefore => '1 week before',
    ReminderTiming.custom => 'Custom time',
  };
}
