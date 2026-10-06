// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/features/connect/services/connect_models.dart';
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
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import '../../components/canvas_video.dart';
import '../../components/rotating_blurred_cover_background.dart';
import '../../components/inline_delay_editor.dart';
import 'package:wisp/services/system/app_focus_service.dart';

part '../desktop/apple_music_full_player.dart';

class AppleMusicFullScreenPlayer extends StatelessWidget {
  final ScrollController scrollController;
  final bool desktop;
  static final ValueNotifier<_ApplePlayerViewMode> _modeNotifier =
      ValueNotifier<_ApplePlayerViewMode>(_ApplePlayerViewMode.nowPlaying);
  static final Map<String, Future<String?>> _canvasUrlFutureCache =
      <String, Future<String?>>{};
  static final ValueNotifier<bool> _animatedCanvasTemporarilyDisabledNotifier =
      ValueNotifier<bool>(false);

  const AppleMusicFullScreenPlayer({
    required this.scrollController,
    this.desktop = false,
    super.key,
  });

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
    final lineState = lyricsProvider.getState(
      currentTrack,
      LyricsSyncMode.line,
    );
    if (!syncedState.isLoading &&
        syncedState.lyrics == null &&
        syncedState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.word);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final wordLyrics = syncedState.lyrics;
    final syncedLyrics = wordLyrics?.isWordSynced == true
        ? wordLyrics
        : syncedState.hasFetched && !syncedState.isLoading
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
        (syncedState.isLoading ||
            lineState.isLoading ||
            unsyncedState.isLoading) &&
        lyrics == null;

    if (lyricsProvider.isInitialized && !lyricsProvider.hasSources) {
      return Center(
        child: Text(
          'No lyrics providers available.\nAdd some in the settings!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[400], fontSize: 16, height: 1.4),
        ),
      );
    }

    if (isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (lyrics == null || lyrics.lines.isEmpty) {
      final noProviders = !lyricsProvider.hasSources;
      return Center(
        child: Text(
          noProviders
              ? 'No lyrics providers available.\nAdd some in the settings!'
              : 'No lyrics found',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[400], fontSize: 16, height: 1.4),
        ),
      );
    }

    final normalizedLyrics = removeEmptyLyricsLines(lyrics);
    if (normalizedLyrics.lines.isEmpty) {
      final noProviders = !lyricsProvider.hasSources;
      return Center(
        child: Text(
          noProviders
              ? 'No lyrics providers available.\nAdd some in the settings!'
              : 'No lyrics found',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[400], fontSize: 16, height: 1.4),
        ),
      );
    }
    final lyricsRenderMode = normalizedLyrics.isWordSynced
        ? LyricsSyncMode.word
        : normalizedLyrics.syncMode;

    return _AppleMusicLyricsView(
      key: ValueKey<String>('${currentTrack.id}_${normalizedLyrics.syncMode}'),
      lyrics: normalizedLyrics,
      lyricsRenderMode: lyricsRenderMode,
      currentTrack: currentTrack,
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

    final basePosition = context.select<PlaybackCoordinator, Duration>(
      (coordinator) => coordinator.effectiveInterpolatedPosition,
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
              if (artists.isEmpty && albumName.isEmpty)
                Text(
                  'No Artist - No Album',
                  style: TextStyle(color: Colors.grey[300], fontSize: 16),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: MarqueeText(
                    pauseWhenUnfocused: true,
                    text:
                        '${artists.map((a) => a.name).join(', ')} - $albumName',
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildProgressBar(context, player),
        _buildPlaybackControls(context, player),
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
      child: GenericIconButton(
        style: AppStyle.AppleMusic,
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

  @override
  Widget build(BuildContext context) {
    return Consumer2<global_audio_player.WispAudioHandler, LyricsProvider>(
      builder: (context, player, lyricsProvider, child) {
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
                        !animatedCanvasDisabled && isNowPlaying && hasCanvas;

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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24.0,
                                  ).add(EdgeInsets.only(top: topInset)),
                                  child: _buildHeader(context),
                                ),
                                SizedBox(height: isNowPlaying ? 56 : 16),
                                Flexible(
                                  fit: FlexFit.tight,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24.0,
                                    ),
                                    child: Column(
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
                                        SizedBox(height: isNowPlaying ? 10 : 4),
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

enum _ApplePlayerViewMode { nowPlaying, lyrics, queue }

class _AppleMusicLyricsView extends StatefulWidget {
  final LyricsResult lyrics;
  final LyricsSyncMode lyricsRenderMode;
  final GenericSong currentTrack;
  final global_audio_player.WispAudioHandler player;
  final LyricsProvider lyricsProvider;

  const _AppleMusicLyricsView({
    super.key,
    required this.lyrics,
    required this.lyricsRenderMode,
    required this.currentTrack,
    required this.player,
    required this.lyricsProvider,
  });

  @override
  State<_AppleMusicLyricsView> createState() => _AppleMusicLyricsViewState();
}

class _AppleMusicLyricsViewState extends State<_AppleMusicLyricsView>
    with SingleTickerProviderStateMixin {
  final GlobalKey _listKey = GlobalKey();
  late final ScrollController _scrollController = ScrollController();
  late List<GlobalKey> _lineKeys;
  late List<ValueNotifier<LyricsFrame>> _lineTimingNotifiers;
  Ticker? _positionTicker;
  VoidCallback? _focusListener;
  bool _freezeWhenUnfocused = false;
  int _currentLineIndex = -1;
  Set<int> _currentActiveIndices = {};
  int? _previousWaitingDotsIndex;
  int _lastFocusIndex = -1;
  bool _userInteracting = false;
  Timer? _resumeAutoScrollTimer;

  @override
  void initState() {
    super.initState();
    _initLines();
    _setupFocusListener();
    _startTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCurrentLine();
      final focusIndex = _lastFocusIndex >= 0 ? _lastFocusIndex : 0;
      _scrollToLine(focusIndex, instant: true);
    });
  }

  void _setupFocusListener() {
    _focusListener = () {
      if (!mounted) return;
      final isFocused = AppFocusService.instance.isFocused.value;
      if (isFocused) {
        if (_positionTicker != null && !_positionTicker!.isActive) {
          _positionTicker!.start();
        }
        _updateCurrentLine();
        if (!_userInteracting && _lastFocusIndex >= 0) {
          _scrollToLine(_lastFocusIndex);
        }
      } else if (_freezeWhenUnfocused) {
        _positionTicker?.stop();
      }
    };
    AppFocusService.instance.isFocused.addListener(_focusListener!);
  }

  void _initLines() {
    _lineKeys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
    final delayMs = (widget.lyricsProvider.getDelaySecondsCached(widget.currentTrack.id) * 1000).round();
    final initialPos = _effectivePositionMs(delayMs);
    final initialTiming = widget.lyricsRenderMode != LyricsSyncMode.unsynced
        ? resolveSyncedLyricsTiming(widget.lyrics.lines, initialPos)
        : null;
    final initialFrame = LyricsFrame(
      activeIndex: initialTiming?.activeIndex ?? 0,
      activeIndices: initialTiming?.activeIndices ?? const {0},
      timing: initialTiming,
      positionMs: initialPos,
      delayMs: delayMs,
    );
    _lineTimingNotifiers = List.generate(
      widget.lyrics.lines.length,
      (_) => ValueNotifier<LyricsFrame>(initialFrame),
    );
  }

  void _disposeLines() {
    for (final notifier in _lineTimingNotifiers) {
      notifier.dispose();
    }
  }

  @override
  void didUpdateWidget(_AppleMusicLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentTrack.id != oldWidget.currentTrack.id ||
        widget.lyrics.lines.length != oldWidget.lyrics.lines.length) {
      _resumeAutoScrollTimer?.cancel();
      _userInteracting = false;
      _disposeLines();
      _currentLineIndex = -1;
      _currentActiveIndices = {};
      _previousWaitingDotsIndex = null;
      _lastFocusIndex = -1;
      _initLines();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    if (_focusListener != null) {
      AppFocusService.instance.isFocused.removeListener(_focusListener!);
      _focusListener = null;
    }
    _resumeAutoScrollTimer?.cancel();
    _positionTicker?.dispose();
    _disposeLines();
    _scrollController.dispose();
    super.dispose();
  }

  void _startTicker() {
    _positionTicker?.dispose();
    _positionTicker = createTicker((_) {
      if (!mounted) return;
      if (_freezeWhenUnfocused && !AppFocusService.instance.isFocused.value) {
        return;
      }
      _updateCurrentLine();
    });
    if (!_freezeWhenUnfocused || AppFocusService.instance.isFocused.value) {
      _positionTicker!.start();
    }
  }

  int _effectivePositionMs(int delayMs) {
    final basePos = context.read<PlaybackCoordinator>().effectiveInterpolatedPosition.inMilliseconds;
    final adjusted = basePos - delayMs;
    return adjusted < 0 ? 0 : adjusted;
  }

  void _updateCurrentLine() {
    final delayMs = (widget.lyricsProvider.getDelaySecondsCached(widget.currentTrack.id) * 1000).round();
    final effectivePosition = _effectivePositionMs(delayMs);

    if (widget.lyricsRenderMode == LyricsSyncMode.unsynced) {
      final newIndex = widget.lyrics.lines.isEmpty ? -1 : 0;
      if (newIndex != _currentLineIndex) {
        _currentLineIndex = newIndex;
        _currentActiveIndices = {0};
        _previousWaitingDotsIndex = null;
        _notifyTimingLines(const LyricsFrame.unsynced());
      }
      return;
    }

    final timing = resolveSyncedLyricsTiming(widget.lyrics.lines, effectivePosition);
    final waitingDotsIndex = (timing.showWaitingDots && timing.nextIndex != null)
        ? timing.nextIndex
        : null;
    final previousWaitingDotsIndex = _previousWaitingDotsIndex;
    _previousWaitingDotsIndex = waitingDotsIndex;

    final previousIndex = _currentLineIndex;
    final previousActiveIndices = _currentActiveIndices;
    final frame = LyricsFrame(
      activeIndex: timing.activeIndex,
      activeIndices: timing.activeIndices,
      timing: timing,
      positionMs: effectivePosition,
      delayMs: delayMs,
    );

    _currentLineIndex = timing.activeIndex;
    _currentActiveIndices = timing.activeIndices;

    final focusIndex = timing.activeIndex >= 0
        ? timing.activeIndex
        : (timing.nextIndex ?? timing.previousIndex ?? 0);

    if (focusIndex != _lastFocusIndex) {
      _lastFocusIndex = focusIndex;
      if (!_userInteracting) {
        _scrollToLine(focusIndex);
      }
    }

    _notifyTimingLines(
      frame,
      previousActiveIndices: previousActiveIndices,
      previousIndex: previousIndex,
      previousWaitingDotsIndex: previousWaitingDotsIndex,
    );
  }

  void _scrollToLine(int focusIndex, {bool instant = false, int retries = 3}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (focusIndex < 0 || focusIndex >= _lineKeys.length) return;
      final lineContext = _lineKeys[focusIndex].currentContext;
      final listContext = _listKey.currentContext;
      if (lineContext == null || listContext == null) {
        if (retries > 0) {
          _scrollToLine(focusIndex, instant: instant, retries: retries - 1);
        }
        return;
      }

      final lineBox = lineContext.findRenderObject() as RenderBox?;
      final listBox = listContext.findRenderObject() as RenderBox?;
      if (lineBox == null || listBox == null || !lineBox.hasSize || !listBox.hasSize) {
        if (retries > 0) {
          _scrollToLine(focusIndex, instant: instant, retries: retries - 1);
        }
        return;
      }

      final lineGlobalTop = lineBox.localToGlobal(Offset.zero).dy;
      final viewportGlobalTop = listBox.localToGlobal(Offset.zero).dy;
      final lineTopInViewport = lineGlobalTop - viewportGlobalTop;

      const topTargetOffset = 24.0;
      final currentOffset = _scrollController.offset;
      final targetOffset = (currentOffset + lineTopInViewport) - topTargetOffset;
      final clampedOffset = targetOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );

      if (instant) {
        _scrollController.jumpTo(clampedOffset);
      } else {
        _scrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _notifyTimingLines(
    LyricsFrame frame, {
    Set<int>? previousActiveIndices,
    int? previousIndex,
    int? previousWaitingDotsIndex,
  }) {
    final indices = <int>{
      ?previousIndex,
      ...?previousActiveIndices,
      ?previousWaitingDotsIndex,
      ...frame.activeIndices,
      frame.activeIndex,
      if (frame.timing?.showWaitingDots == true &&
          frame.timing?.nextIndex != null)
        frame.timing!.nextIndex!,
    };
    for (final index in indices) {
      if (index >= 0 && index < _lineTimingNotifiers.length) {
        _lineTimingNotifiers[index].value = frame;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.lyricsFullscreen,
      ),
    );
    _freezeWhenUnfocused = freezeWhenUnfocused;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomPadding = constraints.maxHeight * 0.75;

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _userInteracting = true;
                _resumeAutoScrollTimer?.cancel();
              } else if (notification is ScrollEndNotification) {
                if (_userInteracting) {
                  _resumeAutoScrollTimer?.cancel();
                  _resumeAutoScrollTimer = Timer(const Duration(seconds: 4), () {
                    if (!mounted) return;
                    _userInteracting = false;
                    final focusIndex = _lastFocusIndex >= 0 ? _lastFocusIndex : 0;
                    _scrollToLine(focusIndex);
                  });
                }
              } else if (notification is UserScrollNotification &&
                  notification.direction == ScrollDirection.idle &&
                  !_userInteracting) {
                // Idle notification when not user interacting
              }
              return false;
            },
            child: ListView.builder(
              key: _listKey,
              controller: _scrollController,
              scrollCacheExtent: ScrollCacheExtent.pixels(20000),
              itemCount: widget.lyrics.lines.length + 1,
              padding: EdgeInsets.fromLTRB(0, 24.0, 0, bottomPadding),
              itemBuilder: (context, index) {
                if (index == widget.lyrics.lines.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lyrics provided by ${widget.lyrics.providerLabel}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.left,
                        ),
                        if (widget.lyrics.attribution != null &&
                            widget.lyrics.attribution!.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _buildAttributionText(
                            widget.lyrics.attribution!,
                            baseStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                            linkStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return _AppleMusicLyricsLineItem(
                  key: _lineKeys[index],
                  line: widget.lyrics.lines[index],
                  index: index,
                  syncMode: widget.lyricsRenderMode,
                  frameListenable: _lineTimingNotifiers[index],
                  onSeek: (position) {
                    _resumeAutoScrollTimer?.cancel();
                    _userInteracting = false;
                    _lastFocusIndex = index;
                    _scrollToLine(index);
                    unawaited(
                      context.read<PlaybackCoordinator>().seek(position),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttributionText(
    String text, {
    required TextStyle baseStyle,
    required TextStyle linkStyle,
  }) {
    final spans = <InlineSpan>[];
    final linkRegex = RegExp(r'\[([^\]]+)\]\((https?://[^\)]+)\)');
    int lastMatchEnd = 0;

    for (final match in linkRegex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }
      final linkText = match.group(1) ?? '';
      final linkUrl = match.group(2) ?? '';
      spans.add(
        TextSpan(
          text: linkText,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(linkUrl);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.left,
    );
  }
}

class _AppleMusicLyricsLineItem extends StatefulWidget {
  final LyricsLine line;
  final int index;
  final LyricsSyncMode syncMode;
  final ValueListenable<LyricsFrame> frameListenable;
  final ValueChanged<Duration> onSeek;

  const _AppleMusicLyricsLineItem({
    super.key,
    required this.line,
    required this.index,
    required this.syncMode,
    required this.frameListenable,
    required this.onSeek,
  });

  @override
  State<_AppleMusicLyricsLineItem> createState() =>
      _AppleMusicLyricsLineItemState();
}

class _AppleMusicLyricsLineItemState extends State<_AppleMusicLyricsLineItem> {
  late List<TextSelection> _wordRanges;
  late List<List<TextSelection>> _bgWordRanges;

  String _formatBgContent(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
      return trimmed;
    }
    return '($trimmed)';
  }

  @override
  void initState() {
    super.initState();
    _initRanges();
  }

  @override
  void didUpdateWidget(_AppleMusicLyricsLineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.line != oldWidget.line) {
      _initRanges();
    }
  }

  void _initRanges() {
    _wordRanges = resolveWordRanges(widget.line.content, widget.line.words);
    _bgWordRanges = widget.line.background
        .map((bg) => resolveWordRanges(_formatBgContent(bg.content), bg.words))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LyricsFrame>(
      valueListenable: widget.frameListenable,
      builder: (context, frame, _) {
        final isSynced = widget.syncMode != LyricsSyncMode.unsynced;
        final timing = frame.timing;
        final anchorIndex = frame.activeIndex >= 0
            ? frame.activeIndex
            : (timing?.nextIndex ?? timing?.previousIndex ?? 0);
        final distance = (widget.index - anchorIndex).abs();
        final isLineActive = !isSynced ||
            frame.activeIndices.contains(widget.index) ||
            frame.activeIndex == widget.index;

        var opacity = (!isSynced || isLineActive)
            ? 1.0
            : (1.0 - (distance * 0.22)).clamp(0.16, 0.72);
        var fontSize = (!isSynced || isLineActive) ? 34.0 : 30.0;
        var fontWeight = (!isSynced || isLineActive) ? FontWeight.w700 : FontWeight.w600;
        var color = (!isSynced || isLineActive) ? Colors.white : Colors.grey[500]!;

        if (isSynced &&
            timing != null &&
            timing.shouldFadePreviousLine &&
            timing.previousIndex == widget.index &&
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

        final baseStyle = TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.1,
        );
        final defaultTextStyle = DefaultTextStyle.of(context).style;
        final effectiveBaseStyle = defaultTextStyle.merge(baseStyle);
        final textScaler = MediaQuery.textScalerOf(context);

        final isRight = widget.line.isRightSpeaker;
        final textAlign = isRight ? TextAlign.right : TextAlign.left;
        final alignment = isRight ? Alignment.centerRight : Alignment.centerLeft;

        final Widget textContent;
        if (isLineActive &&
            widget.syncMode == LyricsSyncMode.word &&
            widget.line.hasWordTiming) {
          final activeWordColor = Colors.white.withValues(alpha: opacity);
          final inactiveWordColor =
              Colors.white.withValues(alpha: 0.45 * opacity);

          textContent = LayoutBuilder(
            builder: (context, constraints) {
              final layoutWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;

              return Stack(
                alignment: alignment,
                children: [
                  Text(
                    widget.line.content,
                    style: effectiveBaseStyle.copyWith(color: inactiveWordColor),
                    textAlign: textAlign,
                  ),
                  ClipPath(
                    clipper: LyricsLineFillClipper(
                      lineContent: widget.line.content,
                      words: widget.line.words,
                      wordRanges: _wordRanges,
                      lineEndTimeMs: widget.line.endTimeMs,
                      style: effectiveBaseStyle,
                      textScaler: textScaler,
                      layoutWidth: layoutWidth,
                      positionMs: frame.positionMs,
                    ),
                    child: Text(
                      widget.line.content,
                      style: effectiveBaseStyle.copyWith(color: activeWordColor),
                      textAlign: textAlign,
                    ),
                  ),
                ],
              );
            },
          );
        } else {
          textContent = Text(
            widget.line.content,
            style: effectiveBaseStyle,
            textAlign: textAlign,
          );
        }

        // Synchronized Background vocal lines rendering if present
        Widget? backgroundContent;
        if (widget.line.hasBackground) {
          final bgWidgets = <Widget>[];
          final baseBgFontSize = fontSize * 0.72;

          for (int bIdx = 0; bIdx < widget.line.background.length; bIdx++) {
            final bg = widget.line.background[bIdx];
            final bgRanges = (bIdx < _bgWordRanges.length)
                ? _bgWordRanges[bIdx]
                : <TextSelection>[];
            final bgFormattedText = _formatBgContent(bg.content);

            // Timing checks for this background vocal phrase
            final bgStart = bg.startTimeMs;
            int? resolvedBgEnd = bg.endTimeMs;
            if (resolvedBgEnd == null && bg.words.isNotEmpty) {
              final lastWord = bg.words.last;
              resolvedBgEnd = lastWord.endTimeMs ?? (lastWord.startTimeMs + 800);
            }
            resolvedBgEnd ??= (widget.line.endTimeMs ?? (bgStart + 2000));

            final isBgActive = isSynced &&
                isLineActive &&
                frame.positionMs >= bgStart &&
                frame.positionMs < resolvedBgEnd;
            final isBgPast = isSynced &&
                (frame.positionMs >= resolvedBgEnd ||
                    (!isLineActive && frame.positionMs >= bgStart));
            final isBgUpcoming = isSynced && frame.positionMs < bgStart;

            double bgOpacity = opacity;
            if (isSynced) {
              if (isBgActive) {
                bgOpacity = 1.0;
              } else if (isBgPast) {
                bgOpacity = (opacity * 0.65).clamp(0.2, 0.7);
              } else if (isBgUpcoming) {
                bgOpacity = (opacity * 0.35).clamp(0.1, 0.4);
              }
            }

            final inactiveBgColor = Color.lerp(Colors.grey[500]!, Colors.black, 0.2) ?? Colors.grey[600]!;
            final bgBaseStyle = effectiveBaseStyle.copyWith(
              fontSize: baseBgFontSize,
              fontStyle: FontStyle.italic,
              color: (isBgActive ? Colors.white : inactiveBgColor).withValues(
                alpha: (isBgActive ? bgOpacity : (inactiveBgColor.a * bgOpacity)).clamp(0.0, 1.0),
              ),
            );

            Widget phraseWidget;
            if (isBgActive && bg.hasWordTiming && bgRanges.isNotEmpty) {
              final activeWordColor = Colors.white.withValues(alpha: bgOpacity);
              final inactiveWordColor = Colors.white.withValues(alpha: 0.45 * bgOpacity);

              phraseWidget = LayoutBuilder(
                builder: (context, constraints) {
                  final bgLayoutWidth = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : MediaQuery.sizeOf(context).width;

                  return Stack(
                    alignment: alignment,
                    children: [
                      Text(
                        bgFormattedText,
                        style: bgBaseStyle.copyWith(color: inactiveWordColor),
                        textAlign: textAlign,
                      ),
                      ClipPath(
                        clipper: LyricsLineFillClipper(
                          lineContent: bgFormattedText,
                          words: bg.words,
                          wordRanges: bgRanges,
                          lineEndTimeMs: resolvedBgEnd,
                          style: bgBaseStyle,
                          textScaler: textScaler,
                          layoutWidth: bgLayoutWidth,
                          positionMs: frame.positionMs,
                        ),
                        child: Text(
                          bgFormattedText,
                          style: bgBaseStyle.copyWith(color: activeWordColor),
                          textAlign: textAlign,
                        ),
                      ),
                    ],
                  );
                },
              );
            } else {
              phraseWidget = Text(
                bgFormattedText,
                style: bgBaseStyle,
                textAlign: textAlign,
              );
            }

            bgWidgets.add(
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: phraseWidget,
              ),
            );
          }

          if (bgWidgets.isNotEmpty) {
            backgroundContent = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: bgWidgets,
            );
          }
        }

        final canSeek = isSynced && widget.line.startTimeMs > 0;

        final fullContent = backgroundContent == null
            ? textContent
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  textContent,
                  backgroundContent,
                ],
              );

        final lineWidget = AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: opacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              mouseCursor: canSeek
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              onTap: canSeek
                  ? () => widget.onSeek(
                      Duration(
                        milliseconds: widget.line.startTimeMs + frame.delayMs,
                      ),
                    )
                  : null,
              child: Align(
                alignment: alignment,
                child: fullContent,
              ),
            ),
          ),
        );

        final showWaitingDots = isSynced &&
            timing != null &&
            timing.showWaitingDots &&
            timing.nextIndex == widget.index;

        if (!showWaitingDots) {
          return lineWidget;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            _buildWaitingDots(timing.progressToNext),
            lineWidget,
          ],
        );
      },
    );
  }

  Widget _buildWaitingDots(double progress) {
    const dotSize = 13.0;
    final dots = List<Widget>.generate(3, (index) {
      final start = index / 3;
      final end = (index + 1) / 3;
      final localProgress =
          ((progress - start) / (end - start)).clamp(0.0, 1.0);
      final opacity = lerpDouble(0.2, 1.0, localProgress)!;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: dotSize,
          height: dotSize,
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
}
