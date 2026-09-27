// Copyright © 2026 wizeshi

library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'js_metadata_source.dart';

/// Manages modular metadata sources discovered from user storage and repo packages.
class MetadataSourceManager extends ChangeNotifier {
  static final MetadataSourceManager instance = MetadataSourceManager._();
  MetadataSourceManager._();

  final Map<String, JsMetadataSource> _sources = {};
  final Set<String> _explicitlyUninstalled = {};
  bool _initialized = false;
  Future<void>? _initFuture;

  bool get isInitialized => _initialized;

  Map<String, JsMetadataSource> get sources => Map.unmodifiable(_sources);

  JsMetadataSource? get defaultSource => _sources['spotify'] ?? (_sources.isNotEmpty ? _sources.values.first : null);

  /// Unregister and dispose a provider in memory and mark it as explicitly uninstalled
  void unregisterSource(String id) {
    _explicitlyUninstalled.add(id);
    final source = _sources.remove(id);
    source?.dispose();
    logger.i('[MetadataSourceManager] Unregistered and disposed metadata provider: $id');
    notifyListeners();
  }

  /// Clear the uninstalled flag (e.g. when reinstalling)
  void clearUninstalled(String id) {
    _explicitlyUninstalled.remove(id);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initFuture ??= _doInitialize();
    await _initFuture;
  }

  Future<Directory> getProvidersDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'providers', 'metadata'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<void> _doInitialize() async {
    try {
      final userDir = await getProvidersDirectory();
      final searchDirs = <Directory>[userDir];

      final autoRegisterDev =
          await PreferencesProvider.isAutoRegisterLocalProvidersEnabledStatic();
      if (autoRegisterDev) {
        final devPaths = [
          p.join(Directory.current.path, 'providers', 'metadata'),
          p.join(Directory.current.path, '..', '..', 'providers', 'metadata'),
          p.join(Directory.current.path, '..', 'providers', 'metadata'),
        ];
        for (final devPath in devPaths) {
          final devDir = Directory(devPath);
          if (devDir.existsSync() &&
              !searchDirs.any((d) => p.equals(d.path, devDir.path))) {
            searchDirs.add(devDir);
          }
        }
      }

      for (final baseDir in searchDirs) {
        if (!baseDir.existsSync()) continue;
        final subdirs = baseDir.listSync().whereType<Directory>();
        for (final folder in subdirs) {
          final manifestFile = File(p.join(folder.path, 'manifest.json'));
          if (!manifestFile.existsSync()) continue;

          try {
            final manifestJson = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
            final id = manifestJson['id'] as String? ?? p.basename(folder.path);
            if (_explicitlyUninstalled.contains(id)) {
              logger.d('[MetadataSourceManager] Skipping uninstalled provider: $id');
              continue;
            }
            final entryName = manifestJson['entry'] as String? ?? 'index.js';
            final service = manifestJson['service'] as String? ?? id;
            final name = manifestJson['name'] as String? ?? id;
            final displayName = manifestJson['displayName'] as String? ?? name;
            final description = manifestJson['description'] as String? ?? '';
            final iconURL = manifestJson['iconURL'] as String? ?? '';
            final logoURL = manifestJson['logoURL'] as String? ?? '';

            final scriptFile = File(p.join(folder.path, entryName));
            if (!scriptFile.existsSync()) continue;
            final script = await scriptFile.readAsString();
            final deps = (manifestJson['dependencies'] as List?)?.cast<String>() ?? [];
            final hasAuthDep = deps.any((d) => d.startsWith('auth/') || d == 'auth');
            final supportsAuth = manifestJson['auth'] as bool? ?? hasAuthDep || (manifestJson['service'] != null);

            final source = JsMetadataSource(
              providerId: id,
              serviceId: service,
              name: name,
              displayName: displayName,
              description: description,
              iconURL: iconURL,
              logoURL: logoURL,
              supportsAuth: supportsAuth,
              customScript: script,
              scriptPath: scriptFile.path,
            );
            await source.initialize();
            _sources[id] = source;
            logger.i('[MetadataSourceManager] Registered metadata provider: $id');
          } catch (e) {
            logger.w('[MetadataSourceManager] Failed loading provider in ${folder.path}: $e');
          }
        }
      }
    } catch (e, stack) {
      logger.e('[MetadataSourceManager] Error scanning metadata providers: $e', error: e, stackTrace: stack);
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> reload() async {
    for (final source in _sources.values) {
      source.dispose();
    }
    _sources.clear();
    _initialized = false;
    _initFuture = null;
    await initialize();
  }
}
