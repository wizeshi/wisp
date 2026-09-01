import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color brandColor = Color(0xFF0096FF);

  static const _scaffoldBackgroundColor = Color(0xFF121212);
  static const _surfaceColor = Color(0xFF181818);

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: brandColor,
      secondary: brandColor,
      surface: _surfaceColor,
    );

    const clickableCursor = WidgetStatePropertyAll<MouseCursor>(SystemMouseCursors.click);

    return ThemeData(
      colorScheme: scheme,
      fontFamily: 'SF Pro',
      scaffoldBackgroundColor: _scaffoldBackgroundColor,
      textButtonTheme: const TextButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
      filledButtonTheme: const FilledButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
      elevatedButtonTheme: const ElevatedButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
      outlinedButtonTheme: const OutlinedButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
      iconButtonTheme: const IconButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
      listTileTheme: const ListTileThemeData(style: ListTileStyle.drawer),
      useMaterial3: true,
    );
  }
}