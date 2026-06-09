import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../domain/models/event_models.dart';
import '../../domain/models/promotion_models.dart';
import 'audience_import_sheet.dart';

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
  bool _fullscreenAnnouncement = false;
  bool _includeUploadedContacts = true;
  bool _scheduleForLater = true;
  CampaignObjective _objective = CampaignObjective.sellTickets;
  AudienceStrategy _audienceStrategy = AudienceStrategy.recommended;
  OptimizationGoal _optimizationGoal = OptimizationGoal.conversions;
  BidStrategy _bidStrategy = BidStrategy.balanced;
  CreativeMode _creativeMode = CreativeMode.single;
  int _frequencyCap = 2;
  bool _launching = false;
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 4));

  @override
  void initState() {
    super.initState();
    _selectedEventId = widget.initialEvent?.id;
    _nameController = TextEditingController(
      text: widget.initialEvent == null
          ? ''
          : '${widget.initialEvent!.title} launch',
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
    final repository = context.watch<VennuzoRepository>();
    final events = repository.managedEvents;
    final palette = context.palette;
    final effectiveEventId =
        _selectedEventId ??
        widget.initialEvent?.id ??
        (events.isNotEmpty ? events.first.id : null);
    final selectedEvent = effectiveEventId == null
        ? null
        : repository.eventById(effectiveEventId);
    final pushAudience = selectedEvent == null
        ? 0
        : repository.pushAudienceFor(selectedEvent.id);
    final smsAudience = selectedEvent == null
        ? 0
        : repository.smsAudienceFor(selectedEvent.id);
    final placementReach =
        (_featureInDiscover ? 1800 : 0) + (_fullscreenAnnouncement ? 900 : 0);
    final estimatedReach =
        (_sendPush ? pushAudience : 0) +
        (_sendSms ? smsAudience : 0) +
        placementReach;
    final projectedResults = _projectedResults(estimatedReach);
    final budget = double.tryParse(_budgetController.text.trim()) ?? 0;
    final costPerResult = projectedResults > 0
        ? budget / projectedResults
        : 0.0;

    final viewInsets = MediaQuery.of(context).viewInsets;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return SizedBox(
      height: maxHeight,
      child: Container(
        decoration: const BoxDecoration(
          color: VennuzoTheme.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(VennuzoTheme.radiusXl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, viewInsets.bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close campaign composer',
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          Text(
                            'Launch promotion',
                            style: context.text.headlineSmall?.copyWith(
                              fontSize: 26,
                              color: VennuzoTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Build paid outreach around event and place targets, owned audiences, placements, forecasts, and optimization rules.',
                            style: context.text.bodyMedium?.copyWith(
                              color: VennuzoTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _SectionLabel(
                            title: '1. Objective',
                            subtitle: _objectiveDescription(_objective),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: CampaignObjective.values
                                .map(
                                  (objective) => _OptionChip(
                                    label: _objectiveLabel(objective),
                                    icon: _objectiveIcon(objective),
                                    selected: _objective == objective,
                                    onTap: () => _applyObjective(
                                      objective,
                                      selectedEvent,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 20),
                          if (events.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: VennuzoTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: VennuzoTheme.borderBright,
                                ),
                              ),
                              child: Text(
                                'No hosted events are available yet. Create one from the Host tab before launching a campaign.',
                                style: context.text.bodyLarge,
                              ),
                            )
                          else
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
                                final event = value == null
                                    ? null
                                    : repository.eventById(value);
                                if (event != null &&
                                    _nameController.text.trim().isEmpty) {
                                  _nameController.text =
                                      '${event.title} launch';
                                }
                              }),
                              decoration: const InputDecoration(
                                labelText: '2. Campaign target',
                              ),
                            ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _nameController,
                            enabled: events.isNotEmpty,
                            decoration: const InputDecoration(
                              labelText: 'Campaign name',
                              hintText: '72-hour final push',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _budgetController,
                            enabled: events.isNotEmpty,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Budget cap / wallet hold target',
                              hintText: '350',
                              helperText:
                                  'Push and SMS reserve wallet balance before sending.',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          _SectionLabel(
                            title: '3. Audience strategy',
                            subtitle: _audienceStrategyDescription(
                              _audienceStrategy,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: AudienceStrategy.values
                                .map(
                                  (strategy) => _OptionChip(
                                    label: _audienceStrategyLabel(strategy),
                                    icon: Icons.groups_2_outlined,
                                    selected: _audienceStrategy == strategy,
                                    onTap: () =>
                                        _applyAudienceStrategy(strategy),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _messageController,
                            enabled: events.isNotEmpty,
                            minLines: 4,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              labelText: 'Campaign message',
                              hintText: 'What should this campaign say and do?',
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _OptionChip(
                                label: 'Single creative',
                                icon: Icons.touch_app_outlined,
                                selected: _creativeMode == CreativeMode.single,
                                onTap: () => setState(
                                  () => _creativeMode = CreativeMode.single,
                                ),
                              ),
                              _OptionChip(
                                label: 'A/B test',
                                icon: Icons.splitscreen_outlined,
                                selected: _creativeMode == CreativeMode.abTest,
                                onTap: () => setState(
                                  () => _creativeMode = CreativeMode.abTest,
                                ),
                              ),
                              _ActionChipButton(
                                label: 'Draft from objective',
                                icon: Icons.auto_awesome_outlined,
                                onTap: () {
                                  if (selectedEvent == null) return;
                                  setState(() {
                                    _messageController.text = _suggestedMessage(
                                      _objective,
                                      selectedEvent,
                                    );
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '4. Channels',
                            style: context.text.titleLarge?.copyWith(
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: VennuzoTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: VennuzoTheme.borderBright,
                              ),
                            ),
                            child: Text(
                              'Push only goes to Vennuzo users who opted into promotional alerts for this event type. SMS uses consented phones and Hubtel at a GHS 0.04 base cost plus Vennuzo markup.',
                              style: context.text.bodyMedium,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _ChannelToggle(
                                label: 'Push alerts',
                                selected: _sendPush,
                                onTap: () =>
                                    setState(() => _sendPush = !_sendPush),
                              ),
                              _ChannelToggle(
                                label: 'SMS',
                                selected: _sendSms,
                                onTap: () =>
                                    setState(() => _sendSms = !_sendSms),
                              ),
                              _ChannelToggle(
                                label: 'Share link',
                                selected: _shareLink,
                                onTap: () =>
                                    setState(() => _shareLink = !_shareLink),
                              ),
                              _ChannelToggle(
                                label: 'Featured banner',
                                selected: _featureInDiscover,
                                onTap: () => setState(
                                  () =>
                                      _featureInDiscover = !_featureInDiscover,
                                ),
                              ),
                              _ChannelToggle(
                                label: 'Fullscreen announcement',
                                selected: _fullscreenAnnouncement,
                                onTap: () => setState(
                                  () => _fullscreenAnnouncement =
                                      !_fullscreenAnnouncement,
                                ),
                              ),
                            ],
                          ),
                          if (selectedEvent != null) ...[
                            const SizedBox(height: 18),
                            _SectionLabel(
                              title: '5. Optimization',
                              subtitle:
                                  '${_optimizationGoalLabel(_optimizationGoal)} · ${_bidStrategyLabel(_bidStrategy)} · $_frequencyCap touches per person',
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<OptimizationGoal>(
                              initialValue: _optimizationGoal,
                              items: OptimizationGoal.values
                                  .map(
                                    (goal) => DropdownMenuItem(
                                      value: goal,
                                      child: Text(_optimizationGoalLabel(goal)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(
                                () => _optimizationGoal =
                                    value ?? OptimizationGoal.conversions,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Optimization goal',
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<BidStrategy>(
                              initialValue: _bidStrategy,
                              items: BidStrategy.values
                                  .map(
                                    (strategy) => DropdownMenuItem(
                                      value: strategy,
                                      child: Text(_bidStrategyLabel(strategy)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(
                                () => _bidStrategy =
                                    value ?? BidStrategy.balanced,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Bid strategy',
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: _frequencyCap,
                              items: const [1, 2, 3, 5]
                                  .map(
                                    (count) => DropdownMenuItem(
                                      value: count,
                                      child: Text(
                                        '$count touch${count == 1 ? '' : 'es'} per person',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _frequencyCap = value ?? 2),
                              decoration: const InputDecoration(
                                labelText: 'Frequency cap',
                              ),
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _includeUploadedContacts,
                              onChanged: (value) => setState(
                                () => _includeUploadedContacts = value,
                              ),
                              title: const Text('Include uploaded opt-ins'),
                              subtitle: const Text(
                                'Add imported contacts to this event’s RSVP and buyer audience.',
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _importAudience(context),
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Import audience'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: VennuzoTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: VennuzoTheme.borderBright,
                                ),
                              ),
                              child: Wrap(
                                spacing: 14,
                                runSpacing: 14,
                                children: [
                                  _AudienceMetric(
                                    label: 'Opt-in push',
                                    value: repository
                                        .pushAudienceFor(selectedEvent.id)
                                        .toString(),
                                    color: palette.coral,
                                  ),
                                  _AudienceMetric(
                                    label: 'Consented SMS',
                                    value: repository
                                        .smsAudienceFor(selectedEvent.id)
                                        .toString(),
                                    color: palette.teal,
                                  ),
                                  _AudienceMetric(
                                    label: 'Share URL',
                                    value: selectedEvent.allowSharing
                                        ? 'Ready'
                                        : 'Disabled',
                                    color: palette.gold,
                                  ),
                                  _AudienceMetric(
                                    label: 'Premium slots',
                                    value:
                                        (_featureInDiscover ||
                                            _fullscreenAnnouncement)
                                        ? 'Selected'
                                        : 'Optional',
                                    color: palette.ink,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            _ForecastCard(
                              estimatedReach: estimatedReach,
                              projectedResults: projectedResults,
                              costPerResult: costPerResult,
                              optimizationGoal: _optimizationGoal,
                              objective: _objective,
                            ),
                          ],
                          const SizedBox(height: 18),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _scheduleForLater,
                            onChanged: (value) =>
                                setState(() => _scheduleForLater = value),
                            title: const Text('Schedule for later'),
                            subtitle: Text(
                              _scheduleForLater
                                  ? formatPromoTime(_scheduledAt)
                                  : 'Start immediately',
                              style: context.text.bodyMedium,
                            ),
                          ),
                          if (_scheduleForLater)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await _pickDateTime(
                                    context,
                                    initial: _scheduledAt,
                                  );
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
                              onPressed: events.isEmpty || _launching
                                  ? null
                                  : () => _launchCampaign(selectedEvent),
                              child: const Text('Launch campaign'),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _launchCampaign(EventModel? event) {
    if (_launching) return;

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
    if (budget <= 0) {
      _showMessage('Enter a valid budget cap or wallet hold target.');
      return;
    }

    final channels = <PromotionChannel>[
      if (_sendPush) PromotionChannel.push,
      if (_sendSms) PromotionChannel.sms,
      if (_shareLink) PromotionChannel.shareLink,
      if (_featureInDiscover) PromotionChannel.featured,
      if (_fullscreenAnnouncement) PromotionChannel.announcement,
    ];
    if (channels.isEmpty) {
      _showMessage('Select at least one channel.');
      return;
    }

    setState(() => _launching = true);
    try {
      final campaign = context.read<VennuzoRepository>().scheduleCampaign(
        event: event,
        name: name,
        scheduledAt: _scheduleForLater ? _scheduledAt : null,
        channels: channels,
        budget: budget,
        message: message,
        objective: _objective,
        audienceStrategy: _audienceStrategy,
        optimizationGoal: _optimizationGoal,
        bidStrategy: _bidStrategy,
        creativeMode: _creativeMode,
        frequencyCap: _frequencyCap,
        budgetCapGhs: budget,
        audienceSources: <String>[
          'event_rsvps',
          'ticket_buyers',
          if (_includeUploadedContacts) 'uploaded_contacts',
        ],
      );
      Navigator.of(context).pop(campaign);
    } catch (_) {
      if (context.mounted) {
        _showMessage(
          'Could not launch campaign. Check host access and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _launching = false);
      }
    }
  }

  void _applyObjective(CampaignObjective objective, EventModel? event) {
    setState(() {
      _objective = objective;
      _optimizationGoal = switch (objective) {
        CampaignObjective.driveRsvps => OptimizationGoal.rsvps,
        CampaignObjective.fillTables => OptimizationGoal.tables,
        CampaignObjective.boostAwareness => OptimizationGoal.reach,
        CampaignObjective.retargetInterest => OptimizationGoal.clicks,
        CampaignObjective.sellTickets ||
        CampaignObjective.lastCall => OptimizationGoal.conversions,
      };
      _applyAudienceStrategyState(switch (objective) {
        CampaignObjective.sellTickets => AudienceStrategy.highIntent,
        CampaignObjective.driveRsvps => AudienceStrategy.recommended,
        CampaignObjective.fillTables => AudienceStrategy.ownedCrm,
        CampaignObjective.boostAwareness => AudienceStrategy.broadDiscovery,
        CampaignObjective.retargetInterest => AudienceStrategy.retargeting,
        CampaignObjective.lastCall => AudienceStrategy.highIntent,
      });
      if (event != null && _messageController.text.trim().isEmpty) {
        _messageController.text = _suggestedMessage(objective, event);
      }
      if (event != null && _nameController.text.trim().isEmpty) {
        _nameController.text = '${event.title} ${_objectiveLabel(objective)}';
      }
    });
  }

  void _applyAudienceStrategy(AudienceStrategy strategy) {
    setState(() => _applyAudienceStrategyState(strategy));
  }

  void _applyAudienceStrategyState(AudienceStrategy strategy) {
    _audienceStrategy = strategy;
    switch (strategy) {
      case AudienceStrategy.recommended:
        _sendPush = true;
        _sendSms = true;
        _featureInDiscover = false;
        _fullscreenAnnouncement = false;
        _includeUploadedContacts = true;
      case AudienceStrategy.highIntent:
        _sendPush = true;
        _sendSms = true;
        _featureInDiscover = false;
        _fullscreenAnnouncement = false;
        _includeUploadedContacts = false;
      case AudienceStrategy.ownedCrm:
        _sendPush = true;
        _sendSms = true;
        _featureInDiscover = false;
        _fullscreenAnnouncement = false;
        _includeUploadedContacts = true;
      case AudienceStrategy.broadDiscovery:
        _sendPush = true;
        _sendSms = false;
        _featureInDiscover = true;
        _fullscreenAnnouncement = true;
        _includeUploadedContacts = false;
      case AudienceStrategy.retargeting:
        _sendPush = true;
        _sendSms = true;
        _featureInDiscover = false;
        _fullscreenAnnouncement = false;
        _includeUploadedContacts = true;
    }
  }

  int _projectedResults(int estimatedReach) {
    final objectiveRate = switch (_objective) {
      CampaignObjective.sellTickets => 0.055,
      CampaignObjective.driveRsvps => 0.09,
      CampaignObjective.fillTables => 0.028,
      CampaignObjective.boostAwareness => 0.16,
      CampaignObjective.retargetInterest => 0.07,
      CampaignObjective.lastCall => 0.06,
    };
    final strategyRate = switch (_audienceStrategy) {
      AudienceStrategy.recommended => 1.0,
      AudienceStrategy.highIntent => 1.25,
      AudienceStrategy.ownedCrm => 1.12,
      AudienceStrategy.broadDiscovery => 0.72,
      AudienceStrategy.retargeting => 1.18,
    };
    return (estimatedReach * objectiveRate * strategyRate).round();
  }

  Future<void> _importAudience(BuildContext context) async {
    final result = await showAudienceImportSheet(context);
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported ${result.importedCount}; ${result.smsEligibleCount} SMS-eligible, ${result.pushMatchedCount} push-matched.',
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<DateTime?> _pickDateTime(
    BuildContext context, {
    required DateTime initial,
  }) async {
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.titleLarge?.copyWith(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: context.text.bodyMedium?.copyWith(
            color: VennuzoTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      avatar: Icon(icon, size: 16, color: selected ? Colors.white : null),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: VennuzoTheme.primaryStart,
      labelStyle: context.text.bodyMedium?.copyWith(
        color: selected ? Colors.white : VennuzoTheme.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide.none,
      showCheckmark: false,
      backgroundColor: VennuzoTheme.surfaceElevated,
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: VennuzoTheme.surfaceElevated,
      labelStyle: context.text.bodyMedium?.copyWith(
        color: VennuzoTheme.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide.none,
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({
    required this.estimatedReach,
    required this.projectedResults,
    required this.costPerResult,
    required this.optimizationGoal,
    required this.objective,
  });

  final int estimatedReach;
  final int projectedResults;
  final double costPerResult;
  final OptimizationGoal optimizationGoal;
  final CampaignObjective objective;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: VennuzoTheme.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: VennuzoTheme.shadowResting,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Forecast',
            style: context.text.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$projectedResults projected ${_resultLabel(optimizationGoal)}',
            style: context.text.titleLarge?.copyWith(
              color: Colors.white,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ForecastPill(label: 'Reach', value: '$estimatedReach'),
              _ForecastPill(
                label: 'Clicks',
                value: '${(estimatedReach * 0.22).round()}',
              ),
              _ForecastPill(
                label: 'Cost/result',
                value: costPerResult > 0 ? formatMoney(costPerResult) : '—',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _objectiveDescription(objective),
            style: context.text.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastPill extends StatelessWidget {
  const _ForecastPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 94),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.text.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.text.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.74),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: VennuzoTheme.primaryStart,
      labelStyle: context.text.bodyMedium?.copyWith(
        color: selected ? Colors.white : VennuzoTheme.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      showCheckmark: false,
      backgroundColor: VennuzoTheme.surfaceElevated,
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
          Text(value, style: context.text.titleLarge?.copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Text(label, style: context.text.bodyMedium),
        ],
      ),
    );
  }
}

String _objectiveLabel(CampaignObjective objective) => switch (objective) {
  CampaignObjective.sellTickets => 'Sell tickets',
  CampaignObjective.driveRsvps => 'Drive RSVPs',
  CampaignObjective.fillTables => 'Fill tables',
  CampaignObjective.boostAwareness => 'Awareness',
  CampaignObjective.retargetInterest => 'Retarget',
  CampaignObjective.lastCall => 'Last call',
};

String _objectiveDescription(CampaignObjective objective) =>
    switch (objective) {
      CampaignObjective.sellTickets =>
        'Prioritize buyers and high-intent guests closest to checkout.',
      CampaignObjective.driveRsvps =>
        'Move interested guests onto the list for RSVP-based events.',
      CampaignObjective.fillTables =>
        'Push premium packages to previous buyers and VIP contacts.',
      CampaignObjective.boostAwareness =>
        'Use placements and share links to get the event seen by more people.',
      CampaignObjective.retargetInterest =>
        'Re-engage known guests who already interacted with your event.',
      CampaignObjective.lastCall =>
        'Send a time-sensitive final reminder before sales close.',
    };

IconData _objectiveIcon(CampaignObjective objective) => switch (objective) {
  CampaignObjective.sellTickets => Icons.ads_click_outlined,
  CampaignObjective.driveRsvps => Icons.how_to_reg_outlined,
  CampaignObjective.fillTables => Icons.table_bar_outlined,
  CampaignObjective.boostAwareness => Icons.travel_explore_outlined,
  CampaignObjective.retargetInterest => Icons.repeat_rounded,
  CampaignObjective.lastCall => Icons.bolt_rounded,
};

String _audienceStrategyLabel(AudienceStrategy strategy) => switch (strategy) {
  AudienceStrategy.recommended => 'Recommended',
  AudienceStrategy.highIntent => 'High intent',
  AudienceStrategy.ownedCrm => 'Owned CRM',
  AudienceStrategy.broadDiscovery => 'Discovery boost',
  AudienceStrategy.retargeting => 'Retargeting',
};

String _audienceStrategyDescription(AudienceStrategy strategy) =>
    switch (strategy) {
      AudienceStrategy.recommended =>
        'Balanced push, SMS, RSVPs, buyers, and imported contacts.',
      AudienceStrategy.highIntent =>
        'Focus on RSVPs and buyers with direct push/SMS delivery.',
      AudienceStrategy.ownedCrm =>
        'Use imported contacts plus past buyers for VIP and table offers.',
      AudienceStrategy.broadDiscovery =>
        'Use sponsored placements and light direct delivery for visibility.',
      AudienceStrategy.retargeting =>
        'Re-message known guests with a share link and conversion copy.',
    };

String _optimizationGoalLabel(OptimizationGoal goal) => switch (goal) {
  OptimizationGoal.conversions => 'Ticket purchases',
  OptimizationGoal.reach => 'Reach',
  OptimizationGoal.clicks => 'Link clicks',
  OptimizationGoal.rsvps => 'RSVPs',
  OptimizationGoal.tables => 'Table leads',
};

String _bidStrategyLabel(BidStrategy strategy) => switch (strategy) {
  BidStrategy.lowestCost => 'Lowest cost first',
  BidStrategy.balanced => 'Balanced delivery',
  BidStrategy.premiumAttention => 'Premium attention',
};

String _resultLabel(OptimizationGoal goal) => switch (goal) {
  OptimizationGoal.rsvps => 'RSVPs',
  OptimizationGoal.tables => 'table leads',
  OptimizationGoal.reach => 'engagements',
  OptimizationGoal.clicks => 'clicks',
  OptimizationGoal.conversions => 'actions',
};

String _suggestedMessage(CampaignObjective objective, EventModel event) {
  final location = '${event.venue}, ${event.city}'.trim();
  final base =
      '${event.title} is happening ${formatEventWindow(event.startDate, event.endDate)} at $location.';
  return switch (objective) {
    CampaignObjective.driveRsvps =>
      '$base RSVP now so the host can keep your spot ready.',
    CampaignObjective.fillTables =>
      '$base Table packages are available for groups. Reserve before the best spots go.',
    CampaignObjective.boostAwareness =>
      '$base Share it with your people and see what is happening on Vennuzo.',
    CampaignObjective.retargetInterest =>
      '$base You showed interest before. Open the event page and finish your plan today.',
    CampaignObjective.lastCall =>
      '$base Last call: secure your entry before sales close.',
    CampaignObjective.sellTickets =>
      '$base Tickets are available now. Book yours on Vennuzo.',
  };
}
