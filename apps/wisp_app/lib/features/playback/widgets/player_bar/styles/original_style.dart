// Copyright Â© 2026 wizeshi

part of '../../player_bar.dart';

/// Darkened, slightly desaturated variant of the primary color used as the
/// blurred surface of the M3E mobile player bar (mirrors the Spotify style).
Color _originalTintedPrimary(Color color, {double blend = 0.4}) {
  final hsl = HSLColor.fromColor(color);
  final overlay = hsl
      .withLightness(0.22)
      .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
      .toColor();
  return Color.lerp(color, overlay, blend) ?? color;
}

/// Play button with a circular progress ring for the Original (M3E) mobile bar.
class _OriginalCircularPlayButton extends StatelessWidget {
  const _OriginalCircularPlayButton();

  @override
  Widget build(BuildContext context) {
    final ringColor = Theme.of(context).colorScheme.primary;

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
              // Circular progress ring
              _PlayerBarCircularProgressRing(
                ringColor: ringColor,
                isLoading: isLoading,
              ),

              // Play / Pause Button (M3E)
              M3EIconButton(
                variant: M3EIconButtonVariant.filled,
                size: M3EIconButtonSize.xs,
                shape: M3EIconButtonShapeVariant.round,
                icon: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 18,
                ),
                onPressed: onPressed,
                tooltip: data.isPlaying ? 'Pause' : 'Play',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Original Desktop Player Bar featuring Material 3 Expressive.
class _OriginalDesktopPlayerBar extends StatelessWidget {
  final GenericSong? currentTrack;

  const _OriginalDesktopPlayerBar({required this.currentTrack});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    final handoffMessage = context.select<ConnectSessionProvider, String?>(
      (connect) => _handoffStatusMessage(connect),
    );

    final barContent = Container(
      height: 88,
      decoration: BoxDecoration(
        // Neutral dark surface background (not primary tinted)
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
          // Top margin progress bar sits directly on the border between playerbar & content
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _PlayerBarTopProgressBar(accentColor: primaryColor),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                // Track Area (takes available space on left)
                Expanded(
                  child: Row(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: _DesktopTrackInfo(
                            currentTrack: currentTrack,
                            appStyle: AppStyle.Original,
                          ),
                        ),
                      ),

                      AudioQualityBadge(
                        preferredColor: Colors.white,
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

                                Widget? icon;

                                if (quality.isHiRes || quality.isLossless) {
                                  icon = SvgPicture.network(
                                    "https://upload.wikimedia.org/wikipedia/commons/0/0d/Apple_Lossless_logo.svg",
                                    fit: BoxFit.fill,
                                    colorFilter: ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  );
                                } else if (quality.bitrate != null &&
                                    quality.bitrate! >= 320) {
                                  icon = Icon(
                                    Symbols.check_circle_filled,
                                    fill: 1,
                                    color: Colors.white,
                                    size: 12,
                                  );
                                }

                                return Selector<
                                  CoverArtPaletteProvider,
                                  Color?
                                >(
                                  selector: (context, palette) =>
                                      palette.primaryColor,
                                  builder: (context, primaryColor, child) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryColor?.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: primaryColor != null ? Border.all(
                                          color: primaryColor.withValues(
                                            alpha: 0.35,
                                          ),
                                          width: 1,
                                        ) : null,
                                      ),
                                      child: Row(
                                        children: [
                                          if (icon != null) ...[
                                            icon,
                                            const SizedBox(width: 4),
                                          ],

                                          Text(
                                            label,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                      ),
                    ],
                  ),
                ),

                // Center Playback Area - natural width, guaranteed in the dead center
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: _OriginalDesktopPlaybackControls(),
                ),

                // Right Control Center (takes available space on right)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: _OriginalDesktopRightControls(
                        currentTrack: currentTrack,
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
                backgroundColor: HSLColor.fromColor(
                  primaryColor,
                ).withLightness(0.4).toColor(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Expressive playback controls for the Original desktop player bar.
class _OriginalDesktopPlaybackControls extends StatelessWidget {
  const _OriginalDesktopPlaybackControls();

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

        // Shuffle button
        final shuffleActive = data.shuffleEnabled;
        final shuffleColor = shuffleActive
            ? Theme.of(context).colorScheme.onPrimary
            : Colors.grey[400];

        // Repeat button
        final repeatActive =
            data.repeatMode != global_audio_player.RepeatMode.off;
        final repeatColor = repeatActive
            ? Theme.of(context).colorScheme.onPrimary
            : Colors.grey[400];

        final repeatIcon = data.repeatMode == global_audio_player.RepeatMode.one
            ? tokens.repeatOneIcon
            : tokens.repeatIcon;

        const navBtnVariant = M3EIconButtonVariant.tonal;
        const navBtnDecoration = M3EIconButtonDecoration(
          backgroundColor: WidgetStatePropertyAll(Color(0xFF26262A)),
        );

        // Active toggles use the filled variant (primary background).
        final shuffleVariant = shuffleActive
            ? M3EIconButtonVariant.filled
            : navBtnVariant;
        final shuffleDecoration = shuffleActive ? null : navBtnDecoration;

        final repeatVariant = repeatActive
            ? M3EIconButtonVariant.filled
            : navBtnVariant;
        final repeatDecoration = repeatActive ? null : navBtnDecoration;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Shuffle
            M3EIconButton(
              variant: shuffleVariant,
              decoration: shuffleDecoration,
              shape: M3EIconButtonShapeVariant.round,
              size: M3EIconButtonSize.sm,
              tooltip: 'Shuffle',
              icon: Icon(tokens.shuffleIcon, color: shuffleColor, size: 20),
              onPressed: data.isDJMode ? null : coordinator.toggleShuffle,
            ),
            const SizedBox(width: 8),

            // Previous
            M3EIconButton(
              variant: navBtnVariant,
              decoration: navBtnDecoration,
              shape: M3EIconButtonShapeVariant.round,
              size: M3EIconButtonSize.sm,
              tooltip: 'Previous',
              icon: Icon(tokens.playPrevIcon, color: Colors.white, size: 22),
              onPressed: coordinator.skipPrevious,
            ),
            const SizedBox(width: 12),

            // Center Play / Pause
            const _OriginalDesktopPlayPauseButton(),
            const SizedBox(width: 12),

            // Next
            M3EIconButton(
              variant: navBtnVariant,
              decoration: navBtnDecoration,
              shape: M3EIconButtonShapeVariant.round,
              size: M3EIconButtonSize.sm,
              tooltip: 'Next',
              icon: Icon(tokens.playNextIcon, color: Colors.white, size: 22),
              onPressed: coordinator.skipNext,
            ),
            const SizedBox(width: 8),

            // Repeat
            M3EIconButton(
              variant: repeatVariant,
              decoration: repeatDecoration,
              shape: M3EIconButtonShapeVariant.round,
              size: M3EIconButtonSize.sm,
              tooltip: data.isDJMode ? 'Unavailable in DJ mode' : 'Repeat',
              icon: Icon(repeatIcon, color: repeatColor, size: 20),
              onPressed: data.isDJMode ? null : coordinator.toggleRepeat,
            ),
          ],
        );
      },
    );
  }
}

/// Center Play/Pause button for Original Desktop.
class _OriginalDesktopPlayPauseButton extends StatelessWidget {
  const _OriginalDesktopPlayPauseButton();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final primaryColor = Theme.of(context).colorScheme.primary;

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
          return SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: M3EProgressIndicator.circularWavy(
                size: 26,
                strokeWidth: 2.5,
                color: primaryColor,
              ),
            ),
          );
        }

        return M3EIconButton(
          variant: M3EIconButtonVariant.filled,
          size: M3EIconButtonSize.md,
          shape: M3EIconButtonShapeVariant.round,
          icon: Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimary,
            size: 28,
          ),
          onPressed: onPressed,
          tooltip: data.isPlaying ? 'Pause' : 'Play',
        );
      },
    );
  }
}

/// Original Desktop Right Controls: segmented button group with a light
/// background (M3E).
class _OriginalDesktopRightControls extends StatelessWidget {
  final GenericSong? currentTrack;

  const _OriginalDesktopRightControls({required this.currentTrack});

  @override
  Widget build(BuildContext context) {
    final navState = context.watch<NavigationState>();
    return ValueListenableBuilder<Route<dynamic>?>(
      valueListenable: NavigationHistory.instance.currentRoute,
      builder: (context, route, child) {
        final routeName = route?.settings.name;
        final isLyricsRouteOpen = routeName == '/lyrics';
        final isQueueOpen = routeName == '/queue';
        final isFullScreenOpen = routeName == '/fullplayer';
        final hasTrack = currentTrack != null;
        final isSidebarOpen = hasTrack && navState.rightSidebarVisible;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final onPrimaryColor = Theme.of(context).colorScheme.onPrimary;
        final inactiveColor = Colors.grey[400];
        final tokens = context.tokens;

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showLyricsButton = width >= 230;
            final showQueueButton = width >= 280;
            final showVolumeSlider = width >= 390;

            return ValueListenableBuilder<FullPlayerDesktopMode>(
              valueListenable: AppNavigation.instance.fullPlayerDesktopMode,
              builder: (context, fullPlayerMode, child) {
                final isLyricsActive = isFullScreenOpen
                    ? fullPlayerMode == FullPlayerDesktopMode.lyrics
                    : isLyricsRouteOpen;
                final isQueueActive = isFullScreenOpen
                    ? fullPlayerMode == FullPlayerDesktopMode.queue
                    : isQueueOpen;

                final segments = <Widget Function(BorderRadius radius)>[];

                if (!isFullScreenOpen) {
                  // DJ segment
                  segments.add(
                    (radius) =>
                        Selector<global_audio_player.WispAudioHandler, bool>(
                          selector: (context, player) =>
                              player.playbackContext != null &&
                              player.playbackContext!.id
                                  .toLowerCase()
                                  .startsWith('dj'),
                          builder: (context, isDjActive, child) {
                            return _buildSegmentItem(
                              icon: Symbols.headphones,
                              tooltip: 'DJ',
                              isActive: isDjActive,
                              primaryColor: primaryColor,
                              onPrimaryColor: onPrimaryColor,
                              inactiveColor: inactiveColor,
                              borderRadius: radius,
                              onPressed: () {
                                NavigationHistory
                                            .instance
                                            .currentRoute
                                            .value
                                            ?.settings
                                            .name ==
                                        '/dj'
                                    ? NavigationHistory.instance.goBack()
                                    : AppNavigation.instance.navigateToDJView(
                                        context,
                                      );
                              },
                            );
                          },
                        ),
                  );

                  // Sidebar segment
                  segments.add(
                    (radius) => _buildSegmentItem(
                      icon: tokens.sidebarIcon,
                      tooltip: 'Sidebar',
                      isActive: isSidebarOpen,
                      primaryColor: primaryColor,
                      onPrimaryColor: onPrimaryColor,
                      inactiveColor: inactiveColor,
                      borderRadius: radius,
                      onPressed: hasTrack ? navState.toggleRightSidebar : null,
                    ),
                  );
                }

                // Lyrics segment
                if (showLyricsButton) {
                  segments.add(
                    (radius) => _buildSegmentItem(
                      icon: tokens.lyricsIcon,
                      tooltip: 'Lyrics',
                      isActive: isLyricsActive,
                      primaryColor: primaryColor,
                      onPrimaryColor: onPrimaryColor,
                      inactiveColor: inactiveColor,
                      borderRadius: radius,
                      onPressed: currentTrack == null
                          ? null
                          : () {
                              if (isFullScreenOpen) {
                                if (fullPlayerMode ==
                                    FullPlayerDesktopMode.lyrics) {
                                  AppNavigation.instance
                                      .restorePreviousFullPlayerDesktopMode();
                                } else {
                                  AppNavigation.instance
                                      .setFullPlayerDesktopMode(
                                        FullPlayerDesktopMode.lyrics,
                                      );
                                }
                                return;
                              }
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
                  );
                }

                // Queue segment
                if (showQueueButton) {
                  segments.add(
                    (radius) => _buildSegmentItem(
                      icon: tokens.queueIcon,
                      tooltip: 'Queue',
                      isActive: isQueueActive,
                      primaryColor: primaryColor,
                      onPrimaryColor: onPrimaryColor,
                      inactiveColor: inactiveColor,
                      borderRadius: radius,
                      onPressed: () {
                        if (isFullScreenOpen) {
                          if (fullPlayerMode == FullPlayerDesktopMode.queue) {
                            AppNavigation.instance
                                .restorePreviousFullPlayerDesktopMode();
                          } else {
                            AppNavigation.instance.setFullPlayerDesktopMode(
                              FullPlayerDesktopMode.queue,
                            );
                          }
                          return;
                        }
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
                  );
                }

                // Connect segment (seamlessly integrated into capsule)
                segments.add(
                  (radius) =>
                      Consumer2<ConnectSessionProvider, NavigationState>(
                        builder: (context, connect, navigation, child) {
                          final isDesktopConnectMenuOpen =
                              navigation.rightSidebarVisible &&
                              navigation.rightSidebarContent ==
                                  RightSidebarContent.connect;
                          final isConnectActive =
                              connect.isLinked || isDesktopConnectMenuOpen;
                          return _buildSegmentItem(
                            icon: tokens.connectIcon,
                            tooltip: 'Handoff',
                            isActive: isConnectActive,
                            primaryColor: primaryColor,
                            onPrimaryColor: onPrimaryColor,
                            inactiveColor: inactiveColor,
                            borderRadius: radius,
                            onPressed: () =>
                                _openConnectMenuWithAccent(context),
                          );
                        },
                      ),
                );

                if (!isFullScreenOpen) {
                  // Fullscreen segment
                  segments.add(
                    (radius) => _buildSegmentItem(
                      icon: tokens.fullscreenIcon,
                      tooltip: 'Full Screen',
                      isActive: false,
                      primaryColor: primaryColor,
                      onPrimaryColor: onPrimaryColor,
                      inactiveColor: inactiveColor,
                      borderRadius: radius,
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
                  );
                }

                final segmentWidgets = <Widget>[];
                for (var i = 0; i < segments.length; i++) {
                  final isFirst = i == 0;
                  final isLast = i == segments.length - 1;
                  final radius = isFirst && isLast
                      ? BorderRadius.circular(16)
                      : isFirst
                      ? const BorderRadius.horizontal(left: Radius.circular(16))
                      : isLast
                      ? const BorderRadius.horizontal(
                          right: Radius.circular(16),
                        )
                      : BorderRadius.zero; // Completely square in the middle!

                  segmentWidgets.add(segments[i](radius));
                  if (!isLast) {
                    segmentWidgets.add(_buildSegmentDivider());
                  }
                }

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Segmented Button Capsule with lighter background and balanced padding
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF26262A),
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: segmentWidgets,
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Volume Pill Container with lighter background
                    Selector<global_audio_player.WispAudioHandler, double>(
                      selector: (context, player) => player.userVolume,
                      builder: (context, volume, child) {
                        final player = context
                            .read<global_audio_player.WispAudioHandler>();
                        if (!showVolumeSlider) {
                          return Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF26262A),
                              borderRadius: BorderRadius.circular(19),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 0.8,
                              ),
                            ),
                            child: _VolumePopupButton(
                              inactiveColor: inactiveColor,
                              accentColor: primaryColor,
                            ),
                          );
                        }

                        return Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF26262A),
                            borderRadius: BorderRadius.circular(19),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GenericIconButton(
                                style: AppStyle.Original,
                                mouseCursor: SystemMouseCursors.click,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: volume == 0 ? 'Unmute' : 'Mute',
                                onPressed: player.toggleMute,
                                icon: Icon(
                                  volume == 0
                                      ? tokens.volumeOffIcon
                                      : volume < 0.5
                                      ? tokens.volumeDownIcon
                                      : tokens.volumeUpIcon,
                                  color: Colors.grey[400],
                                  size: 18,
                                ),
                              ),
                              SizedBox(
                                width: 88,
                                child: _HoverVolumeSlider(
                                  value: volume,
                                  onChanged: (value) => player.setVolume(value),
                                  primaryColor: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  static Widget _buildSegmentItem({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required Color primaryColor,
    required Color onPrimaryColor,
    required Color? inactiveColor,
    required VoidCallback? onPressed,
    BorderRadius borderRadius = BorderRadius.zero,
  }) {
    final bool isClickable = onPressed != null;
    return MouseRegion(
      cursor: isClickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isActive ? primaryColor : Colors.transparent,
          borderRadius: borderRadius,
          child: InkWell(
            mouseCursor: isClickable
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            borderRadius: borderRadius,
            onTap: onPressed,
            child: Container(
              constraints: const BoxConstraints(minWidth: 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: isActive
                    ? onPrimaryColor
                    : (isClickable
                          ? (inactiveColor ?? Colors.grey[400])
                          : Colors.grey[600]),
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildSegmentDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
      color: Colors.white.withValues(alpha: 0.12),
    );
  }
}

/// Original Mobile Player Bar featuring Liquid Glass / M3E and circular progress ring.
class _OriginalMobilePlayerBar extends StatefulWidget {
  final dynamic currentTrack;

  const _OriginalMobilePlayerBar({required this.currentTrack});

  @override
  State<_OriginalMobilePlayerBar> createState() =>
      _OriginalMobilePlayerBarState();
}

class _OriginalMobilePlayerBarState extends State<_OriginalMobilePlayerBar> {
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

    final tintedPrimary = _originalTintedPrimary(
      Theme.of(context).colorScheme.primary,
    );

    Widget cardBody = Container(
      width: MediaQuery.of(context).size.width - 32,
      height: 60,
      decoration: BoxDecoration(
        // Blurred, tinted primary surface (like the Spotify style).
        color: tintedPrimary.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        child: Row(
          children: [
            // Track Art
            _buildMobileArt(widget.currentTrack),
            const SizedBox(width: 12),

            // Track Title & Artist (with swipe animation)
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

            // Connect button
            _ConnectMenuButton(
              iconSize: 22,
              appStyle: AppStyle.Original,
              inactiveColor: Colors.grey[400],
              activeColorOverride: Colors.white,
            ),

            // Like button
            LikeButton(
              track: widget.currentTrack as GenericSong?,
              iconSize: 22,
              padding: const EdgeInsets.all(2),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: Colors.white,
            ),
            const SizedBox(width: 4),

            // Circular progress indicator surrounding the play button!
            const _OriginalCircularPlayButton(),
          ],
        ),
      ),
    );

    cardBody = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: cardBody,
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
                  child: cardBody,
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
        const SizedBox(height: 2),
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
