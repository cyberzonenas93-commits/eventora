import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

import '../../core/theme/theme_extensions.dart';
import 'social_models.dart';
import 'social_service.dart';

Future<void> showWriteReviewSheet(
  BuildContext context, {
  required String eventId,
  required String userId,
  required String displayName,
  String? photoUrl,
  required SocialService socialService,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WriteReviewSheet(
      eventId: eventId,
      userId: userId,
      displayName: displayName,
      photoUrl: photoUrl,
      socialService: socialService,
    ),
  );
}

class _WriteReviewSheet extends StatefulWidget {
  const _WriteReviewSheet({
    required this.eventId,
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.socialService,
  });

  final String eventId;
  final String userId;
  final String displayName;
  final String? photoUrl;
  final SocialService socialService;

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  double _rating = 4.0;
  final _textController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write something about the event.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final review = EventReview(
        reviewId: widget.socialService.generateId('review'),
        eventId: widget.eventId,
        userId: widget.userId,
        displayName: widget.displayName,
        photoUrl: widget.photoUrl,
        rating: _rating,
        comment: _textController.text.trim(),
        timestamp: DateTime.now(),
      );
      await widget.socialService.submitReview(review);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit review. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Write a Review',
            style: context.text.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Share your experience at this event',
            style: context.text.bodyMedium?.copyWith(color: palette.slate),
          ),
          const SizedBox(height: 24),
          Center(
            child: RatingBar.builder(
              initialRating: _rating,
              minRating: 1,
              direction: Axis.horizontal,
              allowHalfRating: true,
              itemCount: 5,
              itemSize: 40,
              itemPadding: const EdgeInsets.symmetric(horizontal: 4),
              itemBuilder: (_, __) => const Icon(
                Icons.star,
                color: Color(0xFFFFD700),
              ),
              onRatingUpdate: (rating) => setState(() => _rating = rating),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _textController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Tell others what you thought about this event...',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit Review'),
            ),
          ),
        ],
      ),
    );
  }
}
