import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../data/repositories/vennuzo_repository.dart';
import 'social_models.dart';
import 'social_service.dart';

class SocialProfileScreen extends StatelessWidget {
  const SocialProfileScreen({
    super.key,
    required this.profileUserId,
    required this.displayName,
    this.photoUrl,
    this.coverUrl,
  });

  final String profileUserId;
  final String displayName;
  final String? photoUrl;
  final String? coverUrl;

  static final _socialService = SocialService();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<VennuzoSessionController>();
    final currentUserId = session.viewer.uid ?? '';
    final isOwnProfile = currentUserId == profileUserId;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _CoverPhoto(
                coverUrl: coverUrl,
                photoUrl: photoUrl,
                displayName: displayName,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _ProfileHeader(
              profileUserId: profileUserId,
              displayName: displayName,
              photoUrl: photoUrl,
              currentUserId: currentUserId,
              isOwnProfile: isOwnProfile,
              socialService: _socialService,
            ),
          ),
          SliverToBoxAdapter(
            child: _PostsSection(
              profileUserId: profileUserId,
              socialService: _socialService,
            ),
          ),
          SliverToBoxAdapter(
            child: _AttendedEventsSection(
              profileUserId: profileUserId,
            ),
          ),
          SliverToBoxAdapter(
            child: _SavedEventsSection(
              profileUserId: profileUserId,
              socialService: _socialService,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _CoverPhoto extends StatelessWidget {
  const _CoverPhoto({
    this.coverUrl,
    this.photoUrl,
    required this.displayName,
  });

  final String? coverUrl;
  final String? photoUrl;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cover
        if (coverUrl != null && coverUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: coverUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                Container(color: palette.darkSurface),
            errorWidget: (_, __, ___) => _DefaultCover(palette: palette),
          )
        else
          _DefaultCover(palette: palette),
        // Scrim
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0x88000000)],
            ),
          ),
        ),
        // Avatar overlay at bottom-left
        Positioned(
          bottom: 16,
          left: 20,
          child: CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white,
            foregroundImage:
                photoUrl != null ? NetworkImage(photoUrl!) : null,
            child: photoUrl == null
                ? Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: palette.teal,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _DefaultCover extends StatelessWidget {
  const _DefaultCover({required this.palette});
  final VennuzoPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.teal, palette.coral],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profileUserId,
    required this.displayName,
    this.photoUrl,
    required this.currentUserId,
    required this.isOwnProfile,
    required this.socialService,
  });

  final String profileUserId;
  final String displayName;
  final String? photoUrl;
  final String currentUserId;
  final bool isOwnProfile;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: context.text.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _CountBadge(
                          label: 'Followers',
                          stream: socialService
                              .getFollowerCount(profileUserId),
                        ),
                        const SizedBox(width: 20),
                        _CountBadge(
                          label: 'Following',
                          stream: socialService
                              .getFollowingCount(profileUserId),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isOwnProfile && currentUserId.isNotEmpty)
                _FollowButton(
                  followerId: currentUserId,
                  targetId: profileUserId,
                  socialService: socialService,
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label, required this.stream});
  final String label;
  final Stream<int> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Column(
          children: [
            Text(
              '$count',
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.palette.slate,
                fontSize: 12,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.followerId,
    required this.targetId,
    required this.socialService,
  });

  final String followerId;
  final String targetId;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: socialService.isFollowing(followerId, targetId),
      builder: (context, snapshot) {
        final following = snapshot.data ?? false;
        return ElevatedButton(
          onPressed: () {
            if (following) {
              socialService.unfollowUser(followerId, targetId);
            } else {
              socialService.followUser(followerId, targetId);
            }
          },
          style: following
              ? ElevatedButton.styleFrom(
                  backgroundColor:
                      context.palette.border,
                  foregroundColor: context.palette.ink,
                )
              : null,
          child: Text(following ? 'Unfollow' : 'Follow'),
        );
      },
    );
  }
}

class _PostsSection extends StatelessWidget {
  const _PostsSection({
    required this.profileUserId,
    required this.socialService,
  });

  final String profileUserId;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Text('Posts', style: context.text.titleMedium),
        ),
        StreamBuilder<List<EventPost>>(
          stream: socialService.getUserPosts(profileUserId),
          builder: (context, snapshot) {
            final posts = snapshot.data ?? [];
            if (posts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'No posts yet.',
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.palette.slate),
                ),
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final photoUrl = posts[index].photoUrl;
                if (photoUrl == null || photoUrl.isEmpty) {
                  return Container(color: const Color(0xFF1F2937));
                }
                return CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: const Color(0xFF1F2937)),
                  errorWidget: (_, __, ___) =>
                      Container(color: const Color(0xFF1F2937)),
                );
              },
            );
          },
        ),
        const Divider(height: 32),
      ],
    );
  }
}

class _AttendedEventsSection extends StatelessWidget {
  const _AttendedEventsSection({required this.profileUserId});
  final String profileUserId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    // Show events the user has RSVP'd or bought tickets for
    final events = repository.discoverableEvents
        .where((e) => repository.hasRsvp(e.id))
        .take(6)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Events Attended', style: context.text.titleMedium),
        ),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              'No events yet.',
              style: context.text.bodyMedium
                  ?.copyWith(color: context.palette.slate),
            ),
          )
        else
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final event = events[index];
                return Chip(
                  avatar: const Icon(
                    Icons.event,
                    size: 16,
                  ),
                  label: Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        const Divider(height: 32),
      ],
    );
  }
}

class _SavedEventsSection extends StatelessWidget {
  const _SavedEventsSection({
    required this.profileUserId,
    required this.socialService,
  });

  final String profileUserId;
  final SocialService socialService;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Saved Events', style: context.text.titleMedium),
        ),
        StreamBuilder<List<String>>(
          stream: socialService.getSavedEvents(profileUserId),
          builder: (context, snapshot) {
            final eventIds = snapshot.data ?? [];
            if (eventIds.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'No saved events.',
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.palette.slate),
                ),
              );
            }
            final events = eventIds
                .map((id) => repository.eventById(id))
                .where((e) => e != null)
                .take(6)
                .toList();
            return SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: events.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final event = events[index]!;
                  return Chip(
                    avatar: const Icon(Icons.bookmark, size: 16),
                    label: Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
