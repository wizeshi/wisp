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

  static ThemeData dark({Color? primaryOverride}) {
    final primary = primaryOverride ?? brandColor;
    final colorScheme = ColorScheme.dark(
      primary: primary,
      secondary: primary,
      surface: _surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    );
    const clickableCursor = WidgetStatePropertyAll<MouseCursor>(
      SystemMouseCursors.click,
    );

    return ThemeData(
      fontFamily: "SpotifyMixUI",
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _scaffoldBackground,
      cardColor: _surface,
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(mouseCursor: clickableCursor),
      ),
      elevatedButtonTheme: const ElevatedButtonThemeData(
        style: ButtonStyle(mouseCursor: clickableCursor),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(mouseCursor: clickableCursor),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(mouseCursor: clickableCursor),
      ),
      listTileTheme: const ListTileThemeData(
        mouseCursor: clickableCursor,
      ),
      useMaterial3: true,
    );
  }
}
