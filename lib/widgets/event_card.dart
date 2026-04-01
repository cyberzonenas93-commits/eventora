import 'package:flutter/material.dart';

import '../core/art/event_art_widget.dart';
import '../core/art/mood_art_palette.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/vennuzo_theme.dart';
import '../core/utils/formatters.dart';
import '../domain/models/event_models.dart';
import 'vennuzo_motion.dart';

/// Premium event card inspired by Ticketmaster's 3-tier shadow system,
/// Eventbrite's image-led design, and DICE's immersive dark overlays.
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
    final entryLabel =
        minPrice == null ? 'Free entry' : 'From ${formatMoney(minPrice)}';
    final artHeight = compact ? 180.0 : 220.0;
    final moodPal = MoodArtPalette.fromMood(event.mood);

    return VennuzoReveal(
      delay: const Duration(milliseconds: 110),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          boxShadow: [
            BoxShadow(
              color: moodPal.base.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
            const BoxShadow(
              color: Color(0x080F0F14),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          child: Material(
            color: palette.card,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Immersive hero image ─────────────────────────
                  SizedBox(
                    height: artHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        EventArtwork(event: event, height: artHeight),
                        // Cinematic gradient scrim
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.05),
                                  Colors.black.withValues(alpha: 0.15),
                                  Colors.black.withValues(alpha: 0.65),
                                ],
                                stops: const [0.0, 0.4, 1.0],
                              ),
                            ),
                          ),
                        ),
                        // Top gradient for pills
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.center,
                                colors: [
                                  Colors.black.withValues(alpha: 0.3),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Content overlay
                        Padding(
                          padding: EdgeInsets.all(compact ? 14 : 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Status pills
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _GlassPill(
                                    label: event.isPrivate
                                        ? 'Invite only'
                                        : 'Public',
                                    icon: event.isPrivate
                                        ? Icons.lock_outline
                                        : Icons.public,
                                  ),
                                  if (event.ticketing.enabled)
                                    _GlassPill(
                                      label: event.ticketing.requireTicket
                                          ? 'Tickets'
                                          : 'RSVP',
                                      icon:
                                          Icons.confirmation_num_outlined,
                                    ),
                                  if (event.recurrence.isRecurring)
                                    const _GlassPill(
                                      label: 'Recurring',
                                      icon: Icons.repeat,
                                    ),
                                ],
                              ),
                              const Spacer(),
                              // Date badge
                              _DateChip(
                                label: formatShortDate(event.startDate),
                              ),
                              const SizedBox(height: 8),
                              // Title + price row
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stackBelow =
                                      compact && constraints.maxWidth < 320;
                                  final title = Text(
                                    event.title,
                                    style: context.text.headlineSmall
                                        ?.copyWith(
                                      color: Colors.white,
                                      height: 1.08,
                                      letterSpacing: -0.3,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  );

                                  if (stackBelow) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        title,
                                        const SizedBox(height: 8),
                                        _PriceBadge(label: entryLabel),
                                      ],
                                    );
                                  }

                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
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
                  // ── Gradient accent line ─────────────────────────
                  Container(
                    height: 2.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          moodPal.mid,
                          moodPal.highlight,
                          moodPal.pop.withValues(alpha: 0.4),
                        ],
                      ),
                    ),
                  ),
                  // ── Card body ────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 14 : 18,
                      14,
                      compact ? 14 : 18,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.description,
                          style: context.text.bodyMedium?.copyWith(
                            color: palette.slate,
                            height: 1.5,
                          ),
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.place_outlined,
                          label: '${event.venue}, ${event.city}',
                        ),
                        const SizedBox(height: 8),
                        _InfoRow(
                          icon: Icons.schedule_outlined,
                          label: formatEventWindow(
                            event.startDate,
                            event.endDate,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Social proof row
                        Row(
                          children: [
                            _MicroStat(
                              icon: Icons.favorite_rounded,
                              value: '${event.likesCount}',
                              color: palette.coral,
                            ),
                            const SizedBox(width: 16),
                            _MicroStat(
                              icon: Icons.people_rounded,
                              value: '${event.rsvpCount}',
                              color: palette.teal,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ── Tags ─────────────────────────────────────────
                  if (event.tags.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 14 : 18,
                        10,
                        compact ? 14 : 18,
                        0,
                      ),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: event.tags
                            .take(compact ? 2 : 4)
                            .map(
                              (tag) => _TagChip(
                                label: tag,
                                color: moodPal.mid,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (footer != null)
                    Padding(
                      padding: EdgeInsets.all(compact ? 14 : 16),
                      child: footer,
                    )
                  else
                    const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Glass-morphism pill (over images) ─────────────────────────────────
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Date chip ────────────────────────────────────────────────────────
class _DateChip extends StatelessWidget {
  const _DateChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: VennuzoTheme.primaryStart.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Price badge ──────────────────────────────────────────────────────
class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusSm),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: context.text.titleSmall?.copyWith(
          color: VennuzoTheme.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Info row (venue, time) ───────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: palette.canvas,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: palette.slate),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: context.text.bodyMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Micro stat (likes, RSVPs) ────────────────────────────────────────
class _MicroStat extends StatelessWidget {
  const _MicroStat({
    required this.icon,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: context.text.labelMedium?.copyWith(
            color: context.palette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ── Tag chip ─────────────────────────────────────────────────────────
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: context.palette.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
