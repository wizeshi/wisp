// Copyright © 2026 wizeshi

library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/audio/audio_source.dart';
import 'package:wisp/data/sources/audio/js_audio_source.dart';
import 'package:wisp/data/sources/audio/sources/youtube_audio_source.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/data/sources/providers/provider_dependency_validator.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

/// Central manager that discovers, loads, and coordinates modular audio streaming sources.
class AudioSourceManager extends ChangeNotifier {
  static final AudioSourceManager instance = AudioSourceManager._();
  AudioSourceManager._();

  final Map<String, AudioSource> _sources = {};
  final Set<String> _explicitlyUninstalled = {};
  bool _initialized = false;
  Future<void>? _initFuture;
  bool _disposed = false;

  bool get isInitialized => _initialized;

  Map<String, AudioSource> get sources => Map.unmodifiable(_sources);

  List<AudioSource> get allSources => _sources.values.toList();

  AudioSource? getSource(String id) => _sources[id];

  /// Unregister and dispose a provider in memory and mark it as explicitly uninstalled
  void unregisterSource(String id) {
    _explicitlyUninstalled.add(id);
    final source = _sources.remove(id);
    source?.dispose();
    logger.i('[AudioSourceManager] Unregistered and disposed audio provider: $id');
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
    final dir = Directory(p.join(supportDir.path, 'providers', 'audio'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<void> _doInitialize() async {
    logger.i('[AudioSourceManager] Initializing audio sources...');

    // Ensure AuthSourceManager is initialized first so dependency validation (e.g. auth/spotify) succeeds
    await AuthSourceManager.instance.initialize();

    // 1. Register built-in YouTube source
    if (!_explicitlyUninstalled.contains('youtube') && !_sources.containsKey('youtube')) {
      final ytSource = YouTubeAudioSource();
      await ytSource.initialize();
      _sources['youtube'] = ytSource;
    }

    // 2. Discover disk providers
    try {
      await _loadDiskProviders();
    } catch (e, stack) {
      logger.e('[AudioSourceManager] Error scanning audio providers: $e', error: e, stackTrace: stack);
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadDiskProviders() async {
    final userDir = await getProvidersDirectory();
    final searchDirs = <Directory>[userDir];

    final autoRegisterDev =
        await PreferencesProvider.isAutoRegisterLocalProvidersEnabledStatic();
    if (autoRegisterDev) {
      final devPaths = [
        p.join(Directory.current.path, 'providers', 'audio'),
        p.join(Directory.current.path, '..', '..', 'providers', 'audio'),
        p.join(Directory.current.path, '..', 'providers', 'audio'),
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
          final manifestJson =
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>;
          final id = manifestJson['id'] as String? ?? p.basename(folder.path);
          if (_explicitlyUninstalled.contains(id)) {
            logger.d('[AudioSourceManager] Skipping uninstalled provider: $id');
            continue;
          }

          final entryName = manifestJson['entry'] as String? ?? 'index.js';
          final service = manifestJson['service'] as String? ?? id;
          final name = manifestJson['name'] as String? ?? id;
          final description = manifestJson['description'] as String? ?? '';
          final priority = (manifestJson['priority'] as num?)?.toInt() ?? 0;

          final scriptFile = File(p.join(folder.path, entryName));
          if (!scriptFile.existsSync()) continue;
          final script = await scriptFile.readAsString();

          final deps =
              (manifestJson['dependencies'] as List?)?.cast<String>() ?? [];
          if (deps.isNotEmpty) {
            final unsatisfied =
                await ProviderDependencyValidator.checkDependenciesAsync(deps);
            if (unsatisfied.isNotEmpty) {
              logger.w(
                '[AudioSourceManager] Skipping provider "$id" due to unsatisfied dependencies: '
                '${unsatisfied.map((u) => u.message).join('; ')}',
              );
              continue;
            }
          }

          final rawQualities =
              (manifestJson['supportedQualities'] as List?)?.cast<String>() ??
                  ['standard', 'high'];
          final qualities = rawQualities
              .map((q) => AudioQuality.fromString(q))
              .toSet();

          if (_sources.containsKey(id)) {
            logger.d(
              '[AudioSourceManager] Provider $id already registered, skipping duplicate',
            );
            continue;
          }

          final source = JsAudioSource(
            id: id,
            name: name,
            description: description,
            priority: priority,
            supportedQualities: qualities,
            serviceId: service,
            script: script,
          );
          await source.initialize();
          _sources[id] = source;
          logger.i('[AudioSourceManager] Registered audio provider: $id');
        } catch (e) {
          logger.w(
            '[AudioSourceManager] Failed loading audio provider in ${folder.path}: $e',
          );
        }
      }
    }
  }

  /// Returns enabled audio sources ordered by user priority preferences.
  List<AudioSource> getOrderedSources(PreferencesProvider? prefs) {
    final customOrder = prefs?.getProviderOrder('audio') ?? const <String>[];
    final active = _sources.values.where((source) {
      if (prefs == null) return true;
      return prefs.isProviderEnabled(source.id, type: 'audio');
    }).toList();

    active.sort((a, b) {
      final aIdx = customOrder.indexOf(a.id);
      final bIdx = customOrder.indexOf(b.id);
      if (aIdx >= 0 && bIdx >= 0) return aIdx.compareTo(bIdx);
      if (aIdx >= 0) return -1;
      if (bIdx >= 0) return 1;
      return b.priority.compareTo(a.priority);
    });

    return active;
  }

  Future<void> reload() async {
    for (final source in _sources.values) {
      if (!source.isBuiltIn) {
        source.dispose();
      }
    }
    _sources.removeWhere((id, source) => !source.isBuiltIn);
    _initialized = false;
    _initFuture = null;
    await initialize();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final source in _sources.values) {
      source.dispose();
    }
    _sources.clear();
    super.dispose();
  }
}

