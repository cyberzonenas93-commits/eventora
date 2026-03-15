import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';

Future<PromotionCampaign?> showCampaignComposerSheet(
  BuildContext context, {
  EventModel? initialEvent,
}) {
  return showModalBottomSheet<PromotionCampaign>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _CampaignComposerSheet(initialEvent: initialEvent),
  );
}

class _CampaignComposerSheet extends StatefulWidget {
  const _CampaignComposerSheet({this.initialEvent});

  final EventModel? initialEvent;

  @override
  State<_CampaignComposerSheet> createState() => _CampaignComposerSheetState();
}

class _CampaignComposerSheetState extends State<_CampaignComposerSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _budgetController;
  late final TextEditingController _messageController;

  String? _selectedEventId;
  bool _sendPush = true;
  bool _sendSms = true;
  bool _shareLink = true;
  bool _featureInDiscover = false;
  bool _scheduleForLater = true;
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 4));

  @override
  void initState() {
    super.initState();
    _selectedEventId = widget.initialEvent?.id;
    _nameController = TextEditingController(
      text: widget.initialEvent == null ? '' : '${widget.initialEvent!.title} launch',
    );
    _budgetController = TextEditingController(text: '350');
    _messageController = TextEditingController(
      text: widget.initialEvent == null
          ? ''
          : 'Push urgency, remind warm audiences, and route every click into the share link.',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<EventoraRepository>();
    final events = repository.managedEvents;
    final palette = context.palette;
    final effectiveEventId = _selectedEventId ?? widget.initialEvent?.id ?? (events.isNotEmpty ? events.first.id : null);
    final selectedEvent = effectiveEventId == null ? null : repository.eventById(effectiveEventId);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDF8F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                'Launch promotion',
                style: context.text.headlineSmall?.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 8),
              Text(
                'Build a push, SMS, and share-link campaign around one event.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: effectiveEventId,
                items: events
                    .map(
                      (event) => DropdownMenuItem<String>(
                        value: event.id,
                        child: Text(event.title),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _selectedEventId = value;
                  final event = value == null ? null : repository.eventById(value);
                  if (event != null && _nameController.text.trim().isEmpty) {
                    _nameController.text = '${event.title} launch';
                  }
                }),
                decoration: const InputDecoration(labelText: 'Event'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Campaign name',
                  hintText: '72-hour final push',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _budgetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Budget',
                  hintText: '350',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _messageController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Campaign message',
                  hintText: 'What should this campaign say and do?',
                ),
              ),
              const SizedBox(height: 18),
              Text('Channels', style: context.text.titleLarge?.copyWith(fontSize: 20)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ChannelToggle(
                    label: 'Push',
                    selected: _sendPush,
                    onTap: () => setState(() => _sendPush = !_sendPush),
                  ),
                  _ChannelToggle(
                    label: 'SMS',
                    selected: _sendSms,
                    onTap: () => setState(() => _sendSms = !_sendSms),
                  ),
                  _ChannelToggle(
                    label: 'Share link',
                    selected: _shareLink,
                    onTap: () => setState(() => _shareLink = !_shareLink),
                  ),
                  _ChannelToggle(
                    label: 'Featured',
                    selected: _featureInDiscover,
                    onTap: () => setState(() => _featureInDiscover = !_featureInDiscover),
                  ),
                ],
              ),
              if (selectedEvent != null) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0x1410212A)),
                  ),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _AudienceMetric(
                        label: 'Push audience',
                        value: repository.pushAudienceFor(selectedEvent.id).toString(),
                        color: palette.coral,
                      ),
                      _AudienceMetric(
                        label: 'SMS audience',
                        value: repository.smsAudienceFor(selectedEvent.id).toString(),
                        color: palette.teal,
                      ),
                      _AudienceMetric(
                        label: 'Share URL',
                        value: selectedEvent.allowSharing ? 'Ready' : 'Disabled',
                        color: palette.gold,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _scheduleForLater,
                onChanged: (value) => setState(() => _scheduleForLater = value),
                title: const Text('Schedule for later'),
                subtitle: Text(
                  _scheduleForLater ? formatPromoTime(_scheduledAt) : 'Start immediately',
                  style: context.text.bodyMedium,
                ),
              ),
              if (_scheduleForLater)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _pickDateTime(context, initial: _scheduledAt);
                      if (picked != null && mounted) {
                        setState(() => _scheduledAt = picked);
                      }
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text(formatPromoTime(_scheduledAt)),
                  ),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final event = selectedEvent;
                    final name = _nameController.text.trim();
                    final message = _messageController.text.trim();
                    final budget = double.tryParse(_budgetController.text.trim()) ?? 0;

                    if (event == null) {
                      _showMessage('Pick an event before launching a campaign.');
                      return;
                    }
                    if (name.isEmpty || message.isEmpty) {
                      _showMessage('Give the campaign a name and a message.');
                      return;
                    }

                    final channels = <PromotionChannel>[
                      if (_sendPush) PromotionChannel.push,
                      if (_sendSms) PromotionChannel.sms,
                      if (_shareLink) PromotionChannel.shareLink,
                      if (_featureInDiscover) PromotionChannel.featured,
                    ];
                    if (channels.isEmpty) {
                      _showMessage('Select at least one channel.');
                      return;
                    }

                    final campaign = context.read<EventoraRepository>().scheduleCampaign(
                          event: event,
                          name: name,
                          scheduledAt: _scheduleForLater ? _scheduledAt : null,
                          channels: channels,
                          budget: budget,
                          message: message,
                        );
                    Navigator.of(context).pop(campaign);
                  },
                  child: const Text('Launch campaign'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<DateTime?> _pickDateTime(BuildContext context, {required DateTime initial}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !context.mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

class _ChannelToggle extends StatelessWidget {
  const _ChannelToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: palette.ink,
      labelStyle: context.text.bodyMedium?.copyWith(
        color: selected ? Colors.white : palette.ink,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      showCheckmark: false,
      backgroundColor: Colors.white,
    );
  }
}

class _AudienceMetric extends StatelessWidget {
  const _AudienceMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.text.titleLarge?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(label, style: context.text.bodyMedium),
        ],
      ),
    );
  }
}
