// Copyright © 2026 wizeshi

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:wisp/data/models/metadata_models.dart';

const int kLyricsWaitingGapThresholdMs = 10000;
const int kLyricsInitialWaitingGapThresholdMs =
    kLyricsWaitingGapThresholdMs ~/ 2;
const int kLyricsFadeOutWindowMs = 140;

class LyricsTimingState {
  final int activeIndex;
  final Set<int> activeIndices;
  final int? previousIndex;
  final int? nextIndex;
  final int gapMs;
  final double progressToNext;
  final double fadeOutProgress;

  const LyricsTimingState({
    required this.activeIndex,
    this.activeIndices = const {},
    required this.previousIndex,
    required this.nextIndex,
    required this.gapMs,
    required this.progressToNext,
    required this.fadeOutProgress,
  });

  bool get showWaitingDots {
    final thresholdMs = previousIndex == null
        ? kLyricsInitialWaitingGapThresholdMs
        : kLyricsWaitingGapThresholdMs;
    return activeIndex < 0 && nextIndex != null && gapMs > thresholdMs;
  }

  bool get shouldFadePreviousLine =>
      previousIndex != null &&
      nextIndex != null &&
      gapMs > 0 &&
      gapMs <= kLyricsWaitingGapThresholdMs;
}

class LyricsFrame {
  final int activeIndex;
  final Set<int> activeIndices;
  final LyricsTimingState? timing;
  final int positionMs;
  final int delayMs;

  const LyricsFrame({
    required this.activeIndex,
    this.activeIndices = const {},
    required this.timing,
    required this.positionMs,
    required this.delayMs,
  });

  const LyricsFrame.unsynced()
      : activeIndex = 0,
        activeIndices = const {0},
        timing = null,
        positionMs = 0,
        delayMs = 0;
}

class LyricsWordTimingState {
  final int activeIndex;
  final int? previousIndex;
  final int? nextIndex;

  const LyricsWordTimingState({
    required this.activeIndex,
    required this.previousIndex,
    required this.nextIndex,
  });

  bool get hasActiveWord => activeIndex >= 0;
}

List<LyricsLine> nonEmptyLyricsLines(List<LyricsLine> lines) {
  final filtered = <({LyricsLine line, int index})>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_shouldKeepLyricsLine(line)) {
      filtered.add((line: line, index: i));
    }
  }

  filtered.sort((a, b) {
    final byStart = a.line.startTimeMs.compareTo(b.line.startTimeMs);
    if (byStart != 0) return byStart;
    return a.index.compareTo(b.index);
  });

  return filtered.map((entry) => entry.line).toList(growable: false);
}

LyricsWordTimingState resolveWordLyricsTiming(
  List<LyricsWord> words,
  int positionMs,
) {
  final safePositionMs = positionMs < 0 ? 0 : positionMs;

  if (words.isEmpty) {
    return const LyricsWordTimingState(
      activeIndex: -1,
      previousIndex: null,
      nextIndex: null,
    );
  }

  int? previousIndex;
  int? nextIndex;

  for (var i = 0; i < words.length; i++) {
    if (words[i].startTimeMs <= safePositionMs) {
      previousIndex = i;
      continue;
    }
    nextIndex = i;
    break;
  }

  if (previousIndex == null) {
    return LyricsWordTimingState(
      activeIndex: -1,
      previousIndex: null,
      nextIndex: nextIndex,
    );
  }

  return LyricsWordTimingState(
    activeIndex: previousIndex,
    previousIndex: previousIndex,
    nextIndex: nextIndex,
  );
}

/// Aligns timed [words] against [lineContent] and returns whether each word
/// should be preceded by a space. Syllables of the same word stay unspaced.
List<bool> resolveWordLeadingSpaces(
  String lineContent,
  List<LyricsWord> words,
) {
  if (words.isEmpty) {
    return const [];
  }

  final leadingSpaces = List<bool>.filled(words.length, false);
  var pos = 0;

  for (var i = 0; i < words.length; i++) {
    if (i > 0) {
      final spaceStart = pos;
      while (pos < lineContent.length && lineContent[pos] == ' ') {
        pos++;
      }
      leadingSpaces[i] = pos > spaceStart;
    }

    final word = words[i].content;
    if (word.isEmpty) {
      continue;
    }

    if (lineContent.startsWith(word, pos)) {
      pos += word.length;
      continue;
    }

    final idx = lineContent.indexOf(word, pos);
    if (idx >= 0) {
      if (idx > pos) {
        leadingSpaces[i] = lineContent.substring(pos, idx).contains(' ');
      }
      pos = idx + word.length;
      continue;
    }

    pos += word.length;
  }

  return leadingSpaces;
}

/// Maps each [LyricsWord] to its [TextSelection] range within [lineContent].
List<TextSelection> resolveWordRanges(
  String lineContent,
  List<LyricsWord> words,
) {
  if (words.isEmpty) {
    return const [];
  }

  final ranges = <TextSelection>[];
  var pos = 0;

  for (final word in words) {
    if (word.content.isEmpty) {
      ranges.add(TextSelection(baseOffset: pos, extentOffset: pos));
      continue;
    }

    final idx = lineContent.indexOf(word.content, pos);
    if (idx >= 0) {
      final end = idx + word.content.length;
      ranges.add(TextSelection(baseOffset: idx, extentOffset: end));
      pos = end;
    } else {
      final nextEnd = (pos + word.content.length).clamp(0, lineContent.length);
      ranges.add(TextSelection(baseOffset: pos, extentOffset: nextEnd));
      pos = nextEnd;
    }
  }

  return ranges;
}

/// Computes the effective end time in milliseconds for [line].
int resolveLineEndTimeMs(
  LyricsLine line, {
  int? nextLineStartTimeMs,
}) {
  if (line.hasWordTiming && line.words.isNotEmpty) {
    final lastWord = line.words.last;
    final lastWordEnd = lastWord.endTimeMs ?? (lastWord.startTimeMs + 800);
    if (line.endTimeMs != null && line.endTimeMs! > line.startTimeMs) {
      return math.max(line.endTimeMs!, lastWordEnd);
    }
    return lastWordEnd;
  }

  if (line.endTimeMs != null && line.endTimeMs! > line.startTimeMs) {
    return line.endTimeMs!;
  }

  if (nextLineStartTimeMs != null && nextLineStartTimeMs > line.startTimeMs) {
    final span = nextLineStartTimeMs - line.startTimeMs;
    return line.startTimeMs + _estimateLineActiveMs(line.content, span);
  }

  return line.startTimeMs + _estimateLineActiveMs(line.content, 4000);
}

/// A clipper that reveals the filled (sung) portion of a lyrics line from left to right.
///
/// Used in dual-layer lyrics line rendering where an identical inactive line is
/// overlaid with a clipped active line. This ensures zero layout shifts or baseline
/// jumps during the fill animation.
class LyricsLineFillClipper extends CustomClipper<Path> {
  final String lineContent;
  final List<LyricsWord> words;
  final List<TextSelection> wordRanges;
  final int? lineEndTimeMs;
  final TextStyle style;
  final int positionMs;

  const LyricsLineFillClipper({
    required this.lineContent,
    required this.words,
    required this.wordRanges,
    this.lineEndTimeMs,
    required this.style,
    required this.positionMs,
  });

  @override
  Path getClip(Size size) {
    if (words.isEmpty) return Path();

    final tp = TextPainter(
      text: TextSpan(text: lineContent, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    final lineEnd = lineEndTimeMs ??
        (words.last.endTimeMs ?? (words.last.startTimeMs + 800));

    // If position is past the line's end, fully reveal the line
    if (positionMs >= lineEnd) {
      return Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width + 10, size.height + 10));
    }

    final wordTiming = resolveWordLyricsTiming(words, positionMs);
    final activeIndex = wordTiming.activeIndex;

    final path = Path();
    if (activeIndex < 0 && positionMs < words.first.startTimeMs) {
      return path;
    }

    for (var i = 0; i < words.length; i++) {
      if (i > activeIndex && activeIndex >= 0) break;
      if (i >= wordRanges.length) break;
      final range = wordRanges[i];
      if (range.start >= range.end) continue;

      final word = words[i];
      final wordStartMs = word.startTimeMs;
      final int wordEndMs;
      if (word.endTimeMs != null && word.endTimeMs! > wordStartMs) {
        wordEndMs = word.endTimeMs!;
      } else if (i + 1 < words.length) {
        wordEndMs = words[i + 1].startTimeMs;
      } else if (lineEndTimeMs != null && lineEndTimeMs! > wordStartMs) {
        wordEndMs = lineEndTimeMs!;
      } else {
        wordEndMs = wordStartMs + 800;
      }

      final double fillProgress;
      if (i < activeIndex) {
        fillProgress = 1.0;
      } else if (i == activeIndex) {
        if (positionMs <= wordStartMs) {
          fillProgress = 0.0;
        } else if (positionMs >= wordEndMs || wordEndMs <= wordStartMs) {
          fillProgress = 1.0;
        } else {
          fillProgress =
              ((positionMs - wordStartMs) / (wordEndMs - wordStartMs)).clamp(0.0, 1.0);
        }
      } else {
        fillProgress = 0.0;
      }

      if (fillProgress <= 0.0) continue;

      final int extentEnd;
      if (i < activeIndex && i + 1 < wordRanges.length) {
        extentEnd = wordRanges[i + 1].start;
      } else if (i == words.length - 1 && fillProgress >= 1.0) {
        extentEnd = lineContent.length;
      } else {
        extentEnd = range.end;
      }

      final boxes = tp.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: extentEnd),
      );

      for (final box in boxes) {
        final rect = box.toRect();
        if (fillProgress >= 1.0) {
          path.addRect(Rect.fromLTRB(rect.left, rect.top, rect.right + 0.5, rect.bottom));
        } else {
          final partialWidth = rect.width * fillProgress;
          path.addRect(Rect.fromLTRB(rect.left, rect.top, rect.left + partialWidth, rect.bottom));
        }
      }
    }

    return path;
  }

  @override
  bool shouldReclip(LyricsLineFillClipper oldClipper) {
    return oldClipper.positionMs != positionMs ||
        oldClipper.style != style ||
        oldClipper.lineContent != lineContent ||
        oldClipper.lineEndTimeMs != lineEndTimeMs;
  }
}

InlineSpan buildLyricsLineSpan({
  required LyricsLine line,
  required LyricsSyncMode syncMode,
  required int positionMs,
  required TextStyle baseStyle,
  required Color activeWordColor,
  required Color inactiveWordColor,
  required bool highlightWords,
  bool animateWordFill = false,
}) {
  if (!highlightWords ||
      syncMode != LyricsSyncMode.word ||
      !line.hasWordTiming) {
    return TextSpan(text: line.content, style: baseStyle);
  }

  final wordTiming = resolveWordLyricsTiming(line.words, positionMs);
  if (line.words.isEmpty) {
    return TextSpan(text: line.content, style: baseStyle);
  }

  final leadingSpaces = resolveWordLeadingSpaces(line.content, line.words);
  final spans = <InlineSpan>[];
  for (var index = 0; index < line.words.length; index++) {
    final word = line.words[index];
    final isActiveWord = wordTiming.activeIndex == index;
    final wordStartMs = word.startTimeMs;
    final wordEndMs =
        word.endTimeMs ??
        (index + 1 < line.words.length
            ? line.words[index + 1].startTimeMs
            : wordStartMs + 300);
    final fillProgress = index < wordTiming.activeIndex
        ? 1.0
        : index > wordTiming.activeIndex || positionMs <= wordStartMs
        ? 0.0
        : positionMs >= wordEndMs || wordEndMs <= wordStartMs
        ? 1.0
        : ((positionMs - wordStartMs) / (wordEndMs - wordStartMs)).clamp(
            0.0,
            1.0,
          );

    if (leadingSpaces[index]) {
      spans.add(
        TextSpan(
          text: ' ',
          style: baseStyle.copyWith(color: inactiveWordColor),
        ),
      );
    }

    if (animateWordFill) {
      final color = Color.lerp(inactiveWordColor, activeWordColor, fillProgress);
      spans.add(
        TextSpan(
          text: word.content,
          style: baseStyle.copyWith(color: color),
        ),
      );
      continue;
    }

    spans.add(
      TextSpan(
        text: word.content,
        style: baseStyle.copyWith(
          color: isActiveWord ? activeWordColor : inactiveWordColor,
        ),
      ),
    );
  }

  return TextSpan(style: baseStyle, children: spans);
}

bool _shouldKeepLyricsLine(LyricsLine line) {
  final trimmed = line.content.trim();
  if (trimmed.isEmpty) return false;

  final normalized = trimmed.replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) return false;
  if (RegExp(r'^[♪]+$').hasMatch(normalized)) return false;

  return true;
}

LyricsResult removeEmptyLyricsLines(LyricsResult lyrics) {
  final cleanedLines = nonEmptyLyricsLines(lyrics.lines);
  if (cleanedLines.length == lyrics.lines.length) {
    return lyrics;
  }

  return LyricsResult(
    provider: lyrics.provider,
    customProviderName: lyrics.customProviderName,
    syncMode: lyrics.syncMode,
    lines: cleanedLines,
  );
}

LyricsTimingState resolveSyncedLyricsTiming(
  List<LyricsLine> lines,
  int positionMs,
) {
  final safePositionMs = positionMs < 0 ? 0 : positionMs;

  if (lines.isEmpty) {
    return const LyricsTimingState(
      activeIndex: -1,
      activeIndices: {},
      previousIndex: null,
      nextIndex: null,
      gapMs: 0,
      progressToNext: 0,
      fadeOutProgress: 0,
    );
  }

  final lineEndTimes = List<int>.generate(lines.length, (i) {
    final nextStart = i + 1 < lines.length ? lines[i + 1].startTimeMs : null;
    return resolveLineEndTimeMs(lines[i], nextLineStartTimeMs: nextStart);
  });

  final activeIndices = <int>{};
  int? previousIndex;
  int? nextIndex;

  for (var i = 0; i < lines.length; i++) {
    final start = lines[i].startTimeMs;
    final end = lineEndTimes[i];

    if (start <= safePositionMs && safePositionMs < end) {
      activeIndices.add(i);
    }

    if (start <= safePositionMs) {
      previousIndex = i;
    } else {
      nextIndex ??= i;
    }
  }

  if (previousIndex == null) {
    final nextStart = nextIndex == null ? 0 : lines[nextIndex].startTimeMs;
    final gapMs = nextStart < 0 ? 0 : nextStart;
    final progress = gapMs <= 0
        ? 0.0
        : (safePositionMs.clamp(0, gapMs) / gapMs);

    return LyricsTimingState(
      activeIndex: -1,
      activeIndices: const {},
      previousIndex: null,
      nextIndex: nextIndex,
      gapMs: gapMs,
      progressToNext: progress.clamp(0.0, 1.0),
      fadeOutProgress: 0.0,
    );
  }

  if (nextIndex == null) {
    final active = activeIndices.isNotEmpty
        ? activeIndices.last
        : (safePositionMs < lineEndTimes[previousIndex] ? previousIndex : -1);
    return LyricsTimingState(
      activeIndex: active,
      activeIndices: activeIndices,
      previousIndex: previousIndex,
      nextIndex: null,
      gapMs: 0,
      progressToNext: 1,
      fadeOutProgress: 1,
    );
  }

  final nextStart = lines[nextIndex].startTimeMs;
  final lineEndMs = lineEndTimes[previousIndex];

  final gapMs = (nextStart - lineEndMs).clamp(0, 1 << 31).toInt();
  final isPastLineEnd = safePositionMs >= lineEndMs;

  final progress = gapMs <= 0
      ? 1.0
      : ((safePositionMs - lineEndMs).clamp(0, gapMs) / gapMs).toDouble();

  final fadeWindowMs = gapMs <= 0 ? 0 : math.min(gapMs, kLyricsFadeOutWindowMs);
  final fadeStartMs = nextStart - fadeWindowMs;
  final fadeOutProgress = fadeWindowMs <= 0
      ? 0.0
      : ((safePositionMs - fadeStartMs).clamp(0, fadeWindowMs) / fadeWindowMs)
            .toDouble();

  final isLongGap = gapMs > kLyricsWaitingGapThresholdMs;
  final int activeIndex;
  if (activeIndices.isNotEmpty) {
    activeIndex = activeIndices.last;
  } else if (isLongGap && isPastLineEnd) {
    activeIndex = -1;
  } else {
    activeIndex = previousIndex;
  }

  return LyricsTimingState(
    activeIndex: activeIndex,
    activeIndices: activeIndices,
    previousIndex: previousIndex,
    nextIndex: nextIndex,
    gapMs: gapMs,
    progressToNext: progress.clamp(0.0, 1.0),
    fadeOutProgress: fadeOutProgress.clamp(0.0, 1.0),
  );
}

int _estimateLineActiveMs(String content, int availableSpanMs) {
  if (availableSpanMs <= 0) return 0;

  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return math.min(availableSpanMs, 650);
  }

  final charCount = trimmed.length;
  final wordCount = trimmed
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;
  final punctuationCount = RegExp(r'[\.,;:!?]').allMatches(trimmed).length;

  final estimatedMs =
      520 + (charCount * 36) + (wordCount * 70) + (punctuationCount * 110);

  final lowerBound = math.min(availableSpanMs, 700);
  final upperBound = math.min(availableSpanMs, 3400);

  if (upperBound <= lowerBound) {
    return upperBound;
  }

  return estimatedMs.clamp(lowerBound, upperBound).toInt();
}
