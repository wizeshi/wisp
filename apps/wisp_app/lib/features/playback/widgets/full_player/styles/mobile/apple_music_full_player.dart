// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_svg/svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/sources/audio/models/audio_quality_info.dart';
import 'package:wisp/features/connect/services/connect_models.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';
import 'package:wisp/features/playback/widgets/player_bar/components/audio_quality_badge.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/features/connect/widgets/connect_menu.dart';
import 'package:wisp/shared/widgets/display/marquee_text.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart'
    as global_audio_player;
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/connect/state/connect_session_provider.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/shared/widgets/menus/adaptive_context_menu.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/shared/widgets/playback/track_cache_indicator.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import 'package:wisp/shared/widgets/lyrics/word_fill_lyrics_line.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/rows/track_row.dart';
import '../../components/canvas_video.dart';
import '../../components/clickable_artist_names.dart';
import '../../components/full_player_lyrics_view.dart';
import '../../components/player_hero.dart';
import '../../components/rotating_blurred_cover_background.dart';
import '../../components/inline_delay_editor.dart';

part '../desktop/apple_music_full_player.dart';

class AppleMusicFullScreenPlayer extends StatelessWidget {
  final ScrollController scrollController;
  final bool desktop;
  static final ValueNotifier<_ApplePlayerViewMode> _modeNotifier =
      ValueNotifier<_ApplePlayerViewMode>(_ApplePlayerViewMode.nowPlaying);
  static final Map<String, Future<String?>> _canvasUrlFutureCache =
      <String, Future<String?>>{};

  const AppleMusicFullScreenPlayer({
    required this.scrollController,
    this.desktop = false,
    super.key,
  });

  static Future<void> showTrackMenuWithCanvasToggle(
    BuildContext context, {
    required GenericSong track,
    Offset? globalPosition,
    Rect? anchorRect,
  }) async {
    final prefs = context.read<PreferencesProvider>();
    final canvasEnabled = prefs.animatedCanvasEnabled;
    final supportsCanvas = context.read<MetadataManager>().hasCapability(
      MetadataCapability.canvas,
      source: track.source,
    );
    await EntityContextMenus.showTrackMenu(
      context,
      track: track,
      globalPosition: globalPosition,
      anchorRect: anchorRect,
      onBeforeNavigate: () =>
          AppNavigation.instance.disableFullPlayerDesktopMode(),
      additionalActions: [
        if (supportsCanvas)
          ContextMenuAction(
            id: 'toggle-animated-canvas-pref',
            label: canvasEnabled
                ? 'Disable Animated Canvas'
                : 'Enable Animated Canvas',
            icon: canvasEnabled
                ? Icons.motion_photos_off
                : Icons.motion_photos_on,
            onSelected: (_) {
              unawaited(prefs.setAnimatedCanvasEnabled(!canvasEnabled));
            },
          ),
      ],
    );
  }

  bool get _isDesktop =>
      desktop || Platform.isLinux || Platform.isMacOS || Platform.isWindows;

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
    final Widget imageContent = ClipRRect(
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
    );

    if (!size.isFinite) {
      return SizedBox.expand(child: imageContent);
    }

    return SizedBox(
      width: size,
      height: size,
      child: imageContent,
    );
  }

  Widget _buildAnimatedCoverSection(
    BuildContext context,
    _ApplePlayerViewMode mode,
    dynamic currentTrack,
    String imageUrl,
    bool hideNowPlayingCover, {
    double? maxCoverSize,
  }) {
    final isNowPlaying = mode == _ApplePlayerViewMode.nowPlaying;
    final onCoverTap = isNowPlaying
        ? null
        : () => _setMode(_ApplePlayerViewMode.nowPlaying);
    final double expandedSize = math.min(
      MediaQuery.sizeOf(context).width - 48,
      maxCoverSize ?? 360.0,
    );
    final shouldHideCover = isNowPlaying && hideNowPlayingCover;
    final compactSize = 64.0;
    final List<GenericSimpleArtist> compactArtists = currentTrack is GenericSong
        ? currentTrack.artists
        : const <GenericSimpleArtist>[];
    final GenericSimpleAlbum? compactAlbum =
        currentTrack is GenericSong ? currentTrack.album : null;

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
                        child: PlayerArtworkHero(
                          enabled: !_isDesktop,
                          borderRadius: BorderRadius.circular(8),
                          child: _buildCoverImageBox(
                            context,
                            imageUrl,
                            double.infinity,
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
                              Row(
                                children: [
                                  Flexible(
                                    child: GestureDetector(
                                      onTap: compactAlbum != null &&
                                              compactAlbum.id.isNotEmpty
                                          ? () => unawaited(
                                              _openAlbumFromPlayer(
                                                compactAlbum,
                                              ),
                                            )
                                          : null,
                                      child: Text(
                                        currentTrack?.title ??
                                            'No track playing',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (currentTrack is GenericSong)
                                    TrackBadges(
                                      track: currentTrack,
                                      leadingSpacing: 6,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              ClickableArtistNames(
                                artists: compactArtists,
                                emptyText: 'No Artist',
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

  Future<void> _openAlbumFromPlayer(
    GenericSimpleAlbum album,
  ) async {
    await AppNavigation.instance.closeFullPlayer();
    NavigationService.instance.pushList(
      id: album.id,
      type: 'album',
      source: album.source,
    );
  }

  Widget _buildLyricsModeContent(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    LyricsProvider lyricsProvider,
  ) {
    return FullPlayerLyricsSection(
      player: player,
      lyricsProvider: lyricsProvider,
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
            GenericButton.text(
              style: AppStyle.AppleMusic,
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
                      child: TrackRow(
                        track: track,
                        height: 56,
                        artworkSize: ArtworkSize.large,
                        isCurrentOverride: isCurrent,
                        isPlayingOverride: isCurrent && player.isPlaying,
                        playIconLocation: PlayIconLocation.art,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Icon(
                            Icons.drag_handle,
                            color: Colors.grey[500],
                            size: 22,
                          ),
                        ),
                        onTap: () {
                          if (isCurrent) {
                            player.isPlaying ? player.pause() : player.play();
                          } else {
                            unawaited(
                              context
                                  .read<PlaybackCoordinator>()
                                  .playQueueIndex(queueIndex),
                            );
                          }
                        },
                        onPlayPause: () {
                          if (isCurrent) {
                            player.isPlaying ? player.pause() : player.play();
                          } else {
                            unawaited(
                              context
                                  .read<PlaybackCoordinator>()
                                  .playQueueIndex(queueIndex),
                            );
                          }
                        },
                        onSecondaryTapDown: (details) {
                          EntityContextMenus.showTrackMenu(
                            context,
                            track: track,
                            globalPosition: details.globalPosition,
                          );
                        },
                        onLongPress: () {
                          EntityContextMenus.showTrackMenu(
                            context,
                            track: track,
                          );
                        },
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
        child = Builder(
          builder: (lyricsContext) =>
              _buildLyricsModeContent(lyricsContext, player, lyricsProvider),
        );
        break;
      case _ApplePlayerViewMode.queue:
        child = _buildQueueModeContent(context, player, isMobile);
        break;
      case _ApplePlayerViewMode.nowPlaying:
        child = const SizedBox.shrink();
        break;
    }

    return SizedBox.expand(child: child);
  }

  void _pruneFutureCache<T>(Map<String, Future<T>> cache, {int maxSize = 48}) {
    while (cache.length > maxSize) {
      cache.remove(cache.keys.first);
    }
  }

  Future<String?>? _getCanvasUrlFuture(
    MetadataManager metadataManager,
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
    final future = metadataManager.getCanvasUrl(
      trackId,
      source: currentTrack.source,
    );
    _canvasUrlFutureCache[trackId] = future;
    return future;
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
                  GenericIconButton(
                    style: AppStyle.AppleMusic,
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
                  GenericIconButton(
                    style: AppStyle.AppleMusic,
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
              child: GenericIconButton(
                style: AppStyle.AppleMusic,
                icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                color: Colors.white,
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(child: _isDesktop ? centerInfo : mobileInfo),
            SizedBox(
              width: 40,
              child: GenericIconButton(
                style: AppStyle.AppleMusic,
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

    final wordState = lyricsProvider.getState(
      currentTrack,
      LyricsSyncMode.word,
    );
    final lineState = lyricsProvider.getState(
      currentTrack,
      LyricsSyncMode.line,
    );
    if (!wordState.isLoading &&
        wordState.lyrics == null &&
        wordState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.word);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final wordLyrics = wordState.lyrics;
    final lyrics = wordLyrics?.isWordSynced == true
        ? wordLyrics
        : wordState.hasFetched && !wordState.isLoading
        ? lineState.lyrics ?? wordLyrics
        : null;

    if ((wordLyrics == null || !wordLyrics.isWordSynced) &&
        !lineState.isLoading &&
        lineState.lyrics == null &&
        lineState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.line);
      });
    }

    if (lyrics == null || lyrics.lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final lines = nonEmptyLyricsLines(lyrics.lines);
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();

    return ValueListenableBuilder<Duration>(
      valueListenable:
          context.read<PlaybackCoordinator>().effectivePositionListenable,
      builder: (context, basePosition, _) {
        final adjustedPosition = basePosition.inMilliseconds - delayMs;
        final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;

        final timing = lyrics.syncMode != LyricsSyncMode.unsynced
            ? resolveSyncedLyricsTiming(lines, effectivePosition)
            : null;
        final line = _getSingleLine(lyrics, effectivePosition);
        final showWaitingPlaceholder =
            lyrics.syncMode != LyricsSyncMode.unsynced &&
            timing != null &&
            timing.activeIndex < 0 &&
            timing.nextIndex != null &&
            line == null;
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
            : WordFillLyricsLine(
                key: ValueKey<String>(
                  '${line.startTimeMs}_${line.content.trim()}',
                ),
                line: line,
                positionMs: effectivePosition,
                isActive: effectivePosition >= line.startTimeMs,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                activeColor: Colors.white,
                inactiveColor: Colors.grey[400]!,
                enableTicker: true,
              ),
            ),
          );
      },
    );
  }

  Widget _buildTrackInfo(
    BuildContext context,
    GenericSong? currentTrack,
    Color likeColor,
    bool isDesktop,
  ) {
    final title = currentTrack?.title ?? 'No track playing';
    final artists = currentTrack?.artists ?? const <GenericSimpleArtist>[];
    final album = currentTrack?.album;
    final hasAlbum = album != null && album.id.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: GestureDetector(
                      onTap: hasAlbum
                          ? () => unawaited(
                              _openAlbumFromPlayer(album),
                            )
                          : null,
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
                  if (currentTrack != null)
                    TrackBadges(track: currentTrack, leadingSpacing: 6),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: double.infinity,
                child: ClickableArtistNames(
                  artists: artists,
                  album: album,
                  emptyText: 'No Artist',
                  style: TextStyle(color: Colors.grey[300], fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        LikeButton(
          track: currentTrack,
          iconSize: 22,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          likedIcon: CupertinoIcons.heart_fill,
          notLikedIcon: CupertinoIcons.heart,
          color: likeColor,
        ),
        if (isDesktop) ...[
          const SizedBox(width: 4),
          Builder(
            builder: (buttonContext) => _buildDesktopCupertinoButton(
              tooltip: 'More options',
              minimumSize: 32,
              onPressed: currentTrack == null
                  ? null
                  : () => _openDesktopTrackMenu(buttonContext, currentTrack),
              child: const Icon(CupertinoIcons.ellipsis, size: 22),
            ),
          ),
        ],
      ],
    );
  }

  LyricsLine? _getSingleLine(LyricsResult lyrics, int positionMs) {
    final lines = nonEmptyLyricsLines(lyrics.lines);
    if (lines.isEmpty) return null;
    if (lyrics.syncMode == LyricsSyncMode.unsynced) {
      return lines.first;
    }
    final timing = resolveSyncedLyricsTiming(lines, positionMs);
    if (timing.activeIndex >= 0 && timing.activeIndex < lines.length) {
      return lines[timing.activeIndex];
    }
    // Lead-in: show next line ahead of time (up to 1800ms) so user can read before singing starts
    if (timing.nextIndex != null && timing.nextIndex! < lines.length) {
      final nextLine = lines[timing.nextIndex!];
      final timeToNext = nextLine.startTimeMs - positionMs;
      if (timeToNext <= 1800) {
        return nextLine;
      }
    }
    // Hold previous line briefly (up to 800ms) so it doesn't vanish jarringly
    if (timing.previousIndex != null && timing.previousIndex! < lines.length) {
      final prevLine = lines[timing.previousIndex!];
      final prevEnd = prevLine.endTimeMs ?? (prevLine.startTimeMs + 3000);
      if (positionMs - prevEnd < 800) {
        return prevLine;
      }
    }
    return null;
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
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProgressBar(context, player),
        const SizedBox(height: 12),
        _buildPlaybackControls(context, player),
        const SizedBox(height: 8),
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
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, livePlayer, child) =>
          _buildDesktopPlayerControlsContent(
            context,
            livePlayer,
            btnColor,
            mode,
          ),
    );
  }

  Widget _buildDesktopPlayerControlsContent(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    Color btnColor,
    _ApplePlayerViewMode mode,
  ) {
    return Column(
      children: [
        _buildProgressBar(context, player),
        const SizedBox(height: 8),
        Row(
          children: [
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
            Expanded(
              child: Row(
                spacing: 24,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildModeActionButton(
                    tooltip: player.isDJMode
                        ? 'Unavailable in DJ mode'
                        : 'Shuffle',
                    icon: CupertinoIcons.shuffle,
                    selected: !player.isDJMode && player.shuffleEnabled,
                    onTap: player.isDJMode
                        ? null
                        : () => context
                              .read<PlaybackCoordinator>()
                              .toggleShuffle(),
                    activeColor: btnColor,
                  ),
                  _buildDesktopTransportControls(context, player),
                  _buildModeActionButton(
                    tooltip: player.isDJMode
                        ? 'Unavailable in DJ mode'
                        : 'Repeat',
                    icon:
                        player.repeatMode == global_audio_player.RepeatMode.one
                        ? CupertinoIcons.repeat_1
                        : CupertinoIcons.repeat,
                    selected:
                        !player.isDJMode &&
                        player.repeatMode != global_audio_player.RepeatMode.off,
                    onTap: player.isDJMode
                        ? null
                        : () => context
                              .read<PlaybackCoordinator>()
                              .toggleRepeat(),
                    activeColor: btnColor,
                  ),
                ],
              ),
            ),
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
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildDesktopCupertinoButton(
              tooltip: player.volume <= 0.001 ? 'Unmute' : 'Mute',
              minimumSize: 28,
              onPressed: () => unawaited(player.toggleMute()),
              child: Icon(
                player.volume <= 0.001 ? Icons.volume_off : Icons.volume_up,
                size: 18,
                color: Colors.grey[300],
              ),
            ),
            Expanded(
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
                  overlayColor: btnColor.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: player.volume.clamp(0.0, 1.0).toDouble(),
                  onChanged: (value) => unawaited(player.setVolume(value)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
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

    const mainIconSize = 44.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        _buildDesktopCupertinoButton(
          tooltip: 'Previous',
          minimumSize: 44,
          onPressed: player.queueTracks.isEmpty
              ? null
              : () {
                  context.read<PlaybackCoordinator>().skipPrevious();
                },
          child: const Icon(
            CupertinoIcons.backward_fill,
            size: mainIconSize,
            color: Colors.white,
          ),
        ),
        _buildDesktopCupertinoButton(
          tooltip: isPlaying ? 'Pause' : 'Play',
          minimumSize: 44,
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
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  size: mainIconSize,
                  color: Colors.white,
                ),
        ),
        _buildDesktopCupertinoButton(
          tooltip: 'Next',
          minimumSize: 44,
          onPressed: player.queueTracks.isEmpty
              ? null
              : () {
                  context.read<PlaybackCoordinator>().skipNext();
                },
          child: const Icon(
            CupertinoIcons.forward_fill,
            size: mainIconSize,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopCupertinoButton({
    required String tooltip,
    required Widget child,
    required VoidCallback? onPressed,
    double minimumSize = 36,
  }) {
    return GenericIconButton(
      style: AppStyle.AppleMusic,
      tooltip: tooltip,
      icon: child,
      padding: EdgeInsets.zero,
      minimumSize: Size.square(minimumSize),
      onPressed: onPressed,
    );
  }

  void _openDesktopTrackMenu(BuildContext buttonContext, GenericSong track) {
    final overlay = Overlay.of(buttonContext).context.findRenderObject();
    final button = buttonContext.findRenderObject();
    if (overlay is! RenderBox || button is! RenderBox) {
      unawaited(showTrackMenuWithCanvasToggle(buttonContext, track: track));
      return;
    }

    final anchorRect = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );
    unawaited(
      showTrackMenuWithCanvasToggle(
        buttonContext,
        track: track,
        anchorRect: anchorRect,
      ),
    );
  }

  Widget _buildModeActionButton({
    required String tooltip,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
    required Color activeColor,
  }) {
    final secondaryIconSize = 20.0;

    return _buildDesktopCupertinoButton(
      tooltip: tooltip,
      onPressed: onTap,
      child: Icon(
        icon,
        size: secondaryIconSize,
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
            selected:
                !player.isDJMode &&
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
        child: GenericIconButton(
          style: AppStyle.AppleMusic,
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
              GenericIconButton(
                style: AppStyle.AppleMusic,
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
              GenericIconButton(
                style: AppStyle.AppleMusic,
                icon: const Icon(CupertinoIcons.antenna_radiowaves_left_right),
                iconSize: 24,
                color: handoffColor,
                onPressed: () {
                  unawaited(_openHandoffSheet(context));
                },
              ),
              GenericIconButton(
                style: AppStyle.AppleMusic,
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
    final coordinator = context.read<PlaybackCoordinator>();
    final useHandoffState = context.select<PlaybackCoordinator, bool>(
      (c) => c.useLinkedPlaybackState,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final duration = player.duration;

    return ValueListenableBuilder<Duration>(
      valueListenable: coordinator.effectivePositionListenable,
      builder: (context, position, _) {
        final isLoading = _isUiLoading(player, useHandoffState, position);
        final bufferedPosition = coordinator.effectiveBufferedPosition;
        final clampedPosition = position > duration ? duration : position;
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        final bufferedProgress = duration.inMilliseconds > 0
            ? (bufferedPosition.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;

        if (isLoading) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.grey[400],
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.grey[300]!),
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
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 3,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 2),
                  activeTrackColor: Colors.grey[300],
                  secondaryActiveTrackColor: Colors.white.withValues(
                    alpha: 0.45,
                  ),
                  inactiveTrackColor: Colors.grey[400],
                  thumbColor: Colors.white,
                  overlayColor: colorScheme.primary.withValues(alpha: 0.2),
                ),
                child: Slider(
                  padding: EdgeInsets.zero,
                  value: progress,
                  secondaryTrackValue: bufferedProgress,
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
                    _formatDuration(clampedPosition),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11,
                    ),
                  ),

                  AudioQualityBadge(
                    preferredColor: Colors.white,
                    child:
                        Selector<
                          global_audio_player.WispAudioHandler,
                          ActiveTrackQualityInfo?
                        >(
                          selector: (context, player) =>
                              player.activeTrackQuality,
                          builder: (context, quality, child) {
                            if (quality == null) {
                              return const SizedBox.shrink();
                            }

                            String label = 'Standard';

                            if (quality.isHiRes) {
                              label = 'Hi-Res Lossless';
                            } else if (quality.isLossless) {
                              label = 'Lossless';
                            } else if (quality.bitrate != null) {
                              if (quality.bitrate! >= 320) {
                                label = 'High Quality';
                              } else if (quality.bitrate! < 320) {
                                label = 'Standard';
                              }
                            }

                            Widget? icon;

                            if (quality.isHiRes || quality.isLossless) {
                              icon = SvgPicture.network(
                                "https://upload.wikimedia.org/wikipedia/commons/0/0d/Apple_Lossless_logo.svg",
                                fit: BoxFit.fill,
                                colorFilter: ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              );
                            } else if (quality.bitrate != null &&
                                quality.bitrate! >= 320) {
                              icon = Icon(
                                CupertinoIcons.checkmark_seal_fill,
                                color: Colors.white,
                                size: 12,
                              );
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (icon != null) ...[
                                    icon,
                                    const SizedBox(width: 4),
                                  ],

                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                  ),

                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11,
                    ),
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
        GenericIconButton(
          style: AppStyle.AppleMusic,
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
        GenericIconButton(
          style: AppStyle.AppleMusic,
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
    final useHandoffState = context.select<PlaybackCoordinator, bool>(
      (coordinator) => coordinator.useLinkedPlaybackState,
    );
    final isLoading = _isUiLoading(player, useHandoffState);
    if (isLoading) {
      return const SizedBox(
        width: 72,
        height: 72,
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle),
          child: Center(
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
      width: 72,
      height: 72,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: GenericIconButton(
        style: AppStyle.AppleMusic,
        icon: Icon(
          isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
        ),
        iconSize: 48,
        color: Colors.white,
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
    bool useHandoffState, [
    Duration? position,
  ]) {
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
        (position ?? player.position).inMilliseconds <= 0;
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

  @override
  Widget build(BuildContext context) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final currentTrack = player.currentTrack;
        final useCanvas = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.animatedCanvasEnabled,
        );
        final metadataManager = context.read<MetadataManager>();
        final canUseCanvas =
            useCanvas &&
            currentTrack != null &&
            metadataManager.hasCapability(
              MetadataCapability.canvas,
              source: currentTrack.source,
            );
        final Future<String?>? canvasFuture = _getCanvasUrlFuture(
          metadataManager,
          currentTrack,
          canUseCanvas,
        );

        final viewPadding = MediaQuery.viewPaddingOf(context);
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

            return ValueListenableBuilder<_ApplePlayerViewMode>(
              valueListenable: _modeNotifier,
              builder: (context, mode, _) {
                final isNowPlaying =
                    mode == _ApplePlayerViewMode.nowPlaying;
                final useNowPlayingCanvas = isNowPlaying && hasCanvas;

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
                      child: SingleChildScrollView(
                        controller: scrollController,
                        physics: const ClampingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        child: SizedBox(
                          height: MediaQuery.sizeOf(context).height,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: bottomInset + 16),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24.0,
                                  ).add(EdgeInsets.only(top: topInset + 8.0)),
                                  child: _buildHeader(context),
                                ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final availableForCover = math.max(
                                      160.0,
                                      constraints.maxHeight - 130.0,
                                    );
                                    final maxCoverSize = math
                                        .min(
                                          constraints.maxWidth,
                                          availableForCover,
                                        )
                                        .clamp(160.0, 360.0);
                                    final topSpacerHeight = isNowPlaying
                                        ? math.max(
                                            0.0,
                                            (availableForCover -
                                                    maxCoverSize) /
                                                2.0,
                                          )
                                        : 0.0;
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 340,
                                          ),
                                          curve: Curves.easeInOutCubic,
                                          height: topSpacerHeight,
                                        ),
                                        KeyedSubtree(
                                          key: const ValueKey(
                                            'apple-cover-section',
                                          ),
                                          child: _buildAnimatedCoverSection(
                                            context,
                                            mode,
                                            currentTrack,
                                            imageUrl,
                                            useNowPlayingCanvas,
                                            maxCoverSize: maxCoverSize,
                                          ),
                                        ),
                                        if (isNowPlaying) ...[
                                          const Spacer(),
                                          Consumer<LyricsProvider>(
                                            builder: (ctx, lyricsProvider, _) =>
                                                _buildSingleLyricsLine(
                                                  ctx,
                                                  player,
                                                  lyricsProvider,
                                                ),
                                          ),
                                          const SizedBox(height: 12),
                                          _buildTrackInfo(
                                            context,
                                            currentTrack,
                                            btnColor,
                                            false,
                                          ),
                                          const SizedBox(height: 12),
                                        ] else ...[
                                          const SizedBox(height: 12),
                                          Expanded(
                                            child: AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 280,
                                              ),
                                              switchInCurve: Curves.easeOut,
                                              switchOutCurve: Curves.easeIn,
                                              child: KeyedSubtree(
                                                key:
                                                    ValueKey<
                                                      _ApplePlayerViewMode
                                                    >(mode),
                                                child: _buildModeContent(
                                                  context,
                                                  mode,
                                                  player,
                                                  context.read<LyricsProvider>(),
                                                  true,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
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
                          ],
                        ),
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
      },
    );
  }
}

enum _ApplePlayerViewMode { nowPlaying, lyrics, queue }
