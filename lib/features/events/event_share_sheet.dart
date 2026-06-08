import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/services/vennuzo_share_link_service.dart';
import '../../domain/models/event_models.dart';

Future<void> showEventShareSheet(
  BuildContext context, {
  required EventModel event,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EventShareSheet(event: event),
  );
}

class _EventShareSheet extends StatefulWidget {
  const _EventShareSheet({required this.event});

  final EventModel event;

  @override
  State<_EventShareSheet> createState() => _EventShareSheetState();
}

class _EventShareSheetState extends State<_EventShareSheet> {
  late final Future<String> _shareLinkFuture;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _shareLinkFuture = VennuzoShareLinkService.createEventLink(
      event: widget.event,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: VennuzoTheme.surface,
        borderRadius: BorderRadius.vertical(
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
        child: FutureBuilder<String>(
          future: _shareLinkFuture,
          builder: (context, snapshot) {
            final shareLink =
                snapshot.data ??
                VennuzoShareLinkService.fallbackEventLink(widget.event.id);
            final isPreparing =
                snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: VennuzoTheme.textTertiary.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Share event',
                          style: context.text.headlineSmall?.copyWith(
                            fontSize: 26,
                            color: VennuzoTheme.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close share sheet',
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share the same Vennuzo landing page used by campaigns, SMS reminders, and premium placements.',
                    style: context.text.bodyMedium?.copyWith(
                      color: VennuzoTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.event.mood.colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.event.title,
                          style: context.text.headlineSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.event.venue}, ${widget.event.city}',
                          style: context.text.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatEventWindow(
                            widget.event.startDate,
                            widget.event.endDate,
                          ),
                          style: context.text.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.84),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stackButtons = constraints.maxWidth < 340;
                      final shareButton = ElevatedButton.icon(
                        onPressed: () =>
                            _shareLink(context, shareLink: shareLink),
                        icon: const Icon(Icons.share_outlined),
                        label: Text(
                          isPreparing ? 'Share fallback' : 'Share now',
                        ),
                      );
                      final copyButton = OutlinedButton.icon(
                        onPressed: () =>
                            _copyLink(context, shareLink: shareLink),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy link'),
                      );

                      if (stackButtons) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            shareButton,
                            const SizedBox(height: 10),
                            copyButton,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: shareButton),
                          const SizedBox(width: 12),
                          Expanded(child: copyButton),
                        ],
                      );
                    },
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _copied
                        ? Padding(
                            key: const ValueKey('copied'),
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: VennuzoTheme.success,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Share link copied.',
                                  style: context.text.bodyMedium?.copyWith(
                                    color: VennuzoTheme.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Share link',
                    style: context.text.titleLarge?.copyWith(
                      fontSize: 18,
                      color: VennuzoTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: VennuzoTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: VennuzoTheme.borderBright),
                    ),
                    child: Text(
                      shareLink,
                      style: context.text.bodyLarge?.copyWith(
                        color: VennuzoTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: VennuzoTheme.borderBright),
                      ),
                      child: QrImageView(
                        data: shareLink,
                        version: QrVersions.auto,
                        size: 164,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF121E31),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF121E31),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      isPreparing
                          ? 'Generating the tracked link. The fallback link is ready now.'
                          : 'Scan to open the Vennuzo share landing page.',
                      style: context.text.bodyMedium?.copyWith(
                        color: VennuzoTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _shareLink(
    BuildContext context, {
    required String shareLink,
  }) async {
    unawaited(_openNativeShare(context, shareLink: shareLink));
    await Clipboard.setData(ClipboardData(text: shareLink));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  Future<void> _openNativeShare(
    BuildContext context, {
    required String shareLink,
  }) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: '${widget.event.title}\n\n$shareLink',
          subject: widget.event.title,
        ),
      );
      if (!context.mounted) {
        return;
      }
      switch (result.status) {
        case ShareResultStatus.success:
          return;
        case ShareResultStatus.dismissed:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Share cancelled. Link copied.')),
          );
          return;
        case ShareResultStatus.unavailable:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sharing is unavailable here. Link copied.'),
            ),
          );
          return;
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sharing did not open. Link copied.')),
      );
    }
  }

  Future<void> _copyLink(
    BuildContext context, {
    required String shareLink,
  }) async {
    await Clipboard.setData(ClipboardData(text: shareLink));
    if (!context.mounted) {
      return;
    }
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }
}
