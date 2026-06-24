/// ALOQA — Material 3 theme (logo blue/indigo palette).
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// Primary brand indigo (matches logo background #1A237E used in splash).
  static const Color brandIndigo = Color(0xFF1A237E);
  static const Color brandBlue = Color(0xFF2962FF);
  static const Color brandLight = Color(0xFF5C6BC0);
  static const Color surfaceDark = Color(0xFF0E1116);
  static const Color danger = Color(0xFFE53935);
  static const Color success = Color(0xFF2E7D32);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandIndigo,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.brandIndigo,
      secondary: AppColors.brandBlue,
    );
    return _base(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandIndigo,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.brandLight,
      secondary: AppColors.brandBlue,
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        // NOTE: use withOpacity (Flutter 3.22) — withValues is NOT available.
        color: scheme.surfaceContainerHighest.withOpacity(0.4),
      ),
    );
  }
}
