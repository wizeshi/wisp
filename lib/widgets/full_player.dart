/// Full-screen player bottom sheet for mobile
library;

import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../providers/lyrics/provider.dart';
import '../providers/metadata/spotify_internal.dart';
import '../providers/library/library_state.dart';
import '../providers/navigation_state.dart';
import '../models/metadata_models.dart';
import '../providers/preferences/preferences_provider.dart';
import '../providers/theme/cover_art_palette_provider.dart';
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
  Widget _buildSheet(BuildContext context, ScrollController scrollController, String style) {
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
                    final player =
                      context.read<global_audio_player.WispAudioHandler>();
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

  Widget _buildSingleLyricsLine(
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

    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = player.throttledPosition.inMilliseconds - delayMs;
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
          constraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
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
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = player.throttledPosition.inMilliseconds - delayMs;
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
                  foregroundColor:
                      Theme.of(context).colorScheme.onPrimary,
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
              icon: const Icon(Icons.share),
              iconSize: 24,
              color: Colors.grey[400],
              onPressed: () => { },
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
    final colorScheme = Theme.of(context).colorScheme;
    final position = player.throttledPosition;
    final duration = player.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

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
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
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
                    player.seek(newPosition);
                  },
                ),
              )
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
          onPressed: player.toggleShuffle,
        ),
        // Previous
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 36,
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          onPressed: player.queueTracks.isEmpty ? null : player.skipPrevious,
        ),
        // Play/Pause - Large circular button
        _buildPlayPauseButton(context, player, bgColor),
        // Next
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 36,
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          onPressed: player.queueTracks.isEmpty ? null : player.skipNext,
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
          onPressed: player.toggleRepeat,
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
    Color bgColor,
  ) {
    if (player.isLoading || player.isBuffering) {
      return SizedBox(
        width: 64,
        height: 64,
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    final isPlaying = player.isPlaying;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
        iconSize: 36,
        color: Colors.white,
        padding: EdgeInsets.zero,
        onPressed: () {
          if (isPlaying) {
            player.pause();
          } else if (player.currentTrack != null) {
            player.play();
          } else if (player.queueTracks.isNotEmpty) {
            player.playTrack(player.queueTracks.first);
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

  @override
  Widget build(BuildContext context) {
    return Consumer2<global_audio_player.WispAudioHandler, LyricsProvider>(
      builder: (context, player, lyricsProvider, child) {
        final currentTrack = player.currentTrack;
        final imageUrl = currentTrack?.thumbnailUrl ?? '';
        final useCanvas = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.animatedCanvasEnabled,
        );
        final canUseCanvas = useCanvas &&
            currentTrack != null &&
            (currentTrack.source == SongSource.spotifyInternal ||
                currentTrack.source == SongSource.spotify);
        final spotifyInternal = context.read<SpotifyInternalProvider>();

        final viewPadding = MediaQuery.of(context).viewPadding;
        final windowPadding = MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        ).padding;
        final topInset = viewPadding.top == 0 ? windowPadding.top : viewPadding.top;
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

        return _CoverGradientContainer(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  top: topInset,
                  bottom: bottomInset,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Header with down arrow, title, more button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: _buildHeader(context),
                    ),
                    const SizedBox(height: 48),
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
                              // Album art at 90% width
                              if (canUseCanvas)
                                FutureBuilder<String?>(
                                  future: spotifyInternal.getCanvasUrl(
                                    currentTrack!.id,
                                  ),
                                  builder: (context, snapshot) {
                                    final canvasUrl = snapshot.data ?? '';
                                    if (canvasUrl.isNotEmpty) {
                                      return _buildCanvasVideo(canvasUrl, imageUrl);
                                    }
                                    return _buildAlbumArt(context, imageUrl);
                                  },
                                )
                              else
                                _buildAlbumArt(context, imageUrl),
                              _buildSingleLyricsLine(
                                player,
                                lyricsProvider,
                              ),
                              const SizedBox(height: 24),
                              // Track info with links
                              _buildTrackInfo(currentTrack, btnColor),
                              const SizedBox(height: 16),
                              // Progress bar with controls
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
            ),
          ),
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
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
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
        errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
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

/// Apple Music variant — currently uses the Spotify layout but is a separate
/// class to allow future customization.
class AppleMusicFullScreenPlayer extends StatelessWidget {
  final ScrollController scrollController;

  const AppleMusicFullScreenPlayer({required this.scrollController, super.key});

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
                    final player =
                      context.read<global_audio_player.WispAudioHandler>();
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

    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = player.throttledPosition.inMilliseconds - delayMs;
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
          constraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          likedIcon: CupertinoIcons.heart_fill,
          notLikedIcon: CupertinoIcons.heart,
          color: likeColor,
        ),
      ],
    );
  }

  Widget _buildLyricsPreview(
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
    final delayMs =
        (lyricsProvider.getDelaySecondsCached(currentTrack.id) * 1000).round();
    final adjustedPosition = player.throttledPosition.inMilliseconds - delayMs;
    final effectivePosition = adjustedPosition < 0 ? 0 : adjustedPosition;
    final previewLines = lyrics == null
        ? const <LyricsLine>[]
        : _getPreviewLines(lyrics, effectivePosition);

    final palette = context.select<CoverArtPaletteProvider, ColorScheme?>(
      (provider) => provider.palette,
    );
    final bgColor = HSLColor.fromColor(
      palette?.onSecondaryContainer ?? const Color(0xFF1A1A1A),
    ).withLightness(0.6).withSaturation(0.65).toColor();
    final btnColor = HSLColor.fromColor(
      palette?.onPrimaryContainer ?? const Color(0xFF1A1A1A),
    ).withLightness(0.7).withSaturation(1).toColor();

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
    Color btnColor,
  ) {
    return Column(
      children: [
        const SizedBox(height: 4),
        _buildProgressBar(context, player),
        const SizedBox(height: 16),
        _buildPlaybackControls(context, player),
        const SizedBox(height: 16),
        _buildSecondaryControls(context, btnColor),
      ],
    );
  }

  Widget _buildSecondaryControls(BuildContext context, Color btnColor) {
    return SizedBox(
      height: 56,
      child: Consumer<global_audio_player.WispAudioHandler>(
        builder: (context, player, child) {
          return PageView(
            scrollDirection: Axis.horizontal,
            pageSnapping: true,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.shuffle),
                    iconSize: 24,
                    color: player.shuffleEnabled
                        ? btnColor
                        : Colors.grey[200],
                    onPressed: player.toggleShuffle,
                  ),
                  IconButton(
                    icon: Icon(
                      player.repeatMode == global_audio_player.RepeatMode.one
                          ? CupertinoIcons.repeat_1
                          : CupertinoIcons.repeat,
                    ),
                    iconSize: 24,
                    color: player.repeatMode != global_audio_player.RepeatMode.off
                        ? btnColor
                        : Colors.grey[200],
                    onPressed: player.toggleRepeat,
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.music_note_list),
                    iconSize: 24,
                    color: Colors.grey[200],
                    onPressed: () {
                      showMobileQueueSheet(context);
                    },
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.double_music_note),
                    iconSize: 24,
                    color: Colors.grey[200],
                    onPressed: () => _openLyrics(context),
                  ),
                ],
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
    final colorScheme = Theme.of(context).colorScheme;
    final position = player.throttledPosition;
    final duration = player.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

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
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3),
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
                    player.seek(newPosition);
                  },
                ),
              )
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
          onPressed: player.queueTracks.isEmpty ? null : player.skipPrevious,
        ),
        // Play/Pause - Large circular button
        _buildPlayPauseButton(context, player),
        // Next
        IconButton(
          icon: const Icon(CupertinoIcons.forward_fill),
          iconSize: 36,
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          onPressed: player.queueTracks.isEmpty ? null : player.skipNext,
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton(
    BuildContext context,
    global_audio_player.WispAudioHandler player,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    if (player.isLoading || player.isBuffering) {
      return SizedBox(
        width: 96,
        height: 96,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    final isPlaying = player.isPlaying;

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill),
        iconSize: 64,
        color: colorScheme.onPrimary,
        padding: EdgeInsets.zero,
        onPressed: () {
          if (isPlaying) {
            player.pause();
          } else if (player.currentTrack != null) {
            player.play();
          } else if (player.queueTracks.isNotEmpty) {
            player.playTrack(player.queueTracks.first);
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

  @override
  Widget build(BuildContext context) {
    return Consumer2<global_audio_player.WispAudioHandler, LyricsProvider>(
      builder: (context, player, lyricsProvider, child) {
        final currentTrack = player.currentTrack;
        final imageUrl = currentTrack?.thumbnailUrl ?? '';

        final viewPadding = MediaQuery.of(context).viewPadding;
        final windowPadding = MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        ).padding;
        final topInset = viewPadding.top == 0 ? windowPadding.top : viewPadding.top;
        final bottomInset = viewPadding.bottom == 0
            ? windowPadding.bottom
            : viewPadding.bottom;

        final imageProvider = CachedNetworkImageProvider(imageUrl);

        return FutureBuilder<ColorScheme?>(
          future: ColorScheme.fromImageProvider(
            provider: imageProvider,
          ).catchError((_) => null as ColorScheme?),
          builder: (context, snapshot) {
            final palette = snapshot.data;
            var bgColor = HSLColor.fromColor(palette?.onSecondaryContainer ?? const Color(0xFF1A1A1A)).withLightness(0.6).withSaturation(0.65).toColor();
            var btnColor = HSLColor.fromColor(palette?.onPrimaryContainer ?? const Color(0xFF1A1A1A)).withLightness(0.7).withSaturation(1).toColor();

            return Stack(
              clipBehavior: Clip.hardEdge,
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
                      )
                    ]
                  )
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
                      )
                    ]
                  )
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: bottomInset,
                    ),
                    child: Column(
                      children: [
                        // Header with down arrow, title, more button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0).add(EdgeInsets.only(top: topInset)),
                          child: _buildHeader(context),
                        ),
                        const SizedBox(height: 48),
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
                                  // Album art at 90% width
                                  SizedBox(height: MediaQuery.of(context).size.height * 0.375),
                                  _buildSingleLyricsLine(
                                    player,
                                    lyricsProvider,
                                  ),
                                  const SizedBox(height: 24),
                                  // Track info with links
                                  _buildTrackInfo(currentTrack, btnColor ?? bgColor),
                                  const SizedBox(height: 16),
                                  // Progress bar with controls
                                  _buildPlayerControls(context, player, btnColor ?? bgColor),
                                  /* const SizedBox(height: 16),
                                  _buildLyricsPreview(
                                    context,
                                    player,
                                    lyricsProvider,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildArtistInfoSection(currentTrack), */
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]
            );
          },
        );
      }
    );
  }
}


/// YouTube Music variant — currently reuses the Spotify layout.
class YouTubeMusicFullScreenPlayer extends StatelessWidget {
  final ScrollController scrollController;

  const YouTubeMusicFullScreenPlayer({required this.scrollController, super.key});

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

        if (_needsMarquee != needsMarquee || _scrollDistance != scrollDistance) {
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

class _CoverGradientContainer extends StatelessWidget {
  final Widget child;

  const _CoverGradientContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = context.select<CoverArtPaletteProvider, ColorScheme?>(
      (provider) => provider.palette,
    );
    var dominantColor = palette?.onSecondaryContainer ?? Colors.black;
    if (dominantColor.computeLuminance() < 0.2) {
      final altColor = palette?.onSecondary;
      if (altColor != null && altColor.computeLuminance() >= 0.2) {
        dominantColor = altColor;
      }
    }

    return Container(
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
      child: child,
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
