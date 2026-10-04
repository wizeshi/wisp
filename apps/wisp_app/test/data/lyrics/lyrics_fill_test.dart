import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_timing.dart';

void main() {
  group('Lyrics Fill & Word Wipe Tests', () {

    test('resolveWordRanges accurately maps words to character selections', () {
      const content = "Hello world from Flutter";
      final words = [
        LyricsWord(content: 'Hello', startTimeMs: 0, endTimeMs: 500),
        LyricsWord(content: 'world', startTimeMs: 500, endTimeMs: 1000),
        LyricsWord(content: 'from', startTimeMs: 1000, endTimeMs: 1500),
        LyricsWord(content: 'Flutter', startTimeMs: 1500, endTimeMs: 2000),
      ];

      final ranges = resolveWordRanges(content, words);
      expect(ranges.length, equals(4));
      expect(content.substring(ranges[0].start, ranges[0].end), equals('Hello'));
      expect(content.substring(ranges[1].start, ranges[1].end), equals('world'));
      expect(content.substring(ranges[2].start, ranges[2].end), equals('from'));
      expect(content.substring(ranges[3].start, ranges[3].end), equals('Flutter'));
    });

    testWidgets('LyricsLineFillClipper produces non-empty clip for active word', (tester) async {
      const content = 'Hello world';
      final words = [
        LyricsWord(content: 'Hello', startTimeMs: 1000, endTimeMs: 2000),
        LyricsWord(content: 'world', startTimeMs: 2000, endTimeMs: 3000),
      ];
      final ranges = resolveWordRanges(content, words);
      const style = TextStyle(fontSize: 32);

      // Before start: path should be empty
      final clipperBefore = LyricsLineFillClipper(
        lineContent: content,
        words: words,
        wordRanges: ranges,
        style: style,
        positionMs: 500,
      );
      final clipBefore = clipperBefore.getClip(const Size(400, 50));
      expect(clipBefore.getBounds().isEmpty, isTrue);

      // Halfway through "Hello" (1500ms): clip should cover half of "Hello"
      final clipperMid = LyricsLineFillClipper(
        lineContent: content,
        words: words,
        wordRanges: ranges,
        style: style,
        positionMs: 1500,
      );
      final clipMid = clipperMid.getClip(const Size(400, 50));
      final boundsMid = clipMid.getBounds();
      expect(boundsMid.isEmpty, isFalse);
      expect(boundsMid.width, greaterThan(0));

      // After "Hello" finished and into "world" (2500ms): clip should be wider
      final clipperLater = LyricsLineFillClipper(
        lineContent: content,
        words: words,
        wordRanges: ranges,
        style: style,
        positionMs: 2500,
      );
      final clipLater = clipperLater.getClip(const Size(400, 50));
      final boundsLater = clipLater.getBounds();
      expect(boundsLater.width, greaterThan(boundsMid.width));
    });

    test('resolveSyncedLyricsTiming supports overlapping active lines', () {
      final lines = [
        LyricsLine(
          content: 'Line 1: 2:05 - 2:15',
          startTimeMs: 125000,
          endTimeMs: 135000,
        ),
        LyricsLine(
          content: 'Line 2: 2:10 - 2:20',
          startTimeMs: 130000,
          endTimeMs: 140000,
        ),
      ];

      // Before Line 1
      final t0 = resolveSyncedLyricsTiming(lines, 120000);
      expect(t0.activeIndices, isEmpty);
      expect(t0.nextIndex, equals(0));

      // During Line 1 only
      final t1 = resolveSyncedLyricsTiming(lines, 127000);
      expect(t1.activeIndices, equals({0}));
      expect(t1.activeIndex, equals(0));

      // During overlap (2:12): BOTH lines active!
      final tOverlap = resolveSyncedLyricsTiming(lines, 132000);
      expect(tOverlap.activeIndices, equals({0, 1}));
      expect(tOverlap.activeIndex, equals(1));

      // After Line 1, Line 2 still active
      final t2 = resolveSyncedLyricsTiming(lines, 137000);
      expect(t2.activeIndices, equals({1}));
      expect(t2.activeIndex, equals(1));

      // After both lines finished
      final tEnd = resolveSyncedLyricsTiming(lines, 145000);
      expect(tEnd.activeIndices, isEmpty);
    });

    test('LyricsLineFillClipper fully reveals last word and trailing punctuation on completion', () {
      const content = 'I will always love you!';
      final words = [
        LyricsWord(content: 'I', startTimeMs: 1000, endTimeMs: 1200),
        LyricsWord(content: 'will', startTimeMs: 1200, endTimeMs: 1400),
        LyricsWord(content: 'always', startTimeMs: 1400, endTimeMs: 1700),
        LyricsWord(content: 'love', startTimeMs: 1700, endTimeMs: 2000),
        LyricsWord(content: 'you', startTimeMs: 2000, endTimeMs: 2500),
      ];
      final ranges = resolveWordRanges(content, words);
      const style = TextStyle(fontSize: 30);

      final tp = TextPainter(
        text: const TextSpan(text: content, style: style),
        textDirection: TextDirection.ltr,
      )..layout();

      final clipper = LyricsLineFillClipper(
        lineContent: content,
        words: words,
        wordRanges: ranges,
        lineEndTimeMs: 2500,
        style: style,
        positionMs: 2500,
      );

      final clip = clipper.getClip(Size(tp.width, tp.height));
      final bounds = clip.getBounds();
      expect(bounds.width, greaterThanOrEqualTo(tp.width));
    });

    test('resolveSyncedLyricsTiming triggers showWaitingDots during long gaps', () {
      final lines = [
        LyricsLine(
          content: 'First line after intro',
          startTimeMs: 12000,
          endTimeMs: 15000,
        ),
        LyricsLine(
          content: 'Second line after long instrumental break',
          startTimeMs: 35000,
          endTimeMs: 40000,
        ),
      ];

      // Intro gap (0 to 12s, > 5s initial threshold)
      final introTiming = resolveSyncedLyricsTiming(lines, 4000);
      expect(introTiming.showWaitingDots, isTrue);
      expect(introTiming.nextIndex, equals(0));
      expect(introTiming.progressToNext, closeTo(4000 / 12000, 0.05));

      // During line 1: no waiting dots
      final activeTiming = resolveSyncedLyricsTiming(lines, 13000);
      expect(activeTiming.showWaitingDots, isFalse);

      // Instrumental break between line 1 (ends at 15s) and line 2 (starts at 35s): gap = 20s (> 10s threshold)
      final breakTiming = resolveSyncedLyricsTiming(lines, 25000);
      expect(breakTiming.showWaitingDots, isTrue);
      expect(breakTiming.nextIndex, equals(1));
      expect(breakTiming.progressToNext, closeTo((25000 - 15000) / (35000 - 15000), 0.05));
    });

    test('Must be morning does not wrap and fills completely through end of line', () {
      const content = 'Must be morning';
      final words = [
        LyricsWord(content: 'Must', startTimeMs: 1000, endTimeMs: 1400),
        LyricsWord(content: 'be', startTimeMs: 1400, endTimeMs: 1700),
        LyricsWord(content: 'morning', startTimeMs: 1700, endTimeMs: 2300),
      ];
      final ranges = resolveWordRanges(content, words);
      const style = TextStyle(fontSize: 42, letterSpacing: -1.5, fontWeight: FontWeight.w700);

      final tp = TextPainter(
        text: const TextSpan(text: content, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 800);

      // During active singing of "morning" (at 2000ms):
      final clipperMid = LyricsLineFillClipper(
        lineContent: content,
        words: words,
        wordRanges: ranges,
        lineEndTimeMs: 2500,
        style: style,
        layoutWidth: 800,
        positionMs: 2000,
      );

      final clipMid = clipperMid.getClip(Size(tp.width, tp.height));
      final boundsMid = clipMid.getBounds();

      // Bounds must stay within line height (no lower line artifact)
      expect(boundsMid.top, equals(0.0));
      expect(boundsMid.bottom, closeTo(tp.height, 1.0));
      // Must cover more than half of the total width
      expect(boundsMid.width, greaterThan(tp.width * 0.5));
      expect(boundsMid.width, lessThan(tp.width));

      // Upon completion of the line (at 2350ms):
      final clipperEnd = LyricsLineFillClipper(
        lineContent: content,
        words: words,
        wordRanges: ranges,
        lineEndTimeMs: 2500,
        style: style,
        layoutWidth: 800,
        positionMs: 2350,
      );

      final clipEnd = clipperEnd.getClip(Size(tp.width, tp.height));
      final boundsEnd = clipEnd.getBounds();
      // Entire line must be fully revealed
      expect(boundsEnd.width, greaterThanOrEqualTo(tp.width));
    });

    test('LyricsLineFillClipper distributes fill across wrapped lines sequentially without leaking into lower line', () {
      const content = 'So let it happen, let it happen';
      final words = [
        LyricsWord(content: 'So', startTimeMs: 0, endTimeMs: 300),
        LyricsWord(content: 'let', startTimeMs: 300, endTimeMs: 600),
        LyricsWord(content: 'it', startTimeMs: 600, endTimeMs: 900),
        LyricsWord(content: 'happen,', startTimeMs: 900, endTimeMs: 1500),
        LyricsWord(content: 'let', startTimeMs: 1500, endTimeMs: 1800),
        LyricsWord(content: 'it', startTimeMs: 1800, endTimeMs: 2100),
        LyricsWord(content: 'happen', startTimeMs: 2100, endTimeMs: 2700),
      ];
      final ranges = resolveWordRanges(content, words);
      const style = TextStyle(fontSize: 30);

      // Layout constrained to 220px to force wrapping
      final tp = TextPainter(
        text: const TextSpan(text: content, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 220);

      final lineMetrics = tp.computeLineMetrics();
      expect(lineMetrics.length, greaterThanOrEqualTo(2));
      final firstLineHeight = lineMetrics.first.height;

      // At position 450ms (halfway through word 1 'let' on the first line):
      final clipperLine1 = LyricsLineFillClipper(
        lineContent: content,
        words: words,
        wordRanges: ranges,
        lineEndTimeMs: 2700,
        style: style,
        layoutWidth: 220,
        positionMs: 450,
      );

      final clip1 = clipperLine1.getClip(Size(220, tp.height));
      final bounds1 = clip1.getBounds();

      // Ensure no clipping occurred below the first line
      expect(bounds1.bottom, closeTo(firstLineHeight, 1.0));
      expect(bounds1.width, greaterThan(0));
    });
  });
}
