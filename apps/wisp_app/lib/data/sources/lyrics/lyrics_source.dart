// Copyright © 2026 wizeshi

library;

import 'package:wisp/data/models/metadata_models.dart';

/// Base interface for modular lyrics sources.
abstract class LyricsSource {
  /// Unique identifier (e.g. 'betterlyrics', 'lrclib', 'spotify').
  String get id;

  /// User-facing display name.
  String get name;

  /// Optional description.
  String? get description => null;

  /// Whether this source is built into the app binary or loaded dynamically.
  bool get isBuiltIn => false;

  /// Sync modes supported by this provider (e.g. word, line, unsynced).
  Set<LyricsSyncMode> get supportedSyncModes => {
        LyricsSyncMode.line,
        LyricsSyncMode.unsynced,
      };

  /// Base priority weight (higher number = tried first).
  int get priority => 0;

  /// Capability rank: word (3) > line (2) > unsynced (1).
  int get capabilityRank {
    if (supportedSyncModes.contains(LyricsSyncMode.word)) return 3;
    if (supportedSyncModes.contains(LyricsSyncMode.line)) return 2;
    return 1;
  }

  /// Initialize any required background runtimes or resources.
  Future<void> initialize() async {}

  /// Fetch lyrics for the given song.
  Future<LyricsResult?> getLyrics(GenericSong song, LyricsSyncMode mode);

  /// Cleanup resources.
  void dispose() {}
}
