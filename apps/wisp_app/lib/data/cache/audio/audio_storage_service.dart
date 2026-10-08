// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/models/audio_cache_entry.dart';

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

  AudioCacheEntry? _findEntry(String trackId) {
    final key = normalizeTrackId(trackId);
    final direct = _cacheEntries[key];
    if (direct != null) return direct;

    for (final entry in _cacheEntries.values) {
      if (normalizeTrackId(entry.videoId) == key ||
          normalizeTrackId(entry.trackId) == key) {
        return entry;
      }
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
    final entry = _findEntry(trackId);
    if (entry == null) return null;

    final file = File(entry.filePath);
    if (!file.existsSync()) {
      logger.w('[AudioStorageService] Cached file missing from disk: $trackId');
      _cacheEntries.remove(entry.trackId);
      _recalculateSizes();
      _saveCacheEntries(immediate: true);
      notifyListeners();
      return null;
    }

    // Corrupted file safeguard: if entry points to .m4a but a valid .ogg exists
    // (e.g. from Spotify AES-CTR decryption), prefer the .ogg file and clean up the corrupted .m4a.
    if (entry.filePath.endsWith('.m4a')) {
      final oggPath = entry.filePath.replaceAll(RegExp(r'\.m4a$'), '.ogg');
      final oggFile = File(oggPath);
      if (oggFile.existsSync()) {
        logger.i('[AudioStorageService] Found valid .ogg file replacing corrupted .m4a: $oggPath');
        try {
          file.deleteSync();
        } catch (_) {}
        final updatedEntry = entry.copyWith(
          filePath: oggPath,
          fileSize: oggFile.lengthSync(),
        );
        _cacheEntries[entry.trackId] = updatedEntry;
        _saveCacheEntries(immediate: true);
        return oggPath;
      }
    }

    return entry.filePath;
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
      _cacheEntries.remove(candidate.trackId);
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
    );

    _cacheEntries[key] = entry;
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
    _cacheEntries.remove(entry.trackId);
    _recalculateSizes();
    await _saveCacheEntries(immediate: true);
    notifyListeners();
  }

  /// Clears only auto-cached files, leaving user-downloaded songs untouched.
  Future<void> clearAutoCache() async {
    final autoCached = _cacheEntries.values.where((e) => !e.isUserDownload).toList();
    for (final entry in autoCached) {
      await _deleteEntryFile(entry);
      _cacheEntries.remove(entry.trackId);
    }
    _recalculateSizes();
    await _saveCacheEntries(immediate: true);
    notifyListeners();
    logger.i('[AudioStorageService] Cleared ${autoCached.length} auto-cached files');
  }

  /// Clears all user downloads, leaving auto-cache untouched.
  Future<void> clearUserDownloads() async {
    final userList = _cacheEntries.values.where((e) => e.isUserDownload).toList();
    for (final entry in userList) {
      await _deleteEntryFile(entry);
      _cacheEntries.remove(entry.trackId);
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

  Future<void> _reconcileDiskAndOrphans() async {
    final dir = _cacheDirectory;
    if (dir == null || !await dir.exists()) return;

    try {
      final entities = dir.listSync();

      // Clean up temporary/incomplete download files (.part / .tmp)
      for (final entity in entities) {
        if (entity is File) {
          final path = entity.path;
          if (path.endsWith('.part') || path.endsWith('.tmp')) {
            try {
              entity.deleteSync();
              logger.d('[AudioStorageService] Cleaned up temporary file: $path');
            } catch (_) {}
          }
        }
      }

      // SAFEGUARD: Cleanup duplicate corrupted .m4a files where a corresponding .ogg exists.
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.m4a')) {
          final oggPath = entity.path.replaceAll(RegExp(r'\.m4a$'), '.ogg');
          if (File(oggPath).existsSync()) {
            logger.i('[AudioStorageService] Removing duplicate corrupted .m4a file: ${entity.path}');
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }

      // If an existing entry was pointing to .m4a but .ogg exists, migrate it
      for (final MapEntry(:key, :value) in _cacheEntries.entries.toList()) {
        if (value.filePath.endsWith('.m4a')) {
          final oggPath = value.filePath.replaceAll(RegExp(r'\.m4a$'), '.ogg');
          final oggFile = File(oggPath);
          if (oggFile.existsSync()) {
            _cacheEntries[key] = value.copyWith(
              filePath: oggPath,
              fileSize: oggFile.lengthSync(),
            );
          }
        }
      }

      // SAFEGUARD: Never delete valid audio files on startup!
      // If the index failed to load or experienced a timing glitch, deleting audio files
      // would wipe the user's entire offline music library.
      // Instead, we verify that registered entries still exist on disk and prune
      // any dead index keys.
      final missingKeys = <String>[];
      for (final entry in _cacheEntries.entries) {
        if (!File(entry.value.filePath).existsSync()) {
          missingKeys.add(entry.key);
        }
      }
      if (missingKeys.isNotEmpty) {
        logger.w(
          '[AudioStorageService] Pruned ${missingKeys.length} registered entries whose files no longer exist on disk',
        );
        for (final k in missingKeys) {
          _cacheEntries.remove(k);
        }
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
          if (File(cacheEntry.filePath).existsSync()) {
            _cacheEntries[entry.key] = cacheEntry;
          }
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
              if (File(cacheEntry.filePath).existsSync()) {
                _cacheEntries[entry.key] = cacheEntry;
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
      final jsonString = json.encode(entriesMap);

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
