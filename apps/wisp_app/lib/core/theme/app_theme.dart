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
    AppStyle.AppleMusic => const Color(0xFFFF4E6B),
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
/// and future wisp Original (M3E/Liquid Glass).
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
          playerControlSpacing: 8.0,
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
  WispColors get colors =>
      Theme.of(this).extension<WispColors>() ??
      WispColors.fromTheme(Theme.of(this).brightness, appStyle);
}

/// Semantic color tokens for surfaces, chrome, borders, and text across
/// Dark and Light themes and [AppStyle] variants.
@immutable
class WispColors extends ThemeExtension<WispColors> {
  final Brightness brightness;

  /// Main scrolling page background.
  final Color canvas;

  /// Top desktop title bar / outer shell chrome.
  final Color chrome;

  /// Left navigation sidebar & right sidebar background.
  final Color sidebar;

  /// Desktop bottom player bar background.
  final Color playerBar;

  /// Cards, settings rows, section containers.
  final Color surface;

  /// Dialogs, bottom sheets, context menus, popovers, dropdown menus.
  final Color surfaceElevated;

  /// Search pills, text fields, chips, inactive pills.
  final Color inputFill;

  /// Faint tile fill (e.g. home quick tiles).
  final Color surfaceSubtle;

  /// Hover/pressed tint overlay.
  final Color hoverOverlay;

  /// 1px hairline pane/card borders and dividers.
  final Color borderSubtle;

  /// Stronger borders for outlined buttons and inputs.
  final Color border;

  /// Primary headings, titles, active icons.
  final Color textPrimary;

  /// Subtitles, secondary labels, action icons.
  final Color textSecondary;

  /// Hints, timestamps, section headers, disabled icons.
  final Color textMuted;

  /// Drop shadow color.
  final Color shadow;

  /// Placeholder fill behind missing/loading artwork.
  final Color artworkPlaceholder;

  /// Inactive track color for sliders and progress bars.
  final Color trackInactive;

  bool get isDark => brightness == Brightness.dark;

  const WispColors({
    required this.brightness,
    required this.canvas,
    required this.chrome,
    required this.sidebar,
    required this.playerBar,
    required this.surface,
    required this.surfaceElevated,
    required this.inputFill,
    required this.surfaceSubtle,
    required this.hoverOverlay,
    required this.borderSubtle,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.shadow,
    required this.artworkPlaceholder,
    required this.trackInactive,
  });

  /// Returns a legible foreground color on top of [background].
  Color onColor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF141416);

  /// Adapts a cover-art [accent] color for detail page headers.
  Color tintedHeader(Color accent) {
    if (isDark) return accent;
    return Color.lerp(canvas, accent, 0.24) ?? accent;
  }

  /// Adapts a cover-art [accent] color for subtle header action gradients.
  Color tintedSubtle(Color accent) {
    if (isDark) {
      final hsl = HSLColor.fromColor(accent);
      return hsl
          .withLightness((hsl.lightness * 0.5).clamp(0.0, 1.0))
          .toColor();
    }
    return Color.lerp(canvas, accent, 0.14) ?? accent;
  }

  factory WispColors.fromTheme(Brightness brightness, AppStyle style) {
    if (brightness == Brightness.dark) {
      final chrome = switch (style) {
        AppStyle.Spotify => const Color(0xFF000000),
        AppStyle.Original => const Color(0xFF0C0C0E),
        AppStyle.AppleMusic => const Color(0xFF101012),
      };
      final sidebar = switch (style) {
        AppStyle.Spotify => const Color(0xFF0F0F0F),
        AppStyle.Original => const Color(0xFF101012),
        AppStyle.AppleMusic => const Color(0xFF141416),
      };
      final playerBar = switch (style) {
        AppStyle.Spotify => const Color(0xFF000000),
        AppStyle.Original => const Color(0xFF141414),
        AppStyle.AppleMusic => const Color(0xFF141414),
      };
      final surface = style == AppStyle.AppleMusic
          ? const Color(0xFF1C1C1E)
          : const Color(0xFF181818);
      final surfaceElevated = style == AppStyle.AppleMusic
          ? const Color(0xFF262628)
          : const Color(0xFF242424);
      final inputFill = switch (style) {
        AppStyle.AppleMusic => const Color(0xFF2C2C2E),
        AppStyle.Original => const Color(0xFF26262A),
        AppStyle.Spotify => const Color(0xFF282828),
      };

      return WispColors(
        brightness: Brightness.dark,
        canvas: const Color(0xFF121212),
        chrome: chrome,
        sidebar: sidebar,
        playerBar: playerBar,
        surface: surface,
        surfaceElevated: surfaceElevated,
        inputFill: inputFill,
        surfaceSubtle: const Color(0x0DFFFFFF),
        hoverOverlay: const Color(0x14FFFFFF),
        borderSubtle: const Color(0x1AFFFFFF),
        border: const Color(0x38FFFFFF),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFFB3B3B3),
        textMuted: const Color(0xFF7A7A7A),
        shadow: const Color(0x66000000),
        artworkPlaceholder: const Color(0xFF262626),
        trackInactive: const Color(0xFF333333),
      );
    }

    final chrome = switch (style) {
      AppStyle.Spotify => const Color(0xFFEFEFF2),
      AppStyle.Original => const Color(0xFFF2F2F5),
      AppStyle.AppleMusic => const Color(0xFFF5F5F7),
    };
    final sidebar = switch (style) {
      AppStyle.Spotify => const Color(0xFFF4F4F6),
      AppStyle.Original => const Color(0xFFF3F3F7),
      AppStyle.AppleMusic => const Color(0xFFF5F5F7),
    };
    final playerBar = switch (style) {
      AppStyle.Spotify => const Color(0xFFF2F2F4),
      AppStyle.Original => const Color(0xFFF5F5F8),
      AppStyle.AppleMusic => const Color(0xFFF7F7F9),
    };
    final surface = switch (style) {
      AppStyle.Spotify => const Color(0xFFF3F3F5),
      AppStyle.Original => const Color(0xFFF4F4F8),
      AppStyle.AppleMusic => const Color(0xFFF5F5F7),
    };
    final inputFill = switch (style) {
      AppStyle.Spotify => const Color(0xFFE8E8EB),
      AppStyle.Original => const Color(0xFFE9E9F0),
      AppStyle.AppleMusic => const Color(0xFFE8E8ED),
    };

    return WispColors(
      brightness: Brightness.light,
      canvas: const Color(0xFFFFFFFF),
      chrome: chrome,
      sidebar: sidebar,
      playerBar: playerBar,
      surface: surface,
      surfaceElevated: const Color(0xFFFFFFFF),
      inputFill: inputFill,
      surfaceSubtle: const Color(0x0A000000),
      hoverOverlay: const Color(0x0F000000),
      borderSubtle: const Color(0x17000000),
      border: const Color(0x2E000000),
      textPrimary: const Color(0xFF141416),
      textSecondary: const Color(0xFF52525B),
      textMuted: const Color(0xFF71717A),
      shadow: const Color(0x1F000000),
      artworkPlaceholder: const Color(0xFFE4E4E9),
      trackInactive: const Color(0xFFD8D8DF),
    );
  }

  @override
  ThemeExtension<WispColors> copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? chrome,
    Color? sidebar,
    Color? playerBar,
    Color? surface,
    Color? surfaceElevated,
    Color? inputFill,
    Color? surfaceSubtle,
    Color? hoverOverlay,
    Color? borderSubtle,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? shadow,
    Color? artworkPlaceholder,
    Color? trackInactive,
  }) {
    return WispColors(
      brightness: brightness ?? this.brightness,
      canvas: canvas ?? this.canvas,
      chrome: chrome ?? this.chrome,
      sidebar: sidebar ?? this.sidebar,
      playerBar: playerBar ?? this.playerBar,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      inputFill: inputFill ?? this.inputFill,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      hoverOverlay: hoverOverlay ?? this.hoverOverlay,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      shadow: shadow ?? this.shadow,
      artworkPlaceholder: artworkPlaceholder ?? this.artworkPlaceholder,
      trackInactive: trackInactive ?? this.trackInactive,
    );
  }

  @override
  ThemeExtension<WispColors> lerp(
    covariant ThemeExtension<WispColors>? other,
    double t,
  ) {
    if (other is! WispColors) return this;
    return WispColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      chrome: Color.lerp(chrome, other.chrome, t) ?? chrome,
      sidebar: Color.lerp(sidebar, other.sidebar, t) ?? sidebar,
      playerBar: Color.lerp(playerBar, other.playerBar, t) ?? playerBar,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
          surfaceElevated,
      inputFill: Color.lerp(inputFill, other.inputFill, t) ?? inputFill,
      surfaceSubtle:
          Color.lerp(surfaceSubtle, other.surfaceSubtle, t) ?? surfaceSubtle,
      hoverOverlay:
          Color.lerp(hoverOverlay, other.hoverOverlay, t) ?? hoverOverlay,
      borderSubtle:
          Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      border: Color.lerp(border, other.border, t) ?? border,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      shadow: Color.lerp(shadow, other.shadow, t) ?? shadow,
      artworkPlaceholder:
          Color.lerp(artworkPlaceholder, other.artworkPlaceholder, t) ??
          artworkPlaceholder,
      trackInactive:
          Color.lerp(trackInactive, other.trackInactive, t) ?? trackInactive,
    );
  }
}

/// Centralized theme configuration for the app.
class AppTheme {
  AppTheme._();

  static const Color brandColor = Color(0xFF0096FF);

  static ThemeData dark({
    ColorScheme? paletteOverride,
    AppStyle appStyle = AppStyle.Spotify,
  }) => _build(
    Brightness.dark,
    paletteOverride: paletteOverride,
    appStyle: appStyle,
  );

  static ThemeData light({
    ColorScheme? paletteOverride,
    AppStyle appStyle = AppStyle.Spotify,
  }) => _build(
    Brightness.light,
    paletteOverride: paletteOverride,
    appStyle: appStyle,
  );

  static ThemeData fromBrightness(
    Brightness brightness, {
    ColorScheme? paletteOverride,
    AppStyle appStyle = AppStyle.Spotify,
  }) => _build(
    brightness,
    paletteOverride: paletteOverride,
    appStyle: appStyle,
  );

  static Color _brandColorForBrightness(AppStyle style, Brightness brightness) {
    if (brightness == Brightness.dark) return style.brandColor;
    return switch (style) {
      AppStyle.Spotify => const Color(0xFF159A43),
      AppStyle.AppleMusic => const Color(0xFFE63956),
      AppStyle.Original => const Color(0xFF0077CC),
    };
  }

  static ThemeData _build(
    Brightness brightness, {
    ColorScheme? paletteOverride,
    required AppStyle appStyle,
  }) {
    final colors = WispColors.fromTheme(brightness, appStyle);
    final styleBrandColor = _brandColorForBrightness(appStyle, brightness);

    final fallback = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: styleBrandColor,
            secondary: styleBrandColor,
            surface: colors.canvas,
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: colors.textPrimary,
          )
        : ColorScheme.light(
            primary: styleBrandColor,
            secondary: styleBrandColor,
            surface: colors.canvas,
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: colors.textPrimary,
          );

    final colorScheme = (paletteOverride ?? fallback).copyWith(
      brightness: brightness,
      surface: colors.canvas,
      onSurface: colors.textPrimary,
      onSurfaceVariant: colors.textSecondary,
      surfaceContainerLowest: colors.chrome,
      surfaceContainerLow: colors.sidebar,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.surfaceElevated,
      surfaceContainerHighest: colors.inputFill,
      outline: colors.border,
      outlineVariant: colors.borderSubtle,
    );

    const clickableCursor = WidgetStatePropertyAll<MouseCursor>(
      SystemMouseCursors.click,
    );

    const appleLetterSpacing = -0.41;
    const withAppleLetterSpacing = TextStyle(
      letterSpacing: appleLetterSpacing,
    );

    final fontFamily = switch (appStyle) {
      AppStyle.AppleMusic => 'SF Pro',
      AppStyle.Spotify => 'SpotifyMixUI',
      AppStyle.Original => 'Google Sans',
    };

    return ThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
      package: 'wisp_assets',
      textTheme:
          appStyle == AppStyle.AppleMusic &&
              (Platform.isMacOS || Platform.isIOS)
          ? const TextTheme(
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
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      cardColor: colors.surface,
      dividerColor: colors.borderSubtle,
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderSubtle,
        thickness: 1,
      ),
      iconTheme: IconThemeData(color: colors.textPrimary),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: colors.inputFill,
        hintStyle: TextStyle(color: colors.textMuted),
        labelStyle: TextStyle(color: colors.textSecondary),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: colorScheme.primary,
        scaffoldBackgroundColor: colors.canvas,
        barBackgroundColor: colors.chrome,
      ),
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
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(mouseCursor: clickableCursor),
      ),
      useMaterial3: true,
      extensions: [
        WispStyleTokens.fromStyle(appStyle),
        colors,
      ],
    );
  }
}
