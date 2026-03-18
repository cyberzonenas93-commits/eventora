import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EventoraTheme {
  static const background = Color(0xFFF9FAFB);
  static const surface = Color(0xFFFFFFFF);
  static const darkSurface = Color(0xFF111827);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const primaryStart = Color(0xFF6366F1);
  static const primaryEnd = Color(0xFFF43F5E);
  static const accent = Color(0xFFF43F5E);
  static const accentSoft = Color(0xFF8B5CF6);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
  static const border = Color(0xFFE5E7EB);
  static const shadow = Color(0x14111827);

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: primaryStart,
        onPrimary: Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
      ),
    );

    final displayFont = GoogleFonts.soraTextTheme(base.textTheme);
    final bodyFont = GoogleFonts.interTextTheme(displayFont);

    final textTheme = bodyFont.copyWith(
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        color: textPrimary,
        height: 1.55,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        color: textSecondary,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
      titleLarge: GoogleFonts.sora(
        fontSize: 24,
        height: 1.1,
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.sora(
        fontSize: 34,
        height: 1.02,
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: GoogleFonts.sora(
        fontSize: 28,
        height: 1.04,
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 15,
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: GoogleFonts.sora(
        fontSize: 18,
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );

    return base.copyWith(
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sora(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: shadow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: const BorderSide(color: border),
        labelStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryStart,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: const Color(0xFFF3F4F6),
          side: const BorderSide(color: border),
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        hintStyle: GoogleFonts.inter(
          color: textSecondary.withValues(alpha: 0.85),
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: error, width: 1.4),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        selectedItemColor: primaryStart,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkSurface,
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryStart,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      dividerColor: border,
      extensions: const [
        EventoraPalette(
          ink: textPrimary,
          slate: textSecondary,
          coral: accent,
          teal: primaryStart,
          gold: accentSoft,
          card: surface,
          canvas: background,
          success: success,
          error: error,
          border: border,
          darkSurface: darkSurface,
          primaryStart: primaryStart,
          primaryEnd: primaryEnd,
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
    required this.success,
    required this.error,
    required this.border,
    required this.darkSurface,
    required this.primaryStart,
    required this.primaryEnd,
  });

  final Color ink;
  final Color slate;
  final Color coral;
  final Color teal;
  final Color gold;
  final Color card;
  final Color canvas;
  final Color success;
  final Color error;
  final Color border;
  final Color darkSurface;
  final Color primaryStart;
  final Color primaryEnd;

  @override
  ThemeExtension<EventoraPalette> copyWith({
    Color? ink,
    Color? slate,
    Color? coral,
    Color? teal,
    Color? gold,
    Color? card,
    Color? canvas,
    Color? success,
    Color? error,
    Color? border,
    Color? darkSurface,
    Color? primaryStart,
    Color? primaryEnd,
  }) {
    return EventoraPalette(
      ink: ink ?? this.ink,
      slate: slate ?? this.slate,
      coral: coral ?? this.coral,
      teal: teal ?? this.teal,
      gold: gold ?? this.gold,
      card: card ?? this.card,
      canvas: canvas ?? this.canvas,
      success: success ?? this.success,
      error: error ?? this.error,
      border: border ?? this.border,
      darkSurface: darkSurface ?? this.darkSurface,
      primaryStart: primaryStart ?? this.primaryStart,
      primaryEnd: primaryEnd ?? this.primaryEnd,
    );
  }

  @override
  ThemeExtension<EventoraPalette> lerp(
    covariant ThemeExtension<EventoraPalette>? other,
    double t,
  ) {
    if (other is! EventoraPalette) {
      return this;
    }
    return EventoraPalette(
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      slate: Color.lerp(slate, other.slate, t) ?? slate,
      coral: Color.lerp(coral, other.coral, t) ?? coral,
      teal: Color.lerp(teal, other.teal, t) ?? teal,
      gold: Color.lerp(gold, other.gold, t) ?? gold,
      card: Color.lerp(card, other.card, t) ?? card,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      success: Color.lerp(success, other.success, t) ?? success,
      error: Color.lerp(error, other.error, t) ?? error,
      border: Color.lerp(border, other.border, t) ?? border,
      darkSurface: Color.lerp(darkSurface, other.darkSurface, t) ?? darkSurface,
      primaryStart:
          Color.lerp(primaryStart, other.primaryStart, t) ?? primaryStart,
      primaryEnd: Color.lerp(primaryEnd, other.primaryEnd, t) ?? primaryEnd,
    );
  }
}
