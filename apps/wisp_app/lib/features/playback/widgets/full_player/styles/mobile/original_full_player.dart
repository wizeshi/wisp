// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/svg.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/audio/models/audio_quality_info.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/connect/services/connect_models.dart';
import 'package:wisp/features/connect/state/connect_session_provider.dart';
import 'package:wisp/features/connect/widgets/connect_menu.dart';
import 'package:wisp/features/navigation/router/navigation_service.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/playback/views/queue_view.dart';
import 'package:wisp/features/playback/widgets/player_bar/components/audio_quality_badge.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart'
    as global_audio_player;
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/shared/widgets/connect/connect_device_indicator.dart';
import 'package:wisp/shared/widgets/display/marquee_text.dart';
import 'package:wisp/shared/widgets/lyrics/word_fill_lyrics_line.dart';
import 'package:wisp/shared/widgets/playback/track_cache_indicator.dart';

import '../../components/canvas_video.dart';
import '../../components/clickable_artist_names.dart';
import '../../components/full_player_lyrics_view.dart';
import '../../components/inline_delay_editor.dart';
import '../../components/player_hero.dart';
import '../../components/rotating_blurred_cover_background.dart';
import 'apple_music_full_player.dart';

enum OriginalMobilePlayerMode { player, lyrics, queue }

/// Material 3 Expressive mobile full-screen player for the Original style.
class OriginalMobileFullScreenPlayer extends StatefulWidget {
  final ScrollController scrollController;

  const OriginalMobileFullScreenPlayer({
    required this.scrollController,
    super.key,
  });

  @override
  State<OriginalMobileFullScreenPlayer> createState() =>
      _OriginalMobileFullScreenPlayerState();
}

class _OriginalMobileFullScreenPlayerState
    extends State<OriginalMobileFullScreenPlayer> {
  static final Map<String, Future<String?>> _canvasUrlFutureCache =
      <String, Future<String?>>{};

  OriginalMobilePlayerMode _mode = OriginalMobilePlayerMode.player;

  void _setMode(OriginalMobilePlayerMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
    });
  }

  Future<String?>? _getCanvasUrlFuture(
    MetadataManager metadataManager,
    GenericSong? currentTrack,
    bool canUseCanvas,
  ) {
    if (!canUseCanvas || currentTrack == null) {
      return null;
    }
    final cached = _canvasUrlFutureCache[currentTrack.id];
    if (cached != null) {
      return cached;
    }
    while (_canvasUrlFutureCache.length > 48) {
      _canvasUrlFutureCache.remove(_canvasUrlFutureCache.keys.first);
    }
    final future = metadataManager.getCanvasUrl(
      currentTrack.id,
      source: currentTrack.source,
    );
    _canvasUrlFutureCache[currentTrack.id] = future;
    return future;
  }

  Future<void> _openAlbumFromPlayer(GenericSimpleAlbum album) async {
    await AppNavigation.instance.closeFullPlayer();
    NavigationService.instance.pushList(
      id: album.id,
      type: 'album',
      source: album.source,
    );
  }

  Future<void> _openHandoffSheet(BuildContext context) async {
    final connect = context.read<ConnectSessionProvider>();
    connect.startDiscovery();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.75;
        return SafeArea(
          top: false,
          child: Container(
            height: maxHeight,
            decoration: const BoxDecoration(
              color: Color(0xFF171717),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
    if (useHandoffState) return false;
    if (player.isLoading || player.isBuffering || player.isTrackTransitioning) {
      return true;
    }
    if (player.currentTrack == null) return false;
    return !player.isPlaying &&
        player.duration.inMilliseconds == 0 &&
        (position ?? player.position).inMilliseconds <= 0;
  }

  Widget _buildHeader(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
  ) {
    final connect = context.watch<ConnectSessionProvider>();
    final contextType = player.playbackContext?.type;
    final contextName = player.playbackContext?.name;

    String firstLine = 'PLAYING FROM';
    String secondLine = '';

    if (contextType != null &&
        contextName != null &&
        contextName.isNotEmpty) {
      secondLine = contextType == global_audio_player.PlaybackContextType.artist
          ? 'Top 10 - $contextName'
          : contextName;
    }

    if (connect.phase == ConnectPhase.pairing) {
      firstLine = 'HANDOFF | PAIRING';
      secondLine = connect.pendingPairRequest != null
          ? 'Incoming pairing request'
          : 'Waiting for device...';
    } else if (connect.isLinked) {
      if (connect.isHost) {
        firstLine = 'HANDOFF | LISTENING ON';
        secondLine = _resolveHandoffPeerName(connect) ?? 'Linked device';
      } else if (connect.isTarget) {
        firstLine = 'HANDOFF | CONTROLLING FROM';
        secondLine = _resolveHandoffPeerName(connect) ?? 'Host device';
      }
    }

    final tonalDecoration = M3EIconButtonDecoration(
      backgroundColor: WidgetStatePropertyAll(
        Colors.white.withValues(alpha: 0.12),
      ),
    );

    return Row(
      children: [
          M3EIconButton(
            variant: M3EIconButtonVariant.tonal,
            decoration: tonalDecoration,
            size: M3EIconButtonSize.sm,
            shape: M3EIconButtonShapeVariant.round,
            icon: const Icon(
              Symbols.keyboard_arrow_down,
              color: Colors.white,
              size: 24,
            ),
            tooltip: 'Collapse',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: secondLine.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          firstLine,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          secondLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          M3EIconButton(
            variant: M3EIconButtonVariant.tonal,
            decoration: tonalDecoration,
            size: M3EIconButtonSize.sm,
            shape: M3EIconButtonShapeVariant.round,
            icon: const Icon(
              Symbols.more_vert,
              color: Colors.white,
              size: 22,
            ),
            tooltip: 'More options',
            onPressed: player.currentTrack == null
                ? null
                : () {
                    unawaited(
                      AppleMusicFullScreenPlayer.showTrackMenuWithCanvasToggle(
                        context,
                        track: player.currentTrack!,
                      ),
                    );
                  },
          ),
        ],
      );
  }

  Widget _buildCoverImage(String imageUrl, double radius, {bool isLarge = true}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.expand(
          child: imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: const Color(0xFF1F1F1F),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) =>
                      _buildPlaceholderArtwork(isLarge: isLarge),
                )
              : _buildPlaceholderArtwork(isLarge: isLarge),
        ),
      ),
    );
  }

  Widget _buildPlaceholderArtwork({bool isLarge = true}) {
    return Container(
      color: const Color(0xFF1F1F1F),
      child: Center(
        child: Icon(
          Symbols.music_note,
          size: isLarge ? 64 : 26,
          color: Colors.white30,
        ),
      ),
    );
  }

  Widget _buildArtworkSection(
    BuildContext context, {
    required GenericSong? currentTrack,
    required String imageUrl,
    required bool hideNowPlayingCover,
    required double maxCoverSize,
    required LyricsProvider lyricsProvider,
  }) {
    final isPlayerMode = _mode == OriginalMobilePlayerMode.player;
    const compactSize = 56.0;
    final targetSize = isPlayerMode ? maxCoverSize : compactSize;
    final targetRadius = isPlayerMode ? 20.0 : 10.0;
    final shouldHide = isPlayerMode && hideNowPlayingCover;
    final artists = currentTrack?.artists ?? const <GenericSimpleArtist>[];
    final album = currentTrack?.album;
    final hasAlbum = album != null && album.id.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      height: targetSize,
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            alignment: isPlayerMode ? Alignment.center : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              width: targetSize,
              height: targetSize,
              child: shouldHide
                  ? const SizedBox.expand()
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: isPlayerMode
                          ? null
                          : () => _setMode(OriginalMobilePlayerMode.player),
                      child: PlayerArtworkHero(
                        enabled: true,
                        borderRadius: BorderRadius.circular(targetRadius),
                        child: _buildCoverImage(
                          imageUrl,
                          targetRadius,
                          isLarge: isPlayerMode,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: isPlayerMode,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isPlayerMode ? 0 : 1,
                child: Padding(
                  padding: const EdgeInsets.only(left: compactSize + 12),
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
                                    onTap: hasAlbum
                                        ? () => unawaited(
                                            _openAlbumFromPlayer(album),
                                          )
                                        : null,
                                    child: Text(
                                      currentTrack?.title ?? 'No track playing',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                if (currentTrack != null)
                                  TrackBadges(
                                    track: currentTrack,
                                    leadingSpacing: 6,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            ClickableArtistNames(
                              artists: artists,
                              emptyText: 'No Artist',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_mode == OriginalMobilePlayerMode.lyrics &&
                          currentTrack != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InlineDelayEditor(
                            lyricsProvider: lyricsProvider,
                            trackId: currentTrack.id,
                            visible: true,
                            liquidGlass: true,
                          ),
                        ),
                      LikeButton(
                        track: currentTrack,
                        iconSize: 22,
                        color: Colors.white,
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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

    if (lyrics == null || lyrics.lines.isEmpty || !lyrics.isSynced) {
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

        final timing = resolveSyncedLyricsTiming(lines, effectivePosition);
        LyricsLine? line;
        if (timing.activeIndex >= 0 && timing.activeIndex < lines.length) {
          line = lines[timing.activeIndex];
        } else if (timing.nextIndex != null && timing.nextIndex! < lines.length) {
          final nextLine = lines[timing.nextIndex!];
          if (nextLine.startTimeMs - effectivePosition <= 1800) {
            line = nextLine;
          }
        }

        if (line == null || line.content.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: WordFillLyricsLine(
              key: ValueKey<String>('${line.startTimeMs}_${line.content.trim()}'),
              line: line,
              positionMs: effectivePosition,
              isActive: effectivePosition >= line.startTimeMs,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.45),
              enableTicker: true,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackInfo(BuildContext context, GenericSong? currentTrack) {
    final title = currentTrack?.title ?? 'No track playing';
    final artists = currentTrack?.artists ?? const <GenericSimpleArtist>[];
    final album = currentTrack?.album;
    final hasAlbum = album != null && album.id.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: hasAlbum
                          ? () => unawaited(
                              _openAlbumFromPlayer(album),
                            )
                          : null,
                      child: MarqueeText(
                        text: title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  if (currentTrack != null)
                    TrackBadges(track: currentTrack, leadingSpacing: 6),
                ],
              ),
              const SizedBox(height: 4),
              ClickableArtistNames(
                artists: artists,
                album: album,
                emptyText: 'No Artist',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        LikeButton(
          track: currentTrack,
          iconSize: 24,
          color: Colors.white,
        ),
      ],
    );
  }

  Widget _buildModeContent(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    LyricsProvider lyricsProvider,
  ) {
    switch (_mode) {
      case OriginalMobilePlayerMode.lyrics:
        return SizedBox.expand(
          child: FullPlayerLyricsSection(
            player: player,
            lyricsProvider: lyricsProvider,
            activeFontSize: 28.0,
            inactiveFontSize: 23.0,
            waitingDotColor: Theme.of(context).colorScheme.primary,
            topPadding: 12.0,
          ),
        );
      case OriginalMobilePlayerMode.queue:
        return const SizedBox.expand(
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            child: QueueView(
              contentOnly: true,
              hideHeader: true,
              backgroundColor: Colors.transparent,
              listPadding: EdgeInsets.zero,
            ),
          ),
        );
      case OriginalMobilePlayerMode.player:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProgressBar(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
  ) {
    final coordinator = context.read<PlaybackCoordinator>();
    final useHandoffState = context.select<PlaybackCoordinator, bool>(
      (c) => c.useLinkedPlaybackState,
    );
    final primaryColor = Theme.of(context).colorScheme.primary;
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
                  ),
                ),
              ),
              _buildDurationRow(
                context,
                elapsed: clampedPosition,
                duration: duration,
                primaryColor: primaryColor,
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: primaryColor,
                  secondaryActiveTrackColor: Colors.white.withValues(
                    alpha: 0.32,
                  ),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                  thumbColor: Colors.white,
                  overlayColor: primaryColor.withValues(alpha: 0.2),
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
            _buildDurationRow(
              context,
              elapsed: clampedPosition,
              duration: duration,
              primaryColor: primaryColor,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDurationRow(
    BuildContext context, {
    required Duration elapsed,
    required Duration duration,
    required Color primaryColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _formatDuration(elapsed),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12,
          ),
        ),
        AudioQualityBadge(
          preferredColor: Colors.white,
          child: Selector<
            global_audio_player.WispAudioHandler,
            ActiveTrackQualityInfo?
          >(
            selector: (context, player) => player.activeTrackQuality,
            builder: (context, quality, child) {
              if (quality == null) {
                return const SizedBox.shrink();
              }

              var label = 'Standard';
              if (quality.isHiRes) {
                label = 'Hi-Res Lossless';
              } else if (quality.isLossless) {
                label = 'Lossless';
              } else if (quality.bitrate != null && quality.bitrate! >= 320) {
                label = 'High Quality';
              }

              Widget? icon;
              if (quality.isHiRes || quality.isLossless) {
                icon = SvgPicture.network(
                  'https://upload.wikimedia.org/wikipedia/commons/0/0d/Apple_Lossless_logo.svg',
                  fit: BoxFit.fill,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                );
              } else if (quality.bitrate != null && quality.bitrate! >= 320) {
                icon = const Icon(
                  Symbols.check_circle_filled,
                  fill: 1,
                  color: Colors.white,
                  size: 12,
                );
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      icon,
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
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
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
  ) {
    final tokens = context.tokens;
    final coordinator = context.read<PlaybackCoordinator>();
    final colorScheme = Theme.of(context).colorScheme;
    final useHandoffState = context.select<PlaybackCoordinator, bool>(
      (c) => c.useLinkedPlaybackState,
    );
    final isPlaying = context.select<PlaybackCoordinator, bool>(
      (c) => c.effectiveIsPlaying,
    );
    final isLoading = _isUiLoading(player, useHandoffState);

    final tonalDecoration = M3EIconButtonDecoration(
      backgroundColor: WidgetStatePropertyAll(
        Colors.white.withValues(alpha: 0.12),
      ),
    );
    final shuffleActive = !player.isDJMode && player.shuffleEnabled;
    final repeatActive =
        !player.isDJMode &&
        player.repeatMode != global_audio_player.RepeatMode.off;
    final repeatIcon = player.repeatMode == global_audio_player.RepeatMode.one
        ? tokens.repeatOneIcon
        : tokens.repeatIcon;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        M3EIconButton(
          variant: shuffleActive
              ? M3EIconButtonVariant.filled
              : M3EIconButtonVariant.tonal,
          decoration: shuffleActive ? null : tonalDecoration,
          shape: M3EIconButtonShapeVariant.round,
          size: M3EIconButtonSize.sm,
          tooltip: player.isDJMode ? 'Unavailable in DJ mode' : 'Shuffle',
          icon: Icon(
            tokens.shuffleIcon,
            color: player.isDJMode
                ? Colors.white30
                : (shuffleActive ? colorScheme.onPrimary : Colors.white70),
            size: 20,
          ),
          onPressed: player.isDJMode ? null : coordinator.toggleShuffle,
        ),
        M3EIconButton(
          variant: M3EIconButtonVariant.tonal,
          decoration: tonalDecoration,
          shape: M3EIconButtonShapeVariant.round,
          size: M3EIconButtonSize.md,
          tooltip: 'Previous',
          icon: Icon(
            tokens.playPrevIcon,
            color: player.queueTracks.isEmpty ? Colors.white30 : Colors.white,
            size: 28,
          ),
          onPressed: player.queueTracks.isEmpty
              ? null
              : coordinator.skipPrevious,
        ),
        _buildExpressivePlayPause(
          context,
          isPlaying: isPlaying,
          isLoading: isLoading,
          useHandoffState: useHandoffState,
          colorScheme: colorScheme,
          tokens: tokens,
        ),
        M3EIconButton(
          variant: M3EIconButtonVariant.tonal,
          decoration: tonalDecoration,
          shape: M3EIconButtonShapeVariant.round,
          size: M3EIconButtonSize.md,
          tooltip: 'Next',
          icon: Icon(
            tokens.playNextIcon,
            color: player.queueTracks.isEmpty ? Colors.white30 : Colors.white,
            size: 28,
          ),
          onPressed: player.queueTracks.isEmpty ? null : coordinator.skipNext,
        ),
        M3EIconButton(
          variant: repeatActive
              ? M3EIconButtonVariant.filled
              : M3EIconButtonVariant.tonal,
          decoration: repeatActive ? null : tonalDecoration,
          shape: M3EIconButtonShapeVariant.round,
          size: M3EIconButtonSize.sm,
          tooltip: player.isDJMode ? 'Unavailable in DJ mode' : 'Repeat',
          icon: Icon(
            repeatIcon,
            color: player.isDJMode
                ? Colors.white30
                : (repeatActive ? colorScheme.onPrimary : Colors.white70),
            size: 20,
          ),
          onPressed: player.isDJMode ? null : coordinator.toggleRepeat,
        ),
      ],
    );
  }

  Widget _buildExpressivePlayPause(
    BuildContext context, {
    required bool isPlaying,
    required bool isLoading,
    required bool useHandoffState,
    required ColorScheme colorScheme,
    required WispStyleTokens tokens,
  }) {
    final borderRadius = BorderRadius.circular(isPlaying ? 20 : 34);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: borderRadius,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: isLoading
              ? null
              : () {
                  final coordinator = context.read<PlaybackCoordinator>();
                  if (isPlaying) {
                    coordinator.pause();
                  } else {
                    final audio = context
                        .read<global_audio_player.WispAudioHandler>();
                    if (!useHandoffState &&
                        (audio.isLoading ||
                            audio.isBuffering ||
                            audio.isTrackTransitioning)) {
                      return;
                    }
                    coordinator.play();
                  }
                },
          child: Center(
            child: isLoading
                ? M3EProgressIndicator.circularWavy(
                    size: 28,
                    strokeWidth: 2.5,
                    color: colorScheme.onPrimary,
                  )
                : Icon(
                    isPlaying ? tokens.pauseIcon : tokens.playIcon,
                    color: colorScheme.onPrimary,
                    size: 34,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomUtilities(BuildContext context) {
    return ConnectDeviceIndicator(
      detailedBuilder:
          (
            context,
            showConnectStatus,
            connectStatusWidget,
            deviceName,
            deviceIcon,
          ) {
            return OriginalMobileUtilitiesRow(
              showConnectStatus: showConnectStatus,
              deviceName: deviceName,
              deviceIcon: deviceIcon,
              onConnectTap: () => unawaited(_openHandoffSheet(context)),
              selectedMode: _mode,
              onModeChanged: _setMode,
            );
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final currentTrack = player.currentTrack;
        final imageUrl = currentTrack?.thumbnailUrl ?? '';
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
        final canvasFuture = _getCanvasUrlFuture(
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

        return FutureBuilder<String?>(
          future: canvasFuture,
          builder: (context, canvasSnapshot) {
            final canvasUrl = canvasSnapshot.data ?? '';
            final hasCanvas = canvasUrl.isNotEmpty;
            final isPlayerMode = _mode == OriginalMobilePlayerMode.player;
            final useCanvasBg = isPlayerMode && hasCanvas;

            return Stack(
              fit: StackFit.expand,
              children: [
                if (!useCanvasBg)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: RotatingBlurredCoverBackground(
                        imageUrl: imageUrl,
                        blurSigma: 72,
                      ),
                    ),
                  ),
                if (useCanvasBg)
                  Positioned.fill(
                    child: CanvasVideo(
                      url: canvasUrl,
                      fallbackUrl: imageUrl,
                    ),
                  ),
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.48),
                  ),
                ),
                SingleChildScrollView(
                  controller: widget.scrollController,
                  physics: const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        topInset + 8,
                        24,
                        bottomInset + 16,
                      ),
                      child: Column(
                        children: [
                          _buildHeader(context, player),
                          const SizedBox(height: 12),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final availableForCover = math.max(
                                  160.0,
                                  constraints.maxHeight - 124.0,
                                );
                                final maxCoverSize = math
                                    .min(
                                      constraints.maxWidth,
                                      availableForCover,
                                    )
                                    .clamp(160.0, 360.0);
                                final topSpacerHeight = isPlayerMode
                                    ? math.max(
                                        0.0,
                                        (availableForCover - maxCoverSize) /
                                            2.0,
                                      )
                                    : 0.0;

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 320,
                                      ),
                                      curve: Curves.easeInOutCubic,
                                      height: topSpacerHeight,
                                    ),
                                    KeyedSubtree(
                                      key: const ValueKey(
                                        'original-cover-section',
                                      ),
                                      child: _buildArtworkSection(
                                        context,
                                        currentTrack: currentTrack,
                                        imageUrl: imageUrl,
                                        hideNowPlayingCover: useCanvasBg,
                                        maxCoverSize: maxCoverSize,
                                        lyricsProvider:
                                            context.read<LyricsProvider>(),
                                      ),
                                    ),
                                    if (isPlayerMode) ...[
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
                                      _buildTrackInfo(context, currentTrack),
                                      const SizedBox(height: 12),
                                    ] else ...[
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 240,
                                          ),
                                          child: KeyedSubtree(
                                            key:
                                                ValueKey<
                                                  OriginalMobilePlayerMode
                                                >(_mode),
                                            child: _buildModeContent(
                                              context,
                                              player,
                                              context.read<LyricsProvider>(),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                          _buildProgressBar(context, player),
                          const SizedBox(height: 14),
                          _buildPlaybackControls(context, player),
                          const SizedBox(height: 14),
                          _buildBottomUtilities(context),
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
}

/// Bottom utilities row for [OriginalMobileFullScreenPlayer]: a shrinking,
/// ellipsis-truncated Connect pill on the left and an icon-only segmented mode
/// selector on the right.
class OriginalMobileUtilitiesRow extends StatelessWidget {
  final bool showConnectStatus;
  final String? deviceName;
  final IconData? deviceIcon;
  final VoidCallback onConnectTap;
  final OriginalMobilePlayerMode selectedMode;
  final ValueChanged<OriginalMobilePlayerMode> onModeChanged;

  const OriginalMobileUtilitiesRow({
    super.key,
    required this.showConnectStatus,
    required this.deviceName,
    required this.deviceIcon,
    required this.onConnectTap,
    required this.selectedMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: showConnectStatus
                  ? primaryColor.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onConnectTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        showConnectStatus
                            ? (deviceIcon ?? Symbols.cast_connected)
                            : Symbols.cast_connected,
                        size: 18,
                        color: showConnectStatus
                            ? primaryColor
                            : Colors.white70,
                      ),
                      if (showConnectStatus &&
                          deviceName != null &&
                          deviceName!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            deviceName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeTab(
                mode: OriginalMobilePlayerMode.player,
                tooltip: 'Player',
                icon: Symbols.album,
                primaryColor: primaryColor,
                onPrimary: onPrimary,
              ),
              _buildModeTab(
                mode: OriginalMobilePlayerMode.lyrics,
                tooltip: 'Lyrics',
                icon: Symbols.lyrics,
                primaryColor: primaryColor,
                onPrimary: onPrimary,
              ),
              _buildModeTab(
                mode: OriginalMobilePlayerMode.queue,
                tooltip: 'Queue',
                icon: Symbols.queue_music,
                primaryColor: primaryColor,
                onPrimary: onPrimary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeTab({
    required OriginalMobilePlayerMode mode,
    required String tooltip,
    required IconData icon,
    required Color primaryColor,
    required Color onPrimary,
  }) {
    final isSelected = selectedMode == mode;
    final fg = isSelected ? onPrimary : Colors.white70;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => onModeChanged(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.92)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 20, color: fg),
        ),
      ),
    );
  }
}
