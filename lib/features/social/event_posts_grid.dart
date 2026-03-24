import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/theme_extensions.dart';
import 'social_models.dart';
import 'social_service.dart';

class EventPostsGrid extends StatelessWidget {
  const EventPostsGrid({
    super.key,
    required this.eventId,
    required this.socialService,
  });

  final String eventId;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EventPost>>(
      stream: socialService.getEventPosts(eventId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final posts = snapshot.data ?? [];
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
              onTap: () => _openFullScreen(context, post, posts, index),
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
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenPostViewer(
          posts: posts,
          initialIndex: initialIndex,
          socialService: socialService,
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
    return CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: const Color(0xFF1F2937),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFF1F2937),
        child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
      ),
    );
  }
}

class _FullScreenPostViewer extends StatefulWidget {
  const _FullScreenPostViewer({
    required this.posts,
    required this.initialIndex,
    required this.socialService,
  });

  final List<EventPost> posts;
  final int initialIndex;
  final SocialService socialService;

  @override
  State<_FullScreenPostViewer> createState() => _FullScreenPostViewerState();
}

class _FullScreenPostViewerState extends State<_FullScreenPostViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.posts.length}',
          style: const TextStyle(color: Colors.white),
        ),
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
  const _FullScreenPostCard({
    required this.post,
    required this.socialService,
  });

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
          CachedNetworkImage(
            imageUrl: photoUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white38,
              size: 64,
            ),
          )
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
                          ? NetworkImage(post.userPhotoUrl!)
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
                        Icons.comment_outlined, color: Colors.white70, size: 18),
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
