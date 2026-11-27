// Copyright © 2026 wizeshi

import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/system/app_focus_service.dart';

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
        child: CustomPaint(
          painter: _PlayingWaveformPainter(
            animation: _controller,
            color: widget.color,
            minHeight: minHeight,
            maxHeight: maxHeight,
            barWidth: barWidth,
            spacing: spacing,
          ),
        ),
      ),
    );
  }
}

class _PlayingWaveformPainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;
  final double minHeight;
  final double maxHeight;
  final double barWidth;
  final double spacing;

  static const _phases = [0.0, 1.4, 2.8];

  _PlayingWaveformPainter({
    required this.animation,
    required this.color,
    required this.minHeight,
    required this.maxHeight,
    required this.barWidth,
    required this.spacing,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * 2 * pi;
    final totalWidth =
        barWidth * _phases.length + spacing * (_phases.length - 1);
    var x = (size.width - totalWidth) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final radius = Radius.circular(barWidth / 2);

    for (var i = 0; i < _phases.length; i++) {
      final barHeight =
          minHeight + ((sin(t + _phases[i]) + 1) / 2) * (maxHeight - minHeight);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - barHeight, barWidth, barHeight),
        radius,
      );
      canvas.drawRRect(rect, paint);
      x += barWidth + spacing;
    }
  }

  @override
  bool shouldRepaint(covariant _PlayingWaveformPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.minHeight != minHeight ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.barWidth != barWidth ||
        oldDelegate.spacing != spacing ||
        !identical(oldDelegate.animation, animation);
  }
}
