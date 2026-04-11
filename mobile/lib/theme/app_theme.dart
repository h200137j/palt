library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Google Yellow — primary brand color.
const kPaltYellow = Color(0xFFFBBC04);

/// Google Blue accent — for complementary actions.
const kGoogleBlue = Color(0xFF1A73E8);

/// Deep Charcoal for readable text on yellow.
const kOnYellow = Color(0xFF1A1400);

/// Premium Surface Color (Off-white)
const kSurface = Color(0xFFFDFDFD);

/// Gradient Amber for headers
const kAmberGradient = LinearGradient(
  colors: [Color(0xFFFBBC04), Color(0xFFF9A825)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

ThemeData buildAppTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: kPaltYellow,
    brightness: Brightness.light,
    primary: kPaltYellow,
    onPrimary: kOnYellow,
    secondary: kGoogleBlue,
    onSecondary: Colors.white,
    surface: kSurface,
    onSurface: const Color(0xFF1F1F1F),
    surfaceContainer: const Color(0xFFF3F5F7),
    surfaceContainerLow: const Color(0xFFF8F9FA),
    surfaceContainerHigh: const Color(0xFFE9ECEF),
    error: const Color(0xFFD32F2F),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,

    // ── Typography ────────────────────────────────────────────────────────
    // Using Outfit for a modern, geometric Google-like feel.
    textTheme: GoogleFonts.outfitTextTheme(const TextTheme(
      displayLarge:  TextStyle(fontSize: 57, fontWeight: FontWeight.bold, letterSpacing: -1.0),
      displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.bold, letterSpacing: -0.8),
      displaySmall:  TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: -0.5),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.5),
      headlineSmall:  TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge:   TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      titleMedium:  TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      titleSmall:   TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      bodyLarge:    TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.2),
      bodyMedium:   TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.2),
      bodySmall:    TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      labelLarge:   TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      labelSmall:   TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
    )),

    // ── App bar ───────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: kSurface,
      foregroundColor: const Color(0xFF1F1F1F),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.outfit(
        color: const Color(0xFF1F1F1F),
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    ),

    // ── Cards ─────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: Colors.black.withOpacity(0.04), width: 1),
      ),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
    ),

    // ── Buttons ─────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kPaltYellow,
        foregroundColor: kOnYellow,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),

    // ── FAB ───────────────────────────────────────────────────────────────
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: kPaltYellow,
      foregroundColor: kOnYellow,
      elevation: 3,
      hoverElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),

    // ── Scaffold background ───────────────────────────────────────────────
    scaffoldBackgroundColor: const Color(0xFFF9FAFB),

    // ── Divider ───────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      color: Colors.black.withOpacity(0.05),
      thickness: 1,
      indent: 16,
      endIndent: 16,
    ),
  );
}
