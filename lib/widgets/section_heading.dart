import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../core/theme/vennuzo_theme.dart';

/// Refined section heading — smaller, more editorial, less dominant.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Accent bar
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                VennuzoTheme.primaryStart,
                VennuzoTheme.primaryMid,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.text.titleMedium?.copyWith(
                  letterSpacing: -0.2,
                  color: VennuzoTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: context.text.bodySmall?.copyWith(
                    color: palette.slate,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              foregroundColor: VennuzoTheme.primaryStart,
            ),
            child: Text(
              actionLabel!,
              style: context.text.labelMedium?.copyWith(
                color: VennuzoTheme.primaryStart,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
