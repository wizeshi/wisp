// Copyright © 2026 wizeshi

library;

import 'package:xml/xml.dart';
import 'package:wisp/data/models/metadata_models.dart';

/// Comprehensive TTML (Timed Text Markup Language) parser that converts
/// TTML XML documents into wisp [LyricsResult] structures.
class TtmlParser {
  const TtmlParser._();

  /// Parses the given [xmlContent] into a [LyricsResult].
  ///
  /// Supports:
  /// - Word-level, syllable-level, and line-level timestamps
  /// - Time formats: hh:mm:ss.sss, mm:ss.sss, ss.sss, ms, and s
  /// - begin, end, and dur attributes
  /// - Background vocals (ttm:role="x-bg", role="x-bg")
  /// - Singer / agent alignment (ttm:agent="v2" -> right speaker)
  /// - XML namespace prefix agnosticism (e.g. `<tt:p>`, `<p>`)
  static LyricsResult parse(
    String xmlContent, {
    String? defaultProviderName = 'Imported',
  }) {
    final trimmed = xmlContent.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('TTML content is empty');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(trimmed);
    } catch (e) {
      throw FormatException('Failed to parse TTML XML: $e');
    }

    final pElements = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'p')
        .toList();

    if (pElements.isEmpty) {
      throw const FormatException('No lyric lines (<p>) found in TTML file');
    }

    final lines = <LyricsLine>[];

    for (final p in pElements) {
      final line = _parseLine(p);
      if (line != null) {
        lines.add(line);
      }
    }

    if (lines.isEmpty) {
      throw const FormatException('No valid lyric lines could be extracted');
    }

    // Determine overall sync mode
    final hasWords = lines.any((l) => l.hasWordTiming);
    final hasTimedLines = lines.any((l) => l.startTimeMs > 0 || l.endTimeMs != null);
    final syncMode = hasWords
        ? LyricsSyncMode.word
        : hasTimedLines
            ? LyricsSyncMode.line
            : LyricsSyncMode.unsynced;

    return LyricsResult(
      provider: LyricsProviderType.custom,
      customProviderName: defaultProviderName ?? 'Imported',
      syncMode: syncMode,
      attribution: 'Imported from local TTML file',
      lines: lines,
    );
  }

  static LyricsLine? _parseLine(XmlElement p) {
    final beginAttr = _getAttribute(p, 'begin');
    final endAttr = _getAttribute(p, 'end');
    final durAttr = _getAttribute(p, 'dur');
    final agentAttr = _getAttribute(p, 'agent') ?? _getAttribute(p, 'role');

    final lineStartMs = parseTimeMs(beginAttr) ?? 0;
    var lineEndMs = parseTimeMs(endAttr);
    if (lineEndMs == null && durAttr != null) {
      final dur = parseTimeMs(durAttr);
      if (dur != null) {
        lineEndMs = lineStartMs + dur;
      }
    }

    final speaker = _resolveSpeaker(agentAttr);

    // Identify any background vocal container spans
    final allSpans = p.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'span')
        .toList();

    final bgSpans = <XmlElement>[];
    for (final s in allSpans) {
      final role = (_getAttribute(s, 'role') ?? '').toLowerCase();
      final agent = (_getAttribute(s, 'agent') ?? '').toLowerCase();
      final cls = (_getAttribute(s, 'class') ?? '').toLowerCase();
      if (role.contains('bg') ||
          agent.contains('bg') ||
          cls.contains('bg') ||
          role == 'x-bg') {
        bgSpans.add(s);
      }
    }

    // Extract background vocal lines
    final bgLines = <BackgroundVocalLine>[];
    final bgDescendantSpans = <XmlElement>{};
    for (final bgSpan in bgSpans) {
      bgDescendantSpans.add(bgSpan);
      bgDescendantSpans.addAll(
        bgSpan.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'span'),
      );

      final bgLine = _parseBackgroundVocalLine(bgSpan, lineStartMs);
      if (bgLine != null) {
        bgLines.add(bgLine);
      }
    }

    // Extract lead words from spans that are NOT inside background spans
    final leadLeafSpans = <XmlElement>[];
    for (final span in allSpans) {
      if (bgDescendantSpans.contains(span)) continue;

      // Check if leaf span (has no child spans)
      final hasChildSpan = span.children
          .whereType<XmlElement>()
          .any((c) => c.name.local.toLowerCase() == 'span');
      if (!hasChildSpan && span.innerText.trim().isNotEmpty) {
        leadLeafSpans.add(span);
      }
    }

    final leadWords = <LyricsWord>[];
    for (var i = 0; i < leadLeafSpans.length; i++) {
      final span = leadLeafSpans[i];
      final rawText = span.innerText;
      final cleanWord = _cleanWhitespace(rawText);
      if (cleanWord.isEmpty) continue;

      final sBegin = _getAttribute(span, 'begin');
      final sEnd = _getAttribute(span, 'end');
      final sDur = _getAttribute(span, 'dur');

      final wStart = parseTimeMs(sBegin) ?? lineStartMs;
      var wEnd = parseTimeMs(sEnd);
      if (wEnd == null && sDur != null) {
        final dur = parseTimeMs(sDur);
        if (dur != null) wEnd = wStart + dur;
      }

      final isPartOfWordAttr = _getAttribute(span, 'partOfWord');
      final bool isPartOfWord;
      if (isPartOfWordAttr != null) {
        isPartOfWord = isPartOfWordAttr.toLowerCase() == 'true';
      } else if (cleanWord.endsWith('-')) {
        isPartOfWord = true;
      } else {
        isPartOfWord = false;
      }

      leadWords.add(LyricsWord(
        content: cleanWord,
        startTimeMs: wStart,
        endTimeMs: wEnd,
        partOfWord: isPartOfWord,
      ));
    }

    // Sort words chronologically
    leadWords.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));

    // Construct line content with proper inter-word spaces
    String lineContent;
    if (leadWords.isNotEmpty) {
      final buffer = StringBuffer();
      for (var i = 0; i < leadWords.length; i++) {
        final w = leadWords[i];
        final wordText = w.content;

        // If this word is standalone trailing punctuation, attach to previous word
        if (i > 0 &&
            RegExp(r'^[.,!?:;)\]]+$').hasMatch(wordText) &&
            buffer.isNotEmpty &&
            buffer.toString().endsWith(' ')) {
          final str = buffer.toString();
          buffer.clear();
          buffer.write(str.substring(0, str.length - 1));
        }

        buffer.write(wordText);

        if (i < leadWords.length - 1 && !w.partOfWord) {
          buffer.write(' ');
        }
      }
      lineContent = _cleanWhitespace(buffer.toString());
    } else {
      // If no lead words, use innerText excluding bg spans if possible
      final rawText = p.innerText;
      lineContent = _cleanWhitespace(rawText);
    }

    if (lineContent.isEmpty && bgLines.isEmpty) {
      return null;
    }

    if (lineEndMs == null && leadWords.isNotEmpty) {
      lineEndMs = leadWords.last.endTimeMs;
    }

    return LyricsLine(
      content: lineContent.isNotEmpty
          ? lineContent
          : (bgLines.isNotEmpty ? bgLines.first.content : ''),
      startTimeMs: lineStartMs,
      endTimeMs: lineEndMs,
      words: leadWords,
      speaker: speaker,
      background: bgLines,
    );
  }

  static BackgroundVocalLine? _parseBackgroundVocalLine(
    XmlElement bgSpan,
    int fallbackStartMs,
  ) {
    final beginAttr = _getAttribute(bgSpan, 'begin');
    final endAttr = _getAttribute(bgSpan, 'end');
    final durAttr = _getAttribute(bgSpan, 'dur');

    final bgStartMs = parseTimeMs(beginAttr) ?? fallbackStartMs;
    var bgEndMs = parseTimeMs(endAttr);
    if (bgEndMs == null && durAttr != null) {
      final dur = parseTimeMs(durAttr);
      if (dur != null) bgEndMs = bgStartMs + dur;
    }

    final childSpans = bgSpan.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'span')
        .toList();

    final leafSpans = childSpans.where((s) {
      return !s.children
          .whereType<XmlElement>()
          .any((c) => c.name.local.toLowerCase() == 'span') &&
          s.innerText.trim().isNotEmpty;
    }).toList();

    final bgWords = <LyricsWord>[];
    for (final s in leafSpans) {
      final rawText = s.innerText;
      final cleanWord = _cleanWhitespace(rawText);
      if (cleanWord.isEmpty) continue;

      final sBegin = _getAttribute(s, 'begin');
      final sEnd = _getAttribute(s, 'end');
      final sDur = _getAttribute(s, 'dur');

      final wStart = parseTimeMs(sBegin) ?? bgStartMs;
      var wEnd = parseTimeMs(sEnd);
      if (wEnd == null && sDur != null) {
        final dur = parseTimeMs(sDur);
        if (dur != null) wEnd = wStart + dur;
      }

      final isPartOfWordAttr = _getAttribute(s, 'partOfWord');
      final bool isPartOfWord;
      if (isPartOfWordAttr != null) {
        isPartOfWord = isPartOfWordAttr.toLowerCase() == 'true';
      } else if (cleanWord.endsWith('-')) {
        isPartOfWord = true;
      } else {
        isPartOfWord = false;
      }

      bgWords.add(LyricsWord(
        content: cleanWord,
        startTimeMs: wStart,
        endTimeMs: wEnd,
        partOfWord: isPartOfWord,
      ));
    }

    bgWords.sort((a, b) => a.startTimeMs.compareTo(b.startTimeMs));

    final String cleanContent;
    if (bgWords.isNotEmpty) {
      final buffer = StringBuffer();
      for (var i = 0; i < bgWords.length; i++) {
        final w = bgWords[i];
        final wordText = w.content;

        if (i > 0 &&
            RegExp(r'^[.,!?:;)\]]+$').hasMatch(wordText) &&
            buffer.isNotEmpty &&
            buffer.toString().endsWith(' ')) {
          final str = buffer.toString();
          buffer.clear();
          buffer.write(str.substring(0, str.length - 1));
        }

        buffer.write(wordText);

        if (i < bgWords.length - 1 && !w.partOfWord) {
          buffer.write(' ');
        }
      }
      cleanContent = _cleanWhitespace(buffer.toString());
    } else {
      final rawContent = bgSpan.innerText;
      cleanContent = _cleanWhitespace(rawContent);
    }
    if (cleanContent.isEmpty) return null;

    if (bgEndMs == null && bgWords.isNotEmpty) {
      bgEndMs = bgWords.last.endTimeMs;
    }

    return BackgroundVocalLine(
      content: cleanContent,
      startTimeMs: bgStartMs,
      endTimeMs: bgEndMs,
      words: bgWords,
    );
  }

  /// Parses a TTML time representation into integer milliseconds.
  ///
  /// Formats supported:
  /// - `00:01:23.456` or `01:23.45` (colon-delimited mm:ss or hh:mm:ss)
  /// - `1234ms`
  /// - `12.34s`
  /// - `12.34` (unqualified seconds)
  static int? parseTimeMs(String? val) {
    if (val == null) return null;
    final trimmed = val.trim().toLowerCase();
    if (trimmed.isEmpty) return null;

    if (trimmed.endsWith('ms')) {
      final numStr = trimmed.substring(0, trimmed.length - 2).trim();
      final parsed = int.tryParse(numStr);
      return parsed ?? double.tryParse(numStr)?.round();
    }
    if (trimmed.endsWith('s')) {
      final numStr = trimmed.substring(0, trimmed.length - 1).trim();
      final parsed = double.tryParse(numStr);
      return parsed != null ? (parsed * 1000).round() : null;
    }
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      if (parts.length >= 2 && parts.length <= 4) {
        final secStr = parts.removeLast();
        final minStr = parts.removeLast();
        final hrStr = parts.isNotEmpty ? parts.removeLast() : '0';

        final sec = double.tryParse(secStr);
        final min = int.tryParse(minStr);
        final hr = int.tryParse(hrStr);
        if (sec != null && min != null && hr != null) {
          return (((hr * 3600) + (min * 60) + sec) * 1000).round();
        }
      }
      return null;
    }

    final num = double.tryParse(trimmed);
    if (num != null) {
      return (num * 1000).round();
    }
    return null;
  }

  static String? _getAttribute(XmlElement element, String localName) {
    final lowerName = localName.toLowerCase();
    for (final attr in element.attributes) {
      if (attr.name.local.toLowerCase() == lowerName) {
        return attr.value;
      }
    }
    return null;
  }

  static LyricSpeaker _resolveSpeaker(String? agentAttr) {
    if (agentAttr == null) return LyricSpeaker.left;
    final lower = agentAttr.toLowerCase();
    if (lower.contains('v2') ||
        lower.contains('secondary') ||
        lower.contains('opposite') ||
        lower.contains('right')) {
      return LyricSpeaker.right;
    }
    return LyricSpeaker.left;
  }

  static String _cleanWhitespace(String str) {
    return str.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

