// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/audio/audio_source.dart';
import 'package:wisp/data/sources/providers/js_provider_bridge.dart';

/// A modular audio source running inside a sandboxed JavaScript runtime (QuickJS / JSC).
class JsAudioSource extends AudioSource {
  @override
  final String id;

  @override
  final String name;

  @override
  final String? description;

  @override
  final bool isBuiltIn;

  @override
  final Set<AudioQuality> supportedQualities;

  @override
  final int priority;

  final String? serviceId;
  final String script;
  JavascriptRuntime? _runtime;
  bool _isInitialized = false;
  bool _failedInit = false;
  int _reqCounter = 0;
  final Map<int, Completer<dynamic>> _pendingRequests = {};

  JsAudioSource({
    required this.id,
    required this.name,
    this.description,
    this.isBuiltIn = false,
    this.supportedQualities = const {
      AudioQuality.standard,
      AudioQuality.high,
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

      // Setup search result channel
      runtime.onMessage('wisp_audio_search_result', (dynamic args) {
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          final reqId = map['reqId'] as int?;
          if (reqId != null) {
            final completer = _pendingRequests.remove(reqId);
            if (completer != null && !completer.isCompleted) {
              if (map['error'] != null) {
                logger.w('[JsAudioSource/$id] Search error: ${map['error']}');
                completer.complete(<AudioTrackCandidate>[]);
              } else {
                final rawList = map['result'] as List? ?? [];
                final candidates = rawList
                    .whereType<Map>()
                    .map((item) {
                      final m = item.cast<String, dynamic>();
                      final durationMs = (m['durationMs'] as num?)?.toInt();
                      final durationSecs = (m['durationSecs'] as num?)?.toInt() ??
                          (durationMs != null ? durationMs ~/ 1000 : 0);
                      return AudioTrackCandidate(
                        mediaId: m['id']?.toString() ?? m['mediaId']?.toString() ?? '',
                        providerId: id,
                        title: m['title']?.toString() ?? '',
                        artist: m['artist']?.toString() ?? '',
                        album: m['album']?.toString(),
                        duration: Duration(seconds: durationSecs),
                        thumbnailUrl: m['thumbnailUrl']?.toString() ?? m['thumbnail_url']?.toString(),
                        qualityLabel: m['quality']?.toString() ?? m['qualityLabel']?.toString(),
                        score: (m['score'] as num?)?.toDouble() ?? 0.0,
                      );
                    })
                    .where((c) => c.mediaId.isNotEmpty)
                    .toList();
                completer.complete(candidates);
              }
            }
          }
        } catch (e) {
          logger.e('[JsAudioSource/$id] Error handling search result: $e');
        }
        return '';
      });

      // Setup stream result channel
      runtime.onMessage('wisp_audio_stream_result', (dynamic args) {
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          final reqId = map['reqId'] as int?;
          if (reqId != null) {
            final completer = _pendingRequests.remove(reqId);
            if (completer != null && !completer.isCompleted) {
              if (map['error'] != null) {
                logger.w('[JsAudioSource/$id] Stream resolution error: ${map['error']}');
                completer.completeError(Exception(map['error']));
              } else {
                final res = map['result'] as Map<String, dynamic>?;
                if (res != null) {
                  final headers = (res['headers'] as Map?)?.cast<String, String>();
                  DateTime? expiresAt;
                  if (res['expiresAt'] != null) {
                    expiresAt = DateTime.tryParse(res['expiresAt'].toString());
                  }
                  final segmentedMap = res['segmented'] as Map?;
                  final segmented = segmentedMap != null
                      ? SegmentedAudioDescriptor.fromMap(segmentedMap.cast<String, dynamic>())
                      : null;
                  completer.complete(
                    AudioStreamResult(
                      url: res['url']?.toString() ?? '',
                      headers: headers,
                      format: res['format']?.toString(),
                      bitrate: (res['bitrate'] as num?)?.toInt(),
                      sampleRate: (res['sampleRate'] as num?)?.toInt(),
                      bitDepth: (res['bitDepth'] as num?)?.toInt(),
                      expiresAt: expiresAt,
                      segmented: segmented,
                      customData: (res['customData'] as Map?)?.cast<String, dynamic>(),
                    ),
                  );
                } else {
                  completer.completeError(Exception('No stream result returned'));
                }
              }
            }
          }
        } catch (e) {
          logger.e('[JsAudioSource/$id] Error handling stream result: $e');
        }
        return '';
      });

      // Inject audio helper polyfills
      const audioPolyfill = '''
        globalThis.__wisp_invoke_searchAudio = function(reqId, id, queryStr) {
          try {
            var query = typeof queryStr === 'string' ? JSON.parse(queryStr) : queryStr;
            var provider = globalThis['__wisp_provider_' + id];
            if (!provider || typeof provider.searchAudio !== 'function') {
              sendMessage('wisp_audio_search_result', JSON.stringify({
                reqId: reqId,
                error: 'Provider ' + id + '.searchAudio is not a function'
              }));
              return;
            }
            Promise.resolve(provider.searchAudio(query)).then(function(result) {
              sendMessage('wisp_audio_search_result', JSON.stringify({
                reqId: reqId,
                result: result || []
              }));
            }).catch(function(err) {
              sendMessage('wisp_audio_search_result', JSON.stringify({
                reqId: reqId,
                error: String(err)
              }));
            });
          } catch (e) {
            sendMessage('wisp_audio_search_result', JSON.stringify({
              reqId: reqId,
              error: String(e)
            }));
          }
        };

        globalThis.__wisp_invoke_getStreamUrl = function(reqId, id, mediaId, optionsStr) {
          try {
            var options = typeof optionsStr === 'string' ? JSON.parse(optionsStr) : optionsStr;
            var provider = globalThis['__wisp_provider_' + id];
            if (!provider || typeof provider.getStreamUrl !== 'function') {
              sendMessage('wisp_audio_stream_result', JSON.stringify({
                reqId: reqId,
                error: 'Provider ' + id + '.getStreamUrl is not a function'
              }));
              return;
            }
            Promise.resolve(provider.getStreamUrl(mediaId, options)).then(function(result) {
              sendMessage('wisp_audio_stream_result', JSON.stringify({
                reqId: reqId,
                result: result || null
              }));
            }).catch(function(err) {
              sendMessage('wisp_audio_stream_result', JSON.stringify({
                reqId: reqId,
                error: String(err)
              }));
            });
          } catch (e) {
            sendMessage('wisp_audio_stream_result', JSON.stringify({
              reqId: reqId,
              error: String(e)
            }));
          }
        };
      ''';
      runtime.evaluate(audioPolyfill);
      runtime.enableHandlePromises();

      _evaluateProviderScript(runtime);
      _runtime = runtime;
      _isInitialized = true;
    } catch (e) {
      _failedInit = true;
      logger.w('[JsAudioSource] Could not initialize JS runtime for $name: $e');
    }
  }

  void _drainMicrotasks(JavascriptRuntime runtime) {
    try {
      while (runtime.executePendingJob() > 0) {}
    } catch (_) {}
  }

  void _evaluateProviderScript(JavascriptRuntime runtime) {
    final encodedId = jsonEncode(id);
    final wrappedScript = '''
      var exports = {};
      var module = { exports: exports };
      (function(exports, module) {
        $script

        if (typeof searchAudio === 'function') exports.searchAudio = searchAudio;
        if (typeof getStreamUrl === 'function') exports.getStreamUrl = getStreamUrl;
        if (module.exports) {
          if (typeof module.exports.searchAudio === 'function') exports.searchAudio = module.exports.searchAudio;
          if (typeof module.exports.getStreamUrl === 'function') exports.getStreamUrl = module.exports.getStreamUrl;
        }
      })(exports, module);

      if (module.exports && (module.exports.searchAudio || module.exports.getStreamUrl)) {
        exports = module.exports;
      }
      globalThis['__wisp_provider_' + $encodedId] = exports;
    ''';
    final evalRes = runtime.evaluate(wrappedScript);
    if (evalRes.isError) {
      logger.e('[JsAudioSource/$id] Script evaluation failed: ${evalRes.stringResult}');
    } else {
      final checkRes = runtime.evaluate(
        'typeof globalThis["__wisp_provider_" + $encodedId]?.searchAudio === "function"',
      );
      final hasSearchAudio = checkRes.stringResult == 'true';
      if (hasSearchAudio) {
        logger.i('[JsAudioSource/$id] Script evaluated and searchAudio is available');
      } else {
        logger.w('[JsAudioSource/$id] Script evaluated but searchAudio was not registered on provider exports');
      }
    }
    _drainMicrotasks(runtime);
  }

  @override
  Future<List<AudioTrackCandidate>> searchAudio(AudioSearchQuery query) async {
    if (!_isInitialized) await initialize();
    final runtime = _runtime;
    if (runtime == null) return [];

    final reqId = ++_reqCounter;
    final completer = Completer<List<AudioTrackCandidate>>();
    _pendingRequests[reqId] = completer;

    final queryMap = {
      'title': query.title,
      'artists': query.artists,
      'artist': query.artistNames,
      'album': query.album,
      'durationSecs': query.durationSecs,
      'isrc': query.isrc,
      'trackId': query.trackId,
      'metadataSource': query.metadataSource,
    };

    final encId = jsonEncode(id);
    final encQuery = jsonEncode(jsonEncode(queryMap));

    runtime.evaluate('globalThis.__wisp_invoke_searchAudio($reqId, $encId, $encQuery);');
    _drainMicrotasks(runtime);

    Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (completer.isCompleted) {
        timer.cancel();
      } else {
        _drainMicrotasks(runtime);
      }
    });

    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        _pendingRequests.remove(reqId);
        logger.w('[JsAudioSource/$id] searchAudio timed out');
        return [];
      },
    );
  }

  @override
  Future<AudioStreamResult> getStreamUrl(
    String mediaId, {
    AudioQuality? preferredQuality,
  }) async {
    if (!_isInitialized) await initialize();
    final runtime = _runtime;
    if (runtime == null) throw Exception('JS runtime not initialized for $name');

    final reqId = ++_reqCounter;
    final completer = Completer<AudioStreamResult>();
    _pendingRequests[reqId] = completer;

    final optionsMap = {
      'preferredQuality': preferredQuality?.name ?? AudioQuality.auto.name,
    };

    final encId = jsonEncode(id);
    final encMediaId = jsonEncode(mediaId);
    final encOptions = jsonEncode(jsonEncode(optionsMap));

    runtime.evaluate(
      'globalThis.__wisp_invoke_getStreamUrl($reqId, $encId, $encMediaId, $encOptions);',
    );
    _drainMicrotasks(runtime);

    Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (completer.isCompleted) {
        timer.cancel();
      } else {
        _drainMicrotasks(runtime);
      }
    });

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingRequests.remove(reqId);
        throw TimeoutException('getStreamUrl timed out for $mediaId in $name');
      },
    );
  }

  @override
  void dispose() {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Disposed'));
      }
    }
    _pendingRequests.clear();
    _runtime?.dispose();
    _runtime = null;
    _isInitialized = false;
  }
}

