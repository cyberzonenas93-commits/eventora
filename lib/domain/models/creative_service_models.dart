import 'package:cloud_firestore/cloud_firestore.dart';

class CreativeBrandConfig {
  const CreativeBrandConfig({
    this.brandName = '',
    this.tagline = '',
    this.brandStyle = '',
    this.brandColor = '#7dd3fc',
    this.logoUrl = '',
    this.phones = const <String>[],
    this.instagram = '',
    this.website = '',
  });

  final String brandName;
  final String tagline;
  final String brandStyle;
  final String brandColor;
  final String logoUrl;
  final List<String> phones;
  final String instagram;
  final String website;

  factory CreativeBrandConfig.fromMap(Map<dynamic, dynamic>? data) {
    final map = data ?? const <dynamic, dynamic>{};
    return CreativeBrandConfig(
      brandName: '${map['brandName'] ?? ''}'.trim(),
      tagline: '${map['tagline'] ?? ''}'.trim(),
      brandStyle: '${map['brandStyle'] ?? ''}'.trim(),
      brandColor: '${map['brandColor'] ?? '#7dd3fc'}'.trim(),
      logoUrl: '${map['logoUrl'] ?? ''}'.trim(),
      phones:
          (map['phones'] as Iterable?)
              ?.map((value) => '$value'.trim())
              .where((value) => value.isNotEmpty)
              .toList() ??
          const <String>[],
      instagram: '${map['instagram'] ?? ''}'.trim(),
      website: '${map['website'] ?? ''}'.trim(),
    );
  }

  Map<String, Object?> toPayload({String? organizationId}) {
    final payload = <String, Object?>{
      'brandName': brandName.trim(),
      'tagline': tagline.trim(),
      'brandStyle': brandStyle.trim(),
      'brandColor': brandColor.trim(),
      'logoUrl': logoUrl.trim(),
      'phones': phones.map((phone) => phone.trim()).where((phone) {
        return phone.isNotEmpty;
      }).toList(),
      'instagram': instagram.trim(),
      'website': website.trim(),
    };
    if (organizationId != null) {
      payload['organizationId'] = organizationId;
    }
    return payload;
  }

  CreativeBrandConfig copyWith({
    String? brandName,
    String? tagline,
    String? brandStyle,
    String? brandColor,
    String? logoUrl,
    List<String>? phones,
    String? instagram,
    String? website,
  }) {
    return CreativeBrandConfig(
      brandName: brandName ?? this.brandName,
      tagline: tagline ?? this.tagline,
      brandStyle: brandStyle ?? this.brandStyle,
      brandColor: brandColor ?? this.brandColor,
      logoUrl: logoUrl ?? this.logoUrl,
      phones: phones ?? this.phones,
      instagram: instagram ?? this.instagram,
      website: website ?? this.website,
    );
  }
}

class CreativeServicesPricing {
  const CreativeServicesPricing({
    this.flyerGhs = 50,
    this.tablePackageFlyerGhs = 50,
    this.flyerVideoGhs = 100,
    this.includedMinorEdits = 10,
    this.includedRedesigns = 2,
  });

  final double flyerGhs;
  final double tablePackageFlyerGhs;
  final double flyerVideoGhs;
  final int includedMinorEdits;
  final int includedRedesigns;

  factory CreativeServicesPricing.fromMap(Map<dynamic, dynamic>? data) {
    final map = data ?? const <dynamic, dynamic>{};
    return CreativeServicesPricing(
      flyerGhs: (map['flyerGhs'] as num?)?.toDouble() ?? 50,
      tablePackageFlyerGhs:
          (map['tablePackageFlyerGhs'] as num?)?.toDouble() ?? 50,
      flyerVideoGhs: (map['flyerVideoGhs'] as num?)?.toDouble() ?? 100,
      includedMinorEdits: (map['includedMinorEdits'] as num?)?.toInt() ?? 10,
      includedRedesigns: (map['includedRedesigns'] as num?)?.toInt() ?? 2,
    );
  }
}

class CreativeServicesConfig {
  const CreativeServicesConfig({
    required this.organizationId,
    required this.brand,
    required this.pricing,
  });

  final String organizationId;
  final CreativeBrandConfig brand;
  final CreativeServicesPricing pricing;
}

class CreativeTier {
  const CreativeTier({
    required this.name,
    required this.price,
    required this.items,
  });

  final String name;
  final String price;
  final List<String> items;

  Map<String, Object?> toPayload() {
    return <String, Object?>{
      'name': name.trim(),
      'price': price.trim(),
      'items': items.map((item) => item.trim()).where((item) {
        return item.isNotEmpty;
      }).toList(),
    };
  }
}

class CreativeJobSnapshot {
  const CreativeJobSnapshot({
    required this.jobId,
    required this.status,
    this.eventName = 'Creative asset',
    this.currentStep = '',
    this.progress = 0,
    this.imageUrl = '',
    this.sessionId = '',
    this.error = '',
  });

  final String jobId;
  final String status;
  final String eventName;
  final String currentStep;
  final int progress;
  final String imageUrl;
  final String sessionId;
  final String error;

  bool get isComplete => status == 'complete';
  bool get hasFailed => status == 'error' || status == 'failed';

  factory CreativeJobSnapshot.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CreativeJobSnapshot(
      jobId: doc.id,
      status: '${data['status'] ?? 'pending'}'.trim(),
      eventName: '${data['eventName'] ?? 'Creative asset'}'.trim(),
      currentStep: '${data['currentStep'] ?? ''}'.trim(),
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      imageUrl: '${data['imageUrl'] ?? ''}'.trim(),
      sessionId: '${data['sessionId'] ?? ''}'.trim(),
      error: '${data['error'] ?? ''}'.trim(),
    );
  }
}

class CreativeVideoJobSnapshot {
  const CreativeVideoJobSnapshot({
    required this.jobId,
    required this.status,
    this.eventName = 'Flyer video',
    this.currentStep = '',
    this.progress = 0,
    this.videoUrl = '',
    this.motionPrompt = '',
    this.error = '',
  });

  final String jobId;
  final String status;
  final String eventName;
  final String currentStep;
  final int progress;
  final String videoUrl;
  final String motionPrompt;
  final String error;

  bool get isComplete => status == 'complete';
  bool get hasFailed => status == 'error' || status == 'failed';

  factory CreativeVideoJobSnapshot.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CreativeVideoJobSnapshot(
      jobId: doc.id,
      status: '${data['status'] ?? 'pending'}'.trim(),
      eventName: '${data['eventName'] ?? 'Flyer video'}'.trim(),
      currentStep: '${data['currentStep'] ?? ''}'.trim(),
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      videoUrl: '${data['videoUrl'] ?? ''}'.trim(),
      motionPrompt: '${data['motionPrompt'] ?? ''}'.trim(),
      error: '${data['error'] ?? ''}'.trim(),
    );
  }
}

class CreativeSession {
  const CreativeSession({
    required this.id,
    required this.eventName,
    required this.serviceType,
    required this.imageUrl,
    required this.createdAt,
    this.minorEditsRemaining,
    this.redesignsRemaining,
    this.priceChargedGhs = 0,
    this.latestVideoUrl = '',
    this.latestVideoJobId = '',
  });

  final String id;
  final String eventName;
  final String serviceType;
  final String imageUrl;
  final DateTime createdAt;
  final int? minorEditsRemaining;
  final int? redesignsRemaining;
  final double priceChargedGhs;
  final String latestVideoUrl;
  final String latestVideoJobId;

  bool get isTablePackage => serviceType == 'table_package_flyer';

  factory CreativeSession.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return CreativeSession(
      id: doc.id,
      eventName: '${data['eventName'] ?? 'Creative asset'}'.trim(),
      serviceType: '${data['serviceType'] ?? 'event_flyer'}'.trim(),
      imageUrl: '${data['imageUrl'] ?? data['downloadUrl'] ?? ''}'.trim(),
      createdAt: _dateFromValue(data['createdAt']) ?? DateTime.now(),
      minorEditsRemaining: (data['minorEditsRemaining'] as num?)?.toInt(),
      redesignsRemaining: (data['redesignsRemaining'] as num?)?.toInt(),
      priceChargedGhs: (data['priceChargedGhs'] as num?)?.toDouble() ?? 0,
      latestVideoUrl: '${data['latestVideoUrl'] ?? ''}'.trim(),
      latestVideoJobId: '${data['latestVideoJobId'] ?? ''}'.trim(),
    );
  }
}

class WalletBalance {
  const WalletBalance({
    this.availableBalance = 0,
    this.heldBalance = 0,
    this.currency = 'GHS',
  });

  final double availableBalance;
  final double heldBalance;
  final String currency;

  factory WalletBalance.fromMap(Map<dynamic, dynamic>? data) {
    final map = data ?? const <dynamic, dynamic>{};
    return WalletBalance(
      availableBalance: (map['availableBalance'] as num?)?.toDouble() ?? 0,
      heldBalance: (map['heldBalance'] as num?)?.toDouble() ?? 0,
      currency: '${map['currency'] ?? 'GHS'}'.trim(),
    );
  }
}

DateTime? _dateFromValue(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
