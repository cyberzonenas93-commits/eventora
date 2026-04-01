import 'package:flutter/material.dart';

import '../core/art/art_seed.dart';
import '../core/theme/theme_extensions.dart';
import '../core/theme/vennuzo_theme.dart';
import 'vennuzo_motion.dart';

/// Premium metric tile with glassmorphic feel,
/// inspired by Ticketmaster's elevated card system.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.highlight,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = highlight ?? palette.teal;

    return VennuzoReveal(
      delay: const Duration(milliseconds: 80),
      child: Container(
        constraints: const BoxConstraints(minWidth: 152),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(VennuzoTheme.radiusLg),
          border: Border.all(color: palette.border.withValues(alpha: 0.5)),
          boxShadow: VennuzoTheme.shadowResting,
        ),
        child: Stack(
          children: [
            // Subtle accent glow in top-right
            Positioned(
              top: -8,
              right: -8,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.1),
                      accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Subtle decorative dots
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _MetricDotsPainter(
                    seed: ArtSeed.hash(label),
                    color: accent,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.15),
                        accent.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(height: 16),
                Text(
                  value,
                  style: context.text.headlineSmall?.copyWith(
                    fontSize: 24,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: context.text.bodySmall?.copyWith(
                    color: palette.slate,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricDotsPainter extends CustomPainter {
  const _MetricDotsPainter({required this.seed, required this.color});

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dotCount = 5;
    for (int i = 0; i < dotCount; i++) {
      final si = i * 5;
      final x = size.width * ArtSeed.seedRange(seed, si, 0.15, 0.9);
      final y = size.height * ArtSeed.seedRange(seed, si + 1, 0.15, 0.9);
      final r = ArtSeed.seedRange(seed, si + 2, 1.5, 4);
      final alpha = ArtSeed.seedRange(seed, si + 3, 0.02, 0.06);

      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_MetricDotsPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.color != color;
}
