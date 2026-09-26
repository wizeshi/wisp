// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/utils/logger.dart';

/// Metadata entry representing a cached track -> YouTube video ID mapping.
class YouTubeMappingEntry {
  final String videoId;
  final String? title;
  final int? durationSecs;
  final DateTime resolvedAt;
  final bool isManualOverride;

  YouTubeMappingEntry({
    required this.videoId,
    this.title,
    this.durationSecs,
    DateTime? resolvedAt,
    this.isManualOverride = false,
  }) : resolvedAt = resolvedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    if (title != null) 'title': title,
    if (durationSecs != null) 'durationSecs': durationSecs,
    'resolvedAt': resolvedAt.toIso8601String(),
    'isManualOverride': isManualOverride,
  };

  factory YouTubeMappingEntry.fromJson(dynamic json) {
    if (json is String) {
      return YouTubeMappingEntry(videoId: json);
    }
    final map = json as Map<String, dynamic>;
    return YouTubeMappingEntry(
      videoId: map['videoId'] as String? ?? '',
      title: map['title'] as String?,
      durationSecs: map['durationSecs'] as int?,
      resolvedAt: map['resolvedAt'] != null
          ? DateTime.tryParse(map['resolvedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      isManualOverride: map['isManualOverride'] as bool? ?? false,
    );
  }
}

/// Standalone persistent store for track ID -> YouTube video ID mappings.
///
/// Stores mappings in a dedicated `youtube_mappings.json` file in
/// [getApplicationSupportDirectory], preventing SharedPreferences bloat.
/// Uses an in-memory L1 cache for instant O(1) synchronous lookups during playback,
/// and debounces atomic writes to disk.
class YouTubeMappingStore {
  static final YouTubeMappingStore instance = YouTubeMappingStore._();
  YouTubeMappingStore._();

  static const String _legacyPrefsKey = 'youtube_video_id_cache';
  static const Duration _debounceDuration = Duration(milliseconds: 1000);

  final Map<String, YouTubeMappingEntry> _mappings = {};
  File? _file;
  bool _initialized = false;
  bool _isDirty = false;
  Timer? _debounceTimer;

  bool get isInitialized => _initialized;
  bool get isDirty => _isDirty;
  int get count => _mappings.length;

  /// Returns total disk size of the mappings file in bytes.
  int get diskSizeBytes {
    try {
      if (_file != null && _file!.existsSync()) {
        return _file!.lengthSync();
      }
    } catch (_) {}
    return 0;
  }

  /// Initializes the store and performs one-time migration from SharedPreferences.
  Future<void> initialize({Directory? supportDirectory}) async {
    if (_initialized) return;

    try {
      final dir = supportDirectory ?? await getApplicationSupportDirectory();
      _file = File('${dir.path}/youtube_mappings.json');

      if (await _file!.exists()) {
        try {
          final content = await _file!.readAsString();
          if (content.trim().isNotEmpty) {
            final Map<String, dynamic> decoded = json.decode(content);
            for (final entry in decoded.entries) {
              _mappings[entry.key] = YouTubeMappingEntry.fromJson(entry.value);
            }
            logger.i(
              '[YouTubeMappingStore] Loaded ${_mappings.length} mappings from disk',
            );
          }
        } catch (e) {
          logger.e('[YouTubeMappingStore] Failed to read mappings file', error: e);
        }
      }

      // One-time migration from SharedPreferences
      await _migrateFromLegacyPrefs();

      _initialized = true;
    } catch (e) {
      logger.e('[YouTubeMappingStore] Initialization error', error: e);
      _initialized = true;
    }
  }

  Future<void> _migrateFromLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyJson = prefs.getString(_legacyPrefsKey);
      if (legacyJson != null && legacyJson.trim().isNotEmpty) {
        final Map<String, dynamic> legacyMap = json.decode(legacyJson);
        var migrated = 0;
        for (final entry in legacyMap.entries) {
          if (!_mappings.containsKey(entry.key)) {
            _mappings[entry.key] = YouTubeMappingEntry(
              videoId: entry.value.toString(),
            );
            migrated++;
          }
        }
        // Remove the bloated string from SharedPreferences
        await prefs.remove(_legacyPrefsKey);
        if (migrated > 0) {
          await flush();
        }
        logger.i(
          '[YouTubeMappingStore] Migrated $migrated legacy mappings from SharedPreferences and removed key',
        );
      }
    } catch (e) {
      logger.w('[YouTubeMappingStore] Legacy migration skipped or failed', error: e);
    }
  }

  /// Synchronously gets the cached YouTube video ID for a track.
  String? getVideoId(String trackId) => _mappings[trackId]?.videoId;

  /// Synchronously gets the full mapping entry for a track.
  YouTubeMappingEntry? getEntry(String trackId) => _mappings[trackId];

  /// Checks if a mapping exists for the given track ID.
  bool contains(String trackId) => _mappings.containsKey(trackId);

  /// Caches or updates a track -> video ID mapping.
  Future<void> setVideoId(
    String trackId,
    String videoId, {
    String? title,
    int? durationSecs,
    bool isManualOverride = false,
  }) async {
    _mappings[trackId] = YouTubeMappingEntry(
      videoId: videoId,
      title: title,
      durationSecs: durationSecs,
      isManualOverride: isManualOverride,
    );
    _scheduleDebouncedFlush();
  }

  /// Removes a cached video ID for a track.
  Future<void> remove(String trackId) async {
    if (_mappings.remove(trackId) != null) {
      _scheduleDebouncedFlush();
    }
  }

  /// Clears the entire mapping cache and empties the persistent file.
  Future<void> clear() async {
    _debounceTimer?.cancel();
    _mappings.clear();
    _isDirty = false;
    try {
      if (_file != null && await _file!.exists()) {
        await _file!.delete();
      }
      logger.i('[YouTubeMappingStore] Cache cleared');
    } catch (e) {
      logger.e('[YouTubeMappingStore] Error deleting mappings file', error: e);
    }
  }

  /// Returns a snapshot of track ID -> video ID map.
  Map<String, String> getSnapshot() {
    return _mappings.map((k, v) => MapEntry(k, v.videoId));
  }

  /// Merges mappings into the cache.
  Future<void> merge(Map<String, String> map) async {
    if (map.isEmpty) return;
    for (final entry in map.entries) {
      _mappings[entry.key] = YouTubeMappingEntry(videoId: entry.value);
    }
    _scheduleDebouncedFlush();
  }

  void _scheduleDebouncedFlush() {
    _isDirty = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      unawaited(flush());
    });
  }

  /// Immediately writes dirty in-memory mappings to disk atomically.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    if (_file == null) return;

    try {
      final jsonString = json.encode(
        _mappings.map((k, v) => MapEntry(k, v.toJson())),
      );

      await _file!.writeAsString(jsonString, flush: true);

      _isDirty = false;
    } catch (e) {
      logger.e('[YouTubeMappingStore] Failed to write mappings to disk', error: e);
    }
  }
}
