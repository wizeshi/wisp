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
  late List<List<TextSelection>> _bgWordRanges;

  @override
  void initState() {
    super.initState();
    _initRanges();
  }

  @override
  void didUpdateWidget(LyricsLineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line) {
      _initRanges();
    }
  }

  String _formatBgContent(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
      return trimmed;
    }
    return '($trimmed)';
  }

  void _initRanges() {
    _wordRanges = resolveWordRanges(widget.line.content, widget.line.words);
    _bgWordRanges = widget.line.background
        .map((bg) => resolveWordRanges(_formatBgContent(bg.content), bg.words))
        .toList();
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

        final isRight = widget.line.isRightSpeaker;
        final textAlign = isRight ? TextAlign.right : TextAlign.left;
        final alignment = isRight ? Alignment.centerRight : Alignment.centerLeft;

        Widget textContent;
        if (isActiveLine &&
            widget.syncMode == LyricsSyncMode.word &&
            widget.line.hasWordTiming) {
          textContent = LayoutBuilder(
            builder: (context, constraints) {
              final layoutWidth =
                  constraints.maxWidth.isFinite && constraints.maxWidth > 0
                      ? constraints.maxWidth
                      : null;

              return Stack(
                alignment: alignment,
                children: [
                  Text(
                    widget.line.content,
                    style: effectiveBaseStyle.copyWith(color: inactiveWordColor),
                    textAlign: textAlign,
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
                      textAlign: textAlign,
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
            textAlign: textAlign,
          );
        }

        // Synchronized Background vocal lines rendering if present
        Widget? backgroundContent;
        if (widget.line.hasBackground) {
          final bgWidgets = <Widget>[];
          final baseBgFontSize = (effectiveBaseStyle.fontSize ?? 24) * 0.72;

          for (int bIdx = 0; bIdx < widget.line.background.length; bIdx++) {
            final bg = widget.line.background[bIdx];
            final bgRanges = (bIdx < _bgWordRanges.length) ? _bgWordRanges[bIdx] : <TextSelection>[];
            final bgFormattedText = _formatBgContent(bg.content);

            // Timing checks for this background vocal phrase
            final bgStart = bg.startTimeMs;
            int? resolvedBgEnd = bg.endTimeMs;
            if (resolvedBgEnd == null && bg.words.isNotEmpty) {
              final lastWord = bg.words.last;
              resolvedBgEnd = lastWord.endTimeMs ?? (lastWord.startTimeMs + 800);
            }
            resolvedBgEnd ??= (widget.line.endTimeMs ?? (bgStart + 2000));

            final isBgActive = isSynced &&
                isLineActive &&
                frame.positionMs >= bgStart &&
                frame.positionMs < resolvedBgEnd;
            final isBgPast = isSynced &&
                (frame.positionMs >= resolvedBgEnd ||
                    (!isLineActive && frame.positionMs >= bgStart));
            final isBgUpcoming = isSynced && frame.positionMs < bgStart;

            double bgOpacity = opacity;
            if (isSynced) {
              if (isBgActive) {
                bgOpacity = 1.0;
              } else if (isBgPast) {
                bgOpacity = (opacity * 0.65).clamp(0.2, 0.7);
              } else if (isBgUpcoming) {
                bgOpacity = (opacity * 0.35).clamp(0.1, 0.4);
              }
            }

            final bgBaseStyle = effectiveBaseStyle.copyWith(
              fontSize: baseBgFontSize,
              fontStyle: FontStyle.italic,
              color: (isBgActive ? Colors.white : inactiveColor).withValues(
                alpha: (isBgActive ? bgOpacity : (inactiveColor.a * bgOpacity)).clamp(0.0, 1.0),
              ),
            );

            Widget phraseWidget;
            if (isBgActive && bg.hasWordTiming && bgRanges.isNotEmpty) {
              final activeWordColor = Colors.white.withValues(alpha: bgOpacity);
              final inactiveWordColor = Colors.white.withValues(alpha: 0.45 * bgOpacity);

              phraseWidget = LayoutBuilder(
                builder: (context, constraints) {
                  final bgLayoutWidth =
                      constraints.maxWidth.isFinite && constraints.maxWidth > 0
                          ? constraints.maxWidth
                          : null;

                  return Stack(
                    alignment: alignment,
                    children: [
                      Text(
                        bgFormattedText,
                        style: bgBaseStyle.copyWith(color: inactiveWordColor),
                        textAlign: textAlign,
                      ),
                      ClipPath(
                        clipper: LyricsLineFillClipper(
                          lineContent: bgFormattedText,
                          words: bg.words,
                          wordRanges: bgRanges,
                          lineEndTimeMs: resolvedBgEnd,
                          style: bgBaseStyle,
                          textScaler: textScaler,
                          layoutWidth: bgLayoutWidth,
                          positionMs: frame.positionMs,
                        ),
                        child: Text(
                          bgFormattedText,
                          style: bgBaseStyle.copyWith(color: activeWordColor),
                          textAlign: textAlign,
                        ),
                      ),
                    ],
                  );
                },
              );
            } else {
              phraseWidget = Text(
                bgFormattedText,
                style: bgBaseStyle,
                textAlign: textAlign,
              );
            }

            bgWidgets.add(
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: phraseWidget,
              ),
            );
          }

          if (bgWidgets.isNotEmpty) {
            backgroundContent = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: bgWidgets,
            );
          }
        }

        final canSeek = widget.line.startTimeMs > 0;

        final lineWidget = Padding(
          padding: EdgeInsets.symmetric(vertical: widget.isDesktop ? 8 : 12),
          child: Align(
            alignment: alignment,
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: isRight
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      textContent,
                      ?backgroundContent,
                    ],
                  ),
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
          crossAxisAlignment:
              isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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

