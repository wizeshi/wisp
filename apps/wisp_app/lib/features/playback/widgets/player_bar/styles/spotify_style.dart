// Copyright © 2026 wizeshi

part of '../../player_bar.dart';

class _MobilePlayerBarAnimated extends StatefulWidget {
  final dynamic currentTrack;
  final AppStyle appStyle;

  const _MobilePlayerBarAnimated({
    required this.currentTrack,
    required this.appStyle,
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

  Color _tintedDominantColor(Color color, {double blend = 0.4}) {
    final hsl = HSLColor.fromColor(color);
    final overlay = hsl
        .withLightness(0.22)
        .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
        .toColor();
    return Color.lerp(color, overlay, blend) ?? color;
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

    var bgColor = _tintedDominantColor(Theme.of(context).colorScheme.primary);

    var btnColor = HSLColor.fromColor(
      bgColor,
    ).withLightness(0.7).withSaturation(1).toColor();

    final handoffMessage = context.select<ConnectSessionProvider, String?>(
      (connect) => _handoffStatusMessage(connect),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Center(
          child: GestureDetector(
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => FullScreenPlayer.show(context),
                    child: Container(
                      width:
                          MediaQuery.of(context).size.width -
                          32, // 16px padding each side
                      height: 56,
                      decoration: BoxDecoration(
                        color: bgColor.withValues(alpha: 0.78),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                        borderRadius: BorderRadius.circular(10),
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
                                    child: Stack(
                                      children: [
                                        AnimatedSlide(
                                          offset: offset,
                                          duration: Duration.zero,
                                          child: Opacity(
                                            opacity: (1.0 - dragProgress).clamp(
                                              0.3,
                                              1.0,
                                            ),
                                            child: _buildMobileTrackInfo(
                                              widget.currentTrack,
                                            ),
                                          ),
                                        ),
                                        if (previewTrack != null && dragProgress > 0)
                                          Positioned.fill(
                                            child: IgnorePointer(
                                              child: Opacity(
                                                opacity: (dragProgress * 0.95).clamp(
                                                  0.0,
                                                  0.95,
                                                ),
                                                child: Transform.translate(
                                                  offset: Offset(
                                                    isSwipingLeft
                                                        ? (1 - dragProgress) * 24
                                                        : -(1 - dragProgress) * 24,
                                                    0,
                                                  ),
                                                  child: _buildMobileTrackInfo(
                                                    previewTrack,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                _buildMobileConnectButton(widget.appStyle),
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
                                _buildMobilePlayPauseButton(widget.appStyle),
                              ],
                            ),
                          ),
                          _buildMiniProgressBar(),
                        ],
                      ),
                    ),
                  ),
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
                backgroundColor: btnColor,
                mobile: true,
              ),
            ),
          ),
      ],
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
    if (currentTrack == null || currentTrack is! GenericSong) {
      return Text(
        'No track playing',
        style: TextStyle(color: Colors.grey[600], fontSize: 14),
      );
    }

    final GenericSong track = currentTrack;

    final output = context.select<ConnectSessionProvider, _MobileOutputInfo>(
      (connect) => _MobileOutputInfo.fromProvider(connect),
    );

    if (output.isExternal) {
      final artists = track.artists
          .map((artist) => artist.name)
          .join(', ');
      final songLine = artists.isEmpty
          ? track.title
          : '${track.title}  ·  $artists';

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarqueeText(
            text: songLine,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            pauseWhenUnfocused: true,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TrackBadges(track: track),
              Flexible(
                child: MarqueeText(
                  text: output.deviceName,
                  style: TextStyle(
                    color: Colors.white,
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
                  color: Colors.grey[250],
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

  Widget _buildMobileConnectButton(AppStyle appStyle) {
    return _ConnectMenuButton(
      iconSize: 24,
      appStyle: appStyle,
      inactiveColor: Colors.grey[300],
      activeColorOverride: Colors.white,
    );
  }

  Widget _buildMobilePlayPauseButton(AppStyle appStyle) {
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
        );
      },
      builder: (context, data, child) {
        final useHandoffState = context.select<PlaybackCoordinator, bool>(
          (coordinator) => coordinator.useLinkedPlaybackState,
        );
        final effectiveIsPlaying = context.select<PlaybackCoordinator, bool>(
          (coordinator) => coordinator.effectiveIsPlaying,
        );
        if (data.isLoading || data.isBuffering || data.isTransitioning) {
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
            ? context.tokens.pauseIcon
            : context.tokens.playIcon;
        VoidCallback? onPressed;
        if (!isOfflineBlocked) {
          if (effectiveIsPlaying) {
            onPressed = () {
              context.read<PlaybackCoordinator>().pause();
            };
          } else if (data.currentTrackId != null) {
            onPressed = () {
              final audio = context
                  .read<global_audio_player.WispAudioHandler>();
              if (!useHandoffState &&
                  (audio.isLoading ||
                      audio.isBuffering ||
                      audio.isTrackTransitioning)) {
                return;
              }
              context.read<PlaybackCoordinator>().play();
            };
          } else if (data.queueNotEmpty) {
            onPressed = () {
              final audio = context
                  .read<global_audio_player.WispAudioHandler>();
              if (!useHandoffState &&
                  (audio.isLoading ||
                      audio.isBuffering ||
                      audio.isTrackTransitioning)) {
                return;
              }
              context.read<PlaybackCoordinator>().play();
            };
          }
        }

        return GenericIconButton(
          style: AppStyle.Spotify,
          icon: Icon(icon, size: 28, color: Colors.white),
          onPressed: onPressed,
        );
      },
    );
  }

  Widget _buildMiniProgressBar() {
    return Selector2<
      global_audio_player.WispAudioHandler,
      PlaybackCoordinator,
      _PositionData
    >(
      selector: (context, player, coordinator) => _PositionData(
        position: coordinator.useLinkedPlaybackState
            ? coordinator.effectiveThrottledPosition
            : player.throttledPosition,
        duration: player.duration,
        isLoading: !coordinator.useLinkedPlaybackState &&
            (player.isLoading || player.isBuffering),
      ),
      builder: (context, data, _) {
        if (data.isLoading) {
          return const SizedBox(
            height: 3,
            child: LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          );
        }

        final duration = data.duration;
        final position = data.position;
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;

        final shouldFreeze = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
            PausedBackgroundWidget.playerProgressBar,
          ),
        );

        if (shouldFreeze) {
          return FocusFreezeBuilder<_PositionData>(
            value: data,
            builder: (context, frozenData) {
              final fDuration = frozenData.duration;
              final fProgress = fDuration.inMilliseconds > 0
                  ? (frozenData.position.inMilliseconds /
                          fDuration.inMilliseconds)
                      .clamp(0.0, 1.0)
                  : 0.0;
              return _buildMiniProgressIndicator(fProgress);
            },
          );
        }

        return _buildMiniProgressIndicator(progress);
      },
    );
  }

  Widget _buildMiniProgressIndicator(double progress) {
    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: Colors.grey[850]?.withValues(alpha: 0.4),
        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }
}

class _DesktopPlayerBar extends StatelessWidget {
  final GenericSong? currentTrack;
  final AppStyle appStyle;

  const _DesktopPlayerBar({required this.currentTrack, required this.appStyle});

  @override
  Widget build(BuildContext context) {
    final buttonColor = Theme.of(context).colorScheme.primary;

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
                  // Track Area (30%)
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: _DesktopTrackInfo(
                          currentTrack: currentTrack,
                          appStyle: appStyle,
                        ),
                      ),
                    ),
                  ),
                  // Playback Area (40%)
                  Expanded(
                    flex: 4,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DesktopPlaybackControls(appStyle: appStyle),
                          _DesktopProgressBar(),
                        ],
                      ),
                    ),
                  ),
                  // Control Center (30%)
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: _DesktopRightControls(
                          currentTrack: currentTrack,
                          appStyle: appStyle,
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
              top: -32,
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

