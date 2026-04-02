import 'package:flutter/material.dart' show Color, HSLColor;

import '../../domain/models/event_models.dart';

/// Expanded color palette for generative event artwork.
class MoodArtPalette {
  const MoodArtPalette({
    required this.base,
    required this.mid,
    required this.highlight,
    required this.pop,
    required this.overlay,
    required this.accent,
  });

  final Color base;
  final Color mid;
  final Color highlight;
  final Color pop;
  final Color overlay;
  final Color accent;

  List<Color> get fills => [base, mid, highlight, pop];
  List<Color> get all => [base, mid, highlight, pop, overlay, accent];

  static MoodArtPalette fromMood(EventMood mood) {
    return switch (mood) {
      EventMood.night => const MoodArtPalette(
          base: Color(0xFF0D1B2A),
          mid: Color(0xFF1B3A5C),
          highlight: Color(0xFFE86B43),
          pop: Color(0xFFFFC07A),
          overlay: Color(0xFF6A4C93),
          accent: Color(0xFFE8D5C4),
        ),
      EventMood.sunrise => const MoodArtPalette(
          base: Color(0xFFFF7F50),
          mid: Color(0xFFFFC56E),
          highlight: Color(0xFFFFE0B2),
          pop: Color(0xFFE84878),
          overlay: Color(0xFFFFF3E0),
          accent: Color(0xFFFF9A76),
        ),
      EventMood.electric => const MoodArtPalette(
          base: Color(0xFF10212A),
          mid: Color(0xFF2B7A78),
          highlight: Color(0xFF3AAFA9),
          pop: Color(0xFF17EAD9),
          overlay: Color(0xFF1A3C40),
          accent: Color(0xFFDEF2F1),
        ),
      EventMood.garden => const MoodArtPalette(
          base: Color(0xFF4A7C59),
          mid: Color(0xFF7EBB74),
          highlight: Color(0xFFF4E7B6),
          pop: Color(0xFFE8C547),
          overlay: Color(0xFF5C8A4D),
          accent: Color(0xFFFFFBF0),
        ),
    };
  }

  /// Create a palette from a single accent color (for onboarding, etc.)
  static MoodArtPalette fromAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    return MoodArtPalette(
      base: hsl.withLightness((hsl.lightness * 0.3).clamp(0, 1)).toColor(),
      mid: accent,
      highlight:
          hsl.withLightness((hsl.lightness * 1.3).clamp(0, 0.85)).toColor(),
      pop: hsl
          .withHue((hsl.hue + 30) % 360)
          .withSaturation((hsl.saturation * 1.2).clamp(0, 1))
          .toColor(),
      overlay:
          hsl.withLightness((hsl.lightness * 0.5).clamp(0, 1)).toColor(),
      accent:
          hsl.withLightness((hsl.lightness * 1.5).clamp(0, 0.95)).toColor(),
    );
  }
}
