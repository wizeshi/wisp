// Copyright © 2026 wizeshi

/// Lyrics provider facade with caching and fallback
library;

import 'package:flutter/foundation.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'lyrics_source.dart';
import 'lyrics_source_manager.dart';

class LyricsFetchState {
  final bool isLoading;
  final LyricsResult? lyrics;
  final String? error;
  final bool hasFetched;

  const LyricsFetchState({
    required this.isLoading,
    this.lyrics,
    this.error,
    this.hasFetched = false,
  });

  const LyricsFetchState.idle() : this(isLoading: false);

  LyricsFetchState copyWith({
    bool? isLoading,
    LyricsResult? lyrics,
    String? error,
    bool? hasFetched,
  }) {
    return LyricsFetchState(
      isLoading: isLoading ?? this.isLoading,
      lyrics: lyrics ?? this.lyrics,
      error: error ?? this.error,
      hasFetched: hasFetched ?? this.hasFetched,
    );
  }
}

class LyricsProvider extends ChangeNotifier {
  final LyricsSourceManager _sourceManager = LyricsSourceManager.instance;
  final MetadataCacheStore _cacheStore = MetadataCacheStore.instance;
  static const String _cacheProvider = 'lyrics_v2';
  static const String _delayCacheType = 'delay';
  static const Duration _errorRetryCooldown = Duration(seconds: 30);

  LyricsProvider() {
    _sourceManager.initialize();
    _sourceManager.addListener(_onSourcesChanged);
  }

  void _onSourcesChanged() {
    // When providers reload or change, clear cached empty results so tracks can be re-queried
    _cache.removeWhere((key, state) => state.lyrics == null);
    _lastErrorAt.clear();
    notifyListeners();
  }

  final Map<String, LyricsFetchState> _cache = {};
  final Map<String, DateTime> _lastErrorAt = {};
  final Set<String> _lyricsInFlight = {};
  final Map<String, double> _delayCache = {};
  final Set<String> _delayLoading = {};

  bool get hasSources => _sourceManager.allSources.isNotEmpty;
  bool get isInitialized => _sourceManager.isInitialized;

  LyricsFetchState getState(GenericSong track, LyricsSyncMode mode) {
    final direct = _cache[_key(track.id, mode)];
    if (direct != null && direct.lyrics != null) return direct;
    if (mode == LyricsSyncMode.line) {
      final word = _cache[_key(track.id, LyricsSyncMode.word)];
      if (word != null && word.lyrics != null) return word;
    }
    return direct ?? const LyricsFetchState.idle();
  }

  LyricsResult? getLyrics(GenericSong track, LyricsSyncMode mode) {
    return getState(track, mode).lyrics;
  }

  Future<void> ensureLyrics(GenericSong track, LyricsSyncMode mode) async {
    final key = _key(track.id, mode);
    final current = _cache[key];
    if (current?.isLoading == true || _lyricsInFlight.contains(key)) {
      logger.d('[LyricsProvider] Lyrics request in-flight for $key');
      return;
    }

    if (current != null && current.hasFetched && current.error == null) {
      return;
    }

    // Ensure lyrics sources are fully loaded before processing request
    if (!_sourceManager.isInitialized) {
      logger.i(
        '[LyricsProvider] Waiting for LyricsSourceManager initialization before ensureLyrics...',
      );
      await _sourceManager.initialize();
    }

    if (_sourceManager.allSources.isEmpty) {
      _cache[key] = const LyricsFetchState(isLoading: false, hasFetched: true);
      notifyListeners();
      return;
    }

    logger.i(
      '[LyricsProvider] ensureLyrics for "${track.title}" (id: ${track.id}, source: ${track.source}, mode: ${mode.name})',
    );

    _lyricsInFlight.add(key);

    try {
      final lastErrorAt = _lastErrorAt[key];
      if (lastErrorAt != null) {
        final sinceError = DateTime.now().difference(lastErrorAt);
        if (sinceError < _errorRetryCooldown) {
          logger.w(
            '[LyricsProvider] Skipping fetch for $key: retry cooldown (${sinceError.inSeconds}s < ${_errorRetryCooldown.inSeconds}s)',
          );
          return;
        }
      }

      final cached = await _readCachedLyrics(track.id, mode);
      if (cached != null) {
        logger.i(
          '[LyricsProvider] Cache hit for "${track.title}" (${cached.lyrics.lines.length} lines, sync: ${cached.lyrics.syncMode.name})',
        );
        _cache[key] = LyricsFetchState(
          isLoading: false,
          lyrics: cached.lyrics,
          hasFetched: true,
        );
        notifyListeners();
        if (!cached.isExpired) return;
      }

      if (current?.lyrics != null && cached == null) return;

      _cache[key] = LyricsFetchState(
        isLoading: true,
        lyrics: current?.lyrics,
        hasFetched: current?.hasFetched ?? false,
      );
      notifyListeners();

      try {
        final result = await _fetchLyrics(track, mode);
        _cache[key] = LyricsFetchState(
          isLoading: false,
          lyrics: result,
          hasFetched: true,
        );
        _lastErrorAt.remove(key);
        if (result != null) {
          logger.i(
            '[LyricsProvider] Successfully resolved lyrics for "${track.title}" via ${result.providerLabel} (${result.lines.length} lines, sync: ${result.syncMode.name})',
          );
          await _writeCachedLyrics(track.id, mode, result);
          if (result.isWordSynced) {
            final wordState = LyricsFetchState(
              isLoading: false,
              lyrics: result,
              hasFetched: true,
            );
            _cache[_key(track.id, LyricsSyncMode.word)] = wordState;
            _cache[_key(track.id, LyricsSyncMode.line)] = wordState;
            await _writeCachedLyrics(track.id, LyricsSyncMode.word, result);
            await _writeCachedLyrics(track.id, LyricsSyncMode.line, result);
          } else if (result.isLineSynced) {
            final lineState = LyricsFetchState(
              isLoading: false,
              lyrics: result,
              hasFetched: true,
            );
            _cache[_key(track.id, LyricsSyncMode.line)] = lineState;
            await _writeCachedLyrics(track.id, LyricsSyncMode.line, result);
          }
        } else {
          logger.w(
            '[LyricsProvider] No lyrics found across any provider for "${track.title}"',
          );
        }
      } catch (e, stack) {
        logger.e(
          '[LyricsProvider] Error during _fetchLyrics for "${track.title}": $e',
          error: e,
          stackTrace: stack,
        );
        _cache[key] = LyricsFetchState(
          isLoading: false,
          error: e.toString(),
          hasFetched: true,
        );
        _lastErrorAt[key] = DateTime.now();
      }

      notifyListeners();
    } finally {
      _lyricsInFlight.remove(key);
    }
  }

  double getDelaySecondsCached(String trackId) {
    return _delayCache[trackId] ?? 0;
  }

  Future<double> getDelaySeconds(String trackId) async {
    if (_delayCache.containsKey(trackId)) {
      return _delayCache[trackId] ?? 0;
    }
    final delay = await _readCachedDelay(trackId);
    _delayCache[trackId] = delay;
    return delay;
  }

  Future<void> ensureDelayLoaded(String trackId) async {
    if (_delayCache.containsKey(trackId) || _delayLoading.contains(trackId)) {
      return;
    }
    _delayLoading.add(trackId);
    final delay = await _readCachedDelay(trackId);
    _delayCache[trackId] = delay;
    _delayLoading.remove(trackId);
    notifyListeners();
  }

  Future<void> setDelaySeconds(String trackId, double seconds) async {
    _delayCache[trackId] = seconds;
    notifyListeners();
    await _writeCachedDelay(trackId, seconds);
  }

  Future<LyricsResult?> _fetchLyrics(
    GenericSong track,
    LyricsSyncMode mode,
  ) async {
    if (!_sourceManager.isInitialized) {
      await _sourceManager.initialize();
    }
    logger.i(
      '[LyricsProvider] Cascade started for "${track.title}" (mode: ${mode.name}). Registered sources (${_sourceManager.allSources.length}): ${_sourceManager.allSources.map((s) => "${s.name}[${s.id},prio=${s.priority}]").join(", ")}',
    );

    // Map to stash results returned by providers across tiers to avoid redundant network calls.
    // E.g., if a provider asked for word mode returns line-synced lyrics, we stash it here.
    final Map<String, LyricsResult> sessionResults = {};
    final Set<String> failedSources = {};

    Future<LyricsResult?> fetchFromSource(
      LyricsSource source,
      LyricsSyncMode targetMode,
    ) async {
      if (failedSources.contains(source.id)) {
        logger.d('[LyricsProvider] Skipping previously failed source: ${source.id}');
        return null;
      }

      // Check if provider is enabled in preferences
      final isEnabled =
          await PreferencesProvider.isProviderEnabledStatic(source.id);
      if (!isEnabled) {
        logger.i('[LyricsProvider] Source ${source.name} (${source.id}) is DISABLED in preferences');
        return null;
      }

      logger.i(
        '[LyricsProvider] -> Fetching from ${source.name} (${source.id}) for mode: ${targetMode.name}...',
      );

      try {
        final result = await _sourceManager.fetchWithSource(
          sourceId: source.id,
          song: track,
          mode: targetMode,
        );
        if (result != null && result.lines.isNotEmpty) {
          logger.i(
            '[LyricsProvider] <- ${source.name} (${source.id}) SUCCESS: ${result.lines.length} lines (sync: ${result.syncMode.name})',
          );
          sessionResults[source.id] = result;
          return result;
        } else {
          logger.w(
            '[LyricsProvider] <- ${source.name} (${source.id}) returned no lyrics',
          );
          failedSources.add(source.id);
          return null;
        }
      } catch (e, stack) {
        logger.e(
          '[LyricsProvider] <- ${source.name} (${source.id}) threw error: $e',
          error: e,
          stackTrace: stack,
        );
        failedSources.add(source.id);
        return null;
      }
    }

    // ------------------------------------------------------------------------
    // TIER 1: Word-synced cascade (all sources supporting word sync by priority)
    // ------------------------------------------------------------------------
    final wordSources = _sourceManager.getSourcesForMode(LyricsSyncMode.word);
    logger.i(
      '[LyricsProvider] Tier 1 (Word sync) sources: ${wordSources.map((s) => "${s.name}(${s.priority})").join(", ")}',
    );
    for (final source in wordSources) {
      final result = await fetchFromSource(source, LyricsSyncMode.word);
      if (result != null && result.isWordSynced) {
        logger.i(
          '[LyricsProvider] Tier 1 hit: Word-synced from ${result.providerLabel} (priority: ${source.priority})',
        );
        return _normalizeResult(result, mode);
      }
      // If result was line-synced or unsynced, it is stashed in sessionResults
      // so Tier 2 or 3 will pick it up without an extra HTTP call!
    }

    // ------------------------------------------------------------------------
    // TIER 2: Line-synced cascade (all sources supporting line sync by priority)
    // ------------------------------------------------------------------------
    final lineSources = _sourceManager.getSourcesForMode(LyricsSyncMode.line);
    logger.i(
      '[LyricsProvider] Tier 2 (Line sync) sources: ${lineSources.map((s) => "${s.name}(${s.priority})").join(", ")}',
    );
    for (final source in lineSources) {
      LyricsResult? result = sessionResults[source.id];
      if (result == null && !failedSources.contains(source.id)) {
        result = await fetchFromSource(source, LyricsSyncMode.line);
      }

      if (result != null && result.isLineSynced) {
        logger.i(
          '[LyricsProvider] Tier 2 hit: Line-synced from ${result.providerLabel} (priority: ${source.priority})',
        );
        return _normalizeResult(result, mode);
      }
    }

    // ------------------------------------------------------------------------
    // TIER 3: Unsynced cascade (all sources supporting unsynced by priority)
    // ------------------------------------------------------------------------
    final unsyncedSources =
        _sourceManager.getSourcesForMode(LyricsSyncMode.unsynced);
    logger.i(
      '[LyricsProvider] Tier 3 (Unsynced) sources: ${unsyncedSources.map((s) => "${s.name}(${s.priority})").join(", ")}',
    );
    for (final source in unsyncedSources) {
      LyricsResult? result = sessionResults[source.id];
      if (result == null && !failedSources.contains(source.id)) {
        result = await fetchFromSource(source, LyricsSyncMode.unsynced);
      }

      if (result != null && result.lines.isNotEmpty) {
        logger.i(
          '[LyricsProvider] Tier 3 hit: Unsynced from ${result.providerLabel} (priority: ${source.priority})',
        );
        return _normalizeResult(result, mode);
      }
    }

    return null;
  }

  LyricsResult _normalizeResult(LyricsResult result, LyricsSyncMode mode) {
    if (result.hasWordTiming &&
        result.syncMode != LyricsSyncMode.word &&
        mode != LyricsSyncMode.unsynced) {
      return LyricsResult(
        provider: result.provider,
        customProviderName: result.customProviderName,
        syncMode: LyricsSyncMode.word,
        lines: result.lines,
      );
    }

    if (mode == LyricsSyncMode.unsynced &&
        result.syncMode != LyricsSyncMode.unsynced) {
      return LyricsResult(
        provider: result.provider,
        customProviderName: result.customProviderName,
        syncMode: LyricsSyncMode.unsynced,
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
    // 1. Direct match in cache
    final entry = await _cacheStore.readEntry(
      provider: _cacheProvider,
      type: mode.name,
      id: trackId,
    );
    if (entry != null) {
      try {
        final payload = entry.payload;
        final lyrics = _lyricsFromJson(payload);
        if (lyrics != null) {
          return _LyricsCacheResult(lyrics: lyrics, isExpired: entry.isExpired);
        }
      } catch (_) {}
    }

    // 2. If requesting line or unsynced, check if higher-fidelity word cache exists
    if (mode == LyricsSyncMode.line || mode == LyricsSyncMode.unsynced) {
      final wordEntry = await _cacheStore.readEntry(
        provider: _cacheProvider,
        type: LyricsSyncMode.word.name,
        id: trackId,
      );
      if (wordEntry != null) {
        try {
          final lyrics = _lyricsFromJson(wordEntry.payload);
          if (lyrics != null) {
            return _LyricsCacheResult(
              lyrics: _normalizeResult(lyrics, mode),
              isExpired: wordEntry.isExpired,
            );
          }
        } catch (_) {}
      }
    }

    // 3. If requesting unsynced, check if line cache exists
    if (mode == LyricsSyncMode.unsynced) {
      final lineEntry = await _cacheStore.readEntry(
        provider: _cacheProvider,
        type: LyricsSyncMode.line.name,
        id: trackId,
      );
      if (lineEntry != null) {
        try {
          final lyrics = _lyricsFromJson(lineEntry.payload);
          if (lyrics != null) {
            return _LyricsCacheResult(
              lyrics: _normalizeResult(lyrics, mode),
              isExpired: lineEntry.isExpired,
            );
          }
        } catch (_) {}
      }
    }

    return null;
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

  Map<String, dynamic> _lyricsToJson(LyricsResult result) => result.toWlfJson();

  LyricsResult? _lyricsFromJson(Map<String, dynamic> json) {
    try {
      return LyricsResult.fromWlfJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<double> _readCachedDelay(String trackId) async {
    final entry = await _cacheStore.readEntry(
      provider: _cacheProvider,
      type: _delayCacheType,
      id: trackId,
    );
    if (entry == null) return 0;
    final payload = entry.payload;
    final value = payload['delaySeconds'];
    if (value is num) return value.toDouble();
    return 0;
  }

  Future<void> _writeCachedDelay(String trackId, double seconds) async {
    await _cacheStore.writeEntry(
      provider: _cacheProvider,
      type: _delayCacheType,
      id: trackId,
      payload: {'delaySeconds': seconds},
    );
  }

  Future<void> clearCache() async {
    _cache.clear();
    _lastErrorAt.clear();
    _lyricsInFlight.clear();
    _delayCache.clear();
    _delayLoading.clear();
    notifyListeners();
    await _cacheStore.clearProvider(_cacheProvider);
  }

  @override
  void dispose() {
    _sourceManager.removeListener(_onSourcesChanged);
    super.dispose();
  }
}

class _LyricsCacheResult {
  final LyricsResult lyrics;
  final bool isExpired;

  const _LyricsCacheResult({required this.lyrics, required this.isExpired});
}
