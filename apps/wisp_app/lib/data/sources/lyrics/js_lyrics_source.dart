// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source.dart';
import 'package:wisp/data/sources/spotify/spotify_tokens.dart';

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
    required this.script,
  });

  @override
  Future<void> initialize() async {
    if (_isInitialized || _failedInit) return;
    try {
      final runtime = getJavascriptRuntime();

      // Setup custom logging channel
      runtime.onMessage('wisp_log', (dynamic args) {
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          final level = map['level'] as String? ?? 'info';
          final msg = map['msg'] as String? ?? '';
          if (level == 'error') {
            logger.e('[JS/$name] $msg');
          } else if (level == 'warn') {
            logger.w('[JS/$name] $msg');
          } else {
            logger.i('[JS/$name] $msg');
          }
        } catch (_) {}
        return '';
      });

      // Setup sandboxed network channel routed through Dart http client
      runtime.onMessage('wisp_fetch', (dynamic args) {
        unawaited(() async {
          int? cbId;
          try {
            final map = args is String
                ? jsonDecode(args) as Map<String, dynamic>
                : (args is Map
                    ? args.cast<String, dynamic>()
                    : const <String, dynamic>{});
            cbId = map['cbId'] as int?;
            final url = map['url'] as String?;
            final method = (map['method'] as String?)?.toUpperCase() ?? 'GET';
            final headers =
                (map['headers'] as Map?)?.cast<String, String>() ?? {};
            final body = map['body'] as String?;

            if (url == null || cbId == null) {
              throw ArgumentError('url and cbId are required for wisp_fetch');
            }

            logger.i('[JS/$name HTTP] -> $method $url');
            final uri = Uri.parse(url);
            final client = createSpotifyHttpClient();
            http.Response response;
            try {
              final request = http.Request(method, uri);
              request.headers.addAll(headers);
              if (body != null) {
                request.body = body;
              }
              final streamedResponse = await client.send(request);
              response = await http.Response.fromStream(streamedResponse);
              logger.i(
                '[JS/$name HTTP] <- $method $url: status=${response.statusCode} (body length=${response.body.length})',
              );
            } finally {
              client.close();
            }

            _resolveJsCallback(runtime, cbId, {
              'status': response.statusCode,
              'body': response.body,
              'headers': response.headers,
            });
          } catch (e) {
            logger.e('[JS/$name HTTP] Error requesting: $e');
            if (cbId != null) {
              _resolveJsCallback(runtime, cbId, {
                'status': 500,
                'body': '',
                'error': e.toString(),
                'headers': {},
              });
            }
          }
        }());
        return '';
      });

      // Setup Spotify token bridge channel
      runtime.onMessage('wisp_get_spotify_tokens', (dynamic args) {
        unawaited(() async {
          int? cbId;
          try {
            final map = args is String
                ? jsonDecode(args) as Map<String, dynamic>
                : (args is Map
                    ? args.cast<String, dynamic>()
                    : const <String, dynamic>{});
            cbId = map['cbId'] as int?;
            final forceRefresh = map['forceRefresh'] as bool? ?? false;
            logger.i(
              '[JS/$name] Bridge requesting Spotify tokens (forceRefresh: $forceRefresh)...',
            );
            final tokens =
                await SpotifyTokenManager.getTokens(forceRefresh: forceRefresh);
            if (cbId != null) {
              if (tokens == null) {
                logger.w(
                  '[JS/$name] Bridge: No Spotify tokens available from SpotifyTokenManager',
                );
                _resolveJsCallback(runtime, cbId, {'error': 'No tokens available'});
              } else {
                logger.i(
                  '[JS/$name] Bridge: Handed Spotify tokens to JS runtime (token length: ${tokens.accessToken.length})',
                );
                _resolveJsCallback(runtime, cbId, {
                  'accessToken': tokens.accessToken,
                  'clientToken': tokens.clientToken,
                });
              }
            }
          } catch (e) {
            logger.e('[JS/$name] Bridge: Error in wisp_get_spotify_tokens: $e');
            if (cbId != null) {
              _resolveJsCallback(runtime, cbId, {'error': e.toString()});
            }
          }
        }());
        return '';
      });

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

      // Inject standard global primitives
      const bridgePolyfills = '''
        globalThis.__wisp_pending_callbacks = {};
        globalThis.__wisp_callback_counter = 0;

        globalThis.__wisp_resolve_callback = function(cbId, dataStr) {
          try {
            var cb = globalThis.__wisp_pending_callbacks[cbId];
            if (cb) {
              delete globalThis.__wisp_pending_callbacks[cbId];
              var data = typeof dataStr === 'string' ? JSON.parse(dataStr) : dataStr;
              cb(data);
            }
          } catch (e) {
            console.error('Error in __wisp_resolve_callback: ' + e);
          }
        };

        globalThis.console = {
          log: function(msg) { sendMessage('wisp_log', JSON.stringify({ level: 'info', msg: String(msg) })); },
          error: function(msg) { sendMessage('wisp_log', JSON.stringify({ level: 'error', msg: String(msg) })); },
          warn: function(msg) { sendMessage('wisp_log', JSON.stringify({ level: 'warn', msg: String(msg) })); },
          debug: function(msg) { sendMessage('wisp_log', JSON.stringify({ level: 'debug', msg: String(msg) })); }
        };

        globalThis.wisp = {
          fetch: function(url, options) {
            return new Promise(function(resolve) {
              var cbId = ++globalThis.__wisp_callback_counter;
              globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                if (!res) res = { status: 500, headers: {}, body: '' };
                resolve({
                  status: res.status || 500,
                  ok: (res.status >= 200 && res.status < 300),
                  headers: res.headers || {},
                  text: async function() { return res.body || ''; },
                  json: async function() { return JSON.parse(res.body || '{}'); }
                });
              };
              options = options || {};
              sendMessage('wisp_fetch', JSON.stringify({
                cbId: cbId,
                url: String(url),
                method: options.method || 'GET',
                headers: options.headers || {},
                body: options.body || null
              }));
            });
          },
          spotify: {
            getTokens: function(options) {
              return new Promise(function(resolve) {
                var cbId = ++globalThis.__wisp_callback_counter;
                globalThis.__wisp_pending_callbacks[cbId] = function(res) {
                  if (!res || res.error) {
                    resolve(null);
                  } else {
                    resolve(res);
                  }
                };
                options = options || {};
                sendMessage('wisp_get_spotify_tokens', JSON.stringify({
                  cbId: cbId,
                  forceRefresh: !!options.forceRefresh
                }));
              });
            }
          }
        };

        if (typeof globalThis.fetch === 'undefined') {
          globalThis.fetch = globalThis.wisp.fetch;
        }

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
      runtime.evaluate(bridgePolyfills);

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

  void _resolveJsCallback(JavascriptRuntime runtime, int cbId, dynamic data) {
    try {
      final jsonStr = jsonEncode(data);
      runtime.evaluate(
        'globalThis.__wisp_resolve_callback($cbId, ${jsonEncode(jsonStr)});',
      );
      _drainMicrotasks(runtime);
    } catch (e) {
      logger.e('[JsLyricsSource/$id] Error resolving JS callback $cbId: $e');
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
      'source': song.source.name,
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
      final providerStr = data['provider'] as String? ?? id;
      final syncModeStr = data['syncMode'] as String? ?? 'line';
      final syncMode = LyricsSyncMode.values.firstWhere(
        (m) => m.name == syncModeStr,
        orElse: () => LyricsSyncMode.line,
      );

      final rawLines = (data['lines'] as List?) ?? const [];
      final lines = <LyricsLine>[];

      for (final rawLine in rawLines) {
        if (rawLine is! Map) continue;
        final map = rawLine.cast<String, dynamic>();
        final content = map['content'] as String? ?? '';
        final startTimeMs = map['startTimeMs'] as int? ?? 0;
        final endTimeMs = map['endTimeMs'] as int?;

        final rawWords = (map['words'] as List?) ?? const [];
        final words = <LyricsWord>[];
        for (final rawWord in rawWords) {
          if (rawWord is! Map) continue;
          final wMap = rawWord.cast<String, dynamic>();
          words.add(
            LyricsWord(
              content: wMap['content'] as String? ?? '',
              startTimeMs: wMap['startTimeMs'] as int? ?? 0,
              endTimeMs: wMap['endTimeMs'] as int?,
            ),
          );
        }

        lines.add(
          LyricsLine(
            content: content,
            startTimeMs: startTimeMs,
            endTimeMs: endTimeMs,
            words: words,
          ),
        );
      }

      if (lines.isEmpty) {
        logger.w('[JsLyricsSource/$id] Result contained 0 valid lyric lines');
        return null;
      }

      final matchedType = LyricsProviderType.values.firstWhere(
        (t) => t.name.toLowerCase() == providerStr.toLowerCase(),
        orElse: () => LyricsProviderType.custom,
      );

      logger.i(
        '[JsLyricsSource/$id] Parsed ${lines.length} lines from $providerStr (mode: ${syncMode.name})',
      );

      return LyricsResult(
        provider: matchedType,
        customProviderName: name,
        syncMode: syncMode,
        lines: lines,
      );
    } catch (e, stack) {
      logger.e('[JsLyricsSource/$id] Error parsing result: $e', error: e, stackTrace: stack);
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
