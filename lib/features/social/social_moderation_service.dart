import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Content surfaces that can be reported. Kept in sync with the allow-list in
/// the `reportContent` Cloud Function (functions/content_moderation.js).
enum ReportContentType { post, comment, review, profile }

extension ReportContentTypeWire on ReportContentType {
  String get wireValue {
    switch (this) {
      case ReportContentType.post:
        return 'post';
      case ReportContentType.comment:
        return 'comment';
      case ReportContentType.review:
        return 'review';
      case ReportContentType.profile:
        return 'profile';
    }
  }
}

/// A single selectable report reason. [value] is sent to the backend (and must
/// be in the server allow-list); [label] is shown to the user.
class ReportReason {
  const ReportReason(this.value, this.label);

  final String value;
  final String label;

  /// Reasons offered in the report picker. Values mirror ALLOWED_REASONS in
  /// functions/content_moderation.js exactly.
  static const List<ReportReason> all = [
    ReportReason('spam', 'Spam or scam'),
    ReportReason('harassment', 'Harassment or bullying'),
    ReportReason('hate', 'Hate speech'),
    ReportReason('nudity_sexual', 'Nudity or sexual content'),
    ReportReason('violence', 'Violence or dangerous content'),
    ReportReason('false_info', 'False information'),
    ReportReason('other', 'Something else'),
  ];
}

/// App Store Guideline 1.2 — UGC moderation service.
///
/// Wraps the `reportContent` / `blockUser` / `unblockUser` callables and exposes
/// the signed-in user's block list (from `user_blocks/{uid}`) so the social
/// layer can filter out content authored by blocked users.
class SocialModerationService {
  SocialModerationService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestoreOverride = firestore,
       _functionsOverride = functions;

  // Resolved lazily (not in the constructor) so that constructing the service —
  // which several social widgets do as a field initializer — never touches
  // FirebaseFirestore.instance / FirebaseFunctions before a Firebase app exists
  // (e.g. in widget tests booted with firebaseEnabled: false).
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseFunctions? _functionsOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'us-central1');

  // ─── Reporting ─────────────────────────────────────────────────────────────

  /// Files a moderation report for a piece of content. Throws on failure so the
  /// caller can surface an error toast.
  Future<void> reportContent({
    required ReportContentType contentType,
    required String contentId,
    String? authorId,
    required String reason,
    String? details,
  }) async {
    await _functions.httpsCallable('reportContent').call(<String, Object?>{
      'contentType': contentType.wireValue,
      'contentId': contentId,
      'reason': reason,
      if (authorId != null && authorId.trim().isNotEmpty)
        'authorId': authorId.trim(),
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    });
  }

  // ─── Blocking ──────────────────────────────────────────────────────────────

  Future<void> blockUser(String blockedUserId) async {
    await _functions.httpsCallable('blockUser').call(<String, Object?>{
      'blockedUserId': blockedUserId,
    });
  }

  Future<void> unblockUser(String blockedUserId) async {
    await _functions.httpsCallable('unblockUser').call(<String, Object?>{
      'blockedUserId': blockedUserId,
    });
  }

  // ─── Block list ────────────────────────────────────────────────────────────

  /// Live set of uids the [userId] has blocked. Emits an empty set when the
  /// user has no block list yet (or is signed out / [userId] is empty).
  Stream<Set<String>> blockedUserIds(String userId) {
    if (userId.isEmpty) {
      return Stream<Set<String>>.value(const <String>{});
    }
    return _firestore
        .collection('user_blocks')
        .doc(userId)
        .snapshots()
        .map(_blockedSetFromSnapshot);
  }

  /// One-shot read of the current block list — handy for non-stream call sites.
  Future<Set<String>> fetchBlockedUserIds(String userId) async {
    if (userId.isEmpty) return const <String>{};
    final snap = await _firestore.collection('user_blocks').doc(userId).get();
    return _blockedSetFromSnapshot(snap);
  }

  Set<String> _blockedSetFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final raw = snap.data()?['blockedUserIds'];
    if (raw is List) {
      return raw
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return const <String>{};
  }
}
