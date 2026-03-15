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
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x1410212A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 16),
          Text(
            value,
            style: context.text.headlineSmall?.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: context.text.bodyMedium),
        ],
      ),
    );
  }
}
