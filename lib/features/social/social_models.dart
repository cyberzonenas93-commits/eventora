import 'package:cloud_firestore/cloud_firestore.dart';

class EventSave {
  const EventSave({
    required this.userId,
    required this.eventId,
    required this.savedAt,
  });

  final String userId;
  final String eventId;
  final DateTime savedAt;

  factory EventSave.fromFirestore(Map<String, dynamic> data) {
    return EventSave(
      userId: data['userId'] as String? ?? '',
      eventId: data['eventId'] as String? ?? '',
      savedAt: (data['savedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'eventId': eventId,
        'savedAt': Timestamp.fromDate(savedAt),
      };
}

class EventReaction {
  const EventReaction({
    required this.userId,
    required this.eventId,
    required this.type,
    required this.timestamp,
  });

  final String userId;
  final String eventId;
  final String type;
  final DateTime timestamp;

  factory EventReaction.fromFirestore(Map<String, dynamic> data) {
    return EventReaction(
      userId: data['userId'] as String? ?? '',
      eventId: data['eventId'] as String? ?? '',
      type: data['type'] as String? ?? 'like',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'eventId': eventId,
        'type': type,
        'timestamp': Timestamp.fromDate(timestamp),
      };
}

class EventReview {
  const EventReview({
    required this.reviewId,
    required this.eventId,
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.rating,
    required this.comment,
    required this.timestamp,
    this.likes = 0,
  });

  final String reviewId;
  final String eventId;
  final String userId;
  final String displayName;
  final String? photoUrl;
  final double rating;
  final String comment;
  final DateTime timestamp;
  final int likes;

  factory EventReview.fromFirestore(String id, Map<String, dynamic> data) {
    return EventReview(
      reviewId: id,
      eventId: data['eventId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Attendee',
      photoUrl: data['photoUrl'] as String?,
      rating: (data['rating'] as num?)?.toDouble() ?? 3.0,
      comment: data['comment'] as String? ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      likes: (data['likes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'eventId': eventId,
        'userId': userId,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'rating': rating,
        'comment': comment,
        'timestamp': Timestamp.fromDate(timestamp),
        'likes': likes,
      };
}

class EventPost {
  const EventPost({
    required this.postId,
    required this.eventId,
    required this.userId,
    required this.displayName,
    this.userPhotoUrl,
    this.photoUrl,
    this.caption = '',
    this.likeCount = 0,
    this.commentCount = 0,
    required this.timestamp,
  });

  final String postId;
  final String eventId;
  final String userId;
  final String displayName;
  final String? userPhotoUrl;
  final String? photoUrl;
  final String caption;
  final int likeCount;
  final int commentCount;
  final DateTime timestamp;

  factory EventPost.fromFirestore(String id, Map<String, dynamic> data) {
    return EventPost(
      postId: id,
      eventId: data['eventId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Attendee',
      userPhotoUrl: data['userPhotoUrl'] as String?,
      photoUrl: data['photoUrl'] as String?,
      caption: data['caption'] as String? ?? '',
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'eventId': eventId,
        'userId': userId,
        'displayName': displayName,
        'userPhotoUrl': userPhotoUrl,
        'photoUrl': photoUrl,
        'caption': caption,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'timestamp': Timestamp.fromDate(timestamp),
      };

  EventPost copyWith({
    String? photoUrl,
    int? likeCount,
    int? commentCount,
  }) {
    return EventPost(
      postId: postId,
      eventId: eventId,
      userId: userId,
      displayName: displayName,
      userPhotoUrl: userPhotoUrl,
      photoUrl: photoUrl ?? this.photoUrl,
      caption: caption,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      timestamp: timestamp,
    );
  }
}

class PostComment {
  const PostComment({
    required this.commentId,
    required this.postId,
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.text,
    required this.timestamp,
  });

  final String commentId;
  final String postId;
  final String userId;
  final String displayName;
  final String? photoUrl;
  final String text;
  final DateTime timestamp;

  factory PostComment.fromFirestore(String id, Map<String, dynamic> data) {
    return PostComment(
      commentId: id,
      postId: data['postId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Attendee',
      photoUrl: data['photoUrl'] as String?,
      text: data['text'] as String? ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'postId': postId,
        'userId': userId,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'text': text,
        'timestamp': Timestamp.fromDate(timestamp),
      };
}

class SocialFollow {
  const SocialFollow({
    required this.followerId,
    required this.followingId,
    required this.timestamp,
  });

  final String followerId;
  final String followingId;
  final DateTime timestamp;

  factory SocialFollow.fromFirestore(Map<String, dynamic> data) {
    return SocialFollow(
      followerId: data['followerId'] as String? ?? '',
      followingId: data['followingId'] as String? ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'followerId': followerId,
        'followingId': followingId,
        'timestamp': Timestamp.fromDate(timestamp),
      };
}
