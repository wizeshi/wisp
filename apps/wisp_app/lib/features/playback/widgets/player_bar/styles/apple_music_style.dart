// Copyright © 2026 wizeshi

part of '../../player_bar.dart';

/// True liquid glass surface (refracting [LiquidGlassLens]) used by the Apple
/// Music mobile player bar.
class _AppleGlassLens extends StatelessWidget {
  final double cornerRadius;
  final Widget child;

  const _AppleGlassLens({required this.cornerRadius, required this.child});

  @override
  Widget build(BuildContext context) {
    return LiquidGlassLens(
      style: LiquidGlassStyle(
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: cornerRadius,
        ),
        appearance: LiquidGlassAppearance(
          blur: const LiquidGlassBlur(sigmaX: 6, sigmaY: 6),
          color: Colors.black.withValues(alpha: 0.18),
        ),
        refraction: const LiquidGlassRefraction(
          distortion: 0.12,
          distortionWidth: 24,
        ),
      ),
      child: child,
    );
  }
}

/// Apple Music desktop player bar: opaque surface, white accents (primary color
/// is disregarded), top-margin scrubbing bar.
class _AppleMusicDesktopPlayerBar extends StatelessWidget {
  final GenericSong? currentTrack;

  const _AppleMusicDesktopPlayerBar({required this.currentTrack});

  @override
  Widget build(BuildContext context) {
    final handoffMessage = context.select<ConnectSessionProvider, String?>(
      (connect) => _handoffStatusMessage(connect),
    );

    final barContent = Container(
      height: 88,
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Stack(
        children: [
          // Top margin progress bar sits on the border between bar & content
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _PlayerBarTopProgressBar(accentColor: Colors.white),
          ),
          Padding(
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
                      padding: const EdgeInsets.only(right: 16),
                      child: _DesktopTrackInfo(
                        currentTrack: currentTrack,
                        appStyle: AppStyle.AppleMusic,
                      ),
                    ),
                  ),
                ),

                // Center playback controls: natural width, dead center
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: _AppleMusicDesktopPlaybackControls(),
                ),

                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: _DesktopRightControls(
                        currentTrack: currentTrack,
                        appStyle: AppStyle.AppleMusic,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          barContent,
          if (handoffMessage != null)
            Positioned(
              top: -32,
              right: 16,
              child: _HandoffStatusIndicator(
                message: handoffMessage,
                backgroundColor: Colors.grey[800]!,
              ),
            ),
        ],
      ),
    );
  }
}

/// Center playback controls for the Apple Music desktop player bar.
class _AppleMusicDesktopPlaybackControls extends StatelessWidget {
  const _AppleMusicDesktopPlaybackControls();

  static Widget _controlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required double size,
    bool active = false,
  }) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.white : Colors.transparent,
      ),
      child: GenericIconButton(
        style: AppStyle.AppleMusic,
        mouseCursor: onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        iconSize: size,
        icon: Icon(icon, color: active ? Colors.black : Colors.grey[400]),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

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
          isTransitioning: player.isTrackTransitioning,
          isOnline: player.isOnline,
          currentTrackId: track?.id,
          currentTrackCached: track == null
              ? true
              : player.isTrackCached(track.id),
          queueNotEmpty: player.queueTracks.isNotEmpty,
          queueFirstId: queueFirst?.id,
          shuffleEnabled: player.shuffleEnabled,
          repeatMode: player.repeatMode,
          isDJMode: player.isDJMode,
        );
      },
      builder: (context, data, child) {
        final coordinator = context.read<PlaybackCoordinator>();
        final repeatActive =
            data.repeatMode != global_audio_player.RepeatMode.off;
        final repeatIcon = data.repeatMode == global_audio_player.RepeatMode.one
            ? tokens.repeatOneIcon
            : tokens.repeatIcon;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 24,
          children: [
            _controlButton(
              icon: tokens.shuffleIcon,
              tooltip: 'Shuffle',
              size: 20,
              active: data.shuffleEnabled,
              onPressed: data.isDJMode ? null : coordinator.toggleShuffle,
            ),
            Row(
              spacing: 16,
              children: [
                GenericIconButton(
                  style: AppStyle.AppleMusic,
                  mouseCursor: SystemMouseCursors.click,
                  tooltip: 'Previous',
                  icon: Icon(
                    tokens.playPrevIcon,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: coordinator.skipPrevious,
                ),
                const _AppleMusicDesktopPlayPauseButton(),
                GenericIconButton(
                  style: AppStyle.AppleMusic,
                  mouseCursor: SystemMouseCursors.click,
                  tooltip: 'Next',
                  icon: Icon(
                    tokens.playNextIcon,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: coordinator.skipNext,
                ),
              ],
            ),
            _controlButton(
              icon: repeatIcon,
              tooltip: data.isDJMode ? 'Unavailable in DJ mode' : 'Repeat',
              size: 20,
              active: repeatActive,
              onPressed: data.isDJMode ? null : coordinator.toggleRepeat,
            ),
          ],
        );
      },
    );
  }
}

/// Center Play/Pause button for the Apple Music desktop player bar.
class _AppleMusicDesktopPlayPauseButton extends StatelessWidget {
  const _AppleMusicDesktopPlayPauseButton();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Selector2<
      global_audio_player.WispAudioHandler,
      PlaybackCoordinator,
      _PlayPauseData
    >(
      selector: (context, player, coordinator) {
        final track = player.currentTrack;
        final queueFirst = player.queueTracks.isNotEmpty
            ? player.queueTracks.first
            : null;
        return _PlayPauseData(
          isPlaying: coordinator.effectiveIsPlaying,
          isLoading: player.isLoading,
          isBuffering: player.isBuffering,
          isTransitioning: player.isTrackTransitioning,
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
        final coordinator = context.read<PlaybackCoordinator>();
        final isLoading =
            data.isLoading || data.isBuffering || data.isTransitioning;

        VoidCallback? onPressed;
        if (data.isPlaying) {
          onPressed = () => coordinator.pause();
        } else if (data.currentTrackId != null || data.queueNotEmpty) {
          onPressed = () => coordinator.play();
        }

        final IconData icon = data.isPlaying
            ? tokens.pauseIcon
            : tokens.playIcon;

        if (isLoading) {
          return const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          );
        }

        return GenericIconButton(
            style: AppStyle.AppleMusic,
            mouseCursor: SystemMouseCursors.click,
            padding: EdgeInsets.zero,
            iconSize: 44,
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
        );
      },
    );
  }
}

/// Play button with a circular progress ring for the Apple Music mobile bar.
class _AppleMusicCircularPlayButton extends StatelessWidget {
  const _AppleMusicCircularPlayButton();

  @override
  Widget build(BuildContext context) {
    return Selector2<
      global_audio_player.WispAudioHandler,
      PlaybackCoordinator,
      _PlayPauseData
    >(
      selector: (context, player, coordinator) {
        final track = player.currentTrack;
        final queueFirst = player.queueTracks.isNotEmpty
            ? player.queueTracks.first
            : null;
        return _PlayPauseData(
          isPlaying: coordinator.effectiveIsPlaying,
          isLoading: player.isLoading,
          isBuffering: player.isBuffering,
          isTransitioning: player.isTrackTransitioning,
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
        final coordinator = context.read<PlaybackCoordinator>();
        final isLoading =
            data.isLoading || data.isBuffering || data.isTransitioning;

        VoidCallback? onPressed;
        if (data.isPlaying) {
          onPressed = () => coordinator.pause();
        } else if (data.currentTrackId != null || data.queueNotEmpty) {
          onPressed = () => coordinator.play();
        }

        final IconData icon = data.isPlaying
            ? context.tokens.pauseIcon
            : context.tokens.playIcon;

        return SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _PlayerBarCircularProgressRing(
                ringColor: Colors.white,
                isLoading: isLoading,
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: GenericIconButton(
                  style: AppStyle.AppleMusic,
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: Icon(icon, color: Colors.white),
                  onPressed: onPressed,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Apple Music mobile player bar: a see-through liquid glass card.
class _AppleMusicMobilePlayerBar extends StatefulWidget {
  final dynamic currentTrack;

  const _AppleMusicMobilePlayerBar({required this.currentTrack});

  @override
  State<_AppleMusicMobilePlayerBar> createState() =>
      _AppleMusicMobilePlayerBarState();
}

class _AppleMusicMobilePlayerBarState
    extends State<_AppleMusicMobilePlayerBar> {
  double _dragOffset = 0.0;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta ?? 0;
      _dragOffset = _dragOffset.clamp(-100.0, 100.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final playback = context.read<PlaybackCoordinator>();

    if (velocity.abs() > 200 || _dragOffset.abs() > 50) {
      if (_dragOffset < 0 || velocity < -200) {
        playback.skipNext();
      } else {
        playback.skipPrevious();
      }
    }

    setState(() {
      _dragOffset = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final offset = Offset(_dragOffset / 300, 0);
    final dragProgress = (_dragOffset.abs() / 100).clamp(0.0, 1.0);

    final swipePreview = context
        .select<global_audio_player.WispAudioHandler, _SwipePreviewData>((
          player,
        ) {
          final queue = player.queueTracks;
          final currentIndex = player.currentIndex;
          GenericSong? previousTrack;
          GenericSong? nextTrack;

          if (currentIndex > 0 && currentIndex < queue.length) {
            previousTrack = queue[currentIndex - 1];
          }
          if (currentIndex >= 0 && currentIndex + 1 < queue.length) {
            nextTrack = queue[currentIndex + 1];
          }

          return _SwipePreviewData(
            previousTrack: previousTrack,
            nextTrack: nextTrack,
          );
        });

    final isSwipingLeft = _dragOffset < 0;
    final previewTrack = isSwipingLeft
        ? swipePreview.nextTrack
        : swipePreview.previousTrack;

    final handoffMessage = context.select<ConnectSessionProvider, String?>(
      (connect) => _handoffStatusMessage(connect),
    );

    // Transparent body: the lens provides the glass material.
    final cardBody = SizedBox(
      width: MediaQuery.of(context).size.width - 32,
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        child: Row(
          children: [
            _buildMobileArt(widget.currentTrack),
            const SizedBox(width: 12),

            // Track title & artist (with swipe animation)
            Expanded(
              child: ClipRect(
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  children: [
                    AnimatedSlide(
                      offset: offset,
                      duration: Duration.zero,
                      child: Opacity(
                        opacity: (1.0 - dragProgress).clamp(0.3, 1.0),
                        child: _buildMobileTrackInfo(widget.currentTrack),
                      ),
                    ),
                    if (previewTrack != null && dragProgress > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: (dragProgress * 0.95).clamp(0.0, 0.95),
                            child: Transform.translate(
                              offset: Offset(
                                isSwipingLeft
                                    ? (1 - dragProgress) * 24
                                    : -(1 - dragProgress) * 24,
                                0,
                              ),
                              child: _buildMobileTrackInfo(previewTrack),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            _ConnectMenuButton(
              iconSize: 22,
              appStyle: AppStyle.AppleMusic,
              inactiveColor: Colors.grey[400],
              activeColorOverride: Colors.white,
            ),
            LikeButton(
              track: widget.currentTrack as GenericSong?,
              iconSize: 22,
              padding: const EdgeInsets.all(2),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: Colors.white,
            ),
            const SizedBox(width: 4),

            // Circular progress indicator surrounding the play button
            const _AppleMusicCircularPlayButton(),
          ],
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Center(
          child: GestureDetector(
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => FullScreenPlayer.show(context),
                  child: _AppleGlassLens(cornerRadius: 16, child: cardBody),
                ),
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
                backgroundColor: const Color(0xFF2C2C2E),
                mobile: true,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileArt(dynamic currentTrack) {
    final imageUrl = currentTrack?.thumbnailUrl ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 46,
        height: 46,
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
    if (currentTrack == null || currentTrack is! GenericSong) {
      return Text(
        'No track playing',
        style: TextStyle(color: Colors.grey[600], fontSize: 14),
      );
    }

    final GenericSong track = currentTrack;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarqueeText(
          text: track.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          children: [
            TrackBadges(track: track),
            Expanded(
              child: MarqueeText(
                text: track.artists.map((a) => a.name).join(', '),
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
