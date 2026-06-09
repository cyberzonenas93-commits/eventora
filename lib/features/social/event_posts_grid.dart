import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import 'social_models.dart';
import 'social_moderation_service.dart';
import 'social_moderation_ui.dart';
import 'social_post_image.dart';
import 'social_service.dart';

class EventPostsGrid extends StatefulWidget {
  EventPostsGrid({
    super.key,
    required this.eventId,
    required this.socialService,
    SocialModerationService? moderationService,
    this.currentUserId,
  }) : moderationService = moderationService ?? SocialModerationService();

  final String eventId;
  final SocialService socialService;
  final SocialModerationService moderationService;

  /// The signed-in viewer's uid. When null it is resolved from the session via
  /// context so callers that don't have it handy (e.g. event detail screen)
  /// still get block-filtering + self-moderation suppression.
  final String? currentUserId;

  @override
  State<EventPostsGrid> createState() => _EventPostsGridState();
}

class _EventPostsGridState extends State<EventPostsGrid> {
  late Stream<List<EventPost>> _postsStream;

  @override
  void initState() {
    super.initState();
    _postsStream = widget.socialService.getEventPosts(widget.eventId);
  }

  @override
  void didUpdateWidget(covariant EventPostsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.socialService != widget.socialService) {
      _postsStream = widget.socialService.getEventPosts(widget.eventId);
    }
  }

  String _resolveCurrentUserId(BuildContext context) {
    if (widget.currentUserId != null) return widget.currentUserId!;
    return context.watch<VennuzoSessionController>().viewer.uid ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _resolveCurrentUserId(context);
    return StreamBuilder<Set<String>>(
      stream: widget.moderationService.blockedUserIds(currentUserId),
      builder: (context, blockedSnap) {
        final blocked = blockedSnap.data ?? const <String>{};
        return _buildGrid(context, blocked, currentUserId);
      },
    );
  }

  Widget _buildGrid(
    BuildContext context,
    Set<String> blocked,
    String currentUserId,
  ) {
    return StreamBuilder<List<EventPost>>(
      stream: _postsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'Event photos could not be loaded right now.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.palette.slate,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final posts = (snapshot.data ?? [])
            .where((p) => !blocked.contains(p.userId))
            .toList();
        if (posts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No photos yet. Be the first to post!',
                style: context.text.bodyMedium?.copyWith(
                  color: context.palette.slate,
                ),
              ),
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return GestureDetector(
              onTap: () =>
                  _openFullScreen(context, post, posts, index, currentUserId),
              child: _PostThumbnail(post: post),
            );
          },
        );
      },
    );
  }

  void _openFullScreen(
    BuildContext context,
    EventPost post,
    List<EventPost> posts,
    int initialIndex,
    String currentUserId,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenPostViewer(
          posts: posts,
          initialIndex: initialIndex,
          socialService: widget.socialService,
          moderationService: widget.moderationService,
          currentUserId: currentUserId,
        ),
      ),
    );
  }
}

class _PostThumbnail extends StatelessWidget {
  const _PostThumbnail({required this.post});
  final EventPost post;

  @override
  Widget build(BuildContext context) {
    final photoUrl = post.photoUrl;
    if (photoUrl == null || photoUrl.isEmpty) {
      return Container(
        color: context.palette.darkSurface,
        child: const Icon(Icons.image_outlined, color: Colors.white54),
      );
    }
    return SocialPostImage(imageUrl: photoUrl, fit: BoxFit.cover);
  }
}

class _FullScreenPostViewer extends StatefulWidget {
  const _FullScreenPostViewer({
    required this.posts,
    required this.initialIndex,
    required this.socialService,
    required this.moderationService,
    required this.currentUserId,
  });

  final List<EventPost> posts;
  final int initialIndex;
  final SocialService socialService;
  final SocialModerationService moderationService;
  final String currentUserId;

  @override
  State<_FullScreenPostViewer> createState() => _FullScreenPostViewerState();
}

class _FullScreenPostViewerState extends State<_FullScreenPostViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final lastIndex = widget.posts.isEmpty ? 0 : widget.posts.length - 1;
    _currentIndex = widget.initialIndex.clamp(0, lastIndex);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            'Post unavailable',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final lastIndex = widget.posts.length - 1;
    final safeIndex = _currentIndex.clamp(0, lastIndex);
    final currentPost = widget.posts[safeIndex];
    final canModerate =
        currentPost.userId.isNotEmpty &&
        currentPost.userId != widget.currentUserId;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${safeIndex + 1} / ${widget.posts.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (canModerate)
            ContentModerationButton(
              contentType: ReportContentType.post,
              contentId: currentPost.postId,
              authorId: currentPost.userId,
              authorName: currentPost.displayName,
              currentUserId: widget.currentUserId,
              isBlocked: false,
              color: Colors.white,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.posts.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          return _FullScreenPostCard(
            post: widget.posts[index],
            socialService: widget.socialService,
          );
        },
      ),
    );
  }
}

class _FullScreenPostCard extends StatelessWidget {
  const _FullScreenPostCard({required this.post, required this.socialService});

  final EventPost post;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    final photoUrl = post.photoUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Photo
        if (photoUrl != null && photoUrl.isNotEmpty)
          SocialPostImage(imageUrl: photoUrl, fit: BoxFit.contain)
        else
          const Icon(Icons.image_outlined, color: Colors.white38, size: 64),
        // Glass overlay at bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xDD000000), Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white24,
                      foregroundImage: post.userPhotoUrl != null
                          ? CachedNetworkImageProvider(post.userPhotoUrl!)
                          : null,
                      child: post.userPhotoUrl == null
                          ? const Icon(
                              Icons.person,
                              color: Colors.white70,
                              size: 16,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      post.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (post.caption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    post.caption,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.white70, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${post.likeCount}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.comment_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.commentCount}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
