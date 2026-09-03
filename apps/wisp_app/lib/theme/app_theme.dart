import 'dart:io';

import 'package:flutter/material.dart';

enum AppStyle {
  // ignore: constant_identifier_names
  Original,
  // ignore: constant_identifier_names
  Spotify,
  // ignore: constant_identifier_names
  AppleMusic;

  @override
  String toString() => {
    AppStyle.Original: 'Original',
    AppStyle.Spotify: 'Spotify',
    AppStyle.AppleMusic: 'Apple Music',
  }[this]!;

  static AppStyle fromString(String string) {
    return AppStyle.values.firstWhere(
      (e) => e.toString() == string,
      orElse: () => AppStyle.Spotify,
    );
  }
}

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
    AppStyle appStyle = AppStyle.Spotify,
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

    // Apple's font rendering is slightly different, making their SF Pro font
    // appear slightly more spaced out than other platforms. This is a quick
    // fix to make the text look more consistent across platforms.
    double appleLetterSpacing = -0.41;

    TextStyle withAppleLetterSpacing = TextStyle(
      letterSpacing: appleLetterSpacing,
    );

    return ThemeData(
      fontFamily: appStyle == AppStyle.AppleMusic ? 'SF Pro' : 'SpotifyMixUI',
      package: "wisp_assets",
      textTheme: (appStyle == AppStyle.AppleMusic && (Platform.isMacOS || Platform.isIOS)) ? TextTheme(
        bodyLarge: withAppleLetterSpacing,
        bodyMedium: withAppleLetterSpacing,
        bodySmall: withAppleLetterSpacing,
        labelLarge: withAppleLetterSpacing,
        labelMedium: withAppleLetterSpacing,
        labelSmall: withAppleLetterSpacing,
        titleLarge: withAppleLetterSpacing,
        titleMedium: withAppleLetterSpacing,
        titleSmall: withAppleLetterSpacing,
        displayLarge: withAppleLetterSpacing,
        displayMedium: withAppleLetterSpacing,
        displaySmall: withAppleLetterSpacing,
        headlineLarge: withAppleLetterSpacing,
        headlineMedium: withAppleLetterSpacing,
        headlineSmall: withAppleLetterSpacing,
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
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(mouseCursor: clickableCursor),
      ),
      listTileTheme: const ListTileThemeData(
        mouseCursor: clickableCursor,
      ),
      useMaterial3: true,
    );
  }
}
