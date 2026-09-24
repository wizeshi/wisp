// Copyright © 2026 wizeshi

import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'full_player/styles/apple_music_full_player.dart';
import 'full_player/styles/original_full_player.dart';
import 'full_player/styles/spotify_desktop_full_player.dart';
import 'full_player/styles/spotify_full_player.dart';

// Re-export styles and components for external callers
export 'full_player/styles/apple_music_full_player.dart';
export 'full_player/styles/original_full_player.dart';
export 'full_player/styles/spotify_desktop_full_player.dart';
export 'full_player/styles/spotify_full_player.dart';
export 'full_player/components/canvas_video.dart';
export 'full_player/components/cover_gradient_container.dart';
export 'full_player/components/desktop_lyrics_preview.dart';
export 'full_player/components/full_player_volume_controls.dart';
export 'full_player/components/inline_delay_editor.dart';
export 'full_player/components/mobile_artist_info_card.dart';
export 'full_player/components/rotating_blurred_cover_background.dart';

class FullScreenPlayer extends StatelessWidget {
  const FullScreenPlayer({super.key});

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  static void show(BuildContext context) {
    AppleMusicFullScreenPlayer.resetTemporaryOptions();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FullScreenPlayer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = context.watch<PreferencesProvider>().style;

    // Use new desktop fullscreen for Spotify on desktop
    if (_isDesktop && style == AppStyle.Spotify) {
      return PopScope(
        onPopInvoked: (didPop) {
          if (!didPop) return;
          unawaited(AppNavigation.instance.disableFullPlayerDesktopMode());
        },
        child: const SpotifyDesktopFullScreenPlayer(),
      );
    }

    final sheet = DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.5, 1.0],
      builder: (context, scrollController) =>
          _buildSheet(context, scrollController, style),
    );
    if (_isDesktop) {
      return PopScope(
        onPopInvoked: (didPop) {
          if (!didPop) return;
          unawaited(AppNavigation.instance.disableFullPlayerDesktopMode());
        },
        child: sheet,
      );
    }
    return sheet;
  }

  Widget _buildSheet(
    BuildContext context,
    ScrollController scrollController,
    AppStyle style,
  ) {
    switch (style) {
      case AppStyle.AppleMusic:
        return AppleMusicFullScreenPlayer(scrollController: scrollController);
      case AppStyle.Original:
        return OriginalFullScreenPlayer(scrollController: scrollController);
      case AppStyle.Spotify:
        return SpotifyFullScreenPlayer(scrollController: scrollController);
    }
  }
}
