// Copyright © 2026 wizeshi

library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/auth/js_auth_source.dart';

/// Central manager that discovers, loads, and coordinates modular authentication sources.
class AuthSourceManager extends ChangeNotifier {
  static final AuthSourceManager instance = AuthSourceManager._();
  AuthSourceManager._();

  final Map<String, JsAuthSource> _sources = {};
  final Set<String> _explicitlyUninstalled = {};
  bool _initialized = false;
  Future<void>? _initFuture;

  bool get isInitialized => _initialized;
  Map<String, JsAuthSource> get sources => Map.unmodifiable(_sources);

  void unregisterSource(String id) {
    _explicitlyUninstalled.add(id);
    final source = _sources.remove(id);
    source?.dispose();
    logger.i('[AuthSourceManager] Unregistered auth provider: $id');
    notifyListeners();
  }

  void clearUninstalled(String id) {
    _explicitlyUninstalled.remove(id);
  }

  JsAuthSource? getAuthSource(String serviceOrId) {
    final key = serviceOrId.toLowerCase();
    if (_sources.containsKey(key)) return _sources[key];
    for (final s in _sources.values) {
      if (s.serviceId.toLowerCase() == key || s.id.toLowerCase() == key) {
        return s;
      }
    }
    return null;
  }

  Future<void> login(String serviceOrId) async {
    final auth = getAuthSource(serviceOrId);
    if (auth != null) {
      await auth.login();
    } else {
      logger.w('[AuthSourceManager] No auth provider found for $serviceOrId');
    }
  }

  Future<void> logout(String serviceOrId) async {
    final auth = getAuthSource(serviceOrId);
    if (auth != null) {
      await auth.logout();
    }
  }

  Future<Map<String, dynamic>?> getTokens(
    String serviceOrId, {
    bool forceRefresh = false,
  }) async {
    final auth = getAuthSource(serviceOrId);
    if (auth != null) {
      return await auth.getTokens(forceRefresh: forceRefresh);
    }
    return null;
  }

  Future<void> initialize() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> reload() async {
    for (final s in _sources.values) {
      s.dispose();
    }
    _sources.clear();
    _initialized = false;
    _initFuture = null;
    await initialize();
    notifyListeners();
  }

  Future<Directory> getProvidersDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'providers', 'auth'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<void> _doInitialize() async {
    logger.i('[AuthSourceManager] Initializing auth sources...');
    try {
      final userDir = await getProvidersDirectory();
      await _loadDirectory(userDir);

      final devPaths = [
        p.join(Directory.current.path, 'providers', 'auth'),
        p.join(Directory.current.path, '..', '..', 'providers', 'auth'),
        p.join(Directory.current.path, '..', 'providers', 'auth'),
      ];
      for (final dp in devPaths) {
        final d = Directory(dp);
        if (d.existsSync()) {
          await _loadDirectory(d);
          break;
        }
      }
    } catch (e, stack) {
      logger.e('[AuthSourceManager] Error initializing: $e', error: e, stackTrace: stack);
    }
    _initialized = true;
    logger.i('[AuthSourceManager] Initialized with ${_sources.length} sources');
    notifyListeners();
  }

  Future<void> _loadDirectory(Directory dir) async {
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is Directory) {
        final manifestFile = File(p.join(entity.path, 'manifest.json'));
        final scriptFile = File(p.join(entity.path, 'index.js'));
        if (manifestFile.existsSync() && scriptFile.existsSync()) {
          try {
            final manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
            final id = manifest['id'] as String? ?? p.basename(entity.path);
            if (_explicitlyUninstalled.contains(id)) continue;

            final name = manifest['name'] as String? ?? id;
            final serviceId = manifest['service'] as String? ?? id;
            final script = await scriptFile.readAsString();

            final source = JsAuthSource(
              id: id,
              name: name,
              serviceId: serviceId,
              script: script,
            );
            await source.initialize();
            _sources[id.toLowerCase()] = source;
          } catch (e) {
            logger.e('[AuthSourceManager] Failed loading auth provider at ${entity.path}: $e');
          }
        }
      }
    }
  }
}
