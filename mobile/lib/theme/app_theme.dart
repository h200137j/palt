/// app_theme.dart — PALT Material Design 3 Theme
///
/// Yellow (#FBBC04) primary, matching the desktop MUI theme exactly.
/// Uses MD3 ColorScheme.fromSeed for automatic tonal palette generation.
library;

import 'package:flutter/material.dart';

/// Google Yellow — matches desktop theme.ts primary.
const kPaltYellow = Color(0xFFFBBC04);

/// Google Blue accent — matches secondary in desktop theme.
const kGoogleBlue = Color(0xFF1A73E8);

/// Near-black for text on yellow (WCAG AA compliant).
const kOnYellow = Color(0xFF1A1400);

ThemeData buildAppTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: kPaltYellow,
    brightness: Brightness.light,
    primary: kPaltYellow,
    onPrimary: kOnYellow,
    secondary: kGoogleBlue,
    onSecondary: Colors.white,
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF202124),
    surfaceContainerHighest: const Color(0xFFF8F9FA),
    error: const Color(0xFFD93025),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,

    // ── Typography ────────────────────────────────────────────────────────
    // MD3 uses Roboto by default on Android — no extra package needed.
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontSize: 57, fontWeight: FontWeight.w400),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w400),
      headlineSmall:  TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
      titleLarge:   TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
      titleMedium:  TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.15),
      titleSmall:   TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
      bodyLarge:    TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5),
      bodyMedium:   TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
      bodySmall:    TextStyle(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
      labelLarge:   TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 1.25),
      labelSmall:   TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.5),
    ),

    // ── App bar ───────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF202124),
      elevation: 0,
      scrolledUnderElevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      titleTextStyle: const TextStyle(
        color: Color(0xFF202124),
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
    ),

    // ── Cards ─────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      color: Colors.white,
    ),

    // ── Chips ─────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    // ── Elevated / Filled buttons ─────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPaltYellow,
        foregroundColor: kOnYellow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),

    // ── FAB ───────────────────────────────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPaltYellow,
      foregroundColor: kOnYellow,
    ),

    // ── Scaffold background ───────────────────────────────────────────────
    scaffoldBackgroundColor: const Color(0xFFF8F9FA),

    // ── Divider ───────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE0E0E0),
      thickness: 1,
    ),
  );
}
