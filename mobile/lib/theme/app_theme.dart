library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kPrimary   = Color(0xFF1A1A1A);
const kSecondary = Color(0xFF6B6B6B);
const kTertiary  = Color(0xFFD4E157);
const kNeutral   = Color(0xFFD9D6D0);
const kSurface   = Color(0xFFF0EDE6);
const kOnPrimary = Color(0xFF1A1A1A);

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: kPrimary,
      onPrimary: Colors.white,
      secondary: kSecondary,
      onSecondary: Colors.white,
      tertiary: kTertiary,
      onTertiary: kOnPrimary,
      surface: kSurface,
      onSurface: kPrimary,
      surfaceContainer: kNeutral,
      surfaceContainerLow: kNeutral,
      surfaceContainerHigh: Color(0xFFC9C6C0),
      error: Color(0xFFD32F2F),
    ),

    textTheme: GoogleFonts.archivoTextTheme(const TextTheme(
      displayLarge:   TextStyle(fontSize: 72,   fontWeight: FontWeight.w800, letterSpacing: -2.88),
      displayMedium:  TextStyle(fontSize: 45,   fontWeight: FontWeight.w800),
      displaySmall:   TextStyle(fontSize: 36,   fontWeight: FontWeight.w800),
      headlineMedium: TextStyle(fontSize: 28,   fontWeight: FontWeight.w800),
      headlineSmall:  TextStyle(fontSize: 24,   fontWeight: FontWeight.w800),
      titleLarge:     TextStyle(fontSize: 22,   fontWeight: FontWeight.w700),
      titleMedium:    TextStyle(fontSize: 16,   fontWeight: FontWeight.w600),
      titleSmall:     TextStyle(fontSize: 14,   fontWeight: FontWeight.w600),
      bodyLarge:      TextStyle(fontSize: 16,   height: 1.5),
      bodyMedium:     TextStyle(fontSize: 15.2, height: 1.5),
      bodySmall:      TextStyle(fontSize: 12,   height: 1.5),
      labelLarge:     TextStyle(fontSize: 14,   fontWeight: FontWeight.w700, letterSpacing: 1.6),
      labelSmall:     TextStyle(fontSize: 11.52, fontWeight: FontWeight.w700, letterSpacing: 1.6),
    )),

    appBarTheme: AppBarTheme(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.archivo(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
    ),

    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
      color: kSurface,
      margin: EdgeInsets.zero,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kTertiary,
        foregroundColor: kOnPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: const RoundedRectangleBorder(),
        textStyle: GoogleFonts.archivo(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: kTertiary,
      foregroundColor: kOnPrimary,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      extendedTextStyle: GoogleFonts.archivo(fontWeight: FontWeight.w700),
    ),

    scaffoldBackgroundColor: kNeutral,

    dividerTheme: const DividerThemeData(
      color: kSecondary,
      thickness: 1,
    ),
  );
}
