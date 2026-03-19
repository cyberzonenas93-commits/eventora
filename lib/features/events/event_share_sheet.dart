import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/theme_extensions.dart';
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

  @override
  void initState() {
    super.initState();
    _shareLinkFuture = VennuzoShareLinkService.createEventLink(
      event: widget.event,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBF7),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
            final isLoading =
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
                        color: const Color(0x1A10212A),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Share event',
                    style: context.text.headlineSmall?.copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share the same Vennuzo landing page used by campaigns, SMS reminders, and premium placements.',
                    style: context.text.bodyMedium,
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
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isLoading
                              ? null
                              : () => _shareLink(context, shareLink: shareLink),
                          icon: const Icon(Icons.share_outlined),
                          label: Text(isLoading ? 'Preparing...' : 'Share now'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isLoading
                              ? null
                              : () => _copyLink(context, shareLink: shareLink),
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Copy link'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Share link',
                    style: context.text.titleLarge?.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x1610212A)),
                    ),
                    child: Text(
                      shareLink,
                      style: context.text.bodyLarge?.copyWith(
                        color: palette.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0x1610212A)),
                      ),
                      child: QrImageView(
                        data: shareLink,
                        version: QrVersions.auto,
                        size: 196,
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
                      'Scan to open the Vennuzo share landing page.',
                      style: context.text.bodyMedium?.copyWith(
                        color: palette.slate,
                      ),
                    ),
                  ),
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
    await SharePlus.instance.share(
      ShareParams(
        text: '${widget.event.title}\n\n$shareLink',
        subject: widget.event.title,
      ),
    );
  }

  Future<void> _copyLink(
    BuildContext context, {
    required String shareLink,
  }) async {
    await Clipboard.setData(ClipboardData(text: shareLink));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Share link copied.')));
  }
}
