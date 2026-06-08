import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/models/creative_service_models.dart';

class SubmitCreativeJobResult {
  const SubmitCreativeJobResult({
    required this.jobId,
    required this.priceChargedGhs,
    required this.quotaCovered,
  });

  final String jobId;
  final double priceChargedGhs;
  final bool quotaCovered;
}

class SubmitCreativeVideoJobResult {
  const SubmitCreativeVideoJobResult({
    required this.jobId,
    required this.priceChargedGhs,
  });

  final String jobId;
  final double priceChargedGhs;
}

class AudienceImportResult {
  const AudienceImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.pushMatchedCount,
    required this.smsEligibleCount,
  });

  final int importedCount;
  final int skippedCount;
  final int pushMatchedCount;
  final int smsEligibleCount;
}

class VennuzoCreativeServicesService {
  const VennuzoCreativeServicesService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static FirebaseStorage get _storage => FirebaseStorage.instance;

  static Future<CreativeServicesConfig> getConfig(String organizationId) async {
    final result = await _functions
        .httpsCallable('getCreativeServicesConfig')
        .call(<String, Object?>{'organizationId': organizationId});
    final data = Map<dynamic, dynamic>.from(result.data as Map);
    return CreativeServicesConfig(
      organizationId: '${data['organizationId'] ?? organizationId}',
      brand: CreativeBrandConfig.fromMap(data['brand'] as Map?),
      pricing: CreativeServicesPricing.fromMap(data['pricing'] as Map?),
    );
  }

  static Future<CreativeBrandConfig> saveBrand({
    required String organizationId,
    required CreativeBrandConfig brand,
  }) async {
    final result = await _functions
        .httpsCallable('saveCreativeBrandConfig')
        .call(brand.toPayload(organizationId: organizationId));
    final data = Map<dynamic, dynamic>.from(result.data as Map);
    return CreativeBrandConfig.fromMap(data['brand'] as Map?);
  }

  static Future<SubmitCreativeJobResult> submitJob({
    required String organizationId,
    required String serviceType,
    required String eventName,
    required String venue,
    required String date,
    required String time,
    required String performers,
    required String creativeDescription,
    String? uploadedFlyerUrl,
    List<CreativeTier> tiers = const <CreativeTier>[],
  }) async {
    final result = await _functions
        .httpsCallable('submitCreativeFlyerJob')
        .call(<String, Object?>{
          'organizationId': organizationId,
          'serviceType': serviceType,
          'eventName': eventName,
          'venue': venue,
          'date': date,
          'time': time,
          'djs': performers,
          'creativeDescription': creativeDescription,
          if (uploadedFlyerUrl != null && uploadedFlyerUrl.isNotEmpty)
            'uploadedFlyerUrl': uploadedFlyerUrl,
          'tiers': tiers.map((tier) => tier.toPayload()).toList(),
        });
    final data = Map<dynamic, dynamic>.from(result.data as Map);
    return SubmitCreativeJobResult(
      jobId: '${data['jobId'] ?? ''}',
      priceChargedGhs: (data['priceChargedGhs'] as num?)?.toDouble() ?? 0,
      quotaCovered: data['quotaCovered'] == true,
    );
  }

  static Future<SubmitCreativeJobResult> submitEdit({
    required String organizationId,
    required CreativeSession source,
    required String editMode,
    required String instruction,
  }) async {
    final result = await _functions
        .httpsCallable('submitCreativeFlyerJob')
        .call(<String, Object?>{
          'organizationId': organizationId,
          'serviceType': source.serviceType,
          'eventName': source.eventName,
          'editMode': editMode,
          'sourceSessionId': source.id,
          'sourceFlyerUrl': source.imageUrl,
          'editInstruction': instruction,
        });
    final data = Map<dynamic, dynamic>.from(result.data as Map);
    return SubmitCreativeJobResult(
      jobId: '${data['jobId'] ?? ''}',
      priceChargedGhs: (data['priceChargedGhs'] as num?)?.toDouble() ?? 0,
      quotaCovered: data['quotaCovered'] == true,
    );
  }

  static Stream<CreativeJobSnapshot> watchJob(String jobId) {
    return _firestore
        .collection('flyer_jobs')
        .doc(jobId)
        .snapshots()
        .map(CreativeJobSnapshot.fromDocument);
  }

  static Future<SubmitCreativeVideoJobResult> submitVideoJob({
    required String organizationId,
    required CreativeSession source,
  }) async {
    final result = await _functions
        .httpsCallable('submitCreativeFlyerVideoJob')
        .call(<String, Object?>{
          'organizationId': organizationId,
          'sourceSessionId': source.id,
          'eventName': source.eventName,
        });
    final data = Map<dynamic, dynamic>.from(result.data as Map);
    return SubmitCreativeVideoJobResult(
      jobId: '${data['jobId'] ?? ''}',
      priceChargedGhs: (data['priceChargedGhs'] as num?)?.toDouble() ?? 0,
    );
  }

  static Stream<CreativeVideoJobSnapshot> watchVideoJob(String jobId) {
    return _firestore
        .collection('flyer_video_jobs')
        .doc(jobId)
        .snapshots()
        .map(CreativeVideoJobSnapshot.fromDocument);
  }

  static Stream<List<CreativeSession>> watchSessions(String organizationId) {
    return _firestore
        .collection('flyer_sessions')
        .where('organizationId', isEqualTo: organizationId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(CreativeSession.fromDocument)
              .where((session) => session.imageUrl.isNotEmpty)
              .toList();
        });
  }

  static Future<String> uploadAsset({
    required String organizationId,
    required XFile file,
    required String folder,
  }) async {
    final bytes = await file.readAsBytes();
    return uploadAssetBytes(
      organizationId: organizationId,
      bytes: bytes,
      folder: folder,
      name: file.name,
      mimeType: file.mimeType,
    );
  }

  static Future<String> uploadAssetBytes({
    required String organizationId,
    required Uint8List bytes,
    required String folder,
    required String name,
    String? mimeType,
  }) async {
    final nameParts = name.split('.');
    final extension = nameParts.length > 1 ? nameParts.last : 'png';
    final path =
        'creative-brands/$organizationId/$folder-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: mimeType ?? 'image/$extension'),
    );
    return ref.getDownloadURL();
  }

  static Future<AudienceImportResult> importAudienceContacts({
    required String organizationId,
    required List<Map<String, Object?>> contacts,
    String sourceName = 'App import',
    String duplicateMode = 'merge',
  }) async {
    final result = await _functions
        .httpsCallable('importAudienceContacts')
        .call(<String, Object?>{
          'organizationId': organizationId,
          'sourceName': sourceName,
          'duplicateMode': duplicateMode,
          'contacts': contacts,
        });
    final data = Map<dynamic, dynamic>.from(result.data as Map);
    return AudienceImportResult(
      importedCount: (data['importedCount'] as num?)?.toInt() ?? 0,
      skippedCount: (data['skippedCount'] as num?)?.toInt() ?? 0,
      pushMatchedCount: (data['pushMatchedCount'] as num?)?.toInt() ?? 0,
      smsEligibleCount: (data['smsEligibleCount'] as num?)?.toInt() ?? 0,
    );
  }
}
