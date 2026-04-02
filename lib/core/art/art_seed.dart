import 'dart:ui';

/// Deterministic seed utilities for generative art.
///
/// All helpers are pure functions — same input always yields the same output.
class ArtSeed {
  ArtSeed._();

  /// FNV-1a 32-bit hash of [input].
  static int hash(String input) {
    int h = 0x811c9dc5;
    for (int i = 0; i < input.length; i++) {
      h ^= input.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Combine two seeds into a new deterministic seed.
  static int combine(int a, int b) => (a * 31 + b) & 0x7FFFFFFF;

  /// Returns a double in [0.0, 1.0) derived from [seed] and [index].
  static double seedDouble(int seed, int index) {
    final mixed = combine(seed, index * 7919 + 104729);
    return (mixed & 0xFFFF) / 65536.0;
  }

  /// Returns an integer in [0, max) derived from [seed] and [index].
  static int seedInt(int seed, int index, int max) {
    if (max <= 0) return 0;
    return ((seedDouble(seed, index) * max).floor()).clamp(0, max - 1);
  }

  /// Picks a color from [palette] using the seed.
  static Color seedColor(int seed, int index, List<Color> palette) {
    if (palette.isEmpty) return const Color(0xFF000000);
    return palette[seedInt(seed, index, palette.length)];
  }

  /// Returns a double in [min, max] derived from [seed] and [index].
  static double seedRange(int seed, int index, double min, double max) {
    return min + seedDouble(seed, index) * (max - min);
  }
}
