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
import '../widgets/like_button.dart';

class WispPlayerBar extends StatelessWidget {
  const WispPlayerBar({super.key});

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final currentTrack = context.select<AudioPlayerProvider, GenericSong?>(
      (player) => player.currentTrack,
    );

    if (_isMobile) {
      return _MobilePlayerBarAnimated(currentTrack: currentTrack);
    }

    return _DesktopPlayerBar(currentTrack: currentTrack);
  }
}

class _MobilePlayerBarAnimated extends StatefulWidget {
  final dynamic currentTrack;

  const _MobilePlayerBarAnimated({
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
    final player = context.read<AudioPlayerProvider>();

    if (velocity.abs() > 200 || _dragOffset.abs() > 50) {
      if (_dragOffset < 0 || velocity < -200) {
        // Swipe left -> skip next
        player.skipNext();
      } else {
        // Swipe right -> skip previous
        player.skipPrevious();
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
                    LikeButton(
                      track: widget.currentTrack as GenericSong?,
                      iconSize: 20,
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Play/Pause button
                    _buildMobilePlayPauseButton(),
                  ],
                ),
              ),
              _buildMiniProgressBar(),
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

  Widget _buildMobilePlayPauseButton() {
    return Selector<AudioPlayerProvider, _PlayPauseData>(
      selector: (context, player) {
        final track = player.currentTrack;
        final queueFirst = player.queue.isNotEmpty ? player.queue.first : null;
        return _PlayPauseData(
          isPlaying: player.isPlaying,
          isLoading: player.isLoading,
          isBuffering: player.isBuffering,
          isOnline: player.isOnline,
          currentTrackId: track?.id,
          currentTrackCached:
              track == null ? true : player.isTrackCached(track.id),
          queueNotEmpty: player.queue.isNotEmpty,
          queueFirstId: queueFirst?.id,
        );
      },
      builder: (context, data, child) {
        if (data.isLoading || data.isBuffering) {
          return const SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          );
        }

        final player = context.read<AudioPlayerProvider>();
        final isOfflineBlocked =
            !data.isOnline && data.currentTrackId != null && !data.currentTrackCached;
        final IconData icon =
            data.isPlaying ? Icons.pause : Icons.play_arrow;
        VoidCallback? onPressed;
        if (!isOfflineBlocked) {
          if (data.isPlaying) {
            onPressed = player.pause;
          } else if (data.currentTrackId != null) {
            onPressed = player.play;
          } else if (data.queueNotEmpty) {
            onPressed = () => player.playTrack(player.queue.first);
          }
        }

        return IconButton(
          icon: Icon(icon, size: 40, color: Colors.white),
          onPressed: onPressed,
        );
      },
    );
  }

  Widget _buildMiniProgressBar() {
    final trackId =
        context.select<AudioPlayerProvider, String?>((p) => p.currentTrack?.id);
    if (trackId == null) {
      return const SizedBox.shrink();
    }

    return Selector<AudioPlayerProvider, _PositionData>(
      selector: (context, player) => _PositionData(
        position: player.position,
        duration: player.duration,
      ),
      builder: (context, data, child) {
        final progress = data.duration.inMilliseconds > 0
            ? data.position.inMilliseconds / data.duration.inMilliseconds
            : 0.0;

        return SizedBox(
          height: 3,
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: Colors.grey[850],
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }
}

class _DesktopPlayerBar extends StatelessWidget {
  final GenericSong? currentTrack;

  const _DesktopPlayerBar({required this.currentTrack});

  @override
  Widget build(BuildContext context) {
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
            _DesktopTrackInfo(currentTrack: currentTrack),

            const SizedBox(width: 24),

            // Center: Playback controls + progress
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DesktopPlaybackControls(),
                  _DesktopProgressBar(),
                ],
              ),
            ),

            const SizedBox(width: 24),

            // Right: Volume + queue
            _DesktopRightControls(currentTrack: currentTrack),
          ],
        ),
      ),
    );
  }
}

class _DesktopProgressBar extends StatelessWidget {
  const _DesktopProgressBar();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerProvider, _PositionData>(
      selector: (context, player) => _PositionData(
        position: player.position,
        duration: player.duration,
      ),
      builder: (context, data, child) {
        final duration = data.duration;
        final position = data.position;
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
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                  inactiveTrackColor: Colors.grey[800],
                  thumbColor: Colors.white,
                  overlayColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.2),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: (value) {
                    final newPosition = Duration(
                      milliseconds:
                          (value * duration.inMilliseconds).toInt(),
                    );
                    context.read<AudioPlayerProvider>().seek(newPosition);
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
      },
    );
  }
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

class _DesktopTrackInfo extends StatelessWidget {
  final GenericSong? currentTrack;

  const _DesktopTrackInfo({required this.currentTrack});

  @override
  Widget build(BuildContext context) {
    final libraryState = context.read<LibraryState>();
    final navState = context.read<NavigationState>();
    final currentLibraryView = navState.selectedLibraryView;
    final currentNavIndex = navState.selectedNavIndex;
    final track = currentTrack;
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
              child: currentTrack!.thumbnailUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: currentTrack!.thumbnailUrl,
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
                                    pageBuilder:
                                        (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                        ) => SharedListDetailView(
                                          id: album.id,
                                          type: SharedListType.album,
                                          initialTitle: album.title,
                                          initialThumbnailUrl:
                                              album.thumbnailUrl,
                                          playlists: libraryState.playlists,
                                          albums: libraryState.albums,
                                          artists: libraryState.artists,
                                          initialLibraryView:
                                              currentLibraryView,
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
                        text: currentTrack!.title,
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
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
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
                        text: currentTrack!.artists
                            .map((a) => a.name)
                            .join(', '),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
              ],
            ),
          ),
              const SizedBox(width: 6),
              LikeButton(
                track: currentTrack,
                iconSize: 18,
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
              ),
        ],
      ),
    );
  }
}

class _DesktopPlaybackControls extends StatelessWidget {
  const _DesktopPlaybackControls();

  @override
  Widget build(BuildContext context) {
    return Selector<AudioPlayerProvider, _PlayPauseData>(
      selector: (context, player) {
        final track = player.currentTrack;
        final queueFirst = player.queue.isNotEmpty ? player.queue.first : null;
        return _PlayPauseData(
          isPlaying: player.isPlaying,
          isLoading: player.isLoading,
          isBuffering: player.isBuffering,
          isOnline: player.isOnline,
          currentTrackId: track?.id,
          currentTrackCached:
              track == null ? true : player.isTrackCached(track.id),
          queueNotEmpty: player.queue.isNotEmpty,
          queueFirstId: queueFirst?.id,
          shuffleEnabled: player.shuffleEnabled,
          repeatMode: player.repeatMode,
        );
      },
      builder: (context, data, child) {
        final player = context.read<AudioPlayerProvider>();
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
                color: data.shuffleEnabled
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[400],
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
              onPressed: data.queueNotEmpty ? player.skipPrevious : null,
            ),

            SizedBox(width: 4),

            // Play/Pause
            _DesktopPlayPauseButton(data: data),

            SizedBox(width: 4),

            // Next
            IconButton(
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(),
              icon: Icon(Icons.skip_next, color: Colors.white, size: 28),
              onPressed: data.queueNotEmpty ? player.skipNext : null,
            ),

            SizedBox(width: 4),

            // Repeat
            IconButton(
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(),
              icon: Icon(
                data.repeatMode == RepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
                color: data.repeatMode != RepeatMode.off
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[400],
                size: 20,
              ),
              onPressed: player.toggleRepeat,
            ),
          ],
        );
      },
    );
  }
}

class _DesktopPlayPauseButton extends StatelessWidget {
  final _PlayPauseData data;

  const _DesktopPlayPauseButton({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isLoading || data.isBuffering) {
      return SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    final player = context.read<AudioPlayerProvider>();
    final isOfflineBlocked =
        !data.isOnline && data.currentTrackId != null && !data.currentTrackCached;
    IconData icon = data.isPlaying
        ? Icons.pause_circle_filled
        : Icons.play_circle_filled;
    VoidCallback? onPressed;

    if (!isOfflineBlocked) {
      if (data.isPlaying) {
        onPressed = player.pause;
      } else if (data.currentTrackId != null) {
        onPressed = player.play;
      } else if (data.queueNotEmpty) {
        onPressed = () => player.playTrack(player.queue.first);
      }
    }

    if (isOfflineBlocked) {
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
      icon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 40),
      onPressed: onPressed,
    );
  }
}

class _DesktopRightControls extends StatelessWidget {
  final GenericSong? currentTrack;

  const _DesktopRightControls({required this.currentTrack});

  @override
  Widget build(BuildContext context) {
    final navState = context.watch<NavigationState>();
    return ValueListenableBuilder<Route<dynamic>?>(
      valueListenable: NavigationHistory.instance.currentRoute,
      builder: (context, route, child) {
        final routeName = route?.settings.name;
        final isLyricsOpen = routeName == '/lyrics';
        final isQueueOpen = routeName == '/queue';
        final isSidebarOpen = navState.rightSidebarVisible;
        final activeColor = Theme.of(context).colorScheme.primary;
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
            Selector<AudioPlayerProvider, double>(
              selector: (context, player) => player.volume,
              builder: (context, volume, child) {
                final player = context.read<AudioPlayerProvider>();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: player.toggleMute,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          volume == 0
                              ? Icons.volume_off
                              : volume < 0.5
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
                          thumbShape:
                              RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape:
                              RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor:
                              Theme.of(context).colorScheme.primary,
                          inactiveTrackColor: Colors.grey[800],
                          thumbColor: Colors.white,
                          overlayColor: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.2),
                        ),
                        child: Slider(
                          value: volume,
                          onChanged: (value) => player.setVolume(value),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
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

class _PositionData {
  final Duration position;
  final Duration duration;

  const _PositionData({required this.position, required this.duration});

  @override
  bool operator ==(Object other) =>
      other is _PositionData &&
      other.position.inMilliseconds == position.inMilliseconds &&
      other.duration.inMilliseconds == duration.inMilliseconds;

  @override
  int get hashCode => Object.hash(
    position.inMilliseconds,
    duration.inMilliseconds,
  );
}

class _PlayPauseData {
  final bool isPlaying;
  final bool isLoading;
  final bool isBuffering;
  final bool isOnline;
  final String? currentTrackId;
  final bool currentTrackCached;
  final bool queueNotEmpty;
  final String? queueFirstId;
  final bool shuffleEnabled;
  final RepeatMode? repeatMode;

  const _PlayPauseData({
    required this.isPlaying,
    required this.isLoading,
    required this.isBuffering,
    required this.isOnline,
    required this.currentTrackId,
    required this.currentTrackCached,
    required this.queueNotEmpty,
    required this.queueFirstId,
    this.shuffleEnabled = false,
    this.repeatMode,
  });

  @override
  bool operator ==(Object other) =>
      other is _PlayPauseData &&
      other.isPlaying == isPlaying &&
      other.isLoading == isLoading &&
      other.isBuffering == isBuffering &&
      other.isOnline == isOnline &&
      other.currentTrackId == currentTrackId &&
      other.currentTrackCached == currentTrackCached &&
      other.queueNotEmpty == queueNotEmpty &&
      other.queueFirstId == queueFirstId &&
      other.shuffleEnabled == shuffleEnabled &&
      other.repeatMode == repeatMode;

  @override
  int get hashCode => Object.hash(
    isPlaying,
    isLoading,
    isBuffering,
    isOnline,
    currentTrackId,
    currentTrackCached,
    queueNotEmpty,
    queueFirstId,
    shuffleEnabled,
    repeatMode,
  );
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
