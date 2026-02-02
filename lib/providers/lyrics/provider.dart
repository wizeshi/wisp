/// Lyrics provider facade with caching and fallback
library;

import 'package:flutter/foundation.dart';
import '../../models/metadata_models.dart';
import '../../services/metadata_cache.dart';
import 'lrclib.dart';

class LyricsFetchState {
  final bool isLoading;
  final LyricsResult? lyrics;
  final String? error;

  const LyricsFetchState({
    required this.isLoading,
    this.lyrics,
    this.error,
  });

  const LyricsFetchState.idle() : this(isLoading: false);

  LyricsFetchState copyWith({
    bool? isLoading,
    LyricsResult? lyrics,
    String? error,
  }) {
    return LyricsFetchState(
      isLoading: isLoading ?? this.isLoading,
      lyrics: lyrics ?? this.lyrics,
      error: error ?? this.error,
    );
  }
}

class LyricsProvider extends ChangeNotifier {
  final LrcLibLyricsProvider _lrcLibProvider = LrcLibLyricsProvider();
  final MetadataCacheStore _cacheStore = MetadataCacheStore.instance;
  static const String _cacheProvider = 'lyrics';

  final Map<String, LyricsFetchState> _cache = {};

  LyricsFetchState getState(GenericSong track, LyricsSyncMode mode) {
    return _cache[_key(track.id, mode)] ?? const LyricsFetchState.idle();
  }

  LyricsResult? getLyrics(GenericSong track, LyricsSyncMode mode) {
    return getState(track, mode).lyrics;
  }

  Future<void> ensureLyrics(GenericSong track, LyricsSyncMode mode) async {
    final key = _key(track.id, mode);
    final current = _cache[key];
    if (current?.isLoading == true) return;

    final cached = await _readCachedLyrics(track.id, mode);
    if (cached != null) {
      _cache[key] = LyricsFetchState(isLoading: false, lyrics: cached.lyrics);
      notifyListeners();
      if (!cached.isExpired) return;
    }

    if (current?.lyrics != null && cached == null) return;

    _cache[key] = const LyricsFetchState(isLoading: true);
    notifyListeners();

    try {
      final result = await _fetchLyrics(track, mode);
      _cache[key] = LyricsFetchState(isLoading: false, lyrics: result);
      if (result != null) {
        await _writeCachedLyrics(track.id, mode, result);
      }
    } catch (e) {
      _cache[key] = LyricsFetchState(
        isLoading: false,
        error: e.toString(),
      );
    }

    notifyListeners();
  }

  Future<LyricsResult?> _fetchLyrics(GenericSong track, LyricsSyncMode mode) async {
    final result = await _lrcLibProvider.getLyrics(track, mode);
    if (result == null) return null;
    return _normalizeResult(result, mode);
  }

  LyricsResult _normalizeResult(LyricsResult result, LyricsSyncMode mode) {
    if (mode == LyricsSyncMode.unsynced && result.synced) {
      return LyricsResult(
        provider: result.provider,
        synced: false,
        lines: result.lines
            .map((line) => LyricsLine(content: line.content, startTimeMs: 0))
            .toList(),
      );
    }
    return result;
  }

  String _key(String trackId, LyricsSyncMode mode) => '${trackId}_${mode.name}';

  Future<_LyricsCacheResult?> _readCachedLyrics(
    String trackId,
    LyricsSyncMode mode,
  ) async {
    final entry = await _cacheStore.readEntry(
      provider: _cacheProvider,
      type: mode.name,
      id: trackId,
    );
    if (entry == null) return null;
    try {
      final payload = entry.payload;
      final lyrics = _lyricsFromJson(payload);
      if (lyrics == null) return null;
      return _LyricsCacheResult(lyrics: lyrics, isExpired: entry.isExpired);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedLyrics(
    String trackId,
    LyricsSyncMode mode,
    LyricsResult result,
  ) async {
    await _cacheStore.writeEntry(
      provider: _cacheProvider,
      type: mode.name,
      id: trackId,
      payload: _lyricsToJson(result),
    );
  }

  Map<String, dynamic> _lyricsToJson(LyricsResult result) => {
        'provider': result.provider.name,
        'synced': result.synced,
        'lines': result.lines
            .map(
              (line) => {
                'content': line.content,
                'startTimeMs': line.startTimeMs,
              },
            )
            .toList(),
      };

  LyricsResult? _lyricsFromJson(Map<String, dynamic> json) {
    try {
      final provider = LyricsProviderType.values.firstWhere(
        (p) => p.name == json['provider'],
        orElse: () => LyricsProviderType.lrclib,
      );
      final synced = json['synced'] as bool? ?? false;
      final linesJson = (json['lines'] as List?) ?? const [];
      final lines = linesJson
          .whereType<Map<String, dynamic>>()
          .map(
            (line) => LyricsLine(
              content: line['content'] as String? ?? '',
              startTimeMs: line['startTimeMs'] as int? ?? 0,
            ),
          )
          .toList();
      return LyricsResult(provider: provider, synced: synced, lines: lines);
    } catch (_) {
      return null;
    }
  }
}

class _LyricsCacheResult {
  final LyricsResult lyrics;
  final bool isExpired;

  const _LyricsCacheResult({
    required this.lyrics,
    required this.isExpired,
  });
}
