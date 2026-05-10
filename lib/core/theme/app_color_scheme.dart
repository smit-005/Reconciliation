import 'package:flutter/material.dart';

class AppColorScheme {
  static const Color primary = Color(0xFF1E4E8C);
  static const Color secondary = Color(0xFF0F766E);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF7F9FC);
  static const Color surfaceMuted = Color(0xFFF1F5F9);
  static const Color background = Color(0xFFF5F7FA);
  static const Color border = Color(0xFFD8DEE8);
  static const Color divider = Color(0xFFE2E8F0);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);

  static const Color success = Color(0xFF166534);
  static const Color successSoft = Color(0xFFEAF7EF);
  static const Color warning = Color(0xFF9A5B13);
  static const Color warningSoft = Color(0xFFFFF7ED);
  static const Color danger = Color(0xFFB42318);
  static const Color dangerSoft = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF1E4E8C);
  static const Color infoSoft = Color(0xFFEFF6FF);

  static ColorScheme get light =>
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        surface: surface,
      ).copyWith(
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: Colors.white,
        error: danger,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
      );
}
