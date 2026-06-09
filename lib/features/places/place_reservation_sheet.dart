part of 'places_screen.dart';

Future<void> _reserve(BuildContext context, PlaceProfile place) async {
  final repository = context.read<VennuzoRepository>();
  final result = await showModalBottomSheet<PlaceReservationRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReservationSheet(place: place),
  );
  if (result == null || !context.mounted) return;
  repository.createPlaceReservation(result);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Reservation request sent to ${_placeDisplayName(place)}.'),
    ),
  );
}

class _ReservationSheet extends StatefulWidget {
  const _ReservationSheet({required this.place});

  final PlaceProfile place;

  @override
  State<_ReservationSheet> createState() => _ReservationSheetState();
}

class _ReservationSheetState extends State<_ReservationSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  PlaceReservationType _type = PlaceReservationType.table;
  int _partySize = 4;
  DateTime _requestedAt = DateTime.now().add(const Duration(days: 1, hours: 3));
  final Set<String> _selectedMenuItems = <String>{};

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final placeName = _placeDisplayName(widget.place);
    final featuredItems = repository
        .menuItemsForPlace(widget.place.id)
        .where((item) => item.featured && item.isAvailable)
        .toList();
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Container(
      decoration: const BoxDecoration(
        color: VennuzoTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reserve $placeName', style: context.text.headlineSmall),
            const SizedBox(height: 16),
            DropdownButtonFormField<PlaceReservationType>(
              initialValue: _type,
              items: PlaceReservationType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(_typeLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
              decoration: const InputDecoration(labelText: 'Reservation type'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _partySize,
              items: [1, 2, 3, 4, 5, 6, 8, 10, 12]
                  .map(
                    (count) => DropdownMenuItem(
                      value: count,
                      child: Text('$count guests'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _partySize = value ?? 4),
              decoration: const InputDecoration(labelText: 'Party size'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _requestedAt,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (picked == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_requestedAt),
                );
                if (time == null) return;
                setState(() {
                  _requestedAt = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    time.hour,
                    time.minute,
                  );
                });
              },
              icon: const Icon(Icons.schedule_outlined),
              label: Text(formatPromoTime(_requestedAt)),
            ),
            if (featuredItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Add package interest', style: context.text.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: featuredItems
                    .map(
                      (item) => FilterChip(
                        label: Text(
                          '${item.name} · ${formatMoney(item.price)}',
                        ),
                        selected: _selectedMenuItems.contains(item.id),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _selectedMenuItems.add(item.id);
                          } else {
                            _selectedMenuItems.remove(item.id);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final name = _name.text.trim();
                  final phone = _phone.text.trim();
                  if (name.isEmpty || phone.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Add a name and phone number.'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).pop(
                    PlaceReservationRequest(
                      placeId: widget.place.id,
                      placeName: placeName,
                      reservationType: _type,
                      guestName: name,
                      phone: phone,
                      partySize: _partySize,
                      requestedAt: _requestedAt,
                      note: _note.text.trim(),
                      selectedMenuItemIds: _selectedMenuItems.toList(),
                    ),
                  );
                },
                child: const Text('Send reservation request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _typeLabel(PlaceReservationType type) => switch (type) {
  PlaceReservationType.table => 'Table',
  PlaceReservationType.vipTable => 'VIP table',
  PlaceReservationType.guestlist => 'Guestlist',
  PlaceReservationType.bottleService => 'Bottle service',
  PlaceReservationType.privateBooking => 'Private booking',
};
