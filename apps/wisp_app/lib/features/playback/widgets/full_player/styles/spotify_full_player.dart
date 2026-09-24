// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wisp/features/connect/services/connect_models.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/features/connect/widgets/connect_menu.dart';
import 'package:wisp/shared/widgets/display/marquee_text.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/connect/state/connect_session_provider.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/playback/views/lyrics_view.dart';
import 'package:wisp/features/playback/views/queue_view.dart';
import 'package:wisp/features/playback/widgets/animated_lyrics_preview.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import '../components/canvas_video.dart';
import '../components/cover_gradient_container.dart';
import '../components/mobile_artist_info_card.dart';
import 'apple_music_full_player.dart';

class SpotifyFullScreenPlayer extends StatelessWidget {
  final ScrollController scrollController;

  const SpotifyFullScreenPlayer({required this.scrollController, super.key});

  Widget _buildArtistInfoSection(dynamic currentTrack) {
    final artist = currentTrack?.artists?.isNotEmpty == true
        ? currentTrack.artists.first
        : null;
    if (artist == null) {
      return const SizedBox.shrink();
    }
    return MobileArtistInfoCard(
      artist: artist,
      trackId: currentTrack?.id as String?,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final connect = context.watch<ConnectSessionProvider>();
        final contextType = player.playbackContext?.type;
        final contextName = player.playbackContext?.name;

        String firstLine = 'playing from';
        String secondLine = '';

        if (contextType != null &&
            contextName != null &&
            contextName.isNotEmpty) {
          if (contextType == PlaybackContextType.artist) {
            secondLine = 'Top 10 - $contextName';
          } else {
            secondLine = contextName;
          }
        }

        if (connect.phase == ConnectPhase.pairing) {
          firstLine = 'Handoff | Pairing';
          if (connect.pendingPairRequest != null) {
            secondLine = 'Incoming pairing request';
          } else {
            secondLine = 'Waiting for device...';
          }
        } else if (connect.isLinked) {
          if (connect.isHost) {
            firstLine = 'Handoff | Listening on';
            secondLine = _resolveHandoffPeerName(connect) ?? 'Linked device';
          } else if (connect.isTarget) {
            firstLine = 'Handoff | Controlling from';
            secondLine = _resolveHandoffPeerName(connect) ?? 'Host device';
          }
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                color: Colors.white,
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: secondLine.isNotEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          firstLine,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                            fontWeight: FontWeight.w300,
                            height: 1.3,
                          ),
                        ),
                        Text(
                          secondLine,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.more_vert, size: 24),
                color: Colors.white,
                padding: EdgeInsets.zero,
                onPressed: () {
                  final player = context
                      .read<global_audio_player.WispAudioHandler>();
                  final currentTrack = player.currentTrack;
                  if (currentTrack == null) return;
                  unawaited(
                    AppleMusicFullScreenPlayer.showTrackMenuWithCanvasToggle(
                      context,
                      track: currentTrack,
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

  String? _resolveHandoffPeerName(ConnectSessionProvider connect) {
    final cachedName = connect.linkedPeerName;
    if (cachedName != null && cachedName.trim().isNotEmpty) {
      return cachedName;
    }

    final peerId = connect.linkedDeviceId;
    if (peerId == null) return null;
    for (final device in connect.discoveredDevices) {
      if (device.id == peerId) {
        return device.name;
      }
    }
    return null;
  }

  Future<void> _openHandoffSheet(BuildContext context) async {
    final connect = context.read<ConnectSessionProvider>();
    connect.startDiscovery();

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
  }

  Widget _buildAlbumArt(BuildContext context, String imageUrl) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[900],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey[900],
                        child: const Icon(
                          Icons.music_note,
                          size: 80,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.grey[900],
                      child: const Icon(
                        Icons.music_note,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCanvasVideo(String url, String fallbackUrl) {
    return CanvasVideo(url: url, fallbackUrl: fallbackUrl);
  }

  Widget _buildHiddenArtworkPlaceholder(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSingleLyricsLine(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    LyricsProvider lyricsProvider,
  ) {
    final currentTrack = player.currentTrack;
    if (currentTrack == null) {
      return const SizedBox.shrink();
    }

    final state = lyricsProvider.getState(currentTrack, LyricsSyncMode.line);
    if (!state.isLoading && state.lyrics == null && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.line);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final lyrics = state.lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Consumer<PlaybackCoordinator>(
      builder: (ctx, coordinator, child) {
        final basePosition = coordinator.effectiveThrottledPosition;
        final delayMs =
            (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000)
                .round();
        final adjustedPosition = basePosition.inMilliseconds - delayMs;
        final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
        final lines = nonEmptyLyricsLines(lyrics.lines);
        if (lines.isEmpty) {
          return const SizedBox.shrink();
        }

        final timing = lyrics.syncMode == LyricsSyncMode.line
            ? resolveSyncedLyricsTiming(lines, effectivePosition)
            : null;
        final line = _getSingleLine(lyrics, effectivePosition);
        final showWaitingPlaceholder =
            lyrics.syncMode == LyricsSyncMode.line &&
            timing != null &&
            timing.activeIndex < 0 &&
            timing.nextIndex != null;
        if ((line == null || line.content.trim().isEmpty) &&
            !showWaitingPlaceholder) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: const Interval(0.5, 1.0, curve: Curves.easeOut),
            switchOutCurve: const Interval(0.0, 0.5, curve: Curves.easeIn),
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: [...previousChildren, ?currentChild],
              );
            },
            transitionBuilder: (child, animation) {
              final isRemoving = animation.status == AnimationStatus.reverse;
              final tween = isRemoving
                  ? Tween<Offset>(
                      begin: Offset.zero,
                      end: const Offset(0, -0.2),
                    )
                  : Tween<Offset>(
                      begin: const Offset(0, 0.2),
                      end: Offset.zero,
                    );

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: tween.animate(animation),
                  child: child,
                ),
              );
            },
            child: line == null
                ? const SizedBox(
                    key: ValueKey<String>('lyrics-waiting-placeholder'),
                    width: double.infinity,
                    height: 19,
                  )
                : Text(
                    line.content.trim(),
                    key: ValueKey<String>(line.content.trim()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildTrackInfo(
    dynamic currentTrack,
    Color likeColor,
    bool useCoverArt,
  ) {
    final title = currentTrack?.title ?? 'No track playing';
    final artists = currentTrack?.artists ?? [];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (useCoverArt) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 56, maxWidth: 56),
            child: CachedNetworkImage(imageUrl: currentTrack.thumbnailUrl),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  // TODO: Navigate to track
                },
                child: SizedBox(
                  width: double.infinity,
                  child: MarqueeText(
                    text: title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              if (artists.isNotEmpty)
                Wrap(
                  children: [
                    for (int i = 0; i < artists.length; i++) ...[
                      GestureDetector(
                        onTap: () {
                          // TODO: Navigate to artist
                        },
                        child: Text(
                          artists[i].name,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (i < artists.length - 1)
                        Text(
                          ', ',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ],
                )
              else
                Text(
                  'No Artist',
                  style: TextStyle(color: Colors.grey[300], fontSize: 16),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        LikeButton(
          track: currentTrack as GenericSong?,
          iconSize: 22,
          color: likeColor,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _buildLyricsPreview(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    LyricsProvider lyricsProvider,
    Color bgColor,
    Color? btnColor,
  ) {
    final currentTrack = player.currentTrack;
    if (currentTrack == null) {
      return const SizedBox.shrink();
    }

    final state = lyricsProvider.getState(currentTrack, LyricsSyncMode.line);
    if (!state.isLoading && state.lyrics == null && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.line);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final lyrics = state.lyrics;

    return Consumer<PlaybackCoordinator>(
      builder: (ctx, coordinator, child) {
        final basePosition = coordinator.effectiveThrottledPosition;
        final delayMs =
            (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000)
                .round();
        final adjustedPosition = basePosition.inMilliseconds - delayMs;
        final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
        final previewLines = lyrics == null
            ? const <LyricsLine>[]
            : _getPreviewLines(lyrics, effectivePosition);

        if (!state.isLoading && (lyrics == null || previewLines.isEmpty)) {
          return const SizedBox.shrink();
        }

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Lyrics Preview',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Open lyrics',
                      onPressed: lyrics == null
                          ? null
                          : () => _openLyrics(context),
                      icon: const Icon(Icons.lyrics_outlined),
                      iconSize: 20,
                      color: Colors.white,
                      visualDensity: VisualDensity.compact,
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              if (state.isLoading && lyrics == null)
                const Text(
                  'Loading lyrics…',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                )
              else
                AnimatedLyricsPreviewList(
                  lines: previewLines,
                  resetKey: currentTrack.id,
                  textStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                lyrics == null
                    ? ''
                    : 'Lyrics provided by ${lyrics.provider.label}',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openLyrics(BuildContext context) {
    final currentRoute = ModalRoute.of(context);
    if (currentRoute?.settings.name == '/lyrics') {
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        settings: const RouteSettings(name: '/lyrics'),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LyricsView(),
      ),
    );
  }

  List<LyricsLine> _getPreviewLines(LyricsResult lyrics, int positionMs) {
    final lines = nonEmptyLyricsLines(lyrics.lines);
    if (lines.isEmpty) return const [];
    if (lyrics.syncMode != LyricsSyncMode.line) {
      return lines.take(5).toList();
    }
    final timing = resolveSyncedLyricsTiming(lines, positionMs);
    final startIndex = timing.activeIndex >= 0
        ? timing.activeIndex
        : (timing.nextIndex ?? timing.previousIndex ?? 0);
    return lines.skip(startIndex).take(5).toList();
  }

  LyricsLine? _getSingleLine(LyricsResult lyrics, int positionMs) {
    final lines = nonEmptyLyricsLines(lyrics.lines);
    if (lines.isEmpty) return null;
    if (lyrics.syncMode != LyricsSyncMode.line) {
      return lines.first;
    }
    final timing = resolveSyncedLyricsTiming(lines, positionMs);
    if (timing.activeIndex < 0 || timing.activeIndex >= lines.length) {
      return null;
    }
    return lines[timing.activeIndex];
  }

  Widget _buildPlayerControls(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    Color bgColor,
  ) {
    return Column(
      children: [
        const SizedBox(height: 4),
        _buildProgressBar(context, player, bgColor),
        const SizedBox(height: 16),
        _buildPlaybackControls(context, player, bgColor),
        const SizedBox(height: 16),
        _buildSecondaryControls(context),
      ],
    );
  }

  Widget _buildSecondaryControls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Queue button
            IconButton(
              icon: const Icon(Icons.cast_connected),
              iconSize: 24,
              color: Colors.grey[400],
              onPressed: () {
                unawaited(_openHandoffSheet(context));
              },
            ),
            IconButton(
              icon: const Icon(Icons.share),
              iconSize: 24,
              color: Colors.grey[400],
              onPressed: () => {},
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Queue button
            IconButton(
              icon: const Icon(Icons.queue_music),
              iconSize: 24,
              color: Colors.grey[400],
              onPressed: () {
                showMobileQueueSheet(context);
              },
            ),
            // Lyrics button
            IconButton(
              icon: const Icon(Icons.music_note),
              iconSize: 24,
              color: Colors.grey[400],
              onPressed: () => _openLyrics(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBar(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    Color bgColor,
  ) {
    final useHandoffState = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.useLinkedPlaybackState,
    );
    final isLoading = _isUiLoading(player, useHandoffState);
    final colorScheme = Theme.of(context).colorScheme;
    final position = context.select<PlaybackCoordinator, Duration>(
      (coordinator) => coordinator.effectiveInterpolatedPosition,
    );
    final duration = player.duration;
    final clampedPosition = position > duration ? duration : position;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    if (isLoading) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.grey[800],
                  valueColor: AlwaysStoppedAnimation<Color>(bgColor),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(clampedPosition),
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 200),
      builder: (context, animatedProgress, child) {
        final animatedPosition = Duration(
          milliseconds: (animatedProgress * duration.inMilliseconds).round(),
        );

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
                  activeTrackColor: bgColor,
                  inactiveTrackColor: Colors.grey[800],
                  thumbColor: Colors.white,
                  overlayColor: colorScheme.primary.withValues(alpha: 0.2),
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
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(animatedPosition),
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaybackControls(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    Color bgColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Shuffle
        IconButton(
          icon: const Icon(Icons.shuffle),
          iconSize: 28,
          color: player.isDJMode
              ? Colors.grey[600]
              : (player.shuffleEnabled ? bgColor : Colors.grey[300]),
          padding: const EdgeInsets.all(8),
          tooltip: player.isDJMode ? 'Unavailable in DJ mode' : null,
          onPressed: player.isDJMode
              ? null
              : () {
                  context.read<PlaybackCoordinator>().toggleShuffle();
                },
        ),
        // Previous
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 36,
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          onPressed: player.queueTracks.isEmpty
              ? null
              : () {
                  context.read<PlaybackCoordinator>().skipPrevious();
                },
        ),
        // Play/Pause - Large circular button
        _buildPlayPauseButton(context, player, bgColor),
        // Next
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 36,
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          onPressed: player.queueTracks.isEmpty
              ? null
              : () {
                  context.read<PlaybackCoordinator>().skipNext();
                },
        ),
        // Repeat
        IconButton(
          icon: Icon(
            player.repeatMode == global_audio_player.RepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
          ),
          iconSize: 28,
          color: player.isDJMode
              ? Colors.grey[600]
              : (player.repeatMode != global_audio_player.RepeatMode.off
                  ? bgColor
                  : Colors.grey[300]),
          padding: const EdgeInsets.all(8),
          tooltip: player.isDJMode ? 'Unavailable in DJ mode' : null,
          onPressed: player.isDJMode
              ? null
              : () {
                  context.read<PlaybackCoordinator>().toggleRepeat();
                },
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    Color bgColor,
  ) {
    final useHandoffState = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.useLinkedPlaybackState,
    );
    final isLoading = _isUiLoading(player, useHandoffState);

    if (isLoading) {
      return SizedBox(
        width: 64,
        height: 64,
        child: Container(
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    final isPlaying = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.effectiveIsPlaying,
    );

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
        iconSize: 36,
        color: Colors.black,
        padding: EdgeInsets.zero,
        onPressed: () {
          if (isPlaying) {
            context.read<PlaybackCoordinator>().pause();
          } else {
            final audio = context.read<global_audio_player.WispAudioHandler>();
            if (!useHandoffState &&
                (audio.isLoading ||
                    audio.isBuffering ||
                    audio.isTrackTransitioning)) {
              return;
            }
            context.read<PlaybackCoordinator>().play();
          }
        },
      ),
    );
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

  bool _isUiLoading(
    global_audio_player.WispAudioHandler player,
    bool useHandoffState,
  ) {
    if (useHandoffState) {
      return false;
    }

    if (player.isLoading || player.isBuffering || player.isTrackTransitioning) {
      return true;
    }

    if (player.currentTrack == null) {
      return false;
    }

    return !player.isPlaying &&
        player.duration.inMilliseconds == 0 &&
        player.throttledPosition.inMilliseconds <= 0;
  }

  Widget _buildSpotifyTopCanvasBackground(
    BuildContext context,
    String canvasUrl,
    String fallbackUrl,
  ) {
    final canvas = _buildCanvasVideo(canvasUrl, fallbackUrl);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: scrollController,
            builder: (context, child) {
              final scrollOffset = scrollController.hasClients
                  ? scrollController.offset
                  : 0.0;
              // Apply blur when scrolling down into cards area
              final blurAmount = (scrollOffset * 0.2).clamp(0.0, 25.0);

              // Always wrap in ImageFiltered to prevent widget tree changes that cause flicker
              return ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: blurAmount,
                  sigmaY: blurAmount,
                ),
                child: child,
              );
            },
            child: canvas,
          ),
          Container(color: Colors.black.withValues(alpha: 0.08)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppleMusicFullScreenPlayer
          .animatedCanvasTemporarilyDisabledListenable,
      builder: (context, animatedCanvasDisabled, _) {
        return Consumer2<global_audio_player.WispAudioHandler, LyricsProvider>(
          builder: (context, player, lyricsProvider, child) {
            final currentTrack = player.currentTrack;
            final imageUrl = currentTrack?.thumbnailUrl ?? '';
            final useCanvas = context.select<PreferencesProvider, bool>(
              (prefs) => prefs.animatedCanvasEnabled,
            );
            final allowCanvas = useCanvas && !animatedCanvasDisabled;
            final canUseCanvas =
                allowCanvas &&
                currentTrack != null &&
                (currentTrack.source == SongSource.spotifyInternal ||
                    currentTrack.source == SongSource.spotify);
            final spotifyInternal = context.read<SpotifyInternalProvider>();

            final maxHeight = MediaQuery.sizeOf(context).height;

            final viewPadding = MediaQuery.of(context).viewPadding;
            final windowPadding = MediaQueryData.fromView(
              WidgetsBinding.instance.platformDispatcher.views.first,
            ).padding;
            final topInset = viewPadding.top == 0
                ? windowPadding.top
                : viewPadding.top;
            final bottomInset = viewPadding.bottom == 0
                ? windowPadding.bottom
                : viewPadding.bottom;

            final mainAreaHeight =
                (maxHeight - (topInset + bottomInset)) * 0.95;

            final bgColor = tintedDominantColor(
              Theme.of(context).colorScheme.primary,
            );
            final btnColor = bgColor;

            Widget buildPlayerScaffold(BuildContext ctx, {String? canvasUrl}) {
              final hasCanvas = canvasUrl != null && canvasUrl.isNotEmpty;
              final content = Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                ),
                child: Padding(
                  padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: mainAreaHeight,
                                  child: Column(
                                    children: [
                                      _buildHeader(ctx),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            hasCanvas
                                                ? _buildHiddenArtworkPlaceholder(
                                                    context,
                                                  )
                                                : _buildAlbumArt(ctx, imageUrl),
                                            _buildSingleLyricsLine(
                                              ctx,
                                              player,
                                              lyricsProvider,
                                            ),
                                            _buildTrackInfo(
                                              currentTrack,
                                              btnColor,
                                              (currentTrack!
                                                      .thumbnailUrl
                                                      .isNotEmpty &&
                                                  hasCanvas &&
                                                  useCanvas),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _buildPlayerControls(
                                        ctx,
                                        player,
                                        btnColor,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _buildLyricsPreview(
                                  ctx,
                                  player,
                                  lyricsProvider,
                                  bgColor,
                                  btnColor,
                                ),
                                const SizedBox(height: 16),
                                _buildArtistInfoSection(currentTrack),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );

              final foreground = hasCanvas
                  ? CoverGradientContainer(
                      background: _buildSpotifyTopCanvasBackground(
                        context,
                        canvasUrl,
                        imageUrl,
                      ),
                      child: content,
                    )
                  : CoverGradientContainer(child: content);

              return foreground;
            }

            if (!canUseCanvas) {
              return buildPlayerScaffold(context);
            }

            return FutureBuilder<String?>(
              future: spotifyInternal.getCanvasUrl(currentTrack.id),
              builder: (context, snapshot) {
                final canvasUrl = snapshot.data ?? '';
                return buildPlayerScaffold(context, canvasUrl: canvasUrl);
              },
            );
          },
        );
      },
    );
  }
}

/// Apple Music variant — currently uses the Spotify layout but is a separate
/// class to allow future customization.
