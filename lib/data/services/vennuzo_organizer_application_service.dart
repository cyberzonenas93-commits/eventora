import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/models/account_models.dart';

class VennuzoOrganizerApplicationDraft {
  const VennuzoOrganizerApplicationDraft({
    required this.organizerName,
    required this.contactPerson,
    required this.email,
    required this.phone,
    required this.businessType,
    required this.businessAddress,
    required this.city,
    required this.instagram,
    required this.logoFileName,
    required this.logoImageUrl,
    required this.governmentIdFileName,
    required this.governmentIdUrl,
    required this.selfieFileName,
    required this.selfieUrl,
    required this.isRegisteredBusiness,
    required this.businessRegistrationNumber,
    required this.tinNumber,
    required this.payoutMethod,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    required this.network,
    required this.payoutPhone,
    required this.settlementPreference,
    required this.agreedToPayoutTerms,
    required this.agreesToCompliance,
    required this.reviewNotes,
    required this.organizationId,
  });

  factory VennuzoOrganizerApplicationDraft.bootstrap(VennuzoViewer viewer) {
    return VennuzoOrganizerApplicationDraft(
      organizerName: '',
      contactPerson: viewer.displayName == 'Guest' ? '' : viewer.displayName,
      email: viewer.email ?? '',
      phone: viewer.phone ?? '',
      businessType: '',
      businessAddress: '',
      city: 'Accra',
      instagram: '',
      logoFileName: '',
      logoImageUrl: '',
      governmentIdFileName: '',
      governmentIdUrl: '',
      selfieFileName: '',
      selfieUrl: '',
      isRegisteredBusiness: false,
      businessRegistrationNumber: '',
      tinNumber: '',
      payoutMethod: 'mobile-money',
      bankName: '',
      accountName: '',
      accountNumber: '',
      network: 'MTN Mobile Money',
      payoutPhone: viewer.phone ?? '',
      settlementPreference: 'After event ends',
      agreedToPayoutTerms: false,
      agreesToCompliance: false,
      reviewNotes: viewer.organizerReviewNotes ?? '',
      organizationId: viewer.defaultOrganizationId ?? '',
    );
  }

  factory VennuzoOrganizerApplicationDraft.fromFirestore(
    Map<String, dynamic> data, {
    required VennuzoViewer viewer,
  }) {
    final seeded = VennuzoOrganizerApplicationDraft.bootstrap(viewer);
    return seeded.copyWith(
      organizerName: '${data['organizerName'] ?? ''}'.trim(),
      contactPerson: '${data['contactPerson'] ?? seeded.contactPerson}'.trim(),
      email: '${data['email'] ?? seeded.email}'.trim(),
      phone: '${data['phone'] ?? seeded.phone}'.trim(),
      businessType: '${data['businessType'] ?? ''}'.trim(),
      businessAddress: '${data['businessAddress'] ?? ''}'.trim(),
      city: '${data['city'] ?? seeded.city}'.trim(),
      instagram: '${data['instagram'] ?? ''}'.trim(),
      logoFileName: '${data['logoFileName'] ?? ''}'.trim(),
      logoImageUrl: '${data['logoImageUrl'] ?? ''}'.trim(),
      governmentIdFileName: '${data['governmentIdFileName'] ?? ''}'.trim(),
      governmentIdUrl: '${data['governmentIdUrl'] ?? ''}'.trim(),
      selfieFileName: '${data['selfieFileName'] ?? ''}'.trim(),
      selfieUrl: '${data['selfieUrl'] ?? ''}'.trim(),
      isRegisteredBusiness:
          '${data['isRegisteredBusiness'] ?? 'no'}'.trim().toLowerCase() ==
          'yes',
      businessRegistrationNumber: '${data['businessRegistrationNumber'] ?? ''}'
          .trim(),
      tinNumber: '${data['tinNumber'] ?? ''}'.trim(),
      payoutMethod: '${data['payoutMethod'] ?? seeded.payoutMethod}'.trim(),
      bankName: '${data['bankName'] ?? ''}'.trim(),
      accountName: '${data['accountName'] ?? ''}'.trim(),
      accountNumber: '${data['accountNumber'] ?? ''}'.trim(),
      network: '${data['network'] ?? seeded.network}'.trim(),
      payoutPhone: '${data['payoutPhone'] ?? seeded.payoutPhone}'.trim(),
      settlementPreference:
          '${data['settlementPreference'] ?? seeded.settlementPreference}'
              .trim(),
      agreedToPayoutTerms: data['agreedToPayoutTerms'] == true,
      agreesToCompliance: data['agreesToCompliance'] == true,
      reviewNotes: '${data['reviewNotes'] ?? viewer.organizerReviewNotes ?? ''}'
          .trim(),
      organizationId:
          '${data['organizationId'] ?? viewer.defaultOrganizationId ?? ''}'
              .trim(),
    );
  }

  final String organizerName;
  final String contactPerson;
  final String email;
  final String phone;
  final String businessType;
  final String businessAddress;
  final String city;
  final String instagram;
  final String logoFileName;
  final String logoImageUrl;
  final String governmentIdFileName;
  final String governmentIdUrl;
  final String selfieFileName;
  final String selfieUrl;
  final bool isRegisteredBusiness;
  final String businessRegistrationNumber;
  final String tinNumber;
  final String payoutMethod;
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String network;
  final String payoutPhone;
  final String settlementPreference;
  final bool agreedToPayoutTerms;
  final bool agreesToCompliance;
  final String reviewNotes;
  final String organizationId;

  VennuzoOrganizerApplicationDraft copyWith({
    String? organizerName,
    String? contactPerson,
    String? email,
    String? phone,
    String? businessType,
    String? businessAddress,
    String? city,
    String? instagram,
    String? logoFileName,
    String? logoImageUrl,
    String? governmentIdFileName,
    String? governmentIdUrl,
    String? selfieFileName,
    String? selfieUrl,
    bool? isRegisteredBusiness,
    String? businessRegistrationNumber,
    String? tinNumber,
    String? payoutMethod,
    String? bankName,
    String? accountName,
    String? accountNumber,
    String? network,
    String? payoutPhone,
    String? settlementPreference,
    bool? agreedToPayoutTerms,
    bool? agreesToCompliance,
    String? reviewNotes,
    String? organizationId,
  }) {
    return VennuzoOrganizerApplicationDraft(
      organizerName: organizerName ?? this.organizerName,
      contactPerson: contactPerson ?? this.contactPerson,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      businessType: businessType ?? this.businessType,
      businessAddress: businessAddress ?? this.businessAddress,
      city: city ?? this.city,
      instagram: instagram ?? this.instagram,
      logoFileName: logoFileName ?? this.logoFileName,
      logoImageUrl: logoImageUrl ?? this.logoImageUrl,
      governmentIdFileName: governmentIdFileName ?? this.governmentIdFileName,
      governmentIdUrl: governmentIdUrl ?? this.governmentIdUrl,
      selfieFileName: selfieFileName ?? this.selfieFileName,
      selfieUrl: selfieUrl ?? this.selfieUrl,
      isRegisteredBusiness: isRegisteredBusiness ?? this.isRegisteredBusiness,
      businessRegistrationNumber:
          businessRegistrationNumber ?? this.businessRegistrationNumber,
      tinNumber: tinNumber ?? this.tinNumber,
      payoutMethod: payoutMethod ?? this.payoutMethod,
      bankName: bankName ?? this.bankName,
      accountName: accountName ?? this.accountName,
      accountNumber: accountNumber ?? this.accountNumber,
      network: network ?? this.network,
      payoutPhone: payoutPhone ?? this.payoutPhone,
      settlementPreference: settlementPreference ?? this.settlementPreference,
      agreedToPayoutTerms: agreedToPayoutTerms ?? this.agreedToPayoutTerms,
      agreesToCompliance: agreesToCompliance ?? this.agreesToCompliance,
      reviewNotes: reviewNotes ?? this.reviewNotes,
      organizationId: organizationId ?? this.organizationId,
    );
  }
}

class VennuzoOrganizerUpload {
  const VennuzoOrganizerUpload({
    required this.fileName,
    required this.downloadUrl,
  });

  final String fileName;
  final String downloadUrl;
}

class VennuzoOrganizerApplicationService {
  VennuzoOrganizerApplicationService._();

  static final VennuzoOrganizerApplicationService instance =
      VennuzoOrganizerApplicationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<VennuzoOrganizerApplicationDraft?> loadDraft(
    String userId, {
    required VennuzoViewer viewer,
  }) async {
    final snapshot = await _firestore
        .collection('organizer_applications')
        .doc(userId)
        .get();
    if (!snapshot.exists) {
      return null;
    }
    return VennuzoOrganizerApplicationDraft.fromFirestore(
      snapshot.data() ?? <String, dynamic>{},
      viewer: viewer,
    );
  }

  Future<VennuzoOrganizerUpload> uploadImage({
    required String userId,
    required String kind,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final extension = _extensionFor(fileName);
    final ref = _storage.ref(
      'organizer-applications/$userId/$kind-${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await ref.putData(
      bytes,
      SettableMetadata(contentType: _contentTypeFor(extension)),
    );
    return VennuzoOrganizerUpload(
      fileName: fileName,
      downloadUrl: await ref.getDownloadURL(),
    );
  }

  Future<void> saveDraft({
    required String userId,
    required VennuzoOrganizerApplicationDraft draft,
  }) async {
    await _persist(userId: userId, draft: draft, status: 'draft');
  }

  Future<void> submit({
    required String userId,
    required VennuzoOrganizerApplicationDraft draft,
  }) async {
    await _persist(userId: userId, draft: draft, status: 'submitted');
  }

  Future<void> _persist({
    required String userId,
    required VennuzoOrganizerApplicationDraft draft,
    required String status,
  }) async {
    final applicationRef = _firestore
        .collection('organizer_applications')
        .doc(userId);
    final userRef = _firestore.collection('users').doc(userId);
    final organizationId = draft.organizationId.trim().isEmpty
        ? 'org_$userId'
        : draft.organizationId.trim();

    final payload = <String, Object?>{
      'userId': userId,
      'organizerName': draft.organizerName.trim(),
      'contactPerson': draft.contactPerson.trim(),
      'email': draft.email.trim(),
      'phone': draft.phone.trim(),
      'businessType': draft.businessType.trim(),
      'businessAddress': draft.businessAddress.trim(),
      'city': draft.city.trim().isEmpty ? 'Accra' : draft.city.trim(),
      'country': 'Ghana',
      'instagram': draft.instagram.trim(),
      'logoFileName': draft.logoFileName.trim(),
      'logoImageUrl': draft.logoImageUrl.trim(),
      'governmentIdFileName': draft.governmentIdFileName.trim(),
      'governmentIdUrl': draft.governmentIdUrl.trim(),
      'selfieFileName': draft.selfieFileName.trim(),
      'selfieUrl': draft.selfieUrl.trim(),
      'isRegisteredBusiness': draft.isRegisteredBusiness ? 'yes' : 'no',
      'businessRegistrationNumber': draft.businessRegistrationNumber.trim(),
      'tinNumber': draft.tinNumber.trim(),
      'payoutMethod': draft.payoutMethod.trim(),
      'bankName': draft.bankName.trim(),
      'accountName': draft.accountName.trim(),
      'accountNumber': draft.accountNumber.trim(),
      'network': draft.network.trim(),
      'payoutPhone': draft.payoutPhone.trim(),
      'settlementPreference': draft.settlementPreference.trim(),
      'agreedToPayoutTerms': draft.agreedToPayoutTerms,
      'agreesToCompliance': draft.agreesToCompliance,
      'reviewNotes': draft.reviewNotes.trim(),
      'organizationId': organizationId,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      if (status == 'submitted') 'submittedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();
    batch.set(applicationRef, payload, SetOptions(merge: true));
    batch.set(userRef, <String, Object?>{
      'email': draft.email.trim(),
      'phone': draft.phone.trim().isEmpty ? null : draft.phone.trim(),
      'organizerApplicationStatus': status,
      'organizerApplication': <String, Object?>{
        'status': status,
        'organizationId': organizationId,
        'reviewNotes': draft.reviewNotes.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  String _extensionFor(String fileName) {
    final segments = fileName.trim().split('.');
    if (segments.length < 2) {
      return 'jpg';
    }
    final extension = segments.last.trim().toLowerCase();
    return extension.isEmpty ? 'jpg' : extension;
  }

  String _contentTypeFor(String extension) {
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}
