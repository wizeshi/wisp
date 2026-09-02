import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_focus_service.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.builder,
    this.gap = 24.0,
    this.scrollSpeed = 40.0,
    this.pauseDuration = const Duration(seconds: 3),
    this.pauseWhenUnfocused = false,
  });

  final String text;
  final TextStyle style;
  final Widget Function(BuildContext context, TextStyle style)? builder;
  final double gap;
  final double scrollSpeed;
  final Duration pauseDuration;
  final bool pauseWhenUnfocused;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
  )..addStatusListener(_handleAnimationStatus);

  Timer? _pauseTimer;
  double _viewportWidth = 0;
  double _textWidth = 0;
  double _textHeight = 0;
  double _pendingViewportWidth = 0;
  double _pendingTextWidth = 0;
  double _pendingTextHeight = 0;
  bool _pendingHasOverflow = false;
  bool _hasOverflow = false;
  bool _metricsUpdateScheduled = false;
  bool _focusListenerAttached = false;
  bool _isHolding = false;

  bool get _canAnimate => _hasOverflow && mounted;

  bool get _shouldPauseForFocus =>
      widget.pauseWhenUnfocused && !AppFocusService.instance.isFocused.value;

  @override
  void initState() {
    super.initState();
    _attachFocusListenerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.pauseWhenUnfocused != widget.pauseWhenUnfocused) {
      _attachFocusListenerIfNeeded();
      _applyFocusState();
    }

    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _resetAnimationState();
    }
  }

  @override
  void dispose() {
    if (_focusListenerAttached) {
      AppFocusService.instance.isFocused.removeListener(_handleFocusChanged);
    }
    _pauseTimer?.cancel();
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  void _attachFocusListenerIfNeeded() {
    if (widget.pauseWhenUnfocused) {
      if (!_focusListenerAttached) {
        AppFocusService.instance.isFocused.addListener(_handleFocusChanged);
        _focusListenerAttached = true;
      }
    } else if (_focusListenerAttached) {
      AppFocusService.instance.isFocused.removeListener(_handleFocusChanged);
      _focusListenerAttached = false;
    }
  }

  void _handleFocusChanged() {
    _applyFocusState();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _controller.value = 0.0;
      _startHoldPhase();
    }
  }

  void _applyFocusState() {
    if (!mounted) return;

    if (_shouldPauseForFocus) {
      _pauseTimer?.cancel();
      _pauseTimer = null;
      if (_controller.isAnimating) {
        _controller.stop(canceled: false);
      }
      return;
    }

    if (_isHolding) {
      if (_pauseTimer == null || !_pauseTimer!.isActive) {
        _startHoldPhase();
      }
    } else if (_canAnimate && !_controller.isAnimating) {
      _startScrolling();
    }
  }

  void _startHoldPhase() {
    if (!mounted) return;
    _isHolding = true;
    _pauseTimer?.cancel();

    if (!_canAnimate || _shouldPauseForFocus) return;

    _pauseTimer = Timer(widget.pauseDuration, () {
      if (!mounted) return;
      _isHolding = false;
      _pauseTimer = null;
      _startScrolling();
    });
  }

  void _startScrolling() {
    if (!_canAnimate || _shouldPauseForFocus || _isHolding) return;

    final distance = _textWidth + widget.gap;
    final durationMs = (distance / widget.scrollSpeed * 1000).round();
    _controller.duration = Duration(milliseconds: durationMs < 1 ? 1 : durationMs);
    _controller.forward(from: _controller.value);
  }

  void _resetAnimationState() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _isHolding = false;
    _controller
      ..stop(canceled: false)
      ..value = 0;
  }

  void _scheduleMetricsUpdate({
    required double viewportWidth,
    required double textWidth,
    required double textHeight,
    required bool hasOverflow,
  }) {
    final unchanged =
        _viewportWidth == viewportWidth &&
        _textWidth == textWidth &&
        _textHeight == textHeight &&
        _hasOverflow == hasOverflow;
    if (unchanged) return;

    _pendingViewportWidth = viewportWidth;
    _pendingTextWidth = textWidth;
    _pendingTextHeight = textHeight;
    _pendingHasOverflow = hasOverflow;

    if (_metricsUpdateScheduled) return;

    _metricsUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsUpdateScheduled = false;
      if (!mounted) return;

      final changed =
          _viewportWidth != _pendingViewportWidth ||
          _textWidth != _pendingTextWidth ||
          _textHeight != _pendingTextHeight ||
          _hasOverflow != _pendingHasOverflow;
      if (!changed) return;

      _viewportWidth = _pendingViewportWidth;
      _textWidth = _pendingTextWidth;
      _textHeight = _pendingTextHeight;
      _hasOverflow = _pendingHasOverflow;

      _resetAnimationState();
      setState(() {});
      _startHoldPhase();
    });
  }

  Widget _buildTextChild(BuildContext context) {
    if (widget.builder != null) {
      return widget.builder!(context, widget.style);
    }
    return Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.visible,
      softWrap: false,
      style: widget.style,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final viewportWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : textPainter.width;
        final hasOverflow =
            constraints.hasBoundedWidth && textPainter.width > viewportWidth;

        _scheduleMetricsUpdate(
          viewportWidth: viewportWidth,
          textWidth: textPainter.width,
          textHeight: textPainter.height,
          hasOverflow: hasOverflow,
        );

        final textChild = _buildTextChild(context);

        if (!hasOverflow) {
          return textChild;
        }

        final singleWidth = textPainter.width + widget.gap;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final currentOffset = _controller.value * singleWidth;

            return SizedBox(
              width: viewportWidth,
              height: textPainter.height,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: -currentOffset,
                      top: 0,
                      child: textChild,
                    ),
                    Positioned(
                      left: -currentOffset + singleWidth,
                      top: 0,
                      child: textChild,
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