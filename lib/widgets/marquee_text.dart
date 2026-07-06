import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../services/app_focus_service.dart';

class MarqueeText extends StatefulWidget {
	const MarqueeText({
		super.key,
		required this.text,
		required this.style,
		this.pauseWhenUnfocused = false,
	});

	final String text;
	final TextStyle style;
	final bool pauseWhenUnfocused;

	@override
	State<MarqueeText> createState() => _MarqueeTextState();
}

enum _MarqueePhase { entering, holding, exiting }

class _MarqueeTextState extends State<MarqueeText>
		with SingleTickerProviderStateMixin {
	static const Duration _pauseDuration = Duration(seconds: 3);
	static const double _scrollSpeed = 40.0;
	static const double _gap = 24.0;

	late final AnimationController _controller = AnimationController(
		vsync: this,
		lowerBound: 0,
		upperBound: 1,
	)..addStatusListener(_handleAnimationStatus);

	final Stopwatch _pauseStopwatch = Stopwatch();

	Timer? _pauseTimer;
	_MarqueePhase _phase = _MarqueePhase.entering;
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
		_pauseStopwatch.stop();
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
			_handlePhaseCompleted();
		}
	}

	void _handlePhaseCompleted() {
		switch (_phase) {
			case _MarqueePhase.entering:
				_beginHoldingPhase();
				break;
			case _MarqueePhase.holding:
				_beginExitingPhase();
				break;
			case _MarqueePhase.exiting:
				_beginEnteringPhase();
				break;
		}
	}

	void _applyFocusState() {
		if (!mounted) {
			return;
		}

		if (_shouldPauseForFocus) {
			_pauseForFocusLoss();
			return;
		}

		switch (_phase) {
			case _MarqueePhase.entering:
			case _MarqueePhase.exiting:
				_startScrollingIfNeeded();
				break;
			case _MarqueePhase.holding:
				_startOrResumeHold();
				break;
		}
	}

	void _beginEnteringPhase() {
		if (!mounted) {
			return;
		}

		_phase = _MarqueePhase.entering;
		_controller.duration = _durationForDistance(_viewportWidth);
		_pauseTimer?.cancel();
		_pauseTimer = null;
		_pauseStopwatch
			..reset()
			..stop();
		_controller
			..stop(canceled: false)
			..value = 0;
		_startScrollingIfNeeded();
	}

	void _beginHoldingPhase() {
		if (!mounted) {
			return;
		}

		_phase = _MarqueePhase.holding;
		_pauseTimer?.cancel();
		_pauseTimer = null;
		_pauseStopwatch
			..reset()
			..start();
		_startOrResumeHold();
	}

	void _beginExitingPhase() {
		if (!mounted) {
			return;
		}

		_phase = _MarqueePhase.exiting;
		_controller.duration = _durationForDistance(_textWidth + _gap);
		_pauseTimer?.cancel();
		_pauseTimer = null;
		_pauseStopwatch
			..reset()
			..stop();
		_controller
			..stop(canceled: false)
			..value = 0;
		_startScrollingIfNeeded();
	}

	void _startOrResumeHold() {
		if (_shouldPauseForFocus) {
			return;
		}

		_pauseTimer?.cancel();
		_pauseTimer = Timer(_remainingHoldDuration, _finishHold);
	}

	Duration get _remainingHoldDuration {
		if (_phase != _MarqueePhase.holding) {
			return _pauseDuration;
		}

		final remaining = _pauseDuration - _pauseStopwatch.elapsed;
		if (remaining.isNegative || remaining == Duration.zero) {
			return Duration.zero;
		}

		return remaining;
	}

	void _finishHold() {
		if (!mounted) {
			return;
		}

		_pauseTimer?.cancel();
		_pauseTimer = null;
		_pauseStopwatch
			..stop()
			..reset();
		if (_phase != _MarqueePhase.holding) {
			return;
		}

		if (!_canAnimate || _shouldPauseForFocus) {
			return;
		}

		_beginExitingPhase();
	}

	void _pauseForFocusLoss() {
		if (_phase == _MarqueePhase.holding) {
			if (_pauseTimer != null) {
				_pauseTimer?.cancel();
				_pauseTimer = null;
				_pauseStopwatch.stop();
			}
			return;
		}

		if (_controller.isAnimating) {
			_controller.stop(canceled: false);
		}
	}

	void _startScrollingIfNeeded() {
		if (!_canAnimate || _phase == _MarqueePhase.holding || _controller.isAnimating) {
			return;
		}

		_controller.forward(from: _controller.value);
	}

	Duration _durationForDistance(double distance) {
		final durationMs = (distance / _scrollSpeed * 1000).round();
		return Duration(milliseconds: durationMs < 1 ? 1 : durationMs);
	}

	void _resetAnimationState() {
		_pauseTimer?.cancel();
		_pauseTimer = null;
		_pauseStopwatch
			..stop()
			..reset();
		_phase = _MarqueePhase.entering;
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
		final unchanged = _viewportWidth == viewportWidth &&
				_textWidth == textWidth &&
				_textHeight == textHeight &&
				_hasOverflow == hasOverflow;
		if (unchanged) {
			return;
		}

		_pendingViewportWidth = viewportWidth;
		_pendingTextWidth = textWidth;
		_pendingTextHeight = textHeight;
		_pendingHasOverflow = hasOverflow;

		if (_metricsUpdateScheduled) {
			return;
		}

		_metricsUpdateScheduled = true;
		WidgetsBinding.instance.addPostFrameCallback((_) {
			_metricsUpdateScheduled = false;
			if (!mounted) {
				return;
			}

			final changed = _viewportWidth != _pendingViewportWidth ||
					_textWidth != _pendingTextWidth ||
					_textHeight != _pendingTextHeight ||
					_hasOverflow != _pendingHasOverflow;
			if (!changed) {
				return;
			}

			_viewportWidth = _pendingViewportWidth;
			_textWidth = _pendingTextWidth;
			_textHeight = _pendingTextHeight;
			_hasOverflow = _pendingHasOverflow;
			_resetAnimationState();
			setState(() {});
			_beginEnteringPhase();
		});
	}

	Text _buildText(BuildContext context) {
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
					text: TextSpan(
						text: widget.text,
						style: widget.style,
					),
					maxLines: 1,
					textDirection: Directionality.of(context),
					textScaler: MediaQuery.textScalerOf(context),
				)..layout();

				final viewportWidth = constraints.hasBoundedWidth
						? constraints.maxWidth
						: textPainter.width;
				final hasOverflow = constraints.hasBoundedWidth &&
						textPainter.width > viewportWidth;

				_scheduleMetricsUpdate(
					viewportWidth: viewportWidth,
					textWidth: textPainter.width,
					textHeight: textPainter.height,
					hasOverflow: hasOverflow,
				);

				if (!hasOverflow) {
					return _buildText(context);
				}

				return AnimatedBuilder(
					animation: _controller,
					child: _buildText(context),
					builder: (context, child) {
						double startX;
						double endX;
						switch (_phase) {
							case _MarqueePhase.entering:
								startX = viewportWidth;
								endX = 0.0;
								break;
							case _MarqueePhase.holding:
								startX = 0.0;
								endX = 0.0;
								break;
							case _MarqueePhase.exiting:
								startX = 0.0;
								endX = -(textPainter.width + _gap);
								break;
						}
						final currentX = lerpDouble(startX, endX, _controller.value) ??
								startX;

						return SizedBox(
							width: viewportWidth,
							height: textPainter.height,
							child: ClipRect(
								child: Stack(
									clipBehavior: Clip.hardEdge,
									children: [
										Positioned(
											left: currentX,
											top: -2,
											child: child!,
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
