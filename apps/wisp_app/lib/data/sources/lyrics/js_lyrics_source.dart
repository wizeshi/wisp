// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source.dart';
import 'package:wisp/data/sources/providers/shared_js_runtime.dart';

/// A modular lyrics source powered by the shared sandboxed JavaScript runtime.
class JsLyricsSource extends LyricsSource {
  @override
  final String id;

  @override
  final String name;

  @override
  final String? description;

  @override
  final bool isBuiltIn;

  @override
  final Set<LyricsSyncMode> supportedSyncModes;

  @override
  final int priority;

  final String? serviceId;
  String? script;
  final String? scriptPath;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  JsLyricsSource({
    required this.id,
    required this.name,
    this.description,
    this.isBuiltIn = false,
    this.supportedSyncModes = const {
      LyricsSyncMode.line,
      LyricsSyncMode.unsynced,
    },
    this.priority = 0,
    this.serviceId,
    required this.script,
    this.scriptPath,
  });

  @override
  Future<void> initialize() async {
    // Eager runtime creation is replaced with lazy evaluation in SharedJsRuntime.
    _isInitialized = true;
  }

  Future<void> _ensureLoaded() async {
    final code = script;
    if (code == null) return;
    await SharedJsRuntime.instance.loadProvider(
      id: id,
      name: name,
      script: code,
      serviceId: serviceId,
      type: 'lyrics',
    );
    script = null;
  }


  @override
  Future<LyricsResult?> getLyrics(GenericSong song, LyricsSyncMode mode) async {
    try {
      await _ensureLoaded();

      final query = {
        'id': song.id,
        'source': song.source,
        'title': song.title,
        'artist': song.artists.map((a) => a.name).join(', '),
        'album': song.album?.title ?? '',
        'durationSecs': song.durationSecs,
        'mode': mode.name,
      };

      logger.i('[JsLyricsSource/$id] Fetching lyrics for "${song.title}" by "${song.artists.map((a) => a.name).join(", ")}" (mode: ${mode.name})');

      final raw = await SharedJsRuntime.instance.getLyrics(id, query);
      if (raw == null) {
        logger.i('[JsLyricsSource/$id] Provider returned null or empty data for "${song.title}"');
        return null;
      }
      return _parseJsResult(raw, mode);
    } catch (e, stack) {
      logger.e('[JsLyricsSource/$id] Failed to get lyrics: $e', error: e, stackTrace: stack);
      return null;
    }
  }

  LyricsResult? _parseJsResult(
    Map<String, dynamic> data,
    LyricsSyncMode requestedMode,
  ) {
    try {
      final result = LyricsResult.fromWlfJson(
        data,
        fallbackProvider: id,
        fallbackName: name,
      );

      if (result.lines.isEmpty) {
        logger.w('[JsLyricsSource/$id] WLF result contained 0 valid lyric lines');
        return null;
      }

      logger.i(
        '[JsLyricsSource/$id] Parsed ${result.lines.length} lines from ${result.providerLabel} (mode: ${result.syncMode.name})',
      );

      return result;
    } catch (e, stack) {
      logger.e('[JsLyricsSource/$id] Error parsing WLF result: $e', error: e, stackTrace: stack);
      return null;
    }
  }

  @override
  void dispose() {
    SharedJsRuntime.instance.unloadProvider(id, type: 'lyrics');
    _isInitialized = false;
  }
}

