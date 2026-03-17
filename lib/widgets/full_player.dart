/// Full-screen player bottom sheet for mobile
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:wisp/services/connect/connect_models.dart';
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
import '../widgets/track_context_menu.dart';
import '../widgets/animated_lyrics_preview.dart';
import '../widgets/like_button.dart';

class FullScreenPlayer extends StatelessWidget {
  const FullScreenPlayer({super.key});

  static void show(BuildContext context) {
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
    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.5, 1.0],
      builder: (context, scrollController) =>
          _buildSheet(context, scrollController, style),
    );
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
    return _MobileArtistInfoCard(artist: artist);
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
            // Down arrow button (10%)
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                color: Colors.white,
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // Center text (80%)
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
            // More button (10%)
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
                  final libraryState = context.read<LibraryState>();
                  final navState = context.read<NavigationState>();
                  TrackContextMenu.show(
                    context: context,
                    track: currentTrack,
                    playlists: libraryState.playlists,
                    albums: libraryState.albums,
                    artists: libraryState.artists,
                    currentLibraryView: navState.selectedLibraryView,
                    currentNavIndex: navState.selectedNavIndex,
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
    final line = _getSingleLine(lyrics, effectivePosition);
    if (line == null || line.content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 32),
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
        child: Text(
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

  Widget _buildTrackInfo(dynamic currentTrack, Color likeColor) {
    final title = currentTrack?.title ?? 'No track playing';
    final artists = currentTrack?.artists ?? [];

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
            child: const Text(
              'Lyrics Preview',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  lyrics == null
                      ? ''
                      : 'Lyrics provided by ${lyrics.provider.label}',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              ElevatedButton(
                onPressed: lyrics == null
                    ? null
                    : () {
                        _openLyrics(context);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: btnColor,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Show lyrics'),
              ),
            ],
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
    if (lyrics.lines.isEmpty) return const [];
    if (!lyrics.synced) {
      return lyrics.lines.take(5).toList();
    }
    final currentIndex = _findCurrentLineIndex(lyrics.lines, positionMs);
    return lyrics.lines.skip(currentIndex).take(5).toList();
  }

  LyricsLine? _getSingleLine(LyricsResult lyrics, int positionMs) {
    if (lyrics.lines.isEmpty) return null;
    if (!lyrics.synced) {
      return lyrics.lines.first;
    }
    final currentIndex = _findCurrentLineIndex(lyrics.lines, positionMs);
    if (currentIndex < 0 || currentIndex >= lyrics.lines.length) return null;
    return lyrics.lines[currentIndex];
  }

  int _findCurrentLineIndex(List<LyricsLine> lines, int positionMs) {
    var index = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startTimeMs <= positionMs) {
        index = i;
      } else {
        break;
      }
    }
    return index;
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
        : player.throttledPosition;
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
        color: Colors.white,
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
    final topSpan = MediaQuery.of(context).size.height * 0.72;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: double.infinity,
        height: topSpan,
        child: _buildCanvasVideo(canvasUrl, fallbackUrl),
      ),
    );
  }

  Widget _buildCanvasBackground(String url, String fallbackUrl) {
    return _CanvasVideo(url: url, fallbackUrl: fallbackUrl);
  }

  Widget _buildFallbackBackground(
    BuildContext context,
    String imageUrl,
    double topInset,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: -topInset,
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            children: [
              Expanded(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    repeat: ImageRepeat.repeatY,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: topInset,
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black,
                      Colors.black,
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.08, 0.88, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.fitHeight,
                  ),
                ),
              ),
            ],
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
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: _buildHeader(context),
                  ),
                  const SizedBox(height: 48),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            hasCanvas
                                ? _buildHiddenArtworkPlaceholder(context)
                                : _buildAlbumArt(context, imageUrl),
                            _buildSingleLyricsLine(
                              context,
                              player,
                              lyricsProvider,
                            ),
                            const SizedBox(height: 24),
                            _buildTrackInfo(currentTrack, btnColor),
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

          if (hasCanvas) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: const SizedBox.expand(),
                  ),
                ),
                _buildSpotifyTopCanvasBackground(context, canvasUrl, imageUrl),
                Container(color: Colors.black.withOpacity(0.28)),
                content,
              ],
            );
          }

          return _CoverGradientContainer(child: content);
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
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
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
  }

  @override
  Widget build(BuildContext context) {
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 50),
  )..repeat();

  @override
  void dispose() {
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
  static final ScrollController _lyricsScrollController = ScrollController();
  static int _lastLyricsIndex = -1;
  static String? _lastLyricsTrackId;
  static List<GlobalKey>? _lyricsLineKeys;
  static String? _lyricsLineKeysTrackId;

  const AppleMusicFullScreenPlayer({required this.scrollController, super.key});

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
    final double expandedSize = math.min(
      MediaQuery.of(context).size.width - 48,
      360.0,
    );
    if (isNowPlaying && hideNowPlayingCover) {
      return SizedBox(width: double.infinity, height: expandedSize);
    }
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
              child: _buildCoverImageBox(
                context,
                imageUrl,
                isNowPlaying ? expandedSize : compactSize,
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

    final state = lyricsProvider.getState(currentTrack, LyricsSyncMode.synced);
    if (!state.isLoading && state.lyrics == null && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        lyricsProvider.ensureLyrics(currentTrack, LyricsSyncMode.synced);
      });
    }

    lyricsProvider.ensureDelayLoaded(currentTrack.id);
    final lyrics = state.lyrics;
    if (state.isLoading && lyrics == null) {
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

    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
    final basePosition = useHandoffState
        ? connect.linkedInterpolatedPosition
        : player.throttledPosition;
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = basePosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    final currentIndex = lyrics.synced
        ? _findCurrentLineIndex(lyrics.lines, effectivePosition)
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
        _lyricsLineKeys!.length != lyrics.lines.length) {
      _lyricsLineKeysTrackId = currentTrack.id;
      _lyricsLineKeys = List<GlobalKey>.generate(
        lyrics.lines.length,
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
          itemCount: lyrics.lines.length,
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          itemBuilder: (context, index) {
            final lyricLine = lyrics.lines[index];
            final line = lyricLine.content.trim();
            if (line.isEmpty) {
              return SizedBox(key: lineKeys[index], height: 18);
            }

            final distance = (index - currentIndex).abs();
            final isCurrent = index == currentIndex;
            final opacity = isCurrent
                ? 1.0
                : (1.0 - (distance * 0.22)).clamp(0.16, 0.72);

            return AnimatedOpacity(
              key: lineKeys[index],
              duration: const Duration(milliseconds: 220),
              opacity: opacity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: lyrics.synced
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
                        color: isCurrent ? Colors.white : Colors.grey[500],
                        fontSize: isCurrent ? 34 : 30,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQueueModeContent(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
  ) {
    final queue = player.queueTracks;
    final currentIndex = player.currentIndex;
    final contextName = player.playbackContextName;
    final connect = context.read<ConnectSessionProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildQueuePillButton(
                icon: CupertinoIcons.shuffle,
                selected: player.shuffleEnabled,
                onTap: connect.requestToggleShuffle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildQueuePillButton(
                icon: player.repeatMode == global_audio_player.RepeatMode.one
                    ? CupertinoIcons.repeat_1
                    : CupertinoIcons.repeat,
                selected:
                    player.repeatMode != global_audio_player.RepeatMode.off,
                onTap: connect.requestToggleRepeat,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Text(
                'History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
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
        const Text(
          'Continue playing',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          contextName != null && contextName.isNotEmpty
              ? 'from $contextName'
              : 'from Queue',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: queue.isEmpty
              ? Center(
                  child: Text(
                    'Queue is empty',
                    style: TextStyle(color: Colors.grey[500], fontSize: 18),
                  ),
                )
              : ListView.separated(
                  itemCount: queue.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final track = queue[index];
                    final isCurrent = index == currentIndex;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        unawaited(
                          context
                              .read<ConnectSessionProvider>()
                              .requestPlayQueueIndex(index),
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
                          Icon(
                            Icons.drag_handle,
                            color: Colors.grey[500],
                            size: 22,
                          ),
                        ],
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
  ) {
    switch (mode) {
      case _ApplePlayerViewMode.lyrics:
        return _buildLyricsModeContent(context, player, lyricsProvider);
      case _ApplePlayerViewMode.queue:
        return _buildQueueModeContent(context, player);
      case _ApplePlayerViewMode.nowPlaying:
        return const SizedBox.shrink();
    }
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

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Down arrow button (10%)
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                color: Colors.white,
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // Center text (80%)
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
            // More button (10%)
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
                  final libraryState = context.read<LibraryState>();
                  final navState = context.read<NavigationState>();
                  TrackContextMenu.show(
                    context: context,
                    track: currentTrack,
                    playlists: libraryState.playlists,
                    albums: libraryState.albums,
                    artists: libraryState.artists,
                    currentLibraryView: navState.selectedLibraryView,
                    currentNavIndex: navState.selectedNavIndex,
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
    final line = _getSingleLine(lyrics, effectivePosition);
    if (line == null || line.content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 32),
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
        child: Text(
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

  Widget _buildTrackInfo(dynamic currentTrack, Color likeColor) {
    final title = currentTrack?.title ?? 'No track playing';
    final artists = currentTrack?.artists ?? [];

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
    if (lyrics.lines.isEmpty) return null;
    if (!lyrics.synced) {
      return lyrics.lines.first;
    }
    final currentIndex = _findCurrentLineIndex(lyrics.lines, positionMs);
    if (currentIndex < 0 || currentIndex >= lyrics.lines.length) return null;
    return lyrics.lines[currentIndex];
  }

  int _findCurrentLineIndex(List<LyricsLine> lines, int positionMs) {
    var index = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startTimeMs <= positionMs) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  Widget _buildPlayerControls(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    Color btnColor,
    _ApplePlayerViewMode mode,
  ) {
    return Column(
      children: [
        const SizedBox(height: 4),
        _buildProgressBar(context, player),
        const SizedBox(height: 16),
        _buildPlaybackControls(context, player),
        const SizedBox(height: 16),
        _buildSecondaryControls(context, btnColor, mode),
      ],
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
        : player.throttledPosition;
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
        _RotatingBlurredCoverBackground(imageUrl: fallbackUrl),
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
    return _RotatingBlurredCoverBackground(imageUrl: imageUrl);
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

        final imageProvider = CachedNetworkImageProvider(imageUrl);

        return FutureBuilder<ColorScheme?>(
          future: _resolveColorScheme(imageProvider),
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
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.45),
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
                                const SizedBox(height: 24),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24.0,
                                    ),
                                    child: Column(
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
                                        const SizedBox(height: 32),
                                        if (isNowPlaying) ...[
                                          _buildSingleLyricsLine(
                                            context,
                                            player,
                                            lyricsProvider,
                                          ),
                                          const SizedBox(height: 24),
                                          _buildTrackInfo(
                                            currentTrack,
                                            btnColor ?? bgColor,
                                          ),
                                          const Spacer(),
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
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        _buildPlayerControls(
                                          context,
                                          player,
                                          btnColor ?? bgColor,
                                          mode,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
  final Color? dominantColorOverride;
  final bool overlayGradientOnBackground;

  const _CoverGradientContainer({
    required this.child,
    this.background,
    this.dominantColorOverride,
    this.overlayGradientOnBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.select<CoverArtPaletteProvider, ColorScheme?>(
      (provider) => provider.palette,
    );
    var dominantColor =
        dominantColorOverride ??
        palette?.primaryContainer ??
        palette?.primary ??
        palette?.onSecondaryContainer ??
        Colors.black;
    if (dominantColor.computeLuminance() < 0.2) {
      final altColor = palette?.primary ?? palette?.secondary;
      if (altColor != null && altColor.computeLuminance() >= 0.2) {
        dominantColor = altColor;
      }
    }

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
        if (!overlayGradientOnBackground) gradientLayer,
        if (background != null) Positioned.fill(child: background!),
        if (overlayGradientOnBackground) gradientLayer,
        child,
      ],
    );
  }
}

class _MobileArtistInfoCard extends StatefulWidget {
  final GenericSimpleArtist artist;

  const _MobileArtistInfoCard({required this.artist});

  @override
  State<_MobileArtistInfoCard> createState() => _MobileArtistInfoCardState();
}

class _MobileArtistInfoCardState extends State<_MobileArtistInfoCard> {
  Future<GenericArtist?>? _artistFuture;
  String? _artistId;

  @override
  Widget build(BuildContext context) {
    if (_artistId != widget.artist.id) {
      _artistId = widget.artist.id;
      final spotifyInternal = context.read<SpotifyInternalProvider>();
      _artistFuture = _loadArtist(spotifyInternal, widget.artist);
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
                          onPressed: () => _openArtist(data, widget.artist),
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
  ) async {
    try {
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

  void _openArtist(GenericArtist? data, GenericSimpleArtist fallback) {
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
