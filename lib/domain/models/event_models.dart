import 'package:flutter/material.dart';

import '../../core/art/mood_art_palette.dart';

class VennuzoEventCategory {
  const VennuzoEventCategory({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.icon,
    required this.keywords,
  });

  final String id;
  final String label;
  final String shortLabel;
  final String description;
  final IconData icon;
  final List<String> keywords;
}

class EventTaxonomy {
  const EventTaxonomy._();

  static const defaultCategoryId = 'nightlife';

  static const categories = <VennuzoEventCategory>[
    VennuzoEventCategory(
      id: 'nightlife',
      label: 'Nightlife & Parties',
      shortLabel: 'Nightlife',
      description: 'Clubs, lounges, day parties, DJ nights, beach parties.',
      icon: Icons.nightlife_rounded,
      keywords: ['nightlife', 'club', 'party', 'after dark', 'lounge', 'vip'],
    ),
    VennuzoEventCategory(
      id: 'music_live',
      label: 'Music & Live Entertainment',
      shortLabel: 'Music',
      description: 'Concerts, comedy, theatre, poetry, screenings.',
      icon: Icons.music_note_rounded,
      keywords: ['music', 'concert', 'comedy', 'theatre', 'poetry', 'film'],
    ),
    VennuzoEventCategory(
      id: 'corporate_professional',
      label: 'Corporate & Professional',
      shortLabel: 'Corporate',
      description: 'Conferences, networking, retreats, seminars, launches.',
      icon: Icons.business_center_rounded,
      keywords: ['corporate', 'professional', 'conference', 'networking'],
    ),
    VennuzoEventCategory(
      id: 'marketing_sales',
      label: 'Marketing & Sales',
      shortLabel: 'Marketing',
      description: 'Activations, pop-ups, trade shows, expos, retail sales.',
      icon: Icons.campaign_rounded,
      keywords: [
        'marketing',
        'sales',
        'activation',
        'pop-up',
        'expo',
        'retail',
      ],
    ),
    VennuzoEventCategory(
      id: 'faith_spiritual',
      label: 'Faith & Spiritual',
      shortLabel: 'Faith',
      description: 'Church events, worship nights, crusades, retreats.',
      icon: Icons.church_rounded,
      keywords: ['faith', 'church', 'worship', 'spiritual', 'crusade'],
    ),
    VennuzoEventCategory(
      id: 'education_workshops',
      label: 'Education & Workshops',
      shortLabel: 'Workshops',
      description: 'Classes, bootcamps, masterclasses, trainings, lectures.',
      icon: Icons.school_rounded,
      keywords: ['education', 'workshop', 'class', 'bootcamp', 'training'],
    ),
    VennuzoEventCategory(
      id: 'food_drink',
      label: 'Food & Drink',
      shortLabel: 'Food',
      description: 'Brunches, tastings, chef nights, restaurant events.',
      icon: Icons.restaurant_rounded,
      keywords: ['food', 'drink', 'brunch', 'dinner', 'wine', 'tasting'],
    ),
    VennuzoEventCategory(
      id: 'arts_culture_fashion',
      label: 'Arts, Culture & Fashion',
      shortLabel: 'Culture',
      description: 'Exhibitions, fashion shows, cultural festivals.',
      icon: Icons.palette_rounded,
      keywords: ['art', 'arts', 'culture', 'fashion', 'gallery', 'festival'],
    ),
    VennuzoEventCategory(
      id: 'sports_fitness',
      label: 'Sports & Fitness',
      shortLabel: 'Sports',
      description: 'Tournaments, screenings, runs, yoga, wellness events.',
      icon: Icons.sports_basketball_rounded,
      keywords: ['sports', 'fitness', 'football', 'run', 'yoga', 'match'],
    ),
    VennuzoEventCategory(
      id: 'community_civic',
      label: 'Community & Civic',
      shortLabel: 'Community',
      description:
          'Town halls, fundraisers, volunteer drives, local gatherings.',
      icon: Icons.groups_rounded,
      keywords: ['community', 'civic', 'charity', 'fundraiser', 'meetup'],
    ),
    VennuzoEventCategory(
      id: 'family_kids',
      label: 'Family & Kids',
      shortLabel: 'Family',
      description: 'School events, family fun days, kids activities.',
      icon: Icons.family_restroom_rounded,
      keywords: ['family', 'kids', 'children', 'school', 'family friendly'],
    ),
    VennuzoEventCategory(
      id: 'lifestyle_wellness',
      label: 'Lifestyle & Wellness',
      shortLabel: 'Wellness',
      description: 'Beauty, health, self-care, and lifestyle socials.',
      icon: Icons.spa_rounded,
      keywords: ['lifestyle', 'wellness', 'beauty', 'health', 'self-care'],
    ),
    VennuzoEventCategory(
      id: 'tech_startup',
      label: 'Tech & Startup',
      shortLabel: 'Tech',
      description: 'Hackathons, demo days, meetups, pitch events.',
      icon: Icons.memory_rounded,
      keywords: ['tech', 'startup', 'hackathon', 'demo day', 'pitch'],
    ),
    VennuzoEventCategory(
      id: 'travel_experiences',
      label: 'Travel & Experiences',
      shortLabel: 'Travel',
      description: 'Tours, retreats, adventure trips, destination events.',
      icon: Icons.flight_takeoff_rounded,
      keywords: ['travel', 'tour', 'retreat', 'trip', 'destination'],
    ),
    VennuzoEventCategory(
      id: 'private_invite',
      label: 'Private / Invite-Only',
      shortLabel: 'Private',
      description: 'Weddings, birthdays, company parties, private ticketing.',
      icon: Icons.lock_rounded,
      keywords: ['private', 'invite', 'wedding', 'birthday', 'invitation'],
    ),
    VennuzoEventCategory(
      id: 'online_hybrid',
      label: 'Online / Hybrid',
      shortLabel: 'Online',
      description: 'Webinars, livestreams, virtual and hybrid conferences.',
      icon: Icons.connected_tv_rounded,
      keywords: ['online', 'hybrid', 'webinar', 'virtual', 'livestream'],
    ),
  ];

  static VennuzoEventCategory byId(String? value) {
    final id = canonicalCategoryId(value);
    return categories.firstWhere(
      (category) => category.id == id,
      orElse: () => categories.first,
    );
  }

  static String canonicalCategoryId(String? value) {
    final token = normalizeToken(value);
    if (token.isEmpty || token == 'all') return defaultCategoryId;
    for (final category in categories) {
      if (token == category.id ||
          token == normalizeToken(category.label) ||
          token == normalizeToken(category.shortLabel) ||
          category.keywords.any(
            (keyword) => token == normalizeToken(keyword),
          )) {
        return category.id;
      }
    }
    return switch (token) {
      'music' => 'music_live',
      'arts' => 'arts_culture_fashion',
      'business' => 'corporate_professional',
      'workshops' => 'education_workshops',
      'food_and_drink' => 'food_drink',
      'sports' => 'sports_fitness',
      'community' => 'community_civic',
      _ => token,
    };
  }

  static String inferCategoryId({
    String? categoryId,
    String? title,
    String? description,
    String? mood,
    Iterable<String> tags = const <String>[],
  }) {
    final direct = canonicalCategoryId(categoryId);
    if (categories.any((category) => category.id == direct)) return direct;

    final text = [
      title,
      description,
      mood,
      ...tags,
    ].whereType<String>().join(' ').toLowerCase();
    for (final category in categories) {
      if (category.keywords.any((keyword) => text.contains(keyword))) {
        return category.id;
      }
    }
    return defaultCategoryId;
  }

  static bool eventMatchesAny(EventModel event, Iterable<String> categoryIds) {
    final wanted = categoryIds
        .map(canonicalCategoryId)
        .where((id) => id.isNotEmpty && id != 'all')
        .toSet();
    if (wanted.isEmpty) return true;
    final eventId = inferCategoryId(
      categoryId: event.categoryId,
      title: event.title,
      description: event.description,
      mood: event.mood.name,
      tags: event.tags,
    );
    return wanted.contains(eventId);
  }

  static String normalizeToken(String? value) {
    return (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

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

enum EventDiscountVoucherType { percentage, fixedAmount }

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

class EventDiscountVoucher {
  const EventDiscountVoucher({
    required this.code,
    required this.type,
    required this.value,
    this.maxRedemptions,
    this.redeemedCount = 0,
    this.active = true,
    this.expiresAt,
    this.note,
  });

  final String code;
  final EventDiscountVoucherType type;
  final double value;
  final int? maxRedemptions;
  final int redeemedCount;
  final bool active;
  final DateTime? expiresAt;
  final String? note;

  String get normalizedCode => normalizeCode(code);

  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && expiry.isBefore(DateTime.now());
  }

  bool get isSoldThrough =>
      maxRedemptions != null && redeemedCount >= maxRedemptions!;

  bool get isAvailable => active && !isExpired && !isSoldThrough && value > 0;

  String get label {
    return switch (type) {
      EventDiscountVoucherType.percentage =>
        '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}% off',
      EventDiscountVoucherType.fixedAmount =>
        'GHS ${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)} off',
    };
  }

  double discountFor(double subtotal) {
    if (!isAvailable || subtotal <= 0) {
      return 0;
    }
    final rawDiscount = switch (type) {
      EventDiscountVoucherType.percentage => subtotal * (value / 100),
      EventDiscountVoucherType.fixedAmount => value,
    };
    if (rawDiscount <= 0) {
      return 0;
    }
    return rawDiscount > subtotal ? subtotal : rawDiscount;
  }

  EventDiscountVoucher copyWith({
    String? code,
    EventDiscountVoucherType? type,
    double? value,
    int? maxRedemptions,
    bool clearMaxRedemptions = false,
    int? redeemedCount,
    bool? active,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    String? note,
    bool clearNote = false,
  }) {
    return EventDiscountVoucher(
      code: code ?? this.code,
      type: type ?? this.type,
      value: value ?? this.value,
      maxRedemptions: clearMaxRedemptions
          ? null
          : maxRedemptions ?? this.maxRedemptions,
      redeemedCount: redeemedCount ?? this.redeemedCount,
      active: active ?? this.active,
      expiresAt: clearExpiresAt ? null : expiresAt ?? this.expiresAt,
      note: clearNote ? null : note ?? this.note,
    );
  }

  static String normalizeCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
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
    this.discountVouchers = const [],
  });

  final bool enabled;
  final bool requireTicket;
  final String currency;
  final List<TicketTier> tiers;
  final List<EventDiscountVoucher> discountVouchers;

  double? get minimumPrice {
    final priced = tiers.where((tier) => tier.price > 0).toList();
    if (priced.isEmpty) return null;
    return priced.map((tier) => tier.price).reduce((a, b) => a < b ? a : b);
  }

  int get totalSold => tiers.fold(0, (sum, tier) => sum + tier.sold);

  EventDiscountVoucher? voucherByCode(String? code) {
    final normalized = EventDiscountVoucher.normalizeCode(code ?? '');
    if (normalized.isEmpty) {
      return null;
    }
    for (final voucher in discountVouchers) {
      if (voucher.normalizedCode == normalized) {
        return voucher;
      }
    }
    return null;
  }

  double discountForCode(String? code, double subtotal) {
    final voucher = voucherByCode(code);
    return voucher == null ? 0 : voucher.discountFor(subtotal);
  }

  EventTicketing copyWith({
    bool? enabled,
    bool? requireTicket,
    String? currency,
    List<TicketTier>? tiers,
    List<EventDiscountVoucher>? discountVouchers,
  }) {
    return EventTicketing(
      enabled: enabled ?? this.enabled,
      requireTicket: requireTicket ?? this.requireTicket,
      currency: currency ?? this.currency,
      tiers: tiers ?? this.tiers,
      discountVouchers: discountVouchers ?? this.discountVouchers,
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
    this.categoryId = EventTaxonomy.defaultCategoryId,
    this.location,
    this.flyerAsset,
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
  final String categoryId;
  final EventLocation? location;
  final String? flyerAsset;

  bool get isPrivate => visibility == EventVisibility.privateEvent;
  bool get isTicketed => ticketing.enabled;
  bool get hasLocation => location != null;
  VennuzoEventCategory get category => EventTaxonomy.byId(categoryId);

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
    String? categoryId,
    EventLocation? location,
    bool clearLocation = false,
    String? flyerAsset,
    bool clearFlyerAsset = false,
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
      categoryId: categoryId ?? this.categoryId,
      location: clearLocation ? null : location ?? this.location,
      flyerAsset: clearFlyerAsset ? null : flyerAsset ?? this.flyerAsset,
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
    this.categoryId = EventTaxonomy.defaultCategoryId,
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
  final String categoryId;
  final EventLocation? location;
}

extension EventMoodPalette on EventMood {
  List<Color> get colors => switch (this) {
    EventMood.night => const [Color(0xFF112A46), Color(0xFFE86B43)],
    EventMood.sunrise => const [Color(0xFFFFC56E), Color(0xFFFF7F50)],
    EventMood.electric => const [Color(0xFF2B7A78), Color(0xFF10212A)],
    EventMood.garden => const [Color(0xFF7EBB74), Color(0xFFF4E7B6)],
  };

  MoodArtPalette get artPalette => MoodArtPalette.fromMood(this);
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
