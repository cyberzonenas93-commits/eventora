import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/utils/formatters.dart';
import '../domain/models/event_models.dart';
import 'vennuzo_motion.dart';

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
    final entryLabel = minPrice == null
        ? 'Free entry'
        : 'From ${formatMoney(minPrice)}';

    return VennuzoReveal(
      delay: const Duration(milliseconds: 110),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: palette.primaryStart.withValues(alpha: 0.1),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(minHeight: compact ? 146 : 188),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        palette.primaryStart,
                        event.mood.colors.first.withValues(alpha: 0.92),
                        palette.primaryEnd,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -18,
                        right: -10,
                        child: Container(
                          width: compact ? 92 : 124,
                          height: compact ? 92 : 124,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(compact ? 16 : 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _HeaderPill(
                                  label: event.isPrivate
                                      ? 'Invite only'
                                      : 'Public event',
                                ),
                                if (event.ticketing.enabled)
                                  _HeaderPill(
                                    label: event.ticketing.requireTicket
                                        ? 'Ticket required'
                                        : 'RSVP friendly',
                                  ),
                                if (event.recurrence.isRecurring)
                                  const _HeaderPill(label: 'Repeats'),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              formatShortDate(event.startDate),
                              style: context.text.bodyLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stackPriceBelow =
                                    compact && constraints.maxWidth < 320;
                                final title = Text(
                                  event.title,
                                  style: context.text.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    height: 1.05,
                                  ),
                                );

                                if (stackPriceBelow) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      title,
                                      const SizedBox(height: 10),
                                      _PriceBadge(label: entryLabel),
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    Expanded(child: title),
                                    const SizedBox(width: 12),
                                    _PriceBadge(label: entryLabel),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 18,
                    18,
                    compact ? 16 : 18,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.description,
                        style: context.text.bodyMedium?.copyWith(
                          color: palette.ink.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DetailStrip(
                        icon: Icons.place_outlined,
                        label: '${event.venue}, ${event.city}',
                      ),
                      const SizedBox(height: 10),
                      _DetailStrip(
                        icon: Icons.schedule_outlined,
                        label: formatEventWindow(
                          event.startDate,
                          event.endDate,
                        ),
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
                            icon: event.ticketing.enabled
                                ? Icons.confirmation_num_outlined
                                : Icons.event_available_outlined,
                            label: entryLabel,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (event.tags.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 18,
                      14,
                      compact ? 16 : 18,
                      0,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: event.tags
                          .take(compact ? 2 : 4)
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: palette.canvas,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: palette.border),
                              ),
                              child: Text(
                                tag,
                                style: context.text.bodyMedium?.copyWith(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                if (footer != null)
                  Padding(
                    padding: EdgeInsets.all(compact ? 16 : 18),
                    child: footer,
                  )
                else
                  const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: context.text.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Text(
          label,
          style: context.text.bodyMedium?.copyWith(
            color: context.palette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DetailStrip extends StatelessWidget {
  const _DetailStrip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: palette.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: Icon(icon, size: 18, color: palette.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: context.text.bodyMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

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
        border: Border.all(color: palette.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 16, color: palette.slate),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
