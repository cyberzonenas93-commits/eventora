import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Vennuzo Design System — cosmic glass UI.
/// Dark starfield surfaces, iridescent accents, and image-led event moments.
class VennuzoTheme {
  // ── Logo-inspired cosmic canvas ───────────────────────────────────
  static const background = Color(0xFF050713);
  static const surface = Color(0xFF0B1022);
  static const surfaceElevated = Color(0xFF111A34);
  static const surfaceBright = Color(0xFF1A2750);

  // ── Text on cosmic surfaces ───────────────────────────────────────
  static const textPrimary = Color(0xFFF7FAFF);
  static const textSecondary = Color(0xFFB8C3E6);
  static const textTertiary = Color(0xFF7F8EB7);

  // ── Iridescent logo palette ───────────────────────────────────────
  static const primaryStart = Color(0xFF6EEBFF);
  static const primaryMid = Color(0xFF8A5CFF);
  static const primaryEnd = Color(0xFFFF5CCB);
  static const accentAmber = Color(0xFFFFC76A);
  static const accentCyan = Color(0xFF74F7FF);
  static const accentMint = Color(0xFF7CF5CC);

  // ── Semantic ──────────────────────────────────────────────────────
  static const success = Color(0xFF10B981);
  static const error = Color(0xFFDC2626);
  static const warning = Color(0xFFF59E0B);

  // ── Borders ───────────────────────────────────────────────────────
  static const border = Color(0x2BFFFFFF);
  static const borderSubtle = Color(0x14FFFFFF);
  static const borderBright = Color(0x40B8F8FF);

  // ── Shadows ───────────────────────────────────────────────────────
  static const shadow = Color(0x8A000000);

  static const shadowResting = [
    BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
  static const shadowElevated = [
    BoxShadow(color: Color(0x7A000000), blurRadius: 28, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x2B6EEBFF), blurRadius: 20, offset: Offset(0, 0)),
  ];
  static const shadowFloating = [
    BoxShadow(color: Color(0x8F000000), blurRadius: 38, offset: Offset(0, 18)),
    BoxShadow(color: Color(0x2EFF5CCB), blurRadius: 26, offset: Offset(0, 0)),
  ];

  // ── Iridescent glow shadows ───────────────────────────────────────
  static List<BoxShadow> glowShadow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.12),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: color.withValues(alpha: 0.06),
      blurRadius: 34,
      offset: const Offset(0, 14),
    ),
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
        onPrimary: Color(0xFF031018),
        secondary: primaryEnd,
        onSecondary: Colors.white,
        tertiary: primaryMid,
        onTertiary: Colors.white,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        outline: border,
      ),
    );

    final bodyFont = GoogleFonts.interTextTheme(base.textTheme);

    final textTheme = bodyFont.copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 48,
        height: 1.0,
        color: textPrimary,
        fontWeight: FontWeight.w800,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 40,
        height: 1.02,
        color: textPrimary,
        fontWeight: FontWeight.w800,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 34,
        height: 1.05,
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 28,
        height: 1.08,
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 24,
        height: 1.1,
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 20,
        height: 1.15,
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 17,
        color: textPrimary,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 15,
        color: textPrimary,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        color: textSecondary,
        height: 1.6,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        color: textSecondary,
        height: 1.55,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        color: textTertiary,
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 15,
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        color: textSecondary,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        color: textTertiary,
        fontWeight: FontWeight.w600,
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
        backgroundColor: background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        foregroundColor: textPrimary,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
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
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: border),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
        side: const BorderSide(color: border),
        labelStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          color: const Color(0xFF031018),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        selectedColor: primaryStart,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryStart,
          foregroundColor: const Color(0xFF031018),
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surface,
          side: const BorderSide(color: border),
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryStart,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: GoogleFonts.inter(
          color: textTertiary,
          fontWeight: FontWeight.w400,
        ),
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
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceBright,
        contentTextStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryStart,
        foregroundColor: const Color(0xFF031018),
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
          darkSurfaceMid: surfaceBright,
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
    Color? ink,
    Color? slate,
    Color? muted,
    Color? coral,
    Color? teal,
    Color? gold,
    Color? warm,
    Color? mint,
    Color? card,
    Color? cardElevated,
    Color? canvas,
    Color? success,
    Color? error,
    Color? warning,
    Color? border,
    Color? borderSubtle,
    Color? darkSurface,
    Color? darkSurfaceMid,
    Color? primaryStart,
    Color? primaryMid,
    Color? primaryEnd,
  }) {
    return VennuzoPalette(
      ink: ink ?? this.ink,
      slate: slate ?? this.slate,
      muted: muted ?? this.muted,
      coral: coral ?? this.coral,
      teal: teal ?? this.teal,
      gold: gold ?? this.gold,
      warm: warm ?? this.warm,
      mint: mint ?? this.mint,
      card: card ?? this.card,
      cardElevated: cardElevated ?? this.cardElevated,
      canvas: canvas ?? this.canvas,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      darkSurface: darkSurface ?? this.darkSurface,
      darkSurfaceMid: darkSurfaceMid ?? this.darkSurfaceMid,
      primaryStart: primaryStart ?? this.primaryStart,
      primaryMid: primaryMid ?? this.primaryMid,
      primaryEnd: primaryEnd ?? this.primaryEnd,
    );
  }

  @override
  ThemeExtension<VennuzoPalette> lerp(
    covariant ThemeExtension<VennuzoPalette>? other,
    double t,
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
      cardElevated:
          Color.lerp(cardElevated, other.cardElevated, t) ?? cardElevated,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      success: Color.lerp(success, other.success, t) ?? success,
      error: Color.lerp(error, other.error, t) ?? error,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      border: Color.lerp(border, other.border, t) ?? border,
      borderSubtle:
          Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      darkSurface: Color.lerp(darkSurface, other.darkSurface, t) ?? darkSurface,
      darkSurfaceMid:
          Color.lerp(darkSurfaceMid, other.darkSurfaceMid, t) ?? darkSurfaceMid,
      primaryStart:
          Color.lerp(primaryStart, other.primaryStart, t) ?? primaryStart,
      primaryMid: Color.lerp(primaryMid, other.primaryMid, t) ?? primaryMid,
      primaryEnd: Color.lerp(primaryEnd, other.primaryEnd, t) ?? primaryEnd,
    );
  }
}
