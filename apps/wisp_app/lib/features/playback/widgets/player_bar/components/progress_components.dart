// Copyright © 2026 wizeshi

part of '../../player_bar.dart';

/// Top-margin edge-to-edge scrubbing bar shared by the Original (M3E) and
/// Apple Music desktop player bars. Only the accent color differs.
class _PlayerBarTopProgressBar extends StatefulWidget {
  final Color accentColor;

  const _PlayerBarTopProgressBar({required this.accentColor});

  @override
  State<_PlayerBarTopProgressBar> createState() =>
      _PlayerBarTopProgressBarState();
}

class _PlayerBarTopProgressBarState
    extends State<_PlayerBarTopProgressBar> {
  bool _isHovering = false;
  bool _isDragging = false;
  double? _hoverRelativeX;

  void _seekTo(double relativeX, Duration duration) {
    final clamped = relativeX.clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (clamped * duration.inMilliseconds).round(),
    );
    context.read<PlaybackCoordinator>().seek(target);
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.accentColor;
    final coordinator = context.read<PlaybackCoordinator>();
    final player = context.read<global_audio_player.WispAudioHandler>();

    return Selector<global_audio_player.WispAudioHandler, ({Duration duration, bool isLoading})>(
      selector: (context, p) => (
        duration: p.duration,
        isLoading: p.isLoading || p.isBuffering,
      ),
      builder: (context, meta, child) {
        final shouldFreeze = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
            PausedBackgroundWidget.playerProgressBar,
          ),
        );

        return ValueListenableBuilder<Duration>(
          valueListenable: coordinator.effectivePositionListenable,
          builder: (context, position, _) {
            final data = _PositionData(
              position: position,
              bufferedPosition: player.bufferedPosition,
              duration: meta.duration,
              isLoading: meta.isLoading,
            );

            if (shouldFreeze && !_isHovering && !_isDragging) {
              return FocusFreezeBuilder<_PositionData>(
                value: data,
                builder: (context, frozenData) {
                  return _buildBarContent(context, frozenData, activeColor);
                },
              );
            }

            return RepaintBoundary(
              child: _buildBarContent(context, data, activeColor),
            );
          },
        );
      },
    );
  }

  Widget _buildBarContent(
    BuildContext context,
    _PositionData data,
    Color activeColor,
  ) {
    final duration = data.duration;
    final position = data.position;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final bufferedProgress = duration.inMilliseconds > 0
        ? (data.bufferedPosition.inMilliseconds / duration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    final colors = context.colors;
    final barHeight = (_isHovering || _isDragging) ? 6.0 : 3.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() {
        _isHovering = false;
        _hoverRelativeX = null;
      }),
      onHover: (event) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.size.width > 0) {
          setState(() {
            _hoverRelativeX = (event.localPosition.dx / box.size.width)
                .clamp(0.0, 1.0);
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null && box.size.width > 0) {
            final rel = details.localPosition.dx / box.size.width;
            _seekTo(rel, duration);
          }
        },
        onHorizontalDragStart: (_) => setState(() => _isDragging = true),
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null && box.size.width > 0) {
            final rel = details.localPosition.dx / box.size.width;
            setState(() => _hoverRelativeX = rel.clamp(0.0, 1.0));
            _seekTo(rel, duration);
          }
        },
        onHorizontalDragEnd: (_) {
          setState(() => _isDragging = false);
        },
        child: SizedBox(
          height: 14, // Generous interactive hit target along the top border
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // Progress line: clean flat bar across both M3E and Apple
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                height: barHeight,
                width: double.infinity,
                color: colors.borderSubtle,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (bufferedProgress > progress)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: bufferedProgress,
                          child: Container(
                            color: colors.textPrimary.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: activeColor,
                            boxShadow: [
                              if (_isHovering || _isDragging)
                                BoxShadow(
                                  color: activeColor.withValues(alpha: 0.4),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Hover scrub thumbnail tooltip
              if ((_isHovering || _isDragging) &&
                  _hoverRelativeX != null &&
                  duration.inMilliseconds > 0)
                Positioned(
                  top: 10,
                  left: (_hoverRelativeX! *
                          (MediaQuery.sizeOf(context).width - 60))
                      .clamp(8.0, MediaQuery.sizeOf(context).width - 68),
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: colors.borderSubtle,
                          width: 0.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        _formatDuration(
                          Duration(
                            milliseconds: (_hoverRelativeX! *
                                    duration.inMilliseconds)
                                .round(),
                          ),
                        ),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerBarCircularProgressRing extends StatelessWidget {
  final Color ringColor;
  final bool isLoading;

  const _PlayerBarCircularProgressRing({
    required this.ringColor,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final trackColor = context.colors.borderSubtle;
    if (isLoading) {
      return SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          backgroundColor: trackColor,
          valueColor: AlwaysStoppedAnimation<Color>(ringColor),
        ),
      );
    }

    final coordinator = context.read<PlaybackCoordinator>();
    return Selector<global_audio_player.WispAudioHandler, Duration>(
      selector: (context, player) => player.duration,
      builder: (context, duration, _) {
        final shouldFreeze = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
            PausedBackgroundWidget.playerProgressBar,
          ),
        );

        return ValueListenableBuilder<Duration>(
          valueListenable: coordinator.effectivePositionListenable,
          builder: (context, position, _) {
            final data = _PositionData(
              position: position,
              duration: duration,
              isLoading: false,
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
                  return _buildRing(fProgress, trackColor);
                },
              );
            }

            final progress = duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds)
                    .clamp(0.0, 1.0)
                : 0.0;
            return _buildRing(progress, trackColor);
          },
        );
      },
    );
  }

  Widget _buildRing(double progress, Color trackColor) {
    return SizedBox(
      width: 40,
      height: 40,
      child: CircularProgressIndicator(
        value: progress,
        strokeWidth: 2.5,
        backgroundColor: trackColor,
        valueColor: AlwaysStoppedAnimation<Color>(ringColor),
      ),
    );
  }
}
