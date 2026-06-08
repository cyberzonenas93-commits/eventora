import 'package:flutter/material.dart';

enum PlaceReservationStatus {
  pending,
  confirmed,
  changeRequested,
  seated,
  cancelled,
  noShow,
}

enum PlaceReservationType {
  table,
  vipTable,
  guestlist,
  bottleService,
  privateBooking,
}

enum PlaceMenuItemStatus { available, soldOut, hidden }

class PlaceProfile {
  const PlaceProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.city,
    required this.address,
    this.googlePlaceId,
    this.mapsUrl,
    this.latitude,
    this.longitude,
    this.phone,
    this.website,
    this.logoUrl,
    this.coverUrl,
    this.galleryUrls = const <String>[],
    this.categories = const <String>[],
    this.amenities = const <String>[],
    this.openingHours = const <String>[],
    this.rating = 0,
    this.reviewCount = 0,
    this.subscriberCount = 0,
    this.featured = false,
    this.status = 'active',
    this.verificationStatus = 'unverified',
    this.verified = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String city;
  final String address;
  final String? googlePlaceId;
  final String? mapsUrl;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? website;
  final String? logoUrl;
  final String? coverUrl;
  final List<String> galleryUrls;
  final List<String> categories;
  final List<String> amenities;
  final List<String> openingHours;
  final double rating;
  final int reviewCount;
  final int subscriberCount;
  final bool featured;
  final String status;

  /// Server-authoritative verification lifecycle:
  /// 'unverified' | 'pending_review' | 'verified' | 'rejected' | 'suspended'.
  final String verificationStatus;
  final bool verified;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status != 'hidden' && status != 'disabled';

  bool get isVerified => verified || verificationStatus == 'verified';
  bool get isVerificationPending => verificationStatus == 'pending_review';

  IconData get icon {
    final text = [...categories, name, description].join(' ').toLowerCase();
    if (text.contains('club') || text.contains('nightlife')) {
      return Icons.nightlife_rounded;
    }
    if (text.contains('restaurant') || text.contains('food')) {
      return Icons.restaurant_rounded;
    }
    if (text.contains('bar') || text.contains('drink')) {
      return Icons.local_bar_rounded;
    }
    return Icons.storefront_rounded;
  }
}

class PlaceMenuSection {
  const PlaceMenuSection({
    required this.id,
    required this.placeId,
    required this.name,
    this.description = '',
    this.sortOrder = 0,
    this.visible = true,
  });

  final String id;
  final String placeId;
  final String name;
  final String description;
  final int sortOrder;
  final bool visible;
}

class PlaceMenuItem {
  const PlaceMenuItem({
    required this.id,
    required this.placeId,
    required this.sectionId,
    required this.name,
    required this.description,
    required this.price,
    this.currency = 'GHS',
    this.imageUrl,
    this.featured = false,
    this.status = PlaceMenuItemStatus.available,
    this.options = const <String>[],
    this.tags = const <String>[],
    this.sortOrder = 0,
  });

  final String id;
  final String placeId;
  final String sectionId;
  final String name;
  final String description;
  final double price;
  final String currency;
  final String? imageUrl;
  final bool featured;
  final PlaceMenuItemStatus status;
  final List<String> options;
  final List<String> tags;
  final int sortOrder;

  bool get isVisible => status != PlaceMenuItemStatus.hidden;
  bool get isAvailable => status == PlaceMenuItemStatus.available;
}

class PlaceReservationRequest {
  const PlaceReservationRequest({
    required this.placeId,
    required this.placeName,
    required this.reservationType,
    required this.guestName,
    required this.phone,
    required this.partySize,
    required this.requestedAt,
    this.note = '',
    this.selectedMenuItemIds = const <String>[],
  });

  final String placeId;
  final String placeName;
  final PlaceReservationType reservationType;
  final String guestName;
  final String phone;
  final int partySize;
  final DateTime requestedAt;
  final String note;
  final List<String> selectedMenuItemIds;
}

class PlaceReservation {
  const PlaceReservation({
    required this.id,
    required this.placeId,
    required this.placeName,
    required this.userId,
    required this.guestName,
    required this.phone,
    required this.partySize,
    required this.requestedAt,
    required this.reservationType,
    required this.status,
    this.note = '',
    this.internalNote = '',
    this.selectedMenuItemIds = const <String>[],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String placeId;
  final String placeName;
  final String userId;
  final String guestName;
  final String phone;
  final int partySize;
  final DateTime requestedAt;
  final PlaceReservationType reservationType;
  final PlaceReservationStatus status;
  final String note;
  final String internalNote;
  final List<String> selectedMenuItemIds;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PlaceSubscriptionPrefs {
  const PlaceSubscriptionPrefs({
    this.events = true,
    this.menuSpecials = true,
    this.reservationAlerts = true,
    this.announcements = true,
  });

  final bool events;
  final bool menuSpecials;
  final bool reservationAlerts;
  final bool announcements;

  List<String> get channels => <String>[
    if (events) 'events',
    if (menuSpecials) 'menu_specials',
    if (reservationAlerts) 'reservation_alerts',
    if (announcements) 'announcements',
  ];
}
