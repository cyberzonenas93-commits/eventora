import 'package:flutter/material.dart';

import '../core/art/event_art_widget.dart';
import '../core/art/mood_art_palette.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/vennuzo_theme.dart';
import '../core/utils/formatters.dart';
import '../domain/models/event_models.dart';
import 'vennuzo_motion.dart';

/// Premium event card — image-led, clean hierarchy, minimal clutter.
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
        minPrice == null ? 'Free' : formatMoney(minPrice);
    final artHeight = compact ? 160.0 : 200.0;
    final moodPal = MoodArtPalette.fromMood(event.mood);

    return VennuzoReveal(
      delay: const Duration(milliseconds: 80),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          boxShadow: [
            BoxShadow(
              color: moodPal.base.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusXl),
          child: Material(
            color: VennuzoTheme.surface,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero image ──────────────────────────────────
                  SizedBox(
                    height: artHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        EventArtwork(event: event, height: artHeight),
                        // Cinematic scrim
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.5, 1.0],
                                colors: [
                                  Colors.black.withValues(alpha: 0.0),
                                  Colors.black.withValues(alpha: 0.08),
                                  Colors.black.withValues(alpha: 0.60),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Status pills — top left
                        Positioned(
                          top: 12,
                          left: 14,
                          child: Wrap(
                            spacing: 6,
                            children: [
                              if (event.isPrivate)
                                _GlassPill(
                                  label: 'Private',
                                  icon: Icons.lock_outline_rounded,
                                )
                              else
                                _GlassPill(
                                  label: 'Public',
                                  icon: Icons.public_rounded,
                                ),
                              if (event.ticketing.enabled)
                                _GlassPill(
                                  label: event.ticketing.requireTicket
                                      ? 'Ticketed'
                                      : 'RSVP',
                                  icon: Icons.confirmation_num_outlined,
                                ),
                            ],
                          ),
                        ),
                        // Date + price — bottom overlay
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 12,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Text(
                                  event.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.titleLarge?.copyWith(
                                    color: Colors.white,
                                    height: 1.1,
                                    letterSpacing: -0.3,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.5),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _PriceBadge(label: entryLabel),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Mood accent line ────────────────────────────
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [moodPal.mid, moodPal.highlight],
                      ),
                    ),
                  ),
                  // ── Card body ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date row
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 13,
                              color: palette.slate,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              formatShortDate(event.startDate),
                              style: context.text.labelMedium?.copyWith(
                                color: VennuzoTheme.primaryStart,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.place_outlined,
                              size: 13,
                              color: palette.slate,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${event.venue}, ${event.city}',
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelMedium?.copyWith(
                                  color: palette.slate,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Description
                        Text(
                          event.description,
                          style: context.text.bodySmall?.copyWith(
                            color: palette.slate,
                            height: 1.55,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        // Social proof + tags row
                        Row(
                          children: [
                            _MicroStat(
                              icon: Icons.favorite_rounded,
                              value: '${event.likesCount}',
                              color: palette.coral,
                            ),
                            const SizedBox(width: 14),
                            _MicroStat(
                              icon: Icons.people_rounded,
                              value: '${event.rsvpCount}',
                              color: palette.teal,
                            ),
                            const Spacer(),
                            if (event.tags.isNotEmpty)
                              _TagChip(
                                label: event.tags.first,
                                color: moodPal.mid,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ── Footer (action buttons) ─────────────────────
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                      child: footer,
                    )
                  else
                    const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Glass pill over image ──────────────────────────────────────────────
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Colors.white.withValues(alpha: 0.85)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Price badge ─────────────────────────────────────────────────────────
class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: VennuzoTheme.background,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

// ── Micro stat ──────────────────────────────────────────────────────────
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
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: context.text.labelSmall?.copyWith(
            color: context.palette.slate,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Tag chip ───────────────────────────────────────────────────────────
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VennuzoTheme.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: color.withValues(alpha: 0.9),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
