library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wisp/models/metadata_models.dart';
import 'package:wisp/utils/logger.dart';
import 'package:xml/xml.dart';

const _betterLyricsBaseUrl = "https://lyrics-api.boidu.dev/getLyrics";
const _betterLyricsUserAgent =
		'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
		'(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 wisp/1.0.0';

class BetterLyricsProvider {
  Future<LyricsResult?> getLyrics(GenericSong song, LyricsSyncMode mode) async {
    final artistName = song.artists.map((artist) => artist.name).join(", ");
    final trackName = song.title;

    final uri = Uri.parse(_betterLyricsBaseUrl).replace(
			queryParameters: {
				'artist': artistName,
				'song': trackName,
			},
		);

    final response = await http.get(
			uri,
			headers: {
				'Accept': 'application/json',
				'User-Agent': _betterLyricsUserAgent,
			},
		);

    if (response.statusCode == 401) {
      logger.e("[Lyrics/BetterLyrics]: Failed to fetch lyrics for ${song.title} - $artistName: Unauthorized. This song is not cached by them yet.");
      return null;
    }

    if (response.statusCode != 200) {
      logger.e("[Lyrics/BetterLyrics]: Failed to fetch lyrics for ${song.title} - $artistName. Status code: ${response.statusCode}");
      return null;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final lyrics = _normalizeTtmlSource((data['ttml'] as String?) ?? '');

      if (lyrics.trim().isEmpty) {
        return null;
      }

      final parsed = _parseTtmlLyrics(lyrics);
      if (parsed.lines.isEmpty) {
        return null;
      }

      final normalized = _normalizeTimings(parsed);

      if (mode == LyricsSyncMode.unsynced) {
        return _asUnsynced(normalized);
      }

      if (mode == LyricsSyncMode.line) {
        return _asLineLyrics(normalized);
      }

      return normalized.hasWordTiming ? normalized : _asLineLyrics(normalized);
    } catch (e) {
      logger.e(
        "[Lyrics/BetterLyrics]: Failed to parse lyrics for ${song.title} - $artistName.",
        error: e,
      );
      return null;
    }
  }

  LyricsResult _asLineLyrics(LyricsResult result) {
    return LyricsResult(
      provider: LyricsProviderType.betterlyrics,
      syncMode: LyricsSyncMode.line,
      lines: result.lines
          .map(
            (line) => LyricsLine(
              content: line.content,
              startTimeMs: line.startTimeMs,
              endTimeMs: line.endTimeMs,
            ),
          )
          .toList(),
    );
  }

  LyricsResult _asUnsynced(LyricsResult result) {
    return LyricsResult(
      provider: LyricsProviderType.betterlyrics,
      syncMode: LyricsSyncMode.unsynced,
      lines: result.lines
          .map(
            (line) => LyricsLine(
              content: line.content,
              startTimeMs: 0,
            ),
          )
          .toList(),
    );
  }

  LyricsResult _parseTtmlLyrics(String ttml) {
    final sanitizedTtml = ttml.contains(r'\"') ? ttml.replaceAll(r'\"', '"') : ttml;
    final document = XmlDocument.parse(sanitizedTtml);
    final lines = <LyricsLine>[];

    for (final paragraph in document.findAllElements('p')) {
      final startTimeMs = _parseTimeMs(paragraph.getAttribute('begin')) ?? 0;
      final endTimeMs = _parseTimeMs(paragraph.getAttribute('end'));
      final wordMatches = _extractWordMatches(paragraph, startTimeMs);
      final content = _normalizeText(paragraph.innerText);
      lines.add(
        LyricsLine(
          content: content,
          startTimeMs: startTimeMs,
          endTimeMs: endTimeMs ?? wordMatches.lastOrNull?.endTimeMs,
          words: wordMatches,
        ),
      );
    }

    return LyricsResult(
      provider: LyricsProviderType.betterlyrics,
      syncMode: lines.any((line) => line.hasWordTiming)
          ? LyricsSyncMode.word
          : LyricsSyncMode.line,
      lines: lines,
    );
  }

  String _normalizeTtmlSource(String ttml) {
    return ttml
      .replaceAll('\\"', '"')
      .replaceAll('\\n', '\n')
      .replaceAll('\\r', '\r');
  }

  LyricsResult _normalizeTimings(LyricsResult result) {
    final timestamps = <int>[];
    for (final line in result.lines) {
      timestamps.add(line.startTimeMs);
      for (final word in line.words) {
        timestamps.add(word.startTimeMs);
      }
    }

    final positiveTimestamps = timestamps.where((value) => value > 0).toList(growable: false);
    if (positiveTimestamps.isEmpty) {
      return result;
    }

    final minTimestamp = positiveTimestamps.reduce((a, b) => a < b ? a : b);
    if (minTimestamp <= 0) {
      return result;
    }

    int shiftValue(int value) => (value - minTimestamp).clamp(0, 1 << 31).toInt();

    return LyricsResult(
      provider: result.provider,
      syncMode: result.syncMode,
      lines: result.lines
          .map(
            (line) => LyricsLine(
              content: line.content,
              startTimeMs: shiftValue(line.startTimeMs),
              endTimeMs: line.endTimeMs == null ? null : shiftValue(line.endTimeMs!),
              words: line.words
                  .map(
                    (word) => LyricsWord(
                      content: word.content,
                      startTimeMs: shiftValue(word.startTimeMs),
                      endTimeMs: word.endTimeMs == null ? null : shiftValue(word.endTimeMs!),
                    ),
                  )
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
  }

  List<LyricsWord> _extractWordMatches(XmlElement paragraph, int fallbackStartMs) {
    final words = <LyricsWord>[];

    void visit(XmlNode node) {
      if (node is! XmlElement) return;

      if (node.name.local == 'span') {
        final hasTimingAttribute =
            node.getAttribute('begin') != null ||
            node.getAttribute('end') != null ||
            node.getAttribute('dur') != null;
        if (hasTimingAttribute) {
          final innerText = _normalizeText(node.innerText);
          if (innerText.isNotEmpty) {
            final startTimeMs =
                _parseTimeMs(node.getAttribute('begin')) ?? fallbackStartMs;
            final endTimeMs = _parseTimeMs(node.getAttribute('end')) ??
                _parseTimeMs(node.getAttribute('dur'));

            words.add(
              LyricsWord(
                content: innerText,
                startTimeMs: startTimeMs,
                endTimeMs: endTimeMs,
              ),
            );
          }
        }
      }

      for (final child in node.children) {
        visit(child);
      }
    }

    for (final child in paragraph.children) {
      visit(child);
    }

    return words;
  }

  int? _parseTimeMs(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    final lower = value.toLowerCase();
    if (lower.endsWith('ms')) {
      return int.tryParse(lower.substring(0, lower.length - 2).trim());
    }

    if (lower.endsWith('s')) {
      final seconds = double.tryParse(lower.substring(0, lower.length - 1).trim());
      return seconds == null ? null : (seconds * 1000).round();
    }

    final parts = lower.split(':');
    if (parts.length == 3 || parts.length == 2) {
      final secondsPart = parts.removeLast();
      final minutesPart = parts.removeLast();
      final hoursPart = parts.isEmpty ? '0' : parts.removeLast();
      final seconds = double.tryParse(secondsPart);
      final minutes = int.tryParse(minutesPart);
      final hours = int.tryParse(hoursPart);
      if (seconds == null || minutes == null || hours == null) {
        return null;
      }

      return (((hours * 3600) + (minutes * 60) + seconds) * 1000).round();
    }

    final plainNumber = double.tryParse(lower);
    if (plainNumber != null) {
      return (plainNumber * 1000).round();
    }

    return null;
  }

  String _stripTags(String text) {
    return text.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  String _normalizeText(String text) {
    final decoded = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');

    return decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}