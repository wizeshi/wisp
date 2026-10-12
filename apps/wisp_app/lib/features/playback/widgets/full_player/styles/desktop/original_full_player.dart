// Copyright © 2026 wizeshi

import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/playback/views/lyrics_view.dart';
import 'package:wisp/features/playback/views/queue_view.dart';
import 'package:wisp/features/playback/widgets/player_bar.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart'
    as global_audio_player;
import 'package:wisp/services/system/app_focus_service.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/shared/widgets/display/focus_freeze_builder.dart';
import 'package:wisp/shared/widgets/display/marquee_text.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';

import '../../components/inline_delay_editor.dart';
import '../../components/rotating_blurred_cover_background.dart';

/// Available modes for the Original desktop player mode area.
enum OriginalDesktopMode { disc, queue, lyrics }

/// Original Desktop Full-Screen Player featuring YouTube Music / Material 3
/// Expressive aesthetics, split layout, vinyl disc with animated tonearm,
/// FocusFreezeBuilder integration, and isolated architecture.
class OriginalDesktopFullScreenPlayer extends StatefulWidget {
  const OriginalDesktopFullScreenPlayer({super.key});

  @override
  State<OriginalDesktopFullScreenPlayer> createState() =>
      _OriginalDesktopFullScreenPlayerState();
}

class _OriginalDesktopFullScreenPlayerState
    extends State<OriginalDesktopFullScreenPlayer>
    with TickerProviderStateMixin {
  /// Remembers the user's selected mode for this session.
  static OriginalDesktopMode _lastSessionMode = OriginalDesktopMode.disc;

  late OriginalDesktopMode _currentMode;
  late final AnimationController _vinylRotationController;
  late final AnimationController _tonearmController;
  late final Animation<double> _tonearmAnimation;
  final FocusNode _focusNode = FocusNode();
  Timer? _inactivityTimer;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _currentMode = _lastSessionMode;
    _startInactivityTimer();

    // Standard 33 1/3 RPM vinyl turns roughly once every 1.8 - 3.5 seconds.
    // 3.6 seconds creates an organic, smooth spinning sensation.
    _vinylRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );

    // Smooth mechanical movement for tonearm onto and off the record
    _tonearmController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _tonearmAnimation = CurvedAnimation(
      parent: _tonearmController,
      curve: Curves.easeInOutCubic,
    );

    AppNavigation.instance.fullPlayerDesktopMode.addListener(
      _handleNavigationModeChanged,
    );
    AppFocusService.instance.isFocused.addListener(_syncRotationWithPlayback);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncRotationWithPlayback();
      }
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    AppNavigation.instance.fullPlayerDesktopMode.removeListener(
      _handleNavigationModeChanged,
    );
    AppFocusService.instance.isFocused.removeListener(
      _syncRotationWithPlayback,
    );
    _vinylRotationController.dispose();
    _tonearmController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controlsVisible) {
        if (_currentMode == OriginalDesktopMode.queue) {
          return;
        }
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  void _resetInactivityTimer() {
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    _startInactivityTimer();
  }

  void _handleNavigationModeChanged() {
    final navMode = AppNavigation.instance.fullPlayerDesktopMode.value;
    final targetMode = switch (navMode) {
      FullPlayerDesktopMode.lyrics => OriginalDesktopMode.lyrics,
      FullPlayerDesktopMode.queue => OriginalDesktopMode.queue,
      _ => OriginalDesktopMode.disc,
    };

    if (targetMode != _currentMode && mounted) {
      setState(() {
        _currentMode = targetMode;
        _lastSessionMode = targetMode;
      });
      _resetInactivityTimer();
    }
  }

  void _onModeChanged(OriginalDesktopMode mode) {
    if (_currentMode == mode) return;
    _resetInactivityTimer();
    setState(() {
      _currentMode = mode;
      _lastSessionMode = mode;
    });

    final targetNavMode = switch (mode) {
      OriginalDesktopMode.lyrics => FullPlayerDesktopMode.lyrics,
      OriginalDesktopMode.queue => FullPlayerDesktopMode.queue,
      OriginalDesktopMode.disc => FullPlayerDesktopMode.artwork,
    };
    AppNavigation.instance.setFullPlayerDesktopMode(targetNavMode);
  }

  void _syncRotationWithPlayback() {
    if (!mounted) return;
    final coordinator = context.read<PlaybackCoordinator>();
    final isPlaying = coordinator.effectiveIsPlaying;
    final freezeWhenUnfocused = context
        .read<PreferencesProvider>()
        .pausedBackgroundWidgetsEnabled
        .contains(PausedBackgroundWidget.rotatingAlbumArtFullScreen);
    final isFocused = AppFocusService.instance.isFocused.value;

    final shouldRotate = isPlaying && (!freezeWhenUnfocused || isFocused);

    if (shouldRotate) {
      if (!_vinylRotationController.isAnimating) {
        _vinylRotationController.repeat();
      }
    } else {
      if (_vinylRotationController.isAnimating) {
        _vinylRotationController.stop(canceled: false);
      }
    }

    if (isPlaying) {
      if (_tonearmController.status != AnimationStatus.forward &&
          _tonearmController.status != AnimationStatus.completed) {
        _tonearmController.forward();
      }
    } else {
      if (_tonearmController.status != AnimationStatus.reverse &&
          _tonearmController.status != AnimationStatus.dismissed) {
        _tonearmController.reverse();
      }
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(AppNavigation.instance.closeFullPlayer());
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioHandler = context.watch<global_audio_player.WispAudioHandler>();
    final coordinator = context.watch<PlaybackCoordinator>();
    final currentTrack = audioHandler.currentTrack;
    final isPlaying = coordinator.effectiveIsPlaying;

    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.rotatingAlbumArtFullScreen,
      ),
    );
    final isFocused = AppFocusService.instance.isFocused.value;
    final shouldRotate = isPlaying && (!freezeWhenUnfocused || isFocused);

    // Reactively start or pause vinyl rotation
    if (shouldRotate) {
      if (!_vinylRotationController.isAnimating) {
        _vinylRotationController.repeat();
      }
    } else {
      if (_vinylRotationController.isAnimating) {
        _vinylRotationController.stop(canceled: false);
      }
    }

    // Reactively move tonearm
    if (isPlaying) {
      if (_tonearmController.status != AnimationStatus.forward &&
          _tonearmController.status != AnimationStatus.completed) {
        _tonearmController.forward();
      }
    } else {
      if (_tonearmController.status != AnimationStatus.reverse &&
          _tonearmController.status != AnimationStatus.dismissed) {
        _tonearmController.reverse();
      }
    }

    final imageUrl = currentTrack?.thumbnailUrl ?? '';

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => _resetInactivityTimer(),
        onHover: (_) => _resetInactivityTimer(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Rotating blurred background cover (not animated canvas)
            Positioned.fill(
              child: RepaintBoundary(
                child: RotatingBlurredCoverBackground(
                  imageUrl: imageUrl,
                  blurSigma: 80,
                ),
              ),
            ),

            // 2. Dark tint overlay for readability & contrast
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.50)),
            ),

            // 3. Foreground content column
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Bar with collapse action on the top right (auto-hides on inactivity)
                _buildTopBar(context),

                // Main Body: Left Now Playing area and Right Mode area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(48, 4, 48, 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Left Now Playing Area (Always pinned to left side)
                            Expanded(
                              child: Center(
                                child: _buildNowPlayingArea(
                                  context,
                                  currentTrack,
                                  constraints,
                                ),
                              ),
                            ),

                            // Right Mode Area (Always pinned to right side, enlarged width)
                            _buildModeArea(context, currentTrack, constraints),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // Bottom Player Bar: animated slide/fade on inactivity timeout
                _buildAnimatedBottomPlayerBar(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedSlide(
        offset: _controlsVisible ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                M3EIconButton(
                  variant: M3EIconButtonVariant.tonal,
                  size: M3EIconButtonSize.sm,
                  shape: M3EIconButtonShapeVariant.round,
                  icon: const Icon(
                    Symbols.keyboard_arrow_down,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () => AppNavigation.instance.closeFullPlayer(),
                  tooltip: 'Collapse',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedBottomPlayerBar() {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedSlide(
        offset: _controlsVisible ? Offset.zero : const Offset(0, 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: const RepaintBoundary(child: WispPlayerBar()),
        ),
      ),
    );
  }

  Widget _buildNowPlayingArea(
    BuildContext context,
    GenericSong? track,
    BoxConstraints constraints,
  ) {
    // Width takes ~58% of width with responsive clamping (leaving ~42% for the mode area)
    final nowPlayingWidth = (constraints.maxWidth * 0.25);
    final title = track?.title ?? 'No track playing';
    final artists = track?.artists.map((a) => a.name).join(', ') ?? '';
    final albumName = track?.album?.title ?? '';
    final imageUrl = track?.thumbnailUrl ?? '';

    return SizedBox(
      width: nowPlayingWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Album Cover Artwork
          Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              _buildPlaceholderCover(),
                        )
                      : _buildPlaceholderCover(),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Track Info (left-justified) & Action Buttons (right-aligned)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Track Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MarqueeText(
                      text: title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (artists.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                    if (albumName.isNotEmpty && albumName != title) ...[
                      const SizedBox(height: 2),
                      Text(
                        albumName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Action buttons to the right of track info
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LikeButton(track: track, iconSize: 22),
                  const SizedBox(width: 4),
                  GenericIconButton(
                    icon: const Icon(
                      Symbols.more_horiz,
                      color: Colors.white70,
                      size: 22,
                    ),
                    onPressed: track != null
                        ? () => EntityContextMenus.showTrackMenu(
                            context,
                            track: track,
                          )
                        : null,
                    tooltip: 'More options',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      color: const Color(0xFF222222),
      child: const Center(
        child: Icon(Symbols.music_note, size: 64, color: Colors.white30),
      ),
    );
  }

  Widget _buildModeArea(
    BuildContext context,
    GenericSong? track,
    BoxConstraints constraints,
  ) {
    // Mode area width enlarged to 58% of available space
    final modeWidth = (constraints.maxWidth * 0.42);

    return SizedBox(
      width: modeWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // M3E / YouTube Music Segmented Tab Selector
          Align(
            alignment: Alignment.topRight,
            child: _buildModeSelector(context),
          ),

          const SizedBox(height: 16),

          // Mode Content Container with animated switching
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<OriginalDesktopMode>(_currentMode),
                child: _buildCurrentModeContent(context, track),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeTabItem(
            mode: OriginalDesktopMode.disc,
            label: 'Disc',
            icon: Symbols.album,
            primaryColor: primaryColor,
          ),
          _buildModeTabItem(
            mode: OriginalDesktopMode.queue,
            label: 'Queue',
            icon: Symbols.queue_music,
            primaryColor: primaryColor,
          ),
          _buildModeTabItem(
            mode: OriginalDesktopMode.lyrics,
            label: 'Lyrics',
            icon: Symbols.lyrics,
            primaryColor: primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabItem({
    required OriginalDesktopMode mode,
    required String label,
    required IconData icon,
    required Color primaryColor,
  }) {
    final isSelected = _currentMode == mode;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _onModeChanged(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.9)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentModeContent(BuildContext context, GenericSong? track) {
    switch (_currentMode) {
      case OriginalDesktopMode.disc:
        return Center(
          child: _VinylDiscWidget(
            thumbnailUrl: track?.thumbnailUrl ?? '',
            rotationController: _vinylRotationController,
            tonearmAnimation: _tonearmAnimation,
          ),
        );

      case OriginalDesktopMode.queue:
        return const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          child: QueueView(
            contentOnly: true,
            hideHeader: true,
            backgroundColor: Colors.transparent,
          ),
        );

      case OriginalDesktopMode.lyrics:
        final lyricsProvider = context.watch<LyricsProvider>();
        return _OriginalLyricsContainer(
          trackId: track?.id,
          lyricsProvider: lyricsProvider,
        );
    }
  }
}

/// Container for lyrics mode with hoverable inline delay editor.
class _OriginalLyricsContainer extends StatefulWidget {
  final String? trackId;
  final LyricsProvider lyricsProvider;

  const _OriginalLyricsContainer({
    required this.trackId,
    required this.lyricsProvider,
  });

  @override
  State<_OriginalLyricsContainer> createState() =>
      _OriginalLyricsContainerState();
}

class _OriginalLyricsContainerState extends State<_OriginalLyricsContainer> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            child: LyricsView(hideHeader: true),
          ),
          if (widget.trackId != null)
            Positioned(
              top: 8,
              right: 16,
              child: InlineDelayEditor(
                lyricsProvider: widget.lyricsProvider,
                trackId: widget.trackId!,
                visible: _isHovered,
                liquidGlass: true,
              ),
            ),
        ],
      ),
    );
  }
}

/// Realistic grooved vinyl disc with light sheen reflections and mechanical tonearm.
/// Features FocusFreezeBuilder caching when unfocused based on user preferences.
class _VinylDiscWidget extends StatelessWidget {
  final String thumbnailUrl;
  final AnimationController rotationController;
  final Animation<double> tonearmAnimation;

  const _VinylDiscWidget({
    required this.thumbnailUrl,
    required this.rotationController,
    required this.tonearmAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.rotatingAlbumArtFullScreen,
      ),
    );

    if (freezeWhenUnfocused) {
      return FocusFreezeBuilder<double>(
        value: rotationController.value,
        builder: (context, _) => _buildTurntable(context),
      );
    }

    return _buildTurntable(context);
  }

  Widget _buildTurntable(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final totalHeight = constraints.maxHeight;
        final discDiameter = math
            .min(totalWidth * 0.70, totalHeight * 0.88)
            .clamp(260.0, 480.0);

        // Center vinyl disc on left-center of mode area to leave room for tonearm
        final discCenterX = totalWidth * 0.38;
        final discCenterY = totalHeight * 0.50;
        final discRadius = discDiameter / 2;

        // Tonearm pivot location mounted outside the top-right of the record
        final pivotOffset = Offset(
          discCenterX + discRadius * 1.18,
          discCenterY - discRadius * 0.82,
        );
        final tonearmLength = discRadius * 1.22;

        return SizedBox(
          width: totalWidth,
          height: totalHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Vinyl disc ambient shadow
              Positioned(
                left: discCenterX - (discDiameter * 0.47),
                top: discCenterY - (discDiameter * 0.47),
                width: discDiameter * 0.94,
                height: discDiameter * 0.94,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.65),
                        blurRadius: 36,
                        spreadRadius: 6,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Rotating Vinyl Body
              Positioned(
                left: discCenterX - discRadius,
                top: discCenterY - discRadius,
                width: discDiameter,
                height: discDiameter,
                child: RotationTransition(
                  turns: rotationController,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Base vinyl black disc
                      Container(
                        width: discDiameter,
                        height: discDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [
                              Color(0xFF161616),
                              Color(0xFF0F0F0F),
                              Color(0xFF070707),
                            ],
                            stops: [0.4, 0.85, 1.0],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 1.5,
                          ),
                        ),
                      ),

                      // Grooves and specular sheen lines
                      CustomPaint(
                        size: Size(discDiameter, discDiameter),
                        painter: _VinylGroovesPainter(diameter: discDiameter),
                      ),

                      // Center Label (Track Thumbnail)
                      _buildCenterLabel(discDiameter),

                      // Spindle hole
                      Container(
                        width: discDiameter * 0.05,
                        height: discDiameter * 0.05,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0A0A0A),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Tonearm overlay with mechanical pivot and cueing animation
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: tonearmAnimation,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _TonearmPainter(
                        pivot: pivotOffset,
                        armLength: tonearmLength,
                        progress: tonearmAnimation.value,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCenterLabel(double diameter) {
    final labelSize = diameter * 0.38;

    return Container(
      width: labelSize,
      height: labelSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.20),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: thumbnailUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: thumbnailUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => _buildPlaceholderLabel(),
              )
            : _buildPlaceholderLabel(),
      ),
    );
  }

  Widget _buildPlaceholderLabel() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: const Center(
        child: Icon(Symbols.music_note, color: Colors.white30, size: 32),
      ),
    );
  }
}

/// Custom painter for authentic concentric vinyl grooves and sheen highlights.
class _VinylGroovesPainter extends CustomPainter {
  final double diameter;

  _VinylGroovesPainter({required this.diameter});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final labelRadius = radius * 0.38;

    // Draw concentric groove rings
    final groovePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final denseGroovePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    double currentRadius = labelRadius + 10;
    int ringIndex = 0;
    while (currentRadius < radius - 6) {
      final isAccentRing = ringIndex % 6 == 0;
      canvas.drawCircle(
        center,
        currentRadius,
        isAccentRing ? denseGroovePaint : groovePaint,
      );
      currentRadius += isAccentRing ? 5.0 : 3.5;
      ringIndex++;
    }

    // Specular sheen reflections (two opposing light sheen wedges across the grooves)
    final sheenPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.02),
          Colors.transparent,
        ],
        stops: const [0.4, 0.8, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    // Sheen wedge 1
    final path1 = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius - 4),
        -math.pi / 4,
        math.pi / 3,
        false,
      )
      ..close();
    canvas.drawPath(path1, sheenPaint);

    // Sheen wedge 2 (opposing side)
    final path2 = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius - 4),
        3 * math.pi / 4,
        math.pi / 3,
        false,
      )
      ..close();
    canvas.drawPath(path2, sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) {
    return oldDelegate.diameter != diameter;
  }
}

/// Custom painter for authentic turntable tonearm with counterweight,
/// curved arm, rest cradle, headshell, and animated cueing onto the record.
class _TonearmPainter extends CustomPainter {
  final Offset pivot;
  final double armLength;
  final double progress; // 0.0 (rest cradle) to 1.0 (on record grooves)

  _TonearmPainter({
    required this.pivot,
    required this.armLength,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Current rotation angle:
    // When paused (progress 0.0), tonearm sits in the cradle completely off the vinyl.
    // When playing (progress 1.0), tonearm pivots onto the outer music grooves of the vinyl.
    const restAngle = -0.02; // off the vinyl entirely
    const playingAngle = 0.31; // rests on the outer grooves of the vinyl
    final angle = restAngle + (playingAngle - restAngle) * progress;

    // Draw rest cradle
    final cradleDist = armLength * 0.65;
    final restCradlePos = Offset(
      pivot.dx - math.sin(restAngle) * cradleDist,
      pivot.dy + math.cos(restAngle) * cradleDist,
    );
    _drawRestCradle(canvas, restCradlePos);

    // Save canvas, translate to pivot, rotate
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);

    // 1. Counterweight (behind pivot, upwards)
    final counterWeightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFFDDDDDD), Color(0xFF888888), Color(0xFFEEEEEE)],
      ).createShader(const Rect.fromLTWH(-11, -38, 22, 28));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-11, -38, 22, 28),
        const Radius.circular(4),
      ),
      counterWeightPaint,
    );
    // Counterweight ring markings
    final linePaint = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(-11, -25), const Offset(11, -25), linePaint);

    // 2. Arm shadow (projected down onto record)
    final shadowPath = Path()
      ..moveTo(2, 6)
      ..cubicTo(-8, armLength * 0.35, 14, armLength * 0.70, -4, armLength);
    final armShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(shadowPath, armShadowPaint);

    // 3. Metallic tonearm rod (classic curved S/J arm)
    final armPath = Path()
      ..moveTo(0, 4)
      ..cubicTo(-10, armLength * 0.35, 12, armLength * 0.70, -6, armLength);
    final armPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFEEEEEE), Color(0xFFCCCCCC), Color(0xFFFFFFFF)],
      ).createShader(Rect.fromLTWH(-12, 0, 24, armLength))
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(armPath, armPaint);

    // 4. Headshell & Cartridge at the tip (Offset(-6, armLength))
    final tip = Offset(-6, armLength);
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(0.20); // slight offset angle for stylus alignment

    // Headshell body
    const headshellRect = Rect.fromLTWH(-6, 0, 12, 26);
    final headshellPaint = Paint()..color = const Color(0xFF1E1E1E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(headshellRect, const Radius.circular(3)),
      headshellPaint,
    );
    // Silver connector band
    final bandPaint = Paint()..color = const Color(0xFFCCCCCC);
    canvas.drawRect(const Rect.fromLTWH(-5, 0, 10, 4), bandPaint);

    // Finger lift hook
    final fingerLiftPaint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fingerLiftPath = Path()
      ..moveTo(6, 12)
      ..quadraticBezierTo(14, 10, 15, 4);
    canvas.drawPath(fingerLiftPath, fingerLiftPaint);

    // Stylus cartridge tip (red accent)
    final stylusPaint = Paint()..color = const Color(0xFFEE3333);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-3, 20, 6, 8),
        const Radius.circular(1.5),
      ),
      stylusPaint,
    );

    canvas.restore();

    // 5. Pivot gimbal base (circular chrome bearing at (0, 0))
    final pivotBasePaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFEEEEEE), Color(0xFF888888), Color(0xFF555555)],
      ).createShader(const Rect.fromLTWH(-16, -16, 32, 32));
    canvas.drawCircle(Offset.zero, 16, pivotBasePaint);

    final pivotCapPaint = Paint()..color = const Color(0xFF222222);
    canvas.drawCircle(Offset.zero, 7, pivotCapPaint);

    final screwPaint = Paint()..color = const Color(0xFFCCCCCC);
    canvas.drawCircle(Offset.zero, 3, screwPaint);

    canvas.restore();
  }

  void _drawRestCradle(Canvas canvas, Offset pos) {
    final cradlePaint = Paint()
      ..color = const Color(0xFF666666)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    // Small U-shaped fork
    final path = Path()
      ..moveTo(pos.dx - 6, pos.dy - 4)
      ..lineTo(pos.dx - 6, pos.dy + 4)
      ..lineTo(pos.dx + 6, pos.dy + 4)
      ..lineTo(pos.dx + 6, pos.dy - 4);
    canvas.drawPath(path, cradlePaint);

    // Post to ground
    final postPaint = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 4.0;
    canvas.drawLine(
      Offset(pos.dx, pos.dy + 4),
      Offset(pos.dx, pos.dy + 12),
      postPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pivot != pivot ||
        oldDelegate.armLength != armLength;
  }
}
