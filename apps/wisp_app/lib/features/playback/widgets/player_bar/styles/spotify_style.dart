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
    final swipePreview = context
        .select<global_audio_player.WispAudioHandler, _SwipePreviewData>(
          _selectSwipePreview,
        );
    final quality = context
        .select<global_audio_player.WispAudioHandler, ActiveTrackQualityInfo?>(
          (player) => player.activeTrackQuality,
        );
    final playback = context.read<PlaybackCoordinator>();

    final colors = context.colors;
    final isDark = colors.isDark;
    final primary = Theme.of(context).colorScheme.primary;
    final bgColor = isDark
        ? _tintedDominantColor(primary)
        : (Color.lerp(Colors.white, primary, 0.16) ?? Colors.white);
    final fgPrimary = isDark ? Colors.white : colors.textPrimary;
    final fgSecondary = isDark
        ? Colors.white.withValues(alpha: 0.78)
        : colors.textSecondary;

    final btnColor = isDark
        ? HSLColor.fromColor(
            bgColor,
          ).withLightness(0.7).withSaturation(1).toColor()
        : primary;

    final handoffMessage = context.select<ConnectSessionProvider, String?>(
      (connect) => _handoffStatusMessage(connect),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Center(
          child: MobileSwipeablePlayerBar(
            currentTrack: widget.currentTrack is GenericSong
                ? widget.currentTrack as GenericSong
                : null,
            previousTrack: swipePreview.previousTrack,
            nextTrack: swipePreview.nextTrack,
            onSkipNext: playback.skipNext,
            onSkipPrevious: playback.skipPrevious,
            builder: (builderContext, swipe) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => FullScreenPlayer.show(builderContext),
                      child: Container(
                        width: MediaQuery.of(builderContext).size.width - 32,
                        height: 60,
                        decoration: BoxDecoration(
                          color: bgColor.withValues(alpha: isDark ? 0.80 : 0.92),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : colors.borderSubtle,
                            width: 0.8,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.32)
                                  : colors.shadow,
                              blurRadius: isDark ? 14 : 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                                child: Row(
                                  children: [
                                    MobileSwipeArtworkOverlay(
                                      swipe: swipe,
                                      size: 44,
                                      borderRadius: BorderRadius.circular(6),
                                      child: _buildMobileAlbumArt(
                                        builderContext,
                                        widget.currentTrack,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: MobileSwipeTrackInfoStack(
                                        swipe: swipe,
                                        accentColor: btnColor,
                                        secondaryColor: fgSecondary,
                                        currentChild: _buildMobileTrackInfo(
                                          builderContext,
                                          widget.currentTrack,
                                          quality: quality,
                                          fgPrimary: fgPrimary,
                                          fgSecondary: fgSecondary,
                                        ),
                                        previewChild: swipe.previewTrack == null
                                            ? null
                                            : _buildMobileTrackInfo(
                                                builderContext,
                                                swipe.previewTrack,
                                                quality: quality,
                                                fgPrimary: fgPrimary,
                                                fgSecondary: fgSecondary,
                                              ),
                                      ),
                                    ),
                                    _buildMobileConnectButton(
                                      widget.appStyle,
                                      fgPrimary: fgPrimary,
                                      fgSecondary: fgSecondary,
                                    ),
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
                                    _buildMobilePlayPauseButton(
                                      widget.appStyle,
                                      fgPrimary: fgPrimary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: _buildMiniProgressBar(
                                  progressColor:
                                      isDark ? Colors.white : primary,
                                  trackBg: isDark
                                      ? Colors.grey[850]!.withValues(alpha: 0.4)
                                      : colors.borderSubtle,
                                  bufferedColor: fgPrimary.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
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

  Widget _buildMobileAlbumArt(BuildContext context, dynamic currentTrack) {
    final imageUrl = currentTrack?.thumbnailUrl ?? '';
    final colors = context.colors;
    return PlayerArtworkHero(
      borderRadius: BorderRadius.circular(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 44,
          height: 44,
          color: colors.artworkPlaceholder,
          child: imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 132,
                  memCacheHeight: 132,
                  placeholder: (context, url) =>
                      Container(color: colors.artworkPlaceholder),
                  errorWidget: (context, url, error) =>
                      Icon(Icons.music_note, color: colors.textMuted),
                )
              : Icon(Icons.music_note, color: colors.textMuted),
        ),
      ),
    );
  }

  Widget _buildMobileTrackInfo(
    BuildContext context,
    dynamic currentTrack, {
    required ActiveTrackQualityInfo? quality,
    required Color fgPrimary,
    required Color fgSecondary,
  }) {
    if (currentTrack == null || currentTrack is! GenericSong) {
      return Text(
        'No track playing',
        style: TextStyle(color: context.colors.textMuted, fontSize: 14),
      );
    }

    final GenericSong track = currentTrack;

    final qualityLabel = quality == null
        ? 'Standard'
        : quality.isHiRes
        ? 'Hi-Res Lossless'
        : quality.isLossless
        ? 'Lossless'
        : quality.bitrate != null && quality.bitrate! >= 320
        ? 'High Quality'
        : 'Standard';

    return ConnectDeviceIndicator(
      detailedBuilder:
          (
            context,
            showConnectStatus,
            connectStatusWidget,
            deviceName,
            deviceIcon,
          ) {
            final deviceTitle = (deviceName != null && deviceName.isNotEmpty)
                ? deviceName
                : 'Connected Device';

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (showConnectStatus) TrackBadges(track: track),
                    Expanded(
                      child: MarqueeText(
                        text: showConnectStatus
                            ? "${track.title}  •  ${track.artists.map((a) => a.name).join(', ')}"
                            : track.title,
                        style: TextStyle(
                          color: fgPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                showConnectStatus
                    ? Row(
                        children: [
                          if (deviceIcon != null) ...[
                            Icon(deviceIcon, color: fgPrimary, size: 14),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: MarqueeText(
                              text: "$deviceTitle • $qualityLabel",
                              style: TextStyle(
                                color: fgSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          TrackBadges(track: track),
                          Expanded(
                            child: MarqueeText(
                              text:
                                  "${track.artists.map((a) => a.name).join(', ')} • $qualityLabel",
                              style: TextStyle(
                                color: fgSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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

  Widget _buildMobileConnectButton(
    AppStyle appStyle, {
    required Color fgPrimary,
    required Color fgSecondary,
  }) {
    return _ConnectMenuButton(
      iconSize: 24,
      appStyle: appStyle,
      inactiveColor: fgSecondary,
      activeColorOverride: fgPrimary,
    );
  }

  Widget _buildMobilePlayPauseButton(
    AppStyle appStyle, {
    required Color fgPrimary,
  }) {
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
          return SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(fgPrimary),
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
          icon: Icon(icon, size: 28, color: fgPrimary),
          onPressed: onPressed,
        );
      },
    );
  }

  Widget _buildMiniProgressBar({
    required Color progressColor,
    required Color trackBg,
    required Color bufferedColor,
  }) {
    return Selector2<
      global_audio_player.WispAudioHandler,
      PlaybackCoordinator,
      _PositionData
    >(
      selector: (context, player, coordinator) => _PositionData(
        position: coordinator.useLinkedPlaybackState
            ? coordinator.effectiveThrottledPosition
            : player.throttledPosition,
        bufferedPosition: coordinator.effectiveBufferedPosition,
        duration: player.duration,
        isLoading:
            !coordinator.useLinkedPlaybackState &&
            (player.isLoading || player.isBuffering),
      ),
      builder: (context, data, _) {
        if (data.isLoading) {
          return SizedBox(
            height: 3,
            child: LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          );
        }

        final duration = data.duration;
        final position = data.position;
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;
        final bufferedProgress = duration.inMilliseconds > 0
            ? (data.bufferedPosition.inMilliseconds / duration.inMilliseconds)
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
              final fBuffered = fDuration.inMilliseconds > 0
                  ? (frozenData.bufferedPosition.inMilliseconds /
                            fDuration.inMilliseconds)
                        .clamp(0.0, 1.0)
                  : 0.0;
              return _buildMiniProgressIndicator(
                fProgress,
                fBuffered,
                progressColor: progressColor,
                trackBg: trackBg,
                bufferedColor: bufferedColor,
              );
            },
          );
        }

        return _buildMiniProgressIndicator(
          progress,
          bufferedProgress,
          progressColor: progressColor,
          trackBg: trackBg,
          bufferedColor: bufferedColor,
        );
      },
    );
  }

  Widget _buildMiniProgressIndicator(
    double progress,
    double bufferedProgress, {
    required Color progressColor,
    required Color trackBg,
    required Color bufferedColor,
  }) {
    return SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LinearProgressIndicator(
            value: bufferedProgress,
            backgroundColor: trackBg,
            valueColor: AlwaysStoppedAnimation<Color>(bufferedColor),
          ),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
        ],
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
    final colors = context.colors;

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
              color: colors.playerBar,
              border: Border(
                top: BorderSide(color: colors.borderSubtle, width: 1),
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
                        child: _SpotifyDesktopTrackInfo(
                          currentTrack: currentTrack,
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

class _SpotifyDesktopTrackInfo extends StatelessWidget {
  final GenericSong? currentTrack;

  const _SpotifyDesktopTrackInfo({required this.currentTrack});

  @override
  Widget build(BuildContext context) {
    final track = currentTrack!;
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 56,
            height: 56,
            color: colors.artworkPlaceholder,
            child: currentTrack!.thumbnailUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: currentTrack!.thumbnailUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 168,
                    memCacheHeight: 168,
                    placeholder: (context, url) =>
                        Container(color: colors.artworkPlaceholder),
                    errorWidget: (context, url, error) =>
                        Icon(Icons.music_note, color: colors.textMuted),
                  )
                : Icon(Icons.music_note, color: colors.textMuted),
          ),
        ),
        SizedBox(width: 12),
        Flexible(
          fit: FlexFit.loose,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DesktopTrackName(track: track),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TrackBadges(track: track),
                  Flexible(
                    fit: FlexFit.loose,
                    child: _DesktopTrackArtists(track: track),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AudioQualityBadge(
                    preferredColor: Theme.of(context).colorScheme.primary,
                    child:
                        Selector<
                          global_audio_player.WispAudioHandler,
                          ActiveTrackQualityInfo?
                        >(
                          selector: (context, player) =>
                              player.activeTrackQuality,
                          builder: (context, quality, child) {
                            if (quality == null) {
                              return const SizedBox.shrink();
                            }

                            String label = 'Standard';

                            if (quality.isHiRes) {
                              label = 'Hi-Res Lossless';
                            } else if (quality.isLossless) {
                              label = 'Lossless';
                            } else if (quality.bitrate != null) {
                              if (quality.bitrate! >= 320) {
                                label = 'High Quality';
                              } else if (quality.bitrate! < 320) {
                                label = 'Standard';
                              }
                            }

                            return HoverRegion(
                              child: Builder(
                                builder: (context) {
                                  final isHovered =
                                      HoverRegion.of(context) ?? false;

                                  return MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        decorationColor: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        decoration: isHovered
                                            ? TextDecoration.underline
                                            : TextDecoration.none,
                                        decorationThickness: 3,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        LikeButton(
          track: currentTrack,
          iconSize: 18,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }
}
