import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/event_models.dart';

class VennuzoShareLinkService {
  VennuzoShareLinkService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static String fallbackEventLink(String eventId) =>
      'https://vennuzo.app/e/${Uri.encodeComponent(eventId)}';

  static Future<String> createEventLink({required EventModel event}) async {
    try {
      final result = await _functions.httpsCallable('createShareLink').call({
        'type': 'event',
        'targetId': event.id,
        'metadata': {
          'title': event.title,
          'description': event.description,
          'visibility': event.isPrivate ? 'private' : 'public',
          'ticketing': {
            'requireTicket': event.ticketing.requireTicket,
            'currency': event.ticketing.currency,
            'tiers': event.ticketing.tiers
                .map(
                  (tier) => {
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
          'distribution': {'allowSharing': event.allowSharing},
          'venue': event.venue,
          'city': event.city,
          'startAt': event.startDate.toIso8601String(),
          'endAt': event.endDate?.toIso8601String(),
          'timezone': 'Africa/Accra',
        },
      });

      final data = result.data;
      if (data is Map) {
        final url = '${data['url'] ?? ''}'.trim();
        if (url.isNotEmpty) {
          return url;
        }
      }
    } on FirebaseFunctionsException catch (error) {
      debugPrint('Event share link callable failed: ${error.message}');
    } catch (error) {
      debugPrint('Event share link generation failed: $error');
    }

    return fallbackEventLink(event.id);
  }
}
