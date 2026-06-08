import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/vennuzo_session_controller.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../domain/models/creator_models.dart';
import '../../domain/models/event_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/event_card.dart';
import '../../widgets/section_heading.dart';
import '../account/auth_prompt_sheet.dart';
import '../events/event_detail_screen.dart';
import '../social/social_models.dart';
import '../social/social_service.dart';

class CreatorProfileScreen extends StatelessWidget {
  const CreatorProfileScreen({super.key, required this.creatorId});

  final String creatorId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final session = context.watch<VennuzoSessionController>();
    final profile = repository.creatorProfileFor(creatorId);
    final events = repository.eventsForCreator(creatorId);
    final photos = repository.photosForCreator(creatorId);
    final isOwnProfile = session.viewer.uid == creatorId;
    final isFollowing = repository.isFollowingCreator(creatorId);

    return Scaffold(
      appBar: AppBar(title: Text(profile.displayName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          _CreatorHero(
            profile: profile,
            isOwnProfile: isOwnProfile,
            isFollowing: isFollowing,
            onFollow: () => _toggleFollow(context, profile),
            onEdit: isOwnProfile ? () => _editProfile(context, profile) : null,
            onUpload: isOwnProfile
                ? () => _uploadEventPhoto(context, profile)
                : null,
          ),
          const SizedBox(height: 24),
          SectionHeading(title: 'Upcoming events', subtitle: null),
          const SizedBox(height: 14),
          if (events.isEmpty)
            const EmptyStateCard(
              title: 'No public events yet',
              body: 'Follow this creator to see new events when they publish.',
              icon: Icons.event_busy_outlined,
            )
          else
            ...events.map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: EventCard(
                  event: event,
                  compact: true,
                  onTap: () => _openEvent(context, event),
                ),
              ),
            ),
          const SizedBox(height: 22),
          SectionHeading(title: 'Event photos', subtitle: null),
          const SizedBox(height: 14),
          if (photos.isEmpty)
            EmptyStateCard(
              title: isOwnProfile
                  ? 'Add photos from your events'
                  : 'No event photos yet',
              body: isOwnProfile
                  ? 'Upload venue shots, previous editions, guest moments, and production previews.'
                  : null,
              icon: Icons.photo_library_outlined,
              actionLabel: isOwnProfile ? 'Upload photo' : null,
              onAction: isOwnProfile
                  ? () => _uploadEventPhoto(context, profile)
                  : null,
            )
          else
            _CreatorPhotoGrid(photos: photos),
        ],
      ),
    );
  }

  Future<void> _toggleFollow(
    BuildContext context,
    CreatorProfile profile,
  ) async {
    final session = context.read<VennuzoSessionController>();
    if (session.isGuest) {
      final authenticated = await showAuthPromptSheet(
        context,
        title: 'Sign in to follow creators',
        body: 'Following creators keeps their events in your Explore feed.',
      );
      if (!context.mounted || !authenticated) {
        return;
      }
    }

    final repository = context.read<VennuzoRepository>();
    if (repository.isFollowingCreator(profile.creatorId)) {
      repository.unfollowCreator(profile.creatorId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unfollowed ${profile.displayName}.')),
      );
    } else {
      repository.followCreator(profile.creatorId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Following ${profile.displayName}.')),
      );
    }
  }

  Future<void> _editProfile(
    BuildContext context,
    CreatorProfile profile,
  ) async {
    final updated = await showModalBottomSheet<CreatorProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditCreatorProfileSheet(profile: profile),
    );
    if (updated == null || !context.mounted) {
      return;
    }
    context.read<VennuzoRepository>().saveCreatorProfile(updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Creator profile updated.')));
  }

  Future<void> _uploadEventPhoto(
    BuildContext context,
    CreatorProfile profile,
  ) async {
    final repository = context.read<VennuzoRepository>();
    final events = repository.managedEvents
        .where((event) => event.createdBy == profile.creatorId)
        .toList();
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an event before adding photos.')),
      );
      return;
    }

    final photo = await showModalBottomSheet<_CreatorPhotoDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UploadCreatorPhotoSheet(events: events),
    );
    if (photo == null || !context.mounted) {
      return;
    }
    final session = context.read<VennuzoSessionController>();
    var imageUrl = photo.imagePath;
    if (session.firebaseEnabled) {
      try {
        final uploadedPost = await SocialService().createPost(
          EventPost(
            postId: 'creator_${DateTime.now().millisecondsSinceEpoch}',
            eventId: photo.event.id,
            userId: profile.creatorId,
            displayName: profile.displayName,
            userPhotoUrl: session.viewer.photoUrl,
            caption: photo.caption,
            timestamp: DateTime.now(),
          ),
          File(photo.imagePath),
        );
        imageUrl = uploadedPost.photoUrl ?? imageUrl;
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Photo upload failed: $error')));
        return;
      }
    }
    if (!context.mounted) {
      return;
    }
    repository.addCreatorEventPhoto(
      creatorId: profile.creatorId,
      event: photo.event,
      imageUrl: imageUrl,
      caption: photo.caption,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Event photo added.')));
  }

  void _openEvent(BuildContext context, EventModel event) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(eventId: event.id),
      ),
    );
  }
}

class _CreatorHero extends StatelessWidget {
  const _CreatorHero({
    required this.profile,
    required this.isOwnProfile,
    required this.isFollowing,
    required this.onFollow,
    required this.onEdit,
    required this.onUpload,
  });

  final CreatorProfile profile;
  final bool isOwnProfile;
  final bool isFollowing;
  final VoidCallback onFollow;
  final VoidCallback? onEdit;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VennuzoTheme.surface,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        border: Border.all(color: VennuzoTheme.borderSubtle),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 190,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CreatorImage(
                    source: profile.coverUrl ?? profile.avatarUrl,
                    fallbackIcon: Icons.auto_awesome_outlined,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.04),
                          Colors.black.withValues(alpha: 0.62),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: Colors.white,
                          child: ClipOval(
                            child: SizedBox(
                              width: 62,
                              height: 62,
                              child: _CreatorImage(
                                source: profile.avatarUrl,
                                fallbackText: profile.displayName,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            profile.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.headlineSmall?.copyWith(
                              color: Colors.white,
                              height: 1.05,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (profile.bio.trim().isNotEmpty) ...[
                    Text(profile.bio, style: context.text.bodyLarge),
                    const SizedBox(height: 16),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _CreatorStat(
                        label: 'Followers',
                        value: '${profile.followerCount}',
                      ),
                      _CreatorStat(
                        label: 'Events',
                        value: '${profile.eventCount}',
                      ),
                      _CreatorStat(
                        label: 'Photos',
                        value: '${profile.photoCount}',
                      ),
                      _CreatorStat(label: 'City', value: profile.city),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (isOwnProfile)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: onUpload,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Add event photo'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit profile'),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onFollow,
                        icon: Icon(
                          isFollowing
                              ? Icons.check_circle_rounded
                              : Icons.person_add_alt_1_outlined,
                        ),
                        label: Text(
                          isFollowing ? 'Following' : 'Follow creator',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatorStat extends StatelessWidget {
  const _CreatorStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.text.titleSmall?.copyWith(
              color: VennuzoTheme.textPrimary,
            ),
          ),
          Text(
            label,
            style: context.text.bodySmall?.copyWith(
              color: VennuzoTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatorPhotoGrid extends StatelessWidget {
  const _CreatorPhotoGrid({required this.photos});

  final List<CreatorEventPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final photo = photos[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CreatorImage(source: photo.imageUrl),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.70),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      photo.eventTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (photo.caption.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        photo.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      formatShortDate(photo.createdAt),
                      style: context.text.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.76),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CreatorImage extends StatelessWidget {
  const _CreatorImage({
    this.source,
    this.fallbackIcon = Icons.photo_outlined,
    this.fallbackText,
  });

  final String? source;
  final IconData fallbackIcon;
  final String? fallbackText;

  @override
  Widget build(BuildContext context) {
    final value = source?.trim();
    if (value == null || value.isEmpty) {
      return _ImageFallback(icon: fallbackIcon, fallbackText: fallbackText);
    }
    if (value.startsWith('assets/')) {
      return Image.asset(
        value,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _ImageFallback(icon: fallbackIcon, fallbackText: fallbackText),
      );
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _ImageFallback(icon: fallbackIcon, fallbackText: fallbackText),
      );
    }
    return Image.file(
      File(value),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          _ImageFallback(icon: fallbackIcon, fallbackText: fallbackText),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.icon, this.fallbackText});

  final IconData icon;
  final String? fallbackText;

  @override
  Widget build(BuildContext context) {
    final label = fallbackText?.trim();
    return Container(
      color: context.palette.canvas,
      child: Center(
        child: label == null || label.isEmpty
            ? Icon(icon, color: VennuzoTheme.textSecondary)
            : Text(
                label.characters.first.toUpperCase(),
                style: context.text.headlineSmall?.copyWith(
                  color: VennuzoTheme.primaryStart,
                ),
              ),
      ),
    );
  }
}

class _EditCreatorProfileSheet extends StatefulWidget {
  const _EditCreatorProfileSheet({required this.profile});

  final CreatorProfile profile;

  @override
  State<_EditCreatorProfileSheet> createState() =>
      _EditCreatorProfileSheetState();
}

class _EditCreatorProfileSheetState extends State<_EditCreatorProfileSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _cityController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _cityController = TextEditingController(text: widget.profile.city);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Creator profile', style: context.text.titleLarge),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bioController,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Bio'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _cityController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'City'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              child: const Text('Save profile'),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a creator display name.')),
      );
      return;
    }
    Navigator.of(context).pop(
      widget.profile.copyWith(
        displayName: name,
        bio: _bioController.text.trim(),
        city: _cityController.text.trim().isEmpty
            ? 'Accra'
            : _cityController.text.trim(),
      ),
    );
  }
}

class _UploadCreatorPhotoSheet extends StatefulWidget {
  const _UploadCreatorPhotoSheet({required this.events});

  final List<EventModel> events;

  @override
  State<_UploadCreatorPhotoSheet> createState() =>
      _UploadCreatorPhotoSheetState();
}

class _UploadCreatorPhotoSheetState extends State<_UploadCreatorPhotoSheet> {
  final _captionController = TextEditingController();
  final _picker = ImagePicker();
  late EventModel _selectedEvent;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _selectedEvent = widget.events.first;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add event photo', style: context.text.titleLarge),
          const SizedBox(height: 18),
          DropdownButtonFormField<EventModel>(
            initialValue: _selectedEvent,
            decoration: const InputDecoration(labelText: 'Event'),
            items: widget.events
                .map(
                  (event) => DropdownMenuItem<EventModel>(
                    value: event,
                    child: Text(event.title),
                  ),
                )
                .toList(),
            onChanged: (event) =>
                setState(() => _selectedEvent = event ?? _selectedEvent),
          ),
          const SizedBox(height: 14),
          if (_imagePath != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
              child: SizedBox(
                height: 180,
                width: double.infinity,
                child: _CreatorImage(source: _imagePath),
              ),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_imagePath == null ? 'Choose photo' : 'Change photo'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _captionController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Caption',
              hintText: 'What should people know about this photo?',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _imagePath == null ? null : _save,
              child: const Text('Add photo'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _imagePath = picked.path);
  }

  void _save() {
    final imagePath = _imagePath;
    if (imagePath == null) {
      return;
    }
    Navigator.of(context).pop(
      _CreatorPhotoDraft(
        event: _selectedEvent,
        imagePath: imagePath,
        caption: _captionController.text.trim(),
      ),
    );
  }
}

class _CreatorPhotoDraft {
  const _CreatorPhotoDraft({
    required this.event,
    required this.imagePath,
    required this.caption,
  });

  final EventModel event;
  final String imagePath;
  final String caption;
}
