/// Player bar widget with playback controls
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../providers/theme/cover_art_palette_provider.dart';
import '../providers/library/library_state.dart';
import '../models/metadata_models.dart';
import 'full_player.dart';
import '../services/app_navigation.dart';
import '../views/list_detail.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/library_item_context_menu.dart';
import '../widgets/hover_underline.dart';
import '../providers/navigation_state.dart';
import '../services/navigation_history.dart';
import '../widgets/like_button.dart';
import '../services/app_focus_service.dart';
import '../providers/connect/connect_session_provider.dart';
import '../services/connect/connect_models.dart';

class WispPlayerBar extends StatelessWidget {
  const WispPlayerBar({super.key});

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final currentTrack = context
        .select<global_audio_player.WispAudioHandler, GenericSong?>(
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

  const _MobilePlayerBarAnimated({required this.currentTrack});

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
    final connect = context.read<ConnectSessionProvider>();

    if (velocity.abs() > 200 || _dragOffset.abs() > 50) {
      if (_dragOffset < 0 || velocity < -200) {
        // Swipe left -> skip next
        connect.requestSkipNext();
      } else {
        // Swipe right -> skip previous
        connect.requestSkipPrevious();
      }
    }

    setState(() {
      _dragOffset = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final offset = Offset(_dragOffset / 300, 0);
    final palette = context.select<CoverArtPaletteProvider, ColorScheme?>(
      (provider) => provider.palette,
    );

    const colorFallback = Color(0xFF1A1A1A);
    var bgColor = HSLColor.fromColor(
      palette?.primary ?? colorFallback,
    ).toColor();

    if (bgColor.computeLuminance() < 0.11) {
      bgColor = HSLColor.fromColor(
        palette?.onPrimary ?? colorFallback,
      ).withLightness(0.5).toColor();
    }

    var btnColor = HSLColor.fromColor(
      palette?.onPrimaryContainer ?? colorFallback,
    ).withLightness(0.7).withSaturation(1).toColor();

    final handoffMessage = context.select<ConnectSessionProvider, String?>(
      (connect) => _handoffStatusMessage(connect),
    );

    // Test Results:
    //  Nights - Frank Ocean
    //    Native - White-ish
    //    Flutter -
    //       onPrimary - White as hell
    //       primary - Dark Orange
    //       primaryContainer - Very Light Orange
    //       onPrimaryContainer - Darker Orange
    //       onSecondary - Pure White
    //       secondary - Dead Brown
    //       secondaryContainer - Very Light Orange (again)
    //       onSecondaryContainer - Pretty Brown
    //  Airplane Mode - Limbo
    //    Native - Blue
    //    Flutter -
    //       onPrimary - White as hell
    //       primary - Dark Blue (pretty close to native)
    //       primaryContainer - Baby Blue
    //       onPrimaryContainer - Same as primary
    //       onSecondary - Pure White
    //       secondary - Grey
    //       secondaryContainer - Light Grey (blueish)
    //       onSecondaryContainer - Dead Cyan

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            child: InkWell(
              onTap: () => FullScreenPlayer.show(context),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border.all(
                    color: Colors.grey[900]!,
                    width: 1,
                  ).add(Border(bottom: BorderSide())),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(8),
                    bottom: Radius.zero,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
                      child: Row(
                        children: [
                          _buildMobileAlbumArt(widget.currentTrack),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ClipRect(
                              clipBehavior: Clip.hardEdge,
                              child: AnimatedSlide(
                                offset: offset,
                                duration: Duration.zero,
                                child: Opacity(
                                  opacity: (1.0 - (_dragOffset.abs() / 100))
                                      .clamp(0.3, 1.0),
                                  child: _buildMobileTrackInfo(
                                    widget.currentTrack,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _buildMobileConnectButton(),
                          LikeButton(
                            track: widget.currentTrack as GenericSong?,
                            iconSize: 24,
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            color: btnColor,
                          ),
                          _buildMobilePlayPauseButton(),
                        ],
                      ),
                    ),
                    _buildMiniProgressBar(),
                  ],
                ),
              ),
            ),
          ),
          if (handoffMessage != null)
            Positioned(
              top: -24,
              left: 0,
              right: 0,
              child: Center(
                child: _HandoffStatusIndicator(
                  message: handoffMessage,
                  backgroundColor: btnColor,
                  mobile: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileAlbumArt(dynamic currentTrack) {
    final imageUrl = currentTrack?.thumbnailUrl ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 44,
        height: 44,
        color: Colors.grey[900],
        child: imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                filterQuality: FilterQuality.high,
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
            fontWeight: FontWeight.bold,
          ),
        ),
        _MarqueeText(
          text: currentTrack.artists.map((a) => a.name).join(', '),
          style: TextStyle(
            color: Colors.grey[250],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileConnectButton() {
    return _ConnectMenuButton(
      iconSize: 24,
      inactiveColor: Colors.grey[300],
      activeColorOverride: Colors.white,
    );
  }

  Widget _buildMobilePlayPauseButton() {
    return Selector<global_audio_player.WispAudioHandler, _PlayPauseData>(
      selector: (context, player) {
        final track = player.currentTrack;
        final queueFirst = player.queueTracks.isNotEmpty
            ? player.queueTracks.first
            : null;
        return _PlayPauseData(
          isPlaying: player.isPlaying,
          isLoading: player.isLoading,
          isBuffering: player.isBuffering,
          isOnline: player.isOnline,
          currentTrackId: track?.id,
          currentTrackCached: track == null
              ? true
              : player.isTrackCached(track.id),
          queueNotEmpty: player.queueTracks.isNotEmpty,
          queueFirstId: queueFirst?.id,
        );
      },
      builder: (context, data, child) {
        final connect = context.watch<ConnectSessionProvider>();
        final useHandoffState = connect.isLinked && connect.isHost;
        final effectiveIsPlaying = useHandoffState
            ? connect.linkedIsPlaying
            : data.isPlaying;
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

        final isOfflineBlocked =
            !useHandoffState &&
            !data.isOnline &&
            data.currentTrackId != null &&
            !data.currentTrackCached;
        final IconData icon = effectiveIsPlaying
            ? Icons.pause
            : Icons.play_arrow;
        VoidCallback? onPressed;
        if (!isOfflineBlocked) {
          if (effectiveIsPlaying) {
            onPressed = () {
              connect.requestPause();
            };
          } else if (data.currentTrackId != null) {
            onPressed = () {
              connect.requestPlay();
            };
          } else if (data.queueNotEmpty) {
            onPressed = () {
              connect.requestPlay();
            };
          }
        }

        return IconButton(
          icon: Icon(icon, size: 28, color: Colors.white),
          onPressed: onPressed,
        );
      },
    );
  }

  Widget _buildMiniProgressBar() {
    // Use a Selector to read the current track id (safe inside builder)
    return Selector<global_audio_player.WispAudioHandler, String?>(
      selector: (context, player) => player.currentTrack?.id,
      builder: (context, trackId, child) {
        if (trackId == null) return const SizedBox.shrink();

        final connect = context.watch<ConnectSessionProvider>();
        final useHandoffState = connect.isLinked && connect.isHost;

        return Selector<global_audio_player.WispAudioHandler, _PositionData>(
          selector: (context, player) => _PositionData(
            position: useHandoffState
                ? connect.linkedPosition
                : player.throttledPosition,
            duration: player.duration,
            isLoading:
                !useHandoffState && (player.isLoading || player.isBuffering),
          ),
          builder: (context, data, child) {
            if (data.isLoading) {
              return const SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              );
            }

            final progress = data.duration.inMilliseconds > 0
                ? data.position.inMilliseconds / data.duration.inMilliseconds
                : 0.0;

            return TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 200),
              builder: (context, animatedProgress, child) {
                return SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    value: animatedProgress,
                    backgroundColor: Colors.grey[850]?.withOpacity(0.4),
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                );
              },
            );
          },
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
    final palette = context.select<CoverArtPaletteProvider, ColorScheme?>(
      (provider) => provider.palette,
    );
    var buttonColor = HSLColor.fromColor(
      palette?.onSecondaryContainer ?? const Color(0xFF1A1A1A),
    ).withLightness(0.6).withSaturation(0.65).toColor();

    if (buttonColor.computeLuminance() > 0.5) {
      buttonColor = buttonColor.withOpacity(0.65);
    }

    final handoffMessage = context.select<ConnectSessionProvider, String?>(
      (connect) => _handoffStatusMessage(connect),
    );

    return SizedBox(
      height: 90,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 90,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border(
                top: BorderSide(color: Colors.grey[900]!, width: 1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: _DesktopTrackInfo(
                          currentTrack: currentTrack,
                          btnColor: buttonColor,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _DesktopPlaybackControls(btnColor: buttonColor),
                            _DesktopProgressBar(btnColor: buttonColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: _DesktopRightControls(
                          currentTrack: currentTrack,
                          btnColor: buttonColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (handoffMessage != null)
            Positioned(
              top: -26,
              right: 16,
              child: _HandoffStatusIndicator(
                message: handoffMessage,
                backgroundColor: HSLColor.fromColor(
                  buttonColor,
                ).withLightness(0.4).toColor(),
              ),
            ),
        ],
      ),
    );
  }
}

class _HandoffStatusIndicator extends StatelessWidget {
  final String message;
  final Color backgroundColor;
  final bool mobile;

  const _HandoffStatusIndicator({
    required this.message,
    required this.backgroundColor,
    this.mobile = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 8 : 10,
          vertical: mobile ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: backgroundColor.withValues(alpha: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cast_connected, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              message,
              style: TextStyle(
                color: Colors.white,
                fontSize: mobile ? 10 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopProgressBar extends StatelessWidget {
  final Color? btnColor;

  const _DesktopProgressBar({this.btnColor});

  @override
  Widget build(BuildContext context) {
    return Selector<global_audio_player.WispAudioHandler, _PositionData>(
      selector: (context, player) => _PositionData(
        position: player.throttledPosition,
        duration: player.duration,
        isLoading: player.isLoading || player.isBuffering,
      ),
      builder: (context, data, child) {
        if (data.isLoading) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: const SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          );
        }

        final duration = data.duration;
        final progress = duration.inMilliseconds > 0
            ? data.position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 200),
          builder: (context, animatedProgress, child) {
            final animatedPosition = Duration(
              milliseconds: (animatedProgress * duration.inMilliseconds)
                  .round(),
            );

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: SizedBox(
                        width: 56,
                        child: Text(
                          _formatDuration(animatedPosition),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                          activeTrackColor:
                              btnColor ?? Theme.of(context).colorScheme.primary,
                          inactiveTrackColor: Colors.grey[800],
                          thumbColor: Colors.white,
                          overlayColor:
                              (btnColor ??
                                      Theme.of(context).colorScheme.primary)
                                  .withOpacity(0.2),
                        ),
                        child: Slider(
                          value: animatedProgress,
                          onChanged: (value) {
                            final newPosition = Duration(
                              milliseconds: (value * duration.inMilliseconds)
                                  .toInt(),
                            );
                            context.read<ConnectSessionProvider>().requestSeek(
                              newPosition,
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: SizedBox(
                        width: 56,
                        child: Text(
                          _formatDuration(duration),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
  final Color? btnColor;

  const _DesktopTrackInfo({required this.currentTrack, this.btnColor});

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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 56,
            height: 56,
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
        Flexible(
          fit: FlexFit.loose,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
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
                                AppNavigation.instance.openSharedList(
                                  context,
                                  id: album.id,
                                  type: SharedListType.album,
                                  initialTitle: album.title,
                                  initialThumbnailUrl: album.thumbnailUrl,
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
                          AppNavigation.instance.openArtist(
                            context,
                            artistId: primaryArtist.id,
                            initialArtist: primaryArtist,
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
        ),
        const SizedBox(width: 8),
        LikeButton(
          track: currentTrack,
          iconSize: 18,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          color: btnColor ?? Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }
}

class DesktopNextUpPreviewOverlay extends StatelessWidget {
  const DesktopNextUpPreviewOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final nextUp = context
        .select<global_audio_player.WispAudioHandler, GenericSong?>((player) {
          final index = player.currentIndex;
          final queue = player.queueTracks;
          if (index >= 0 && index + 1 < queue.length) {
            return queue[index + 1];
          }
          return null;
        });

    if (nextUp == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'NEXT UP',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 32,
                    height: 32,
                    color: Colors.grey[900],
                    child: nextUp.thumbnailUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: nextUp.thumbnailUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: Colors.grey[800]),
                            errorWidget: (context, url, error) => Icon(
                              Icons.music_note,
                              color: Colors.grey[700],
                              size: 16,
                            ),
                          )
                        : Icon(
                            Icons.music_note,
                            color: Colors.grey[700],
                            size: 16,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nextUp.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      nextUp.artists.map((a) => a.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        /* Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 32,
                height: 32,
                color: Colors.grey[900],
                child: nextUp.thumbnailUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: nextUp.thumbnailUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey[800]),
                        errorWidget: (context, url, error) =>
                            Icon(Icons.music_note, color: Colors.grey[700], size: 16),
                      )
                    : Icon(Icons.music_note, color: Colors.grey[700], size: 16),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 190,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Next up',
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nextUp.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    nextUp.artists.map((a) => a.name).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ), */
      ),
    );
  }
}

class _DesktopPlaybackControls extends StatelessWidget {
  final Color? btnColor;

  const _DesktopPlaybackControls({this.btnColor});

  @override
  Widget build(BuildContext context) {
    return Selector<global_audio_player.WispAudioHandler, _PlayPauseData>(
      selector: (context, player) {
        final track = player.currentTrack;
        final queueFirst = player.queueTracks.isNotEmpty
            ? player.queueTracks.first
            : null;
        return _PlayPauseData(
          isPlaying: player.isPlaying,
          isLoading: player.isLoading,
          isBuffering: player.isBuffering,
          isOnline: player.isOnline,
          currentTrackId: track?.id,
          currentTrackCached: track == null
              ? true
              : player.isTrackCached(track.id),
          queueNotEmpty: player.queueTracks.isNotEmpty,
          queueFirstId: queueFirst?.id,
          shuffleEnabled: player.shuffleEnabled,
          repeatMode: player.repeatMode,
        );
      },
      builder: (context, data, child) {
        final connect = context.watch<ConnectSessionProvider>();
        final useHandoffState = connect.isLinked && connect.isHost;
        final effectiveIsPlaying = useHandoffState
            ? connect.linkedIsPlaying
            : data.isPlaying;
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
                color: data.shuffleEnabled ? btnColor : Colors.grey[400],
                size: 20,
              ),
              onPressed: () {
                connect.requestToggleShuffle();
              },
            ),

            SizedBox(width: 4),

            // Previous
            IconButton(
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(),
              icon: Icon(Icons.skip_previous, color: Colors.white, size: 28),
              onPressed: data.queueNotEmpty
                  ? () {
                      connect.requestSkipPrevious();
                    }
                  : null,
            ),

            SizedBox(width: 4),

            // Play/Pause
            _DesktopPlayPauseButton(data: data, btnColor: btnColor),

            SizedBox(width: 4),

            // Next
            IconButton(
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(),
              icon: Icon(Icons.skip_next, color: Colors.white, size: 28),
              onPressed: data.queueNotEmpty
                  ? () {
                      connect.requestSkipNext();
                    }
                  : null,
            ),

            SizedBox(width: 4),

            // Repeat
            IconButton(
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(),
              icon: Icon(
                data.repeatMode == global_audio_player.RepeatMode.one
                    ? Icons.repeat_one
                    : Icons.repeat,
                color: data.repeatMode != global_audio_player.RepeatMode.off
                    ? btnColor
                    : Colors.grey[400],
                size: 20,
              ),
              onPressed: () {
                connect.requestToggleRepeat();
              },
            ),
          ],
        );
      },
    );
  }
}

class _DesktopPlayPauseButton extends StatelessWidget {
  final _PlayPauseData data;
  final Color? btnColor;

  const _DesktopPlayPauseButton({required this.data, this.btnColor});

  @override
  Widget build(BuildContext context) {
    final connect = context.watch<ConnectSessionProvider>();
    final useHandoffState = connect.isLinked && connect.isHost;
    final effectiveIsPlaying = useHandoffState
        ? connect.linkedIsPlaying
        : data.isPlaying;

    if (data.isLoading || data.isBuffering) {
      return Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              btnColor ?? Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final isOfflineBlocked =
        !useHandoffState &&
        !data.isOnline &&
        data.currentTrackId != null &&
        !data.currentTrackCached;
    IconData icon = effectiveIsPlaying
        ? Icons.pause_circle_filled
        : Icons.play_circle_filled;
    VoidCallback? onPressed;

    if (!isOfflineBlocked) {
      if (effectiveIsPlaying) {
        onPressed = () {
          connect.requestPause();
        };
      } else if (data.currentTrackId != null) {
        onPressed = () {
          connect.requestPlay();
        };
      } else if (data.queueNotEmpty) {
        onPressed = () {
          connect.requestPlay();
        };
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
      icon: Icon(
        icon,
        color: btnColor ?? Theme.of(context).colorScheme.primary,
        size: 40,
      ),
      onPressed: onPressed,
    );
  }
}

class _DesktopRightControls extends StatelessWidget {
  final GenericSong? currentTrack;
  final Color? btnColor;

  const _DesktopRightControls({required this.currentTrack, this.btnColor});

  @override
  Widget build(BuildContext context) {
    final navState = context.watch<NavigationState>();
    return ValueListenableBuilder<Route<dynamic>?>(
      valueListenable: NavigationHistory.instance.currentRoute,
      builder: (context, route, child) {
        final routeName = route?.settings.name;
        final isLyricsOpen = routeName == '/lyrics';
        final isQueueOpen = routeName == '/queue';
        final isFullScreenOpen = routeName == '/fullplayer';
        final isSidebarOpen = navState.rightSidebarVisible;
        final activeColor = btnColor ?? Theme.of(context).colorScheme.primary;
        final inactiveColor = Colors.grey[400];

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showLyricsButton = width >= 230;
            final showQueueButton = width >= 280;
            final showVolumeSlider = width >= 390;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.view_sidebar_outlined,
                    color: isSidebarOpen ? activeColor : inactiveColor,
                    size: 20,
                  ),
                  onPressed: navState.toggleRightSidebar,
                ),
                const SizedBox(width: 8),
                if (showLyricsButton) ...[
                  IconButton(
                    icon: Icon(
                      Icons.music_note,
                      color: isLyricsOpen ? activeColor : inactiveColor,
                      size: 20,
                    ),
                    onPressed: currentTrack == null
                        ? null
                        : () {
                            final currentScreen = NavigationHistory
                                .instance
                                .currentRoute
                                .value
                                ?.settings
                                .name;
                            if (currentScreen == '/lyrics') {
                              NavigationHistory.instance.goBack();
                            } else {
                              _openLyrics(context);
                            }
                          },
                  ),
                  const SizedBox(width: 8),
                ],
                if (showQueueButton) ...[
                  IconButton(
                    icon: Icon(
                      Icons.queue_music,
                      color: isQueueOpen ? activeColor : inactiveColor,
                      size: 20,
                    ),
                    onPressed: () {
                      final currentScreen = NavigationHistory
                          .instance
                          .currentRoute
                          .value
                          ?.settings
                          .name;
                      if (currentScreen == '/queue') {
                        NavigationHistory.instance.goBack();
                      } else {
                        _openQueue(context);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                _ConnectMenuButton(
                  iconSize: 20,
                  inactiveColor: inactiveColor,
                  activeColorOverride: activeColor,
                ),
                const SizedBox(width: 8),
                Selector<global_audio_player.WispAudioHandler, double>(
                  selector: (context, player) => player.volume,
                  builder: (context, volume, child) {
                    final player = context
                        .read<global_audio_player.WispAudioHandler>();
                    if (!showVolumeSlider) {
                      return _VolumePopupButton(
                        inactiveColor: inactiveColor,
                        accentColor: activeColor,
                      );
                    }

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          tooltip: volume == 0 ? 'Unmute' : 'Mute',
                          onPressed: player.toggleMute,
                          icon: Icon(
                            volume == 0
                                ? Icons.volume_off
                                : volume < 0.5
                                ? Icons.volume_down
                                : Icons.volume_up,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 100,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor:
                                  btnColor ??
                                  Theme.of(context).colorScheme.primary,
                              inactiveTrackColor: Colors.grey[800],
                              thumbColor: Colors.white,
                              overlayColor: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.2),
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
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.fullscreen,
                    color: isFullScreenOpen ? activeColor : inactiveColor,
                    size: 20,
                  ),
                  onPressed: () async {
                    final currentScreen = NavigationHistory
                        .instance
                        .currentRoute
                        .value
                        ?.settings
                        .name;
                    if (currentScreen == '/fullplayer') {
                      await AppNavigation.instance.closeFullPlayer();
                    } else {
                      await _openFullPlayer(context);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

Future<void> _openFullPlayer(BuildContext context) async {
  final currentRoute = ModalRoute.of(context);
  if (currentRoute?.settings.name == '/fullplayer') {
    return;
  }
  await AppNavigation.instance.openFullPlayer();
}

void _openLyrics(BuildContext context) {
  final currentRoute = ModalRoute.of(context);
  if (currentRoute?.settings.name == '/lyrics') {
    return;
  }
  AppNavigation.instance.openLyrics();
}

void _openQueue(BuildContext context) {
  final currentRoute = ModalRoute.of(context);
  if (currentRoute?.settings.name == '/queue') {
    return;
  }
  AppNavigation.instance.openQueue();
}

Future<void> _openConnectMenuWithAccent(
  BuildContext context,
  Color? accentColor,
) async {
  final connect = context.read<ConnectSessionProvider>();
  connect.startDiscovery();

  final isMobile = Platform.isAndroid || Platform.isIOS;

  if (isMobile) {
    final themePrimary = accentColor ?? Theme.of(context).colorScheme.primary;
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
              border: Border.all(
                color: themePrimary.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: _ConnectPanelContent(
              accentColor: themePrimary,
              onClose: () => Navigator.of(sheetContext).pop(),
              isMobileSheet: true,
            ),
          ),
        );
      },
    );
    return;
  }

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final button = context.findRenderObject() as RenderBox;
  final buttonRect = Rect.fromPoints(
    button.localToGlobal(Offset.zero, ancestor: overlay),
    button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    ),
  );

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _ConnectQuickPanel(
        anchorRect: buttonRect,
        overlaySize: overlay.size,
        accentColor: accentColor,
      );
    },
  );
}

class _ConnectQuickPanel extends StatelessWidget {
  final Rect anchorRect;
  final Size overlaySize;
  final Color? accentColor;

  const _ConnectQuickPanel({
    required this.anchorRect,
    required this.overlaySize,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final themePrimary = accentColor ?? Theme.of(context).colorScheme.primary;
    const panelWidth = 340.0;
    const panelHeight = 360.0;
    const margin = 8.0;

    final left = (anchorRect.center.dx - (panelWidth / 2)).clamp(
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
            borderRadius: BorderRadius.circular(14),
            elevation: 14,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: themePrimary.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: _ConnectPanelContent(
                accentColor: themePrimary,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectPanelContent extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onClose;
  final bool isMobileSheet;

  const _ConnectPanelContent({
    required this.accentColor,
    required this.onClose,
    this.isMobileSheet = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectSessionProvider>(
      builder: (context, connect, child) {
        final linkedLabel = _linkedDeviceLabel(connect);
        final pendingRequest = connect.pendingPairRequest;
        final devices = connect.discoveredDevices
            .where((device) => device.id != connect.localDeviceId)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Icon(Icons.cast_connected, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Text(
                    'Handoff',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobileSheet ? 18 : 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh Handoff devices',
                    splashRadius: 18,
                    onPressed: connect.refreshDiscovery,
                    icon: Icon(Icons.refresh, size: 18, color: accentColor),
                  ),
                ],
              ),
            ),
            if (linkedLabel != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF212121),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link, size: 16, color: accentColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          linkedLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: isMobileSheet ? 14 : null,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          connect.unlink(localResumed: true);
                          onClose();
                        },
                        child: const Text('Unlink'),
                      ),
                    ],
                  ),
                ),
              ),
            if (pendingRequest != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF212121),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pendingRequest.fromDeviceName} wants to pair via Handoff',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: isMobileSheet ? 14 : 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: connect.rejectIncomingPair,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.grey[700]!),
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
              padding: EdgeInsets.fromLTRB(
                12,
                linkedLabel != null ? 10 : 2,
                12,
                8,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF212121),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Next link mode:',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: isMobileSheet ? 13 : 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SegmentedButton<ConnectLinkMode>(
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? accentColor.withValues(alpha: 0.2)
                                    : Colors.transparent,
                              ),
                              foregroundColor: WidgetStateProperty.all<Color>(
                                Colors.white,
                              ),
                              side: WidgetStatePropertyAll(
                                BorderSide(color: Colors.grey[700]!),
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
                              final next = selection.first;
                              connect.setNextOutgoingLinkMode(next);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Checkbox(
                          value: connect.rememberModeForNextLink,
                          onChanged: (value) {
                            connect.setRememberModeForNextLink(value ?? false);
                          },
                        ),
                        Expanded(
                          child: Text(
                            'Remember for next session',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: isMobileSheet ? 12 : 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                linkedLabel != null ? 12 : 2,
                14,
                8,
              ),
              child: Text(
                'Available devices',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: isMobileSheet ? 14 : 12,
                  fontWeight: FontWeight.w600,
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
                          fontSize: isMobileSheet ? 14 : 13,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                                      mode: connect.nextOutgoingLinkMode,
                                      rememberForDevice:
                                          connect.rememberModeForNextLink,
                                    );
                                    onClose();
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
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: isMobileSheet ? 15 : null,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          device.platform,
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: isMobileSheet ? 13 : 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isLinkedDevice)
                                    Text(
                                      'Linked',
                                      style: TextStyle(
                                        color: accentColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: isMobileSheet ? 13 : 12,
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
    );
  }
}

class _ConnectMenuButton extends StatelessWidget {
  final double iconSize;
  final Color? inactiveColor;
  final Color? activeColorOverride;

  const _ConnectMenuButton({
    required this.iconSize,
    this.inactiveColor,
    this.activeColorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        activeColorOverride ?? Theme.of(context).colorScheme.primary;
    return Selector<ConnectSessionProvider, bool>(
      selector: (context, connect) => connect.isLinked,
      builder: (context, isLinked, child) {
        return IconButton(
          icon: Icon(
            Icons.cast_connected,
            color: isLinked ? activeColor : (inactiveColor ?? Colors.grey[400]),
            size: iconSize,
          ),
          tooltip: 'Handoff',
          onPressed: () => _openConnectMenuWithAccent(context, activeColor),
        );
      },
    );
  }
}

class _VolumePopupButton extends StatelessWidget {
  final Color? inactiveColor;
  final Color? accentColor;

  const _VolumePopupButton({this.inactiveColor, this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Selector<global_audio_player.WispAudioHandler, double>(
      selector: (context, player) => player.volume,
      builder: (context, volume, child) {
        return IconButton(
          mouseCursor: SystemMouseCursors.click,
          tooltip: 'Volume',
          onPressed: () => _openVolumeMenu(context, accentColor: accentColor),
          icon: Icon(
            volume == 0
                ? Icons.volume_off
                : volume < 0.5
                ? Icons.volume_down
                : Icons.volume_up,
            color: inactiveColor ?? Colors.grey[400],
            size: 20,
          ),
        );
      },
    );
  }
}

Future<void> _openVolumeMenu(BuildContext context, {Color? accentColor}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final button = context.findRenderObject() as RenderBox;
  final buttonRect = Rect.fromPoints(
    button.localToGlobal(Offset.zero, ancestor: overlay),
    button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    ),
  );

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _VolumeQuickPanel(
        anchorRect: buttonRect,
        overlaySize: overlay.size,
        accentColor: accentColor,
      );
    },
  );
}

class _VolumeQuickPanel extends StatelessWidget {
  final Rect anchorRect;
  final Size overlaySize;
  final Color? accentColor;

  const _VolumeQuickPanel({
    required this.anchorRect,
    required this.overlaySize,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final themePrimary = accentColor ?? Theme.of(context).colorScheme.primary;
    const panelWidth = 72.0;
    const panelHeight = 210.0;
    const margin = 8.0;

    final left = (anchorRect.center.dx - (panelWidth / 2)).clamp(
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
                border: Border.all(
                  color: themePrimary.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Selector<global_audio_player.WispAudioHandler, double>(
                  selector: (context, player) => player.volume,
                  builder: (context, volume, child) {
                    final player = context
                        .read<global_audio_player.WispAudioHandler>();
                    return Column(
                      children: [
                        Icon(
                          volume == 0
                              ? Icons.volume_off
                              : volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                          color: themePrimary,
                          size: 18,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                                activeTrackColor: themePrimary,
                                inactiveTrackColor: Colors.grey[800],
                                thumbColor: Colors.white,
                                overlayColor: themePrimary.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                              child: Slider(
                                min: 0,
                                max: 1,
                                value: volume,
                                label: '${(volume * 100).round()}%',
                                divisions: 100,
                                onChanged: (value) => player.setVolume(value),
                              ),
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

String? _linkedDeviceLabel(ConnectSessionProvider connect) {
  final linkedId = connect.linkedDeviceId;
  if (linkedId == null || linkedId.isEmpty) return null;

  for (final device in connect.discoveredDevices) {
    if (device.id == linkedId) {
      return device.name;
    }
  }

  if (linkedId.length > 10) {
    return 'Device ${linkedId.substring(0, 10)}';
  }

  return 'Device $linkedId';
}

String? _handoffStatusMessage(ConnectSessionProvider connect) {
  if (connect.phase == ConnectPhase.pairing && !connect.isLinked) {
    return 'Handoff | Waiting for approval...';
  }

  if (connect.isLinked) {
    final label = _linkedDeviceLabel(connect) ?? 'Device';
    if (connect.isTarget) {
      return 'Handoff | Controlling from $label';
    }
    return 'Handoff | Listening on: $label';
  }

  return null;
}

class _PositionData {
  final Duration position;
  final Duration duration;
  final bool isLoading;

  const _PositionData({
    required this.position,
    required this.duration,
    this.isLoading = false,
  });

  @override
  bool operator ==(Object other) =>
      other is _PositionData &&
      other.position.inMilliseconds == position.inMilliseconds &&
      other.duration.inMilliseconds == duration.inMilliseconds &&
      other.isLoading == isLoading;

  @override
  int get hashCode =>
      Object.hash(position.inMilliseconds, duration.inMilliseconds, isLoading);
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
  final global_audio_player.RepeatMode? repeatMode;

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
  late final AppFocusService _focusService;
  bool _isFocused = true;

  @override
  void initState() {
    super.initState();
    _focusService = AppFocusService.instance;
    _isFocused = _focusService.isFocused.value;
    _focusService.isFocused.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _configureController(forceStop: true);
    }
  }

  @override
  void dispose() {
    _focusService.isFocused.removeListener(_handleFocusChange);
    _pauseTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusService.isFocused.value;
    if (focused == _isFocused) return;
    _isFocused = focused;
    if (!_isFocused) {
      _pauseTimer?.cancel();
      _controller?.stop();
      return;
    }
    _configureController();
  }

  void _configureController({bool forceStop = false}) {
    if (!_needsMarquee || forceStop || !_isFocused) {
      _pauseTimer?.cancel();
      _controller?.stop();
      if (_controller != null) {
        _controller!.value = 0;
      }
    }
    if (!_needsMarquee || !_isFocused) return;

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
      if (!mounted || !_needsMarquee || !_isFocused) return;
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
