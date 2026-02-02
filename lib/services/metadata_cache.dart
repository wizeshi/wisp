/// Generic metadata cache store with disk-backed JSON entries
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

enum MetadataFetchPolicy {
  cacheFirst,
  refreshIfExpired,
  refreshAlways,
}

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

  static const Duration _ttl = Duration(days: 7);
  Directory? _baseDir;
  bool _initializing = false;

  Future<void> _ensureInitialized() async {
    if (_baseDir != null || _initializing) return;
    _initializing = true;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${supportDir.path}/metadata_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      _baseDir = cacheDir;
      logger.d('[MetadataCache] Initialized at ${cacheDir.path}');
    } catch (e) {
      logger.e('[MetadataCache] Initialization error', error: e);
    } finally {
      _initializing = false;
    }
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
    try {
      final key = buildKey(
        provider: provider,
        type: type,
        id: id,
        pageKey: pageKey,
      );
      final file = await _fileForKey(
        provider: provider,
        type: type,
        key: key,
      );
      if (file == null || !await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final jsonData = jsonDecode(content) as Map<String, dynamic>;
      return MetadataCacheEntry.fromJson(jsonData);
    } catch (e) {
      logger.w('[MetadataCache] Failed to read entry', error: e);
      return null;
    }
  }

  Future<void> writeEntry({
    required String provider,
    required String type,
    required String id,
    required Map<String, dynamic> payload,
    String? pageKey,
  }) async {
    try {
      final fetchedAt = DateTime.now();
      final expiresAt = fetchedAt.add(_ttl);
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

      final file = await _fileForKey(
        provider: provider,
        type: type,
        key: key,
      );
      if (file == null) return;

      await file.writeAsString(jsonEncode(entry.toJson()));
    } catch (e) {
      logger.w('[MetadataCache] Failed to write entry', error: e);
    }
  }

  @visibleForTesting
  Future<void> clearAll() async {
    await _ensureInitialized();
    final baseDir = _baseDir;
    if (baseDir == null || !await baseDir.exists()) return;
    await baseDir.delete(recursive: true);
    _baseDir = null;
  }
}
