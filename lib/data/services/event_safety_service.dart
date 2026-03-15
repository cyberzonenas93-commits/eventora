import 'package:cloud_firestore/cloud_firestore.dart';

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
    return FirebaseFirestore.instance.collection('event_reports').add({
      'eventId': eventId,
      'eventTitle': eventTitle,
      'reason': reason,
      'details': details.trim(),
      'reporterUid': reporterUid,
      'reporterEmail': reporterEmail?.trim().isEmpty == true ? null : reporterEmail?.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
