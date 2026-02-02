import 'package:flutter/material.dart';

/// Centralized theme configuration for the app.
///
/// Change [brandColor] to update the app-wide accent color.
class AppTheme {
  AppTheme._();

  /// App accent/brand color.
  static const Color brandColor = Color(0xFF0096FF);

  static const Color _scaffoldBackground = Color(0xFF121212);
  static const Color _surface = Color(0xFF181818);

  static ThemeData dark() {
    final colorScheme = const ColorScheme.dark(
      primary: brandColor,
      secondary: brandColor,
      surface: _surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _scaffoldBackground,
      cardColor: _surface,
      useMaterial3: true,
    );
  }
}
