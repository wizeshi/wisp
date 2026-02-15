/// Full-screen player bottom sheet for mobile
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/audio/player.dart' as global_audio_player;
import '../providers/lyrics/provider.dart';
import '../providers/metadata/spotify.dart';
import '../providers/library/library_state.dart';
import '../providers/navigation_state.dart';
import '../models/metadata_models.dart';
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
    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.5, 1.0],
      builder: (context, scrollController) {
        return Consumer2<global_audio_player.AudioPlayerProvider, LyricsProvider>(
          builder: (context, player, lyricsProvider, child) {
            final currentTrack = player.currentTrack;
            final imageUrl = currentTrack?.thumbnailUrl ?? '';

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
            return _CoverGradientContainer(
              imageUrl: imageUrl,
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
                                  _buildAlbumArt(context, imageUrl),
                                  _buildSingleLyricsLine(
                                    player,
                                    lyricsProvider,
                                  ),
                                  const SizedBox(height: 24),
                                  // Track info with links
                                  _buildTrackInfo(currentTrack),
                                  const SizedBox(height: 16),
                                  // Progress bar with controls
                                  _buildPlayerControls(context, player),
                                  const SizedBox(height: 16),
                                  _buildLyricsPreview(
                                    context,
                                    player,
                                    lyricsProvider,
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
      },
    );
  }

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
    return Consumer<global_audio_player.AudioPlayerProvider>(
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
                  final player = context.read<global_audio_player.AudioPlayerProvider>();
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

  Widget _buildSingleLyricsLine(
    global_audio_player.AudioPlayerProvider player,
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

  Widget _buildTrackInfo(dynamic currentTrack) {
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
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                            color: Colors.grey[300],
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
        ),
      ],
    );
  }

  Widget _buildLyricsPreview(
    BuildContext context,
    global_audio_player.AudioPlayerProvider player,
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

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.isLoading && lyrics == null)
            const Text(
              'Loading lyrics…',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            )
          else if (previewLines.isEmpty)
            const Text(
              'No lyrics found',
              style: TextStyle(color: Colors.grey, fontSize: 13),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  lyrics == null
                      ? ''
                      : 'Lyrics provided by ${lyrics.provider.label}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ),
              ElevatedButton(
                onPressed: lyrics == null
                    ? null
                    : () {
                        _openLyrics(context);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
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
    global_audio_player.AudioPlayerProvider player,
  ) {
    return Column(
      children: [
        const SizedBox(height: 4),
        _buildProgressBar(context, player),
        const SizedBox(height: 16),
        _buildPlaybackControls(context, player),
        const SizedBox(height: 16),
        _buildSecondaryControls(context),
      ],
    );
  }

  Widget _buildSecondaryControls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
          icon: const Icon(Icons.lyrics_outlined),
          iconSize: 24,
          color: Colors.grey[400],
          onPressed: () => _openLyrics(context),
        ),
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context, global_audio_player.AudioPlayerProvider player) {
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
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: colorScheme.primary,
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
    global_audio_player.AudioPlayerProvider player,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Shuffle
        IconButton(
          icon: const Icon(Icons.shuffle),
          iconSize: 28,
          color: player.shuffleEnabled ? colorScheme.primary : Colors.white,
          padding: const EdgeInsets.all(8),
          onPressed: player.toggleShuffle,
        ),
        // Previous
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 36,
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          onPressed: player.queue.isEmpty ? null : player.skipPrevious,
        ),
        // Play/Pause - Large circular button
        _buildPlayPauseButton(context, player),
        // Next
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 36,
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          onPressed: player.queue.isEmpty ? null : player.skipNext,
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
              ? colorScheme.primary
              : Colors.white,
          padding: const EdgeInsets.all(8),
          onPressed: player.toggleRepeat,
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton(
    BuildContext context,
    global_audio_player.AudioPlayerProvider player,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    if (player.isLoading || player.isBuffering) {
      return SizedBox(
        width: 64,
        height: 64,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.primary,
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
        color: colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
        iconSize: 36,
        color: colorScheme.onPrimary,
        padding: EdgeInsets.zero,
        onPressed: () {
          if (isPlaying) {
            player.pause();
          } else if (player.currentTrack != null) {
            player.play();
          } else if (player.queue.isNotEmpty) {
            player.playTrack(player.queue.first);
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
}

class _CoverGradientContainer extends StatefulWidget {
  final String imageUrl;
  final Widget child;

  const _CoverGradientContainer({required this.imageUrl, required this.child});

  @override
  State<_CoverGradientContainer> createState() =>
      _CoverGradientContainerState();
}

class _CoverGradientContainerState extends State<_CoverGradientContainer> {
  Color _dominantColor = Colors.black;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _updatePalette(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant _CoverGradientContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _updatePalette(widget.imageUrl);
    }
  }

  Future<void> _updatePalette(String imageUrl) async {
    if (imageUrl.isEmpty || imageUrl == _currentUrl) return;
    _currentUrl = imageUrl;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(imageUrl),
        maximumColorCount: 12,
      );
      final color = palette.dominantColor?.color ?? Colors.black;
      if (mounted) {
        setState(() {
          _dominantColor = color;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _dominantColor = Colors.black;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _dominantColor.withOpacity(0.7),
            _dominantColor.withOpacity(0.2),
            Colors.black.withOpacity(0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: widget.child,
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
      final spotify = context.read<SpotifyProvider>();
      _artistFuture = _loadArtist(spotify, widget.artist);
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
                      height: 170,
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
                        'Artist profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
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
                          : '${_formatNumber(data.monthlyListeners)} monthly listeners',
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
    SpotifyProvider spotify,
    GenericSimpleArtist artist,
  ) async {
    final cached = await spotify.getCachedArtistInfo(artist.id);
    if (cached != null) return cached;
    try {
      return await spotify.getArtistInfo(artist.id);
    } catch (_) {
      return cached;
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
