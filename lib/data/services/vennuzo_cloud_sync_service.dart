import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/account_models.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import '../../domain/models/ticket_models.dart';

class VennuzoCloudSyncService {
  VennuzoCloudSyncService({required this.firebaseEnabled});

  final bool firebaseEnabled;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  bool get isEnabled => firebaseEnabled;

  String organizationIdFor(VennuzoViewer viewer) {
    final existing = viewer.defaultOrganizationId?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    return 'org_${viewer.uid}';
  }

  Future<void> ensureOrganizerWorkspace(VennuzoViewer viewer) async {
    if (!isEnabled || viewer.uid == null || !viewer.hasOrganizerAccess) {
      return;
    }

    final uid = viewer.uid!;
    final organizationId = organizationIdFor(viewer);
    final batch = _firestore.batch();

    batch.set(
      _firestore.collection('organizations').doc(organizationId),
      <String, Object?>{
        'name': '${viewer.displayName} Events',
        'slug': organizationId,
        'ownerId': uid,
        'city': 'Accra',
        'country': 'Ghana',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      _firestore
          .collection('organization_members')
          .doc('${organizationId}_$uid'),
      <String, Object?>{
        'organizationId': organizationId,
        'userId': uid,
        'role': 'owner',
        'permissions': const <String, Object?>{
          'manageEvents': true,
          'manageTickets': true,
          'managePromotions': true,
          'validateTickets': true,
        },
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (viewer.hasCustomerProfile || viewer.hasOrganizerAccess) {
      batch.set(_firestore.collection('users').doc(uid), <String, Object?>{
        'defaultOrganizationId': organizationId,
        'notificationPrefs': <String, Object?>{
          'pushEnabled': viewer.notificationPrefs.pushEnabled,
          'smsEnabled': viewer.notificationPrefs.smsEnabled,
          'marketingOptIn': viewer.notificationPrefs.marketingOptIn,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await _runSafely(batch.commit);
  }

  Future<void> upsertEvent({
    required EventModel event,
    required VennuzoViewer viewer,
    double grossRevenue = 0,
  }) async {
    if (!isEnabled || viewer.uid == null) {
      return;
    }

    await ensureOrganizerWorkspace(viewer);
    final organizationId = organizationIdFor(viewer);
    final eventRef = _firestore.collection('events').doc(event.id);
    final occurrenceRef = _firestore
        .collection('event_occurrences')
        .doc('${event.id}_primary');
    final batch = _firestore.batch();

    batch.set(
      eventRef,
      _eventData(
        event: event,
        organizationId: organizationId,
        createdBy: viewer.uid!,
        grossRevenue: grossRevenue,
      ),
      SetOptions(merge: true),
    );

    batch.set(
      occurrenceRef,
      _occurrenceData(event: event, organizationId: organizationId),
      SetOptions(merge: true),
    );

    batch.set(
      _firestore.collection('share_links').doc(event.id),
      <String, Object?>{
        'type': 'event',
        'targetId': event.id,
        'eventId': event.id,
        'organizationId': organizationId,
        'title': event.title,
        'description': event.description,
        'imageUrl': '',
        'slug': _slugify(event.title),
        'requireTicket': event.ticketing.requireTicket,
        'status': event.allowSharing ? 'active' : 'disabled',
        'createdBy': viewer.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await _runSafely(batch.commit);
  }

  Future<void> upsertRsvp({
    required EventModel event,
    required RsvpRecord record,
    required VennuzoViewer viewer,
  }) async {
    if (!isEnabled || viewer.uid == null) {
      return;
    }

    await ensureOrganizerWorkspace(viewer);
    final organizationId = _eventOrganizationId(event: event, viewer: viewer);
    final rsvpRef = _firestore
        .collection('event_rsvps')
        .doc('${event.id}_${viewer.uid}');
    final eventRsvpRef = _firestore
        .collection('events')
        .doc(event.id)
        .collection('rsvps')
        .doc(viewer.uid);

    await _runSafely(() async {
      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(rsvpRef);
        final existingData = existing.data();
        final createdAt = existing.exists
            ? existingData == null
                  ? null
                  : existingData['createdAt']
            : FieldValue.serverTimestamp();
        transaction.set(rsvpRef, <String, Object?>{
          'eventId': event.id,
          'occurrenceId': '${event.id}_primary',
          'userId': record.attendeeUserId ?? viewer.uid,
          'organizationId': organizationId,
          'eventTitle': event.title,
          'name': record.name,
          'phone': record.phone,
          'guestCount': record.guestCount,
          'bookTable': record.bookTable,
          'status': 'confirmed',
          'createdAt': createdAt,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        transaction.set(eventRsvpRef, <String, Object?>{
          'userId': record.attendeeUserId ?? viewer.uid,
          'name': record.name,
          'phone': record.phone,
          'guestCount': record.guestCount,
          'bookTable': record.bookTable,
          'createdAt': createdAt,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (!existing.exists) {
          transaction.set(
            _firestore.collection('events').doc(event.id),
            <String, Object?>{
              'metrics': <String, Object?>{
                'rsvpCount': FieldValue.increment(1),
              },
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      });
    });
  }

  Future<void> upsertOrder({
    required EventModel event,
    required TicketOrder order,
    required VennuzoViewer viewer,
  }) async {
    if (!isEnabled || viewer.uid == null) {
      return;
    }

    await ensureOrganizerWorkspace(viewer);
    final organizationId = _eventOrganizationId(event: event, viewer: viewer);
    final orderRef = _firestore.collection('event_ticket_orders').doc(order.id);

    await _runSafely(() async {
      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(orderRef);
        transaction.set(orderRef, <String, Object?>{
          'eventId': event.id,
          'occurrenceId': '${event.id}_primary',
          'organizationId': organizationId,
          'eventTitle': order.eventTitle,
          'buyerId': order.buyerUserId ?? viewer.uid,
          'buyerName': order.buyerName,
          'buyerPhone': order.buyerPhone,
          'buyerEmail': order.buyerEmail,
          'selectedTiers': order.selectedTiers
              .map(
                (selection) => <String, Object?>{
                  'tierId': selection.tierId,
                  'name': selection.name,
                  'price': selection.price,
                  'quantity': selection.quantity,
                },
              )
              .toList(),
          'totalAmount': order.totalAmount,
          'currency': event.ticketing.currency,
          'status': order.status.name,
          'paymentStatus': _paymentStatusValue(order.paymentStatus),
          'source': order.source,
          'tickets': {
            for (final ticket in order.tickets)
              ticket.ticketId: <String, Object?>{
                'ticketId': ticket.ticketId,
                'orderId': ticket.orderId,
                'eventId': ticket.eventId,
                'occurrenceId': '${event.id}_primary',
                'tierId': ticket.tierId,
                'tierName': ticket.tierName,
                'qrToken': ticket.qrToken,
                'status': _ticketStatusValue(ticket.status),
                'attendeeName': ticket.attendeeName,
                'price': ticket.price,
                'issuedAt': Timestamp.fromDate(ticket.issuedAt),
                'admittedAt': ticket.admittedAt == null
                    ? null
                    : Timestamp.fromDate(ticket.admittedAt!),
              },
          },
          'createdAt': existing.exists
              ? (existing.data()?['createdAt'] ??
                    Timestamp.fromDate(order.createdAt))
              : Timestamp.fromDate(order.createdAt),
          'updatedAt': FieldValue.serverTimestamp(),
          'paidAt': order.isPaid ? Timestamp.fromDate(order.updatedAt) : null,
        }, SetOptions(merge: true));

        for (final ticket in order.tickets) {
          transaction.set(
            _firestore.collection('event_ticket_lookups').doc(ticket.qrToken),
            <String, Object?>{
              'qrToken': ticket.qrToken,
              'orderId': order.id,
              'ticketId': ticket.ticketId,
              'eventId': event.id,
              'occurrenceId': '${event.id}_primary',
              'organizationId': organizationId,
              'buyerId': order.buyerUserId ?? viewer.uid,
              'attendeeName': ticket.attendeeName,
              'tierId': ticket.tierId,
              'tierName': ticket.tierName,
              'ticketStatus': _ticketStatusValue(ticket.status),
              'paymentStatus': _paymentStatusValue(order.paymentStatus),
              'admittedAt': ticket.admittedAt == null
                  ? null
                  : Timestamp.fromDate(ticket.admittedAt!),
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        if (!existing.exists) {
          transaction.set(
            _firestore.collection('events').doc(event.id),
            <String, Object?>{
              'metrics': <String, Object?>{
                'ticketCount': FieldValue.increment(order.ticketCount),
                'grossRevenue': FieldValue.increment(order.totalAmount),
              },
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      });
    });
  }

  Future<void> saveReminder({
    required EventModel event,
    required VennuzoViewer viewer,
    required ReminderTiming timing,
  }) async {
    if (!isEnabled || viewer.uid == null) {
      return;
    }

    final scheduledAt = _scheduledReminderTime(event.startDate, timing);
    await _runSafely(() {
      return _firestore
          .collection('event_reminders')
          .doc('${event.id}_${viewer.uid}')
          .set(<String, Object?>{
            'eventId': event.id,
            'occurrenceId': '${event.id}_primary',
            'eventTitle': event.title,
            'userId': viewer.uid,
            'phone': viewer.phone,
            'timing': timing.name,
            'scheduledAt': Timestamp.fromDate(scheduledAt),
            'status': 'scheduled',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    });
  }

  Future<void> clearReminder({
    required String eventId,
    required VennuzoViewer viewer,
  }) async {
    if (!isEnabled || viewer.uid == null) {
      return;
    }

    await _runSafely(
      () => _firestore
          .collection('event_reminders')
          .doc('${eventId}_${viewer.uid}')
          .delete(),
    );
  }

  Future<void> launchCampaign({
    required PromotionCampaign campaign,
    required EventModel event,
    required VennuzoViewer viewer,
  }) async {
    if (!isEnabled || viewer.uid == null) {
      return;
    }

    await ensureOrganizerWorkspace(viewer);
    final organizationId = _eventOrganizationId(event: event, viewer: viewer);
    final campaignRef = _firestore
        .collection('promotion_campaigns')
        .doc(campaign.id);

    await _runSafely(() async {
      await campaignRef.set(<String, Object?>{
        'eventId': event.id,
        'occurrenceId': '${event.id}_primary',
        'organizationId': organizationId,
        'eventTitle': event.title,
        'name': campaign.name,
        'status': campaign.status.name,
        'channels': campaign.channels.map((channel) => channel.name).toList(),
        'scheduledAt': campaign.scheduledAt == null
            ? null
            : Timestamp.fromDate(campaign.scheduledAt!),
        'pushAudience': campaign.pushAudience,
        'smsAudience': campaign.smsAudience,
        'shareLinkEnabled': campaign.shareLinkEnabled,
        'budget': campaign.budget,
        'message': campaign.message,
        'createdBy': campaign.createdByUserId ?? viewer.uid,
        'createdAt': Timestamp.fromDate(campaign.createdAt),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _functions.httpsCallable('launchEventNotificationCampaign').call(
        <String, Object?>{
          'campaignId': campaign.id,
          'eventId': event.id,
          'eventTitle': event.title,
          'name': campaign.name,
          'message': campaign.message,
          'channels': campaign.channels.map((channel) => channel.name).toList(),
          'scheduledAt': campaign.scheduledAt?.toIso8601String(),
          'shareLinkEnabled': campaign.shareLinkEnabled,
        },
      );
    });
  }

  Future<void> admitTicket({
    required TicketOrder order,
    required EventTicket ticket,
  }) async {
    if (!isEnabled) {
      return;
    }

    await _runSafely(() async {
      final batch = _firestore.batch();
      batch.set(
        _firestore.collection('event_ticket_orders').doc(order.id),
        <String, Object?>{
          'status': 'paid',
          'paymentStatus': order.paymentStatus == TicketPaymentStatus.cashAtGate
              ? 'cashAtGatePaid'
              : _paymentStatusValue(order.paymentStatus),
          'tickets': <String, Object?>{
            ticket.ticketId: <String, Object?>{
              'status': 'admitted',
              'admittedAt': FieldValue.serverTimestamp(),
            },
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      batch.set(
        _firestore.collection('event_ticket_lookups').doc(ticket.qrToken),
        <String, Object?>{
          'ticketStatus': 'admitted',
          'paymentStatus': order.paymentStatus == TicketPaymentStatus.cashAtGate
              ? 'cashAtGatePaid'
              : _paymentStatusValue(order.paymentStatus),
          'admittedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    });
  }

  Map<String, Object?> _eventData({
    required EventModel event,
    required String organizationId,
    required String createdBy,
    required double grossRevenue,
  }) {
    return <String, Object?>{
      'organizationId': organizationId,
      'createdBy': createdBy,
      'title': event.title,
      'description': event.description,
      'venue': event.venue,
      'city': event.city,
      'country': 'Ghana',
      'addressText': event.location?.address ?? '${event.venue}, ${event.city}',
      'placeId': event.location?.placeId,
      'location': event.location == null
          ? null
          : GeoPoint(event.location!.latitude, event.location!.longitude),
      'latitude': event.location?.latitude,
      'longitude': event.location?.longitude,
      'visibility': switch (event.visibility) {
        EventVisibility.publicEvent => 'public',
        EventVisibility.privateEvent => 'private',
      },
      'status': 'published',
      'startAt': Timestamp.fromDate(event.startDate),
      'endAt': event.endDate == null
          ? null
          : Timestamp.fromDate(event.endDate!),
      'timezone': 'Africa/Accra',
      'recurrence': <String, Object?>{
        'frequency': event.recurrence.frequency.name,
        'interval': event.recurrence.interval,
        'endType': event.recurrence.endType.name,
        'endDate': event.recurrence.endDate == null
            ? null
            : Timestamp.fromDate(event.recurrence.endDate!),
        'endAfterOccurrences': event.recurrence.endAfterOccurrences,
      },
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
      'lineup': <String, Object?>{
        'performers': event.performers,
        'djs': event.djs,
        'mcs': event.mcs,
      },
      'distribution': <String, Object?>{
        'allowSharing': event.allowSharing,
        'sendPushNotification': event.sendPushNotification,
        'sendSmsNotification': event.sendSmsNotification,
      },
      'metrics': <String, Object?>{
        'likesCount': event.likesCount,
        'rsvpCount': event.rsvpCount,
        'ticketCount': event.ticketing.totalSold,
        'grossRevenue': grossRevenue,
      },
      'mood': event.mood.name,
      'tags': event.tags,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, Object?> _occurrenceData({
    required EventModel event,
    required String organizationId,
  }) {
    return <String, Object?>{
      'eventId': event.id,
      'organizationId': organizationId,
      'seriesEventId': event.id,
      'title': event.title,
      'visibility': switch (event.visibility) {
        EventVisibility.publicEvent => 'public',
        EventVisibility.privateEvent => 'private',
      },
      'status': 'published',
      'occurrenceStartAt': Timestamp.fromDate(event.startDate),
      'occurrenceEndAt': event.endDate == null
          ? null
          : Timestamp.fromDate(event.endDate!),
      'timezone': 'Africa/Accra',
      'city': event.city,
      'venue': event.venue,
      'addressText': event.location?.address ?? '${event.venue}, ${event.city}',
      'location': event.location == null
          ? null
          : GeoPoint(event.location!.latitude, event.location!.longitude),
      'ticketingEnabled': event.ticketing.enabled,
      'requireTicket': event.ticketing.requireTicket,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  DateTime _scheduledReminderTime(DateTime startDate, ReminderTiming timing) {
    final now = DateTime.now();
    final scheduledAt = switch (timing) {
      ReminderTiming.onDay => startDate.subtract(const Duration(hours: 6)),
      ReminderTiming.oneDayBefore => startDate.subtract(
        const Duration(days: 1),
      ),
      ReminderTiming.twoDaysBefore => startDate.subtract(
        const Duration(days: 2),
      ),
      ReminderTiming.oneWeekBefore => startDate.subtract(
        const Duration(days: 7),
      ),
      ReminderTiming.custom => startDate.subtract(const Duration(hours: 2)),
    };
    if (scheduledAt.isBefore(now)) {
      return now.add(const Duration(minutes: 1));
    }
    return scheduledAt;
  }

  String _paymentStatusValue(TicketPaymentStatus status) {
    return switch (status) {
      TicketPaymentStatus.cashAtGate => 'cashAtGate',
      TicketPaymentStatus.cashAtGatePaid => 'cashAtGatePaid',
      _ => status.name,
    };
  }

  String _ticketStatusValue(TicketStatus status) => status.name;

  String _eventOrganizationId({
    required EventModel event,
    required VennuzoViewer viewer,
  }) {
    final viewerOrg = viewer.defaultOrganizationId?.trim();
    if (viewerOrg != null && viewerOrg.isNotEmpty) {
      return viewerOrg;
    }
    return 'org_${event.createdBy}';
  }

  String _slugify(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<void> _runSafely(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('VennuzoCloudSyncService error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
