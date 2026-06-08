import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../domain/models/place_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/section_heading.dart';

class PlaceManagementScreen extends StatefulWidget {
  const PlaceManagementScreen({super.key});

  @override
  State<PlaceManagementScreen> createState() => _PlaceManagementScreenState();
}

class _PlaceManagementScreenState extends State<PlaceManagementScreen> {
  String? _selectedPlaceId;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final places = repository.places;
    final selected = _selectedPlaceId == null
        ? (places.isEmpty ? null : places.first)
        : repository.placeById(_selectedPlaceId!);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
      children: [
        SectionHeading(
          title: 'Place manager',
          subtitle: 'Menus, reservations, subscribers, and paid push.',
        ),
        const SizedBox(height: 14),
        if (places.isEmpty)
          const EmptyStateCard(
            title: 'No places assigned',
            icon: Icons.storefront_outlined,
            body:
                'Claim or create a place profile before managing menus and reservations.',
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: selected?.id,
            items: places
                .map(
                  (place) => DropdownMenuItem(
                    value: place.id,
                    child: Text(place.name),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedPlaceId = value),
            decoration: const InputDecoration(labelText: 'Active place'),
          ),
          if (selected != null) ...[
            const SizedBox(height: 18),
            _PlaceOpsSummary(place: selected),
            const SizedBox(height: 22),
            _MenuOps(place: selected),
            const SizedBox(height: 22),
            _ReservationOps(place: selected),
            const SizedBox(height: 22),
            _PushOps(place: selected),
          ],
        ],
      ],
    );
  }
}

class _PlaceOpsSummary extends StatelessWidget {
  const _PlaceOpsSummary({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(label: 'Subscribers', value: '${place.subscriberCount}'),
            _Metric(label: 'Rating', value: place.rating.toStringAsFixed(1)),
            _Metric(label: 'Reviews', value: '${place.reviewCount}'),
            _Metric(label: 'Featured', value: place.featured ? 'Yes' : 'No'),
          ],
        ),
      ),
    );
  }
}

class _MenuOps extends StatelessWidget {
  const _MenuOps({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final sections = repository.menuSectionsForPlace(place.id);
    final items = repository.menuItemsForPlace(place.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Menu',
          subtitle: '${items.length} public items',
          actionLabel: sections.isEmpty ? null : 'Add item',
          onAction: sections.isEmpty
              ? null
              : () => _addMenuItem(context, place, sections.first),
        ),
        const SizedBox(height: 12),
        if (sections.isEmpty)
          const EmptyStateCard(
            title: 'No menu sections',
            icon: Icons.restaurant_menu_outlined,
            body: 'Create sections from the backend to start publishing items.',
          )
        else
          for (final item in items.take(8))
            Card(
              child: ListTile(
                leading: Icon(
                  item.featured
                      ? Icons.star_rounded
                      : Icons.restaurant_menu_rounded,
                  color: item.featured
                      ? context.palette.gold
                      : context.palette.teal,
                ),
                title: Text(item.name),
                subtitle: Text(item.status.name),
                trailing: Text(formatMoney(item.price)),
              ),
            ),
      ],
    );
  }
}

class _ReservationOps extends StatelessWidget {
  const _ReservationOps({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<VennuzoRepository>();
    final reservations = repository.reservationsForPlace(place.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Reservations',
          subtitle: '${reservations.length} requests',
        ),
        const SizedBox(height: 12),
        if (reservations.isEmpty)
          const EmptyStateCard(
            title: 'No reservations yet',
            icon: Icons.event_seat_outlined,
            body: 'Incoming table and guestlist requests will appear here.',
          )
        else
          for (final reservation in reservations.take(12))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reservation.guestName,
                      style: context.text.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${reservation.partySize} guests · ${formatPromoTime(reservation.requestedAt)}',
                    ),
                    if (reservation.note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(reservation.note),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusButton(
                          label: 'Confirm',
                          onTap: () => repository.updatePlaceReservationStatus(
                            reservation.id,
                            PlaceReservationStatus.confirmed,
                          ),
                        ),
                        _StatusButton(
                          label: 'Change',
                          onTap: () => repository.updatePlaceReservationStatus(
                            reservation.id,
                            PlaceReservationStatus.changeRequested,
                          ),
                        ),
                        _StatusButton(
                          label: 'Cancel',
                          onTap: () => repository.updatePlaceReservationStatus(
                            reservation.id,
                            PlaceReservationStatus.cancelled,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _PushOps extends StatelessWidget {
  const _PushOps({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    final estimatedCost = place.subscriberCount * 0.02;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paid push', style: context.text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Send subscriber push for events, menu specials, reservation availability, or announcements. Estimated subscriber reach: ${place.subscriberCount}.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Metric(label: 'Unit fee', value: 'GHS 0.02'),
                _Metric(label: 'Estimate', value: formatMoney(estimatedCost)),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _launchPlacePush(context, place),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Plan place push'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VennuzoTheme.borderBright),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.text.titleMedium),
          const SizedBox(height: 2),
          Text(label, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onTap, child: Text(label));
  }
}

Future<void> _addMenuItem(
  BuildContext context,
  PlaceProfile place,
  PlaceMenuSection section,
) async {
  final name = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  var featured = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Add item to ${section.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: featured,
              onChanged: (value) => setState(() => featured = value),
              title: const Text('Featured item'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (result != true || !context.mounted) return;
  context.read<VennuzoRepository>().createPlaceMenuItem(
    placeId: place.id,
    sectionId: section.id,
    name: name.text.trim(),
    description: description.text.trim(),
    price: double.tryParse(price.text.trim()) ?? 0,
    featured: featured,
  );
}

Future<void> _launchPlacePush(BuildContext context, PlaceProfile place) async {
  final title = TextEditingController(text: place.name);
  final message = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Send place push'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Push title'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: message,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Message'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Send'),
        ),
      ],
    ),
  );
  if (result != true || !context.mounted) return;
  final body = message.text.trim();
  if (body.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a message before sending.')),
    );
    return;
  }
  context.read<VennuzoRepository>().launchPlacePushCampaign(
    place: place,
    title: title.text.trim().isEmpty ? place.name : title.text.trim(),
    message: body,
  );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Place push queued for ${place.name}.')),
  );
}
