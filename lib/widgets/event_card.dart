import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/utils/formatters.dart';
import '../domain/models/event_models.dart';

class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    this.onTap,
    this.footer,
    this.compact = false,
  });

  final EventModel event;
  final VoidCallback? onTap;
  final Widget? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final minPrice = event.ticketing.minimumPrice;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: compact ? 116 : 158,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: event.mood.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Pill(
                          label: event.isPrivate ? 'Private' : 'Public',
                          color: Colors.white.withValues(alpha: 0.18),
                          foreground: Colors.white,
                        ),
                        if (event.recurrence.isRecurring)
                          const _Pill(
                            label: 'Recurring',
                            color: Color(0x1FFFFFFF),
                            foreground: Colors.white,
                          ),
                        if (event.ticketing.enabled)
                          const _Pill(
                            label: 'Ticketing',
                            color: Color(0x1FFFFFFF),
                            foreground: Colors.white,
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      formatShortDate(event.startDate),
                      style: context.text.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: context.text.titleLarge?.copyWith(fontSize: 22)),
                  const SizedBox(height: 8),
                  Text(
                    event.description,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 18, color: palette.slate),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${event.venue}, ${event.city}',
                          style: context.text.bodyMedium?.copyWith(color: palette.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.schedule_outlined, size: 18, color: palette.slate),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          formatEventWindow(event.startDate, event.endDate),
                          style: context.text.bodyMedium?.copyWith(color: palette.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.favorite_outline,
                        label: '${event.likesCount} likes',
                      ),
                      _InfoChip(
                        icon: Icons.people_outline,
                        label: '${event.rsvpCount} RSVPs',
                      ),
                      _InfoChip(
                        icon: event.ticketing.enabled ? Icons.confirmation_num_outlined : Icons.event_available_outlined,
                        label: minPrice == null ? 'Free entry' : 'From ${formatMoney(minPrice)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (event.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: event.tags
                      .take(compact ? 2 : 4)
                      .map(
                        (tag) => Chip(
                          label: Text(tag),
                          backgroundColor: palette.canvas,
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.all(18),
                child: footer,
              )
            else
              const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: palette.slate),
          const SizedBox(width: 8),
          Text(
            label,
            style: context.text.bodyMedium?.copyWith(color: palette.ink),
          ),
        ],
      ),
    );
  }
}
