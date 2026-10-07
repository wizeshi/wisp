// Copyright © 2026 wizeshi

/// Player bar widget with playback controls
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/shared/widgets/display/marquee_text.dart';
import 'package:wisp/shared/widgets/display/focus_freeze_builder.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart'
    as global_audio_player;
import 'package:wisp/data/models/metadata_models.dart';
import 'full_player.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/features/details/views/list_detail_view.dart';
import 'package:wisp/shared/widgets/display/hover_underline.dart';
import 'package:wisp/features/shell/navigation/navigation_state.dart';
import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/features/connect/state/connect_session_provider.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/connect/services/connect_models.dart';
import 'package:wisp/features/connect/widgets/connect_menu.dart';
import 'package:wisp/shared/widgets/playback/track_cache_indicator.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

part 'player_bar/components/progress_components.dart';
part 'player_bar/styles/spotify_style.dart';
part 'player_bar/styles/original_style.dart';
part 'player_bar/styles/apple_music_style.dart';

class WispPlayerBar extends StatelessWidget {
  const WispPlayerBar({super.key});

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final currentTrack = context
        .select<global_audio_player.WispAudioHandler, GenericSong?>(
          (player) => player.currentTrack,
        );

    final appStyle = context.select<PreferencesProvider, AppStyle>(
      (p) => p.style,
    );

    switch (appStyle) {
      case AppStyle.Spotify:
        if (_isMobile) {
          return _MobilePlayerBarAnimated(
            currentTrack: currentTrack,
            appStyle: appStyle,
          );
        }
        return _DesktopPlayerBar(
          currentTrack: currentTrack,
          appStyle: appStyle,
        );
      case AppStyle.AppleMusic:
        if (_isMobile) {
          return _AppleMusicMobilePlayerBar(currentTrack: currentTrack);
        }
        return _AppleMusicDesktopPlayerBar(currentTrack: currentTrack);
      case AppStyle.Original:
        if (_isMobile) {
          return _OriginalMobilePlayerBar(currentTrack: currentTrack);
        }
        return _OriginalDesktopPlayerBar(currentTrack: currentTrack);
    }
  }
}

class _SwipePreviewData {
  final GenericSong? previousTrack;
  final GenericSong? nextTrack;

  const _SwipePreviewData({
    required this.previousTrack,
    required this.nextTrack,
  });

  @override
  bool operator ==(Object other) {
    return other is _SwipePreviewData &&
        other.previousTrack?.id == previousTrack?.id &&
        other.nextTrack?.id == nextTrack?.id;
  }

  @override
  int get hashCode => Object.hash(previousTrack?.id, nextTrack?.id);
}

class _HandoffStatusIndicator extends StatelessWidget {
  final String message;
  final Color backgroundColor;
  final bool mobile;

  const _HandoffStatusIndicator({
    required this.message,
    required this.backgroundColor,
    this.mobile = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 8 : 10,
          vertical: mobile ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: backgroundColor.withValues(alpha: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cast, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              message,
              style: TextStyle(
                color: Colors.white,
                fontSize: mobile ? 10 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopProgressBar extends StatelessWidget {
  const _DesktopProgressBar();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Selector<global_audio_player.WispAudioHandler, _PositionData>(
        selector: (context, player) => _PositionData(
          position: player.throttledPosition,
          duration: player.duration,
          isLoading: player.isLoading || player.isBuffering,
        ),
        builder: (context, data, child) {
          if (data.isLoading) {
            return Center(
              child: const Column(
                children: [
                  SizedBox(height: 8),
                  SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(height: 12),
                ],
              ),
            );
          }

          final duration = data.duration;
          final progress = duration.inMilliseconds > 0
              ? data.position.inMilliseconds / duration.inMilliseconds
              : 0.0;

          // Freeze the ticking progress bar (text + slider) while the app or
          // window is unfocused, instead of rebuilding it on every position
          // update.
          if (context.select<PreferencesProvider, bool>(
            (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
              PausedBackgroundWidget.playerProgressBar,
            ),
          )) {
            return FocusFreezeBuilder<_PositionData>(
              value: data,
              builder: (context, frozenData) {
                final frozenDuration = frozenData.duration;
                final frozenProgress = frozenDuration.inMilliseconds > 0
                    ? frozenData.position.inMilliseconds /
                          frozenDuration.inMilliseconds
                    : 0.0;
                return buildBaseProgressBar(
                  context,
                  frozenDuration,
                  frozenProgress,
                );
              },
            );
          }

          return buildBaseProgressBar(context, duration, progress);
        },
      ),
    );
  }

  Widget buildBaseProgressBar(
    BuildContext context,
    Duration duration,
    double progress,
  ) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 200),
      builder: (context, animatedProgress, child) {
        final animatedPosition = Duration(
          milliseconds: (animatedProgress * duration.inMilliseconds).round(),
        );

        return Center(
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: SizedBox(
                  width: 56,
                  child: Text(
                    _formatDuration(animatedPosition),
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    inactiveTrackColor: Colors.grey[800],
                    thumbColor: Colors.white,
                    overlayColor: (Theme.of(
                      context,
                    ).colorScheme.primary).withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: animatedProgress,
                    onChanged: (value) {
                      final newPosition = Duration(
                        milliseconds: (value * duration.inMilliseconds).toInt(),
                      );
                      context.read<PlaybackCoordinator>().seek(newPosition);
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 56,
                  child: Text(
                    _formatDuration(duration),
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  return '$minutes:${twoDigits(seconds)}';
}

class _DesktopTrackName extends StatelessWidget {
  final GenericSong track;

  const _DesktopTrackName({required this.track});

  @override
  Widget build(BuildContext context) {
    final album = track.album;
    final hasAlbum = album != null && album.id.isNotEmpty;
    final style = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );

    return MarqueeText(
      text: track.title,
      style: style,
      builder: (context, textStyle) => HoverUnderline(
        cursor: hasAlbum ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: hasAlbum
            ? () {
                AppNavigation.instance.openSharedList(
                  context,
                  id: album.id,
                  type: SharedListType.album,
                  initialTitle: album.title,
                  initialThumbnailUrl: album.thumbnailUrl,
                );
              }
            : null,
        onSecondaryTapDown: (details) {
          EntityContextMenus.showTrackMenu(
            context,
            track: track,
            globalPosition: details.globalPosition,
          );
        },
        builder: (isHovering) => Text(
          track.title,
          style: textStyle.copyWith(
            decoration: isHovering && hasAlbum
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _DesktopTrackArtists extends StatelessWidget {
  final GenericSong track;

  const _DesktopTrackArtists({required this.track});

  @override
  Widget build(BuildContext context) {
    final artists = track.artists;
    if (artists.isEmpty) return const SizedBox.shrink();

    final joinedText = artists.map((a) => a.name).join(', ');
    final style = TextStyle(color: Colors.grey[400], fontSize: 12);

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: joinedText, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final overflows =
            constraints.hasBoundedWidth &&
            textPainter.width > constraints.maxWidth;

        if (overflows) {
          return MarqueeText(text: joinedText, style: style);
        }

        return Wrap(
          children: [
            for (int i = 0; i < artists.length; i++) ...[
              HoverUnderline(
                onTap: () {
                  AppNavigation.instance.openArtist(
                    context,
                    artistId: artists[i].id,
                    initialArtist: artists[i],
                  );
                },
                onSecondaryTapDown: (details) {
                  EntityContextMenus.showArtistMenu(
                    context,
                    artist: artists[i],
                    globalPosition: details.globalPosition,
                  );
                },
                builder: (isHovering) => Text(
                  artists[i].name,
                  style: style.copyWith(
                    decoration: isHovering
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                ),
              ),
              if (i < artists.length - 1) Text(', ', style: style),
            ],
          ],
        );
      },
    );
  }
}

class _DesktopTrackInfo extends StatelessWidget {
  final GenericSong? currentTrack;
  final AppStyle appStyle;

  const _DesktopTrackInfo({required this.currentTrack, required this.appStyle});

  @override
  Widget build(BuildContext context) {
    if (currentTrack == null) {
      return SizedBox(
        width: 200,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.music_note, color: Colors.grey[700]),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No track playing',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final track = currentTrack!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 56,
            height: 56,
            color: Colors.grey[900],
            child: currentTrack!.thumbnailUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: currentTrack!.thumbnailUrl,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[800]),
                    errorWidget: (context, url, error) =>
                        Icon(Icons.music_note, color: Colors.grey[700]),
                  )
                : Icon(Icons.music_note, color: Colors.grey[700]),
          ),
        ),
        SizedBox(width: 12),
        Flexible(
          fit: FlexFit.loose,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DesktopTrackName(track: track),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TrackBadges(track: track),
                  Flexible(
                    fit: FlexFit.loose,
                    child: _DesktopTrackArtists(track: track),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Selector<global_audio_player.WispAudioHandler, double?>(
                    selector: (context, player) => player.audioBitrate,
                    builder: (context, audioBitrate, child) {
                      if (audioBitrate == null) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        '${(audioBitrate / 1000).floor() - 1} kbps',
                        style: TextStyle(
                          color: Colors.grey[250],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                  Text(
                    ' • ',
                    style: TextStyle(
                      color: Colors.grey[250],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Selector<global_audio_player.WispAudioHandler, int?>(
                    selector: (context, player) => player.audioSampleRate,
                    builder: (context, audioSampleRate, child) {
                      if (audioSampleRate == null) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        '${((audioSampleRate / 100).floor()) / 10} kHz',
                        style: TextStyle(
                          color: Colors.grey[250],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        LikeButton(
          track: currentTrack,
          iconSize: 18,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }
}

class _DesktopPlaybackControls extends StatelessWidget {
  final AppStyle appStyle;

  const _DesktopPlaybackControls({required this.appStyle});

  @override
  Widget build(BuildContext context) {
    return Selector<global_audio_player.WispAudioHandler, _PlayPauseData>(
      selector: (context, player) {
        final track = player.currentTrack;
        final queueFirst = player.queueTracks.isNotEmpty
            ? player.queueTracks.first
            : null;
        return _PlayPauseData(
          isPlaying: player.isPlaying,
          isLoading: player.isLoading,
          isBuffering: player.isBuffering,
          isTransitioning: player.isTrackTransitioning,
          isOnline: player.isOnline,
          currentTrackId: track?.id,
          currentTrackCached: track == null
              ? true
              : player.isTrackCached(track.id),
          queueNotEmpty: player.queueTracks.isNotEmpty,
          queueFirstId: queueFirst?.id,
          shuffleEnabled: player.shuffleEnabled,
          repeatMode: player.repeatMode,
          isDJMode: player.isDJMode,
        );
      },
      builder: (context, data, child) {
        final tokens = context.tokens;
        final controlSpacing = tokens.playerControlSpacing;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Shuffle
            GenericIconButton(
              style: appStyle,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              tooltip: data.isDJMode ? 'Unavailable in DJ mode' : 'Shuffle',
              icon: Icon(
                tokens.shuffleIcon,
                color: data.isDJMode
                    ? Colors.grey[600]
                    : (data.shuffleEnabled
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[400]),
                size: 20,
              ),
              onPressed: data.isDJMode
                  ? null
                  : () {
                      context.read<PlaybackCoordinator>().toggleShuffle();
                    },
            ),

            SizedBox(width: controlSpacing),

            // Previous
            GenericIconButton(
              style: appStyle,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              icon: Icon(tokens.playPrevIcon, color: Colors.white, size: 24),
              onPressed: data.queueNotEmpty
                  ? () {
                      context.read<PlaybackCoordinator>().skipPrevious();
                    }
                  : null,
            ),

            SizedBox(width: controlSpacing),

            // Play/Pause
            _DesktopPlayPauseButton(data: data, appStyle: appStyle),

            SizedBox(width: controlSpacing),

            // Next
            GenericIconButton(
              style: appStyle,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              icon: Icon(tokens.playNextIcon, color: Colors.white, size: 24),
              onPressed: data.queueNotEmpty
                  ? () {
                      context.read<PlaybackCoordinator>().skipNext();
                    }
                  : null,
            ),

            SizedBox(width: controlSpacing),

            // Repeat
            GenericIconButton(
              style: appStyle,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              tooltip: data.isDJMode ? 'Unavailable in DJ mode' : 'Repeat',
              icon: Icon(
                data.repeatMode == global_audio_player.RepeatMode.one
                    ? tokens.repeatOneIcon
                    : tokens.repeatIcon,
                color: data.isDJMode
                    ? Colors.grey[600]
                    : (data.repeatMode != global_audio_player.RepeatMode.off
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[400]),
                size: 20,
              ),
              onPressed: data.isDJMode
                  ? null
                  : () {
                      context.read<PlaybackCoordinator>().toggleRepeat();
                    },
            ),
          ],
        );
      },
    );
  }
}

class _DesktopPlayPauseButton extends StatelessWidget {
  final _PlayPauseData data;
  final AppStyle appStyle;

  const _DesktopPlayPauseButton({required this.data, required this.appStyle});

  @override
  Widget build(BuildContext context) {
    final useHandoffState = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.useLinkedPlaybackState,
    );
    final effectiveIsPlaying = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.effectiveIsPlaying,
    );

    if (data.isLoading || data.isBuffering || data.isTransitioning) {
      return Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final isOfflineBlocked =
        !useHandoffState &&
        !data.isOnline &&
        data.currentTrackId != null &&
        !data.currentTrackCached;
    final tokens = context.tokens;
    IconData icon = effectiveIsPlaying
        ? (tokens.isApple ? tokens.pauseIcon : Icons.pause_circle_filled)
        : (tokens.isApple ? tokens.playIcon : Icons.play_circle_filled);
    VoidCallback? onPressed;

    if (!isOfflineBlocked) {
      if (effectiveIsPlaying) {
        onPressed = () {
          context.read<PlaybackCoordinator>().pause();
        };
      } else if (data.currentTrackId != null) {
        onPressed = () {
          final audio = context.read<global_audio_player.WispAudioHandler>();
          if (!useHandoffState &&
              (audio.isLoading ||
                  audio.isBuffering ||
                  audio.isTrackTransitioning)) {
            return;
          }
          context.read<PlaybackCoordinator>().play();
        };
      } else if (data.queueNotEmpty) {
        onPressed = () {
          final audio = context.read<global_audio_player.WispAudioHandler>();
          if (!useHandoffState &&
              (audio.isLoading ||
                  audio.isBuffering ||
                  audio.isTrackTransitioning)) {
            return;
          }
          context.read<PlaybackCoordinator>().play();
        };
      }
    }

    if (isOfflineBlocked) {
      return GenericIconButton(
        style: appStyle,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        icon: Icon(icon, color: Colors.grey[700], size: 40),
        onPressed: null,
      );
    }

    return GenericIconButton(
      style: appStyle,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      icon: Icon(
        icon,
        color: tokens.isApple
            ? Colors.white
            : Theme.of(context).colorScheme.primary,
        size: 40,
      ),
      onPressed: onPressed,
    );
  }
}

class _DesktopRightControls extends StatelessWidget {
  final GenericSong? currentTrack;
  final AppStyle appStyle;

  const _DesktopRightControls({
    required this.currentTrack,
    required this.appStyle,
  });

  @override
  Widget build(BuildContext context) {
    final navState = context.watch<NavigationState>();
    return ValueListenableBuilder<Route<dynamic>?>(
      valueListenable: NavigationHistory.instance.currentRoute,
      builder: (context, route, child) {
        final routeName = route?.settings.name;
        final tokens = context.tokens;
        final controlSpacing = tokens.playerControlSpacing;
        final volumeSpacing = tokens.playerVolumeSpacing;
        final isLyricsRouteOpen = routeName == '/lyrics';
        final isQueueOpen = routeName == '/queue';
        final isFullScreenOpen = routeName == '/fullplayer';
        final hasTrack = currentTrack != null;
        final isSidebarOpen = hasTrack && navState.rightSidebarVisible;
        final activeColor = Theme.of(context).colorScheme.primary;
        final inactiveColor = Colors.grey[400];

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showLyricsButton = width >= 230;
            final showQueueButton = width >= 280;
            final showVolumeSlider = width >= 390;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isFullScreenOpen)
                  Selector<global_audio_player.WispAudioHandler, bool>(
                    selector: (context, player) {
                      return player.playbackContext != null &&
                          player.playbackContext!.id.toLowerCase().startsWith(
                            "dj",
                          );
                    },
                    builder: (context, value, child) {
                      return Row(
                        children: [
                          GenericIconButton(
                            style: appStyle,
                            icon: Icon(
                              Symbols.headphones,
                              color: value ? activeColor : inactiveColor,
                              size: 20,
                            ),
                            onPressed: () {
                              NavigationHistory
                                          .instance
                                          .currentRoute
                                          .value
                                          ?.settings
                                          .name ==
                                      '/dj'
                                  ? NavigationHistory.instance.goBack()
                                  : AppNavigation.instance.navigateToDJView(
                                      context,
                                    );
                            },
                          ),
                          SizedBox(width: controlSpacing),
                        ],
                      );
                    },
                  ),
                if (!isFullScreenOpen) ...[
                  GenericIconButton(
                    style: appStyle,
                    icon: Icon(
                      tokens.sidebarIcon,
                      color: isSidebarOpen ? activeColor : inactiveColor,
                      size: 20,
                    ),
                    onPressed: hasTrack ? navState.toggleRightSidebar : null,
                  ),
                  SizedBox(width: controlSpacing),
                ],
                ValueListenableBuilder<FullPlayerDesktopMode>(
                  valueListenable: AppNavigation.instance.fullPlayerDesktopMode,
                  builder: (context, fullPlayerMode, child) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showLyricsButton) ...[
                          GenericIconButton(
                            style: appStyle,
                            icon: Icon(
                              tokens.lyricsIcon,
                              color: isFullScreenOpen
                                  ? fullPlayerMode ==
                                            FullPlayerDesktopMode.lyrics
                                        ? activeColor
                                        : inactiveColor
                                  : isLyricsRouteOpen
                                  ? activeColor
                                  : inactiveColor,
                              size: 20,
                            ),
                            onPressed: currentTrack == null
                                ? null
                                : () {
                                    if (isFullScreenOpen) {
                                      if (fullPlayerMode ==
                                          FullPlayerDesktopMode.lyrics) {
                                        AppNavigation.instance
                                            .restorePreviousFullPlayerDesktopMode();
                                      } else {
                                        AppNavigation.instance
                                            .setFullPlayerDesktopMode(
                                              FullPlayerDesktopMode.lyrics,
                                            );
                                      }
                                      return;
                                    }

                                    final currentScreen = NavigationHistory
                                        .instance
                                        .currentRoute
                                        .value
                                        ?.settings
                                        .name;
                                    if (currentScreen == '/lyrics') {
                                      NavigationHistory.instance.goBack();
                                    } else {
                                      _openLyrics(context);
                                    }
                                  },
                          ),
                          SizedBox(width: controlSpacing),
                        ],
                        if (showQueueButton) ...[
                          GenericIconButton(
                            style: appStyle,
                            icon: Icon(
                              tokens.queueIcon,
                              color: isFullScreenOpen
                                  ? fullPlayerMode ==
                                            FullPlayerDesktopMode.queue
                                        ? activeColor
                                        : inactiveColor
                                  : isQueueOpen
                                  ? activeColor
                                  : inactiveColor,
                              size: 20,
                            ),
                            onPressed: () {
                              if (isFullScreenOpen) {
                                if (fullPlayerMode ==
                                    FullPlayerDesktopMode.queue) {
                                  AppNavigation.instance
                                      .restorePreviousFullPlayerDesktopMode();
                                } else {
                                  AppNavigation.instance
                                      .setFullPlayerDesktopMode(
                                        FullPlayerDesktopMode.queue,
                                      );
                                }
                                return;
                              }

                              final currentScreen = NavigationHistory
                                  .instance
                                  .currentRoute
                                  .value
                                  ?.settings
                                  .name;
                              if (currentScreen == '/queue') {
                                NavigationHistory.instance.goBack();
                              } else {
                                _openQueue(context);
                              }
                            },
                          ),
                          SizedBox(width: controlSpacing),
                        ],
                      ],
                    );
                  },
                ),
                _ConnectMenuButton(
                  iconSize: 20,
                  appStyle: appStyle,
                  inactiveColor: inactiveColor,
                  activeColorOverride: activeColor,
                ),
                SizedBox(width: controlSpacing),
                Selector<global_audio_player.WispAudioHandler, double>(
                  selector: (context, player) => player.userVolume,
                  builder: (context, volume, child) {
                    final player = context
                        .read<global_audio_player.WispAudioHandler>();
                    if (!showVolumeSlider) {
                      return _VolumePopupButton(
                        inactiveColor: inactiveColor,
                        accentColor: activeColor,
                      );
                    }

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GenericIconButton(
                          style: appStyle,
                          mouseCursor: SystemMouseCursors.click,
                          tooltip: volume == 0 ? 'Unmute' : 'Mute',
                          onPressed: player.toggleMute,
                          icon: Icon(
                            volume == 0
                                ? tokens.volumeOffIcon
                                : volume < 0.5
                                ? tokens.volumeDownIcon
                                : tokens.volumeUpIcon,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                        ),
                        SizedBox(width: volumeSpacing),
                        SizedBox(
                          width: 100,
                          child: _HoverVolumeSlider(
                            value: volume,
                            onChanged: (value) => player.setVolume(value),
                            primaryColor: activeColor,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (!isFullScreenOpen) ...[
                  SizedBox(width: controlSpacing / 2),
                  GenericIconButton(
                    style: appStyle,
                    icon: Icon(
                      tokens.fullscreenIcon,
                      color: inactiveColor,
                      size: 20,
                    ),
                    onPressed: () async {
                      final currentScreen = NavigationHistory
                          .instance
                          .currentRoute
                          .value
                          ?.settings
                          .name;
                      if (currentScreen == '/fullplayer') {
                        await AppNavigation.instance.closeFullPlayer();
                      } else {
                        await _openFullPlayer(context);
                      }
                    },
                  ),
                  SizedBox(width: controlSpacing / 2),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

Future<void> _openFullPlayer(BuildContext context) async {
  final currentRoute = ModalRoute.of(context);
  if (currentRoute?.settings.name == '/fullplayer') {
    return;
  }
  await AppNavigation.instance.openFullPlayer();
}

void _openLyrics(BuildContext context) {
  final currentRoute = ModalRoute.of(context);
  if (currentRoute?.settings.name == '/lyrics') {
    return;
  }
  AppNavigation.instance.openLyrics();
}

void _openQueue(BuildContext context) {
  final currentRoute = ModalRoute.of(context);
  if (currentRoute?.settings.name == '/queue') {
    return;
  }
  AppNavigation.instance.openQueue();
}

Future<void> _openConnectMenuWithAccent(BuildContext context) async {
  final connect = context.read<ConnectSessionProvider>();
  connect.startDiscovery();

  final isMobile = Platform.isAndroid || Platform.isIOS;

  if (isMobile) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final mediaQuery = MediaQuery.of(sheetContext);
        final maxHeight = mediaQuery.size.height * 0.75;
        return SafeArea(
          top: false,
          child: Container(
            height: maxHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF171717),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: ConnectMenu(
              compact: true,
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        );
      },
    );
    return;
  }

  final navigation = context.read<NavigationState>();
  final isConnectSidebarOpen =
      navigation.rightSidebarVisible &&
      navigation.rightSidebarContent == RightSidebarContent.connect;
  if (isConnectSidebarOpen) {
    navigation.showLibrarySidebar();
    return;
  }
  navigation.showConnectSidebar();
}

// ignore: unused_element
class _ConnectQuickPanel extends StatelessWidget {
  final Rect anchorRect;
  final Size overlaySize;
  final Color accentColor;

  const _ConnectQuickPanel({
    required this.anchorRect,
    required this.overlaySize,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final themePrimary = accentColor;
    const panelWidth = 340.0;
    const panelHeight = 360.0;
    const margin = 8.0;
    final left = (anchorRect.center.dx - (panelWidth / 2)).clamp(
      margin,
      overlaySize.width - panelWidth - margin,
    );
    final top = (anchorRect.top - panelHeight - margin).clamp(
      margin,
      overlaySize.height - panelHeight - margin,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: panelWidth,
          height: panelHeight,
          child: Material(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(14),
            elevation: 14,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: themePrimary.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: _ConnectPanelContent(
                accentColor: themePrimary,
                onClose: () => Navigator.of(context).pop(),
                isMobileSheet: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectPanelContent extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onClose;
  final bool isMobileSheet;

  const _ConnectPanelContent({
    required this.accentColor,
    required this.onClose,
    this.isMobileSheet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectSessionProvider>(
      builder: (context, connect, child) {
        final linkedLabel = _linkedDeviceLabel(connect);
        final pendingRequest = connect.pendingPairRequest;
        final devices = connect.discoveredDevices
            .where((device) => device.id != connect.localDeviceId)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Icon(Icons.cast_connected, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Text(
                    'Handoff',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobileSheet ? 18 : 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GenericIconButton(
                    tooltip: 'Refresh Handoff devices',
                    splashRadius: 18,
                    onPressed: connect.refreshDiscovery,
                    icon: Icon(Icons.refresh, size: 18, color: accentColor),
                  ),
                ],
              ),
            ),
            if (linkedLabel != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF212121),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link, size: 16, color: accentColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          linkedLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: isMobileSheet ? 14 : null,
                          ),
                        ),
                      ),
                      GenericTextButton(
                        onPressed: () {
                          connect.unlink(localResumed: true);
                          onClose();
                        },
                        child: const Text('Unlink'),
                      ),
                    ],
                  ),
                ),
              ),
            if (pendingRequest != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF212121),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pendingRequest.fromDeviceName} wants to pair via Handoff',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: isMobileSheet ? 14 : 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: GenericOutlinedButton(
                              onPressed: connect.rejectIncomingPair,
                              side: BorderSide(color: Colors.grey[700]!),
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GenericElevatedButton(
                              onPressed: connect.acceptIncomingPair,
                              child: const Text('Accept'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                linkedLabel != null ? 10 : 2,
                12,
                8,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF212121),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Next link mode:',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: isMobileSheet ? 13 : 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SegmentedButton<ConnectLinkMode>(
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? accentColor.withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              foregroundColor: WidgetStateProperty.all<Color>(
                                Colors.white,
                              ),
                              side: WidgetStatePropertyAll(
                                BorderSide(color: Colors.grey[700]!),
                              ),
                            ),
                            segments: const [
                              ButtonSegment<ConnectLinkMode>(
                                value: ConnectLinkMode.fullHandoff,
                                label: Text('Full'),
                              ),
                              ButtonSegment<ConnectLinkMode>(
                                value: ConnectLinkMode.controlOnly,
                                label: Text('Controls'),
                              ),
                            ],
                            selected: {connect.nextOutgoingLinkMode},
                            onSelectionChanged: (selection) {
                              final next = selection.first;
                              connect.setNextOutgoingLinkMode(next);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Checkbox(
                          value: connect.rememberModeForNextLink,
                          onChanged: (value) {
                            connect.setRememberModeForNextLink(value ?? false);
                          },
                        ),
                        Expanded(
                          child: Text(
                            'Remember for next session',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: isMobileSheet ? 12 : 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                linkedLabel != null ? 12 : 2,
                14,
                8,
              ),
              child: Text(
                'Available devices',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: isMobileSheet ? 14 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: devices.isEmpty
                  ? Center(
                      child: Text(
                        'No devices found on this network.',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: isMobileSheet ? 14 : 13,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: devices.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final isLinkedDevice =
                            connect.linkedDeviceId == device.id;
                        return Material(
                          color: const Color(0xFF202020),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: isLinkedDevice
                                ? null
                                : () {
                                    connect.beginPairing(
                                      device.id,
                                      mode: connect.nextOutgoingLinkMode,
                                      rememberForDevice:
                                          connect.rememberModeForNextLink,
                                    );
                                    onClose();
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.devices,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          device.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: isMobileSheet ? 15 : null,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          device.platform,
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: isMobileSheet ? 13 : 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isLinkedDevice)
                                    Text(
                                      'Linked',
                                      style: TextStyle(
                                        color: accentColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: isMobileSheet ? 13 : 12,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ConnectMenuButton extends StatelessWidget {
  final double iconSize;
  final Color? inactiveColor;
  final Color? activeColorOverride;
  final AppStyle appStyle;

  const _ConnectMenuButton({
    required this.iconSize,
    required this.appStyle,
    this.inactiveColor,
    this.activeColorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        activeColorOverride ?? Theme.of(context).colorScheme.primary;
    final icon = context.tokens.connectIcon;

    Widget buildIconButton(bool isActive) {
      return GenericIconButton(
        style: appStyle,
        icon: Icon(
          icon,
          color: isActive ? activeColor : (inactiveColor ?? Colors.grey[400]),
          size: iconSize,
        ),
        tooltip: 'Handoff',
        onPressed: () => _openConnectMenuWithAccent(context),
      );
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return Selector<ConnectSessionProvider, bool>(
        selector: (context, connect) {
          return connect.isLinked;
        },
        builder: (context, isActive, child) {
          return buildIconButton(isActive);
        },
      );
    } else {
      return Selector2<ConnectSessionProvider, NavigationState, bool>(
        selector: (context, connect, navigation) {
          final isDesktopConnectMenuOpen =
              !(Platform.isAndroid || Platform.isIOS) &&
              navigation.rightSidebarVisible &&
              navigation.rightSidebarContent == RightSidebarContent.connect;
          return connect.isLinked || isDesktopConnectMenuOpen;
        },
        builder: (context, isActive, child) {
          return buildIconButton(isActive);
        },
      );
    }
  }
}

class _VolumePopupButton extends StatelessWidget {
  final Color? inactiveColor;
  final Color? accentColor;

  const _VolumePopupButton({this.inactiveColor, this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Selector<global_audio_player.WispAudioHandler, double>(
      selector: (context, player) => player.userVolume,
      builder: (context, volume, child) {
        return GenericIconButton(
          mouseCursor: SystemMouseCursors.click,
          tooltip: 'Volume',
          onPressed: () => _openVolumeMenu(context, accentColor: accentColor),
          icon: Icon(
            volume == 0
                ? Icons.volume_off
                : volume < 0.5
                ? Icons.volume_down
                : Icons.volume_up,
            color: inactiveColor ?? Colors.grey[400],
            size: 20,
          ),
        );
      },
    );
  }
}

Future<void> _openVolumeMenu(BuildContext context, {Color? accentColor}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final button = context.findRenderObject() as RenderBox;
  final buttonRect = Rect.fromPoints(
    button.localToGlobal(Offset.zero, ancestor: overlay),
    button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    ),
  );

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _VolumeQuickPanel(
        anchorRect: buttonRect,
        overlaySize: overlay.size,
        accentColor: accentColor,
      );
    },
  );
}

class _VolumeQuickPanel extends StatelessWidget {
  final Rect anchorRect;
  final Size overlaySize;
  final Color? accentColor;

  const _VolumeQuickPanel({
    required this.anchorRect,
    required this.overlaySize,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final themePrimary = accentColor ?? Theme.of(context).colorScheme.primary;
    const panelWidth = 76.0;
    const panelHeight = 196.0;
    const margin = 8.0;

    final left = (anchorRect.center.dx - (panelWidth / 2)).clamp(
      margin,
      overlaySize.width - panelWidth - margin,
    );
    final top = (anchorRect.top - panelHeight - margin).clamp(
      margin,
      overlaySize.height - panelHeight - margin,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: panelWidth,
          height: panelHeight,
          child: Material(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(12),
            elevation: 10,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 16,
                ),
                child: Selector<global_audio_player.WispAudioHandler, double>(
                  selector: (context, player) => player.userVolume,
                  builder: (context, volume, child) {
                    final player = context
                        .read<global_audio_player.WispAudioHandler>();
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            '${(volume * 100).round()}%',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(height: 4),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: _HoverVolumeSlider(
                              value: volume,
                              onChanged: (value) => player.setVolume(value),
                              primaryColor: themePrimary,
                            ),
                          ),
                        ),
                        GenericIconButton(
                          tooltip: volume == 0 ? 'Unmute' : 'Mute',
                          onPressed: player.toggleMute,
                          icon: Icon(
                            volume == 0
                                ? Icons.volume_off
                                : volume < 0.5
                                ? Icons.volume_down
                                : Icons.volume_up,
                            color: Colors.grey[300],
                            size: 18,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HoverVolumeSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final Color primaryColor;

  const _HoverVolumeSlider({
    required this.value,
    required this.onChanged,
    required this.primaryColor,
  });

  @override
  State<_HoverVolumeSlider> createState() => _HoverVolumeSliderState();
}

class _HoverVolumeSliderState extends State<_HoverVolumeSlider> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = _isHovering ? widget.primaryColor : Colors.grey[500]!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          activeTrackColor: activeColor,
          inactiveTrackColor: Colors.grey[800],
          thumbColor: Colors.white,
          overlayColor: widget.primaryColor.withValues(alpha: 0.2),
        ),
        child: Slider(
          min: 0,
          max: 1,
          value: widget.value,
          divisions: 100,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

String? _linkedDeviceLabel(ConnectSessionProvider connect) {
  final cachedName = connect.linkedPeerName;
  if (cachedName != null && cachedName.trim().isNotEmpty) {
    return cachedName;
  }

  final linkedId = connect.linkedDeviceId;
  if (linkedId == null || linkedId.isEmpty) return null;

  for (final device in connect.discoveredDevices) {
    if (device.id == linkedId) {
      return device.name;
    }
  }

  if (linkedId.length > 10) {
    return 'Device ${linkedId.substring(0, 10)}';
  }

  return 'Device $linkedId';
}

String? _handoffStatusMessage(ConnectSessionProvider connect) {
  if (connect.phase == ConnectPhase.pairing && !connect.isLinked) {
    return 'Handoff | Waiting for approval...';
  }

  if (connect.isLinked) {
    final label = _linkedDeviceLabel(connect) ?? 'Device';
    if (connect.isTarget) {
      return 'Handoff | Controlling from $label';
    }
    return 'Handoff | Listening on: $label';
  }

  return null;
}

class _PositionData {
  final Duration position;
  final Duration duration;
  final bool isLoading;

  const _PositionData({
    required this.position,
    required this.duration,
    this.isLoading = false,
  });

  @override
  bool operator ==(Object other) =>
      other is _PositionData &&
      other.position.inMilliseconds == position.inMilliseconds &&
      other.duration.inMilliseconds == duration.inMilliseconds &&
      other.isLoading == isLoading;

  @override
  int get hashCode =>
      Object.hash(position.inMilliseconds, duration.inMilliseconds, isLoading);
}

class _PlayPauseData {
  final bool isPlaying;
  final bool isLoading;
  final bool isBuffering;
  final bool isTransitioning;
  final bool isOnline;
  final String? currentTrackId;
  final bool currentTrackCached;
  final bool queueNotEmpty;
  final String? queueFirstId;
  final bool shuffleEnabled;
  final global_audio_player.RepeatMode? repeatMode;
  final bool isDJMode;

  const _PlayPauseData({
    required this.isPlaying,
    required this.isLoading,
    required this.isBuffering,
    required this.isTransitioning,
    required this.isOnline,
    required this.currentTrackId,
    required this.currentTrackCached,
    required this.queueNotEmpty,
    required this.queueFirstId,
    this.shuffleEnabled = false,
    this.repeatMode,
    this.isDJMode = false,
  });

  @override
  bool operator ==(Object other) =>
      other is _PlayPauseData &&
      other.isPlaying == isPlaying &&
      other.isLoading == isLoading &&
      other.isBuffering == isBuffering &&
      other.isTransitioning == isTransitioning &&
      other.isOnline == isOnline &&
      other.currentTrackId == currentTrackId &&
      other.currentTrackCached == currentTrackCached &&
      other.queueNotEmpty == queueNotEmpty &&
      other.queueFirstId == queueFirstId &&
      other.shuffleEnabled == shuffleEnabled &&
      other.repeatMode == repeatMode &&
      other.isDJMode == isDJMode;

  @override
  int get hashCode => Object.hash(
    isPlaying,
    isLoading,
    isBuffering,
    isTransitioning,
    isOnline,
    currentTrackId,
    currentTrackCached,
    queueNotEmpty,
    queueFirstId,
    shuffleEnabled,
    repeatMode,
    isDJMode,
  );
}

class _MobileOutputInfo {
  final bool isExternal;
  final String deviceName;

  const _MobileOutputInfo({required this.isExternal, required this.deviceName});

  factory _MobileOutputInfo.fromProvider(ConnectSessionProvider connect) {
    final name = connect.activeOutputDeviceName?.trim();
    return _MobileOutputInfo(
      isExternal: connect.hasExternalOutput,
      deviceName: (name == null || name.isEmpty) ? 'Connected' : name,
    );
  }
}
