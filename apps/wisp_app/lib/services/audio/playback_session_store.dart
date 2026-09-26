// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';

/// Snapshot of the player session state persisted across app restarts.
class PlaybackSession {
  final List<GenericSong> queue;
  final List<GenericSong> originalQueue;
  final int currentIndex;
  final int positionMs;
  final bool shuffleEnabled;
  final RepeatMode repeatMode;
  final PlaybackContext? playbackContext;
  final DateTime savedAt;

  PlaybackSession({
    this.queue = const [],
    this.originalQueue = const [],
    this.currentIndex = -1,
    this.positionMs = 0,
    this.shuffleEnabled = false,
    this.repeatMode = RepeatMode.off,
    this.playbackContext,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'queue': queue.map((s) => s.toJson()).toList(),
    'originalQueue': originalQueue.map((s) => s.toJson()).toList(),
    'currentIndex': currentIndex,
    'positionMs': positionMs,
    'shuffleEnabled': shuffleEnabled,
    'repeatMode': repeatMode.toString(),
    'playbackContext': playbackContext?.toJson(),
    'savedAt': savedAt.toIso8601String(),
  };

  factory PlaybackSession.fromJson(Map<String, dynamic> json) {
    List<GenericSong> q = [];
    if (json['queue'] is List) {
      q = (json['queue'] as List)
          .whereType<Map<String, dynamic>>()
          .map((item) => GenericSong.fromJson(item))
          .toList();
    }

    List<GenericSong> origQ = [];
    if (json['originalQueue'] is List) {
      origQ = (json['originalQueue'] as List)
          .whereType<Map<String, dynamic>>()
          .map((item) => GenericSong.fromJson(item))
          .toList();
    }

    final repStr = json['repeatMode'] as String?;
    final repMode = RepeatMode.values.firstWhere(
      (e) => e.toString() == repStr || e.name == repStr,
      orElse: () => RepeatMode.off,
    );

    PlaybackContext? ctx;
    if (json['playbackContext'] is Map<String, dynamic>) {
      ctx = PlaybackContext.fromJson(
        json['playbackContext'] as Map<String, dynamic>,
      );
    }

    return PlaybackSession(
      queue: q,
      originalQueue: origQ,
      currentIndex: json['currentIndex'] as int? ?? -1,
      positionMs: json['positionMs'] as int? ?? 0,
      shuffleEnabled: json['shuffleEnabled'] as bool? ?? false,
      repeatMode: repMode,
      playbackContext: ctx,
      savedAt: json['savedAt'] != null
          ? DateTime.tryParse(json['savedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Standalone persistent store for player queue and session state.
///
/// Replaces the legacy 9-key SharedPreferences storage with a single
/// atomic file (`playback_session.json`) in [getApplicationSupportDirectory],
/// equipped with write debouncing to eliminate IO stutters during queue changes.
class PlaybackSessionStore {
  static final PlaybackSessionStore instance = PlaybackSessionStore._();
  PlaybackSessionStore._();

  static const Duration _debounceDuration = Duration(milliseconds: 500);

  File? _file;
  bool _initialized = false;
  PlaybackSession? _currentSession;
  Timer? _debounceTimer;

  bool get isInitialized => _initialized;
  PlaybackSession? get currentSession => _currentSession;

  /// Loads the persisted playback session, migrating legacy SharedPreferences if needed.
  Future<PlaybackSession?> loadSession({Directory? supportDirectory}) async {
    try {
      final dir = supportDirectory ?? await getApplicationSupportDirectory();
      _file = File('${dir.path}/playback_session.json');

      if (await _file!.exists()) {
        try {
          final content = await _file!.readAsString();
          if (content.trim().isNotEmpty) {
            final jsonMap = json.decode(content) as Map<String, dynamic>;
            _currentSession = PlaybackSession.fromJson(jsonMap);
            _initialized = true;
            logger.i(
              '[PlaybackSessionStore] Loaded session with ${_currentSession!.queue.length} tracks (index ${_currentSession!.currentIndex})',
            );
            return _currentSession;
          }
        } catch (e) {
          logger.e('[PlaybackSessionStore] Failed parsing session file', error: e);
        }
      }

      // Check legacy SharedPreferences migration
      final migrated = await _migrateFromLegacyPrefs();
      if (migrated != null) {
        _currentSession = migrated;
        _initialized = true;
        return _currentSession;
      }

      _initialized = true;
      return null;
    } catch (e) {
      logger.e('[PlaybackSessionStore] Error initializing session store', error: e);
      _initialized = true;
      return null;
    }
  }

  Future<PlaybackSession?> _migrateFromLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('audio_queue');
      if (queueJson == null) return null;

      final list = json.decode(queueJson) as List;
      final queue = list
          .whereType<Map<String, dynamic>>()
          .map((item) => GenericSong.fromJson(item))
          .toList();

      List<GenericSong> originalQueue = [];
      final originalQueueJson = prefs.getString('audio_original_queue');
      if (originalQueueJson != null) {
        final origList = json.decode(originalQueueJson) as List;
        originalQueue = origList
            .whereType<Map<String, dynamic>>()
            .map((item) => GenericSong.fromJson(item))
            .toList();
      }

      final currentIndex = prefs.getInt('current_index') ?? -1;
      final shuffleEnabled = prefs.getBool('shuffle_enabled') ?? false;

      final repeatStr = prefs.getString('repeat_mode');
      final repeatMode = RepeatMode.values.firstWhere(
        (e) => e.toString() == repeatStr,
        orElse: () => RepeatMode.off,
      );

      final contextType = PlaybackContextType.values.firstWhere(
        (e) => e.toString() == prefs.getString('playback_context_type'),
        orElse: () => PlaybackContextType.unknown,
      );
      final contextName = prefs.getString('playback_context_name');
      final contextId = prefs.getString('playback_context_id');
      final contextSource = SongSource.values.firstWhere(
        (e) => e.toString() == prefs.getString('playback_context_source'),
        orElse: () => SongSource.spotify,
      );

      PlaybackContext? context;
      if (contextId != null &&
          contextId.isNotEmpty &&
          contextName != null &&
          contextName.isNotEmpty) {
        context = PlaybackContext(
          id: contextId,
          name: contextName,
          type: contextType,
          source: contextSource,
        );
      }

      final session = PlaybackSession(
        queue: queue,
        originalQueue: originalQueue,
        currentIndex: currentIndex,
        positionMs: 0,
        shuffleEnabled: shuffleEnabled,
        repeatMode: repeatMode,
        playbackContext: context,
      );

      // Clean up legacy keys
      await prefs.remove('audio_queue');
      await prefs.remove('audio_original_queue');
      await prefs.remove('current_index');
      await prefs.remove('shuffle_enabled');
      await prefs.remove('repeat_mode');
      await prefs.remove('playback_context_type');
      await prefs.remove('playback_context_name');
      await prefs.remove('playback_context_id');
      await prefs.remove('playback_context_source');

      saveSession(session, immediate: true);
      logger.i(
        '[PlaybackSessionStore] Migrated legacy player state (${queue.length} tracks) to playback_session.json and cleaned SharedPreferences',
      );
      return session;
    } catch (e) {
      logger.w('[PlaybackSessionStore] Legacy player migration failed', error: e);
      return null;
    }
  }

  /// Saves the playback session.
  ///
  /// If [immediate] is false, writes are debounced by 500ms to avoid disk thrashing
  /// during rapid skipping or reordering.
  void saveSession(PlaybackSession session, {bool immediate = false}) {
    _currentSession = session;
    if (immediate) {
      _debounceTimer?.cancel();
      unawaited(_flushToDisk());
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(_debounceDuration, () {
        unawaited(_flushToDisk());
      });
    }
  }

  /// Flushes current session to disk atomically.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    await _flushToDisk();
  }

  Future<void> _flushToDisk() async {
    if (_file == null || _currentSession == null) return;

    try {
      final jsonString = json.encode(_currentSession!.toJson());
      await _file!.writeAsString(jsonString, flush: true);
    } catch (e) {
      logger.e('[PlaybackSessionStore] Error writing session to disk', error: e);
    }
  }

  /// Clears the session file.
  Future<void> clearSession() async {
    _debounceTimer?.cancel();
    _currentSession = null;
    try {
      if (_file != null && await _file!.exists()) {
        await _file!.delete();
      }
    } catch (e) {
      logger.e('[PlaybackSessionStore] Error deleting session file', error: e);
    }
  }
}
