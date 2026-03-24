import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';

import '../../core/theme/theme_extensions.dart';
import 'event_posts_grid.dart';
import 'social_models.dart';
import 'social_service.dart';
import 'write_review_sheet.dart';

class EventDetailSocialTab extends StatelessWidget {
  const EventDetailSocialTab({
    super.key,
    required this.eventId,
    required this.userId,
    required this.displayName,
    this.userPhotoUrl,
    required this.socialService,
  });

  final String eventId;
  final String userId;
  final String displayName;
  final String? userPhotoUrl;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _RatingSummary(
          eventId: eventId,
          socialService: socialService,
        ),
        const SizedBox(height: 16),
        if (userId.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => showWriteReviewSheet(
              context,
              eventId: eventId,
              userId: userId,
              displayName: displayName,
              photoUrl: userPhotoUrl,
              socialService: socialService,
            ),
            icon: const Icon(Icons.star_outline),
            label: const Text('Write a Review'),
          ),
        const SizedBox(height: 24),
        _ReviewsList(
          eventId: eventId,
          socialService: socialService,
        ),
        const SizedBox(height: 24),
        Text(
          'Event Photos',
          style: context.text.titleMedium,
        ),
        const SizedBox(height: 12),
        EventPostsGrid(
          eventId: eventId,
          socialService: socialService,
        ),
      ],
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({
    required this.eventId,
    required this.socialService,
  });

  final String eventId;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EventReview>>(
      stream: socialService.getEventReviews(eventId),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? [];
        final count = reviews.length;

        double average = 0;
        final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
        if (count > 0) {
          double sum = 0;
          for (final r in reviews) {
            sum += r.rating;
            final key = r.rating.round().clamp(1, 5);
            dist[key] = (dist[key] ?? 0) + 1;
          }
          average = sum / count;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Text(
                      average.toStringAsFixed(1),
                      style: context.text.headlineMedium?.copyWith(
                        color: const Color(0xFFFFD700),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    RatingBarIndicator(
                      rating: average,
                      itemSize: 16,
                      itemBuilder: (_, __) => const Icon(
                        Icons.star,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count review${count != 1 ? 's' : ''}',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.palette.slate,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [5, 4, 3, 2, 1].map((star) {
                      final starCount = dist[star] ?? 0;
                      final fraction =
                          count == 0 ? 0.0 : starCount / count;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              '$star',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.star,
                                color: Color(0xFFFFD700), size: 12),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: fraction,
                                  backgroundColor:
                                      context.palette.border,
                                  color: const Color(0xFFFFD700),
                                  minHeight: 6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 20,
                              child: Text(
                                '$starCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.palette.slate,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReviewsList extends StatelessWidget {
  const _ReviewsList({
    required this.eventId,
    required this.socialService,
  });

  final String eventId;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EventReview>>(
      stream: socialService.getEventReviews(eventId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final reviews = snapshot.data ?? [];
        if (reviews.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No reviews yet.',
              style: context.text.bodyMedium?.copyWith(
                color: context.palette.slate,
              ),
            ),
          );
        }
        return Column(
          children: reviews.map((r) => _ReviewCard(review: r)).toList(),
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final EventReview review;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy').format(review.timestamp);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: review.photoUrl != null
                      ? NetworkImage(review.photoUrl!)
                      : null,
                  child: review.photoUrl == null
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.displayName,
                        style: context.text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: context.text.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: context.palette.slate,
                        ),
                      ),
                    ],
                  ),
                ),
                RatingBarIndicator(
                  rating: review.rating,
                  itemSize: 14,
                  itemBuilder: (_, __) => const Icon(
                    Icons.star,
                    color: Color(0xFFFFD700),
                  ),
                ),
              ],
            ),
            if (review.comment.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(review.comment, style: context.text.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
