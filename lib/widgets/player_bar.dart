/// Player bar widget with playback controls
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/audio/player.dart';
import '../providers/library/library_state.dart';
import '../models/metadata_models.dart';
import 'full_player.dart';
import '../views/lyrics.dart';
import '../views/queue.dart';
import '../views/list_detail.dart';
import '../views/artist_detail.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/library_item_context_menu.dart';
import '../widgets/hover_underline.dart';
import '../providers/navigation_state.dart';
import '../services/navigation_history.dart';

class WispPlayerBar extends StatelessWidget {
  const WispPlayerBar({super.key});

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerProvider>(
      builder: (context, player, child) {
        final currentTrack = player.currentTrack;

        if (_isMobile) {
          return _MobilePlayerBarAnimated(
            player: player,
            currentTrack: currentTrack,
          );
        }

        return _buildDesktopPlayerBar(context, player, currentTrack);
      },
    );
  }
}

class _MobilePlayerBarAnimated extends StatefulWidget {
  final AudioPlayerProvider player;
  final dynamic currentTrack;

  const _MobilePlayerBarAnimated({
    required this.player,
    required this.currentTrack,
  });

  @override
  State<_MobilePlayerBarAnimated> createState() =>
      _MobilePlayerBarAnimatedState();
}

class _MobilePlayerBarAnimatedState extends State<_MobilePlayerBarAnimated> {
  double _dragOffset = 0.0;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta ?? 0;
      _dragOffset = _dragOffset.clamp(-100.0, 100.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    if (velocity.abs() > 200 || _dragOffset.abs() > 50) {
      if (_dragOffset < 0 || velocity < -200) {
        // Swipe left -> skip next
        widget.player.skipNext();
      } else {
        // Swipe right -> skip previous
        widget.player.skipPrevious();
      }
    }

    setState(() {
      _dragOffset = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final offset = Offset(_dragOffset / 300, 0);

    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: InkWell(
        onTap: () => FullScreenPlayer.show(context),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            border: Border(top: BorderSide(color: Colors.grey[900]!, width: 1)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    // Album art
                    _buildMobileAlbumArt(widget.currentTrack),
                    const SizedBox(width: 12),
                    // Track info with animation
                    Expanded(
                      child: AnimatedSlide(
                        offset: offset,
                        duration: Duration.zero,
                        child: Opacity(
                          opacity: (1.0 - (_dragOffset.abs() / 100)).clamp(
                            0.3,
                            1.0,
                          ),
                          child: _buildMobileTrackInfo(widget.currentTrack),
                        ),
                      ),
                    ),
                    // Play/Pause button
                    _buildMobilePlayPauseButton(widget.player),
                  ],
                ),
              ),
              _buildMiniProgressBar(widget.player),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileAlbumArt(dynamic currentTrack) {
    final imageUrl = currentTrack?.thumbnailUrl ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 52,
        height: 52,
        color: Colors.grey[900],
        child: imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Colors.grey[800]),
                errorWidget: (context, url, error) =>
                    Icon(Icons.music_note, color: Colors.grey[700]),
              )
            : Icon(Icons.music_note, color: Colors.grey[700]),
      ),
    );
  }

  Widget _buildMobileTrackInfo(dynamic currentTrack) {
    if (currentTrack == null) {
      return Text(
        'No track playing',
        style: TextStyle(color: Colors.grey[600], fontSize: 14),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MarqueeText(
          text: currentTrack.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        _MarqueeText(
          text: currentTrack.artists.map((a) => a.name).join(', '),
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMobilePlayPauseButton(AudioPlayerProvider player) {
    if (player.isLoading || player.isBuffering) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(
        player.isPlaying ? Icons.pause : Icons.play_arrow,
        size: 40,
        color: Colors.white,
      ),
      onPressed: player.isPlaying ? player.pause : player.play,
    );
  }

  Widget _buildMiniProgressBar(AudioPlayerProvider player) {
    if (player.currentTrack == null) {
      return const SizedBox.shrink();
    }

    final progress = player.duration.inMilliseconds > 0
        ? player.position.inMilliseconds / player.duration.inMilliseconds
        : 0.0;

    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        backgroundColor: Colors.grey[850],
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
      ),
    );
  }
}

extension on WispPlayerBar {
  Widget _buildDesktopPlayerBar(
    BuildContext context,
    AudioPlayerProvider player,
    dynamic currentTrack,
  ) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        border: Border(top: BorderSide(color: Colors.grey[900]!, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            // Left: Album art + track info
            _buildTrackInfo(context, currentTrack),

            const SizedBox(width: 24),

            // Center: Playback controls + progress
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPlaybackControls(context, player),
                  _buildProgressBar(player),
                ],
              ),
            ),

            const SizedBox(width: 24),

            // Right: Volume + queue
            _buildRightControls(context, player, currentTrack),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(AudioPlayerProvider player) {
    final position = player.position;
    final duration = player.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 8.0),
          child: SizedBox(
            width: 64,
            child: Text(
              _formatDuration(position),
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Color(0xFF1DB954),
              inactiveTrackColor: Colors.grey[800],
              thumbColor: Colors.white,
              overlayColor: Color(0xFF1DB954).withOpacity(0.2),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (value) {
                final newPosition = Duration(
                  milliseconds: (value * duration.inMilliseconds).toInt(),
                );
                player.seek(newPosition);
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8.0, right: 16.0),
          child: SizedBox(
            width: 64,
            child: Text(
              _formatDuration(duration),
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              textAlign: TextAlign.left,
            ),
          ),
        ),
      ],
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

  Widget _buildTrackInfo(BuildContext context, dynamic currentTrack) {
    final libraryState = context.read<LibraryState>();
    final navState = context.read<NavigationState>();
    final currentLibraryView = navState.selectedLibraryView;
    final currentNavIndex = navState.selectedNavIndex;
    final track = currentTrack is GenericSong ? currentTrack : null;
    final album = track?.album;
    final artists = track?.artists ?? <GenericSimpleArtist>[];
    final primaryArtist = artists.isNotEmpty ? artists.first : null;
    if (currentTrack == null) {
      return SizedBox(
        width: 200,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.music_note, color: Colors.grey[700]),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No track playing',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          // Album art
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 48,
              height: 48,
              color: Colors.grey[900],
              child: currentTrack.thumbnailUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: currentTrack.thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: Colors.grey[800]),
                      errorWidget: (context, url, error) =>
                          Icon(Icons.music_note, color: Colors.grey[700]),
                    )
                  : Icon(Icons.music_note, color: Colors.grey[700]),
            ),
          ),
          SizedBox(width: 12),
          // Track info
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                (track != null)
                    ? HoverUnderline(
                        cursor: album != null && album.id.isNotEmpty
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        onTap: album != null && album.id.isNotEmpty
                            ? () {
                                Navigator.push(
                                  context,
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
                                        initialLibraryView: currentLibraryView,
                                        initialNavIndex: currentNavIndex,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        onSecondaryTapDown: (details) {
                          TrackContextMenu.show(
                            context: context,
                            track: track,
                            position: details.globalPosition,
                            playlists: libraryState.playlists,
                            albums: libraryState.albums,
                            artists: libraryState.artists,
                            currentLibraryView: currentLibraryView,
                            currentNavIndex: currentNavIndex,
                          );
                        },
                        builder: (isHovering) => _MarqueeText(
                          text: track.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            decoration: isHovering && album != null
                                ? TextDecoration.underline
                                : TextDecoration.none,
                          ),
                        ),
                      )
                    : _MarqueeText(
                        text: currentTrack.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                SizedBox(height: 2),
                (primaryArtist != null)
                    ? HoverUnderline(
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              transitionDuration: Duration.zero,
                              reverseTransitionDuration: Duration.zero,
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                  ArtistDetailView(
                                artistId: primaryArtist.id,
                                initialArtist: primaryArtist,
                                playlists: libraryState.playlists,
                                albums: libraryState.albums,
                                artists: libraryState.artists,
                                initialLibraryView: currentLibraryView,
                                initialNavIndex: currentNavIndex,
                              ),
                            ),
                          );
                        },
                        onSecondaryTapDown: (details) {
                          LibraryItemContextMenu.show(
                            context: context,
                            item: primaryArtist,
                            position: details.globalPosition,
                            playlists: libraryState.playlists,
                            albums: libraryState.albums,
                            artists: libraryState.artists,
                            currentLibraryView: currentLibraryView,
                            currentNavIndex: currentNavIndex,
                          );
                        },
                        builder: (isHovering) => _MarqueeText(
                          text: artists.map((a) => a.name).join(', '),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                            decoration: isHovering
                                ? TextDecoration.underline
                                : TextDecoration.none,
                          ),
                        ),
                      )
                    : _MarqueeText(
                        text: currentTrack.artists.map((a) => a.name).join(', '),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackControls(
    BuildContext context,
    AudioPlayerProvider player,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Shuffle
        IconButton(
          padding: EdgeInsets.all(4),
          constraints: BoxConstraints(),
          icon: Icon(
            Icons.shuffle,
            color: player.shuffleEnabled ? Color(0xFF1DB954) : Colors.grey[400],
            size: 20,
          ),
          onPressed: player.toggleShuffle,
        ),

        SizedBox(width: 4),

        // Previous
        IconButton(
          padding: EdgeInsets.all(4),
          constraints: BoxConstraints(),
          icon: Icon(Icons.skip_previous, color: Colors.white, size: 28),
          onPressed: player.queue.isEmpty ? null : player.skipPrevious,
        ),

        SizedBox(width: 4),

        // Play/Pause
        _buildPlayPauseButton(context, player),

        SizedBox(width: 4),

        // Next
        IconButton(
          padding: EdgeInsets.all(4),
          constraints: BoxConstraints(),
          icon: Icon(Icons.skip_next, color: Colors.white, size: 28),
          onPressed: player.queue.isEmpty ? null : player.skipNext,
        ),

        SizedBox(width: 4),

        // Repeat
        IconButton(
          padding: EdgeInsets.all(4),
          constraints: BoxConstraints(),
          icon: Icon(
            player.repeatMode == RepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            color: player.repeatMode != RepeatMode.off
                ? Color(0xFF1DB954)
                : Colors.grey[400],
            size: 20,
          ),
          onPressed: player.toggleRepeat,
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton(
    BuildContext context,
    AudioPlayerProvider player,
  ) {
    IconData icon;
    VoidCallback? onPressed;

    if (player.isLoading || player.isBuffering) {
      return SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
        ),
      );
    }

    if (player.isPlaying) {
      icon = Icons.pause_circle_filled;
      onPressed = player.pause;
    } else {
      icon = Icons.play_circle_filled;
      onPressed = player.currentTrack != null
          ? player.play
          : (player.queue.isNotEmpty
                ? () => player.playTrack(player.queue.first)
                : null);
    }

    // Disable if offline and track not cached
    if (!player.isOnline &&
        player.currentTrack != null &&
        !player.isTrackCached(player.currentTrack!.id)) {
      return IconButton(
        padding: EdgeInsets.all(4),
        constraints: BoxConstraints(),
        icon: Icon(icon, color: Colors.grey[700], size: 40),
        onPressed: null,
      );
    }

    return IconButton(
      padding: EdgeInsets.all(4),
      constraints: BoxConstraints(),
      icon: Icon(icon, color: Color(0xFF1DB954), size: 40),
      onPressed: onPressed,
    );
  }

  Widget _buildRightControls(
    BuildContext context,
    AudioPlayerProvider player,
    dynamic currentTrack,
  ) {
    final navState = context.watch<NavigationState>();
    return ValueListenableBuilder<Route<dynamic>?>(
      valueListenable: NavigationHistory.instance.currentRoute,
      builder: (context, route, child) {
        final routeName = route?.settings.name;
        final isLyricsOpen = routeName == '/lyrics';
        final isQueueOpen = routeName == '/queue';
        final isSidebarOpen = navState.rightSidebarVisible;
        final activeColor = const Color(0xFF1DB954);
        final inactiveColor = Colors.grey[400];

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Right sidebar toggle
            IconButton(
              icon: Icon(
                Icons.view_sidebar_outlined,
                color: isSidebarOpen ? activeColor : inactiveColor,
                size: 20,
              ),
              onPressed: navState.toggleRightSidebar,
            ),

            SizedBox(width: 8),

            // Lyrics button
            IconButton(
              icon: Icon(
                Icons.lyrics,
                color: isLyricsOpen ? activeColor : inactiveColor,
                size: 20,
              ),
              onPressed: currentTrack == null
                  ? null
                  : () {
                      _openLyrics(context);
                    },
            ),

            SizedBox(width: 8),

            // Queue button
            IconButton(
              icon: Icon(
                Icons.queue_music,
                color: isQueueOpen ? activeColor : inactiveColor,
                size: 20,
              ),
              onPressed: () => _openQueue(context),
            ),

            SizedBox(width: 8),

            // Volume control
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: player.toggleMute,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      player.volume == 0
                          ? Icons.volume_off
                          : player.volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Color(0xFF1DB954),
                      inactiveTrackColor: Colors.grey[800],
                      thumbColor: Colors.white,
                      overlayColor: Color(0xFF1DB954).withOpacity(0.2),
                    ),
                    child: Slider(
                      value: player.volume,
                      onChanged: (value) => player.setVolume(value),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _openLyrics(BuildContext context) {
    final currentRoute = ModalRoute.of(context);
    if (currentRoute?.settings.name == '/lyrics') {
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

  void _openQueue(BuildContext context) {
    final currentRoute = ModalRoute.of(context);
    if (currentRoute?.settings.name == '/queue') {
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
