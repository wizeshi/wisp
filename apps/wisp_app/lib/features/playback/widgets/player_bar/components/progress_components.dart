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

    return Selector<global_audio_player.WispAudioHandler, _PositionData>(
      selector: (context, player) => _PositionData(
        position: player.throttledPosition,
        duration: player.duration,
        isLoading: player.isLoading || player.isBuffering,
      ),
      builder: (context, data, child) {
        final shouldFreeze = context.select<PreferencesProvider, bool>(
          (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
            PausedBackgroundWidget.playerProgressBar,
          ),
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
                color: Colors.white.withValues(alpha: 0.08),
                child: Align(
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
              ),

              // Hover scrub thumbnail tooltip
              if ((_isHovering || _isDragging) &&
                  _hoverRelativeX != null &&
                  duration.inMilliseconds > 0)
                Positioned(
                  top: 10,
                  left: (_hoverRelativeX! *
                          (MediaQuery.of(context).size.width - 60))
                      .clamp(8.0, MediaQuery.of(context).size.width - 68),
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 0.6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
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
                        style: const TextStyle(
                          color: Colors.white,
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
    if (isLoading) {
      return SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          backgroundColor: Colors.white.withValues(alpha: 0.16),
          valueColor: AlwaysStoppedAnimation<Color>(ringColor),
        ),
      );
    }

    final effectivePosition =
        context.select<PlaybackCoordinator, Duration>(
      (c) => c.effectiveThrottledPosition,
    );
    final duration = context.select<global_audio_player.WispAudioHandler,
        Duration>(
      (player) => player.duration,
    );

    final shouldFreeze = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.playerProgressBar,
      ),
    );

    if (shouldFreeze) {
      return FocusFreezeBuilder<(int, int)>(
        value: (effectivePosition.inMilliseconds, duration.inMilliseconds),
        builder: (context, frozenVal) {
          final progress = frozenVal.$2 > 0
              ? (frozenVal.$1 / frozenVal.$2).clamp(0.0, 1.0)
              : 0.0;
          return _buildRing(progress);
        },
      );
    }

    final progress = duration.inMilliseconds > 0
        ? (effectivePosition.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    return _buildRing(progress);
  }

  Widget _buildRing(double progress) {
    return SizedBox(
      width: 40,
      height: 40,
      child: CircularProgressIndicator(
        value: progress,
        strokeWidth: 2.5,
        backgroundColor: Colors.white.withValues(alpha: 0.16),
        valueColor: AlwaysStoppedAnimation<Color>(ringColor),
      ),
    );
  }
}
