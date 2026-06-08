import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_extensions.dart';
import '../../core/theme/vennuzo_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/vennuzo_repository.dart';
import '../../data/services/vennuzo_places_service.dart';
import '../../domain/models/place_models.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/place_verification_badge.dart';
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
          actionLabel: 'Claim place',
          onAction: () => _startClaimFlow(context),
        ),
        const SizedBox(height: 14),
        if (places.isEmpty)
          EmptyStateCard(
            title: 'No places assigned',
            icon: Icons.storefront_outlined,
            body:
                'Claim a Google business listing or create a place profile before managing menus and reservations.',
            actionLabel: 'Claim or create a place',
            onAction: () => _startClaimFlow(context),
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
            _VerificationOps(place: selected),
            const SizedBox(height: 22),
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

  Future<void> _startClaimFlow(BuildContext context) async {
    final claimedPlaceId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ClaimPlaceSheet(),
    );
    if (claimedPlaceId == null || !mounted) return;
    setState(() => _selectedPlaceId = claimedPlaceId);
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
    final verified = place.isVerified;
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
              onPressed: verified
                  ? () => _launchPlacePush(context, place)
                  : null,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Plan place push'),
            ),
            if (!verified) ...[
              const SizedBox(height: 8),
              _VerifyToUnlockNote(
                message: 'Verify your place to unlock paid push.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Short inline explainer shown next to a disabled promotional action.
class _VerifyToUnlockNote extends StatelessWidget {
  const _VerifyToUnlockNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(Icons.lock_outline_rounded, size: 16, color: palette.warning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: context.text.bodySmall?.copyWith(color: palette.warning),
          ),
        ),
      ],
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

class _VerificationOps extends StatelessWidget {
  const _VerificationOps({required this.place});

  final PlaceProfile place;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final verified = place.isVerified;
    final pending = place.isVerificationPending;

    final String body;
    if (verified) {
      body =
          'This place is verified. Promotional tools like paid push are unlocked.';
    } else if (pending) {
      body =
          'Verification is in review. We will unlock promotional tools once it is approved.';
    } else {
      body =
          'Verify ownership to unlock promotional tools. Claim the Google listing to verify instantly by phone, or upload a document for free-form places.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Verification', style: context.text.titleMedium),
                ),
                PlaceVerificationBadge(place: place),
              ],
            ),
            const SizedBox(height: 10),
            Text(body, style: context.text.bodyMedium),
            if (!verified && !pending) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _startPhoneVerification(context, place),
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Verify by phone'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _startDocumentVerification(context, place),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload a document'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'No listed phone? Upload a business document (licence, registration, '
                'or a utility bill showing the place name) for our team to review.',
                style: context.text.bodySmall?.copyWith(color: palette.slate),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _startPhoneVerification(
  BuildContext context,
  PlaceProfile place,
) async {
  final outcome = await showModalBottomSheet<_VerifyOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PhoneVerificationSheet(place: place),
  );
  if (outcome == null || !context.mounted) return;
  switch (outcome) {
    case _VerifyOutcome.verified:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${place.name} is now verified.')),
      );
    case _VerifyOutcome.switchToDocument:
      await _startDocumentVerification(context, place);
    case _VerifyOutcome.dismissed:
      break;
  }
}

Future<void> _startDocumentVerification(
  BuildContext context,
  PlaceProfile place,
) async {
  final uid = context.read<VennuzoRepository>().currentUserId;
  if (uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in to submit a verification document.')),
    );
    return;
  }
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DocumentVerificationSheet(place: place, uid: uid),
  );
  if (submitted != true || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${place.name} submitted for review.'),
    ),
  );
}

/// Step 1 of the claim flow: search a Google listing (or create a free-form
/// place) and call `claimOrCreatePlace`. Pops the new place id on success.
class _ClaimPlaceSheet extends StatefulWidget {
  const _ClaimPlaceSheet();

  @override
  State<_ClaimPlaceSheet> createState() => _ClaimPlaceSheetState();
}

class _ClaimPlaceSheetState extends State<_ClaimPlaceSheet> {
  final _searchController = TextEditingController();
  List<VennuzoPlaceSuggestion> _results = const <VennuzoPlaceSuggestion>[];
  bool _searching = false;
  bool _claiming = false;
  String? _error;
  int _searchToken = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    final token = ++_searchToken;
    if (trimmed.length < 2) {
      setState(() {
        _results = const <VennuzoPlaceSuggestion>[];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await VennuzoPlacesService.instance.search(trimmed);
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searching = false;
        _error = error is VennuzoPlacesFailure
            ? error.message
            : 'Search is unavailable right now. Please try again.';
      });
    }
  }

  Future<void> _claim(VennuzoPlaceSuggestion suggestion) async {
    setState(() {
      _claiming = true;
      _error = null;
    });
    try {
      final result = await VennuzoPlacesService.instance.claimOrCreatePlace(
        googlePlaceId: suggestion.placeId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result.placeId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _error = error is VennuzoPlacesFailure
            ? error.message
            : 'We could not claim this place. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Text('Claim a place', style: context.text.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Search Google Business listings. Claiming a listing lets you verify by phone instantly.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search venue name or address',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: _runSearch,
            ),
            const SizedBox(height: 14),
            if (_claiming)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(
                _error!,
                style: context.text.bodyMedium?.copyWith(
                  color: context.palette.error,
                ),
              )
            else if (_results.isEmpty &&
                _searchController.text.trim().length >= 2)
              Text(
                'No matching listings found.',
                style: context.text.bodyMedium,
              )
            else
              for (final suggestion in _results)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(
                      suggestion.title.isEmpty
                          ? suggestion.fullText
                          : suggestion.title,
                    ),
                    subtitle: suggestion.subtitle.isEmpty
                        ? null
                        : Text(suggestion.subtitle),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _claim(suggestion),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Step 2 of the claim flow: send an SMS OTP via `startPlaceVerification`,
/// collect the 6-digit code, and confirm via `confirmPlaceVerification`.
class _PhoneVerificationSheet extends StatefulWidget {
  const _PhoneVerificationSheet({required this.place});

  final PlaceProfile place;

  @override
  State<_PhoneVerificationSheet> createState() =>
      _PhoneVerificationSheetState();
}

class _PhoneVerificationSheetState extends State<_PhoneVerificationSheet> {
  final _codeController = TextEditingController();
  bool _starting = true;
  bool _confirming = false;
  bool _noPhone = false;
  String? _maskedTarget;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
      _noPhone = false;
    });
    try {
      final challenge = await VennuzoPlacesService.instance
          .startPlaceVerification(placeId: widget.place.id);
      if (!mounted) return;
      setState(() {
        _starting = false;
        _maskedTarget = challenge.target;
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is VennuzoPlacesFailure
          ? error.message
          : 'We could not start verification right now. Please try again.';
      setState(() {
        _starting = false;
        // No verifiable phone (free-form places) → show the document path.
        _noPhone = message.toLowerCase().contains('phone');
        _error = message;
      });
    }
  }

  Future<void> _confirm() async {
    final code = _codeController.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the 6-digit code we sent.');
      return;
    }
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      await VennuzoPlacesService.instance.confirmPlaceVerification(
        placeId: widget.place.id,
        code: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_VerifyOutcome.verified);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = error is VennuzoPlacesFailure
            ? error.message
            : 'That code did not match. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Text('Verify by phone', style: context.text.headlineSmall),
            const SizedBox(height: 6),
            Text(widget.place.name, style: context.text.bodyMedium),
            const SizedBox(height: 16),
            if (_starting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_noPhone) ...[
              _InfoCallout(
                icon: Icons.upload_file_outlined,
                message:
                    'This place has no verifiable phone number. Upload a business '
                    'document instead and our team will review it shortly.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: context.text.bodySmall?.copyWith(
                    color: context.palette.slate,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_VerifyOutcome.switchToDocument),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Verify with a document'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_VerifyOutcome.dismissed),
                  child: const Text('Close'),
                ),
              ),
            ] else ...[
              Text(
                _maskedTarget == null || _maskedTarget!.isEmpty
                    ? 'We sent a 6-digit code to the venue phone on file.'
                    : 'We sent a 6-digit code to $_maskedTarget.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'Verification code',
                  counterText: '',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: context.text.bodySmall?.copyWith(
                    color: context.palette.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirming ? null : _confirm,
                  child: _confirming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Text('Confirm code'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _confirming ? null : _start,
                child: const Text('Resend code'),
              ),
              TextButton(
                onPressed: _confirming
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop(_VerifyOutcome.switchToDocument),
                child: const Text('Verify with a document instead'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Result of the phone-verification sheet.
enum _VerifyOutcome { verified, switchToDocument, dismissed }

/// A picked verification document (image bytes + original file name).
class _PickedDocument {
  const _PickedDocument({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

/// Document-review fallback: pick business-document photo(s), upload to
/// `place-verifications/{uid}/{placeId}/...`, then call `submitPlaceVerification`.
/// Pops `true` once the request is submitted for admin review.
class _DocumentVerificationSheet extends StatefulWidget {
  const _DocumentVerificationSheet({required this.place, required this.uid});

  final PlaceProfile place;
  final String uid;

  @override
  State<_DocumentVerificationSheet> createState() =>
      _DocumentVerificationSheetState();
}

class _DocumentVerificationSheetState
    extends State<_DocumentVerificationSheet> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _notesController = TextEditingController();
  final List<_PickedDocument> _documents = <_PickedDocument>[];
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addDocument() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _documents.add(_PickedDocument(bytes: bytes, fileName: picked.name));
      _error = null;
    });
  }

  void _removeDocument(int index) {
    setState(() => _documents.removeAt(index));
  }

  Future<void> _submit() async {
    if (_documents.isEmpty) {
      setState(() => _error = 'Add at least one document photo to continue.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = VennuzoPlacesService.instance;
      final urls = <String>[];
      for (final document in _documents) {
        urls.add(
          await service.uploadVerificationDocument(
            uid: widget.uid,
            placeId: widget.place.id,
            bytes: document.bytes,
            fileName: document.fileName,
          ),
        );
      }
      await service.submitPlaceVerification(
        placeId: widget.place.id,
        documentUrls: urls,
        notes: _notesController.text,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is VennuzoPlacesFailure
            ? error.message
            : 'We could not submit your verification right now. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Container(
      decoration: const BoxDecoration(
        color: VennuzoTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: _submitted
            ? _buildSuccess(context)
            : _buildForm(context),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.verified_outlined,
              color: palette.teal,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Submitted for review',
                style: context.text.headlineSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Submitted for review — we\'ll verify your place shortly. '
          'You\'ll see the badge update to "Verified" once our team approves it.',
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verify with a document', style: context.text.headlineSmall),
        const SizedBox(height: 6),
        Text(widget.place.name, style: context.text.bodyMedium),
        const SizedBox(height: 16),
        _InfoCallout(
          icon: Icons.description_outlined,
          message:
              'Upload a clear photo of a business licence, registration '
              'certificate, or a recent utility bill showing this place\'s name. '
              'Our team reviews submissions and verifies your place.',
        ),
        const SizedBox(height: 16),
        if (_documents.isEmpty)
          OutlinedButton.icon(
            onPressed: _submitting ? null : _addDocument,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add document photo'),
          )
        else ...[
          for (var i = 0; i < _documents.length; i++)
            Card(
              child: ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(
                  _documents[i].fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _submitting ? null : () => _removeDocument(i),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: _submitting ? null : _addDocument,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add another'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          minLines: 2,
          maxLines: 4,
          enabled: !_submitting,
          decoration: const InputDecoration(
            labelText: 'Notes for our team (optional)',
            hintText: 'Anything that helps us verify your place',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: context.text.bodySmall?.copyWith(color: palette.error),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Text('Submit for review'),
          ),
        ),
      ],
    );
  }
}

class _InfoCallout extends StatelessWidget {
  const _InfoCallout({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VennuzoTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VennuzoTheme.borderBright),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.palette.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}
