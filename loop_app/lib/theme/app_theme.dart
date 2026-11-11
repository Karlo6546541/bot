import '../config/features.dart';
import '../config/design_variant.dart';

import 'package:flutter/material.dart';

/// Paleta boja Subhasta. Vrijednosti ovise o aktivnoj temi (svijetla/tamna),
/// koju postavlja [LoopColors.use] prije izgradnje [MaterialApp].
///
/// Fotografije i sadržaj imaju prednost pred ukrasima. Neutralne glavne
/// radnje, plave poveznice te zasebne semantičke boje za stanje i pogreške.
class LoopColors {
  static bool _dark = false;

  static bool get isDark => _dark;

  /// Postavlja aktivnu paletu. Poziva se iz `LoopApp` pri promjeni teme.
  static void use(Brightness brightness) =>
      _dark = brightness == Brightness.dark;

  /// Aplikacija samo za aukcije: tamnozelenoplava paleta s teal akcentom
  /// (klasična, holandska i zatvorena imaju svaka svoju boju oznake).
  static bool get _au => !kLiveEnabled;

  /// Boje vrsta aukcije: klasična · holandska · zatvorena.
  static Color get classic =>
      _dark ? const Color(0xFF9AA4FF) : const Color(0xFF4350C7);
  static Color get dutch =>
      _dark ? const Color(0xFFF0A36B) : const Color(0xFFB45309);
  static Color get sealed =>
      _dark ? const Color(0xFF5FD3A8) : const Color(0xFF1B7F5C);

  static Color get background => _au
      ? (_dark ? const Color(0xFF171C1D) : const Color(0xFFF3F6F6))
      : _dark
      ? const Color(0xFF000000)
      : (kSimpleDesign ? const Color(0xFFFAFAF8) : const Color(0xFFF2F2F7));
  static Color get surface => _au
      ? (_dark ? const Color(0xFF1F2627) : const Color(0xFFFFFFFF))
      : _dark
      ? const Color(0xFF1C1C1E)
      : const Color(0xFFFFFFFF);
  static Color get surfaceHover => _au
      ? (_dark ? const Color(0xFF2A3335) : const Color(0xFFE6ECEC))
      : _dark
      ? const Color(0xFF2C2C30)
      : const Color(0xFFEBEDF1);

  /// Shared VisionOS surfaces; opaque content stays readable on every page.
  static Color get glassBorder => _au
      ? (_dark ? const Color(0xFF343D3F) : const Color(0xFFD4DBDC))
      : _dark
      ? Colors.white.withValues(alpha: .18)
      : Colors.black.withValues(alpha: .10);
  static Color get glass => _au
      ? surface
      : _dark
      ? const Color(0xFF28282D).withValues(alpha: .45)
      : Colors.white.withValues(alpha: .8);
  static Color get gold =>
      _dark ? const Color(0xFFFFD60A) : const Color(0xFF806000);

  /// Poveznice, odabir i fokus polja.
  static Color get accent => _au
      ? (_dark ? const Color(0xFF449DA8) : const Color(0xFF2A7C88))
      : _dark
      ? const Color(0xFF64B0FF)
      : const Color(0xFF0066CC);

  /// Uživo (oznaka UŽIVO, live gumbi i bljesak) — isključivo za live.
  // Slightly deeper than the reference so small white labels stay readable.
  static const Color live = Color(0xFFD92D26);

  /// Kupi odmah, dostavljeno, zaštita kupca.
  static Color get buyNow =>
      _dark ? const Color(0xFF30D158) : const Color(0xFF1E7E34);

  /// Tekst/ikone na akcentu.
  static Color get onAccent => _au
      ? (_dark ? const Color(0xFF0E1516) : const Color(0xFFFFFFFF))
      : _dark
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  static Color get textPrimary => _au
      ? (_dark ? const Color(0xFFF2F4F4) : const Color(0xFF141B1C))
      : _dark
      ? const Color(0xFFF5F5F7)
      : const Color(0xFF1D1D1F);
  static Color get textSecondary => _au
      ? (_dark ? const Color(0xFFA4ADAF) : const Color(0xFF566264))
      : _dark
      ? const Color(0xFFAEAEB6)
      : const Color(0xFF646871);
  static Color get error => _au
      ? (_dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828))
      : _dark
      ? const Color(0xFFFF453A)
      : const Color(0xFFD70015);
  static Color get success => _au
      ? (_dark ? const Color(0xFF5FD3A8) : const Color(0xFF1B7F5C))
      : _dark
      ? const Color(0xFF30D158)
      : const Color(0xFF1E7E34);

  /// Plava za bedž "Provjeren" i informativne oznake.
  static Color get info => _au
      ? (_dark ? const Color(0xFF9AA4FF) : const Color(0xFF4350C7))
      : _dark
      ? const Color(0xFF0A84FF)
      : const Color(0xFF0066CC);

  /// Akcent admin panela — namjerno drugačiji (ljubičasta) da je admin
  /// vizualno odvojen od korisničkog dijela.
  static Color get admin =>
      _dark ? const Color(0xFFBF5AF2) : const Color(0xFF7D3CC8);

  // Tamni, gotovo neutralni tonovi za dekorativne pločice i pozadine
  // (nikad za tekst). Boja je tek naznačena, kao toplo svjetlo na crnom.
  static Color get peach =>
      _dark ? const Color(0xFF2A1C10) : const Color(0xFFFFE9D6);
  static Color get sunny =>
      _dark ? const Color(0xFF2A2310) : const Color(0xFFFFF1C9);
  static Color get mint =>
      _dark ? const Color(0xFF10261A) : const Color(0xFFD9F3E3);
  static Color get lilac =>
      _dark ? const Color(0xFF1F1A33) : const Color(0xFFE9E3FF);
  static Color get sky =>
      _dark ? const Color(0xFF0F2233) : const Color(0xFFDCEBFF);
  static Color get rose =>
      _dark ? const Color(0xFF2E1519) : const Color(0xFFFFDDE2);

  /// Slojevi se odvajaju podlogom i tankim obrubom.
  /// Ostaje kao prazan popis da postojeći zapisi (`...softShadow`) rade.
  static List<BoxShadow> get softShadow => const [];
}

/// Kartice i polja: velike, mekano zaobljene (Apple stil).
const double kRadius = 24;

/// Jedinstveni radijusi (kapsula je rezervirana za promjenu kartica, vidi
/// `widgets/pill_tabs.dart`): čipovi 12 · gumbi i polja 16 · kartice 24 ·
/// listovi i prozori 28+.
const double kRadiusChip = 12;
const double kRadiusButton = 16;
const String kFontFamily = 'Inter';

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
  final primary =
      accent ?? (kLiveEnabled ? LoopColors.textPrimary : LoopColors.accent);
  final onPrimary = accent == null
      ? (kLiveEnabled ? LoopColors.background : LoopColors.onAccent)
      : ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
      ? Colors.white
      : const Color(0xFF111113);

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
  final baseTheme = dark ? ThemeData.dark() : ThemeData.light();
  final base = kSimpleDesign
      ? baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(fontFamily: kFontFamily),
        )
      : baseTheme;

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
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: LoopColors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: kSimpleDesign && kLiveEnabled
          ? Colors.transparent
          : LoopColors.glass,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(
          color: kSimpleDesign && kLiveEnabled
              ? Colors.transparent
              : LoopColors.glassBorder,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: LoopColors.surface.withValues(alpha: .85),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(color: LoopColors.glassBorder),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: LoopColors.surface.withValues(alpha: .97),
      modalBarrierColor: Colors.black54,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: LoopColors.textSecondary,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
        // Jedan veliki gumb: visina 56, puna pilula.
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 17,
          letterSpacing: -0.1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusButton),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: LoopColors.textPrimary,
        backgroundColor: Colors.transparent,
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        side: BorderSide(color: LoopColors.glassBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusButton),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: LoopColors.accent,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: LoopColors.glass,
      selectedColor: kLiveEnabled ? LoopColors.textPrimary : LoopColors.accent,
      side: BorderSide(color: LoopColors.glassBorder),
      showCheckmark: false,
      // Čipovi (filteri, oznake) nisu kapsule: kapsula je samo za tabove.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusChip),
      ),
      labelStyle: TextStyle(
        fontFamily: kFontFamily,
        fontWeight: FontWeight.w600,
        // Odabrani čip je obrnut (bijeli s crnim tekstom u tamnoj temi).
        color: WidgetStateColor.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? (kLiveEnabled ? LoopColors.background : LoopColors.onAccent)
              : LoopColors.textPrimary,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusButton),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      // Pomoćni tekst i greške se lome u više redova (ne režu se).
      helperMaxLines: 3,
      errorMaxLines: 3,
      filled: true,
      fillColor: LoopColors.surfaceHover.withValues(alpha: 0.55),
      labelStyle: TextStyle(color: LoopColors.textSecondary),
      hintStyle: TextStyle(color: LoopColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusButton),
        borderSide: BorderSide(color: LoopColors.glassBorder, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusButton),
        borderSide: BorderSide(color: LoopColors.glassBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusButton),
        borderSide: BorderSide(color: LoopColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusButton),
        borderSide: BorderSide(color: LoopColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? LoopColors.surfaceHover : const Color(0xFF1D1D1F),
      contentTextStyle: TextStyle(
        fontFamily: kFontFamily,
        color: dark ? LoopColors.textPrimary : Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: rounded,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? LoopColors.background : LoopColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primary.withValues(alpha: .10),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: kFontFamily,
          fontSize: 11,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: s.contains(WidgetState.selected)
              ? primary
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
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: kFontFamily,
        color: LoopColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: LoopColors.surface,
        selectedForegroundColor: LoopColors.textPrimary,
        foregroundColor: LoopColors.textSecondary,
        side: BorderSide(color: LoopColors.glassBorder, width: 1),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: LoopColors.surfaceHover,
      thickness: 0.7,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: LoopColors.textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: LoopColors.textPrimary,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 13,
        height: 1.45,
        color: LoopColors.textSecondary,
      ),
    ),
    textTheme: base.textTheme
        .apply(
          fontFamily: kFontFamily,
          bodyColor: LoopColors.textPrimary,
          displayColor: LoopColors.textPrimary,
        )
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.5,
            color: LoopColors.textPrimary,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.45,
            color: LoopColors.textPrimary,
          ),
          displayLarge: _tight(base.textTheme.displayLarge, -1.2),
          displayMedium: _tight(base.textTheme.displayMedium, -1),
          displaySmall: _tight(base.textTheme.displaySmall, -0.8),
          headlineLarge: _tight(base.textTheme.headlineLarge, -0.6),
          headlineMedium: _tight(base.textTheme.headlineMedium, -0.5),
          headlineSmall: _tight(base.textTheme.headlineSmall, -0.4),
          titleLarge: _tight(base.textTheme.titleLarge, -0.3),
          titleMedium: _tight(base.textTheme.titleMedium, -0.2),
        ),
  );
}

/// Listovi aplikacije (plaćanje, novčanik, dostava) uvijek u temi
/// aplikacije — i kad se otvore iz tamnog livea.
Widget appThemed(Widget child) => Theme(data: buildLoopTheme(), child: child);

/// Veliki naslovi i brojevi: gušći razmak slova, kao na Appleovim ekranima.
TextStyle? _tight(TextStyle? style, double tracking) => style?.copyWith(
  fontFamily: kFontFamily,
  letterSpacing: tracking,
  color: LoopColors.textPrimary,
);
