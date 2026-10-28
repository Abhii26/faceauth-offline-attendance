import 'package:flutter/material.dart';

/// Design tokens for the whole app.
class AppColors {
  AppColors._();

  static const bg = Color(0xFF060A14);
  static const bgAlt = Color(0xFF0B1224);
  // Glass surfaces (translucent so the aurora shows through)
  static const surface = Color(0x99111A2E);
  static const card = Color(0xFF111A2E);
  static const border = Color(0x1FFFFFFF);

  static const accent = Color(0xFF3DFFA2); // mint
  static const accent2 = Color(0xFF22D3EE); // cyan
  static const violet = Color(0xFF8B5CF6);
  static const success = Color(0xFF22E58B);
  static const danger = Color(0xFFFF4D6D);
  static const warning = Color(0xFFFFB020);
  static const info = Color(0xFF5CC8FF);

  static const textDim = Color(0xB3FFFFFF);
  static const textFaint = Color(0x73FFFFFF);

  static const brandGradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const dangerGradient = LinearGradient(
    colors: [Color(0xFFFF4D6D), Color(0xFFFF8A5C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(primary: AppColors.accent, secondary: AppColors.accent2),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle:
          TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.3),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.card,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.accent.withValues(alpha: 0.2),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
