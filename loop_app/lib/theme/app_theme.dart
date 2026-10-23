import 'package:flutter/material.dart';

/// Paleta boja LICIT-a. Vrijednosti ovise o aktivnoj temi (svijetla/tamna),
/// koju postavlja [LoopColors.use] prije izgradnje [MaterialApp].
///
/// Smjer dizajna: topla, prijateljska tržnica rabljenih stvari — krem
/// pozadina, bijele kartice, terakota akcent i pastelni detalji.
/// Kontrast teksta je provjeren (WCAG AA ≥ 4.5:1 za tekst).
class LoopColors {
  static bool _dark = false;

  static bool get isDark => _dark;

  /// Postavlja aktivnu paletu. Poziva se iz `LoopApp` pri promjeni teme.
  static void use(Brightness brightness) =>
      _dark = brightness == Brightness.dark;

  static Color get background =>
      _dark ? const Color(0xFF110E1A) : const Color(0xFFF6F4FB);
  static Color get surface =>
      _dark ? const Color(0xFF1C1828) : const Color(0xFFFFFFFF);
  static Color get surfaceHover =>
      _dark ? const Color(0xFF272238) : const Color(0xFFECE8F7);

  /// Glavni akcent (gumbi, odabrano). Svijetla: bijeli tekst 4.9:1;
  /// tamna: tamni tekst 7.8:1.
  static Color get accent =>
      _dark ? const Color(0xFFB79BFF) : const Color(0xFF6A2BD6);

  /// Tekst/ikone na akcentu.
  static Color get onAccent =>
      _dark ? const Color(0xFF16102A) : const Color(0xFFFFFFFF);

  static Color get textPrimary =>
      _dark ? const Color(0xFFF2EEFF) : const Color(0xFF1B1530);
  static Color get textSecondary =>
      _dark ? const Color(0xFFA79FC0) : const Color(0xFF6B6385);
  static Color get error =>
      _dark ? const Color(0xFFFF7B7B) : const Color(0xFFC92A3A);
  static Color get success =>
      _dark ? const Color(0xFF4CC38A) : const Color(0xFF1A7F4E);

  /// Plava za bedž "Provjeren" i informativne oznake.
  static Color get info =>
      _dark ? const Color(0xFF6CB4FF) : const Color(0xFF1E6FD9);

  /// Akcent admin panela — namjerno drugačiji (indigo) da je admin
  /// vizualno odvojen od korisničkog dijela.
  static Color get admin =>
      _dark ? const Color(0xFFA8A2FF) : const Color(0xFF4F46E5);

  // Pastelni tonovi za dekorativne pločice i pozadine (nikad za tekst).
  static Color get peach =>
      _dark ? const Color(0xFF3A2A22) : const Color(0xFFFFE1D1);
  static Color get sunny =>
      _dark ? const Color(0xFF3A3220) : const Color(0xFFFFEDB8);
  static Color get mint =>
      _dark ? const Color(0xFF1F3329) : const Color(0xFFD6F2E3);
  static Color get lilac =>
      _dark ? const Color(0xFF2B2740) : const Color(0xFFE7E0FF);
  static Color get sky =>
      _dark ? const Color(0xFF1F2C3A) : const Color(0xFFD9ECFF);
  static Color get rose =>
      _dark ? const Color(0xFF3A2228) : const Color(0xFFFFD9E0);

  /// Meka sjena kartica (u tamnoj temi gotovo nevidljiva).
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: _dark
          ? Colors.black.withValues(alpha: 0.25)
          : const Color(0xFF3B2A6B).withValues(alpha: 0.10),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
}

const double kRadius = 18;
const String kFontFamily = 'Nunito';

/// Material 3 tema za trenutno aktivnu paletu ([LoopColors.use]).
ThemeData buildLoopTheme({Color? accent}) {
  final dark = LoopColors.isDark;
  final primary = accent ?? LoopColors.accent;
  final onPrimary = accent == null || !dark
      ? LoopColors.onAccent
      : const Color(0xFF14122B);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: primary,
        onPrimary: onPrimary,
        surface: LoopColors.surface,
        onSurface: LoopColors.textPrimary,
        onSurfaceVariant: LoopColors.textSecondary,
        surfaceContainerHighest: LoopColors.surfaceHover,
        error: LoopColors.error,
      );

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(kRadius),
  );
  final base = dark ? ThemeData.dark() : ThemeData.light();

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: kFontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: LoopColors.background,
    canvasColor: LoopColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: LoopColors.background,
      foregroundColor: LoopColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: LoopColors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: LoopColors.surface,
      elevation: dark ? 0 : 1.5,
      shadowColor: const Color(0xFF3B2A6B).withValues(alpha: 0.25),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: rounded,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: LoopColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: rounded,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: LoopColors.textPrimary,
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        side: BorderSide(color: LoopColors.surfaceHover, width: 2),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: LoopColors.surface,
      selectedColor: primary.withValues(alpha: 0.16),
      side: BorderSide(color: LoopColors.surfaceHover),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontFamily: kFontFamily,
        fontWeight: FontWeight.w600,
        color: LoopColors.textPrimary,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      shape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LoopColors.surface,
      labelStyle: TextStyle(color: LoopColors.textSecondary),
      hintStyle: TextStyle(color: LoopColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: BorderSide(color: LoopColors.surfaceHover, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: BorderSide(color: LoopColors.surfaceHover, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: BorderSide(color: LoopColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? LoopColors.surfaceHover : const Color(0xFF2A1F17),
      contentTextStyle: TextStyle(
        fontFamily: kFontFamily,
        color: dark ? LoopColors.textPrimary : Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: rounded,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: LoopColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: kFontFamily,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? LoopColors.textPrimary
              : LoopColors.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? primary
              : LoopColors.textSecondary,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: LoopColors.surface,
      indicatorColor: primary.withValues(alpha: 0.16),
      selectedIconTheme: IconThemeData(color: primary),
      unselectedIconTheme: IconThemeData(color: LoopColors.textSecondary),
      selectedLabelTextStyle: TextStyle(
        fontFamily: kFontFamily,
        color: LoopColors.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: kFontFamily,
        color: LoopColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: primary.withValues(alpha: 0.16),
        selectedForegroundColor: LoopColors.textPrimary,
        foregroundColor: LoopColors.textSecondary,
        side: BorderSide(color: LoopColors.surfaceHover, width: 1.5),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: LoopColors.surfaceHover),
    textTheme: base.textTheme.apply(
      fontFamily: kFontFamily,
      bodyColor: LoopColors.textPrimary,
      displayColor: LoopColors.textPrimary,
    ),
  );
}
