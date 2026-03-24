import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'social_models.dart';

class SocialService {
  SocialService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  // ─── Event Saves ──────────────────────────────────────────────────────────

  Future<void> saveEvent(String userId, String eventId) async {
    final save = EventSave(
      userId: userId,
      eventId: eventId,
      savedAt: DateTime.now(),
    );
    await _firestore
        .collection('event_saves')
        .doc(userId)
        .collection('saved')
        .doc(eventId)
        .set(save.toMap());
  }

  Future<void> unsaveEvent(String userId, String eventId) async {
    await _firestore
        .collection('event_saves')
        .doc(userId)
        .collection('saved')
        .doc(eventId)
        .delete();
  }

  Stream<bool> isEventSaved(String userId, String eventId) {
    return _firestore
        .collection('event_saves')
        .doc(userId)
        .collection('saved')
        .doc(eventId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  Stream<List<String>> getSavedEvents(String userId) {
    return _firestore
        .collection('event_saves')
        .doc(userId)
        .collection('saved')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList());
  }

  // ─── Event Reactions ──────────────────────────────────────────────────────

  Future<void> reactToEvent(String userId, String eventId) async {
    final reaction = EventReaction(
      userId: userId,
      eventId: eventId,
      type: 'like',
      timestamp: DateTime.now(),
    );
    await _firestore
        .collection('event_reactions')
        .doc(eventId)
        .collection('reactions')
        .doc(userId)
        .set(reaction.toMap());
  }

  Future<void> unreactToEvent(String userId, String eventId) async {
    await _firestore
        .collection('event_reactions')
        .doc(eventId)
        .collection('reactions')
        .doc(userId)
        .delete();
  }

  Stream<int> getReactionCount(String eventId) {
    return _firestore
        .collection('event_reactions')
        .doc(eventId)
        .collection('reactions')
        .snapshots()
        .map((snap) => snap.size);
  }

  Stream<bool> hasUserReacted(String userId, String eventId) {
    return _firestore
        .collection('event_reactions')
        .doc(eventId)
        .collection('reactions')
        .doc(userId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  // ─── Reviews ──────────────────────────────────────────────────────────────

  Future<void> submitReview(EventReview review) async {
    final ref = _firestore
        .collection('event_reviews')
        .doc(review.eventId)
        .collection('reviews')
        .doc(review.reviewId.isEmpty ? null : review.reviewId);
    await ref.set(review.toMap());
  }

  Stream<List<EventReview>> getEventReviews(String eventId) {
    return _firestore
        .collection('event_reviews')
        .doc(eventId)
        .collection('reviews')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => EventReview.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  Stream<double> getAverageRating(String eventId) {
    return getEventReviews(eventId).map((reviews) {
      if (reviews.isEmpty) return 0.0;
      final sum = reviews.fold<double>(0, (acc, r) => acc + r.rating);
      return sum / reviews.length;
    });
  }

  // ─── Posts ────────────────────────────────────────────────────────────────

  Future<void> createPost(EventPost post, File imageFile) async {
    final storageRef = _storage
        .ref()
        .child('event_posts')
        .child(post.eventId)
        .child('${post.postId}.jpg');
    await storageRef.putFile(imageFile);
    final photoUrl = await storageRef.getDownloadURL();

    final updatedPost = post.copyWith(photoUrl: photoUrl);
    await _firestore
        .collection('event_posts')
        .doc(post.postId)
        .set(updatedPost.toMap());
  }

  Stream<List<EventPost>> getEventPosts(String eventId) {
    return _firestore
        .collection('event_posts')
        .where('eventId', isEqualTo: eventId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => EventPost.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  Stream<List<EventPost>> getUserPosts(String userId) {
    return _firestore
        .collection('event_posts')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => EventPost.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  Future<void> likePost(String postId, String userId) async {
    final batch = _firestore.batch();
    final likeRef = _firestore
        .collection('post_likes')
        .doc(postId)
        .collection('likes')
        .doc(userId);
    final postRef = _firestore.collection('event_posts').doc(postId);
    batch.set(likeRef, {
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
    });
    batch.update(postRef, {'likeCount': FieldValue.increment(1)});
    await batch.commit();
  }

  Future<void> unlikePost(String postId, String userId) async {
    final batch = _firestore.batch();
    final likeRef = _firestore
        .collection('post_likes')
        .doc(postId)
        .collection('likes')
        .doc(userId);
    final postRef = _firestore.collection('event_posts').doc(postId);
    batch.delete(likeRef);
    batch.update(postRef, {'likeCount': FieldValue.increment(-1)});
    await batch.commit();
  }

  Stream<bool> hasUserLikedPost(String postId, String userId) {
    return _firestore
        .collection('post_likes')
        .doc(postId)
        .collection('likes')
        .doc(userId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  // ─── Comments ─────────────────────────────────────────────────────────────

  Future<void> addComment(PostComment comment) async {
    final batch = _firestore.batch();
    final commentRef = _firestore
        .collection('post_comments')
        .doc(comment.postId)
        .collection('comments')
        .doc(
          comment.commentId.isEmpty ? null : comment.commentId,
        );
    final postRef =
        _firestore.collection('event_posts').doc(comment.postId);
    batch.set(commentRef, comment.toMap());
    batch.update(postRef, {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  }

  Stream<List<PostComment>> getComments(String postId) {
    return _firestore
        .collection('post_comments')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => PostComment.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  // ─── Social Graph ─────────────────────────────────────────────────────────

  Future<void> followUser(String followerId, String targetId) async {
    final follow = SocialFollow(
      followerId: followerId,
      followingId: targetId,
      timestamp: DateTime.now(),
    );
    await _firestore
        .collection('social_follows')
        .doc(followerId)
        .collection('following')
        .doc(targetId)
        .set(follow.toMap());
  }

  Future<void> unfollowUser(String followerId, String targetId) async {
    await _firestore
        .collection('social_follows')
        .doc(followerId)
        .collection('following')
        .doc(targetId)
        .delete();
  }

  Stream<bool> isFollowing(String followerId, String targetId) {
    return _firestore
        .collection('social_follows')
        .doc(followerId)
        .collection('following')
        .doc(targetId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  Stream<int> getFollowerCount(String userId) {
    return _firestore
        .collectionGroup('following')
        .where('followingId', isEqualTo: userId)
        .snapshots()
        .map((snap) => snap.size);
  }

  Stream<int> getFollowingCount(String userId) {
    return _firestore
        .collection('social_follows')
        .doc(userId)
        .collection('following')
        .snapshots()
        .map((snap) => snap.size);
  }

  // ─── Feed ─────────────────────────────────────────────────────────────────

  Stream<List<EventPost>> getRecentFeed({int limit = 30}) {
    return _firestore
        .collection('event_posts')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => EventPost.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String generateId(String prefix) {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final rand = (ms % 99999).toString().padLeft(5, '0');
    return '${prefix}_${ms}_$rand';
  }
}
