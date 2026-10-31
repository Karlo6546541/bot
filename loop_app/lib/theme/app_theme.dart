import 'package:flutter/material.dart';

/// Paleta boja Subhasta. Vrijednosti ovise o aktivnoj temi (svijetla/tamna),
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
      _dark ? const Color(0xFF121212) : const Color(0xFFFFF7EF);
  static Color get surface =>
      _dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  static Color get surfaceHover =>
      _dark ? const Color(0xFF2A2A2A) : const Color(0xFFFFEFE2);

  // Pravila boja (nikad se ne miješaju):
  //  * narančasta [accent] — glavne radnje: Licitiraj, Kupi, Objavi;
  //  * crvena [live] — samo "uživo";
  //  * zelena [buyNow] — Kupi odmah, dostavljeno, zaštita kupca.

  /// Glavni akcent (gumbi, odabrano) — narančasta. Svijetla: bijeli
  /// tekst 5.2:1; tamna: tamni tekst 7.9:1.
  static Color get accent =>
      _dark ? const Color(0xFFFF9248) : const Color(0xFFC2410C);

  /// Uživo (oznaka UŽIVO, live gumbi i bljesak) — isključivo za live.
  static const Color live = Color(0xFFFF2D55);

  /// Kupi odmah, dostavljeno, zaštita kupca. Bijeli tekst 5.0:1.
  static Color get buyNow =>
      _dark ? const Color(0xFF4CC38A) : const Color(0xFF15803D);

  /// Tekst/ikone na akcentu.
  static Color get onAccent =>
      _dark ? const Color(0xFF1B1410) : const Color(0xFFFFFFFF);

  static Color get textPrimary =>
      _dark ? const Color(0xFFFFFFFF) : const Color(0xFF2A1F17);
  static Color get textSecondary =>
      _dark ? const Color(0xFFA3A3A3) : const Color(0xFF76685D);
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

  /// Whatnot nema vidljivih sjena: slojevi se odvajaju bojom podloge.
  /// Ostaje kao prazan popis da postojeći zapisi (`...softShadow`) rade.
  static List<BoxShadow> get softShadow => const [];
}

const double kRadius = 14;
const String kFontFamily = 'Nunito';

/// Live je uvijek taman (kao TikTok/Whatnot), neovisno o temi aplikacije:
/// tamna Material tema za sobu i listove otvorene iz nje.
ThemeData buildLiveTheme() {
  final was = LoopColors._dark;
  LoopColors._dark = true;
  try {
    return buildLoopTheme();
  } finally {
    LoopColors._dark = was;
  }
}

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
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: rounded,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: LoopColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: LoopColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected)
            ? LoopColors.buyNow
            : LoopColors.surfaceHover,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        minimumSize: const Size(64, 48),
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
        backgroundColor: LoopColors.surfaceHover,
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        side: BorderSide.none,
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
      backgroundColor: LoopColors.surfaceHover,
      selectedColor: LoopColors.textPrimary,
      side: BorderSide.none,
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(
        fontFamily: kFontFamily,
        fontWeight: FontWeight.w700,
        // Odabrani čip je obrnut (bijeli s crnim tekstom u tamnoj temi).
        color: WidgetStateColor.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? LoopColors.background
              : LoopColors.textPrimary,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      shape: const StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      // Pomoćni tekst i greške se lome u više redova (ne režu se).
      helperMaxLines: 3,
      errorMaxLines: 3,
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
      indicatorColor: Colors.transparent,
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
              ? LoopColors.textPrimary
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

/// Listovi aplikacije (plaćanje, novčanik, dostava) uvijek u temi
/// aplikacije — i kad se otvore iz tamnog livea.
Widget appThemed(Widget child) => Theme(data: buildLoopTheme(), child: child);
