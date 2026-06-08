import 'package:flutter/material.dart';

import '../core/theme/theme_extensions.dart';
import '../domain/models/place_models.dart';

/// Small pill that reflects a place's verification state.
///
/// - `verified`  → green "Verified" badge with a check.
/// - `pending`   → amber "In review" chip.
/// - otherwise   → muted "Unverified" chip.
///
/// Reused on place cards and the detail header so the badge stays consistent.
class PlaceVerificationBadge extends StatelessWidget {
  const PlaceVerificationBadge({super.key, required this.place, this.compact = false});

  final PlaceProfile place;

  /// Compact variant drops the label down a size for tight rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    late final Color color;
    late final IconData icon;
    late final String label;

    if (place.isVerified) {
      color = palette.success;
      icon = Icons.verified_rounded;
      label = 'Verified';
    } else if (place.isVerificationPending) {
      color = palette.warning;
      icon = Icons.hourglass_top_rounded;
      label = 'In review';
    } else {
      color = palette.slate;
      icon = Icons.error_outline_rounded;
      label = 'Unverified';
    }

    final textStyle = (compact ? context.text.labelSmall : context.text.bodySmall)
        ?.copyWith(color: color, fontWeight: FontWeight.w600);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 13 : 15, color: color),
          const SizedBox(width: 5),
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}
