import 'package:flutter/material.dart';

import '../core/art/art_seed.dart';
import '../core/art/event_art_widget.dart';
import '../core/art/mood_art_palette.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/vennuzo_theme.dart';
import '../domain/models/event_models.dart';
import 'vennuzo_motion.dart';

/// Refined empty state with subtle art background,
/// inspired by Eventbrite's friendly zero-state patterns.
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.title,
    required this.icon,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? body;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return VennuzoReveal(
      delay: const Duration(milliseconds: 90),
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          border: Border.all(color: palette.border.withValues(alpha: 0.5)),
          boxShadow: VennuzoTheme.shadowResting,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  GenerativeArt(
                    seed: ArtSeed.hash(title),
                    mood: EventMood.sunrise,
                    palette: MoodArtPalette(
                      base: palette.teal.withValues(alpha: 0.12),
                      mid: palette.gold.withValues(alpha: 0.15),
                      highlight: palette.coral.withValues(alpha: 0.18),
                      pop: palette.teal.withValues(alpha: 0.08),
                      overlay: palette.canvas,
                      accent: Colors.white,
                    ),
                    height: 52,
                    width: 52,
                    borderRadius: BorderRadius.circular(16),
                    intensity: 0.5,
                  ),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: Center(
                      child: Icon(icon, color: palette.teal, size: 24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: context.text.titleLarge?.copyWith(fontSize: 18),
              ),
              if (body != null) ...[
                const SizedBox(height: 6),
                Text(
                  body!,
                  style: context.text.bodyMedium?.copyWith(
                    color: palette.slate,
                    height: 1.5,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
