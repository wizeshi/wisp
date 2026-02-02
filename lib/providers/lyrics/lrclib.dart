/// LrcLib lyrics provider
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/metadata_models.dart';

const _lrclibBaseUrl = 'https://lrclib.net/api/get';
const _lrclibUserAgent =
		'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
		'(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 wisp/1.0.0';

class LrcLibLyricsProvider {
	Future<LyricsResult?> getLyrics(GenericSong song, LyricsSyncMode mode) async {
		final artistName = song.artists.map((artist) => artist.name).join(', ');
		final trackName = song.title;
		final albumName = song.album?.title ?? '';

		final uri = Uri.parse(_lrclibBaseUrl).replace(
			queryParameters: {
				'artist_name': artistName,
				'track_name': trackName,
				'album_name': albumName,
				'duration': song.durationSecs.toString(),
			},
		);

		final response = await http.get(
			uri,
			headers: {
				'Accept': 'application/json',
				'User-Agent': _lrclibUserAgent,
			},
		);

		if (response.statusCode != 200) return null;

		try {
			final data = jsonDecode(response.body) as Map<String, dynamic>;
			final syncedLyrics = (data['syncedLyrics'] as String?) ?? '';
			final plainLyrics = (data['plainLyrics'] as String?) ?? '';

			final hasSynced = syncedLyrics.trim().isNotEmpty;
			final hasPlain = plainLyrics.trim().isNotEmpty;

			if (mode == LyricsSyncMode.synced && hasSynced) {
				final lines = _parseSyncedLyrics(syncedLyrics);
				return LyricsResult(
					provider: LyricsProviderType.lrclib,
					synced: true,
					lines: lines,
				);
			}

			if (mode == LyricsSyncMode.unsynced && hasPlain) {
				final lines = _parsePlainLyrics(plainLyrics);
				return LyricsResult(
					provider: LyricsProviderType.lrclib,
					synced: false,
					lines: lines,
				);
			}

			if (hasSynced) {
				final lines = _parseSyncedLyrics(syncedLyrics);
				return LyricsResult(
					provider: LyricsProviderType.lrclib,
					synced: true,
					lines: lines,
				);
			}

			if (hasPlain) {
				final lines = _parsePlainLyrics(plainLyrics);
				return LyricsResult(
					provider: LyricsProviderType.lrclib,
					synced: false,
					lines: lines,
				);
			}
		} catch (_) {
			return null;
		}

		return null;
	}

	List<LyricsLine> _parseSyncedLyrics(String syncedLyrics) {
		return syncedLyrics
				.split('\n')
				.where((line) => line.trim().isNotEmpty)
				.map((line) {
			final match = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2})\]\s*(.*)')
					.firstMatch(line);
			if (match != null) {
				final minutes = int.parse(match.group(1)!);
				final seconds = int.parse(match.group(2)!);
				final centiseconds = int.parse(match.group(3)!);
				final content = match.group(4) ?? '';
				final startTimeMs =
						(minutes * 60 * 1000) + (seconds * 1000) + (centiseconds * 10);
				return LyricsLine(content: content, startTimeMs: startTimeMs);
			}
			return LyricsLine(content: line, startTimeMs: 0);
		}).toList();
	}

	List<LyricsLine> _parsePlainLyrics(String plainLyrics) {
		return plainLyrics
				.split('\n')
				.where((line) => line.trim().isNotEmpty)
				.map((line) => LyricsLine(content: line, startTimeMs: 0))
				.toList();
	}
}
