/// Full-screen player bottom sheet for mobile
library;

import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisp/services/connect/connect_models.dart';
import '../services/app_navigation.dart';
import '../services/cache_manager.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../providers/lyrics/provider.dart';
import '../providers/metadata/spotify_internal.dart';
import '../providers/library/library_state.dart';
import '../providers/navigation_state.dart';
import '../models/metadata_models.dart';
import '../providers/preferences/preferences_provider.dart';
import '../providers/theme/cover_art_palette_provider.dart';
import '../providers/connect/connect_session_provider.dart';
import '../views/lyrics.dart';
import '../views/queue.dart';
import '../views/artist_detail.dart';
import '../widgets/adaptive_context_menu.dart';
import '../widgets/animated_lyrics_preview.dart';
import '../widgets/entity_context_menus.dart';
import '../widgets/like_button.dart';
import '../utils/lyrics_timing.dart';

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
    String style,
  ) {
    switch (style) {
      case 'Apple Music':
        return AppleMusicFullScreenPlayer(scrollController: scrollController);
      case 'YouTube Music':
        return YouTubeMusicFullScreenPlayer(scrollController: scrollController);
      case 'Spotify':
      default:
        return SpotifyFullScreenPlayer(scrollController: scrollController);
    }
  }
}

/// Spotify variant of the fullscreen player. Uses the existing helper methods
/// (library-private) from `FullScreenPlayer` for layout and behavior.
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
    return _MobileArtistInfoCard(
      artist: artist,
      trackId: currentTrack?.id as String?,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final connect = context.watch<ConnectSessionProvider>();
        final contextType = player.playbackContextType;
        final contextName = player.playbackContextName;

        String firstLine = 'playing from';
        String secondLine = '';

        if (contextType != null &&
            contextName != null &&
            contextName.isNotEmpty) {
          if (contextType == 'artist') {
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
            child: Consumer<ConnectSessionProvider>(
              builder: (context, connect, child) {
                final devices = connect.discoveredDevices
                    .where((device) => device.id != connect.localDeviceId)
                    .toList();
                final linkedName = _resolveHandoffPeerName(connect);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cast_connected,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Handoff',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: connect.refreshDiscovery,
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (connect.isLinked)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF212121),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.link,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  connect.isHost
                                      ? 'Listening on ${linkedName ?? 'linked device'}'
                                      : 'Controlling from ${linkedName ?? 'host device'}',
                                  style: const TextStyle(color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  connect.unlink(localResumed: true);
                                  Navigator.of(sheetContext).pop();
                                },
                                child: const Text('Unlink'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (connect.pendingPairRequest != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF212121),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${connect.pendingPairRequest!.fromDeviceName} wants to pair',
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: connect.rejectIncomingPair,
                                      child: const Text('Decline'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        'Available devices',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF212121),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next link mode:',
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<ConnectLinkMode>(
                              showSelectedIcon: false,
                              style: ButtonStyle(
                                backgroundColor:
                                    WidgetStateProperty.resolveWith(
                                      (states) =>
                                          states.contains(WidgetState.selected)
                                          ? Colors.white.withValues(alpha: 0.12)
                                          : Colors.transparent,
                                    ),
                                foregroundColor: WidgetStateProperty.all<Color>(
                                  Colors.white,
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
                                connect.setNextOutgoingLinkMode(
                                  selection.first,
                                );
                              },
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: connect.rememberModeForNextLink,
                                  onChanged: (value) {
                                    connect.setRememberModeForNextLink(
                                      value ?? false,
                                    );
                                  },
                                ),
                                Expanded(
                                  child: Text(
                                    'Remember for next session',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: devices.isEmpty
                          ? Center(
                              child: Text(
                                'No devices found on this network.',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                                              mode:
                                                  connect.nextOutgoingLinkMode,
                                              rememberForDevice: connect
                                                  .rememberModeForNextLink,
                                            );
                                            Navigator.of(sheetContext).pop();
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
                                            child: Text(
                                              device.name,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (isLinkedDevice)
                                            const Text(
                                              'Linked',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
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
    return _CanvasVideo(url: url, fallbackUrl: fallbackUrl);
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

    final state = lyricsProvider.getState(currentTrack, LyricsSyncMode.synced);
    if (!state.isLoading && state.lyrics == null && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.synced);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final lyrics = state.lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
    final basePosition = useHandoffState
        ? connect.linkedInterpolatedPosition
        : player.throttledPosition;
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = basePosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    final lines = nonEmptyLyricsLines(lyrics.lines);
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final timing = lyrics.synced
        ? resolveSyncedLyricsTiming(lines, effectivePosition)
        : null;
    final line = _getSingleLine(lyrics, effectivePosition);
    final showWaitingPlaceholder =
        lyrics.synced && timing != null && timing.activeIndex < 0 && timing.nextIndex != null;
    if ((line == null || line.content.trim().isEmpty) && !showWaitingPlaceholder) {
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
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
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
  }

  Widget _buildTrackInfo(
    dynamic currentTrack,
    Color likeColor,
    bool useCoverArt,
  ) {
    final title = currentTrack?.title ?? 'No track playing';
    final artists = currentTrack?.artists ?? [];
    final thumbnailUrl = currentTrack?.thumbnailUrl;

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
                  child: _MarqueeText(
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

    final state = lyricsProvider.getState(currentTrack, LyricsSyncMode.synced);
    if (!state.isLoading && state.lyrics == null && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.synced);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final lyrics = state.lyrics;
    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
    final basePosition = useHandoffState
        ? connect.linkedInterpolatedPosition
        : player.throttledPosition;
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = basePosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    final previewLines = lyrics == null
        ? const <LyricsLine>[]
        : _getPreviewLines(lyrics, effectivePosition);

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
                  onPressed: lyrics == null ? null : () => _openLyrics(context),
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
          else if (previewLines.isEmpty)
            const Text(
              'No lyrics found',
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
            lyrics == null ? '' : 'Lyrics provided by ${lyrics.provider.label}',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
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
    if (!lyrics.synced) {
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
    if (!lyrics.synced) {
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
    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
    final isLoading = _isUiLoading(player, useHandoffState);
    final colorScheme = Theme.of(context).colorScheme;
    final position = useHandoffState
        ? connect.linkedInterpolatedPosition
        : player.interpolatedPosition;
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
                  overlayColor: colorScheme.primary.withOpacity(0.2),
                ),
                child: Slider(
                  value: animatedProgress,
                  onChanged: (value) {
                    final newPosition = Duration(
                      milliseconds: (value * duration.inMilliseconds).toInt(),
                    );
                    context.read<ConnectSessionProvider>().requestSeek(
                      newPosition,
                    );
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
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Shuffle
        IconButton(
          icon: const Icon(Icons.shuffle),
          iconSize: 28,
          color: player.shuffleEnabled ? bgColor : Colors.grey[300],
          padding: const EdgeInsets.all(8),
          onPressed: () {
            context.read<ConnectSessionProvider>().requestToggleShuffle();
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
                  context.read<ConnectSessionProvider>().requestSkipPrevious();
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
                  context.read<ConnectSessionProvider>().requestSkipNext();
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
          color: player.repeatMode != global_audio_player.RepeatMode.off
              ? bgColor
              : Colors.grey[300],
          padding: const EdgeInsets.all(8),
          onPressed: () {
            context.read<ConnectSessionProvider>().requestToggleRepeat();
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
    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
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

    final isPlaying = useHandoffState
        ? connect.linkedIsPlaying
        : player.isPlaying;

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
            connect.requestPause();
          } else {
            connect.requestPlay();
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

  Widget _buildSpotifyTopCanvasBackground(
    BuildContext context,
    String canvasUrl,
    String fallbackUrl,
  ) {
    return SizedBox.expand(child: _buildCanvasVideo(canvasUrl, fallbackUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<global_audio_player.WispAudioHandler, LyricsProvider>(
      builder: (context, player, lyricsProvider, child) {
        final currentTrack = player.currentTrack;
        final imageUrl = currentTrack?.thumbnailUrl ?? '';
        final useCanvas = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.animatedCanvasEnabled,
        );
        final canUseCanvas =
            useCanvas &&
            currentTrack != null &&
            (currentTrack.source == SongSource.spotifyInternal ||
                currentTrack.source == SongSource.spotify);
        final spotifyInternal = context.read<SpotifyInternalProvider>();
        final Future<String?>? canvasFuture = canUseCanvas
            ? spotifyInternal.getCanvasUrl(currentTrack.id)
            : null;

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

        final palette = context.select<CoverArtPaletteProvider, ColorScheme?>(
          (provider) => provider.palette,
        );
        final bgColor = HSLColor.fromColor(
          palette?.onSecondaryContainer ?? const Color(0xFF1A1A1A),
        ).withLightness(0.6).withSaturation(0.65).toColor();
        final btnColor = HSLColor.fromColor(
          palette?.onPrimaryContainer ?? const Color(0xFF1A1A1A),
        ).withLightness(0.7).withSaturation(1).toColor();

        Widget buildPlayerScaffold({String? canvasUrl}) {
          final hasCanvas = canvasUrl != null && canvasUrl.isNotEmpty;
          final content = Container(
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.45)),
            child: Padding(
              padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            _buildHeader(context),
                            const SizedBox(height: 48),
                            hasCanvas
                                ? _buildHiddenArtworkPlaceholder(context)
                                : _buildAlbumArt(context, imageUrl),
                            const SizedBox(height: 24),
                            _buildSingleLyricsLine(
                              context,
                              player,
                              lyricsProvider,
                            ),
                            const SizedBox(height: 24),
                            _buildTrackInfo(
                              currentTrack,
                              btnColor,
                              (currentTrack!.thumbnailUrl.isNotEmpty &&
                                  hasCanvas &&
                                  useCanvas),
                            ),
                            const SizedBox(height: 16),
                            _buildPlayerControls(context, player, btnColor),
                            const SizedBox(height: 16),
                            _buildLyricsPreview(
                              context,
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
              ? _CoverGradientContainer(
                  background: _buildSpotifyTopCanvasBackground(
                    context,
                    canvasUrl,
                    imageUrl,
                  ),
                  child: content,
                )
              : _CoverGradientContainer(child: content);

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(color: Colors.black.withOpacity(0.16)),
                  ),
                ),
              ),
              foreground,
            ],
          );
        }

        if (!canUseCanvas) {
          return buildPlayerScaffold();
        }

        return FutureBuilder<String?>(
          future: spotifyInternal.getCanvasUrl(currentTrack!.id),
          builder: (context, snapshot) {
            final canvasUrl = snapshot.data ?? '';
            return buildPlayerScaffold(canvasUrl: canvasUrl);
          },
        );
      },
    );
  }
}

class _CanvasVideo extends StatefulWidget {
  final String url;
  final String fallbackUrl;

  const _CanvasVideo({required this.url, required this.fallbackUrl});

  @override
  State<_CanvasVideo> createState() => _CanvasVideoState();
}

class _CanvasVideoState extends State<_CanvasVideo> {
  VideoPlayerController? _controller;
  bool _initFailed = false;
  bool? _lastShouldPlay;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _CanvasVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _initialize();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      _initFailed = false;
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      _initFailed = true;
      if (mounted) setState(() {});
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _lastShouldPlay = null;
  }

  void _syncPlayback(VideoPlayerController controller, bool shouldPlay) {
    if (_lastShouldPlay == shouldPlay) return;
    _lastShouldPlay = shouldPlay;
    unawaited(_setPlayback(controller, shouldPlay));
  }

  Future<void> _setPlayback(
    VideoPlayerController controller,
    bool shouldPlay,
  ) async {
    try {
      if (shouldPlay) {
        if (!controller.value.isPlaying) {
          await controller.play();
        }
      } else {
        if (controller.value.isPlaying) {
          await controller.pause();
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final useLinkedState = context.select<ConnectSessionProvider, bool>(
      (connect) => connect.isLinked && connect.isHost,
    );
    final linkedShouldPlay = context.select<ConnectSessionProvider, bool>(
      (connect) => connect.linkedIsPlaying,
    );
    final localShouldPlay = context
        .select<global_audio_player.WispAudioHandler, bool>(
          (player) => player.isPlaying,
        );
    final shouldPlay = useLinkedState ? linkedShouldPlay : localShouldPlay;
    final controller = _controller;
    if (_initFailed || controller == null || !controller.value.isInitialized) {
      return CachedNetworkImage(
        imageUrl: widget.fallbackUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[900]),
        errorWidget: (context, url, error) =>
            Container(color: Colors.grey[900]),
      );
    }

    _syncPlayback(controller, shouldPlay);

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _RotatingBlurredCoverBackground extends StatefulWidget {
  final String imageUrl;

  const _RotatingBlurredCoverBackground({required this.imageUrl});

  @override
  State<_RotatingBlurredCoverBackground> createState() =>
      _RotatingBlurredCoverBackgroundState();
}

class _RotatingBlurredCoverBackgroundState
    extends State<_RotatingBlurredCoverBackground>
    with SingleTickerProviderStateMixin, WindowListener {
  late final AnimationController _rotationController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 50),
  );

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _rotationController.repeat();
    if (_isDesktop) {
      windowManager.addListener(this);
      _syncMinimizedState();
    }
  }

  Future<void> _syncMinimizedState() async {
    try {
      final minimized = await windowManager.isMinimized();
      if (!mounted) return;
      if (minimized) {
        _rotationController.stop(canceled: false);
      } else if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } catch (_) {}
  }

  @override
  void onWindowMinimize() {
    _rotationController.stop(canceled: false);
  }

  @override
  void onWindowRestore() {
    if (!_rotationController.isAnimating) {
      _rotationController.repeat();
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.isEmpty) {
      return Container(color: const Color(0xFF101010));
    }

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final maxSide = width > height ? width : height;
          final imageSize = maxSide * 2.4;

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  final angle = _rotationController.value * 6.283185307179586;
                  final centerX = width;
                  final centerY = 0.0;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: centerX - (imageSize / 2),
                        top: centerY - (imageSize / 2),
                        width: imageSize,
                        height: imageSize,
                        child: Transform.rotate(angle: angle, child: child!),
                      ),
                    ],
                  );
                },
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Apple Music variant — currently uses the Spotify layout but is a separate
/// class to allow future customization.
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
  static final Map<String, Future<ColorScheme?>> _colorSchemeFutureCache =
      <String, Future<ColorScheme?>>{};
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
      onBeforeNavigate: () => AppNavigation.instance.disableFullPlayerDesktopMode(),
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

  bool get _isWaveformSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  void _setMode(_ApplePlayerViewMode mode) {
    _modeNotifier.value = mode;
  }

  String? _resolveHandoffPeerName(ConnectSessionProvider connect) {
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
            child: Consumer<ConnectSessionProvider>(
              builder: (context, connect, child) {
                final devices = connect.discoveredDevices
                    .where((device) => device.id != connect.localDeviceId)
                    .toList();
                final linkedName = _resolveHandoffPeerName(connect);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cast_connected,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Handoff',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Refresh devices',
                            splashRadius: 18,
                            onPressed: connect.refreshDiscovery,
                            icon: const Icon(
                              Icons.refresh,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (connect.isLinked)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF212121),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.link,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  connect.isHost
                                      ? 'Listening on ${linkedName ?? 'Linked device'}'
                                      : 'Controlling from ${linkedName ?? 'Host device'}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  connect.unlink(localResumed: true);
                                  Navigator.of(sheetContext).pop();
                                },
                                child: const Text('Unlink'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (connect.pendingPairRequest != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF212121),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${connect.pendingPairRequest!.fromDeviceName} wants to pair via Handoff',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: connect.rejectIncomingPair,
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                          color: Colors.grey[700]!,
                                        ),
                                      ),
                                      child: const Text('Decline'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton(
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Available devices',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF212121),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next link mode:',
                              style: TextStyle(
                                color: Colors.grey[300],
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<ConnectLinkMode>(
                              showSelectedIcon: false,
                              style: ButtonStyle(
                                backgroundColor:
                                    WidgetStateProperty.resolveWith(
                                      (states) =>
                                          states.contains(WidgetState.selected)
                                          ? Colors.white.withValues(alpha: 0.12)
                                          : Colors.transparent,
                                    ),
                                foregroundColor: WidgetStateProperty.all<Color>(
                                  Colors.white,
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
                                connect.setNextOutgoingLinkMode(
                                  selection.first,
                                );
                              },
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: connect.rememberModeForNextLink,
                                  onChanged: (value) {
                                    connect.setRememberModeForNextLink(
                                      value ?? false,
                                    );
                                  },
                                ),
                                Expanded(
                                  child: Text(
                                    'Remember for next session',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                                              mode:
                                                  connect.nextOutgoingLinkMode,
                                              rememberForDevice: connect
                                                  .rememberModeForNextLink,
                                            );
                                            Navigator.of(sheetContext).pop();
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  device.platform,
                                                  style: TextStyle(
                                                    color: Colors.grey[500],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isLinkedDevice)
                                            const Text(
                                              'Linked',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
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
      LyricsSyncMode.synced,
    );
    if (!syncedState.isLoading &&
        syncedState.lyrics == null &&
        syncedState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.synced);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final syncedLyrics = syncedState.lyrics;
    final hasSyncedLyrics =
        syncedLyrics != null &&
        syncedLyrics.lines.isNotEmpty &&
        syncedLyrics.synced;

    final unsyncedState = lyricsProvider.getState(
      currentTrack,
      LyricsSyncMode.unsynced,
    );
    if (!hasSyncedLyrics &&
        !unsyncedState.isLoading &&
        unsyncedState.lyrics == null &&
        unsyncedState.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.unsynced);
      });
    }

    final lyrics = hasSyncedLyrics ? syncedLyrics : unsyncedState.lyrics;
    final isLoading = hasSyncedLyrics
        ? syncedState.isLoading && lyrics == null
        : (syncedState.isLoading || unsyncedState.isLoading) && lyrics == null;

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

    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
    final basePosition = useHandoffState
        ? connect.linkedInterpolatedPosition
        : player.throttledPosition;
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = basePosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    final timing = normalizedLyrics.synced
      ? resolveSyncedLyricsTiming(normalizedLyrics.lines, effectivePosition)
      : null;
    final currentIndex = normalizedLyrics.synced
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
            final line = lyricLine.content.trim();

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
            var color = isCurrent ? Colors.white : Colors.grey[500];

            if (normalizedLyrics.synced &&
                timing != null &&
                timing.shouldFadePreviousLine &&
                timing.previousIndex == index &&
                timing.nextIndex != null) {
              opacity = lerpDouble(1.0, 0.72, timing.fadeOutProgress)!;
              fontSize = lerpDouble(34.0, 30.0, timing.fadeOutProgress)!;
              fontWeight = timing.fadeOutProgress < 0.55
                  ? FontWeight.w700
                  : FontWeight.w600;
              color = Color.lerp(Colors.white, Colors.grey[500], timing.fadeOutProgress)!;
            }

            final row = AnimatedOpacity(
              key: lineKeys[index],
              duration: const Duration(milliseconds: 220),
              opacity: opacity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  mouseCursor: normalizedLyrics.synced
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  onTap: normalizedLyrics.synced
                      ? () {
                          final seekMs = (lyricLine.startTimeMs + delayMs)
                              .clamp(0, player.duration.inMilliseconds)
                              .toInt();
                          unawaited(
                            context.read<ConnectSessionProvider>().requestSeek(
                              Duration(milliseconds: seekMs),
                            ),
                          );
                        }
                      : null,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      line,
                      style: TextStyle(
                        color: color,
                        fontSize: fontSize,
                        fontWeight: fontWeight,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
            );

            final showWaitingDots = normalizedLyrics.synced &&
                timing != null &&
                timing.showWaitingDots &&
                timing.nextIndex == index;

            if (!showWaitingDots) {
              return row;
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLyricsWaitingDots(timing.progressToNext),
                row,
              ],
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
      final localProgress = ((progress - start) / (end - start)).clamp(0.0, 1.0);
      final opacity = lerpDouble(0.2, 1.0, localProgress)!;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            shape: BoxShape.circle,
          ),
        ),
      );
    });

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: dots,
        ),
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
    final contextName = player.playbackContextName;
    final continuePlayingSource =
        contextName != null && contextName.isNotEmpty ? contextName : 'Queue';
    final hideLeadingCurrent = currentIndex == 0 && queue.length > 1;
    final queueStartIndex = hideLeadingCurrent ? 1 : 0;
    final visibleQueueCount = queue.length - queueStartIndex;

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
                      context
                          .read<ConnectSessionProvider>()
                          .requestClearQueue();
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
                  itemCount: visibleQueueCount,
                  onReorder: (oldIndex, newIndex) {
                    if (oldIndex == newIndex) return;
                    final queueOldIndex = oldIndex + queueStartIndex;
                    final queueNewIndex = newIndex + queueStartIndex;
                    unawaited(
                      context.read<ConnectSessionProvider>().requestReorderQueue(
                        queueOldIndex,
                        queueNewIndex,
                      ),
                    );
                  },
                  itemBuilder: (context, index) {
                    final queueIndex = index + queueStartIndex;
                    final track = queue[queueIndex];
                    final isCurrent = queueIndex == currentIndex;
                    return Padding(
                      key: ValueKey('queue-item-${track.id}-$queueIndex'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          unawaited(
                            context
                                .read<ConnectSessionProvider>()
                                .requestPlayQueueIndex(queueIndex),
                          );
                        },
                        child: Row(
                          children: [
                            _buildCoverImageBox(context, track.thumbnailUrl, 56),
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

  Widget _buildQueuePillButton({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? Colors.white.withValues(alpha: 0.2) : Colors.white12,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.grey[200],
              ),
            ],
          ),
        ),
      ),
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
      case _ApplePlayerViewMode.waveform:
        if (!_isWaveformSupported) {
          child = Center(
            child: Text(
              'Waveform is unsupported on this platform.',
              style: TextStyle(color: Colors.grey[400], fontSize: 15),
            ),
          );
        } else {
          child = _buildWaveformModeContent(context, player);
        }
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

  Widget _buildWaveformModeContent(
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

    return _AppleWaveformPanel(
      track: track,
      position: player.throttledPosition,
      duration: player.duration,
    );
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
                                      errorWidget: (context, _, __) =>
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
                          Text(
                            (description != null && description.isNotEmpty)
                                ? description
                                : 'No description available for this artist.',
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

  Future<ColorScheme?> _getColorSchemeFuture(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Future.value(null);
    }
    final cached = _colorSchemeFutureCache[imageUrl];
    if (cached != null) {
      return cached;
    }
    _pruneFutureCache<ColorScheme?>(_colorSchemeFutureCache);
    final future = _resolveColorScheme(CachedNetworkImageProvider(imageUrl));
    _colorSchemeFutureCache[imageUrl] = future;
    return future;
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
    if (value >= 1000000000)
      return '${(value / 1000000000).toStringAsFixed(1)}B';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }

  Widget _buildHeader(BuildContext context) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final connect = context.watch<ConnectSessionProvider>();
        final contextType = player.playbackContextType;
        final contextName = player.playbackContextName;

        String firstLine = 'playing from';
        String secondLine = '';

        if (contextType != null &&
            contextName != null &&
            contextName.isNotEmpty) {
          if (contextType == 'artist') {
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
          String? peerName;
          final peerId = connect.linkedDeviceId;
          if (peerId != null) {
            for (final device in connect.discoveredDevices) {
              if (device.id == peerId) {
                peerName = device.name;
                break;
              }
            }
          }

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
            Expanded(child: centerInfo),
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

    final state = lyricsProvider.getState(currentTrack, LyricsSyncMode.synced);
    if (!state.isLoading && state.lyrics == null && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.synced);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);

    final lyrics = state.lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
    final basePosition = useHandoffState
        ? connect.linkedInterpolatedPosition
        : player.throttledPosition;
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = basePosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    final lines = nonEmptyLyricsLines(lyrics.lines);
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final timing = lyrics.synced
        ? resolveSyncedLyricsTiming(lines, effectivePosition)
        : null;
    final line = _getSingleLine(lyrics, effectivePosition);
    final showWaitingPlaceholder =
        lyrics.synced && timing != null && timing.activeIndex < 0 && timing.nextIndex != null;
    if ((line == null || line.content.trim().isEmpty) && !showWaitingPlaceholder) {
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
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
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
            : Text(
                line.content.trim(),
                key: ValueKey<String>(line.content.trim()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
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
                  child: _MarqueeText(
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
          track: currentTrack as GenericSong?,
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
    if (!lyrics.synced) {
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
    final connect = context.read<ConnectSessionProvider>();
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
                          final overlay = Overlay.of(context).context
                              .findRenderObject() as RenderBox;
                          final box = buttonContext.findRenderObject()
                              as RenderBox?;
                          if (box == null) {
                            unawaited(_openTrackMenu(context, player));
                            return;
                          }
                          final rect = Rect.fromPoints(
                            box.localToGlobal(
                              Offset.zero,
                              ancestor: overlay,
                            ),
                            box.localToGlobal(
                              box.size.bottomRight(Offset.zero),
                              ancestor: overlay,
                            ),
                          );
                          unawaited(
                            _openTrackMenu(
                              context,
                              player,
                              anchorRect: rect,
                            ),
                          );
                        },
                        activeColor: btnColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildModeActionButton(
                      tooltip: 'Shuffle',
                      icon: CupertinoIcons.shuffle,
                      selected: player.shuffleEnabled,
                      onTap: connect.requestToggleShuffle,
                      activeColor: btnColor,
                    ),
                    const SizedBox(width: 6),
                    _buildModeActionButton(
                      tooltip: 'Repeat',
                      icon:
                          player.repeatMode ==
                              global_audio_player.RepeatMode.one
                          ? CupertinoIcons.repeat_1
                          : CupertinoIcons.repeat,
                      selected:
                          player.repeatMode !=
                          global_audio_player.RepeatMode.off,
                      onTap: connect.requestToggleRepeat,
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
    final overlay = Overlay.of(buttonContext).context.findRenderObject()
        as RenderBox;
    final button = buttonContext.findRenderObject() as RenderBox;
    final buttonRect = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
    );

    await showGeneralDialog<void>(
      context: buttonContext,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _FullPlayerVolumeQuickPanel(
          anchorRect: buttonRect,
          overlaySize: overlay.size,
          accentColor: accentColor,
          onToggleMute: () {
            final audio = dialogContext.read<global_audio_player.WispAudioHandler>();
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
    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
    final isLoading = _isUiLoading(player, useHandoffState);
    final isPlaying = useHandoffState
        ? connect.linkedIsPlaying
        : player.isPlaying;

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
                  context.read<ConnectSessionProvider>().requestSkipPrevious();
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
                    connect.requestPause();
                  } else {
                    connect.requestPlay();
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
                  context.read<ConnectSessionProvider>().requestSkipNext();
                },
        ),
      ],
    );
  }

  Widget _buildDesktopModeActions(_ApplePlayerViewMode mode, Color btnColor) {
    final waveformSupported = _isWaveformSupported;
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
          tooltip: waveformSupported
              ? 'Waveform'
              : 'Unsupported on this platform',
          icon: Icons.graphic_eq,
          selected: waveformSupported && mode == _ApplePlayerViewMode.waveform,
          onTap: waveformSupported
              ? () => _setMode(
                  mode == _ApplePlayerViewMode.waveform
                      ? _ApplePlayerViewMode.nowPlaying
                      : _ApplePlayerViewMode.waveform,
                )
              : null,
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
    final connect = context.read<ConnectSessionProvider>();
    final repeatMode = player.repeatMode;

    return Row(
      children: [
        Expanded(
          child: _buildMobileNowPlayingActionButton(
            icon: CupertinoIcons.shuffle,
            selected: player.shuffleEnabled,
            activeColor: btnColor,
            onTap: () => _deferAsyncAction(connect.requestToggleShuffle),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMobileNowPlayingActionButton(
            icon: repeatMode == global_audio_player.RepeatMode.one
                ? CupertinoIcons.repeat_1
                : CupertinoIcons.repeat,
            selected: repeatMode != global_audio_player.RepeatMode.off,
            activeColor: btnColor,
            onTap: () => _deferAsyncAction(connect.requestToggleRepeat),
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
    global_audio_player.WispAudioHandler player,
    {
      Offset? globalPosition,
      Rect? anchorRect,
    }
  ) async {
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
    required VoidCallback onTap,
  }) {
    final color = selected ? Colors.white : Colors.grey[200]!;
    final background = selected
        ? activeColor.withOpacity(0.34)
        : Colors.white.withOpacity(0.13);

    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withOpacity(selected ? 0.26 : 0.14),
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
    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
    final isLoading = _isUiLoading(player, useHandoffState);
    final colorScheme = Theme.of(context).colorScheme;
    final position = useHandoffState
        ? connect.linkedInterpolatedPosition
        : player.interpolatedPosition;
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
                  overlayColor: colorScheme.primary.withOpacity(0.2),
                ),
                child: Slider(
                  value: animatedProgress,
                  onChanged: (value) {
                    final newPosition = Duration(
                      milliseconds: (value * duration.inMilliseconds).toInt(),
                    );
                    context.read<ConnectSessionProvider>().requestSeek(
                      newPosition,
                    );
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
                  context.read<ConnectSessionProvider>().requestSkipPrevious();
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
                  context.read<ConnectSessionProvider>().requestSkipNext();
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
    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
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

    final isPlaying = useHandoffState
        ? connect.linkedIsPlaying
        : player.isPlaying;

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
            connect.requestPause();
          } else {
            connect.requestPlay();
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
          child: _RotatingBlurredCoverBackground(imageUrl: fallbackUrl),
        ),
        Positioned.fill(
          child: _CanvasVideo(url: url, fallbackUrl: fallbackUrl),
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
      child: _RotatingBlurredCoverBackground(imageUrl: imageUrl),
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
        final imageUrl = currentTrack?.thumbnailUrl ?? '';
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

        return FutureBuilder<ColorScheme?>(
          future: _getColorSchemeFuture(imageUrl),
          builder: (context, snapshot) {
            final palette = snapshot.data;
            var bgColor = HSLColor.fromColor(
              palette?.onSecondaryContainer ?? const Color(0xFF1A1A1A),
            ).withLightness(0.6).withSaturation(0.65).toColor();
            var btnColor = HSLColor.fromColor(
              palette?.onPrimaryContainer ?? const Color(0xFF1A1A1A),
            ).withLightness(0.7).withSaturation(1).toColor();

            return FutureBuilder<String?>(
              future: canvasFuture,
              builder: (context, canvasSnapshot) {
                final canvasUrl = canvasSnapshot.data ?? '';
                final hasCanvas = canvasUrl.isNotEmpty;

                return ValueListenableBuilder<bool>(
                  valueListenable: _animatedCanvasTemporarilyDisabledNotifier,
                  builder: (context, animatedCanvasDisabled, __) {
                    return ValueListenableBuilder<_ApplePlayerViewMode>(
                      valueListenable: _modeNotifier,
                      builder: (context, mode, _) {
                        final isNowPlaying =
                            mode == _ApplePlayerViewMode.nowPlaying;
                        final useNowPlayingCanvas = !animatedCanvasDisabled &&
                            (_isDesktop
                                ? hasCanvas
                                : (isNowPlaying && hasCanvas));

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
                            color: Colors.black.withOpacity(0.45),
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
                                const SizedBox(height: 16),
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
      },
    );
  }
}

enum _ApplePlayerViewMode { nowPlaying, lyrics, queue, waveform, artist }

class _AppleWaveformPanel extends StatefulWidget {
  final GenericSong track;
  final Duration position;
  final Duration duration;

  const _AppleWaveformPanel({
    required this.track,
    required this.position,
    required this.duration,
  });

  @override
  State<_AppleWaveformPanel> createState() => _AppleWaveformPanelState();
}

class _AppleWaveformPanelState extends State<_AppleWaveformPanel> {
  StreamSubscription<WaveformProgress>? _extractSubscription;
  Waveform? _waveform;
  double _progress = 0;
  String? _errorText;
  String? _loadedTrackId;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  @override
  void didUpdateWidget(covariant _AppleWaveformPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _loadWaveform();
    }
  }

  @override
  void dispose() {
    _extractSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadWaveform() async {
    if (_loadedTrackId == widget.track.id) return;
    _loadedTrackId = widget.track.id;
    _waveform = null;
    _progress = 0;
    _errorText = null;
    await _extractSubscription?.cancel();

    final cachedPath = AudioCacheManager.instance.getCachedPath(
      widget.track.id,
    );
    if (cachedPath == null || cachedPath.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Waveform is available for cached tracks.';
      });
      return;
    }

    try {
      final audioInFile = File(cachedPath);
      if (!audioInFile.existsSync()) {
        if (!mounted) return;
        setState(() {
          _errorText = 'Cached audio file could not be found.';
        });
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final waveOutFile = File(
        '${tempDir.path}/wisp_waveforms/${widget.track.id}.wave',
      );
      await waveOutFile.parent.create(recursive: true);

      if (waveOutFile.existsSync()) {
        final parsed = await JustWaveform.parse(waveOutFile);
        if (!mounted) return;
        setState(() {
          _waveform = parsed;
          _progress = 1;
        });
        return;
      }

      _extractSubscription =
          JustWaveform.extract(
            audioInFile: audioInFile,
            waveOutFile: waveOutFile,
            zoom: const WaveformZoom.pixelsPerSecond(110),
          ).listen(
            (waveProgress) {
              if (!mounted) return;
              setState(() {
                _progress = waveProgress.progress;
                if (waveProgress.waveform != null) {
                  _waveform = waveProgress.waveform;
                }
              });
            },
            onError: (_) {
              if (!mounted) return;
              setState(() {
                _errorText =
                    'Waveform extraction is not available on this platform.';
              });
            },
          );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Unable to generate waveform for this track.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final waveform = _waveform;
    if (_errorText != null) {
      return Center(
        child: Text(
          _errorText!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[350], fontSize: 15),
        ),
      );
    }
    if (waveform == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 10),
            Text(
              'Generating waveform… ${(_progress * 100).toInt()}%',
              style: TextStyle(color: Colors.grey[300], fontSize: 13),
            ),
          ],
        ),
      );
    }

    final duration = widget.duration == Duration.zero
        ? waveform.duration
        : widget.duration;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Waveform',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _AppleWaveformPainter(
                  waveform: waveform,
                  position: widget.position,
                  duration: duration,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppleWaveformPainter extends CustomPainter {
  final Waveform waveform;
  final Duration position;
  final Duration duration;

  _AppleWaveformPainter({
    required this.waveform,
    required this.position,
    required this.duration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || waveform.length <= 0) return;

    final barWidth = 2.0;
    const gap = 2.0;
    final step = barWidth + gap;
    final bars = (size.width / step).floor().clamp(1, waveform.length).toInt();
    final pixelsPerBar = math.max(1, waveform.length ~/ bars);
    final playedRatio = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    final playedPaint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;
    final unplayedPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < bars; i++) {
      final sampleIndex = (i * pixelsPerBar)
          .clamp(0, waveform.length - 1)
          .toInt();
      final min = waveform.getPixelMin(sampleIndex);
      final max = waveform.getPixelMax(sampleIndex);
      final amplitude = ((max - min).abs() / 65535.0).clamp(0.06, 1.0);
      final lineHeight = size.height * amplitude;
      final x = i * step + (barWidth / 2);
      final y1 = (size.height - lineHeight) / 2;
      final y2 = y1 + lineHeight;
      final ratio = bars <= 1 ? 0.0 : i / (bars - 1);
      canvas.drawLine(
        Offset(x, y1),
        Offset(x, y2),
        ratio <= playedRatio ? playedPaint : unplayedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AppleWaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.position != position ||
        oldDelegate.duration != duration;
  }
}

/// YouTube Music variant — currently reuses the Spotify layout.
class YouTubeMusicFullScreenPlayer extends StatelessWidget {
  final ScrollController scrollController;

  const YouTubeMusicFullScreenPlayer({
    required this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SpotifyFullScreenPlayer(scrollController: scrollController);
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  double _scrollDistance = 0;
  bool _needsMarquee = false;
  Timer? _pauseTimer;

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _configureController(forceStop: true);
    }
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _configureController({bool forceStop = false}) {
    if (!_needsMarquee || forceStop) {
      _pauseTimer?.cancel();
      _controller?.stop();
      if (_controller != null) {
        _controller!.value = 0;
      }
    }
    if (!_needsMarquee) return;

    _controller ??= AnimationController(vsync: this)
      ..addStatusListener(_handleStatusChange);
    final ms = ((_scrollDistance / 24) * 1000).clamp(2400, 12000).toInt();
    _controller!.duration = Duration(milliseconds: ms);
    _scheduleStart();
  }

  void _handleStatusChange(AnimationStatus status) {
    if (!_needsMarquee) return;
    if (status == AnimationStatus.completed) {
      _pauseThen(() => _controller?.reverse());
    } else if (status == AnimationStatus.dismissed) {
      _pauseThen(() => _controller?.forward());
    }
  }

  void _pauseThen(VoidCallback action) {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || !_needsMarquee) return;
      action();
    });
  }

  void _scheduleStart() {
    if (_controller == null) return;
    _pauseTimer?.cancel();
    _controller!.value = 0;
    _pauseThen(() => _controller?.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final maxWidth = constraints.maxWidth;
        final textWidth = textPainter.width;
        final needsMarquee = textWidth > maxWidth;
        const endPadding = 8.0;
        final scrollDistance = (textWidth - maxWidth + endPadding)
            .clamp(0, textWidth)
            .toDouble();

        if (_needsMarquee != needsMarquee ||
            _scrollDistance != scrollDistance) {
          _needsMarquee = needsMarquee;
          _scrollDistance = scrollDistance;
          _configureController();
        }

        if (!needsMarquee) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller ?? const AlwaysStoppedAnimation<double>(0),
            builder: (context, child) {
              final value = _controller?.value ?? 0;
              final dx = -value * _scrollDistance;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
        );
      },
    );
  }
}

Future<ColorScheme?> _resolveColorScheme(ImageProvider imageProvider) async {
  try {
    return await ColorScheme.fromImageProvider(provider: imageProvider);
  } catch (_) {
    return null;
  }
}

class _CoverGradientContainer extends StatelessWidget {
  final Widget child;
  final Widget? background;

  const _CoverGradientContainer({required this.child, this.background});

  @override
  Widget build(BuildContext context) {
    final palette = context.select<CoverArtPaletteProvider, ColorScheme?>(
      (provider) => provider.palette,
    );
    var dominantColor = palette?.primary ?? Colors.black;

    final gradientLayer = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            dominantColor.withOpacity(0.9),
            dominantColor.withOpacity(0.7),
            dominantColor.withOpacity(0.5),
            dominantColor.withOpacity(0.4),
            Colors.black.withOpacity(0.2),
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        gradientLayer,
        if (background != null) Positioned.fill(child: background!),
        child,
      ],
    );
  }
}

class _MobileArtistInfoCard extends StatefulWidget {
  final GenericSimpleArtist artist;
  final String? trackId;

  const _MobileArtistInfoCard({required this.artist, this.trackId});

  @override
  State<_MobileArtistInfoCard> createState() => _MobileArtistInfoCardState();
}

class _MobileArtistInfoCardState extends State<_MobileArtistInfoCard> {
  Future<GenericArtist?>? _artistFuture;
  String? _artistId;
  String? _trackId;

  @override
  Widget build(BuildContext context) {
    if (_artistId != widget.artist.id || _trackId != widget.trackId) {
      _artistId = widget.artist.id;
      _trackId = widget.trackId;
      final spotifyInternal = context.read<SpotifyInternalProvider>();
      _artistFuture = _loadArtist(
        spotifyInternal,
        widget.artist,
        widget.trackId,
      );
    }

    return FutureBuilder<GenericArtist?>(
      future: _artistFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final topSongs =
            data?.topSongs.take(3).toList() ?? const <GenericSong>[];
        final imageUrl = data?.thumbnailUrl.isNotEmpty == true
            ? data!.thumbnailUrl
            : widget.artist.thumbnailUrl;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 320,
                      width: double.infinity,
                      child: imageUrl.isEmpty
                          ? Container(color: Colors.grey[850])
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  Container(color: Colors.grey[850]),
                            ),
                    ),
                    Positioned(
                      left: 16,
                      top: 16,
                      child: Text(
                        'Artist Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            data?.name ?? widget.artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () async {
                            await _openArtist(data, widget.artist);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('Open'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data == null
                          ? 'Loading artist info…'
                          : '${_formatNumber(data.followers)} monthly listeners',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    if (data != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Top songs',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < topSongs.length; i++) ...[
                              Text(
                                topSongs[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey[200],
                                  fontSize: 13,
                                ),
                              ),
                              if (i < topSongs.length - 1)
                                const Text(
                                  ' • ',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<GenericArtist?> _loadArtist(
    SpotifyInternalProvider spotify,
    GenericSimpleArtist artist,
    String? trackId,
  ) async {
    try {
      if (trackId != null && trackId.isNotEmpty) {
        return await spotify.getNpvArtistInfo(artist.id, trackId);
      }
      return await spotify.getArtistInfo(artist.id);
    } catch (_) {
      return null;
    }
  }

  String _formatNumber(int value) {
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  Future<void> _openArtist(
    GenericArtist? data,
    GenericSimpleArtist fallback,
  ) async {
    final libraryState = context.read<LibraryState>();
    final navState = context.read<NavigationState>();
    final artist = data == null
        ? fallback
        : GenericSimpleArtist(
            id: data.id,
            source: data.source,
            name: data.name,
            thumbnailUrl: data.thumbnailUrl,
          );

    await AppNavigation.instance.disableFullPlayerDesktopMode();
    if (!mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ArtistDetailView(
              artistId: artist.id,
              initialArtist: artist,
              playlists: libraryState.playlists,
              albums: libraryState.albums,
              artists: libraryState.artists,
              initialLibraryView: navState.selectedLibraryView,
              initialNavIndex: navState.selectedNavIndex,
            ),
      ),
    );
  }
}

class _FullPlayerVolumeQuickPanel extends StatelessWidget {
  final Rect anchorRect;
  final Size overlaySize;
  final Color accentColor;
  final VoidCallback onToggleMute;

  const _FullPlayerVolumeQuickPanel({
    required this.anchorRect,
    required this.overlaySize,
    required this.accentColor,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    const panelWidth = 228.0;
    const panelHeight = 72.0;
    const margin = 8.0;

    final left = (anchorRect.right - panelWidth).clamp(
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                child: Selector<global_audio_player.WispAudioHandler, double>(
                  selector: (context, player) => player.volume,
                  builder: (context, volume, child) {
                    final audio = context
                        .read<global_audio_player.WispAudioHandler>();
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: volume <= 0.001 ? 'Unmute' : 'Mute',
                          onPressed: onToggleMute,
                          icon: Icon(
                            volume <= 0.001
                                ? Icons.volume_off
                                : volume < 0.5
                                ? Icons.volume_down
                                : Icons.volume_up,
                            color: Colors.grey[300],
                            size: 18,
                          ),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        Expanded(
                          child: _FullPlayerHoverVolumeSlider(
                            value: volume,
                            onChanged: (value) => audio.setVolume(value),
                            primaryColor: accentColor,
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${(volume * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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

class _FullPlayerHoverVolumeSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final Color primaryColor;

  const _FullPlayerHoverVolumeSlider({
    required this.value,
    required this.onChanged,
    required this.primaryColor,
  });

  @override
  State<_FullPlayerHoverVolumeSlider> createState() =>
      _FullPlayerHoverVolumeSliderState();
}

class _FullPlayerHoverVolumeSliderState
    extends State<_FullPlayerHoverVolumeSlider> {
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
          inactiveTrackColor: Colors.grey[700],
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
