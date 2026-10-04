// Copyright © 2026 wizeshi

import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';


class LyricsLineItem extends StatefulWidget {
  final LyricsLine line;
  final int index;
  final bool isDesktop;
  final LyricsSyncMode syncMode;
  final Color backgroundColor;
  final WispAudioHandler player;
  final ValueListenable<LyricsFrame> frameListenable;
  final Future<void> Function(Duration) onSeek;

  const LyricsLineItem({
    super.key,
    required this.line,
    required this.index,
    required this.isDesktop,
    required this.syncMode,
    required this.backgroundColor,
    required this.player,
    required this.frameListenable,
    required this.onSeek,
  });

  @override
  State<LyricsLineItem> createState() => _LyricsLineItemState();
}

class _LyricsLineItemState extends State<LyricsLineItem> {
  bool _hovered = false;
  late List<TextSelection> _wordRanges;

  @override
  void initState() {
    super.initState();
    _wordRanges = resolveWordRanges(widget.line.content, widget.line.words);
  }

  @override
  void didUpdateWidget(LyricsLineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line) {
      _wordRanges = resolveWordRanges(widget.line.content, widget.line.words);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LyricsFrame>(
      valueListenable: widget.frameListenable,
      builder: (context, frame, child) {
        final timing = frame.timing;
        final isSynced = widget.syncMode != LyricsSyncMode.unsynced;
        final isLineActive = !isSynced ||
            (frame.activeIndices.contains(widget.index) ||
                frame.activeIndex == widget.index);

        var opacity = 1.0;
        if (isSynced &&
            (frame.activeIndices.isNotEmpty || frame.activeIndex >= 0)) {
          if (isLineActive) {
            opacity = 1.0;
          } else {
            final minActive = frame.activeIndices.isNotEmpty
                ? frame.activeIndices.reduce(math.min)
                : frame.activeIndex;
            final maxActive = frame.activeIndices.isNotEmpty
                ? frame.activeIndices.reduce(math.max)
                : frame.activeIndex;

            if (widget.index < minActive) {
              final pastDistance = minActive - widget.index;
              opacity = (0.45 - (pastDistance * 0.07)).clamp(0.2, 0.45);
            } else if (widget.index > maxActive) {
              final futureDistance = widget.index - maxActive;
              opacity = (0.75 - (futureDistance * 0.05)).clamp(0.45, 0.75);
            }
          }
        }
        if (isSynced &&
            timing != null &&
            !isLineActive &&
            timing.shouldFadePreviousLine &&
            timing.previousIndex == widget.index &&
            timing.nextIndex != null) {
          opacity = lerpDouble(1.0, 0.5, timing.fadeOutProgress)!;
        }
        final isActiveLine = isLineActive &&
            !(timing != null &&
                timing.shouldFadePreviousLine &&
                timing.fadeOutProgress > 0 &&
                timing.previousIndex == widget.index);
        final inactiveColor =
            Color.lerp(Colors.white, widget.backgroundColor, 0.6) ??
            Colors.white70;
        final baseColor = isActiveLine ? Colors.white : inactiveColor;
        final baseStyle = TextStyle(
          color: baseColor.withValues(
            alpha: (baseColor.a * opacity).clamp(0.0, 1.0),
          ),
          fontSize: widget.isDesktop ? 42.0 : 26.0,
          letterSpacing: widget.isDesktop ? -1.5 : -0.3,
          fontWeight: widget.isDesktop ? FontWeight.w700 : FontWeight.w800,
          height: widget.isDesktop ? 1.4 : 1.1,
          decoration: _hovered ? TextDecoration.underline : TextDecoration.none,
          decorationColor: Colors.white70.withValues(
            alpha: (Colors.white70.a * opacity).clamp(0.0, 1.0),
          ),
        );
        final activeWordColor = Colors.white.withValues(alpha: opacity);
        final inactiveWordColor = isActiveLine
            ? Colors.white.withValues(alpha: 0.45 * opacity)
            : inactiveColor.withValues(
                alpha: (inactiveColor.a * opacity).clamp(0.0, 1.0),
              );

        final defaultTextStyle = DefaultTextStyle.of(context).style;
        final effectiveBaseStyle = defaultTextStyle.merge(baseStyle);
        final textScaler = MediaQuery.textScalerOf(context);

        final Widget textContent;
        if (isLineActive &&
            widget.syncMode == LyricsSyncMode.word &&
            widget.line.hasWordTiming) {
          textContent = LayoutBuilder(
            builder: (context, constraints) {
              final layoutWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;

              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Text(
                    widget.line.content,
                    style: effectiveBaseStyle.copyWith(color: inactiveWordColor),
                    textAlign: TextAlign.left,
                  ),
                  ClipPath(
                    clipper: LyricsLineFillClipper(
                      lineContent: widget.line.content,
                      words: widget.line.words,
                      wordRanges: _wordRanges,
                      lineEndTimeMs: widget.line.endTimeMs,
                      style: effectiveBaseStyle,
                      textScaler: textScaler,
                      layoutWidth: layoutWidth,
                      positionMs: frame.positionMs,
                    ),
                    child: Text(
                      widget.line.content,
                      style: effectiveBaseStyle.copyWith(color: activeWordColor),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              );
            },
          );
        } else {
          textContent = Text(
            widget.line.content,
            style: effectiveBaseStyle,
            textAlign: TextAlign.left,
          );
        }

        final canSeek = widget.line.startTimeMs > 0;

        final lineWidget = Padding(
          padding: EdgeInsets.symmetric(vertical: widget.isDesktop ? 8 : 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                mouseCursor: canSeek ? SystemMouseCursors.click : MouseCursor.defer,
                onHover: widget.isDesktop
                    ? (hovering) => setState(() => _hovered = hovering)
                    : null,
                onTap: canSeek
                    ? () => widget.onSeek(
                        Duration(
                          milliseconds: widget.line.startTimeMs + frame.delayMs,
                        ),
                      )
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: textContent,
                ),
              ),
            ),
          ),
        );

        final showWaitingDots = isSynced &&
            timing != null &&
            timing.showWaitingDots &&
            timing.nextIndex == widget.index;

        if (!showWaitingDots) {
          return lineWidget;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWaitingDots(
              progress: timing.progressToNext,
              isDesktop: widget.isDesktop,
            ),
            lineWidget,
          ],
        );
      },
    );
  }

  Widget _buildWaitingDots({
    required double progress,
    required bool isDesktop,
  }) {
    final dotSize = isDesktop ? 12.0 : 10.0;
    final dots = List<Widget>.generate(3, (index) {
      final start = index / 3;
      final end = (index + 1) / 3;
      final localProgress =
          ((progress - start) / (end - start)).clamp(0.0, 1.0);
      final opacity = lerpDouble(0.24, 1.0, localProgress)!;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        ),
      );
    });

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: dots,
        ),
      ),
    );
  }
}

