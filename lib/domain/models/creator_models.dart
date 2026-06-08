class CreatorProfile {
  const CreatorProfile({
    required this.creatorId,
    required this.displayName,
    this.bio = '',
    this.city = 'Accra',
    this.avatarUrl,
    this.coverUrl,
    this.followerCount = 0,
    this.eventCount = 0,
    this.photoCount = 0,
    required this.updatedAt,
  });

  final String creatorId;
  final String displayName;
  final String bio;
  final String city;
  final String? avatarUrl;
  final String? coverUrl;
  final int followerCount;
  final int eventCount;
  final int photoCount;
  final DateTime updatedAt;

  CreatorProfile copyWith({
    String? creatorId,
    String? displayName,
    String? bio,
    String? city,
    String? avatarUrl,
    bool clearAvatarUrl = false,
    String? coverUrl,
    bool clearCoverUrl = false,
    int? followerCount,
    int? eventCount,
    int? photoCount,
    DateTime? updatedAt,
  }) {
    return CreatorProfile(
      creatorId: creatorId ?? this.creatorId,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      city: city ?? this.city,
      avatarUrl: clearAvatarUrl ? null : avatarUrl ?? this.avatarUrl,
      coverUrl: clearCoverUrl ? null : coverUrl ?? this.coverUrl,
      followerCount: followerCount ?? this.followerCount,
      eventCount: eventCount ?? this.eventCount,
      photoCount: photoCount ?? this.photoCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CreatorEventPhoto {
  const CreatorEventPhoto({
    required this.id,
    required this.creatorId,
    required this.eventId,
    required this.eventTitle,
    required this.imageUrl,
    this.caption = '',
    required this.createdAt,
  });

  final String id;
  final String creatorId;
  final String eventId;
  final String eventTitle;
  final String imageUrl;
  final String caption;
  final DateTime createdAt;
}
