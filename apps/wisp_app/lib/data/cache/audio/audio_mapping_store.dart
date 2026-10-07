// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wisp/core/utils/logger.dart';

/// Single provider resolution entry within a track's audio mapping list.
class AudioMappingItem {
  final String providerID;
  final String mediaID;
  final bool manualOverride;
  final DateTime resolvedAt;

  AudioMappingItem({
    required this.providerID,
    required this.mediaID,
    this.manualOverride = false,
    DateTime? resolvedAt,
  }) : resolvedAt = resolvedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'providerID': providerID,
        'mediaID': mediaID,
        'manualOverride': manualOverride,
        'resolvedAt': resolvedAt.toUtc().toIso8601String(),
      };

  factory AudioMappingItem.fromJson(Map<String, dynamic> json) {
    return AudioMappingItem(
      providerID: json['providerID'] as String? ?? 'youtube',
      mediaID: json['mediaID'] as String? ?? '',
      manualOverride: json['manualOverride'] as bool? ?? false,
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.tryParse(json['resolvedAt'] as String)?.toUtc() ??
              DateTime.now().toUtc()
          : DateTime.now().toUtc(),
    );
  }
}

/// Standalone persistent store for canonical track metadata -> provider audio media IDs.
///
/// Keys are canonical, alphabetically-sorted lowercase word tokens extracted from track
/// title and artist list (e.g. "Let It Happen - Tame Impala" -> "happen_impala_it_let_tame").
/// This ensures that even if two different metadata providers (Spotify, local files, etc.)
/// query the same track, the audio resolution is preserved without re-querying.
class AudioMappingStore {
  static final AudioMappingStore instance = AudioMappingStore._();
  AudioMappingStore._();

  static const Duration _debounceDuration = Duration(milliseconds: 1000);

  final Map<String, List<AudioMappingItem>> _mappings = {};
  File? _file;
  bool _initialized = false;
  bool _isDirty = false;
  Timer? _debounceTimer;

  bool get isInitialized => _initialized;
  bool get isDirty => _isDirty;
  int get count => _mappings.length;

  /// Generates a normalized, canonical track key from title and artist names.
  ///
  /// Extracts alphanumeric words, lowercases them, removes duplicates, sorts them
  /// alphabetically, and joins with an underscore (`_`).
  /// Example: "Let It Happen", ["Tame Impala"] -> "happen_impala_it_let_tame".
  static String canonicalKey({
    required String title,
    required Iterable<String> artists,
  }) {
    final tokens = <String>{};

    void addTokens(String text) {
      final words = text
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((w) => w.isNotEmpty);
      tokens.addAll(words);
    }

    addTokens(title);
    for (final artist in artists) {
      addTokens(artist);
    }

    if (tokens.isEmpty) return 'unknown';

    final sorted = tokens.toList()..sort();
    return sorted.join('_');
  }

  /// Initialize store and perform migration from legacy `youtube_mappings.json`.
  Future<void> initialize({Directory? supportDirectory}) async {
    if (_initialized) return;

    try {
      final dir = supportDirectory ?? await getApplicationSupportDirectory();
      _file = File('${dir.path}/audio_mappings.json');

      if (await _file!.exists()) {
        try {
          final content = await _file!.readAsString();
          if (content.trim().isNotEmpty) {
            final Map<String, dynamic> decoded = json.decode(content);
            for (final entry in decoded.entries) {
              if (entry.value is List) {
                final list = (entry.value as List)
                    .map((item) => AudioMappingItem.fromJson(
                          item as Map<String, dynamic>,
                        ))
                    .where((item) => item.mediaID.isNotEmpty)
                    .toList();
                if (list.isNotEmpty) {
                  _mappings[entry.key] = list;
                }
              }
            }
            logger.i(
              '[AudioMappingStore] Loaded ${_mappings.length} canonical mappings from disk',
            );
          }
        } catch (e) {
          logger.e('[AudioMappingStore] Failed to read audio_mappings.json', error: e);
        }
      }

      // One-time migration from legacy youtube_mappings.json
      await _migrateFromLegacyFile(dir);

      _initialized = true;
    } catch (e) {
      logger.e('[AudioMappingStore] Initialization error', error: e);
      _initialized = true;
    }
  }

  Future<void> _migrateFromLegacyFile(Directory dir) async {
    try {
      final legacyFile = File('${dir.path}/youtube_mappings.json');
      if (!await legacyFile.exists()) return;

      final content = await legacyFile.readAsString();
      if (content.trim().isEmpty) return;

      final Map<String, dynamic> decoded = json.decode(content);
      var migrated = 0;

      for (final entry in decoded.entries) {
        String videoId = '';
        String? title;
        bool isManual = false;
        DateTime? resolvedAt;

        if (entry.value is String) {
          videoId = entry.value as String;
        } else if (entry.value is Map) {
          final map = entry.value as Map<String, dynamic>;
          videoId = map['videoId'] as String? ?? '';
          title = map['title'] as String?;
          isManual = map['isManualOverride'] as bool? ?? false;
          if (map['resolvedAt'] != null) {
            resolvedAt = DateTime.tryParse(map['resolvedAt'] as String);
          }
        }

        if (videoId.isEmpty) continue;

        // Determine key: if title is present, generate canonical key, else fallback to track ID
        final key = (title != null && title.isNotEmpty)
            ? canonicalKey(title: title, artists: const [])
            : entry.key;

        final existing = _mappings[key] ?? [];
        final hasYt = existing.any((item) => item.providerID == 'youtube');
        if (!hasYt) {
          existing.add(
            AudioMappingItem(
              providerID: 'youtube',
              mediaID: videoId,
              manualOverride: isManual,
              resolvedAt: resolvedAt,
            ),
          );
          _mappings[key] = existing;
          migrated++;
        }
      }

      if (migrated > 0) {
        _isDirty = true;
        await flush();
        logger.i(
          '[AudioMappingStore] Migrated $migrated legacy mappings from youtube_mappings.json',
        );
      }
    } catch (e) {
      logger.w('[AudioMappingStore] Legacy migration skipped or failed', error: e);
    }
  }

  /// Gets the resolution entry for a specific provider under [canonicalKey].
  AudioMappingItem? getMapping(String canonicalKey, String providerId) {
    final list = _mappings[canonicalKey];
    if (list == null) return null;
    return list.where((item) => item.providerID == providerId).firstOrNull;
  }

  /// Gets all provider resolution entries for [canonicalKey].
  List<AudioMappingItem> getMappings(String canonicalKey) {
    return List.unmodifiable(_mappings[canonicalKey] ?? const <AudioMappingItem>[]);
  }

  /// Checks if any mappings exist for [canonicalKey].
  bool contains(String canonicalKey) => _mappings.containsKey(canonicalKey);

  /// Caches or updates a provider mapping entry under [canonicalKey].
  Future<void> setMapping(String canonicalKey, AudioMappingItem item) async {
    final list = List<AudioMappingItem>.from(_mappings[canonicalKey] ?? const []);
    final index = list.indexWhere((existing) => existing.providerID == item.providerID);

    if (index >= 0) {
      list[index] = item;
    } else {
      list.add(item);
    }

    _mappings[canonicalKey] = list;
    _scheduleDebouncedFlush();
  }

  /// Removes a mapping for a specific provider, or all mappings under [canonicalKey].
  Future<void> removeMapping(String canonicalKey, {String? providerId}) async {
    if (providerId == null) {
      if (_mappings.remove(canonicalKey) != null) {
        _scheduleDebouncedFlush();
      }
      return;
    }

    final list = _mappings[canonicalKey];
    if (list == null) return;

    final updated = list.where((item) => item.providerID != providerId).toList();
    if (updated.isEmpty) {
      _mappings.remove(canonicalKey);
    } else {
      _mappings[canonicalKey] = updated;
    }
    _scheduleDebouncedFlush();
  }

  /// Clears the entire mapping store and deletes the disk cache.
  Future<void> clear() async {
    _debounceTimer?.cancel();
    _mappings.clear();
    _isDirty = false;
    try {
      if (_file != null && await _file!.exists()) {
        await _file!.delete();
      }
      logger.i('[AudioMappingStore] Cache cleared');
    } catch (e) {
      logger.e('[AudioMappingStore] Error deleting audio_mappings.json', error: e);
    }
  }

  /// Returns a snapshot of `canonicalKey -> List<AudioMappingItem>`.
  Map<String, List<AudioMappingItem>> getSnapshot() {
    return _mappings.map(
      (k, v) => MapEntry(k, List<AudioMappingItem>.unmodifiable(v)),
    );
  }

  /// Merges mappings into the cache.
  Future<void> merge(Map<String, List<AudioMappingItem>> map) async {
    if (map.isEmpty) return;
    for (final entry in map.entries) {
      final existing = List<AudioMappingItem>.from(_mappings[entry.key] ?? const []);
      for (final newItem in entry.value) {
        final idx = existing.indexWhere((e) => e.providerID == newItem.providerID);
        if (idx >= 0) {
          existing[idx] = newItem;
        } else {
          existing.add(newItem);
        }
      }
      _mappings[entry.key] = existing;
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

  /// Flushes dirty in-memory mappings to disk atomically.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    if (_file == null) return;

    try {
      final jsonMap = _mappings.map(
        (key, list) => MapEntry(key, list.map((item) => item.toJson()).toList()),
      );
      final jsonString = json.encode(jsonMap);
      await _file!.writeAsString(jsonString, flush: true);
      _isDirty = false;
    } catch (e) {
      logger.e('[AudioMappingStore] Failed to write mappings to disk', error: e);
    }
  }
}
