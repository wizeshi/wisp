// Copyright © 2026 wizeshi

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/ttml_parser.dart';

void main() {
  group('TtmlParser Time Parsing Tests', () {
    test('parses colon-separated time formats correctly', () {
      expect(TtmlParser.parseTimeMs('00:01:23.456'), equals(83456));
      expect(TtmlParser.parseTimeMs('01:23.450'), equals(83450));
      expect(TtmlParser.parseTimeMs('00:00:05.000'), equals(5000));
      expect(TtmlParser.parseTimeMs('00:05'), equals(5000));
      expect(TtmlParser.parseTimeMs('01:05'), equals(65000));
    });

    test('parses suffix unit time formats correctly', () {
      expect(TtmlParser.parseTimeMs('1500ms'), equals(1500));
      expect(TtmlParser.parseTimeMs('2.5s'), equals(2500));
      expect(TtmlParser.parseTimeMs('10s'), equals(10000));
    });

    test('parses raw floating seconds', () {
      expect(TtmlParser.parseTimeMs('12.345'), equals(12345));
      expect(TtmlParser.parseTimeMs('0'), equals(0));
    });

    test('returns null on invalid or empty times', () {
      expect(TtmlParser.parseTimeMs(null), isNull);
      expect(TtmlParser.parseTimeMs(''), isNull);
      expect(TtmlParser.parseTimeMs('abc'), isNull);
    });
  });

  group('TtmlParser XML Document Tests', () {
    test('parses word-synced TTML with Apple Music / BetterLyrics extensions', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<tt xmlns="http://www.w3.org/ns/ttml"
    xmlns:ttm="http://www.w3.org/ns/ttml#metadata"
    xmlns:itunes="http://music.apple.com/lyric-ttml-extensions">
  <head>
    <metadata>
      <ttm:title>Test Track</ttm:title>
    </metadata>
  </head>
  <body>
    <div>
      <p begin="00:00:10.000" end="00:00:14.000" ttm:agent="v1">
        <span begin="00:00:10.000" end="00:00:10.500">Never </span>
        <span begin="00:00:10.500" end="00:00:11.000">gonna </span>
        <span begin="00:00:11.000" end="00:00:12.000">give </span>
        <span begin="00:00:12.000" end="00:00:12.500">you </span>
        <span begin="00:00:12.500" end="00:00:14.000">up</span>
      </p>
      <p begin="00:00:15.000" end="00:00:18.000" ttm:agent="v2">
        <span begin="00:00:15.000" end="00:00:16.000">Never </span>
        <span begin="00:00:16.000" end="00:00:18.000">mind</span>
      </p>
    </div>
  </body>
</tt>''';

      final result = TtmlParser.parse(xml);
      expect(result.syncMode, equals(LyricsSyncMode.word));
      expect(result.lines.length, equals(2));

      // Line 1
      final l1 = result.lines[0];
      expect(l1.startTimeMs, equals(10000));
      expect(l1.endTimeMs, equals(14000));
      expect(l1.speaker, equals(LyricSpeaker.left));
      expect(l1.content, equals('Never gonna give you up'));
      expect(l1.words.length, equals(5));
      expect(l1.words[0].content, equals('Never'));
      expect(l1.words[0].startTimeMs, equals(10000));
      expect(l1.words[0].endTimeMs, equals(10500));
      expect(l1.words[4].content, equals('up'));
      expect(l1.words[4].startTimeMs, equals(12500));
      expect(l1.words[4].endTimeMs, equals(14000));

      // Line 2 (v2 = opposite/right speaker)
      final l2 = result.lines[1];
      expect(l2.startTimeMs, equals(15000));
      expect(l2.endTimeMs, equals(18000));
      expect(l2.speaker, equals(LyricSpeaker.right));
      expect(l2.content, equals('Never mind'));
      expect(l2.words.length, equals(2));
    });

    test('parses dur attributes and background vocal spans', () {
      const xml = '''<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
  <body>
    <div>
      <p begin="00:05.000" dur="4000ms">
        <span begin="00:05.000" dur="500ms">Hello </span>
        <span begin="00:05.500" dur="500ms">world</span>
        <span ttm:role="x-bg" begin="00:06.500" dur="2000ms">
          <span begin="00:06.500" dur="1000ms">(hello </span>
          <span begin="00:07.500" dur="1000ms">again)</span>
        </span>
      </p>
    </div>
  </body>
</tt>''';

      final result = TtmlParser.parse(xml);
      expect(result.syncMode, equals(LyricsSyncMode.word));
      expect(result.lines.length, equals(1));

      final line = result.lines[0];
      expect(line.startTimeMs, equals(5000));
      expect(line.endTimeMs, equals(9000));
      expect(line.content, equals('Hello world'));
      expect(line.words.length, equals(2));
      expect(line.words[0].content, equals('Hello'));
      expect(line.words[0].startTimeMs, equals(5000));
      expect(line.words[0].endTimeMs, equals(5500));

      // Background vocals
      expect(line.hasBackground, isTrue);
      expect(line.background.length, equals(1));
      final bg = line.background[0];
      expect(bg.startTimeMs, equals(6500));
      expect(bg.endTimeMs, equals(8500));
      expect(bg.content, contains('hello again'));
      expect(bg.words.length, equals(2));
    });

    test('parses line-synced TTML when no word spans are present', () {
      const xml = '''<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:10.000" end="00:15.000">First line of song</p>
      <p begin="00:15.500" end="00:20.000">Second line of song</p>
    </div>
  </body>
</tt>''';

      final result = TtmlParser.parse(xml);
      expect(result.syncMode, equals(LyricsSyncMode.line));
      expect(result.lines.length, equals(2));
      expect(result.lines[0].content, equals('First line of song'));
      expect(result.lines[0].startTimeMs, equals(10000));
      expect(result.lines[0].endTimeMs, equals(15000));
      expect(result.lines[0].words, isEmpty);
    });

    test('throws FormatException on empty or invalid XML', () {
      expect(() => TtmlParser.parse(''), throwsFormatException);
      expect(() => TtmlParser.parse('<tt>no p tags</tt>'), throwsFormatException);
      expect(() => TtmlParser.parse('<not xml'), throwsFormatException);
    });

    test('parses SpicyLyrics new_lyrics.xml with proper word spacing and syllables', () {
      final file = File('temp/new_lyrics.xml');
      if (!file.existsSync()) return;

      final xml = file.readAsStringSync();
      final result = TtmlParser.parse(xml);

      expect(result.syncMode, equals(LyricsSyncMode.word));

      // Line 1: Cá puta Vitor!
      final l1 = result.lines[0];
      expect(l1.content, equals('Cá puta Vitor!'));
      expect(l1.words.length, equals(3));
      expect(l1.words[0].content, equals('Cá'));
      expect(l1.words[1].content, equals('puta'));
      expect(l1.words[2].content, equals('Vitor!'));

      // Line 2: Entra no Jaguar, eu tou de Sergio Tacchini
      final l2 = result.lines[1];
      expect(l2.content, equals('Entra no Jaguar, eu tou de Sergio Tacchini'));
      expect(l2.hasBackground, isTrue);
      expect(l2.background.first.content, equals('(No Jaguar, Tacchini)'));

      // Line 6: amanhã eu vou buscá-los
      final l6 = result.lines[5];
      expect(l6.content, contains('buscá-los'));
      expect(l6.background.first.content, contains('buscá-los'));
    });
  });
}

