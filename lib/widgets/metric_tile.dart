import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';

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
    final accent = highlight ?? palette.ink;

    return Container(
      constraints: const BoxConstraints(minWidth: 152),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.98),
            Colors.white.withValues(alpha: 0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x14121E31)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10121E31),
            blurRadius: 22,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.18),
                  accent.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: context.text.headlineSmall?.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: context.text.bodyMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
