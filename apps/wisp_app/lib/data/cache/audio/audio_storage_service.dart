// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/utils/json.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/models/audio_cache_entry.dart';
import 'package:wisp/data/sources/audio/models/audio_quality_info.dart';

enum StorageStatus {
  /// Normal storage usage (< 80% of max quota).
  normal,

  /// Warning state (>= 80% and < 95% of max quota).
  warning,

  /// Storage is at or near capacity (>= 95%), or no auto-cache tracks can be evicted.
  /// Auto-caching is paused to protect user downloads.
  fullPaused,
}

/// Service managing audio file storage on disk, LRU eviction of auto-cached files,
/// atomic file writes, and storage quotas.
class AudioStorageService extends ChangeNotifier {
  static final AudioStorageService instance = AudioStorageService._();
  AudioStorageService._();

  @visibleForTesting
  void resetForTesting() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _cacheEntries.clear();
    _normalizedTrackIdToKey.clear();
    _videoIdToKey.clear();
    _cacheDirectory = null;
    _indexFile = null;
    _backupIndexFile = null;
    _maxCacheSizeBytes = _defaultMaxCacheSize;
    _userDownloadsSizeBytes = 0;
    _autoCacheSizeBytes = 0;
    _initialized = false;
  }

  static const String _legacyPrefsKeyCacheEntries = 'cache_entries';
  static const String _prefsKeyMaxSize = 'cache_max_size';
  static const int _defaultMaxCacheSize = 750 * 1024 * 1024; // 750MB

  final Map<String, AudioCacheEntry> _cacheEntries = {};
  final Map<String, String> _normalizedTrackIdToKey = {};
  final Map<String, String> _videoIdToKey = {};
  Directory? _cacheDirectory;
  File? _indexFile;
  File? _backupIndexFile;
  Timer? _saveDebounceTimer;
  int _maxCacheSizeBytes = _defaultMaxCacheSize;
  bool _initialized = false;

  int _userDownloadsSizeBytes = 0;
  int _autoCacheSizeBytes = 0;

  // Getters
  bool get isInitialized => _initialized;
  Directory? get cacheDirectory => _cacheDirectory;
  int get maxCacheSizeBytes => _maxCacheSizeBytes;
  int get maxCacheSizeMB => _maxCacheSizeBytes ~/ (1024 * 1024);

  int get indexSizeBytes {
    try {
      if (_indexFile != null && _indexFile!.existsSync()) {
        return _indexFile!.lengthSync();
      }
    } catch (_) {}
    return 0;
  }

  int get userDownloadsSizeBytes => _userDownloadsSizeBytes;
  int get userDownloadsSizeMB => _userDownloadsSizeBytes ~/ (1024 * 1024);

  int get autoCacheSizeBytes => _autoCacheSizeBytes;
  int get autoCacheSizeMB => _autoCacheSizeBytes ~/ (1024 * 1024);

  int get totalCacheSizeBytes => _userDownloadsSizeBytes + _autoCacheSizeBytes;
  int get totalCacheSizeMB => totalCacheSizeBytes ~/ (1024 * 1024);

  int get cachedTrackCount => _cacheEntries.length;

  int get userDownloadCount =>
      _cacheEntries.values.where((e) => e.isUserDownload).length;

  int get autoCacheCount =>
      _cacheEntries.values.where((e) => !e.isUserDownload).length;

  Set<String> get cachedTrackIds => _cacheEntries.keys.toSet();

  List<AudioCacheEntry> get entries =>
      List.unmodifiable(_cacheEntries.values.toList());

  List<AudioCacheEntry> get userDownloads {
    final list = _cacheEntries.values.where((e) => e.isUserDownload).toList()
      ..sort((a, b) => b.downloadDate.compareTo(a.downloadDate));
    return List.unmodifiable(list);
  }

  List<AudioCacheEntry> get autoCachedTracks {
    final list = _cacheEntries.values.where((e) => !e.isUserDownload).toList()
      ..sort((a, b) => b.lastPlayedDate.compareTo(a.lastPlayedDate));
    return List.unmodifiable(list);
  }

  StorageStatus get storageStatus {
    if (_maxCacheSizeBytes <= 0) return StorageStatus.normal;
    final ratio = totalCacheSizeBytes / _maxCacheSizeBytes;
    if (ratio >= 0.95 || (ratio >= 1.0 && autoCacheCount == 0)) {
      return StorageStatus.fullPaused;
    }
    if (ratio >= 0.80) {
      return StorageStatus.warning;
    }
    return StorageStatus.normal;
  }

  bool get isStorageFull => storageStatus == StorageStatus.fullPaused;

  String normalizeTrackId(String trackId) {
    final trimmed = trackId.trim();
    if (!trimmed.contains(':')) return trimmed;
    final parts = trimmed.split(':');
    return parts.isNotEmpty ? parts.last : trimmed;
  }

  String buildSafeCacheFileName(String trackId, String videoId, {String extension = 'm4a'}) {
    final input = '$trackId|$videoId';
    final digest = sha1.convert(utf8.encode(input)).toString();
    final ext = extension.startsWith('.') ? extension.substring(1) : extension;
    return 'track_$digest.$ext';
  }

  /// Initialize the storage directory, load entries, and perform orphan reconciliation.
  Future<void> initialize({
    Directory? supportDirectory,
    Directory? cacheDirectory,
  }) async {
    if (_initialized) return;

    try {
      final appDir = cacheDirectory ?? await getApplicationCacheDirectory();
      _cacheDirectory = Directory('${appDir.path}/audio_cache');
      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
      }

      await _loadSettings();
      await _loadCacheEntries(supportDir: supportDirectory);
      await _reconcileDiskAndOrphans();
      _recalculateSizes();

      _initialized = true;
      logger.i(
        '[AudioStorageService] Initialized: $cachedTrackCount tracks ($totalCacheSizeMB MB / $maxCacheSizeMB MB). '
        'User downloads: $userDownloadCount ($userDownloadsSizeMB MB), Auto-cache: $autoCacheCount ($autoCacheSizeMB MB)',
      );
      notifyListeners();
    } catch (e) {
      logger.e('[AudioStorageService] Initialization error', error: e);
    }
  }

  String _normalizeDiskPath(String path) {
    final unified = path.replaceAll('\\', '/');
    return Platform.isWindows ? unified.toLowerCase() : unified;
  }

  void _indexEntry(String key, AudioCacheEntry entry) {
    final normTrack = normalizeTrackId(entry.trackId);
    if (normTrack.isNotEmpty) {
      _normalizedTrackIdToKey[normTrack] = key;
    }
    final normVideo = normalizeTrackId(entry.videoId);
    if (normVideo.isNotEmpty) {
      _videoIdToKey[normVideo] = key;
    }
  }

  void _unindexEntry(String key, AudioCacheEntry? entry) {
    if (entry == null) return;
    final normTrack = normalizeTrackId(entry.trackId);
    if (_normalizedTrackIdToKey[normTrack] == key) {
      _normalizedTrackIdToKey.remove(normTrack);
    }
    final normVideo = normalizeTrackId(entry.videoId);
    if (_videoIdToKey[normVideo] == key) {
      _videoIdToKey.remove(normVideo);
    }
  }

  AudioCacheEntry? _findEntry(String trackId) {
    final key = normalizeTrackId(trackId);
    final direct = _cacheEntries[key];
    if (direct != null) return direct;

    final byTrackId = _normalizedTrackIdToKey[key];
    if (byTrackId != null) {
      final entry = _cacheEntries[byTrackId];
      if (entry != null) return entry;
    }

    final byVideoId = _videoIdToKey[key];
    if (byVideoId != null) {
      final entry = _cacheEntries[byVideoId];
      if (entry != null) return entry;
    }
    return null;
  }

  bool isTrackCached(String trackId) {
    return _findEntry(trackId) != null;
  }

  bool isTrackUserDownload(String trackId) {
    return _findEntry(trackId)?.isUserDownload ?? false;
  }

  AudioCacheEntry? getEntry(String trackId) {
    return _findEntry(trackId);
  }

  String? getCachedPath(String trackId) {
    return _findEntry(trackId)?.filePath;
  }

  Future<void> updateLastPlayed(String trackId) async {
    final entry = _findEntry(trackId);
    if (entry != null) {
      entry.lastPlayedDate = DateTime.now();
      await _saveCacheEntries();
    }
  }

  /// Promotes an existing auto-cached entry to a protected user download.
  Future<void> promoteToUserDownload(String trackId) async {
    final entry = _findEntry(trackId);
    if (entry != null && !entry.isUserDownload) {
      entry.isUserDownload = true;
      _recalculateSizes();
      await _saveCacheEntries(immediate: true);
      notifyListeners();
      logger.i('[AudioStorageService] Promoted ${entry.trackId} to user download');
    }
  }

  /// Ensures capacity for a new file.
  ///
  /// For auto-cached tracks:
  /// - Only auto-cached files are pruned via LRU.
  /// - User-downloaded files are NEVER evicted.
  /// - If the limit is reached and all auto-cached files are pruned, returns `false` (stop caching).
  ///
  /// For user downloads:
  /// - Prunes auto-cached files to make room.
  /// - Never evicts other user downloads.
  Future<bool> ensureCapacity({
    required int requiredBytes,
    required bool isUserDownload,
  }) async {
    if (totalCacheSizeBytes + requiredBytes <= _maxCacheSizeBytes) {
      return true;
    }

    logger.d(
      '[AudioStorageService] Need ${(requiredBytes / 1024 / 1024).toStringAsFixed(1)} MB '
      '(Current: $totalCacheSizeMB MB / $maxCacheSizeMB MB). Pruning auto-cache...',
    );

    // Get all auto-cached entries sorted by lastPlayedDate (oldest first)
    final candidates = _cacheEntries.values
        .where((e) => !e.isUserDownload)
        .toList()
      ..sort((a, b) => a.lastPlayedDate.compareTo(b.lastPlayedDate));

    for (final candidate in candidates) {
      if (totalCacheSizeBytes + requiredBytes <= _maxCacheSizeBytes) {
        break;
      }
      logger.i(
        '[AudioStorageService] Evicting oldest auto-cached entry: ${candidate.trackTitle ?? candidate.trackId}',
      );
      await _deleteEntryFile(candidate);
      _unindexEntry(candidate.trackId, _cacheEntries.remove(candidate.trackId));
      _recalculateSizes();
    }

    await _saveCacheEntries(immediate: true);
    notifyListeners();

    final hasSpace = totalCacheSizeBytes + requiredBytes <= _maxCacheSizeBytes;
    if (!hasSpace) {
      if (!isUserDownload) {
        logger.w(
          '[AudioStorageService] Storage limit reached and no auto-cached files left to prune. '
          'Pausing auto-cache to protect user downloads.',
        );
      }
      return false;
    }

    return true;
  }

  /// Registers a newly completed download file into the cache index.
  ///
  /// Atomically moves the temporary `.part` file to the final destination file,
  /// verifies length, creates the cache entry, and updates sizes.
  Future<AudioCacheEntry> registerCompletedDownload({
    required String trackId,
    required String videoId,
    required String tempPartPath,
    required String finalFilePath,
    required String trackTitle,
    required String artistName,
    required bool isUserDownload,
    ActiveTrackQualityInfo? qualityInfo,
  }) async {
    final key = normalizeTrackId(trackId);
    final tempFile = File(tempPartPath);
    if (!await tempFile.exists()) {
      throw Exception('Temporary download file not found: $tempPartPath');
    }

    final fileSize = await tempFile.length();
    if (fileSize <= 0) {
      await tempFile.delete();
      throw Exception('Downloaded file is empty (0 bytes)');
    }

    final finalFile = File(finalFilePath);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(finalFilePath);

    final now = DateTime.now();
    final entry = AudioCacheEntry(
      trackId: key,
      videoId: videoId,
      filePath: finalFilePath,
      fileSize: fileSize,
      trackTitle: trackTitle,
      artistName: artistName,
      downloadDate: now,
      lastPlayedDate: now,
      isUserDownload: isUserDownload,
      qualityInfo: qualityInfo,
    );

    _cacheEntries[key] = entry;
    _indexEntry(key, entry);
    _recalculateSizes();
    await _saveCacheEntries(immediate: true);
    notifyListeners();

    // Check if we pushed over quota with this download and prune auto-cache if needed
    if (totalCacheSizeBytes > _maxCacheSizeBytes) {
      await ensureCapacity(requiredBytes: 0, isUserDownload: isUserDownload);
    }

    return entry;
  }

  /// Remove a single entry and its physical file.
  Future<void> removeEntry(String trackId) async {
    final entry = _findEntry(trackId);
    if (entry == null) return;

    logger.i('[AudioStorageService] Removing track: ${entry.trackId}');
    await _deleteEntryFile(entry);
    final removed = _cacheEntries.remove(entry.trackId);
    _unindexEntry(entry.trackId, removed);
    if (removed == null) {
      // Handle entries keyed by non-trackId key in legacy indexes
      final matchingKeys = _cacheEntries.entries
          .where((e) => identical(e.value, entry))
          .map((e) => e.key)
          .toList();
      for (final k in matchingKeys) {
        _unindexEntry(k, _cacheEntries.remove(k));
      }
    }
    _recalculateSizes();
    await _saveCacheEntries(immediate: true);
    notifyListeners();
  }

  /// Clears only auto-cached files, leaving user-downloaded songs untouched.
  Future<void> clearAutoCache() async {
    final autoCached =
        _cacheEntries.entries.where((e) => !e.value.isUserDownload).toList();
    for (final mapEntry in autoCached) {
      await _deleteEntryFile(mapEntry.value);
      _unindexEntry(mapEntry.key, _cacheEntries.remove(mapEntry.key));
    }
    _recalculateSizes();
    await _saveCacheEntries(immediate: true);
    notifyListeners();
    logger.i('[AudioStorageService] Cleared ${autoCached.length} auto-cached files');
  }

  /// Clears all user downloads, leaving auto-cache untouched.
  Future<void> clearUserDownloads() async {
    final userList =
        _cacheEntries.entries.where((e) => e.value.isUserDownload).toList();
    for (final mapEntry in userList) {
      await _deleteEntryFile(mapEntry.value);
      _unindexEntry(mapEntry.key, _cacheEntries.remove(mapEntry.key));
    }
    _recalculateSizes();
    await _saveCacheEntries(immediate: true);
    notifyListeners();
    logger.i('[AudioStorageService] Cleared ${userList.length} user downloads');
  }

  /// Clears all audio files (both user downloads and auto-cache).
  Future<void> clearAll() async {
    for (final entry in _cacheEntries.values) {
      await _deleteEntryFile(entry);
    }
    _cacheEntries.clear();
    _normalizedTrackIdToKey.clear();
    _videoIdToKey.clear();
    _recalculateSizes();
    await _saveCacheEntries(immediate: true);
    notifyListeners();
    logger.i('[AudioStorageService] All audio cache cleared');
  }

  Future<void> setMaxCacheSizeBytes(int bytes) async {
    _maxCacheSizeBytes = bytes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyMaxSize, _maxCacheSizeBytes);
    _recalculateSizes();
    if (totalCacheSizeBytes > _maxCacheSizeBytes) {
      await ensureCapacity(requiredBytes: 0, isUserDownload: false);
    }
    notifyListeners();
  }

  void _recalculateSizes() {
    int userSize = 0;
    int autoSize = 0;
    for (final entry in _cacheEntries.values) {
      if (entry.isUserDownload) {
        userSize += entry.fileSize;
      } else {
        autoSize += entry.fileSize;
      }
    }
    _userDownloadsSizeBytes = userSize;
    _autoCacheSizeBytes = autoSize;
  }

  Future<void> _deleteEntryFile(AudioCacheEntry entry) async {
    try {
      final file = File(entry.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      logger.e('[AudioStorageService] Error deleting file: ${entry.filePath}', error: e);
    }
  }

  static final RegExp _m4aSuffixRegex = RegExp(r'\.m4a$');

  Future<void> _reconcileDiskAndOrphans() async {
    final dir = _cacheDirectory;
    if (dir == null || !await dir.exists()) return;

    try {
      final diskFiles = <String, File>{};
      final m4aFiles = <File>[];

      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final path = entity.path;
        if (path.endsWith('.part') || path.endsWith('.tmp')) {
          try {
            await entity.delete();
            logger.d('[AudioStorageService] Cleaned up temporary file: $path');
          } catch (_) {}
          continue;
        }
        diskFiles[_normalizeDiskPath(path)] = entity;
        if (path.endsWith('.m4a')) {
          m4aFiles.add(entity);
        }
      }

      // SAFEGUARD: Cleanup duplicate corrupted .m4a files where a corresponding .ogg exists.
      for (final m4aFile in m4aFiles) {
        final oggPath = m4aFile.path.replaceAll(_m4aSuffixRegex, '.ogg');
        if (diskFiles.containsKey(_normalizeDiskPath(oggPath))) {
          logger.i('[AudioStorageService] Removing duplicate corrupted .m4a file: ${m4aFile.path}');
          try {
            await m4aFile.delete();
            diskFiles.remove(_normalizeDiskPath(m4aFile.path));
          } catch (_) {}
        }
      }

      // If an existing entry was pointing to .m4a but .ogg exists, migrate it.
      var migratedEntries = false;
      for (final MapEntry(:key, :value) in _cacheEntries.entries.toList()) {
        if (value.filePath.endsWith('.m4a')) {
          final oggPath = value.filePath.replaceAll(_m4aSuffixRegex, '.ogg');
          final oggFile = diskFiles[_normalizeDiskPath(oggPath)];
          if (oggFile != null) {
            final updated = value.copyWith(
              filePath: oggPath,
              fileSize: await oggFile.length(),
            );
            _cacheEntries[key] = updated;
            _indexEntry(key, updated);
            migratedEntries = true;
          }
        }
      }

      // SAFEGUARD: Never delete valid audio files on startup!
      // Verify registered entries exist in the single directory snapshot (or asynchronously if outside dir.path).
      final normalizedDirPrefix = '${_normalizeDiskPath(dir.path)}/';
      final missingKeys = <String>[];
      for (final entry in _cacheEntries.entries) {
        final normPath = _normalizeDiskPath(entry.value.filePath);
        if (normPath.startsWith(normalizedDirPrefix)) {
          if (!diskFiles.containsKey(normPath)) {
            missingKeys.add(entry.key);
          }
        } else if (!await File(entry.value.filePath).exists()) {
          missingKeys.add(entry.key);
        }
      }
      if (missingKeys.isNotEmpty) {
        logger.w(
          '[AudioStorageService] Pruned ${missingKeys.length} registered entries whose files no longer exist on disk',
        );
        for (final k in missingKeys) {
          _unindexEntry(k, _cacheEntries.remove(k));
        }
      }
      if (missingKeys.isNotEmpty || migratedEntries) {
        await _saveCacheEntries(immediate: true);
      }
    } catch (e) {
      logger.w('[AudioStorageService] Error reconciling disk files', error: e);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _maxCacheSizeBytes =
          prefs.getInt(_prefsKeyMaxSize) ?? _defaultMaxCacheSize;
    } catch (e) {
      logger.e('[AudioStorageService] Error loading settings', error: e);
    }
  }

  Future<void> _loadCacheEntries({Directory? supportDir}) async {
    try {
      final dir = supportDir ?? await getApplicationSupportDirectory();
      _indexFile = File('${dir.path}/audio_cache_index.json');
      _backupIndexFile = File('${dir.path}/audio_cache_index.json.bak');

      bool loadedFromFile = false;

      // 1. Try reading primary index file
      if (await _indexFile!.exists()) {
        try {
          final content = await _indexFile!.readAsString();
          if (content.trim().isNotEmpty) {
            final parsed = _parseEntriesJson(content);
            if (parsed) {
              loadedFromFile = true;
              logger.i(
                '[AudioStorageService] Loaded ${_cacheEntries.length} entries from audio_cache_index.json',
              );
            }
          }
        } catch (e) {
          logger.e(
            '[AudioStorageService] Failed reading primary audio_cache_index.json, trying backup',
            error: e,
          );
        }
      }

      // 2. If primary failed or was empty, try backup file
      if (!loadedFromFile && await _backupIndexFile!.exists()) {
        try {
          final content = await _backupIndexFile!.readAsString();
          if (content.trim().isNotEmpty) {
            final parsed = _parseEntriesJson(content);
            if (parsed) {
              loadedFromFile = true;
              logger.w(
                '[AudioStorageService] Restored ${_cacheEntries.length} entries from audio_cache_index.json.bak',
              );
            }
          }
        } catch (e) {
          logger.e(
            '[AudioStorageService] Failed reading backup audio_cache_index.json.bak',
            error: e,
          );
        }
      }

      // 3. One-time migration from legacy SharedPreferences
      await _migrateFromLegacyPrefs();
    } catch (e) {
      logger.e('[AudioStorageService] Error loading cache entries', error: e);
    }
  }

  bool _parseEntriesJson(String jsonString) {
    try {
      final decoded = json.decode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }
      for (final entry in decoded.entries) {
        try {
          final cacheEntry = AudioCacheEntry.fromJson(
            entry.value as Map<String, dynamic>,
          );
          _cacheEntries[entry.key] = cacheEntry;
          _indexEntry(entry.key, cacheEntry);
        } catch (e) {
          logger.w(
            '[AudioStorageService] Error parsing cache entry ${entry.key}',
            error: e,
          );
        }
      }
      return true;
    } catch (e) {
      logger.e('[AudioStorageService] Error parsing cache entries JSON', error: e);
      return false;
    }
  }

  Future<void> _migrateFromLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyJson = prefs.getString(_legacyPrefsKeyCacheEntries);
      if (legacyJson != null && legacyJson.trim().isNotEmpty) {
        final Map<String, dynamic> legacyMap = json.decode(legacyJson);
        var migrated = 0;
        for (final entry in legacyMap.entries) {
          if (!_cacheEntries.containsKey(entry.key)) {
            try {
              final cacheEntry = AudioCacheEntry.fromJson(
                entry.value as Map<String, dynamic>,
              );
              if (await File(cacheEntry.filePath).exists()) {
                _cacheEntries[entry.key] = cacheEntry;
                _indexEntry(entry.key, cacheEntry);
                migrated++;
              }
            } catch (_) {}
          }
        }

        // Clean up legacy key so shared_preferences.json stays clean
        await prefs.remove(_legacyPrefsKeyCacheEntries);
        if (migrated > 0 || _cacheEntries.isNotEmpty) {
          await _saveCacheEntries(immediate: true);
        }
        logger.i(
          '[AudioStorageService] Migrated $migrated legacy entries from SharedPreferences and removed key',
        );
      }
    } catch (e) {
      logger.w(
        '[AudioStorageService] Legacy cache entries migration skipped',
        error: e,
      );
    }
  }

  Future<void> _saveCacheEntries({bool immediate = false}) async {
    if (immediate) {
      _saveDebounceTimer?.cancel();
      await _flushEntriesToDisk();
    } else {
      _saveDebounceTimer?.cancel();
      _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        unawaited(_flushEntriesToDisk());
      });
    }
  }

  Future<void> _flushEntriesToDisk() async {
    if (_indexFile == null) return;

    try {
      final entriesMap = <String, dynamic>{};
      for (final entry in _cacheEntries.entries) {
        entriesMap[entry.key] = entry.value.toJson();
      }
      final jsonString = await JsonUtils.encode(
        entriesMap,
        itemCountHint: entriesMap.length,
      );

      // 1. If primary index exists and has content, back it up
      if (await _indexFile!.exists()) {
        try {
          if (_backupIndexFile != null) {
            await _indexFile!.copy(_backupIndexFile!.path);
          }
        } catch (_) {}
      }

      // 2. Write directly with flush: true
      await _indexFile!.writeAsString(jsonString, flush: true);
    } catch (e) {
      logger.e(
        '[AudioStorageService] Error saving cache entries to disk',
        error: e,
      );
    }
  }
}
