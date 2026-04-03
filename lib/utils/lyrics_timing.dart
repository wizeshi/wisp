import 'dart:math' as math;

import '../models/metadata_models.dart';

const int kLyricsWaitingGapThresholdMs = 5000;
const int kLyricsFadeOutWindowMs = 140;

class LyricsTimingState {
  final int activeIndex;
  final int? previousIndex;
  final int? nextIndex;
  final int gapMs;
  final double progressToNext;
  final double fadeOutProgress;

  const LyricsTimingState({
    required this.activeIndex,
    required this.previousIndex,
    required this.nextIndex,
    required this.gapMs,
    required this.progressToNext,
    required this.fadeOutProgress,
  });

  bool get showWaitingDots =>
      activeIndex < 0 && nextIndex != null && gapMs > kLyricsWaitingGapThresholdMs;

  bool get shouldFadePreviousLine =>
      previousIndex != null &&
      nextIndex != null &&
      gapMs > 0 &&
      gapMs <= kLyricsWaitingGapThresholdMs;
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
    synced: lyrics.synced,
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
      previousIndex: null,
      nextIndex: null,
      gapMs: 0,
      progressToNext: 0,
      fadeOutProgress: 0,
    );
  }

  int? previousIndex;
  int? nextIndex;

  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startTimeMs <= safePositionMs) {
      previousIndex = i;
      continue;
    }
    nextIndex = i;
    break;
  }

  if (previousIndex == null) {
    final nextStart = nextIndex == null ? 0 : lines[nextIndex].startTimeMs;
    final gapMs = nextStart < 0 ? 0 : nextStart;
    final progress =
        gapMs <= 0 ? 0.0 : (safePositionMs.clamp(0, gapMs) / gapMs);

    return LyricsTimingState(
      activeIndex: -1,
      previousIndex: null,
      nextIndex: nextIndex,
      gapMs: gapMs,
      progressToNext: progress.clamp(0.0, 1.0),
      fadeOutProgress: 0.0,
    );
  }

  if (nextIndex == null) {
    return LyricsTimingState(
      activeIndex: previousIndex,
      previousIndex: previousIndex,
      nextIndex: null,
      gapMs: 0,
      progressToNext: 1,
      fadeOutProgress: 1,
    );
  }

  final previousStart = lines[previousIndex].startTimeMs;
  final nextStart = lines[nextIndex].startTimeMs;
  final startToStartSpanMs =
      (nextStart - previousStart).clamp(0, 1 << 31).toInt();

  final estimatedActiveMs = _estimateLineActiveMs(
    lines[previousIndex].content,
    startToStartSpanMs,
  );
  final estimatedLineEndMs = previousStart + estimatedActiveMs;
  final lineEndMs = math.min(estimatedLineEndMs, nextStart);

  final gapMs = (nextStart - lineEndMs).clamp(0, 1 << 31).toInt();
    final isPastLineEnd = safePositionMs >= lineEndMs;

  final progress = gapMs <= 0
      ? 1.0
      : ((safePositionMs - lineEndMs).clamp(0, gapMs) / gapMs).toDouble();

    final fadeWindowMs = gapMs <= 0
      ? 0
      : math.min(gapMs, kLyricsFadeOutWindowMs);
    final fadeStartMs = nextStart - fadeWindowMs;
    final fadeOutProgress = fadeWindowMs <= 0
        ? 0.0
        : ((safePositionMs - fadeStartMs).clamp(0, fadeWindowMs) / fadeWindowMs)
        .toDouble();

  final isLongGap = gapMs > kLyricsWaitingGapThresholdMs;
  final activeIndex = isLongGap && isPastLineEnd ? -1 : previousIndex;

  return LyricsTimingState(
    activeIndex: activeIndex,
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
  final wordCount = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
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
