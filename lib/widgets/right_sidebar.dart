import 'dart:async';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metadata_models.dart';
import '../providers/audio/player.dart';
import '../providers/lyrics/provider.dart';
import '../providers/library/library_state.dart';
import '../providers/metadata/spotify.dart';
import '../providers/navigation_state.dart';
import '../services/navigation_history.dart';
import '../views/artist_detail.dart';
import '../views/list_detail.dart';
import '../views/lyrics.dart';
import '../views/queue.dart';
import 'animated_lyrics_preview.dart';
import 'hover_underline.dart';
import 'library_item_context_menu.dart';
import 'like_button.dart';

class RightSidebar extends StatelessWidget {
  final double width;
  final ValueChanged<double> onResize;

  const RightSidebar({super.key, required this.width, required this.onResize});

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: width,
      child: Row(
        children: [
          _ResizeHandle(onResize: onResize),
          Expanded(
            child: Material(
              color: const Color(0xFF0F0F0F),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Colors.grey[900]!, width: 1),
                  ),
                ),
                child: SafeArea(
                  left: false,
                  right: true,
                  top: false,
                  bottom: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: const [
                        _NowPlayingCard(),
                        SizedBox(height: 16),
                        _ArtistInfoCard(),
                        SizedBox(height: 16),
                        _LyricsPreviewCard(),
                        SizedBox(height: 16),
                        _QueuePreviewCard(),
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
}

class _ResizeHandle extends StatelessWidget {
  final ValueChanged<double> onResize;

  const _ResizeHandle({required this.onResize});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
        child: SizedBox(
          width: 6,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 2,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerProvider, _NowPlayingData>(
      selector: (context, player) => _NowPlayingData(
        track: player.currentTrack,
        playbackContextName: player.playbackContextName,
      ),
      builder: (context, data, child) {
        final libraryState = context.read<LibraryState>();
        final navState = context.read<NavigationState>();
        final track = data.track;
        final headerText =
            (data.playbackContextName?.trim().isNotEmpty ?? false)
            ? data.playbackContextName!.trim()
            : 'Now playing';
        final album = track?.album;
        final primaryArtist = track?.artists.isNotEmpty == true
            ? track!.artists.first
            : null;
        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headerText,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (track == null)
                const Text(
                  'Nothing playing',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: _TrackArtwork(url: track.thumbnailUrl),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: HoverUnderline(
                            cursor: album != null && album.id.isNotEmpty
                                ? SystemMouseCursors.click
                                : SystemMouseCursors.basic,
                            onTap: album != null && album.id.isNotEmpty
                                ? () =>
                                    _openAlbum(album, libraryState, navState)
                                : null,
                            builder: (isHovering) => _MarqueeText(
                              text: track.title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                decoration: isHovering && album != null
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        LikeButton(
                          track: track,
                          iconSize: 20,
                          padding: const EdgeInsets.all(2),
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    HoverUnderline(
                      cursor: primaryArtist != null
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onTap: primaryArtist != null
                          ? () => _openArtist(
                              primaryArtist,
                              libraryState,
                              navState,
                            )
                          : null,
                      onSecondaryTapDown: primaryArtist != null
                          ? (details) {
                              LibraryItemContextMenu.show(
                                context: context,
                                item: primaryArtist,
                                position: details.globalPosition,
                                playlists: libraryState.playlists,
                                albums: libraryState.albums,
                                artists: libraryState.artists,
                                currentLibraryView:
                                    navState.selectedLibraryView,
                                currentNavIndex: navState.selectedNavIndex,
                              );
                            }
                          : null,
                      builder: (isHovering) => _MarqueeText(
                        text: track.artists.map((a) => a.name).join(', '),
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          decoration: isHovering
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                    // Removed origin text under artist
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  void _openAlbum(
    GenericSimpleAlbum album,
    LibraryState libraryState,
    NavigationState navState,
  ) {
    NavigationHistory.instance.navigatorKey.currentState?.push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            SharedListDetailView(
              id: album.id,
              type: SharedListType.album,
              initialTitle: album.title,
              initialThumbnailUrl: album.thumbnailUrl,
              playlists: libraryState.playlists,
              albums: libraryState.albums,
              artists: libraryState.artists,
              initialLibraryView: navState.selectedLibraryView,
              initialNavIndex: navState.selectedNavIndex,
            ),
      ),
    );
  }

  void _openArtist(
    GenericSimpleArtist artist,
    LibraryState libraryState,
    NavigationState navState,
  ) {
    NavigationHistory.instance.navigatorKey.currentState?.push(
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

class _TrackArtwork extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;

  const _TrackArtwork({required this.url, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: (width == null && height == null)
          ? SizedBox.expand(child: _buildImage())
          : SizedBox(
              width: width ?? height,
              height: height ?? width,
              child: _buildImage(),
            ),
    );
  }

  Widget _buildImage() {
    return url.isEmpty
        ? Container(
            color: Colors.grey[850],
            child: const Icon(Icons.music_note),
          )
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.grey[850]),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey[850],
              child: const Icon(Icons.music_note),
            ),
          );
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

class _ArtistInfoCard extends StatefulWidget {
  const _ArtistInfoCard();

  @override
  State<_ArtistInfoCard> createState() => _ArtistInfoCardState();
}

class _ArtistInfoCardState extends State<_ArtistInfoCard> {
  Future<GenericArtist?>? _artistFuture;
  String? _artistId;

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerProvider, GenericSimpleArtist?>(
      selector: (context, player) {
        final track = player.currentTrack;
        return track?.artists.isNotEmpty == true
            ? track!.artists.first
            : null;
      },
      builder: (context, artist, child) {
        if (artist != null && artist.id != _artistId) {
          _artistId = artist.id;
          final spotify = context.read<SpotifyProvider>();
          _artistFuture = _loadArtist(spotify, artist);
        }

        if (artist == null) {
          return _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'About the artist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'No artist info available',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return FutureBuilder<GenericArtist?>(
          future: _artistFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final imageUrl = data?.thumbnailUrl.isNotEmpty == true
                ? data!.thumbnailUrl
                : artist.thumbnailUrl;

            return _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About the artist',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 72,
                          height: 72,
                          child: imageUrl.isEmpty
                              ? Container(color: Colors.grey[850])
                              : CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Container(color: Colors.grey[850]),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HoverUnderline(
                              onTap: () => _openArtist(data, artist),
                              builder: (isHovering) => Text(
                                data?.name ?? artist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  decoration: isHovering
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data == null
                                  ? 'Loading artist info…'
                                  : '${_formatNumber(data.monthlyListeners)} monthly listeners',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (data != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Top tracks: ${data.topSongs.take(2).map((s) => s.title).join(' • ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ],
              ),
            );
          },
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

    NavigationHistory.instance.navigatorKey.currentState?.push(
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

class _LyricsPreviewCard extends StatelessWidget {
  const _LyricsPreviewCard();

  @override
  Widget build(BuildContext context) {
    final track =
        context.select<AudioPlayerProvider, GenericSong?>((p) => p.currentTrack);
    if (track == null) {
      return _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Lyrics preview',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Play a song to see lyrics',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Consumer<LyricsProvider>(
      builder: (context, lyricsProvider, child) {
        final state = lyricsProvider.getState(track, LyricsSyncMode.synced);
        if (!state.isLoading && state.lyrics == null && state.error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            lyricsProvider.ensureLyrics(track, LyricsSyncMode.synced);
          });
        }

        final lyrics = state.lyrics;

        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lyrics preview',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (state.isLoading && lyrics == null)
                const Text(
                  'Loading lyrics…',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                )
              else if (lyrics == null)
                const Text(
                  'No lyrics found',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                )
              else
                _LyricsPreviewLines(lyrics: lyrics, resetKey: track.id),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lyrics == null
                          ? ''
                          : 'Provided by ${lyrics.provider.label}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: lyrics == null ? null : () => _openLyrics(),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _openLyrics() {
    if (NavigationHistory.instance.currentRouteName == '/lyrics') {
      return;
    }
    NavigationHistory.instance.navigatorKey.currentState?.push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        settings: const RouteSettings(name: '/lyrics'),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LyricsView(),
      ),
    );
  }

}

class _QueuePreviewCard extends StatelessWidget {
  const _QueuePreviewCard();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerProvider, _QueuePreviewData>(
      selector: (context, player) => _QueuePreviewData(
        queueLength: player.queue.length,
        currentIndex: player.currentIndex,
        currentTrackId: player.currentTrack?.id,
      ),
      builder: (context, data, child) {
        final player = context.read<AudioPlayerProvider>();
        final queue = player.queue;
        final currentIndex = data.currentIndex;
        final upcoming = currentIndex + 1 < queue.length
            ? queue.sublist(currentIndex + 1)
            : <GenericSong>[];

        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Up next',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openQueue(),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('View all'),
                  ),
                ],
              ),
              if (upcoming.isEmpty)
                const Text(
                  'Queue is empty',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                )
              else
                Column(
                  children: upcoming.take(4).map((track) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          _TrackArtwork(
                            url: track.thumbnailUrl,
                            width: 36,
                            height: 36,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  track.artists.map((a) => a.name).join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openQueue() {
    if (NavigationHistory.instance.currentRouteName == '/queue') {
      return;
    }
    NavigationHistory.instance.navigatorKey.currentState?.push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        settings: const RouteSettings(name: '/queue'),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const QueueView(),
      ),
    );
  }
}

class _LyricsPreviewLines extends StatelessWidget {
  final LyricsResult lyrics;
  final String resetKey;

  const _LyricsPreviewLines({required this.lyrics, required this.resetKey});

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerProvider, int>(
      selector: (context, player) => player.position.inMilliseconds,
      builder: (context, positionMs, child) {
        final previewLines = _getPreviewLines(lyrics, positionMs);
        if (previewLines.isEmpty) {
          return const Text(
            'No lyrics found',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          );
        }

        return AnimatedLyricsPreviewList(
          lines: previewLines,
          resetKey: resetKey,
          maxLines: 2,
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }
}

List<LyricsLine> _getPreviewLines(LyricsResult lyrics, int positionMs) {
  if (lyrics.lines.isEmpty) return const [];
  if (!lyrics.synced) {
    return lyrics.lines.take(3).toList();
  }
  final currentIndex = _findCurrentLineIndex(lyrics.lines, positionMs);
  return lyrics.lines.skip(currentIndex).take(3).toList();
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

class _NowPlayingData {
  final GenericSong? track;
  final String? playbackContextName;

  const _NowPlayingData({required this.track, required this.playbackContextName});

  @override
  bool operator ==(Object other) =>
      other is _NowPlayingData &&
      other.track?.id == track?.id &&
      other.playbackContextName == playbackContextName;

  @override
  int get hashCode => Object.hash(track?.id, playbackContextName);
}

class _QueuePreviewData {
  final int queueLength;
  final int currentIndex;
  final String? currentTrackId;

  const _QueuePreviewData({
    required this.queueLength,
    required this.currentIndex,
    required this.currentTrackId,
  });

  @override
  bool operator ==(Object other) =>
      other is _QueuePreviewData &&
      other.queueLength == queueLength &&
      other.currentIndex == currentIndex &&
      other.currentTrackId == currentTrackId;

  @override
  int get hashCode => Object.hash(queueLength, currentIndex, currentTrackId);
}
