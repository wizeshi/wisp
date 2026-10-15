// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/providers/js_provider_bridge.dart';

/// Central singleton that hosts all modular JavaScript providers within a single
/// shared QuickJS runtime to minimize memory usage and overhead.
class SharedJsRuntime {
  static final SharedJsRuntime instance = SharedJsRuntime._();
  SharedJsRuntime._();

  JavascriptRuntime? _runtime;
  final Set<String> _loadedProviders = {};
  final Map<String, Completer<void>> _loadCompleters = {};
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _reqCounter = 0;
  bool _initializing = false;
  Completer<void>? _initCompleter;

  bool isProviderLoaded(String providerId, {String? type}) {
    final effectiveType = type?.trim().toLowerCase();
    if (effectiveType != null && effectiveType.isNotEmpty) {
      return _loadedProviders.contains('$effectiveType/$providerId') ||
          _loadedProviders.contains(providerId);
    }
    return _loadedProviders.contains(providerId) ||
        _loadedProviders.contains('audio/$providerId') ||
        _loadedProviders.contains('auth/$providerId') ||
        _loadedProviders.contains('lyrics/$providerId') ||
        _loadedProviders.contains('metadata/$providerId');
  }

  JavascriptRuntime get runtime {
    if (_runtime == null) {
      _initSync();
    }
    return _runtime!;
  }

  void _initSync() {
    if (_runtime != null) return;
    try {
      final rt = getJavascriptRuntime();
      _runtime = rt;
      _setupHostRuntime(rt);
    } catch (e) {
      logger.e('[SharedJsRuntime] Failed to initialize JavascriptRuntime: $e');
      rethrow;
    }
  }

  Future<void> ensureInitialized() async {
    if (_runtime != null) return;
    if (_initializing) {
      return _initCompleter?.future;
    }
    _initializing = true;
    _initCompleter = Completer<void>();
    try {
      _initSync();
      _initCompleter?.complete();
    } catch (e) {
      _initCompleter?.completeError(e);
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  void drainMicrotasks() {
    final rt = _runtime;
    if (rt == null) return;
    try {
      while (rt.executePendingJob() > 0) {}
    } catch (_) {}
  }

  void _setupHostRuntime(JavascriptRuntime rt) {
    // 1. Setup host bridges (fetch, storage, auth, crypto, vault, log)
    JsProviderBridge.setupSharedBridge(rt);

    // 2. Setup audio search callback channel
    rt.onMessage('wisp_audio_search_result', (dynamic args) {
      _handleResultChannel('wisp_audio_search_result', args);
      return '';
    });

    // 3. Setup audio stream callback channel
    rt.onMessage('wisp_audio_stream_result', (dynamic args) {
      _handleResultChannel('wisp_audio_stream_result', args);
      return '';
    });

    // 4. Setup lyrics callback channel
    rt.onMessage('wisp_lyrics_result', (dynamic args) {
      _handleResultChannel('wisp_lyrics_result', args);
      return '';
    });

    // 5. Setup metadata callback channel
    rt.onMessage('wisp_metadata_result', (dynamic args) {
      _handleResultChannel('wisp_metadata_result', args);
      return '';
    });

    // 6. Setup auth callback channel
    rt.onMessage('wisp_auth_result', (dynamic args) {
      _handleResultChannel('wisp_auth_result', args);
      return '';
    });

    // 7. Inject global invocation polyfills
    const globalPolyfills = '''
      globalThis.__wisp_providers = globalThis.__wisp_providers || {};

      globalThis.__wisp_invoke_searchAudio = function(reqId, id, queryStr) {
        try {
          var query = typeof queryStr === 'string' ? JSON.parse(queryStr) : queryStr;
          var provider = globalThis.__wisp_providers['audio/' + id] || globalThis.__wisp_providers[id] || globalThis['__wisp_provider_audio_' + id] || globalThis['__wisp_provider_' + id];
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
          var provider = globalThis.__wisp_providers['audio/' + id] || globalThis.__wisp_providers[id] || globalThis['__wisp_provider_audio_' + id] || globalThis['__wisp_provider_' + id];
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

      globalThis.__wisp_invoke_getLyrics = function(reqId, id, queryStr) {
        try {
          var query = typeof queryStr === 'string' ? JSON.parse(queryStr) : queryStr;
          var provider = globalThis.__wisp_providers['lyrics/' + id] || globalThis.__wisp_providers[id] || globalThis['__wisp_provider_lyrics_' + id] || globalThis['__wisp_provider_' + id];
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

      globalThis.__wisp_invoke_metadata = function(reqId, id, method, argsJson) {
        try {
          var args = typeof argsJson === 'string' ? JSON.parse(argsJson) : (argsJson || []);
          var provider = globalThis.__wisp_providers['metadata/' + id] || globalThis.__wisp_providers[id] || globalThis['__wisp_provider_metadata_' + id] || globalThis['__wisp_provider_' + id] || globalThis.__wisp_metadata_provider;
          var fn = (provider && provider[method]) || (provider && provider.default && provider.default[method]) || globalThis[method];
          if (typeof fn !== 'function') {
            sendMessage('wisp_metadata_result', JSON.stringify({
              reqId: reqId,
              error: 'Method ' + method + ' on provider ' + id + ' is not a function'
            }));
            return;
          }
          Promise.resolve(fn.apply(provider || null, args)).then(function(result) {
            sendMessage('wisp_metadata_result', JSON.stringify({
              reqId: reqId,
              result: result
            }));
          }).catch(function(err) {
            sendMessage('wisp_metadata_result', JSON.stringify({
              reqId: reqId,
              error: String(err)
            }));
          });
        } catch (e) {
          sendMessage('wisp_metadata_result', JSON.stringify({
            reqId: reqId,
            error: String(e)
          }));
        }
      };

      globalThis.__wisp_invoke_auth = function(reqId, id, method, argsJson) {
        try {
          var args = typeof argsJson === 'string' ? JSON.parse(argsJson) : (argsJson || []);
          var provider = globalThis.__wisp_providers['auth/' + id] || globalThis.__wisp_providers[id] || globalThis['__wisp_provider_auth_' + id] || globalThis['__wisp_provider_' + id];
          var fn = (provider && provider[method]) || (provider && provider.default && provider.default[method]) || globalThis[method];
          if (typeof fn !== 'function') {
            sendMessage('wisp_auth_result', JSON.stringify({
              reqId: reqId,
              error: 'Method ' + method + ' on provider ' + id + ' is not a function'
            }));
            return;
          }
          Promise.resolve(fn.apply(provider || null, args)).then(function(result) {
            sendMessage('wisp_auth_result', JSON.stringify({
              reqId: reqId,
              result: result
            }));
          }).catch(function(err) {
            sendMessage('wisp_auth_result', JSON.stringify({
              reqId: reqId,
              error: String(err)
            }));
          });
        } catch (e) {
          sendMessage('wisp_auth_result', JSON.stringify({
            reqId: reqId,
            error: String(e)
          }));
        }
      };
    ''';
    rt.evaluate(globalPolyfills);
    rt.enableHandlePromises();
  }


  void _handleResultChannel(String channel, dynamic args) {
    try {
      final map = args is String
          ? jsonDecode(args) as Map<String, dynamic>
          : (args is Map ? args.cast<String, dynamic>() : const <String, dynamic>{});
      final reqId = map['reqId'] as int?;
      if (reqId != null) {
        final completer = _pendingRequests.remove(reqId);
        if (completer != null && !completer.isCompleted) {
          if (map.containsKey('error') && map['error'] != null) {
            completer.completeError(Exception(map['error']));
          } else {
            completer.complete(map['result']);
          }
        }
      }
    } catch (e) {
      logger.e('[SharedJsRuntime] Error handling result on $channel: $e');
    }
  }

  /// Lazily evaluates a provider's JavaScript code into the shared runtime under its namespace.
  Future<void> loadProvider({
    required String id,
    required String name,
    required String script,
    String? serviceId,
    String? type,
  }) async {
    final effectiveType = type?.trim().toLowerCase();
    final providerKey = (effectiveType != null && effectiveType.isNotEmpty)
        ? '$effectiveType/$id'
        : id;

    if (_loadedProviders.contains(providerKey)) return;

    if (_loadCompleters.containsKey(providerKey)) {
      return _loadCompleters[providerKey]!.future;
    }

    final completer = Completer<void>();
    _loadCompleters[providerKey] = completer;

    try {
      await ensureInitialized();
      final rt = runtime;

      final encodedId = jsonEncode(id);
      final encodedKey = jsonEncode(providerKey);
      final encodedName = jsonEncode(name);
      final encodedServiceId = jsonEncode(serviceId ?? id);

      final wrappedScript = '''
        (function(wisp) {
          var exports = {};
          var module = { exports: exports };
          globalThis.__wisp_current_provider = $encodedKey;

          $script

          var finalExports = (module.exports && Object.keys(module.exports).length > 0)
              ? module.exports
              : exports;

          if (typeof searchAudio === 'function' && !finalExports.searchAudio) finalExports.searchAudio = searchAudio;
          if (typeof getStreamUrl === 'function' && !finalExports.getStreamUrl) finalExports.getStreamUrl = getStreamUrl;
          if (typeof getLyrics === 'function' && !finalExports.getLyrics) finalExports.getLyrics = getLyrics;
          if (typeof getTokens === 'function' && !finalExports.getTokens) finalExports.getTokens = getTokens;
          if (typeof login === 'function' && !finalExports.login) finalExports.login = login;
          if (typeof logout === 'function' && !finalExports.logout) finalExports.logout = logout;
          if (typeof isAuthenticated === 'function' && !finalExports.isAuthenticated) finalExports.isAuthenticated = isAuthenticated;

          globalThis.__wisp_providers = globalThis.__wisp_providers || {};
          globalThis.__wisp_providers[$encodedKey] = finalExports;
          globalThis['__wisp_provider_' + $encodedKey] = finalExports;

          var sanitizedKey = $encodedKey.replace(/[^a-zA-Z0-9_]/g, '_');
          globalThis['__wisp_provider_' + sanitizedKey] = finalExports;

          if (!globalThis.__wisp_providers[$encodedId]) {
            globalThis.__wisp_providers[$encodedId] = finalExports;
          }

          // For metadata provider backward compatibility
          if (!globalThis.__wisp_metadata_provider && finalExports.search) {
            globalThis.__wisp_metadata_provider = finalExports;
          }
        })(globalThis.wisp.createScope($encodedKey, $encodedName, $encodedServiceId));
      ''';

      final res = rt.evaluate(wrappedScript);
      if (res.isError) {
        throw Exception('Failed to evaluate provider "$providerKey": ${res.stringResult}');
      }
      drainMicrotasks();

      _loadedProviders.add(providerKey);
      logger.i('[SharedJsRuntime] Evaluated and registered provider "$providerKey"');
      completer.complete();
    } catch (e, stack) {
      logger.e('[SharedJsRuntime] Error loading provider "$providerKey": $e', error: e, stackTrace: stack);
      completer.completeError(e, stack);
      rethrow;
    } finally {
      _loadCompleters.remove(providerKey);
    }
  }

  void unloadProvider(String id, {String? type}) {
    final effectiveType = type?.trim().toLowerCase();
    final providerKey = (effectiveType != null && effectiveType.isNotEmpty)
        ? '$effectiveType/$id'
        : id;
    if (!_loadedProviders.contains(providerKey) && !_loadedProviders.contains(id)) return;
    try {
      final encodedKey = jsonEncode(providerKey);
      final encodedId = jsonEncode(id);
      runtime.evaluate('''
        if (globalThis.__wisp_providers) {
          delete globalThis.__wisp_providers[$encodedKey];
          delete globalThis.__wisp_providers[$encodedId];
        }
        delete globalThis['__wisp_provider_' + $encodedKey];
        delete globalThis['__wisp_provider_' + $encodedId];
        var sanitizedKey = $encodedKey.replace(/[^a-zA-Z0-9_]/g, '_');
        delete globalThis['__wisp_provider_' + sanitizedKey];
      ''');
      drainMicrotasks();
      _loadedProviders.remove(providerKey);
      _loadedProviders.remove(id);
      logger.i('[SharedJsRuntime] Unloaded provider "$providerKey"');
    } catch (e) {
      logger.w('[SharedJsRuntime] Error unloading provider "$providerKey": $e');
    }
  }


  Future<dynamic> _invokeJs(String call, {Duration timeout = const Duration(seconds: 25)}) async {
    final rt = runtime;
    final reqId = ++_reqCounter;
    final completer = Completer<dynamic>();
    _pendingRequests[reqId] = completer;

    final formattedCall = call.replaceFirst('__REQ_ID__', reqId.toString());
    final res = rt.evaluate(formattedCall);
    if (res.isError) {
      _pendingRequests.remove(reqId);
      throw Exception('JS invocation error: ${res.stringResult}');
    }
    drainMicrotasks();

    return await completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(reqId);
        throw TimeoutException('JS operation timed out after $timeout');
      },
    );
  }

  Future<dynamic> searchAudio(String providerId, Map<String, dynamic> query) {
    final queryStr = jsonEncode(query);
    return _invokeJs(
      'globalThis.__wisp_invoke_searchAudio(__REQ_ID__, ${jsonEncode(providerId)}, ${jsonEncode(queryStr)});',
      timeout: const Duration(seconds: 20),
    );
  }

  Future<dynamic> getStreamUrl(String providerId, String mediaId, Map<String, dynamic> options) {
    final optsStr = jsonEncode(options);
    return _invokeJs(
      'globalThis.__wisp_invoke_getStreamUrl(__REQ_ID__, ${jsonEncode(providerId)}, ${jsonEncode(mediaId)}, ${jsonEncode(optsStr)});',
      timeout: const Duration(seconds: 25),
    );
  }

  Future<dynamic> getLyrics(String providerId, Map<String, dynamic> query) {
    final queryStr = jsonEncode(query);
    return _invokeJs(
      'globalThis.__wisp_invoke_getLyrics(__REQ_ID__, ${jsonEncode(providerId)}, ${jsonEncode(queryStr)});',
      timeout: const Duration(seconds: 15),
    );
  }

  Future<dynamic> invokeMetadata(String providerId, String method, List<dynamic> args) {
    final argsJson = jsonEncode(args);
    return _invokeJs(
      'globalThis.__wisp_invoke_metadata(__REQ_ID__, ${jsonEncode(providerId)}, ${jsonEncode(method)}, ${jsonEncode(argsJson)});',
      timeout: const Duration(seconds: 25),
    );
  }

  Future<dynamic> invokeAuth(String providerId, String method, List<dynamic> args) {
    final argsJson = jsonEncode(args);
    return _invokeJs(
      'globalThis.__wisp_invoke_auth(__REQ_ID__, ${jsonEncode(providerId)}, ${jsonEncode(method)}, ${jsonEncode(argsJson)});',
      timeout: const Duration(seconds: 30),
    );
  }

  void dispose() {
    _loadedProviders.clear();
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('SharedJsRuntime disposed'));
      }
    }
    _pendingRequests.clear();
    try {
      _runtime?.dispose();
    } catch (_) {}
    _runtime = null;
  }
}
