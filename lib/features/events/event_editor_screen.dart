import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/eventora_repository.dart';
import '../../domain/models/event_models.dart';

class EventEditorScreen extends StatefulWidget {
  const EventEditorScreen({
    super.key,
    this.existingEvent,
  });

  final EventModel? existingEvent;

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _venueController;
  late final TextEditingController _cityController;
  late final TextEditingController _djsController;
  late final TextEditingController _mcsController;
  late final TextEditingController _performersController;
  late final TextEditingController _tagsController;

  late DateTime _startDate;
  DateTime? _endDate;
  late EventVisibility _visibility;
  late EventMood _mood;
  late bool _ticketingEnabled;
  late bool _requireTicket;
  late bool _sendPush;
  late bool _sendSms;
  late bool _allowSharing;
  late List<TicketTier> _tiers;
  late RecurrenceFrequency _recurrenceFrequency;
  late int _recurrenceInterval;
  late RecurrenceEndType _recurrenceEndType;
  DateTime? _recurrenceEndDate;
  int? _recurrenceOccurrences;

  @override
  void initState() {
    super.initState();
    final event = widget.existingEvent;
    _titleController = TextEditingController(text: event?.title ?? '');
    _descriptionController = TextEditingController(text: event?.description ?? '');
    _venueController = TextEditingController(text: event?.venue ?? '');
    _cityController = TextEditingController(text: event?.city ?? 'Accra');
    _djsController = TextEditingController(text: event?.djs ?? '');
    _mcsController = TextEditingController(text: event?.mcs ?? '');
    _performersController = TextEditingController(text: event?.performers ?? '');
    _tagsController = TextEditingController(text: event?.tags.join(', ') ?? '');

    _startDate = event?.startDate ?? DateTime.now().add(const Duration(days: 7, hours: 3));
    _endDate = event?.endDate;
    _visibility = event?.visibility ?? EventVisibility.publicEvent;
    _mood = event?.mood ?? EventMood.night;
    _ticketingEnabled = event?.ticketing.enabled ?? true;
    _requireTicket = event?.ticketing.requireTicket ?? true;
    _sendPush = event?.sendPushNotification ?? true;
    _sendSms = event?.sendSmsNotification ?? true;
    _allowSharing = event?.allowSharing ?? true;
    _tiers = List<TicketTier>.from(event?.ticketing.tiers ?? const []);
    _recurrenceFrequency = event?.recurrence.frequency ?? RecurrenceFrequency.none;
    _recurrenceInterval = event?.recurrence.interval ?? 1;
    _recurrenceEndType = event?.recurrence.endType ?? RecurrenceEndType.never;
    _recurrenceEndDate = event?.recurrence.endDate;
    _recurrenceOccurrences = event?.recurrence.endAfterOccurrences;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _cityController.dispose();
    _djsController.dispose();
    _mcsController.dispose();
    _performersController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existingEvent != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit event' : 'Create event'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _EditorIntro(isEditing: _isEditing),
          const SizedBox(height: 24),
          _SectionCard(
            title: 'Core details',
            body: Column(
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Event title'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Schedule',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateButton(
                  label: 'Start time',
                  value: formatEventWindow(_startDate, null),
                  onTap: () => _pickStartDate(context),
                ),
                const SizedBox(height: 12),
                _DateButton(
                  label: _endDate == null ? 'Add end time' : 'End time',
                  value: _endDate == null ? 'Not set' : formatEventWindow(_endDate!, null),
                  onTap: () => _pickEndDate(context),
                  onClear: _endDate == null ? null : () => setState(() => _endDate = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Location & lineup',
            body: Column(
              children: [
                TextField(
                  controller: _venueController,
                  decoration: const InputDecoration(labelText: 'Venue'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _cityController,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _performersController,
                  decoration: const InputDecoration(labelText: 'Performers'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _djsController,
                  decoration: const InputDecoration(labelText: 'DJs'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _mcsController,
                  decoration: const InputDecoration(labelText: 'Hosts / MCs'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Visibility & vibe',
            body: Column(
              children: [
                DropdownButtonFormField<EventVisibility>(
                  initialValue: _visibility,
                  decoration: const InputDecoration(labelText: 'Visibility'),
                  items: EventVisibility.values
                      .map(
                        (visibility) => DropdownMenuItem(
                          value: visibility,
                          child: Text(
                            visibility == EventVisibility.publicEvent ? 'Public' : 'Private',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _visibility = value ?? _visibility),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Mood', style: context.text.titleLarge?.copyWith(fontSize: 20)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: EventMood.values
                      .map(
                        (mood) => ChoiceChip(
                          label: Text(_moodLabel(mood)),
                          selected: _mood == mood,
                          onSelected: (_) => setState(() => _mood = mood),
                          showCheckmark: false,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Ticketing',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _ticketingEnabled,
                  onChanged: (value) => setState(() => _ticketingEnabled = value),
                  title: const Text('Enable ticketing'),
                  subtitle: const Text('Turn on tiers, reservations, and ticket issuance.'),
                ),
                if (_ticketingEnabled) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _requireTicket,
                    onChanged: (value) => setState(() => _requireTicket = value),
                    title: const Text('Require ticket for entry'),
                    subtitle: const Text('Turn off if you want RSVPs plus optional support tickets.'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _editTier(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add tier'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_tiers.isEmpty)
                    const Text('No ticket tiers yet.')
                  else
                    ..._tiers.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TierSummaryCard(
                          tier: entry.value,
                          onEdit: () => _editTier(context, existing: entry.value),
                          onDelete: () => setState(() => _tiers.removeAt(entry.key)),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Recurrence',
            body: Column(
              children: [
                DropdownButtonFormField<RecurrenceFrequency>(
                  initialValue: _recurrenceFrequency,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: RecurrenceFrequency.values
                      .map(
                        (frequency) => DropdownMenuItem(
                          value: frequency,
                          child: Text(_frequencyLabel(frequency)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _recurrenceFrequency = value ?? RecurrenceFrequency.none;
                      if (_recurrenceFrequency == RecurrenceFrequency.none) {
                        _recurrenceEndType = RecurrenceEndType.never;
                      }
                    });
                  },
                ),
                if (_recurrenceFrequency != RecurrenceFrequency.none) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: _recurrenceInterval,
                    decoration: const InputDecoration(labelText: 'Repeat every'),
                    items: const [1, 2, 4]
                        .map(
                          (interval) => DropdownMenuItem(
                            value: interval,
                            child: Text('$interval ${interval == 1 ? 'cycle' : 'cycles'}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _recurrenceInterval = value ?? 1),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<RecurrenceEndType>(
                    initialValue: _recurrenceEndType,
                    decoration: const InputDecoration(labelText: 'Ends'),
                    items: RecurrenceEndType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(_endTypeLabel(type)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _recurrenceEndType = value ?? RecurrenceEndType.never),
                  ),
                  if (_recurrenceEndType == RecurrenceEndType.onDate) ...[
                    const SizedBox(height: 12),
                    _DateButton(
                      label: 'Recurrence end date',
                      value: _recurrenceEndDate == null
                          ? 'Choose end date'
                          : formatShortDate(_recurrenceEndDate!),
                      onTap: () => _pickRecurrenceEndDate(context),
                      onClear: _recurrenceEndDate == null
                          ? null
                          : () => setState(() => _recurrenceEndDate = null),
                    ),
                  ],
                  if (_recurrenceEndType == RecurrenceEndType.afterOccurrences) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _recurrenceOccurrences?.toString() ?? '',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Number of occurrences',
                      ),
                      onChanged: (value) => _recurrenceOccurrences = int.tryParse(value),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Distribution settings',
            body: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _sendPush,
                  onChanged: (value) => setState(() => _sendPush = value),
                  title: const Text('Send push notification on publish'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _sendSms,
                  onChanged: (value) => setState(() => _sendSms = value),
                  title: const Text('Include SMS audience flow'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _allowSharing,
                  onChanged: (value) => setState(() => _allowSharing = value),
                  title: const Text('Allow share links'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Tags',
            body: TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Comma-separated tags',
                hintText: 'Music, Featured, Community',
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              child: Text(_isEditing ? 'Save changes' : 'Create event'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStartDate(BuildContext context) async {
    final picked = await _pickDateTime(context, initial: _startDate);
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(hours: 3));
        }
      });
    }
  }

  Future<void> _pickEndDate(BuildContext context) async {
    final initial = _endDate ?? _startDate.add(const Duration(hours: 3));
    final picked = await _pickDateTime(context, initial: initial);
    if (picked != null && mounted) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _pickRecurrenceEndDate(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _recurrenceEndDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: _startDate.add(const Duration(days: 365 * 3)),
    );
    if (selected != null && mounted) {
      setState(() => _recurrenceEndDate = selected);
    }
  }

  Future<DateTime?> _pickDateTime(BuildContext context, {required DateTime initial}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
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

  Future<void> _editTier(BuildContext context, {TicketTier? existing}) async {
    final tier = await showDialog<TicketTier>(
      context: context,
      builder: (_) => _TierEditorDialog(existing: existing),
    );
    if (tier == null || !mounted) return;

    setState(() {
      final index = _tiers.indexWhere((value) => value.tierId == tier.tierId);
      if (index == -1) {
        _tiers = [..._tiers, tier];
      } else {
        _tiers[index] = tier;
      }
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final venue = _venueController.text.trim();
    final city = _cityController.text.trim();

    if (title.isEmpty || description.isEmpty || venue.isEmpty || city.isEmpty) {
      _showMessage('Complete the title, description, venue, and city.');
      return;
    }
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      _showMessage('End time must be after the start time.');
      return;
    }
    if (_ticketingEnabled && _tiers.isEmpty) {
      _showMessage('Add at least one ticket tier or turn ticketing off.');
      return;
    }
    if (_recurrenceFrequency != RecurrenceFrequency.none &&
        _recurrenceEndType == RecurrenceEndType.onDate &&
        _recurrenceEndDate == null) {
      _showMessage('Choose a recurrence end date.');
      return;
    }
    if (_recurrenceFrequency != RecurrenceFrequency.none &&
        _recurrenceEndType == RecurrenceEndType.afterOccurrences &&
        (_recurrenceOccurrences == null || _recurrenceOccurrences! <= 0)) {
      _showMessage('Enter how many times the event should repeat.');
      return;
    }

    final draft = EventDraft(
      title: title,
      description: description,
      venue: venue,
      city: city,
      startDate: _startDate,
      endDate: _endDate,
      visibility: _visibility,
      ticketing: EventTicketing(
        enabled: _ticketingEnabled,
        requireTicket: _ticketingEnabled ? _requireTicket : false,
        currency: 'GHS',
        tiers: _ticketingEnabled ? _tiers : const [],
      ),
      recurrence: RecurrenceRule(
        frequency: _recurrenceFrequency,
        interval: _recurrenceFrequency == RecurrenceFrequency.none ? 1 : _recurrenceInterval,
        endType: _recurrenceFrequency == RecurrenceFrequency.none ? RecurrenceEndType.never : _recurrenceEndType,
        endDate: _recurrenceFrequency == RecurrenceFrequency.none ? null : _recurrenceEndDate,
        endAfterOccurrences:
            _recurrenceFrequency == RecurrenceFrequency.none ? null : _recurrenceOccurrences,
      ),
      sendPushNotification: _sendPush,
      sendSmsNotification: _sendSms,
      allowSharing: _allowSharing,
      djs: _djsController.text.trim(),
      mcs: _mcsController.text.trim(),
      performers: _performersController.text.trim(),
      mood: _mood,
      tags: _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
    );

    final repository = context.read<EventoraRepository>();
    if (_isEditing) {
      repository.updateEvent(widget.existingEvent!.id, draft);
    } else {
      repository.createEvent(draft);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isEditing ? 'Event updated.' : 'Event created.')),
    );
    Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _moodLabel(EventMood mood) => switch (mood) {
        EventMood.night => 'Night',
        EventMood.sunrise => 'Sunrise',
        EventMood.electric => 'Electric',
        EventMood.garden => 'Garden',
      };

  String _frequencyLabel(RecurrenceFrequency frequency) => switch (frequency) {
        RecurrenceFrequency.none => 'No recurrence',
        RecurrenceFrequency.daily => 'Daily',
        RecurrenceFrequency.weekly => 'Weekly',
        RecurrenceFrequency.monthly => 'Monthly',
      };

  String _endTypeLabel(RecurrenceEndType endType) => switch (endType) {
        RecurrenceEndType.never => 'Never',
        RecurrenceEndType.onDate => 'On date',
        RecurrenceEndType.afterOccurrences => 'After occurrences',
      };
}

class _EditorIntro extends StatelessWidget {
  const _EditorIntro({required this.isEditing});

  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withValues(alpha: 0.88),
        border: Border.all(color: const Color(0x1410212A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditing ? 'Refine your event' : 'Build a new event',
            style: context.text.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            'This editor keeps the original app model intact: visibility, ticket tiers, recurrence, push and SMS settings, and sharing rules.',
            style: context.text.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.body,
  });

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleLarge?.copyWith(fontSize: 21)),
            const SizedBox(height: 16),
            body,
          ],
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.bodyMedium),
                const SizedBox(height: 6),
                Text(value, style: context.text.titleLarge?.copyWith(fontSize: 18)),
              ],
            ),
          ),
          TextButton(onPressed: onTap, child: const Text('Choose')),
          if (onClear != null)
            TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
  }
}

class _TierSummaryCard extends StatelessWidget {
  const _TierSummaryCard({
    required this.tier,
    required this.onEdit,
    required this.onDelete,
  });

  final TicketTier tier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tier.name, style: context.text.titleLarge?.copyWith(fontSize: 19)),
              ),
              Text(formatMoney(tier.price), style: context.text.bodyLarge),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tier.description?.isNotEmpty == true ? tier.description! : 'No description yet.',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text('Capacity ${tier.maxQuantity} • Sold ${tier.sold}', style: context.text.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
              OutlinedButton(onPressed: onDelete, child: const Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierEditorDialog extends StatefulWidget {
  const _TierEditorDialog({this.existing});

  final TicketTier? existing;

  @override
  State<_TierEditorDialog> createState() => _TierEditorDialogState();
}

class _TierEditorDialogState extends State<_TierEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _capacityController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _priceController = TextEditingController(text: widget.existing?.price.toStringAsFixed(0) ?? '0');
    _capacityController = TextEditingController(text: widget.existing?.maxQuantity.toString() ?? '100');
    _descriptionController = TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _capacityController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add ticket tier' : 'Edit ticket tier'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Tier name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Capacity'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final price = double.tryParse(_priceController.text.trim());
            final capacity = int.tryParse(_capacityController.text.trim());

            if (name.isEmpty || price == null || capacity == null || capacity <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Complete the tier details.')),
              );
              return;
            }

            Navigator.of(context).pop(
              TicketTier(
                tierId: widget.existing?.tierId ?? 'tier_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                price: price,
                maxQuantity: capacity,
                sold: widget.existing?.sold ?? 0,
                description: _descriptionController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
