import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_focus_service.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool pauseWhenUnfocused;

  const MarqueeText({
    required this.text,
    required this.style,
    this.pauseWhenUnfocused = false,
    super.key,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  double _scrollDistance = 0;
  bool _needsMarquee = false;
  Timer? _pauseTimer;
  AppFocusService? _focusService;
  bool _isFocused = true;

  bool get _shouldPauseForFocus =>
      widget.pauseWhenUnfocused && _isFocused == false;

  @override
  void initState() {
    super.initState();
    _syncFocusListener();
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pauseWhenUnfocused != widget.pauseWhenUnfocused) {
      _syncFocusListener();
    }
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _configureController(forceStop: true);
    }
  }

  @override
  void dispose() {
    _focusService?.isFocused.removeListener(_handleFocusChange);
    _pauseTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _syncFocusListener() {
    if (!widget.pauseWhenUnfocused) {
      _focusService?.isFocused.removeListener(_handleFocusChange);
      _focusService = null;
      _isFocused = true;
      return;
    }

    final focusService = AppFocusService.instance;
    if (_focusService == focusService) {
      _isFocused = focusService.isFocused.value;
      return;
    }

    _focusService?.isFocused.removeListener(_handleFocusChange);
    _focusService = focusService;
    _isFocused = focusService.isFocused.value;
    focusService.isFocused.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    final focusService = _focusService;
    if (focusService == null) return;

    final focused = focusService.isFocused.value;
    if (focused == _isFocused) return;
    _isFocused = focused;
    if (!_isFocused) {
      _pauseTimer?.cancel();
      _controller?.stop();
      return;
    }
    _configureController();
  }

  void _configureController({bool forceStop = false}) {
    if (!_needsMarquee || forceStop || _shouldPauseForFocus) {
      _pauseTimer?.cancel();
      _controller?.stop();
      if (_controller != null) {
        _controller!.value = 0;
      }
    }
    if (!_needsMarquee || _shouldPauseForFocus) return;

    _controller ??= AnimationController(vsync: this)
      ..addStatusListener(_handleStatusChange);
    final ms = ((_scrollDistance / 24) * 1000).clamp(2400, 12000).toInt();
    _controller!.duration = Duration(milliseconds: ms);
    _scheduleStart();
  }

  void _handleStatusChange(AnimationStatus status) {
    if (!_needsMarquee) return;
    if (status == AnimationStatus.completed) {
      _pauseThen(() => _controller?.reverse());
    } else if (status == AnimationStatus.dismissed) {
      _pauseThen(() => _controller?.forward());
    }
  }

  void _pauseThen(VoidCallback action) {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || !_needsMarquee || _shouldPauseForFocus) return;
      action();
    });
  }

  void _scheduleStart() {
    if (_controller == null) return;
    _pauseTimer?.cancel();
    _controller!.value = 0;
    _pauseThen(() => _controller?.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final maxWidth = constraints.maxWidth;
        final textWidth = textPainter.width;
        final needsMarquee = textWidth > maxWidth;
        const endPadding = 8.0;
        final scrollDistance = (textWidth - maxWidth + endPadding)
            .clamp(0, textWidth)
            .toDouble();

        if (_needsMarquee != needsMarquee ||
            _scrollDistance != scrollDistance) {
          _needsMarquee = needsMarquee;
          _scrollDistance = scrollDistance;
          _configureController();
        }

        if (!needsMarquee) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller ?? const AlwaysStoppedAnimation<double>(0),
            builder: (context, child) {
              final value = _controller?.value ?? 0;
              final dx = -value * _scrollDistance;
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
        );
      },
    );
  }
}