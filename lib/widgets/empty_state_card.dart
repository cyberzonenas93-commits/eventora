import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import 'eventora_motion.dart';

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

    return EventoraReveal(
      delay: const Duration(milliseconds: 90),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.coral.withValues(alpha: 0.18),
                      palette.gold.withValues(alpha: 0.14),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: palette.coral),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: context.text.titleLarge?.copyWith(fontSize: 20),
              ),
              if (body != null) ...[
                const SizedBox(height: 8),
                Text(
                  body!,
                  style: context.text.bodyMedium?.copyWith(
                    color: palette.ink,
                    height: 1.5,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
