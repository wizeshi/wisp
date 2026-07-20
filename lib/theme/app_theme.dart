import 'dart:io';

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

  static ThemeData dark({
    ColorScheme? paletteOverride,
    String appStyle = 'Spotify',
  }) {
    final fallback = ColorScheme.dark(
      primary: brandColor,
      secondary: brandColor,
      surface: _surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    );
    final colorScheme = (paletteOverride ?? fallback).copyWith(
      surface: _surface,
      onSurface: Colors.white,
    );
    const clickableCursor = WidgetStatePropertyAll<MouseCursor>(
      SystemMouseCursors.click,
    );

    // MacOS' font rendering is slightly different, making their SF Pro font
    // appear slightly more spaced out than other platforms. This is a quick
    // fix to make the text look more consistent across platforms.
    double macOSletterSpacing = -0.41;

    return ThemeData(
      fontFamily: appStyle == 'Apple Music' ? 'SF Pro' : 'SpotifyMixUI',
      textTheme: (appStyle == "Apple Music" && Platform.isMacOS) ? TextTheme(
        bodyMedium: TextStyle(
          letterSpacing: macOSletterSpacing,
        ),
        bodySmall: TextStyle(
          letterSpacing: macOSletterSpacing,
        ),
        labelSmall: TextStyle(
          letterSpacing: macOSletterSpacing,
        ),
        labelMedium: TextStyle(
          letterSpacing: macOSletterSpacing,
        ),
      ) : null,
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
