// Copyright © 2026 wizeshi

import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

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

  Color get brandColor => switch (this) {
    AppStyle.Spotify => const Color(0xFF1DB954),
    AppStyle.AppleMusic => const Color(0xFFFA243C),
    AppStyle.Original => const Color(0xFF0096FF),
  };

  /// Original on Windows/Linux/Android, Apple Music on iOS/macOS.
  static AppStyle get platformDefault =>
      (Platform.isIOS || Platform.isMacOS)
      ? AppStyle.AppleMusic
      : AppStyle.Original;

  String toStorageString() => name;

  static AppStyle fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return platformDefault;
    final lower = raw.trim().toLowerCase();
    for (final style in AppStyle.values) {
      if (style.name.toLowerCase() == lower ||
          style.toString().toLowerCase() == lower) {
        return style;
      }
    }
    return platformDefault;
  }

  static AppStyle fromString(String string) => fromStorage(string);
}

/// Design tokens capturing platform-specific styles for Spotify, Apple Music,
/// and future Wisp Original (M3E/Liquid Glass).
@immutable
class WispStyleTokens extends ThemeExtension<WispStyleTokens> {
  final AppStyle style;
  final IconData playIcon;
  final IconData pauseIcon;
  final IconData playNextIcon;
  final IconData playPrevIcon;
  final IconData shuffleIcon;
  final IconData repeatIcon;
  final IconData connectIcon;
  final IconData moreIcon;
  final IconData settingsIcon;
  final IconData searchIcon;
  final IconData libraryIcon;
  final IconData homeIcon;
  final BorderRadius cardRadius;
  final BorderRadius artworkRadius;
  final BorderRadius buttonRadius;
  final IconData repeatOneIcon;
  final IconData volumeOffIcon;
  final IconData volumeDownIcon;
  final IconData volumeUpIcon;
  final IconData lyricsIcon;
  final IconData queueIcon;
  final IconData sidebarIcon;
  final IconData fullscreenIcon;
  final IconData personIcon;
  final IconData personAddIcon;
  final double playerControlSpacing;
  final double playerVolumeSpacing;
  final double trackRowDurationWidth;
  
  final bool isAppleMode;
  bool get isApple => isAppleMode;
  bool get isSpotify => style == AppStyle.Spotify;
  bool get isOriginal => style == AppStyle.Original;

  const WispStyleTokens({
    required this.style,
    this.isAppleMode = false,
    required this.playIcon,
    required this.pauseIcon,
    required this.playNextIcon,
    required this.playPrevIcon,
    required this.shuffleIcon,
    required this.repeatIcon,
    required this.connectIcon,
    required this.moreIcon,
    required this.settingsIcon,
    required this.searchIcon,
    required this.libraryIcon,
    required this.homeIcon,
    required this.cardRadius,
    required this.artworkRadius,
    required this.buttonRadius,
    required this.repeatOneIcon,
    required this.volumeOffIcon,
    required this.volumeDownIcon,
    required this.volumeUpIcon,
    required this.lyricsIcon,
    required this.queueIcon,
    required this.sidebarIcon,
    required this.fullscreenIcon,
    required this.personIcon,
    required this.personAddIcon,
    required this.playerControlSpacing,
    required this.playerVolumeSpacing,
    required this.trackRowDurationWidth,
  });

  factory WispStyleTokens.fromStyle(AppStyle style) {
    switch (style) {
      case AppStyle.AppleMusic:
        return const WispStyleTokens(
          style: AppStyle.AppleMusic,
          isAppleMode: true,
          playIcon: CupertinoIcons.play_arrow_solid,
          pauseIcon: CupertinoIcons.pause_solid,
          playNextIcon: CupertinoIcons.forward_fill,
          playPrevIcon: CupertinoIcons.backward_fill,
          shuffleIcon: CupertinoIcons.shuffle,
          repeatIcon: CupertinoIcons.repeat,
          connectIcon: CupertinoIcons.antenna_radiowaves_left_right,
          moreIcon: CupertinoIcons.ellipsis,
          settingsIcon: CupertinoIcons.settings,
          searchIcon: CupertinoIcons.search,
          libraryIcon: CupertinoIcons.square_stack_3d_up,
          homeIcon: CupertinoIcons.house,
          cardRadius: BorderRadius.all(Radius.circular(10)),
          artworkRadius: BorderRadius.all(Radius.circular(8)),
          buttonRadius: BorderRadius.all(Radius.circular(8)),
          repeatOneIcon: CupertinoIcons.repeat_1,
          volumeOffIcon: CupertinoIcons.speaker_slash,
          volumeDownIcon: CupertinoIcons.speaker_1,
          volumeUpIcon: CupertinoIcons.speaker_3,
          lyricsIcon: CupertinoIcons.quote_bubble,
          queueIcon: CupertinoIcons.list_bullet,
          sidebarIcon: CupertinoIcons.sidebar_right,
          fullscreenIcon: CupertinoIcons.arrow_up_left_arrow_down_right,
          personIcon: CupertinoIcons.person_fill,
          personAddIcon: CupertinoIcons.person_add,
          playerControlSpacing: 24.0,
          playerVolumeSpacing: 6.0,
          trackRowDurationWidth: 70.0,
        );
      case AppStyle.Original:
        return const WispStyleTokens(
          style: AppStyle.Original,
          isAppleMode: false,
          playIcon: Icons.play_arrow,
          pauseIcon: Icons.pause,
          playNextIcon: Icons.skip_next,
          playPrevIcon: Icons.skip_previous,
          shuffleIcon: Icons.shuffle,
          repeatIcon: Icons.repeat,
          connectIcon: Icons.cast_connected,
          moreIcon: Icons.more_horiz,
          settingsIcon: Icons.settings_outlined,
          searchIcon: Icons.search,
          libraryIcon: Icons.library_music,
          homeIcon: Icons.home,
          cardRadius: BorderRadius.all(Radius.circular(8)),
          artworkRadius: BorderRadius.all(Radius.circular(4)),
          buttonRadius: BorderRadius.all(Radius.circular(500)),
          repeatOneIcon: Icons.repeat_one,
          volumeOffIcon: Icons.volume_off,
          volumeDownIcon: Icons.volume_down,
          volumeUpIcon: Icons.volume_up,
          lyricsIcon: Icons.music_note,
          queueIcon: Icons.queue_music,
          sidebarIcon: Icons.space_dashboard_outlined,
          fullscreenIcon: Icons.fullscreen,
          personIcon: Icons.person,
          personAddIcon: Icons.person_add_alt_1,
          playerControlSpacing: 8.0,
          playerVolumeSpacing: 4.0,
          trackRowDurationWidth: 80.0,
        );
      case AppStyle.Spotify:
        return const WispStyleTokens(
          style: AppStyle.Spotify,
          playIcon: Icons.play_arrow,
          pauseIcon: Icons.pause,
          playNextIcon: Icons.skip_next,
          playPrevIcon: Icons.skip_previous,
          shuffleIcon: Icons.shuffle,
          repeatIcon: Icons.repeat,
          connectIcon: Icons.cast_connected,
          moreIcon: Icons.more_horiz,
          settingsIcon: Icons.settings_outlined,
          searchIcon: Icons.search,
          libraryIcon: Icons.library_music,
          homeIcon: Icons.home,
          cardRadius: BorderRadius.all(Radius.circular(8)),
          artworkRadius: BorderRadius.all(Radius.circular(4)),
          buttonRadius: BorderRadius.all(Radius.circular(500)),
          repeatOneIcon: Icons.repeat_one,
          volumeOffIcon: Icons.volume_off,
          volumeDownIcon: Icons.volume_down,
          volumeUpIcon: Icons.volume_up,
          lyricsIcon: Icons.music_note,
          queueIcon: Icons.queue_music,
          sidebarIcon: Icons.space_dashboard_outlined,
          fullscreenIcon: Icons.fullscreen,
          personIcon: Icons.person,
          personAddIcon: Icons.person_add_alt_1,
          playerControlSpacing: 8.0,
          playerVolumeSpacing: 4.0,
          trackRowDurationWidth: 80.0,
        );
    }
  }

  @override
  ThemeExtension<WispStyleTokens> copyWith({
    AppStyle? style,
    bool? isAppleMode,
    IconData? playIcon,
    IconData? pauseIcon,
    IconData? playNextIcon,
    IconData? playPrevIcon,
    IconData? shuffleIcon,
    IconData? repeatIcon,
    IconData? connectIcon,
    IconData? moreIcon,
    IconData? settingsIcon,
    IconData? searchIcon,
    IconData? libraryIcon,
    IconData? homeIcon,
    BorderRadius? cardRadius,
    BorderRadius? artworkRadius,
    BorderRadius? buttonRadius,
    IconData? repeatOneIcon,
    IconData? volumeOffIcon,
    IconData? volumeDownIcon,
    IconData? volumeUpIcon,
    IconData? lyricsIcon,
    IconData? queueIcon,
    IconData? sidebarIcon,
    IconData? fullscreenIcon,
    IconData? personIcon,
    IconData? personAddIcon,
    double? playerControlSpacing,
    double? playerVolumeSpacing,
    double? trackRowDurationWidth,
  }) {
    return WispStyleTokens(
      style: style ?? this.style,
      isAppleMode: isAppleMode ?? this.isAppleMode,
      playIcon: playIcon ?? this.playIcon,
      pauseIcon: pauseIcon ?? this.pauseIcon,
      playNextIcon: playNextIcon ?? this.playNextIcon,
      playPrevIcon: playPrevIcon ?? this.playPrevIcon,
      shuffleIcon: shuffleIcon ?? this.shuffleIcon,
      repeatIcon: repeatIcon ?? this.repeatIcon,
      connectIcon: connectIcon ?? this.connectIcon,
      moreIcon: moreIcon ?? this.moreIcon,
      settingsIcon: settingsIcon ?? this.settingsIcon,
      searchIcon: searchIcon ?? this.searchIcon,
      libraryIcon: libraryIcon ?? this.libraryIcon,
      homeIcon: homeIcon ?? this.homeIcon,
      cardRadius: cardRadius ?? this.cardRadius,
      artworkRadius: artworkRadius ?? this.artworkRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      repeatOneIcon: repeatOneIcon ?? this.repeatOneIcon,
      volumeOffIcon: volumeOffIcon ?? this.volumeOffIcon,
      volumeDownIcon: volumeDownIcon ?? this.volumeDownIcon,
      volumeUpIcon: volumeUpIcon ?? this.volumeUpIcon,
      lyricsIcon: lyricsIcon ?? this.lyricsIcon,
      queueIcon: queueIcon ?? this.queueIcon,
      sidebarIcon: sidebarIcon ?? this.sidebarIcon,
      fullscreenIcon: fullscreenIcon ?? this.fullscreenIcon,
      personIcon: personIcon ?? this.personIcon,
      personAddIcon: personAddIcon ?? this.personAddIcon,
      playerControlSpacing: playerControlSpacing ?? this.playerControlSpacing,
      playerVolumeSpacing: playerVolumeSpacing ?? this.playerVolumeSpacing,
      trackRowDurationWidth: trackRowDurationWidth ?? this.trackRowDurationWidth,
    );
  }

  @override
  ThemeExtension<WispStyleTokens> lerp(
    covariant ThemeExtension<WispStyleTokens>? other,
    double t,
  ) {
    if (other is! WispStyleTokens) return this;
    return t < 0.5 ? this : other;
  }
}

extension WispStyleContext on BuildContext {
  WispStyleTokens get tokens =>
      Theme.of(this).extension<WispStyleTokens>() ??
      WispStyleTokens.fromStyle(AppStyle.Spotify);
  AppStyle get appStyle => tokens.style;
}

/// Centralized theme configuration for the app.
class AppTheme {
  AppTheme._();

  static const Color brandColor = Color(0xFF0096FF);

  static const Color _scaffoldBackground = Color(0xFF121212);
  static const Color _surface = Color(0xFF181818);

  static ThemeData dark({
    ColorScheme? paletteOverride,
    AppStyle appStyle = AppStyle.Spotify,
  }) {
    final styleBrandColor = appStyle.brandColor;
    final fallback = ColorScheme.dark(
      primary: styleBrandColor,
      secondary: styleBrandColor,
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

    double appleLetterSpacing = -0.41;

    TextStyle withAppleLetterSpacing = TextStyle(
      letterSpacing: appleLetterSpacing,
    );

    String fontFamily = switch (appStyle) {
      AppStyle.AppleMusic => 'SF Pro',
      AppStyle.Spotify => 'SpotifyMixUI',
      AppStyle.Original => 'Google Sans',
    };

    return ThemeData(
      fontFamily: fontFamily,
      package: "wisp_assets",
      textTheme:
            appStyle == AppStyle.AppleMusic &&
            (Platform.isMacOS || Platform.isIOS)
          ? TextTheme(
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
            )
          : null,
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
      listTileTheme: const ListTileThemeData(mouseCursor: clickableCursor),
      checkboxTheme: const CheckboxThemeData(mouseCursor: clickableCursor),
      useMaterial3: true,
      extensions: [
        WispStyleTokens.fromStyle(appStyle),
      ],
    );
  }
}
