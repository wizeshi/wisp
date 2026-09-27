// Copyright © 2026 wizeshi

library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/js_lyrics_source.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

/// Central manager that discovers, loads, and coordinates modular lyrics sources.
class LyricsSourceManager {
  static final LyricsSourceManager instance = LyricsSourceManager._();

  LyricsSourceManager._();

  final Map<String, LyricsSource> _sources = {};
  final Set<String> _explicitlyUninstalled = {};
  final List<VoidCallback> _listeners = [];

  bool _initialized = false;
  Future<void>? _initFuture;

  bool get isInitialized => _initialized;

  /// All registered lyrics sources.
  List<LyricsSource> get allSources => _sources.values.toList();

  /// Unregister a provider in memory and mark it as explicitly uninstalled
  void unregisterSource(String id) {
    _explicitlyUninstalled.add(id);
    _sources.remove(id);
    logger.i('[LyricsSourceManager] Unregistered lyrics provider: $id');
    _notifyListeners();
  }

  /// Clear the uninstalled flag (e.g. when reinstalling)
  void clearUninstalled(String id) {
    _explicitlyUninstalled.remove(id);
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (e) {
        logger.e('[LyricsSourceManager] Listener error: $e');
      }
    }
  }

  /// Initialize sources and scan local provider directory.
  Future<void> initialize() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    logger.i('[LyricsSourceManager] Initializing lyrics sources...');
    // Discover user drop-in / downloaded providers from disk
    try {
      await _loadDiskProviders();
    } catch (e, stack) {
      logger.e('[LyricsSourceManager] Error loading external providers: $e', error: e, stackTrace: stack);
    }
    _initialized = true;
    logger.i(
      '[LyricsSourceManager] Initialized with ${_sources.length} sources: ${_sources.keys.isEmpty ? "(none)" : _sources.keys.join(", ")}',
    );
  }

  /// Returns all registered sources that support [mode], sorted strictly by priority descending.
  List<LyricsSource> getSourcesForMode(LyricsSyncMode mode) {
    final matching = _sources.values
        .where((s) => s.supportedSyncModes.contains(mode))
        .toList();
    matching.sort((a, b) => b.priority.compareTo(a.priority));
    return matching;
  }

  /// Get all available sources ordered by user priority override (if set),
  /// otherwise by capability rank (word > line > unsynced), tie-broken by manifest priority.
  List<LyricsSource> getOrderedSourcesForMode(LyricsSyncMode requestedMode, [PreferencesProvider? prefs]) {
    final list = _sources.values.toList();
    final customOrder = prefs?.getProviderOrder('lyrics') ?? const [];
    list.sort((a, b) {
      if (customOrder.isNotEmpty) {
        final aIdx = customOrder.indexOf(a.id.toLowerCase());
        final bIdx = customOrder.indexOf(b.id.toLowerCase());
        if (aIdx != -1 && bIdx != -1) return aIdx.compareTo(bIdx);
        if (aIdx != -1) return -1;
        if (bIdx != -1) return 1;
      }

      // 1. Prioritize capability (word = 3 > line = 2 > unsynced = 1)
      final rankDiff = b.capabilityRank.compareTo(a.capabilityRank);
      if (rankDiff != 0) return rankDiff;

      // 2. Tie-break using manifest priority
      return b.priority.compareTo(a.priority);
    });
    return list;
  }

  /// Get the directory where custom lyrics providers are stored.
  Future<Directory> getProvidersDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'providers', 'lyrics'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Scan the providers directories and load custom JS extensions.
  Future<void> _loadDiskProviders() async {
    final userDir = await getProvidersDirectory();

    final searchDirs = <Directory>[userDir];

    // Only scan local repo/workspace providers if automatic registration is enabled in debug preferences
    final autoRegisterDev =
        await PreferencesProvider.isAutoRegisterLocalProvidersEnabledStatic();
    logger.i(
      '[LyricsSourceManager] Scanning for providers. userDir: ${userDir.path}, autoRegisterDev: $autoRegisterDev',
    );
    if (autoRegisterDev) {
      final potentialDevPaths = [
        p.join(Directory.current.path, 'providers', 'lyrics'),
        p.join(Directory.current.path, '..', '..', 'providers', 'lyrics'),
        p.join(Directory.current.path, '..', 'providers', 'lyrics'),
      ];

      for (final devPath in potentialDevPaths) {
        final devDir = Directory(devPath);
        if (devDir.existsSync() &&
            !searchDirs.any((d) => p.equals(d.path, devDir.path))) {
          searchDirs.add(devDir);
        }
      }
    }

    logger.i(
      '[LyricsSourceManager] Provider search directories (${searchDirs.length}): ${searchDirs.map((d) => d.path).join(", ")}',
    );

    for (final baseDir in searchDirs) {
      if (!baseDir.existsSync()) {
        logger.d('[LyricsSourceManager] Directory does not exist: ${baseDir.path}');
        continue;
      }
      final subdirs = baseDir.listSync().whereType<Directory>();
      for (final folder in subdirs) {
        final manifestFile = File(p.join(folder.path, 'manifest.json'));
        if (!manifestFile.existsSync()) {
          logger.d('[LyricsSourceManager] Skipping directory (no manifest.json): ${folder.path}');
          continue;
        }

        try {
          final manifestJson =
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>;
          final id = manifestJson['id'] as String? ?? p.basename(folder.path);
          if (_explicitlyUninstalled.contains(id)) {
            logger.d('[LyricsSourceManager] Skipping uninstalled provider: $id');
            continue;
          }
          final name = manifestJson['name'] as String? ?? id;
          final description = manifestJson['description'] as String?;
          final entryName = manifestJson['entry'] as String? ?? 'index.js';

          // Parse supportedSyncModes (e.g. ["word", "line", "unsynced"])
          final modesList = (manifestJson['supportedSyncModes'] as List?)
              ?.cast<String>();
          final supportedModes = modesList != null
              ? modesList
                  .map((m) => LyricsSyncMode.values.firstWhere(
                        (v) => v.name.toLowerCase() == m.toLowerCase(),
                        orElse: () => LyricsSyncMode.line,
                      ))
                  .toSet()
              : const {LyricsSyncMode.line, LyricsSyncMode.unsynced};

          final priority = manifestJson['priority'] as int? ?? 0;
          final service = manifestJson['service'] as String?;

          final scriptFile = File(p.join(folder.path, entryName));
          if (!scriptFile.existsSync()) {
            logger.w(
              '[LyricsSourceManager] Entry script $entryName not found in ${folder.path}',
            );
            continue;
          }

          final script = await scriptFile.readAsString();
          final source = JsLyricsSource(
            id: id,
            name: name,
            description: description,
            isBuiltIn: false,
            supportedSyncModes: supportedModes,
            priority: priority,
            serviceId: service,
            script: script,
          );

          _sources[id] = source;
          logger.i(
            '[LyricsSourceManager] Registered provider: $name ($id) [priority: $priority, modes: ${supportedModes.map((m) => m.name).join(",")}]',
          );
        } catch (e, stack) {
          logger.e(
            '[LyricsSourceManager] Failed to load provider in ${folder.path}: $e',
            error: e,
            stackTrace: stack,
          );
        }
      }
    }

    logger.i(
      '[LyricsSourceManager] Provider loading complete. Total registered sources: ${_sources.length} (${_sources.keys.join(", ")})',
    );
  }

  /// Fetch lyrics using a specific source id.
  Future<LyricsResult?> fetchWithSource({
    required String sourceId,
    required GenericSong song,
    required LyricsSyncMode mode,
  }) async {
    final source = _sources[sourceId];
    if (source == null) {
      logger.w(
        '[LyricsSourceManager] Provider "$sourceId" not found in registered sources (${_sources.keys.join(", ")})',
      );
      return null;
    }

    try {
      final result = await source.getLyrics(song, mode);
      if (result != null) return result;
    } catch (e, stack) {
      logger.e(
        '[LyricsSourceManager] Source $sourceId threw exception: $e',
        error: e,
        stackTrace: stack,
      );
    }

    return null;
  }

  /// Reload all sources and re-scan the providers directories.
  Future<void> reload() async {
    _sources.clear();
    _initialized = false;
    _initFuture = null;
    await initialize();
    _notifyListeners();
  }
}
