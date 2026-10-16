// Copyright © 2026 wizeshi

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/shared/widgets/lyrics/word_fill_lyrics_line.dart';

void main() {
  testWidgets('WordFillLyricsLine renders ClipPath when words have timing', (tester) async {
    const line = LyricsLine(
      content: 'Never gonna give you up',
      startTimeMs: 1000,
      endTimeMs: 3000,
      words: [
        LyricsWord(content: 'Never', startTimeMs: 1000, endTimeMs: 1400),
        LyricsWord(content: 'gonna', startTimeMs: 1400, endTimeMs: 1800),
        LyricsWord(content: 'give', startTimeMs: 1800, endTimeMs: 2200),
        LyricsWord(content: 'you', startTimeMs: 2200, endTimeMs: 2600),
        LyricsWord(content: 'up', startTimeMs: 2600, endTimeMs: 3000),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WordFillLyricsLine(
            line: line,
            positionMs: 1600,
            enableTicker: false,
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(WordFillLyricsLine),
        matching: find.byType(ClipPath),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(WordFillLyricsLine),
        matching: find.byType(Stack),
      ),
      findsOneWidget,
    );
    // Both inactive and active Text layers exist inside WordFillLyricsLine
    expect(
      find.descendant(
        of: find.byType(WordFillLyricsLine),
        matching: find.text('Never gonna give you up'),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('WordFillLyricsLine falls back to plain Text when no word timing', (tester) async {
    const line = LyricsLine(
      content: 'Line without word timings',
      startTimeMs: 1000,
      endTimeMs: 3000,
      words: [],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WordFillLyricsLine(
            line: line,
            positionMs: 2000,
            enableTicker: false,
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(WordFillLyricsLine),
        matching: find.byType(ClipPath),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(WordFillLyricsLine),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(WordFillLyricsLine),
        matching: find.text('Line without word timings'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('WordFillLyricsLine updates on positionMsListenable change', (tester) async {
    const line = LyricsLine(
      content: 'Test line word sync',
      startTimeMs: 1000,
      endTimeMs: 2000,
      words: [
        LyricsWord(content: 'Test', startTimeMs: 1000, endTimeMs: 1300),
        LyricsWord(content: 'line', startTimeMs: 1300, endTimeMs: 1600),
        LyricsWord(content: 'word', startTimeMs: 1600, endTimeMs: 1800),
        LyricsWord(content: 'sync', startTimeMs: 1800, endTimeMs: 2000),
      ],
    );

    final positionNotifier = ValueNotifier<int>(1100);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordFillLyricsLine(
            line: line,
            positionMsListenable: positionNotifier,
            enableTicker: false,
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(WordFillLyricsLine),
        matching: find.byType(ClipPath),
      ),
      findsOneWidget,
    );

    positionNotifier.value = 1700;
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(WordFillLyricsLine),
        matching: find.byType(ClipPath),
      ),
      findsOneWidget,
    );
  });

  testWidgets('WordFillLyricsLine wraps across multiple lines when maxLines is null', (tester) async {
    const line = LyricsLine(
      content: 'This is a very long line of lyrics that should definitely wrap onto multiple lines when constrained to a small width',
      startTimeMs: 1000,
      endTimeMs: 4000,
      words: [
        LyricsWord(content: 'This', startTimeMs: 1000, endTimeMs: 1200),
        LyricsWord(content: 'is', startTimeMs: 1200, endTimeMs: 1400),
        LyricsWord(content: 'a', startTimeMs: 1400, endTimeMs: 1600),
        LyricsWord(content: 'very', startTimeMs: 1600, endTimeMs: 1800),
        LyricsWord(content: 'long', startTimeMs: 1800, endTimeMs: 2000),
        LyricsWord(content: 'line', startTimeMs: 2000, endTimeMs: 2200),
        LyricsWord(content: 'of', startTimeMs: 2200, endTimeMs: 2400),
        LyricsWord(content: 'lyrics', startTimeMs: 2400, endTimeMs: 2600),
        LyricsWord(content: 'that', startTimeMs: 2600, endTimeMs: 2800),
        LyricsWord(content: 'should', startTimeMs: 2800, endTimeMs: 3000),
        LyricsWord(content: 'definitely', startTimeMs: 3000, endTimeMs: 3200),
        LyricsWord(content: 'wrap', startTimeMs: 3200, endTimeMs: 3400),
        LyricsWord(content: 'onto', startTimeMs: 3400, endTimeMs: 3600),
        LyricsWord(content: 'multiple', startTimeMs: 3600, endTimeMs: 3800),
        LyricsWord(content: 'lines', startTimeMs: 3800, endTimeMs: 4000),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 150,
            child: WordFillLyricsLine(
              line: line,
              positionMs: 1500,
              textStyle: TextStyle(fontSize: 20, height: 1.5),
              enableTicker: false,
            ),
          ),
        ),
      ),
    );

    final lineFinder = find.byType(WordFillLyricsLine);
    final size = tester.getSize(lineFinder);
    // Line height is 20 * 1.5 = 30. Wrapped across multiple lines, total height must be > 50.
    expect(size.height, greaterThan(50.0));
  });
}

