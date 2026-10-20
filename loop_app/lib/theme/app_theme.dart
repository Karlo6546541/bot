import 'package:flutter/material.dart';

/// Paleta boja LOOP-a.
class LoopColors {
  static const background = Color(0xFF0A0E17);
  static const surface = Color(0xFF141A27);
  static const surfaceHover = Color(0xFF1C2435);
  static const accent = Color(0xFF00E5A0);
  static const textPrimary = Color(0xFFE8EDF5);
  static const textSecondary = Color(0xFF8B95A8);
  static const error = Color(0xFFFF4D6D);
  static const success = Color(0xFF00E5A0);

  /// Akcent admin panela — namjerno drugačiji da je admin vizualno odvojen.
  static const admin = Color(0xFFFFB020);
}

const double kRadius = 16;

/// Tamna Material 3 tema.
ThemeData buildLoopTheme({Color accent = LoopColors.accent}) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: accent,
        onPrimary: LoopColors.background,
        surface: LoopColors.surface,
        onSurface: LoopColors.textPrimary,
        onSurfaceVariant: LoopColors.textSecondary,
        surfaceContainerHighest: LoopColors.surfaceHover,
        error: LoopColors.error,
      );

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(kRadius),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LoopColors.background,
    canvasColor: LoopColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: LoopColors.background,
      foregroundColor: LoopColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: LoopColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: rounded,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: LoopColors.surface,
      shape: rounded,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: LoopColors.background,
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: rounded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: LoopColors.textPrimary,
        minimumSize: const Size(64, 52),
        side: const BorderSide(color: LoopColors.surfaceHover, width: 1.5),
        shape: rounded,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: LoopColors.background,
      shape: rounded,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LoopColors.surface,
      labelStyle: const TextStyle(color: LoopColors.textSecondary),
      hintStyle: const TextStyle(color: LoopColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadius),
        borderSide: const BorderSide(color: LoopColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: LoopColors.surfaceHover,
      contentTextStyle: const TextStyle(color: LoopColors.textPrimary),
      shape: rounded,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: LoopColors.surface,
      indicatorColor: accent.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? accent
              : LoopColors.textSecondary,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: LoopColors.surface,
      indicatorColor: accent.withValues(alpha: 0.18),
      selectedIconTheme: IconThemeData(color: accent),
      unselectedIconTheme: const IconThemeData(color: LoopColors.textSecondary),
      selectedLabelTextStyle: TextStyle(
        color: accent,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: LoopColors.textSecondary,
      ),
    ),
    dividerTheme: const DividerThemeData(color: LoopColors.surfaceHover),
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: LoopColors.textPrimary,
      displayColor: LoopColors.textPrimary,
    ),
  );
}
