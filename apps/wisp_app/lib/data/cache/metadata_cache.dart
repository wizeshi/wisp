// Copyright © 2026 wizeshi

/// Generic metadata cache store with in-memory L1 cache and disk-backed JSON entries
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wisp/core/utils/json.dart';
import 'package:wisp/core/utils/logger.dart';

enum MetadataFetchPolicy { cacheFirst, refreshIfExpired, refreshAlways }

class MetadataCacheEntry {
  final String key;
  final String provider;
  final String type;
  final String id;
  final String? pageKey;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  final Map<String, dynamic> payload;

  MetadataCacheEntry({
    required this.key,
    required this.provider,
    required this.type,
    required this.id,
    required this.fetchedAt,
    required this.expiresAt,
    required this.payload,
    this.pageKey,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'key': key,
    'provider': provider,
    'type': type,
    'id': id,
    'pageKey': pageKey,
    'fetchedAt': fetchedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'payload': payload,
  };

  factory MetadataCacheEntry.fromJson(Map<String, dynamic> json) {
    return MetadataCacheEntry(
      key: json['key'] as String,
      provider: json['provider'] as String,
      type: json['type'] as String,
      id: json['id'] as String,
      pageKey: json['pageKey'] as String?,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      payload: (json['payload'] as Map).cast<String, dynamic>(),
    );
  }
}

class MetadataCacheStore {
  MetadataCacheStore._();

  static final MetadataCacheStore instance = MetadataCacheStore._();

  static const Duration _defaultTtl = Duration(days: 7);
  static const int _maxL1Entries = 250;

  final Map<String, MetadataCacheEntry> _l1MemoryCache = {};
  Directory? _baseDir;
  bool _initializing = false;

  Future<void> _ensureInitialized() async {
    if (_baseDir != null || _initializing) return;
    _initializing = true;
    try {
      // Use cache directory so files are not backed up to user cloud storage
      final cacheDir = await getApplicationCacheDirectory();
      final metadataDir = Directory('${cacheDir.path}/metadata_cache');
      if (!await metadataDir.exists()) {
        await metadataDir.create(recursive: true);
      }
      _baseDir = metadataDir;

      // Migrate legacy support directory files if they exist
      await _migrateLegacySupportDirectory(metadataDir);

      logger.d('[Services/MetadataCache] Initialized at ${metadataDir.path}');
    } catch (e) {
      logger.e('[Services/MetadataCache] Initialization error', error: e);
    } finally {
      _initializing = false;
    }
  }

  Future<void> _migrateLegacySupportDirectory(Directory targetDir) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final legacyDir = Directory('${supportDir.path}/metadata_cache');
      if (await legacyDir.exists()) {
        // Clean up legacy files to free up backed-up cloud storage
        await legacyDir.delete(recursive: true);
        logger.d('[Services/MetadataCache] Cleaned up legacy support directory');
      }
    } catch (_) {}
  }

  String buildKey({
    required String provider,
    required String type,
    required String id,
    String? pageKey,
  }) {
    final suffix = pageKey == null ? '' : ':$pageKey';
    return '$provider:$type:$id$suffix';
  }

  Future<File?> _fileForKey({
    required String provider,
    required String type,
    required String key,
  }) async {
    await _ensureInitialized();
    final baseDir = _baseDir;
    if (baseDir == null) return null;

    final dir = Directory('${baseDir.path}/$provider/$type');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final hashed = sha1.convert(utf8.encode(key)).toString();
    return File('${dir.path}/$hashed.json');
  }

  Future<MetadataCacheEntry?> readEntry({
    required String provider,
    required String type,
    required String id,
    String? pageKey,
  }) async {
    final key = buildKey(
      provider: provider,
      type: type,
      id: id,
      pageKey: pageKey,
    );

    // 1. Check in-memory L1 cache first
    final memoryEntry = _l1MemoryCache[key];
    if (memoryEntry != null) {
      return memoryEntry;
    }

    // 2. Fall back to L2 disk cache
    try {
      final file = await _fileForKey(provider: provider, type: type, key: key);
      if (file == null || !await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final jsonData =
          (await JsonUtils.decode(content)) as Map<String, dynamic>;
      final entry = MetadataCacheEntry.fromJson(jsonData);

      // Populate L1 cache
      _putInL1Cache(key, entry);
      return entry;
    } catch (e) {
      logger.w('[Services/MetadataCache] Failed to read entry', error: e);
      return null;
    }
  }

  Future<void> writeEntry({
    required String provider,
    required String type,
    required String id,
    required Map<String, dynamic> payload,
    String? pageKey,
    Duration? ttl,
  }) async {
    try {
      final fetchedAt = DateTime.now();
      final expiresAt = fetchedAt.add(ttl ?? _defaultTtl);
      final key = buildKey(
        provider: provider,
        type: type,
        id: id,
        pageKey: pageKey,
      );
      final entry = MetadataCacheEntry(
        key: key,
        provider: provider,
        type: type,
        id: id,
        pageKey: pageKey,
        fetchedAt: fetchedAt,
        expiresAt: expiresAt,
        payload: payload,
      );

      _putInL1Cache(key, entry);

      final file = await _fileForKey(provider: provider, type: type, key: key);
      if (file == null) return;

      await file.writeAsString(jsonEncode(entry.toJson()));
    } catch (e) {
      logger.w('[Services/MetadataCache] Failed to write entry', error: e);
    }
  }

  void _putInL1Cache(String key, MetadataCacheEntry entry) {
    if (_l1MemoryCache.length >= _maxL1Entries) {
      _l1MemoryCache.remove(_l1MemoryCache.keys.first);
    }
    _l1MemoryCache[key] = entry;
  }

  /// Calculates total size of metadata files on disk in bytes.
  Future<int> getDiskSizeBytes() async {
    await _ensureInitialized();
    final baseDir = _baseDir;
    if (baseDir == null || !await baseDir.exists()) return 0;

    int totalBytes = 0;
    try {
      await for (final entity in baseDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
    } catch (_) {}
    return totalBytes;
  }

  /// Prune expired entries from disk.
  Future<void> pruneExpired() async {
    await _ensureInitialized();
    final baseDir = _baseDir;
    if (baseDir == null || !await baseDir.exists()) return;

    final now = DateTime.now();
    try {
      await for (final entity in baseDir.list(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final expiresAt = DateTime.parse(json['expiresAt'] as String);
            if (now.isAfter(expiresAt)) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @visibleForTesting
  Future<void> clearAll() async {
    _l1MemoryCache.clear();
    await _ensureInitialized();
    final baseDir = _baseDir;
    if (baseDir == null || !await baseDir.exists()) return;
    await baseDir.delete(recursive: true);
    _baseDir = null;
  }

  Future<void> clearProvider(String provider) async {
    _l1MemoryCache.removeWhere((key, _) => key.startsWith('$provider:'));
    await _ensureInitialized();
    final baseDir = _baseDir;
    if (baseDir == null || !await baseDir.exists()) return;
    final providerDir = Directory('${baseDir.path}/$provider');
    if (await providerDir.exists()) {
      await providerDir.delete(recursive: true);
    }
  }
}
