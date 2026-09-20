import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/providers/preferences/preferences_provider.dart';
import 'package:wisp/services/app_focus_service.dart';

class PlayingWaveform extends StatefulWidget {
  final Color color;
  final double size;
  final Duration period;
  final bool active;

  const PlayingWaveform({
    super.key,
    required this.color,
    this.size = 16,
    this.period = const Duration(milliseconds: 900),
    this.active = true,
  });

  @override
  State<PlayingWaveform> createState() => _PlayingWaveformState();
}

class _PlayingWaveformState extends State<PlayingWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Whether the "freeze while unfocused" behavior is turned on for this
  // widget, per the user's preference. Kept in sync from build().
  bool _freezeWhenUnfocused = false;

  static const _phases = [0.0, 1.4, 2.8];
  static const _minHeightFactor = 0.25;
  static const _maxHeightFactor = 0.875;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    if (widget.active) {
      _controller.repeat();
    }
    AppFocusService.instance.isFocused.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant PlayingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _applyFocusState();
    }
  }

  @override
  void dispose() {
    AppFocusService.instance.isFocused.removeListener(_handleFocusChanged);
    _controller.dispose();
    super.dispose();
  }

  // Freeze the waveform animation while the app/window is unfocused instead
  // of continuing to tick it off-screen, but only when the user has enabled
  // that behavior for this widget in preferences.
  void _handleFocusChanged() {
    if (!mounted) return;
    _applyFocusState();
  }

  void _applyFocusState() {
    final shouldAnimate = widget.active &&
        (!_freezeWhenUnfocused || AppFocusService.instance.isFocused.value);
    if (shouldAnimate) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop(canceled: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final freezeWhenUnfocused = context.select<PreferencesProvider, bool>(
      (prefs) => prefs.pausedBackgroundWidgetsEnabled.contains(
        PausedBackgroundWidget.animatedWaveform,
      ),
    );
    if (freezeWhenUnfocused != _freezeWhenUnfocused) {
      _freezeWhenUnfocused = freezeWhenUnfocused;
      _applyFocusState();
    }

    final minHeight = widget.size * _minHeightFactor;
    final maxHeight = widget.size * _maxHeightFactor;
    final barWidth = widget.size * 0.19;
    final spacing = widget.size * 0.125;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * 2 * pi;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _phases.length; i++) ...[
                  if (i != 0) SizedBox(width: spacing),
                  Container(
                    width: barWidth,
                    height:
                        minHeight +
                        ((sin(t + _phases[i]) + 1) / 2) *
                            (maxHeight - minHeight),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(barWidth / 2),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
