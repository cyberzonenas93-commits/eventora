import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/repositories/vennuzo_repository.dart';
import 'saved_events_screen.dart';
import 'social_models.dart';
import 'social_service.dart';

class SocialFeedScreen extends StatefulWidget {
  const SocialFeedScreen({super.key});

  @override
  State<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends State<SocialFeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _socialService = SocialService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Social'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: palette.teal,
          unselectedLabelColor: palette.slate,
          indicatorColor: palette.teal,
          tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Explore'),
            Tab(text: 'Saved'),
          ],
        ),
      ),
      floatingActionButton: session.isGuest
          ? null
          : FloatingActionButton(
              onPressed: () => _openNewPostFlow(context, session),
              tooltip: 'New Post',
              child: const Icon(Icons.add_a_photo_outlined),
            ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FeedTab(socialService: _socialService),
          _ExploreTab(socialService: _socialService),
          SavedEventsScreen(userId: session.viewer.uid ?? ''),
        ],
      ),
    );
  }

  Future<void> _openNewPostFlow(
      BuildContext context, VennuzoSessionController session) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;

    final imageFile = File(picked.path);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewPostSheet(
        imageFile: imageFile,
        session: session,
        socialService: _socialService,
      ),
    );
  }
}

// ─── Feed Tab ────────────────────────────────────────────────────────────────

class _FeedTab extends StatelessWidget {
  const _FeedTab({required this.socialService});
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EventPost>>(
      stream: socialService.getRecentFeed(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 64,
                    color: context.palette.slate.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nothing here yet',
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Posts from events you follow will appear here.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium
                        ?.copyWith(color: context.palette.slate),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            return _FeedPostCard(
              post: posts[index],
              socialService: socialService,
            );
          },
        );
      },
    );
  }
}

// ─── Explore Tab ─────────────────────────────────────────────────────────────

class _ExploreTab extends StatelessWidget {
  const _ExploreTab({required this.socialService});
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EventPost>>(
      stream: socialService.getRecentFeed(limit: 60),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return Center(
            child: Text(
              'No posts to explore yet.',
              style: context.text.bodyMedium
                  ?.copyWith(color: context.palette.slate),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            final photoUrl = post.photoUrl;
            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _SinglePostScreen(
                    post: post,
                    socialService: socialService,
                  ),
                ),
              ),
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFF1F2937),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF1F2937),
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.white38),
                      ),
                    )
                  : Container(
                      color: const Color(0xFF1F2937),
                      child: const Icon(Icons.image_outlined,
                          color: Colors.white38),
                    ),
            );
          },
        );
      },
    );
  }
}

// ─── Feed Post Card ───────────────────────────────────────────────────────────

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({
    required this.post,
    required this.socialService,
  });

  final EventPost post;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final repository = context.watch<VennuzoRepository>();
    final event = repository.eventById(post.eventId);
    final photoUrl = post.photoUrl;
    final dateStr = DateFormat('MMM d').format(post.timestamp);

    return Container(
      color: context.palette.darkSurface,
      margin: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  foregroundImage: post.userPhotoUrl != null
                      ? NetworkImage(post.userPhotoUrl!)
                      : null,
                  child: post.userPhotoUrl == null
                      ? const Icon(Icons.person, color: Colors.white70, size: 18)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (event != null)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.palette.teal.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            event.title,
                            style: TextStyle(
                              color: context.palette.teal,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          // Photo
          if (photoUrl != null && photoUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: photoUrl,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                height: 300,
                color: const Color(0xFF1F2937),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                height: 200,
                color: const Color(0xFF1F2937),
                child: const Icon(Icons.broken_image_outlined,
                    color: Colors.white38, size: 48),
              ),
            ),
          // Caption
          if (post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                post.caption,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
            child: Row(
              children: [
                _LikeButton(
                  postId: post.postId,
                  likeCount: post.likeCount,
                  userId: session.viewer.uid ?? '',
                  socialService: socialService,
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _SinglePostScreen(
                        post: post,
                        socialService: socialService,
                      ),
                    ),
                  ),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  icon: const Icon(Icons.comment_outlined, size: 20),
                  label: Text('${post.commentCount}'),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.share_outlined, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Like Button ──────────────────────────────────────────────────────────────

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.postId,
    required this.likeCount,
    required this.userId,
    required this.socialService,
  });

  final String postId;
  final int likeCount;
  final String userId;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return TextButton.icon(
        onPressed: null,
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        icon: const Icon(Icons.favorite_outline, size: 20),
        label: Text('$likeCount'),
      );
    }
    return StreamBuilder<bool>(
      stream: socialService.hasUserLikedPost(postId, userId),
      builder: (context, snapshot) {
        final liked = snapshot.data ?? false;
        return TextButton.icon(
          onPressed: () {
            if (liked) {
              socialService.unlikePost(postId, userId);
            } else {
              socialService.likePost(postId, userId);
            }
          },
          style: TextButton.styleFrom(
            foregroundColor:
                liked ? context.palette.coral : Colors.white70,
          ),
          icon: Icon(
            liked ? Icons.favorite : Icons.favorite_outline,
            size: 20,
          ),
          label: Text('$likeCount'),
        );
      },
    );
  }
}

// ─── Single Post Screen ───────────────────────────────────────────────────────

class _SinglePostScreen extends StatefulWidget {
  const _SinglePostScreen({
    required this.post,
    required this.socialService,
  });

  final EventPost post;
  final SocialService socialService;

  @override
  State<_SinglePostScreen> createState() => _SinglePostScreenState();
}

class _SinglePostScreenState extends State<_SinglePostScreen> {
  final _commentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment(String userId, String displayName) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final comment = PostComment(
        commentId: widget.socialService.generateId('comment'),
        postId: widget.post.postId,
        userId: userId,
        displayName: displayName,
        text: text,
        timestamp: DateTime.now(),
      );
      await widget.socialService.addComment(comment);
      _commentController.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final photoUrl = widget.post.photoUrl;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.post.displayName,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                if (photoUrl != null && photoUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: photoUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      height: 300,
                      color: const Color(0xFF1F2937),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 200,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                if (widget.post.caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.post.caption,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                const Divider(color: Colors.white12),
                StreamBuilder<List<PostComment>>(
                  stream: widget.socialService
                      .getComments(widget.post.postId),
                  builder: (context, snapshot) {
                    final comments = snapshot.data ?? [];
                    return Column(
                      children: comments.map((c) {
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            foregroundImage: c.photoUrl != null
                                ? NetworkImage(c.photoUrl!)
                                : null,
                            child: c.photoUrl == null
                                ? const Icon(Icons.person,
                                    size: 14, color: Colors.white)
                                : null,
                          ),
                          title: Text(
                            c.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            c.text,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          if (!session.isGuest)
            Container(
              color: const Color(0xFF111827),
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottom),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Add a comment…',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        filled: true,
                        fillColor: Color(0xFF1F2937),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => _submitComment(
                              session.viewer.uid ?? '',
                              session.viewer.displayName,
                            ),
                    icon: Icon(
                      Icons.send,
                      color: context.palette.teal,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── New Post Sheet ───────────────────────────────────────────────────────────

class _NewPostSheet extends StatefulWidget {
  const _NewPostSheet({
    required this.imageFile,
    required this.session,
    required this.socialService,
  });

  final File imageFile;
  final VennuzoSessionController session;
  final SocialService socialService;

  @override
  State<_NewPostSheet> createState() => _NewPostSheetState();
}

class _NewPostSheetState extends State<_NewPostSheet> {
  final _captionController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _submitting = true);
    try {
      final repository = context.read<VennuzoRepository>();
      // Pick first available event as default (or empty)
      final events = repository.discoverableEvents;
      final eventId =
          events.isNotEmpty ? events.first.id : 'unknown';

      final post = EventPost(
        postId: widget.socialService.generateId('post'),
        eventId: eventId,
        userId: widget.session.viewer.uid ?? '',
        displayName: widget.session.viewer.displayName,
        userPhotoUrl: widget.session.viewer.photoUrl,
        caption: _captionController.text.trim(),
        timestamp: DateTime.now(),
      );
      await widget.socialService.createPost(post, widget.imageFile);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                color: context.palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('New Post', style: context.text.titleMedium),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              widget.imageFile,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Write a caption…',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _post,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Share Post'),
            ),
          ),
        ],
      ),
    );
  }
}
