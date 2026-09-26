// Copyright © 2026 wizeshi

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

  static const String _prefsKeyCacheEntries = 'cache_entries';
  static const String _prefsKeyMaxSize = 'cache_max_size';
  static const int _defaultMaxCacheSize = 750 * 1024 * 1024; // 750MB

  final Map<String, AudioCacheEntry> _cacheEntries = {};
  Directory? _cacheDirectory;
  int _maxCacheSizeBytes = _defaultMaxCacheSize;
  bool _initialized = false;

  int _userDownloadsSizeBytes = 0;
  int _autoCacheSizeBytes = 0;

  // Getters
  bool get isInitialized => _initialized;
  Directory? get cacheDirectory => _cacheDirectory;
  int get maxCacheSizeBytes => _maxCacheSizeBytes;
  int get maxCacheSizeMB => _maxCacheSizeBytes ~/ (1024 * 1024);

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

  String buildSafeCacheFileName(String trackId, String videoId) {
    final input = '$trackId|$videoId';
    final digest = sha1.convert(utf8.encode(input)).toString();
    return 'track_$digest.m4a';
  }

  /// Initialize the storage directory, load entries, and perform orphan reconciliation.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final appDir = await getApplicationCacheDirectory();
      _cacheDirectory = Directory('${appDir.path}/audio_cache');
      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
      }

      await _loadSettings();
      await _loadCacheEntries();
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

  bool isTrackCached(String trackId) {
    final key = normalizeTrackId(trackId);
    return _cacheEntries.containsKey(key);
  }

  bool isTrackUserDownload(String trackId) {
    final key = normalizeTrackId(trackId);
    return _cacheEntries[key]?.isUserDownload ?? false;
  }

  AudioCacheEntry? getEntry(String trackId) {
    final key = normalizeTrackId(trackId);
    return _cacheEntries[key];
  }

  String? getCachedPath(String trackId) {
    final key = normalizeTrackId(trackId);
    final entry = _cacheEntries[key];
    if (entry == null) return null;

    final file = File(entry.filePath);
    if (!file.existsSync()) {
      logger.w('[AudioStorageService] Cached file missing from disk: $trackId');
      _cacheEntries.remove(key);
      _recalculateSizes();
      _saveCacheEntries();
      notifyListeners();
      return null;
    }

    return entry.filePath;
  }

  Future<void> updateLastPlayed(String trackId) async {
    final key = normalizeTrackId(trackId);
    final entry = _cacheEntries[key];
    if (entry != null) {
      entry.lastPlayedDate = DateTime.now();
      await _saveCacheEntries();
    }
  }

  /// Promotes an existing auto-cached entry to a protected user download.
  Future<void> promoteToUserDownload(String trackId) async {
    final key = normalizeTrackId(trackId);
    final entry = _cacheEntries[key];
    if (entry != null && !entry.isUserDownload) {
      entry.isUserDownload = true;
      _recalculateSizes();
      await _saveCacheEntries();
      notifyListeners();
      logger.i('[AudioStorageService] Promoted $trackId to user download');
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

    await _saveCacheEntries();
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
    await _saveCacheEntries();
    notifyListeners();

    // Check if we pushed over quota with this download and prune auto-cache if needed
    if (totalCacheSizeBytes > _maxCacheSizeBytes) {
      await ensureCapacity(requiredBytes: 0, isUserDownload: isUserDownload);
    }

    return entry;
  }

  /// Remove a single entry and its physical file.
  Future<void> removeEntry(String trackId) async {
    final key = normalizeTrackId(trackId);
    final entry = _cacheEntries[key];
    if (entry == null) return;

    logger.i('[AudioStorageService] Removing track: $trackId');
    await _deleteEntryFile(entry);
    _cacheEntries.remove(key);
    _recalculateSizes();
    await _saveCacheEntries();
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
    await _saveCacheEntries();
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
    await _saveCacheEntries();
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
    await _saveCacheEntries();
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
      final validFilePaths = _cacheEntries.values.map((e) => e.filePath).toSet();
      final entities = dir.listSync();

      for (final entity in entities) {
        if (entity is File) {
          final path = entity.path;
          // Delete abandoned .part or .tmp files
          if (path.endsWith('.part') || path.endsWith('.tmp')) {
            try {
              entity.deleteSync();
              logger.d('[AudioStorageService] Cleaned up temporary file: $path');
            } catch (_) {}
          } else if (path.endsWith('.m4a') && !validFilePaths.contains(path)) {
            // Orphan m4a file not registered in index
            try {
              entity.deleteSync();
              logger.i('[AudioStorageService] Deleted orphan audio file: $path');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      logger.w('[AudioStorageService] Error reconciling disk orphans', error: e);
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

  Future<void> _loadCacheEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entriesJson = prefs.getString(_prefsKeyCacheEntries);
      if (entriesJson != null) {
        final Map<String, dynamic> entriesMap = json.decode(entriesJson);
        for (final entry in entriesMap.entries) {
          try {
            final cacheEntry = AudioCacheEntry.fromJson(
              entry.value as Map<String, dynamic>,
            );
            if (File(cacheEntry.filePath).existsSync()) {
              _cacheEntries[entry.key] = cacheEntry;
            }
          } catch (e) {
            logger.w(
              '[AudioStorageService] Error loading entry ${entry.key}',
              error: e,
            );
          }
        }
      }
    } catch (e) {
      logger.e('[AudioStorageService] Error loading cache entries', error: e);
    }
  }

  Future<void> _saveCacheEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entriesMap = <String, dynamic>{};
      for (final entry in _cacheEntries.entries) {
        entriesMap[entry.key] = entry.value.toJson();
      }
      await prefs.setString(_prefsKeyCacheEntries, json.encode(entriesMap));
    } catch (e) {
      logger.e('[AudioStorageService] Error saving cache entries', error: e);
    }
  }
}
