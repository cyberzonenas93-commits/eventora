import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/repositories/vennuzo_repository.dart';
import 'saved_events_screen.dart';
import 'social_models.dart';
import 'social_moderation_service.dart';
import 'social_moderation_ui.dart';
import 'social_post_image.dart';
import 'social_service.dart';

class SocialFeedScreen extends StatefulWidget {
  const SocialFeedScreen({super.key});

  @override
  State<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends State<SocialFeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  SocialService? _socialService;
  final SocialModerationService _moderationService = SocialModerationService();

  SocialService get _service => _socialService ??= SocialService();

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
    final socialService = session.firebaseEnabled ? _service : null;

    return Scaffold(
      body: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: TabBar(
              controller: _tabController,
              labelColor: palette.teal,
              unselectedLabelColor: palette.slate,
              indicatorColor: palette.teal,
              tabs: const [
                Tab(child: _AccessibleTabLabel(label: 'Feed')),
                Tab(child: _AccessibleTabLabel(label: 'Explore')),
                Tab(child: _AccessibleTabLabel(label: 'Saved')),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: socialService == null
                  ? const [
                      _OfflineSocialTab(),
                      _OfflineSocialTab(),
                      _OfflineSocialTab(),
                    ]
                  : [
                      _FeedTab(
                        socialService: socialService,
                        moderationService: _moderationService,
                        currentUserId: session.viewer.uid ?? '',
                      ),
                      _ExploreTab(
                        socialService: socialService,
                        moderationService: _moderationService,
                        currentUserId: session.viewer.uid ?? '',
                      ),
                      SavedEventsScreen(userId: session.viewer.uid ?? ''),
                    ],
            ),
          ),
        ],
      ),
      floatingActionButton: session.isGuest || socialService == null
          ? null
          : FloatingActionButton(
              onPressed: () => _openNewPostFlow(context, session),
              tooltip: 'New Post',
              child: const Icon(Icons.add_a_photo_outlined),
            ),
    );
  }

  Future<void> _openNewPostFlow(
    BuildContext context,
    VennuzoSessionController session,
  ) async {
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
        socialService: _service,
      ),
    );
  }
}

class _OfflineSocialTab extends StatelessWidget {
  const _OfflineSocialTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Social features are unavailable in offline preview mode.',
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(
            color: context.palette.slate,
          ),
        ),
      ),
    );
  }
}

class _AccessibleTabLabel extends StatelessWidget {
  const _AccessibleTabLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label tab',
      child: ExcludeSemantics(child: Text(label)),
    );
  }
}

// ─── Feed Tab ────────────────────────────────────────────────────────────────

class _FeedTab extends StatelessWidget {
  const _FeedTab({
    required this.socialService,
    required this.moderationService,
    required this.currentUserId,
  });
  final SocialService socialService;
  final SocialModerationService moderationService;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: moderationService.blockedUserIds(currentUserId),
      builder: (context, blockedSnap) {
        final blocked = blockedSnap.data ?? const <String>{};
        return _buildFeed(context, blocked);
      },
    );
  }

  Widget _buildFeed(BuildContext context, Set<String> blocked) {
    return StreamBuilder<List<EventPost>>(
      stream: socialService.getRecentFeed(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final posts = (snapshot.data ?? [])
            .where((p) => !blocked.contains(p.userId))
            .toList();
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
                  Text('Nothing here yet', style: context.text.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Posts from events you follow will appear here.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.palette.slate,
                    ),
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
              moderationService: moderationService,
              currentUserId: currentUserId,
            );
          },
        );
      },
    );
  }
}

// ─── Explore Tab ─────────────────────────────────────────────────────────────

class _ExploreTab extends StatelessWidget {
  const _ExploreTab({
    required this.socialService,
    required this.moderationService,
    required this.currentUserId,
  });
  final SocialService socialService;
  final SocialModerationService moderationService;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: moderationService.blockedUserIds(currentUserId),
      builder: (context, blockedSnap) {
        final blocked = blockedSnap.data ?? const <String>{};
        return _buildGrid(context, blocked);
      },
    );
  }

  Widget _buildGrid(BuildContext context, Set<String> blocked) {
    return StreamBuilder<List<EventPost>>(
      stream: socialService.getRecentFeed(limit: 60),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final posts = (snapshot.data ?? [])
            .where((p) => !blocked.contains(p.userId))
            .toList();
        if (posts.isEmpty) {
          return Center(
            child: Text(
              'No posts to explore yet.',
              style: context.text.bodyMedium?.copyWith(
                color: context.palette.slate,
              ),
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
            return Semantics(
              button: true,
              label: 'Open post by ${post.displayName}',
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _SinglePostScreen(
                      post: post,
                      socialService: socialService,
                      moderationService: moderationService,
                      currentUserId: currentUserId,
                    ),
                  ),
                ),
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? SocialPostImage(imageUrl: photoUrl)
                    : Container(
                        color: const Color(0xFF1F2937),
                        child: const Icon(
                          Icons.image_outlined,
                          color: Colors.white38,
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Feed Post Card ───────────────────────────────────────────────────────────

class _FeedPostCard extends StatefulWidget {
  const _FeedPostCard({
    required this.post,
    required this.socialService,
    required this.moderationService,
    required this.currentUserId,
  });

  final EventPost post;
  final SocialService socialService;
  final SocialModerationService moderationService;
  final String currentUserId;

  @override
  State<_FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<_FeedPostCard> {
  bool _shareCopied = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final repository = context.watch<VennuzoRepository>();
    final post = widget.post;
    final socialService = widget.socialService;
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
                      ? CachedNetworkImageProvider(post.userPhotoUrl!)
                      : null,
                  child: post.userPhotoUrl == null
                      ? const Icon(
                          Icons.person,
                          color: Colors.white70,
                          size: 18,
                        )
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
                            horizontal: 8,
                            vertical: 2,
                          ),
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
                if (post.userId.isNotEmpty &&
                    post.userId != widget.currentUserId)
                  ContentModerationButton(
                    contentType: ReportContentType.post,
                    contentId: post.postId,
                    authorId: post.userId,
                    authorName: post.displayName,
                    currentUserId: widget.currentUserId,
                    isBlocked: false,
                    color: Colors.white54,
                  ),
              ],
            ),
          ),
          // Photo
          if (photoUrl != null && photoUrl.isNotEmpty)
            SocialPostImage(
              imageUrl: photoUrl,
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
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
                Semantics(
                  button: true,
                  label: 'View comments, ${post.commentCount}',
                  child: ExcludeSemantics(
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _SinglePostScreen(
                            post: post,
                            socialService: socialService,
                            moderationService: widget.moderationService,
                            currentUserId: widget.currentUserId,
                          ),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      icon: const Icon(Icons.comment_outlined, size: 20),
                      label: Text('${post.commentCount}'),
                    ),
                  ),
                ),
                const Spacer(),
                if (_shareCopied)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      'Copied',
                      style: TextStyle(
                        color: context.palette.teal,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: _shareCopied ? 'Post copied' : 'Share post',
                  onPressed: () =>
                      _sharePost(context, eventTitle: event?.title),
                  icon: Icon(
                    _shareCopied
                        ? Icons.check_circle_outline
                        : Icons.share_outlined,
                    color: _shareCopied ? context.palette.teal : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sharePost(BuildContext context, {String? eventTitle}) async {
    final post = widget.post;
    final caption = post.caption.trim();
    final message = [
      if (eventTitle != null && eventTitle.isNotEmpty)
        'Post from $eventTitle on Vennuzo',
      if (caption.isNotEmpty) caption,
      if ((post.photoUrl ?? '').isNotEmpty) post.photoUrl!,
    ].join('\n\n');
    final fallback = message.isEmpty ? 'Post from Vennuzo' : message;

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: fallback));
    if (mounted) setState(() => _shareCopied = true);
    messenger.showSnackBar(const SnackBar(content: Text('Post text copied.')));

    try {
      await SharePlus.instance.share(
        ShareParams(text: fallback, subject: eventTitle ?? 'Vennuzo post'),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Post text copied. Sharing is unavailable right now.'),
        ),
      );
    }
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
      return Semantics(
        button: true,
        enabled: false,
        label: 'Sign in to like post, $likeCount likes',
        child: ExcludeSemantics(
          child: TextButton.icon(
            onPressed: null,
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            icon: const Icon(Icons.favorite_outline, size: 20),
            label: Text('$likeCount'),
          ),
        ),
      );
    }
    return StreamBuilder<bool>(
      stream: socialService.hasUserLikedPost(postId, userId),
      builder: (context, snapshot) {
        final liked = snapshot.data ?? false;
        return Semantics(
          button: true,
          label: liked
              ? 'Unlike post, $likeCount likes'
              : 'Like post, $likeCount likes',
          child: ExcludeSemantics(
            child: TextButton.icon(
              onPressed: () {
                if (liked) {
                  socialService.unlikePost(postId, userId);
                } else {
                  socialService.likePost(postId, userId);
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: liked ? context.palette.coral : Colors.white70,
              ),
              icon: Icon(
                liked ? Icons.favorite : Icons.favorite_outline,
                size: 20,
              ),
              label: Text('$likeCount'),
            ),
          ),
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
    required this.moderationService,
    required this.currentUserId,
  });

  final EventPost post;
  final SocialService socialService;
  final SocialModerationService moderationService;
  final String currentUserId;

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
        actions: [
          if (widget.post.userId.isNotEmpty &&
              widget.post.userId != widget.currentUserId)
            ContentModerationButton(
              contentType: ReportContentType.post,
              contentId: widget.post.postId,
              authorId: widget.post.userId,
              authorName: widget.post.displayName,
              currentUserId: widget.currentUserId,
              isBlocked: false,
              color: Colors.white,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                if (photoUrl != null && photoUrl.isNotEmpty)
                  SocialPostImage(
                    imageUrl: photoUrl,
                    width: double.infinity,
                    height: 300,
                    fit: BoxFit.cover,
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
                StreamBuilder<Set<String>>(
                  stream: widget.moderationService.blockedUserIds(
                    widget.currentUserId,
                  ),
                  builder: (context, blockedSnap) {
                    final blocked = blockedSnap.data ?? const <String>{};
                    return StreamBuilder<List<PostComment>>(
                      stream: widget.socialService.getComments(
                        widget.post.postId,
                      ),
                      builder: (context, snapshot) {
                        final comments = (snapshot.data ?? [])
                            .where((c) => !blocked.contains(c.userId))
                            .toList();
                        return Column(
                          children: comments.map((c) {
                            final canModerate =
                                c.userId.isNotEmpty &&
                                c.userId != widget.currentUserId;
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 14,
                                foregroundImage: c.photoUrl != null
                                    ? CachedNetworkImageProvider(c.photoUrl!)
                                    : null,
                                child: c.photoUrl == null
                                    ? const Icon(
                                        Icons.person,
                                        size: 14,
                                        color: Colors.white,
                                      )
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
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: canModerate
                                  ? ContentModerationButton(
                                      contentType: ReportContentType.comment,
                                      contentId: c.commentId,
                                      authorId: c.userId,
                                      authorName: c.displayName,
                                      currentUserId: widget.currentUserId,
                                      isBlocked: false,
                                      color: Colors.white38,
                                    )
                                  : null,
                            );
                          }).toList(),
                        );
                      },
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
                    tooltip: 'Send comment',
                    onPressed: _submitting
                        ? null
                        : () => _submitComment(
                            session.viewer.uid ?? '',
                            session.viewer.displayName,
                          ),
                    icon: Icon(Icons.send, color: context.palette.teal),
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
  String? _selectedEventId;
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
      final events = repository.discoverableEvents;
      final eventId =
          _selectedEventId ?? (events.isNotEmpty ? events.first.id : 'unknown');

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final repository = context.watch<VennuzoRepository>();
    final events = repository.discoverableEvents;
    final selectedEventId =
        _selectedEventId ?? (events.isNotEmpty ? events.first.id : null);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: context.palette.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text('New Post', style: context.text.titleMedium),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Close new post composer',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            widget.imageFile,
                            height: 220,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedEventId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Event'),
                          items: [
                            for (final event in events)
                              DropdownMenuItem<String>(
                                value: event.id,
                                child: Text(
                                  event.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedEventId = value),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _captionController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Write a caption…',
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _post,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(_submitting ? 'Publishing...' : 'Share Post'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
