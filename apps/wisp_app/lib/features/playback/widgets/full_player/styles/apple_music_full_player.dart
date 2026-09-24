// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisp/features/connect/services/connect_models.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/core/utils/text_parser.dart';
import 'package:wisp/features/connect/widgets/connect_menu.dart';
import 'package:wisp/shared/widgets/display/marquee_text.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/connect/state/connect_session_provider.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/shared/widgets/menus/adaptive_context_menu.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import '../components/canvas_video.dart';
import '../components/full_player_volume_controls.dart';
import '../components/rotating_blurred_cover_background.dart';

class AppleMusicFullScreenPlayer extends StatelessWidget {
  final ScrollController scrollController;
  static final ValueNotifier<_ApplePlayerViewMode> _modeNotifier =
      ValueNotifier<_ApplePlayerViewMode>(_ApplePlayerViewMode.nowPlaying);
  static final ValueNotifier<int> _artistIndexNotifier = ValueNotifier<int>(0);
  static double _lastNonZeroVolume = 1.0;
  static final ScrollController _lyricsScrollController = ScrollController();
  static int _lastLyricsIndex = -1;
  static String? _lastLyricsTrackId;
  static String? _lastArtistTrackId;
  static List<GlobalKey>? _lyricsLineKeys;
  static String? _lyricsLineKeysTrackId;
  static final Map<String, Future<GenericArtist?>> _artistInfoFutureCache =
      <String, Future<GenericArtist?>>{};
  static final Map<String, Future<String?>> _canvasUrlFutureCache =
      <String, Future<String?>>{};
  static final ValueNotifier<bool> _animatedCanvasTemporarilyDisabledNotifier =
      ValueNotifier<bool>(false);

  const AppleMusicFullScreenPlayer({required this.scrollController, super.key});

  static void resetTemporaryOptions() {
    _animatedCanvasTemporarilyDisabledNotifier.value = false;
  }

  static ValueNotifier<bool> get animatedCanvasTemporarilyDisabledListenable =>
      _animatedCanvasTemporarilyDisabledNotifier;

  static Future<void> showTrackMenuWithCanvasToggle(
    BuildContext context, {
    required GenericSong track,
    Offset? globalPosition,
    Rect? anchorRect,
  }) async {
    final animatedCanvasDisabled =
        _animatedCanvasTemporarilyDisabledNotifier.value;
    await EntityContextMenus.showTrackMenu(
      context,
      track: track,
      globalPosition: globalPosition,
      anchorRect: anchorRect,
      onBeforeNavigate: () =>
          AppNavigation.instance.disableFullPlayerDesktopMode(),
      additionalActions: [
        ContextMenuAction(
          id: 'toggle-animated-canvas-temp',
          label: animatedCanvasDisabled
              ? 'Enable Animated Canvas'
              : 'Disable Animated Canvas',
          icon: animatedCanvasDisabled
              ? Icons.motion_photos_on
              : Icons.motion_photos_off,
          onSelected: (_) {
            _animatedCanvasTemporarilyDisabledNotifier.value =
                !animatedCanvasDisabled;
          },
        ),
      ],
    );
  }

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  void _setMode(_ApplePlayerViewMode mode) {
    _modeNotifier.value = mode;
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

  Widget _buildCoverImageBox(
    BuildContext context,
    String imageUrl,
    double size,
  ) {
    return SizedBox(
      width: size,
      height: size,
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
                    size: 40,
                    color: Colors.grey,
                  ),
                ),
              )
            : Container(
                color: Colors.grey[900],
                child: const Icon(
                  Icons.music_note,
                  size: 40,
                  color: Colors.grey,
                ),
              ),
      ),
    );
  }

  Widget _buildAnimatedCoverSection(
    BuildContext context,
    _ApplePlayerViewMode mode,
    dynamic currentTrack,
    String imageUrl,
    bool hideNowPlayingCover,
  ) {
    final isNowPlaying = mode == _ApplePlayerViewMode.nowPlaying;
    final onCoverTap = isNowPlaying
        ? null
        : () => _setMode(_ApplePlayerViewMode.nowPlaying);
    final double expandedSize = math.min(
      MediaQuery.of(context).size.width - 48,
      360.0,
    );
    final shouldHideCover = isNowPlaying && hideNowPlayingCover;
    final compactSize = 64.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeInOutCubic,
      height: isNowPlaying ? expandedSize : compactSize,
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeInOutCubic,
            alignment: isNowPlaying ? Alignment.center : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeInOutCubic,
              width: isNowPlaying ? expandedSize : compactSize,
              height: isNowPlaying ? expandedSize : compactSize,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final scale = Tween<double>(
                    begin: 0.98,
                    end: 1.0,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: scale, child: child),
                  );
                },
                child: shouldHideCover
                    ? const SizedBox.expand(key: ValueKey('apple-cover-hidden'))
                    : GestureDetector(
                        key: const ValueKey('apple-cover-visible'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onCoverTap,
                        child: SizedBox(
                          width: isNowPlaying ? expandedSize : compactSize,
                          height: isNowPlaying ? expandedSize : compactSize,
                          child: _buildCoverImageBox(
                            context,
                            imageUrl,
                            isNowPlaying ? expandedSize : compactSize,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: isNowPlaying,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                opacity: isNowPlaying ? 0 : 1,
                child: Padding(
                  padding: const EdgeInsets.only(left: 78),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentTrack?.title ?? 'No track playing',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentTrack?.artists?.isNotEmpty == true
                                    ? currentTrack.artists.first.name
                                    : 'No Artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        LikeButton(
                          track: currentTrack as GenericSong?,
                          iconSize: 22,
                          padding: const EdgeInsets.all(2),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          likedIcon: CupertinoIcons.heart_fill,
                          notLikedIcon: CupertinoIcons.heart,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsModeContent(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    LyricsProvider lyricsProvider,
  ) {
    final currentTrack = player.currentTrack;
    if (currentTrack == null) {
      return Center(
        child: Text(
          'No track playing',
          style: TextStyle(color: Colors.grey[400], fontSize: 16),
        ),
      );
    }

    final syncedState = lyricsProvider.getState(
      currentTrack,
      LyricsSyncMode.word,
    );
    if (!syncedState.isLoading &&
        syncedState.lyrics == null &&
        syncedState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.word);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final syncedLyrics = syncedState.lyrics;
    final unsyncedState = lyricsProvider.getState(
      currentTrack,
      LyricsSyncMode.unsynced,
    );
    if (syncedLyrics == null &&
        !unsyncedState.isLoading &&
        unsyncedState.lyrics == null &&
        unsyncedState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.unsynced);
      });
    }

    final lyrics = syncedLyrics ?? unsyncedState.lyrics;
    final isLoading =
        (syncedState.isLoading || unsyncedState.isLoading) && lyrics == null;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (lyrics == null || lyrics.lines.isEmpty) {
      return Center(
        child: Text(
          'No lyrics found',
          style: TextStyle(color: Colors.grey[400], fontSize: 16),
        ),
      );
    }

    final normalizedLyrics = removeEmptyLyricsLines(lyrics);
    if (normalizedLyrics.lines.isEmpty) {
      return Center(
        child: Text(
          'No lyrics found',
          style: TextStyle(color: Colors.grey[400], fontSize: 16),
        ),
      );
    }

    final basePosition = context.select<PlaybackCoordinator, Duration>(
      (coordinator) => coordinator.effectiveThrottledPosition,
    );
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = basePosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    final timing = normalizedLyrics.syncMode != LyricsSyncMode.unsynced
        ? resolveSyncedLyricsTiming(normalizedLyrics.lines, effectivePosition)
        : null;
    final currentIndex = normalizedLyrics.syncMode != LyricsSyncMode.unsynced
        ? timing!.activeIndex
        : 0;

    if (_lastLyricsTrackId != currentTrack.id) {
      _lastLyricsTrackId = currentTrack.id;
      _lastLyricsIndex = -1;
      if (_lyricsScrollController.hasClients) {
        _lyricsScrollController.jumpTo(0);
      }
    }

    if (_lyricsLineKeysTrackId != currentTrack.id ||
        _lyricsLineKeys == null ||
        _lyricsLineKeys!.length != normalizedLyrics.lines.length) {
      _lyricsLineKeysTrackId = currentTrack.id;
      _lyricsLineKeys = List<GlobalKey>.generate(
        normalizedLyrics.lines.length,
        (_) => GlobalKey(),
      );
    }
    final lineKeys = _lyricsLineKeys!;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_lastLyricsIndex != currentIndex) {
          _lastLyricsIndex = currentIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (currentIndex < 0 || currentIndex >= lineKeys.length) {
              return;
            }
            final lineContext = lineKeys[currentIndex].currentContext;
            if (lineContext == null) return;
            Scrollable.ensureVisible(
              lineContext,
              alignment: 0.0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }

        return ListView.builder(
          controller: _lyricsScrollController,
          itemCount: normalizedLyrics.lines.length,
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          itemBuilder: (context, index) {
            final lyricLine = normalizedLyrics.lines[index];
            final anchorIndex = currentIndex >= 0
                ? currentIndex
                : (timing?.nextIndex ?? timing?.previousIndex ?? 0);
            final distance = (index - anchorIndex).abs();
            final isCurrent = index == currentIndex;
            var opacity = isCurrent
                ? 1.0
                : (1.0 - (distance * 0.22)).clamp(0.16, 0.72);
            var fontSize = isCurrent ? 34.0 : 30.0;
            var fontWeight = isCurrent ? FontWeight.w700 : FontWeight.w600;
            var color = isCurrent ? Colors.white : Colors.grey[500]!;

            if (normalizedLyrics.syncMode != LyricsSyncMode.unsynced &&
                timing != null &&
                timing.shouldFadePreviousLine &&
                timing.previousIndex == index &&
                timing.nextIndex != null) {
              opacity = lerpDouble(1.0, 0.72, timing.fadeOutProgress)!;
              fontSize = lerpDouble(34.0, 30.0, timing.fadeOutProgress)!;
              fontWeight = timing.fadeOutProgress < 0.55
                  ? FontWeight.w700
                  : FontWeight.w600;
              color = Color.lerp(
                Colors.white,
                Colors.grey[500],
                timing.fadeOutProgress,
              )!;
            }

            final row = AnimatedOpacity(
              key: lineKeys[index],
              duration: const Duration(milliseconds: 220),
              opacity: opacity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  mouseCursor:
                      normalizedLyrics.syncMode != LyricsSyncMode.unsynced
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  onTap: normalizedLyrics.syncMode != LyricsSyncMode.unsynced
                      ? () {
                          final seekMs = (lyricLine.startTimeMs + delayMs)
                              .clamp(0, player.duration.inMilliseconds)
                              .toInt();
                          unawaited(
                            context.read<PlaybackCoordinator>().seek(
                              Duration(milliseconds: seekMs),
                            ),
                          );
                        }
                      : null,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      buildLyricsLineSpan(
                        line: lyricLine,
                        syncMode: normalizedLyrics.syncMode,
                        positionMs: effectivePosition,
                        baseStyle: TextStyle(
                          color: color,
                          fontSize: fontSize,
                          fontWeight: fontWeight,
                          height: 1.1,
                        ),
                        activeWordColor: Colors.white,
                        inactiveWordColor: color,
                        highlightWords: isCurrent,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
              ),
            );

            final showWaitingDots =
                normalizedLyrics.syncMode != LyricsSyncMode.unsynced &&
                timing != null &&
                timing.showWaitingDots &&
                timing.nextIndex == index;

            if (!showWaitingDots) {
              return row;
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [_buildLyricsWaitingDots(timing.progressToNext), row],
            );
          },
        );
      },
    );
  }

  Widget _buildLyricsWaitingDots(double progress) {
    final dots = List<Widget>.generate(3, (index) {
      final start = index / 3;
      final end = (index + 1) / 3;
      final localProgress = ((progress - start) / (end - start)).clamp(
        0.0,
        1.0,
      );
      final opacity = lerpDouble(0.2, 1.0, localProgress)!;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        ),
      );
    });

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: dots),
      ),
    );
  }

  Widget _buildQueueModeContent(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    bool isMobile,
  ) {
    final queue = player.queueTracks;
    final currentIndex = player.currentIndex;
    final contextName = player.playbackContext?.name;
    final continuePlayingSource = contextName != null && contextName.isNotEmpty
        ? contextName
        : 'Queue';
    final visibleQueueIndices = _buildWrappedQueueIndices(queue, currentIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile) ...[
          const SizedBox(height: 14),
          _buildMobileNowPlayingActionButtons(
            context,
            player,
            Theme.of(context).colorScheme.primary,
          ),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Continue playing from',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    continuePlayingSource,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: queue.isEmpty
                  ? null
                  : () {
                      context.read<PlaybackCoordinator>().clearQueue();
                    },
              child: Text(
                'Clear',
                style: TextStyle(color: Colors.grey[400], fontSize: 15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: queue.isEmpty
              ? Center(
                  child: Text(
                    'Queue is empty',
                    style: TextStyle(color: Colors.grey[500], fontSize: 18),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      type: MaterialType.transparency,
                      color: Colors.transparent,
                      child: child,
                    );
                  },
                  itemCount: visibleQueueIndices.length,
                  onReorder: (oldIndex, newIndex) {
                    if (oldIndex == newIndex) return;
                    final queueOldIndex = visibleQueueIndices[oldIndex];
                    final queueNewIndex =
                        visibleQueueIndices[newIndex.clamp(
                          0,
                          visibleQueueIndices.length - 1,
                        )];
                    unawaited(
                      context.read<PlaybackCoordinator>().reorderQueue(
                        queueOldIndex,
                        queueNewIndex,
                      ),
                    );
                  },
                  itemBuilder: (context, index) {
                    final queueIndex = visibleQueueIndices[index];
                    final track = queue[queueIndex];
                    final isCurrent = queueIndex == currentIndex;
                    return Padding(
                      key: ValueKey('queue-item-${track.id}-$queueIndex'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          unawaited(
                            context.read<PlaybackCoordinator>().playQueueIndex(
                              queueIndex,
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            _buildCoverImageBox(
                              context,
                              track.thumbnailUrl,
                              56,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: isCurrent
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    track.artists.isNotEmpty
                                        ? track.artists.first.name
                                        : 'Unknown artist',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: Icon(
                                Icons.drag_handle,
                                color: Colors.grey[500],
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<int> _buildWrappedQueueIndices(
    List<GenericSong> queue,
    int currentIndex,
  ) {
    if (queue.isEmpty) return const <int>[];
    if (currentIndex < 0 || currentIndex >= queue.length) {
      return List<int>.generate(queue.length, (index) => index);
    }

    if (queue.length == 1) {
      return const <int>[];
    }

    return List<int>.generate(
      queue.length - 1,
      (index) => (currentIndex + 1 + index) % queue.length,
    );
  }

  Widget _buildModeContent(
    BuildContext context,
    _ApplePlayerViewMode mode,
    global_audio_player.WispAudioHandler player,
    LyricsProvider lyricsProvider,
    bool isMobile,
  ) {
    Widget child;
    switch (mode) {
      case _ApplePlayerViewMode.lyrics:
        child = _buildLyricsModeContent(context, player, lyricsProvider);
        break;
      case _ApplePlayerViewMode.queue:
        child = _buildQueueModeContent(context, player, isMobile);
        break;
      case _ApplePlayerViewMode.artist:
        child = _buildArtistModeContent(context, player);
        break;
      case _ApplePlayerViewMode.nowPlaying:
        child = const SizedBox.shrink();
        break;
    }

    return SizedBox.expand(child: child);
  }

  Widget _buildArtistModeContent(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
  ) {
    final track = player.currentTrack;
    if (track == null) {
      return Center(
        child: Text(
          'No track playing',
          style: TextStyle(color: Colors.grey[400], fontSize: 16),
        ),
      );
    }

    final artists = track.artists;
    if (artists.isEmpty) {
      return Center(
        child: Text(
          'No artist metadata',
          style: TextStyle(color: Colors.grey[400], fontSize: 16),
        ),
      );
    }

    if (_lastArtistTrackId != track.id) {
      _lastArtistTrackId = track.id;
      _artistIndexNotifier.value = 0;
    }

    return ValueListenableBuilder<int>(
      valueListenable: _artistIndexNotifier,
      builder: (context, selectedIndex, _) {
        final index = selectedIndex.clamp(0, artists.length - 1);
        final selectedArtist = artists[index];
        final spotifyInternal = context.read<SpotifyInternalProvider>();

        return FutureBuilder<GenericArtist?>(
          future: _getArtistInfoFuture(
            spotifyInternal,
            selectedArtist,
            track.id,
          ),
          builder: (context, snapshot) {
            final artist = snapshot.data;
            final artistImage = (artist?.thumbnailUrl.isNotEmpty == true)
                ? artist!.thumbnailUrl
                : selectedArtist.thumbnailUrl;
            final listeners = artist?.monthlyListeners ?? artist?.followers;
            final description = artist?.description?.trim();
            final topTracks = artist?.topSongs ?? const <GenericSong>[];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < artists.length; i++)
                      ChoiceChip(
                        label: Text(artists[i].name),
                        selected: i == index,
                        selectedColor: Colors.white24,
                        backgroundColor: Colors.white10,
                        labelStyle: const TextStyle(color: Colors.white),
                        onSelected: (_) => _artistIndexNotifier.value = i,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 1.4,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: artistImage.isEmpty
                                  ? Container(color: Colors.grey[850])
                                  : CachedNetworkImage(
                                      imageUrl: artistImage,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, _, _) =>
                                          Container(color: Colors.grey[850]),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            artist?.name ?? selectedArtist.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (listeners != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${_formatLargeNumber(listeners)} listeners',
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          (description != null && description.isNotEmpty)
                              ? buildParsedText(
                                  context,
                                  description,
                                  style: TextStyle(
                                    color: Colors.grey[200],
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                )
                              : Text(
                                  'No description available for this artist.',
                                  style: TextStyle(
                                    color: Colors.grey[200],
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                ),
                          if (topTracks.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Top tracks',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (
                              var i = 0;
                              i < math.min(topTracks.length, 5);
                              i++
                            ) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(
                                  '${i + 1}. ${topTracks[i].title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[200],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<GenericArtist?> _loadArtistInfo(
    SpotifyInternalProvider spotifyInternal,
    GenericSimpleArtist artist,
    String? trackId,
  ) async {
    if (artist.source != SongSource.spotifyInternal &&
        artist.source != SongSource.spotify) {
      return null;
    }
    try {
      if (trackId != null && trackId.isNotEmpty) {
        return await spotifyInternal.getNpvArtistInfo(artist.id, trackId);
      }
      return await spotifyInternal.getArtistInfo(artist.id);
    } catch (_) {
      return null;
    }
  }

  Future<GenericArtist?> _getArtistInfoFuture(
    SpotifyInternalProvider spotifyInternal,
    GenericSimpleArtist artist,
    String? trackId,
  ) {
    final normalizedTrackId = (trackId == null || trackId.isEmpty)
        ? 'none'
        : trackId;
    final cacheKey = '${artist.source.name}:${artist.id}:$normalizedTrackId';
    return _artistInfoFutureCache.putIfAbsent(
      cacheKey,
      () => _loadArtistInfo(spotifyInternal, artist, trackId),
    );
  }

  void _pruneFutureCache<T>(Map<String, Future<T>> cache, {int maxSize = 48}) {
    while (cache.length > maxSize) {
      cache.remove(cache.keys.first);
    }
  }

  Future<String?>? _getCanvasUrlFuture(
    SpotifyInternalProvider spotifyInternal,
    GenericSong? currentTrack,
    bool canUseCanvas,
  ) {
    if (!canUseCanvas || currentTrack == null) {
      return null;
    }
    final trackId = currentTrack.id;
    final cached = _canvasUrlFutureCache[trackId];
    if (cached != null) {
      return cached;
    }
    _pruneFutureCache<String?>(_canvasUrlFutureCache);
    final future = spotifyInternal.getCanvasUrl(trackId);
    _canvasUrlFutureCache[trackId] = future;
    return future;
  }

  String _formatLargeNumber(int value) {
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
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
          final peerName =
              connect.linkedPeerName ??
              (() {
                final peerId = connect.linkedDeviceId;
                if (peerId == null) return null;
                for (final device in connect.discoveredDevices) {
                  if (device.id == peerId) {
                    return device.name;
                  }
                }
                return null;
              })();

          if (connect.isHost) {
            firstLine = 'Handoff | Listening on';
            secondLine = peerName ?? 'Linked device';
          } else if (connect.isTarget) {
            firstLine = 'Handoff | Controlling from';
            secondLine = peerName ?? 'Host device';
          }
        }

        final centerInfo = secondLine.isNotEmpty
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
            : const SizedBox.shrink();

        final mobileInfo = secondLine.isNotEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
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
                      ),
                    ],
                  ),
                ],
              )
            : const SizedBox.shrink();

        if (_isDesktop) {
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 84,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Exit fullscreen',
                    icon: const Icon(Icons.fullscreen_exit, size: 18),
                    color: Colors.white,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    splashRadius: 16,
                    onPressed: () {
                      unawaited(AppNavigation.instance.closeFullPlayer());
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Close window',
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.white,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    splashRadius: 16,
                    onPressed: () {
                      unawaited(windowManager.close());
                    },
                  ),
                ],
              ),
            ),
          );
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
            Expanded(child: _isDesktop ? centerInfo : mobileInfo),
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

    final basePosition = context.select<PlaybackCoordinator, Duration>(
      (coordinator) => coordinator.effectiveThrottledPosition,
    );
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = basePosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    final lines = nonEmptyLyricsLines(lyrics.lines);
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final timing = lyrics.syncMode != LyricsSyncMode.unsynced
        ? resolveSyncedLyricsTiming(lines, effectivePosition)
        : null;
    final line = _getSingleLine(lyrics, effectivePosition);
    final showWaitingPlaceholder =
        lyrics.syncMode != LyricsSyncMode.unsynced &&
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
              ? Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.2))
              : Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero);

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
                height: 18,
              )
            : Text.rich(
                buildLyricsLineSpan(
                  line: line,
                  syncMode: lyrics.syncMode,
                  positionMs: effectivePosition,
                  baseStyle: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  activeWordColor: Colors.white,
                  inactiveWordColor: Colors.grey[400]!,
                  highlightWords: true,
                ),
                key: ValueKey<String>(line.content.trim()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
              ),
      ),
    );
  }

  Widget _buildTrackInfo(
    GenericSong? currentTrack,
    Color likeColor,
    bool isDesktop,
  ) {
    final title = currentTrack?.title ?? 'No track playing';
    final artists = currentTrack?.artists ?? [];
    final albumName = currentTrack?.album?.title ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    pauseWhenUnfocused: true,
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
              Row(
                children: [
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
                  Text(
                    ' - $albumName',
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                    maxLines: isDesktop ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        LikeButton(
          track: currentTrack,
          iconSize: 22,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          likedIcon: CupertinoIcons.heart_fill,
          notLikedIcon: CupertinoIcons.heart,
          color: likeColor,
        ),
      ],
    );
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
    Color btnColor,
    _ApplePlayerViewMode mode,
  ) {
    if (_isDesktop) {
      return _buildDesktopPlayerControls(context, player, btnColor, mode);
    }
    return Column(
      children: [
        const SizedBox(height: 0),
        _buildProgressBar(context, player),
        const SizedBox(height: 16),
        _buildPlaybackControls(context, player),
        const SizedBox(height: 16),
        _buildSecondaryControls(context, btnColor, mode),
      ],
    );
  }

  Widget _buildDesktopPlayerControls(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    Color btnColor,
    _ApplePlayerViewMode mode,
  ) {
    return Column(
      children: [
        _buildProgressBar(context, player),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.bottomLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (buttonContext) => _buildModeActionButton(
                        tooltip: 'More options',
                        icon: CupertinoIcons.ellipsis,
                        selected: false,
                        onTap: () {
                          final overlay =
                              Overlay.of(context).context.findRenderObject()
                                  as RenderBox;
                          final box =
                              buttonContext.findRenderObject() as RenderBox?;
                          if (box == null) {
                            unawaited(_openTrackMenu(context, player));
                            return;
                          }
                          final rect = Rect.fromPoints(
                            box.localToGlobal(Offset.zero, ancestor: overlay),
                            box.localToGlobal(
                              box.size.bottomRight(Offset.zero),
                              ancestor: overlay,
                            ),
                          );
                          unawaited(
                            _openTrackMenu(context, player, anchorRect: rect),
                          );
                        },
                        activeColor: btnColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildModeActionButton(
                      tooltip: player.isDJMode ? 'Unavailable in DJ mode' : 'Shuffle',
                      icon: CupertinoIcons.shuffle,
                      selected: !player.isDJMode && player.shuffleEnabled,
                      onTap: player.isDJMode
                          ? null
                          : () => context.read<PlaybackCoordinator>().toggleShuffle(),
                      activeColor: btnColor,
                    ),
                    const SizedBox(width: 6),
                    _buildModeActionButton(
                      tooltip: player.isDJMode ? 'Unavailable in DJ mode' : 'Repeat',
                      icon:
                          player.repeatMode ==
                              global_audio_player.RepeatMode.one
                          ? CupertinoIcons.repeat_1
                          : CupertinoIcons.repeat,
                      selected:
                          !player.isDJMode &&
                          player.repeatMode !=
                          global_audio_player.RepeatMode.off,
                      onTap: player.isDJMode
                          ? null
                          : () => context.read<PlaybackCoordinator>().toggleRepeat(),
                      activeColor: btnColor,
                    ),
                    const SizedBox(width: 6),
                    _buildDesktopVolumeButton(player, btnColor),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _buildDesktopTransportControls(context, player),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: _buildDesktopModeActions(mode, btnColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopVolumeButton(
    global_audio_player.WispAudioHandler player,
    Color btnColor,
  ) {
    final volume = player.volume;
    final volumeIcon = volume == 0
        ? Icons.volume_off
        : volume < 0.5
        ? Icons.volume_down
        : Icons.volume_up;

    return Builder(
      builder: (buttonContext) {
        return IconButton(
          tooltip: 'Volume',
          splashRadius: 18,
          iconSize: 22,
          onPressed: () {
            unawaited(_openDesktopVolumeMenu(buttonContext, btnColor));
          },
          icon: Icon(
            volumeIcon,
            color: volume <= 0.001 ? btnColor : Colors.grey[300],
          ),
        );
      },
    );
  }

  Future<void> _openDesktopVolumeMenu(
    BuildContext buttonContext,
    Color accentColor,
  ) async {
    final overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox;
    final button = buttonContext.findRenderObject() as RenderBox;
    final buttonRect = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );

    await showGeneralDialog<void>(
      context: buttonContext,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return FullPlayerVolumeQuickPanel(
          anchorRect: buttonRect,
          overlaySize: overlay.size,
          accentColor: accentColor,
          onToggleMute: () {
            final audio = dialogContext
                .read<global_audio_player.WispAudioHandler>();
            unawaited(_toggleMute(audio));
          },
        );
      },
    );
  }

  Future<void> _toggleMute(global_audio_player.WispAudioHandler player) async {
    final volume = player.volume.clamp(0.0, 1.0);
    if (volume <= 0.001) {
      final restore = _lastNonZeroVolume <= 0.001 ? 0.5 : _lastNonZeroVolume;
      await player.setVolume(restore.clamp(0.0, 1.0));
      return;
    }

    _lastNonZeroVolume = volume;
    await player.setVolume(0.0);
  }

  Widget _buildDesktopTransportControls(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
  ) {
    final useHandoffState = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.useLinkedPlaybackState,
    );
    final isLoading = _isUiLoading(player, useHandoffState);
    final isPlaying = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.effectiveIsPlaying,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous',
          icon: const Icon(CupertinoIcons.backward_fill),
          iconSize: 22,
          splashRadius: 18,
          color: Colors.white,
          onPressed: player.queueTracks.isEmpty
              ? null
              : () {
                  context.read<PlaybackCoordinator>().skipPrevious();
                },
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: isPlaying ? 'Pause' : 'Play',
          icon: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                ),
          iconSize: 22,
          splashRadius: 18,
          color: Colors.white,
          onPressed: isLoading
              ? null
              : () {
                  if (isPlaying) {
                    context.read<PlaybackCoordinator>().pause();
                  } else {
                    final audio = context
                        .read<global_audio_player.WispAudioHandler>();
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
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Next',
          icon: const Icon(CupertinoIcons.forward_fill),
          iconSize: 22,
          splashRadius: 18,
          color: Colors.white,
          onPressed: player.queueTracks.isEmpty
              ? null
              : () {
                  context.read<PlaybackCoordinator>().skipNext();
                },
        ),
      ],
    );
  }

  Widget _buildDesktopModeActions(_ApplePlayerViewMode mode, Color btnColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildModeActionButton(
          tooltip: 'Lyrics',
          icon: CupertinoIcons.quote_bubble,
          selected: mode == _ApplePlayerViewMode.lyrics,
          onTap: () => _setMode(
            mode == _ApplePlayerViewMode.lyrics
                ? _ApplePlayerViewMode.nowPlaying
                : _ApplePlayerViewMode.lyrics,
          ),
          activeColor: btnColor,
        ),
        const SizedBox(width: 6),
        _buildModeActionButton(
          tooltip: 'Queue',
          icon: CupertinoIcons.list_bullet,
          selected: mode == _ApplePlayerViewMode.queue,
          onTap: () => _setMode(
            mode == _ApplePlayerViewMode.queue
                ? _ApplePlayerViewMode.nowPlaying
                : _ApplePlayerViewMode.queue,
          ),
          activeColor: btnColor,
        ),
        const SizedBox(width: 6),
        _buildModeActionButton(
          tooltip: 'Artist',
          icon: CupertinoIcons.person,
          selected: mode == _ApplePlayerViewMode.artist,
          onTap: () => _setMode(
            mode == _ApplePlayerViewMode.artist
                ? _ApplePlayerViewMode.nowPlaying
                : _ApplePlayerViewMode.artist,
          ),
          activeColor: btnColor,
        ),
      ],
    );
  }

  Widget _buildModeActionButton({
    required String tooltip,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
    required Color activeColor,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      splashRadius: 18,
      iconSize: 22,
      icon: Icon(
        icon,
        color: onTap == null
            ? Colors.grey[600]
            : (selected ? activeColor : Colors.grey[300]),
      ),
    );
  }

  Widget _buildMobileNowPlayingActionButtons(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    Color btnColor,
  ) {
    final repeatMode = player.repeatMode;

    return Row(
      children: [
        Expanded(
          child: _buildMobileNowPlayingActionButton(
            icon: CupertinoIcons.shuffle,
            selected: !player.isDJMode && player.shuffleEnabled,
            activeColor: btnColor,
            onTap: player.isDJMode
                ? null
                : () => _deferAsyncAction(
                    () => context.read<PlaybackCoordinator>().toggleShuffle(),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMobileNowPlayingActionButton(
            icon: repeatMode == global_audio_player.RepeatMode.one
                ? CupertinoIcons.repeat_1
                : CupertinoIcons.repeat,
            selected: !player.isDJMode &&
                repeatMode != global_audio_player.RepeatMode.off,
            activeColor: btnColor,
            onTap: player.isDJMode
                ? null
                : () => _deferAsyncAction(
                    () => context.read<PlaybackCoordinator>().toggleRepeat(),
                  ),
          ),
        ),
      ],
    );
  }

  void _deferAsyncAction(Future<void> Function() action) {
    unawaited(Future<void>.delayed(Duration.zero, action));
  }

  Future<void> _openTrackMenu(
    BuildContext context,
    global_audio_player.WispAudioHandler player, {
    Offset? globalPosition,
    Rect? anchorRect,
  }) async {
    final currentTrack = player.currentTrack;
    if (currentTrack == null) return;
    await showTrackMenuWithCanvasToggle(
      context,
      track: currentTrack,
      globalPosition: globalPosition,
      anchorRect: anchorRect,
    );
  }

  Widget _buildMobileNowPlayingActionButton({
    required IconData icon,
    required bool selected,
    required Color activeColor,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    final color = !isEnabled
        ? Colors.grey[600]!
        : (selected ? Colors.white : Colors.grey[200]!);
    final background = !isEnabled
        ? Colors.white.withValues(alpha: 0.05)
        : (selected
            ? activeColor.withValues(alpha: 0.34)
            : Colors.white.withValues(alpha: 0.13));

    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: selected ? 0.26 : 0.14),
            width: 1,
          ),
        ),
        child: IconButton(
          onPressed: onTap,
          iconSize: 22,
          splashRadius: 18,
          color: color,
          icon: Icon(icon),
        ),
      ),
    );
  }

  Widget _buildSecondaryControls(
    BuildContext context,
    Color btnColor,
    _ApplePlayerViewMode mode,
  ) {
    return SizedBox(
      height: 56,
      child: Consumer<ConnectSessionProvider>(
        builder: (context, connect, child) {
          final handoffColor = connect.isLinked ? btnColor : Colors.grey[200];
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.quote_bubble),
                iconSize: 24,
                color: mode == _ApplePlayerViewMode.lyrics
                    ? btnColor
                    : Colors.grey[200],
                onPressed: () => _setMode(
                  mode == _ApplePlayerViewMode.lyrics
                      ? _ApplePlayerViewMode.nowPlaying
                      : _ApplePlayerViewMode.lyrics,
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.antenna_radiowaves_left_right),
                iconSize: 24,
                color: handoffColor,
                onPressed: () {
                  unawaited(_openHandoffSheet(context));
                },
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.list_bullet),
                iconSize: 24,
                color: mode == _ApplePlayerViewMode.queue
                    ? btnColor
                    : Colors.grey[200],
                onPressed: () => _setMode(
                  mode == _ApplePlayerViewMode.queue
                      ? _ApplePlayerViewMode.nowPlaying
                      : _ApplePlayerViewMode.queue,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressBar(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
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
                  backgroundColor: Colors.grey[400],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[300]!),
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
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
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
                    enabledThumbRadius: 3,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 2),
                  activeTrackColor: Colors.grey[300],
                  inactiveTrackColor: Colors.grey[400],
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
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
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
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // Previous
        IconButton(
          icon: const Icon(CupertinoIcons.backward_fill),
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
        _buildPlayPauseButton(context, player),
        // Next
        IconButton(
          icon: const Icon(CupertinoIcons.forward_fill),
          iconSize: 36,
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          onPressed: player.queueTracks.isEmpty
              ? null
              : () {
                  context.read<PlaybackCoordinator>().skipNext();
                },
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final useHandoffState = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.useLinkedPlaybackState,
    );
    final isLoading = _isUiLoading(player, useHandoffState);
    if (isLoading) {
      return SizedBox(
        width: 96,
        height: 96,
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle),
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
      width: 96,
      height: 96,
      decoration: BoxDecoration(shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(
          isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
        ),
        iconSize: 64,
        color: colorScheme.onPrimary,
        padding: EdgeInsets.zero,
        onPressed: () {
          if (isPlaying) {
            context.read<PlaybackCoordinator>().pause();
          } else {
            final audio = context.read<global_audio_player.WispAudioHandler>();
            if (!useHandoffState && (audio.isLoading || audio.isBuffering)) {
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

    if (player.isLoading || player.isBuffering) {
      return true;
    }

    if (player.currentTrack == null) {
      return false;
    }

    return !player.isPlaying &&
        player.duration.inMilliseconds == 0 &&
        player.throttledPosition.inMilliseconds <= 0;
  }

  Widget _buildCanvasBackground(
    BuildContext context,
    String url,
    String fallbackUrl,
    double topInset,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: RotatingBlurredCoverBackground(imageUrl: fallbackUrl),
        ),
        Positioned.fill(
          child: CanvasVideo(url: url, fallbackUrl: fallbackUrl),
        ),
      ],
    );
  }

  Widget _buildFallbackBackground(
    BuildContext context,
    String imageUrl,
    double topInset,
  ) {
    return RepaintBoundary(
      child: RotatingBlurredCoverBackground(imageUrl: imageUrl),
    );
  }

  Widget _buildDesktopBody(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    LyricsProvider lyricsProvider,
    dynamic currentTrack,
    String imageUrl,
    _ApplePlayerViewMode mode,
    Color btnColor,
  ) {
    final isNowPlaying = mode == _ApplePlayerViewMode.nowPlaying;
    final maxModePanelWidth = math.min(
      MediaQuery.of(context).size.width * 0.34,
      520.0,
    );
    final maxNowPlayingByScreen = math.min(
      MediaQuery.of(context).size.width * 0.40,
      560.0,
    );

    return Column(
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              const reservedBottomHeight = 286.0;
              final nowPlayingPanelWidth = math.min(
                maxNowPlayingByScreen,
                math.max(260.0, availableHeight - reservedBottomHeight),
              );
              final nowPlayingOuterWidth = nowPlayingPanelWidth + 44;
              const panelGap = 4.0;
              final showModePanel = !isNowPlaying;
              final modePanelWidth = math.min(
                maxModePanelWidth,
                math.max(260.0, availableHeight - 80),
              );
              final horizontalShift = showModePanel
                  ? -((modePanelWidth + panelGap) / 2)
                  : 0.0;
              final targetPanelHeight = math.min(
                nowPlayingPanelWidth + reservedBottomHeight,
                availableHeight,
              );
              final panelHeight = math.max(0.0, targetPanelHeight);

              return Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: panelHeight,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: horizontalShift),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOutCubic,
                    builder: (context, shift, _) {
                      return Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Transform.translate(
                            offset: Offset(shift, 0),
                            child: SizedBox(
                              width: nowPlayingOuterWidth,
                              height: panelHeight,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: nowPlayingPanelWidth,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    18,
                                    22,
                                    16,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final coverSize = constraints.maxWidth;

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Flexible(
                                            fit: FlexFit.loose,
                                            child: LayoutBuilder(
                                              builder:
                                                  (context, topConstraints) {
                                                    final hasLyricsRoom =
                                                        topConstraints
                                                            .maxHeight >=
                                                        coverSize + 54;
                                                    return Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _buildCoverImageBox(
                                                          context,
                                                          imageUrl,
                                                          coverSize,
                                                        ),
                                                        if (hasLyricsRoom) ...[
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          _buildSingleLyricsLine(
                                                            context,
                                                            player,
                                                            lyricsProvider,
                                                          ),
                                                        ],
                                                      ],
                                                    );
                                                  },
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          _buildTrackInfo(
                                            currentTrack,
                                            btnColor,
                                            true,
                                          ),
                                          const SizedBox(height: 6),
                                          _buildPlayerControls(
                                            context,
                                            player,
                                            btnColor,
                                            mode,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left:
                                (MediaQuery.of(context).size.width / 2) +
                                (nowPlayingOuterWidth / 2) +
                                panelGap +
                                shift,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                final offset = Tween<Offset>(
                                  begin: const Offset(-0.12, 0),
                                  end: Offset.zero,
                                ).animate(animation);
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: offset,
                                    child: child,
                                  ),
                                );
                              },
                              child: showModePanel
                                  ? SizedBox(
                                      key: ValueKey<_ApplePlayerViewMode>(mode),
                                      height: panelHeight,
                                      width: modePanelWidth,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          0,
                                          18,
                                          0,
                                          16,
                                        ),
                                        child: SizedBox.expand(
                                          child: _buildModeContent(
                                            context,
                                            mode,
                                            player,
                                            lyricsProvider,
                                            false,
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('no-mode-panel'),
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<global_audio_player.WispAudioHandler, LyricsProvider>(
      builder: (context, player, lyricsProvider, child) {
        final currentTrack = player.currentTrack;
        final useCanvas = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.animatedCanvasEnabled,
        );
        final canUseCanvas =
            useCanvas &&
            currentTrack != null &&
            (currentTrack.source == SongSource.spotifyInternal ||
                currentTrack.source == SongSource.spotify);
        final spotifyInternal = context.read<SpotifyInternalProvider>();
        final Future<String?>? canvasFuture = _getCanvasUrlFuture(
          spotifyInternal,
          currentTrack,
          canUseCanvas,
        );

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

        final imageUrl = currentTrack?.thumbnailUrl ?? '';
        final btnColor = Theme.of(context).colorScheme.primary;

        return FutureBuilder<String?>(
          future: canvasFuture,
          builder: (context, canvasSnapshot) {
            final canvasUrl = canvasSnapshot.data ?? '';
            final hasCanvas = canvasUrl.isNotEmpty;

            return ValueListenableBuilder<bool>(
              valueListenable: _animatedCanvasTemporarilyDisabledNotifier,
              builder: (context, animatedCanvasDisabled, _) {
                return ValueListenableBuilder<_ApplePlayerViewMode>(
                  valueListenable: _modeNotifier,
                  builder: (context, mode, _) {
                    final isNowPlaying =
                        mode == _ApplePlayerViewMode.nowPlaying;
                    final useNowPlayingCanvas =
                        !animatedCanvasDisabled &&
                        (_isDesktop ? hasCanvas : (isNowPlaying && hasCanvas));

                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 420),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final moveAnimation = Tween<Offset>(
                                begin: const Offset(0, 0.06),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: moveAnimation,
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey<bool>(useNowPlayingCanvas),
                              child: useNowPlayingCanvas
                                  ? _buildCanvasBackground(
                                      context,
                                      canvasUrl,
                                      imageUrl,
                                      topInset,
                                    )
                                  : _buildFallbackBackground(
                                      context,
                                      imageUrl,
                                      topInset,
                                    ),
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(bottom: bottomInset),
                            child: Column(
                              children: [
                                Padding(
                                  padding:
                                      (_isDesktop
                                              ? const EdgeInsets.only(right: 0)
                                              : const EdgeInsets.symmetric(
                                                  horizontal: 24.0,
                                                ))
                                          .add(EdgeInsets.only(top: topInset)),
                                  child: _buildHeader(context),
                                ),
                                SizedBox(
                                  height: _isDesktop || !isNowPlaying ? 0 : 56,
                                ),
                                Flexible(
                                  fit: FlexFit.tight,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24.0,
                                    ),
                                    child: _isDesktop
                                        ? _buildDesktopBody(
                                            context,
                                            player,
                                            lyricsProvider,
                                            currentTrack,
                                            imageUrl,
                                            mode,
                                            btnColor,
                                          )
                                        : Column(
                                            mainAxisSize: MainAxisSize.max,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              _buildAnimatedCoverSection(
                                                context,
                                                mode,
                                                currentTrack,
                                                imageUrl,
                                                useNowPlayingCanvas,
                                              ),
                                              SizedBox(
                                                height: isNowPlaying ? 10 : 4,
                                              ),
                                              if (isNowPlaying) ...[
                                                const Spacer(),
                                                _buildSingleLyricsLine(
                                                  context,
                                                  player,
                                                  lyricsProvider,
                                                ),
                                                const SizedBox(height: 12),
                                                _buildTrackInfo(
                                                  currentTrack,
                                                  btnColor,
                                                  false,
                                                ),
                                                const SizedBox(height: 24),
                                              ] else ...[
                                                Expanded(
                                                  child: AnimatedSwitcher(
                                                    duration: const Duration(
                                                      milliseconds: 280,
                                                    ),
                                                    switchInCurve:
                                                        Curves.easeOut,
                                                    switchOutCurve:
                                                        Curves.easeIn,
                                                    child: KeyedSubtree(
                                                      key:
                                                          ValueKey<
                                                            _ApplePlayerViewMode
                                                          >(mode),
                                                      child: _buildModeContent(
                                                        context,
                                                        mode,
                                                        player,
                                                        lyricsProvider,
                                                        true,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                  ),
                                ),
                                if (!_isDesktop) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24.0,
                                    ),
                                    child: _buildPlayerControls(
                                      context,
                                      player,
                                      btnColor,
                                      mode,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

enum _ApplePlayerViewMode { nowPlaying, lyrics, queue, artist }

/// YouTube Music variant — currently reuses the Spotify layout.
