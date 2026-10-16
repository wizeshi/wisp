// Copyright © 2026 wizeshi

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_provider.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/services/system/app_focus_service.dart';

/// Renders a single lyrics line with word/syllable-level fill animations (karaoke style)
/// based on the Wisp Lyrics Format.
///
/// Dual-layer text rendering ensures zero layout shift while syllables fill continuously
/// from left to right at display VSYNC framerate via [LyricsLineFillClipper].
///
/// Falls back gracefully to discrete line highlighting when word timestamps are unavailable,
/// and plain text when unsynced.
class WordFillLyricsLine extends StatefulWidget {
  final LyricsLine line;
  final TextStyle? textStyle;
  final Color? activeColor;
  final Color? inactiveColor;

  /// Current position in milliseconds. If omitted, will be read from [positionMsListenable]
  /// or driven automatically by an internal VSYNC [Ticker].
  final int? positionMs;

  /// Optional listenable providing high-frequency position ticks.
  final ValueListenable<int>? positionMsListenable;

  /// Whether this line is considered active in the broader lyrics flow.
  /// If null, defaults to whether current playback position falls within line timing.
  final bool? isActive;

  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final double? layoutWidth;

  /// Whether an internal VSYNC ticker should drive syllable filling when no external
  /// [positionMsListenable] is provided.
  final bool enableTicker;

  const WordFillLyricsLine({
    super.key,
    required this.line,
    this.textStyle,
    this.activeColor,
    this.inactiveColor,
    this.positionMs,
    this.positionMsListenable,
    this.isActive,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.layoutWidth,
    this.enableTicker = true,
  });

  @override
  State<WordFillLyricsLine> createState() => _WordFillLyricsLineState();
}

class _WordFillLyricsLineState extends State<WordFillLyricsLine>
    with SingleTickerProviderStateMixin {
  late List<TextSelection> _wordRanges;
  ValueNotifier<int>? _internalPositionNotifier;
  Ticker? _ticker;
  PlaybackCoordinator? _coordinatorRef;

  @override
  void initState() {
    super.initState();
    _initRanges();
    AppFocusService.instance.isFocused.addListener(_handleFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateCoordinatorListener();
    _syncTickerState();
  }

  @override
  void didUpdateWidget(WordFillLyricsLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.content != widget.line.content ||
        oldWidget.line.words != widget.line.words) {
      _initRanges();
    }
    _syncTickerState();
  }

  @override
  void dispose() {
    AppFocusService.instance.isFocused.removeListener(_handleFocusChanged);
    _coordinatorRef?.removeListener(_syncTickerState);
    _ticker?.dispose();
    _internalPositionNotifier?.dispose();
    super.dispose();
  }

  void _initRanges() {
    if (widget.line.hasWordTiming) {
      _wordRanges = resolveWordRanges(widget.line.content, widget.line.words);
    } else {
      _wordRanges = const [];
    }
  }

  void _updateCoordinatorListener() {
    try {
      final coordinator = context.read<PlaybackCoordinator>();
      if (!identical(_coordinatorRef, coordinator)) {
        _coordinatorRef?.removeListener(_syncTickerState);
        _coordinatorRef = coordinator;
        _coordinatorRef?.addListener(_syncTickerState);
      }
    } catch (_) {
      // Coordinator may not be present in all test harnesses
    }
  }

  void _handleFocusChanged() {
    _syncTickerState();
  }

  bool get _needsInternalTicker =>
      widget.positionMsListenable == null &&
      widget.enableTicker &&
      widget.line.hasWordTiming;

  void _syncTickerState() {
    if (!_needsInternalTicker) {
      _ticker?.stop();
      return;
    }

    _internalPositionNotifier ??= ValueNotifier<int>(widget.positionMs ?? 0);

    final isFocused = AppFocusService.instance.isFocused.value;
    final isPlaying = _coordinatorRef?.effectiveIsPlaying ?? true;

    if (isFocused && isPlaying) {
      _ticker ??= createTicker(_onTick);
      if (!_ticker!.isActive) {
        _ticker!.start();
      }
    } else {
      _ticker?.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (!AppFocusService.instance.isFocused.value) return;

    final coordinator = _coordinatorRef;
    if (coordinator == null || !coordinator.effectiveIsPlaying) {
      _ticker?.stop();
      return;
    }

    final basePosMs = coordinator.effectiveInterpolatedPosition.inMilliseconds;
    double delaySeconds = 0.0;
    try {
      final lyricsProvider = context.read<LyricsProvider>();
      final audioHandler = context.read<WispAudioHandler>();
      final trackId = audioHandler.currentTrack?.id;
      if (trackId != null) {
        delaySeconds = lyricsProvider.getDelaySecondsCached(trackId);
      }
    } catch (_) {}

    final delayMs = (delaySeconds * 1000).round();
    final effectiveMs = math.max(0, basePosMs - delayMs);

    if (_internalPositionNotifier != null &&
        _internalPositionNotifier!.value != effectiveMs) {
      _internalPositionNotifier!.value = effectiveMs;
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultTextStyle = DefaultTextStyle.of(context).style;
    final effectiveBaseStyle = defaultTextStyle.merge(widget.textStyle);
    final textScaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;

    final textAlign = widget.textAlign ??
        (widget.line.isRightSpeaker ? TextAlign.right : TextAlign.left);
    final alignment = widget.line.isRightSpeaker
        ? Alignment.centerRight
        : Alignment.centerLeft;

    final activeColor = widget.activeColor ?? effectiveBaseStyle.color ?? Colors.white;
    final inactiveColor = widget.inactiveColor ??
        activeColor.withValues(alpha: (activeColor.a * 0.45).clamp(0.0, 1.0));

    final effectiveListenable = widget.positionMsListenable ?? _internalPositionNotifier;
    final effectiveSoftWrap = widget.softWrap ?? (widget.maxLines == 1 ? false : true);
    final effectiveOverflow = widget.overflow ?? (widget.maxLines != null ? TextOverflow.ellipsis : null);

    if (effectiveListenable != null && widget.line.hasWordTiming) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final layoutWidth = widget.layoutWidth ??
              (constraints.maxWidth.isFinite && constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : null);

          return Stack(
            alignment: alignment,
            children: [
              Text(
                widget.line.content,
                style: effectiveBaseStyle.copyWith(color: inactiveColor),
                textAlign: textAlign,
                maxLines: widget.maxLines,
                overflow: effectiveOverflow,
                softWrap: effectiveSoftWrap,
              ),
              ValueListenableBuilder<int>(
                valueListenable: effectiveListenable,
                builder: (context, positionMs, child) {
                  return ClipPath(
                    clipper: LyricsLineFillClipper(
                      lineContent: widget.line.content,
                      words: widget.line.words,
                      wordRanges: _wordRanges,
                      lineEndTimeMs: widget.line.endTimeMs,
                      style: effectiveBaseStyle,
                      textAlign: textAlign,
                      textScaler: textScaler,
                      layoutWidth: layoutWidth,
                      positionMs: positionMs,
                    ),
                    child: child,
                  );
                },
                child: Text(
                  widget.line.content,
                  style: effectiveBaseStyle.copyWith(color: activeColor),
                  textAlign: textAlign,
                  maxLines: widget.maxLines,
                  overflow: effectiveOverflow,
                  softWrap: effectiveSoftWrap,
                ),
              ),
            ],
          );
        },
      );
    }

    // Static position or line-level fallback
    final pos = widget.positionMs ?? _internalPositionNotifier?.value ?? 0;
    final hasWords = widget.line.hasWordTiming && _wordRanges.isNotEmpty;

    if (!hasWords) {
      final isLineActive = widget.isActive ??
          (pos >= widget.line.startTimeMs &&
              (widget.line.endTimeMs == null || pos < widget.line.endTimeMs!));
      return Text(
        widget.line.content,
        style: effectiveBaseStyle.copyWith(
          color: isLineActive ? activeColor : inactiveColor,
        ),
        textAlign: textAlign,
        maxLines: widget.maxLines,
        overflow: effectiveOverflow,
        softWrap: effectiveSoftWrap,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutWidth = widget.layoutWidth ??
            (constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : null);

        return Stack(
          alignment: alignment,
          children: [
            Text(
              widget.line.content,
              style: effectiveBaseStyle.copyWith(color: inactiveColor),
              textAlign: textAlign,
              maxLines: widget.maxLines,
              overflow: effectiveOverflow,
              softWrap: effectiveSoftWrap,
            ),
            ClipPath(
              clipper: LyricsLineFillClipper(
                lineContent: widget.line.content,
                words: widget.line.words,
                wordRanges: _wordRanges,
                lineEndTimeMs: widget.line.endTimeMs,
                style: effectiveBaseStyle,
                textAlign: textAlign,
                textScaler: textScaler,
                layoutWidth: layoutWidth,
                positionMs: pos,
              ),
              child: Text(
                widget.line.content,
                style: effectiveBaseStyle.copyWith(color: activeColor),
                textAlign: textAlign,
                maxLines: widget.maxLines,
                overflow: effectiveOverflow,
                softWrap: effectiveSoftWrap,
              ),
            ),
          ],
        );
      },
    );
  }
}
