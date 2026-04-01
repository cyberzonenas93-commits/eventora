import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Vennuzo Design System — Dark iridescent theme matching the 3D
/// holographic logo. Deep navy-black backgrounds with blue-purple-pink
/// iridescent accents and clean white typography.
class VennuzoTheme {
  // ── Dark canvas ───────────────────────────────────────────────────
  static const background = Color(0xFF060611);
  static const surface = Color(0xFF0E0E1A);
  static const surfaceElevated = Color(0xFF16162A);
  static const surfaceBright = Color(0xFF1E1E38);

  // ── Text on dark ──────────────────────────────────────────────────
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8E8EA8);
  static const textTertiary = Color(0xFF5A5A78);

  // ── Iridescent brand palette ──────────────────────────────────────
  static const primaryStart = Color(0xFF7B8CFF);   // Iridescent blue
  static const primaryMid = Color(0xFFB06CFF);     // Holographic purple
  static const primaryEnd = Color(0xFFFF6B9D);     // Pink refraction
  static const accentAmber = Color(0xFFFFB86C);    // Warm amber reflection
  static const accentCyan = Color(0xFF6BDFFF);     // Cool cyan highlight
  static const accentMint = Color(0xFF6BFFB8);     // Green refraction

  // ── Semantic ──────────────────────────────────────────────────────
  static const success = Color(0xFF6BFFB8);
  static const error = Color(0xFFFF6B6B);
  static const warning = Color(0xFFFFB86C);

  // ── Borders ───────────────────────────────────────────────────────
  static const border = Color(0x14FFFFFF);          // 8% white
  static const borderSubtle = Color(0x0AFFFFFF);    // 4% white
  static const borderBright = Color(0x28FFFFFF);    // 16% white

  // ── Shadows ───────────────────────────────────────────────────────
  static const shadow = Color(0x40000000);

  static const shadowResting = [
    BoxShadow(color: Color(0x20000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const shadowElevated = [
    BoxShadow(color: Color(0x30000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x10000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const shadowFloating = [
    BoxShadow(color: Color(0x50000000), blurRadius: 48, offset: Offset(0, 16)),
    BoxShadow(color: Color(0x18000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  // ── Iridescent glow shadows ───────────────────────────────────────
  static List<BoxShadow> glowShadow(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8)),
    BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 48, offset: const Offset(0, 16)),
  ];

  // ── Gradient presets ──────────────────────────────────────────────
  static const brandGradient = LinearGradient(
    colors: [primaryStart, primaryMid, primaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const surfaceGradient = LinearGradient(
    colors: [surface, surfaceElevated],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Border radii ─────────────────────────────────────────────────
  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusXl = 28;
  static const double radiusFull = 999;

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primaryStart,
        onPrimary: Colors.white,
        secondary: primaryEnd,
        onSecondary: Colors.white,
        tertiary: primaryMid,
        onTertiary: Colors.white,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
      ),
    );

    final displayFont = GoogleFonts.soraTextTheme(base.textTheme);
    final bodyFont = GoogleFonts.interTextTheme(displayFont);

    final textTheme = bodyFont.copyWith(
      displayLarge: GoogleFonts.sora(
        fontSize: 48, height: 1.0, color: textPrimary,
        fontWeight: FontWeight.w800, letterSpacing: -1.5,
      ),
      displayMedium: GoogleFonts.sora(
        fontSize: 40, height: 1.02, color: textPrimary,
        fontWeight: FontWeight.w800, letterSpacing: -1.0,
      ),
      headlineLarge: GoogleFonts.sora(
        fontSize: 34, height: 1.05, color: textPrimary,
        fontWeight: FontWeight.w700, letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.sora(
        fontSize: 28, height: 1.08, color: textPrimary,
        fontWeight: FontWeight.w700, letterSpacing: -0.3,
      ),
      headlineSmall: GoogleFonts.sora(
        fontSize: 24, height: 1.1, color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: GoogleFonts.sora(
        fontSize: 20, height: 1.15, color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: GoogleFonts.sora(
        fontSize: 17, color: textPrimary, fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 15, color: textPrimary, fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16, color: textSecondary, height: 1.6,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14, color: textSecondary, height: 1.55,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12, color: textTertiary, height: 1.5,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12, color: textSecondary, fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11, color: textTertiary, fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );

    return base.copyWith(
      splashFactory: InkSparkle.splashFactory,
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
        scrolledUnderElevation: 0,
        foregroundColor: textPrimary,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sora(
          fontSize: 20, fontWeight: FontWeight.w700,
          color: textPrimary, letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: shadow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: border),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
        side: const BorderSide(color: border),
        labelStyle: GoogleFonts.inter(
          color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryStart,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15, fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surfaceElevated,
          side: const BorderSide(color: border),
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14, fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryStart,
          textStyle: GoogleFonts.inter(
            fontSize: 14, fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: GoogleFonts.inter(color: textTertiary, fontWeight: FontWeight.w400),
        prefixIconColor: textTertiary,
        suffixIconColor: textTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryStart, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: primaryStart,
        unselectedItemColor: textTertiary,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.3,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceBright,
        contentTextStyle: GoogleFonts.inter(
          color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryStart,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      dividerColor: border,
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
      ),
      extensions: const [
        VennuzoPalette(
          ink: textPrimary,
          slate: textSecondary,
          muted: textTertiary,
          coral: primaryEnd,
          teal: primaryStart,
          gold: primaryMid,
          warm: accentAmber,
          mint: accentMint,
          card: surface,
          cardElevated: surfaceElevated,
          canvas: background,
          success: success,
          error: error,
          warning: warning,
          border: border,
          borderSubtle: borderSubtle,
          darkSurface: background,
          darkSurfaceMid: surface,
          primaryStart: primaryStart,
          primaryMid: primaryMid,
          primaryEnd: primaryEnd,
        ),
      ],
    );
  }
}

@immutable
class VennuzoPalette extends ThemeExtension<VennuzoPalette> {
  const VennuzoPalette({
    required this.ink,
    required this.slate,
    required this.muted,
    required this.coral,
    required this.teal,
    required this.gold,
    required this.warm,
    required this.mint,
    required this.card,
    required this.cardElevated,
    required this.canvas,
    required this.success,
    required this.error,
    required this.warning,
    required this.border,
    required this.borderSubtle,
    required this.darkSurface,
    required this.darkSurfaceMid,
    required this.primaryStart,
    required this.primaryMid,
    required this.primaryEnd,
  });

  final Color ink, slate, muted, coral, teal, gold, warm, mint;
  final Color card, cardElevated, canvas;
  final Color success, error, warning;
  final Color border, borderSubtle;
  final Color darkSurface, darkSurfaceMid;
  final Color primaryStart, primaryMid, primaryEnd;

  @override
  ThemeExtension<VennuzoPalette> copyWith({
    Color? ink, Color? slate, Color? muted, Color? coral, Color? teal,
    Color? gold, Color? warm, Color? mint, Color? card, Color? cardElevated,
    Color? canvas, Color? success, Color? error, Color? warning,
    Color? border, Color? borderSubtle, Color? darkSurface,
    Color? darkSurfaceMid, Color? primaryStart, Color? primaryMid,
    Color? primaryEnd,
  }) {
    return VennuzoPalette(
      ink: ink ?? this.ink, slate: slate ?? this.slate,
      muted: muted ?? this.muted, coral: coral ?? this.coral,
      teal: teal ?? this.teal, gold: gold ?? this.gold,
      warm: warm ?? this.warm, mint: mint ?? this.mint,
      card: card ?? this.card, cardElevated: cardElevated ?? this.cardElevated,
      canvas: canvas ?? this.canvas, success: success ?? this.success,
      error: error ?? this.error, warning: warning ?? this.warning,
      border: border ?? this.border, borderSubtle: borderSubtle ?? this.borderSubtle,
      darkSurface: darkSurface ?? this.darkSurface,
      darkSurfaceMid: darkSurfaceMid ?? this.darkSurfaceMid,
      primaryStart: primaryStart ?? this.primaryStart,
      primaryMid: primaryMid ?? this.primaryMid,
      primaryEnd: primaryEnd ?? this.primaryEnd,
    );
  }

  @override
  ThemeExtension<VennuzoPalette> lerp(
    covariant ThemeExtension<VennuzoPalette>? other, double t,
  ) {
    if (other is! VennuzoPalette) return this;
    return VennuzoPalette(
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      slate: Color.lerp(slate, other.slate, t) ?? slate,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      coral: Color.lerp(coral, other.coral, t) ?? coral,
      teal: Color.lerp(teal, other.teal, t) ?? teal,
      gold: Color.lerp(gold, other.gold, t) ?? gold,
      warm: Color.lerp(warm, other.warm, t) ?? warm,
      mint: Color.lerp(mint, other.mint, t) ?? mint,
      card: Color.lerp(card, other.card, t) ?? card,
      cardElevated: Color.lerp(cardElevated, other.cardElevated, t) ?? cardElevated,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      success: Color.lerp(success, other.success, t) ?? success,
      error: Color.lerp(error, other.error, t) ?? error,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      border: Color.lerp(border, other.border, t) ?? border,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      darkSurface: Color.lerp(darkSurface, other.darkSurface, t) ?? darkSurface,
      darkSurfaceMid: Color.lerp(darkSurfaceMid, other.darkSurfaceMid, t) ?? darkSurfaceMid,
      primaryStart: Color.lerp(primaryStart, other.primaryStart, t) ?? primaryStart,
      primaryMid: Color.lerp(primaryMid, other.primaryMid, t) ?? primaryMid,
      primaryEnd: Color.lerp(primaryEnd, other.primaryEnd, t) ?? primaryEnd,
    );
  }
}
