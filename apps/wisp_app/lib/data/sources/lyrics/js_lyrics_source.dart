// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source.dart';
import 'package:wisp/data/sources/providers/js_provider_bridge.dart';

/// A modular lyrics source powered by a sandboxed JavaScript runtime (QuickJS / JSC).
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
  final String script;
  JavascriptRuntime? _runtime;
  bool _isInitialized = false;
  bool _failedInit = false;
  int _reqCounter = 0;
  final Map<int, Completer<Map<String, dynamic>?>> _pendingRequests = {};

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
  });

  @override
  Future<void> initialize() async {
    if (_isInitialized || _failedInit) return;
    try {
      final runtime = getJavascriptRuntime();

      // Setup standard wisp host bridge (fetch, service vault, crypto, storage, auth, logging, tokens)
      JsProviderBridge.setupBridge(
        runtime,
        providerId: id,
        providerName: name,
        serviceId: serviceId,
      );

      // Setup lyrics result callback channel
      runtime.onMessage('wisp_lyrics_result', (dynamic args) {
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args is Map
                  ? args.cast<String, dynamic>()
                  : const <String, dynamic>{});
          final reqId = map['reqId'] as int?;
          if (reqId != null) {
            final completer = _pendingRequests.remove(reqId);
            if (completer != null && !completer.isCompleted) {
              if (map.containsKey('error') && map['error'] != null) {
                logger.w('[JsLyricsSource/$id] Error from getLyrics: ${map['error']}');
                completer.complete(null);
              } else {
                final result = map['result'];
                if (result is Map) {
                  completer.complete(result.cast<String, dynamic>());
                } else {
                  completer.complete(null);
                }
              }
            }
          }
        } catch (e) {
          logger.e('[JsLyricsSource/$id] Error in wisp_lyrics_result: $e');
        }
        return '';
      });

      // Inject lyrics-specific invocation helper
      const lyricsPolyfill = '''
        globalThis.__wisp_invoke_getLyrics = function(reqId, id, queryStr) {
          try {
            var query = typeof queryStr === 'string' ? JSON.parse(queryStr) : queryStr;
            var provider = globalThis['__wisp_provider_' + id];
            if (!provider || typeof provider.getLyrics !== 'function') {
              sendMessage('wisp_lyrics_result', JSON.stringify({
                reqId: reqId,
                error: 'Provider ' + id + '.getLyrics is not a function'
              }));
              return;
            }
            Promise.resolve(provider.getLyrics(query)).then(function(result) {
              sendMessage('wisp_lyrics_result', JSON.stringify({
                reqId: reqId,
                result: result || null
              }));
            }).catch(function(err) {
              sendMessage('wisp_lyrics_result', JSON.stringify({
                reqId: reqId,
                error: String(err)
              }));
            });
          } catch (e) {
            sendMessage('wisp_lyrics_result', JSON.stringify({
              reqId: reqId,
              error: String(e)
            }));
          }
        };
      ''';
      runtime.evaluate(lyricsPolyfill);

      runtime.enableHandlePromises();

      // Wrap and evaluate provider script
      _evaluateProviderScript(runtime);

      _runtime = runtime;
      _isInitialized = true;
    } catch (e) {
      _failedInit = true;
      logger.w(
        '[JsLyricsSource] Could not initialize JS runtime for $name: $e (if running on Windows, re-running flutter run will link flutter_js_plugin.dll)',
      );
    }
  }

  void _drainMicrotasks(JavascriptRuntime runtime) {
    try {
      while (runtime.executePendingJob() > 0) {}
    } catch (e) {
      logger.d('[JsLyricsSource/$id] Microtask drainage exception: $e');
    }
  }

  void _evaluateProviderScript(JavascriptRuntime runtime) {
    final encodedId = jsonEncode(id);
    final wrappedScript = '''
      var exports = {};
      var module = { exports: exports };
      (function(exports, module) {
        $script

        if (typeof getLyrics === 'function') {
          exports.getLyrics = getLyrics;
        }
        if (module.exports && typeof module.exports.getLyrics === 'function') {
          exports.getLyrics = module.exports.getLyrics;
        }
      })(exports, module);

      if (module.exports && typeof module.exports.getLyrics === 'function') {
        exports = module.exports;
      }
      if (!exports.getLyrics && typeof globalThis.getLyrics === 'function') {
        exports.getLyrics = globalThis.getLyrics;
      }
      globalThis['__wisp_provider_' + $encodedId] = exports;
    ''';
    final evalResult = runtime.evaluate(wrappedScript);
    if (evalResult.isError) {
      logger.e('[JsLyricsSource] Error evaluating script for $name ($id): ${evalResult.stringResult}');
    }
    final checkResult = runtime.evaluate("typeof (globalThis['__wisp_provider_' + $encodedId] && globalThis['__wisp_provider_' + $encodedId].getLyrics) === 'function'");
    logger.i('[JsLyricsSource] Provider $name ($id) registered getLyrics: ${checkResult.stringResult}');
  }

  @override
  Future<LyricsResult?> getLyrics(GenericSong song, LyricsSyncMode mode) async {
    if (!_isInitialized && !_failedInit) {
      logger.i('[JsLyricsSource/$id] Initializing provider before getLyrics...');
      await initialize();
    }
    if (_failedInit) {
      logger.e('[JsLyricsSource/$id] Cannot fetch lyrics: JS runtime failed initialization');
      return null;
    }
    final runtime = _runtime;
    if (runtime == null) {
      logger.e('[JsLyricsSource/$id] Cannot fetch lyrics: JS runtime is null');
      return null;
    }

    final encodedId = jsonEncode(id);
    final checkResult = runtime.evaluate("typeof (globalThis['__wisp_provider_' + $encodedId] && globalThis['__wisp_provider_' + $encodedId].getLyrics) === 'function'");
    if (checkResult.stringResult != 'true') {
      logger.w('[JsLyricsSource/$id] Provider getLyrics function not found in runtime. Re-evaluating provider script...');
      _evaluateProviderScript(runtime);
    }

    final reqId = ++_reqCounter;
    final completer = Completer<Map<String, dynamic>?>();
    _pendingRequests[reqId] = completer;

    final query = jsonEncode({
      'id': song.id,
      'source': song.source,
      'title': song.title,
      'artist': song.artists.map((a) => a.name).join(', '),
      'album': song.album?.title ?? '',
      'durationSecs': song.durationSecs,
      'mode': mode.name,
    });

    logger.i('[JsLyricsSource/$id] Executing getLyrics (reqId: $reqId) for "${song.title}" by "${song.artists.map((a) => a.name).join(", ")}" (mode: ${mode.name})');

    try {
      final invokeCode = 'globalThis.__wisp_invoke_getLyrics($reqId, $encodedId, ${jsonEncode(query)});';
      final evalResult = runtime.evaluate(invokeCode);
      if (evalResult.isError) {
        logger.e('[JsLyricsSource/$id] JS invoke error: ${evalResult.stringResult}');
        _pendingRequests.remove(reqId);
        return null;
      }
      _drainMicrotasks(runtime);

      final data = await completer.future.timeout(const Duration(seconds: 15));
      if (data == null) {
        logger.i('[JsLyricsSource/$id] Provider returned null or empty data for "${song.title}"');
        return null;
      }
      return _parseJsResult(data, mode);
    } on TimeoutException {
      _pendingRequests.remove(reqId);
      logger.w('[JsLyricsSource/$id] Timeout fetching lyrics for "${song.title}"');
      return null;
    } catch (e, stack) {
      _pendingRequests.remove(reqId);
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
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _pendingRequests.clear();
    _runtime?.dispose();
    _runtime = null;
    _isInitialized = false;
  }
}
