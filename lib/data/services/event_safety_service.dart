import 'package:cloud_functions/cloud_functions.dart';

class EventSafetyService {
  const EventSafetyService();

  Future<void> reportEvent({
    required String eventId,
    required String eventTitle,
    required String reason,
    required String details,
    String? reporterUid,
    String? reporterEmail,
  }) {
    return FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('submitEventReport').call({
      'eventId': eventId,
      'eventTitle': eventTitle,
      'reason': reason,
      'details': details.trim(),
      if (reporterUid?.trim().isNotEmpty == true)
        'reporterUid': reporterUid!.trim(),
      if (reporterEmail?.trim().isNotEmpty == true)
        'reporterEmail': reporterEmail!.trim(),
    });
  }
}
