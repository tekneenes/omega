import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Executive Light Theme Palette - Emerald & Mint Tones
  static const Color background = Color(0xFFF6F9F8); // Very soft sage white
  static const Color surface = Color(0xFFFFFFFF); // Pristine white card surface
  static const Color surfaceMuted = Color(0xFFEDF5F2); // Soft mint tint container
  static const Color borderLight = Color(0xFFE2E8F0); // Subtle slate border

  // Brand Emerald & Mint Greens
  static const Color primary = Color(0xFF059669); // Rich Emerald Green
  static const Color primaryLight = Color(0xFF10B981); // Bright Mint Green
  static const Color primarySoft = Color(0xFFD1FAE5); // Gentle Mint Soft Fill
  static const Color secondary = Color(0xFF0D9488); // Teal Emerald Accent
  static const Color accentRose = Color(0xFFEF4444); // Soft Red for Call Drop

  // Typography Colors
  static const Color textPrimary = Color(0xFF0F172A); // Rich Charcoal Text
  static const Color textSecondary = Color(0xFF475569); // Slate Grey Subtitles
  static const Color textMuted = Color(0xFF94A3B8); // Soft Grey Descriptions

  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: primaryLight,
        surface: surface,
        error: accentRose,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.light().textTheme,
      ).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0.5,
        centerTitle: true,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shadowColor: const Color(0x0F059669),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color(0x33059669),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primaryLight, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),
    );
  }

  // Backward compatibility getter
  static ThemeData get darkTheme => lightTheme;
}
