import 'package:flutter/material.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import 'social_moderation_service.dart';

/// Shared report/block UI for App Store Guideline 1.2 across the social surfaces
/// (posts, comments, reviews, profiles).
///
/// All entry points funnel through [showContentModerationMenu], which presents a
/// "Report" + "Block/Unblock user" action sheet, then handles the report reason
/// picker, the callable invocations, and the confirmation toasts.

final SocialModerationService _moderationService = SocialModerationService();

/// Presents the overflow "⋯" action sheet for a piece of UGC. Does nothing when
/// the viewer authored the content (no self-report / self-block).
///
/// [contentType], [contentId] identify what is being reported. [authorId] is the
/// uid of the content's author (used for both the report payload and blocking).
/// [authorName] is shown in the block confirmation. [isBlocked] controls whether
/// the menu offers "Block" or "Unblock".
Future<void> showContentModerationMenu(
  BuildContext context, {
  required ReportContentType contentType,
  required String contentId,
  required String authorId,
  required String authorName,
  required String currentUserId,
  required bool isBlocked,
}) async {
  // Never allow self-moderation.
  if (authorId.isNotEmpty && authorId == currentUserId) return;
  // Must be signed in to report or block.
  if (currentUserId.isEmpty) {
    _toast(context, 'Sign in to report or block.');
    return;
  }

  final action = await showModalBottomSheet<_ModerationAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report'),
              subtitle: const Text('Flag this content for our team to review'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ModerationAction.report),
            ),
            if (authorId.isNotEmpty)
              ListTile(
                leading: Icon(
                  isBlocked ? Icons.person_outline : Icons.block_outlined,
                  color: isBlocked ? null : sheetContext.palette.coral,
                ),
                title: Text(isBlocked ? 'Unblock user' : 'Block user'),
                subtitle: Text(
                  isBlocked
                      ? 'Show content from this user again'
                      : 'Hide all content from this user',
                ),
                onTap: () => Navigator.of(sheetContext).pop(
                  isBlocked
                      ? _ModerationAction.unblock
                      : _ModerationAction.block,
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case _ModerationAction.report:
      await _handleReport(
        context,
        contentType: contentType,
        contentId: contentId,
        authorId: authorId,
      );
    case _ModerationAction.block:
      await _handleBlock(context, authorId: authorId, authorName: authorName);
    case _ModerationAction.unblock:
      await _handleUnblock(context, authorId: authorId, authorName: authorName);
  }
}

enum _ModerationAction { report, block, unblock }

Future<void> _handleReport(
  BuildContext context, {
  required ReportContentType contentType,
  required String contentId,
  required String authorId,
}) async {
  final reason = await showModalBottomSheet<ReportReason>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportReasonSheet(contentType: contentType),
  );
  if (reason == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await _moderationService.reportContent(
      contentType: contentType,
      contentId: contentId,
      authorId: authorId,
      reason: reason.value,
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Thanks — our team will review this.'),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('We could not send your report right now.'),
      ),
    );
  }
}

Future<void> _handleBlock(
  BuildContext context, {
  required String authorId,
  required String authorName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await _moderationService.blockUser(authorId);
    final who = authorName.trim().isEmpty ? 'this user' : authorName.trim();
    messenger.showSnackBar(
      SnackBar(content: Text('Blocked $who. You will not see their content.')),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not block this user right now.')),
    );
  }
}

Future<void> _handleUnblock(
  BuildContext context, {
  required String authorId,
  required String authorName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await _moderationService.unblockUser(authorId);
    final who = authorName.trim().isEmpty ? 'this user' : authorName.trim();
    messenger.showSnackBar(
      SnackBar(content: Text('Unblocked $who.')),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not unblock this user right now.')),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// A compact overflow icon button that opens the moderation menu. Convenience
/// for screens that want a "⋯" affordance without wiring the call themselves.
class ContentModerationButton extends StatelessWidget {
  const ContentModerationButton({
    super.key,
    required this.contentType,
    required this.contentId,
    required this.authorId,
    required this.authorName,
    required this.currentUserId,
    required this.isBlocked,
    this.color,
    this.tooltip = 'More options',
  });

  final ReportContentType contentType;
  final String contentId;
  final String authorId;
  final String authorName;
  final String currentUserId;
  final bool isBlocked;
  final Color? color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 20,
      icon: Icon(Icons.more_horiz, color: color),
      onPressed: () => showContentModerationMenu(
        context,
        contentType: contentType,
        contentId: contentId,
        authorId: authorId,
        authorName: authorName,
        currentUserId: currentUserId,
        isBlocked: isBlocked,
      ),
    );
  }
}

class _ReportReasonSheet extends StatelessWidget {
  const _ReportReasonSheet({required this.contentType});

  final ReportContentType contentType;

  String get _subjectLabel {
    switch (contentType) {
      case ReportContentType.post:
        return 'this post';
      case ReportContentType.comment:
        return 'this comment';
      case ReportContentType.review:
        return 'this review';
      case ReportContentType.profile:
        return 'this profile';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(VennuzoTheme.radiusXl),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Report content',
                      style: context.text.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close report sheet',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Why are you reporting $_subjectLabel?',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 8),
              for (final reason in ReportReason.all)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop(reason),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
