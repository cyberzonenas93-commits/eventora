import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EventoraTheme {
  static const _canvas = Color(0xFFF4EFE8);
  static const _ink = Color(0xFF10212A);
  static const _slate = Color(0xFF54656F);
  static const _card = Color(0xFFFFFCF8);
  static const _coral = Color(0xFFE86B43);
  static const _teal = Color(0xFF2B7A78);
  static const _gold = Color(0xFFE8B64A);
  static const _shadow = Color(0x1A10212A);

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _coral,
        brightness: Brightness.light,
        primary: _ink,
        secondary: _teal,
        surface: _card,
      ),
    );

    final textTheme = GoogleFonts.spaceGroteskTextTheme(base.textTheme)
        .copyWith(
          bodyLarge: GoogleFonts.manrope(
            fontSize: 16,
            color: _ink,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
          bodyMedium: GoogleFonts.manrope(
            fontSize: 14,
            color: _slate,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
          titleLarge: GoogleFonts.spaceGrotesk(
            fontSize: 24,
            color: _ink,
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: GoogleFonts.spaceGrotesk(
            fontSize: 34,
            color: _ink,
            fontWeight: FontWeight.w700,
          ),
          headlineSmall: GoogleFonts.spaceGrotesk(
            fontSize: 28,
            color: _ink,
            fontWeight: FontWeight.w700,
          ),
          labelLarge: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        centerTitle: false,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: _card,
        surfaceTintColor: Colors.transparent,
        shadowColor: _shadow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0x1F10212A)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
        labelStyle: GoogleFonts.spaceGrotesk(
          color: _ink,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0x3310212A)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        hintStyle: GoogleFonts.manrope(
          color: _slate.withValues(alpha: 0.8),
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0x2010212A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0x2010212A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: _ink, width: 1.4),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFF8F2EB),
        elevation: 0,
        selectedItemColor: _ink,
        unselectedItemColor: _slate,
        type: BottomNavigationBarType.fixed,
      ),
      dividerColor: const Color(0x1F10212A),
      extensions: const [
        EventoraPalette(
          ink: _ink,
          slate: _slate,
          coral: _coral,
          teal: _teal,
          gold: _gold,
          card: _card,
          canvas: _canvas,
        ),
      ],
    );
  }
}

@immutable
class EventoraPalette extends ThemeExtension<EventoraPalette> {
  const EventoraPalette({
    required this.ink,
    required this.slate,
    required this.coral,
    required this.teal,
    required this.gold,
    required this.card,
    required this.canvas,
  });

  final Color ink;
  final Color slate;
  final Color coral;
  final Color teal;
  final Color gold;
  final Color card;
  final Color canvas;

  @override
  ThemeExtension<EventoraPalette> copyWith({
    Color? ink,
    Color? slate,
    Color? coral,
    Color? teal,
    Color? gold,
    Color? card,
    Color? canvas,
  }) {
    return EventoraPalette(
      ink: ink ?? this.ink,
      slate: slate ?? this.slate,
      coral: coral ?? this.coral,
      teal: teal ?? this.teal,
      gold: gold ?? this.gold,
      card: card ?? this.card,
      canvas: canvas ?? this.canvas,
    );
  }

  @override
  ThemeExtension<EventoraPalette> lerp(
    covariant ThemeExtension<EventoraPalette>? other,
    double t,
  ) {
    if (other is! EventoraPalette) return this;
    return EventoraPalette(
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      slate: Color.lerp(slate, other.slate, t) ?? slate,
      coral: Color.lerp(coral, other.coral, t) ?? coral,
      teal: Color.lerp(teal, other.teal, t) ?? teal,
      gold: Color.lerp(gold, other.gold, t) ?? gold,
      card: Color.lerp(card, other.card, t) ?? card,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
    );
  }
}
