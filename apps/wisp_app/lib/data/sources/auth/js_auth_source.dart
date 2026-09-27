// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/providers/js_provider_bridge.dart';
import 'package:wisp/data/sources/providers/service_session_manager.dart';

/// Modular authentication provider powered by a JavaScript runtime.
class JsAuthSource {
  final String id;
  final String name;
  final String serviceId;
  final String script;

  JavascriptRuntime? _runtime;
  bool _isInitialized = false;
  bool _failedInit = false;
  int _reqCounter = 0;
  final Map<int, Completer<dynamic>> _pendingRequests = {};

  JsAuthSource({
    required this.id,
    required this.name,
    required this.serviceId,
    required this.script,
  });

  Future<void> initialize() async {
    if (_isInitialized || _failedInit) return;
    try {
      final runtime = getJavascriptRuntime();
      JsProviderBridge.setupBridge(
        runtime,
        providerId: id,
        providerName: name,
        serviceId: serviceId,
      );

      runtime.onMessage('wisp_auth_result', (dynamic args) {
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
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
          logger.e('[JsAuthSource/$id] Error handling auth result: $e');
        }
        return '';
      });

      runtime.evaluate('''
        globalThis.__wisp_invoke_auth = function(reqId, method, argsJson) {
          Promise.resolve().then(function() {
            var fn = globalThis[method];
            if (typeof fn !== 'function') {
              throw new Error('Method ' + method + ' is not a function');
            }
            var args = argsJson ? JSON.parse(argsJson) : [];
            return fn.apply(null, args);
          }).then(function(result) {
            sendMessage('wisp_auth_result', JSON.stringify({ reqId: reqId, result: result }));
          }).catch(function(err) {
            sendMessage('wisp_auth_result', JSON.stringify({ reqId: reqId, error: String(err) }));
          });
        };
      ''');

      final evalResult = runtime.evaluate(script);
      if (evalResult.isError) {
        throw Exception('JS eval error: ${evalResult.stringResult}');
      }

      while (runtime.executePendingJob() > 0) {}

      _runtime = runtime;
      _isInitialized = true;
      logger.i('[JsAuthSource/$id] Successfully initialized auth provider');
    } catch (e) {
      _failedInit = true;
      logger.e('[JsAuthSource/$id] Initialization error: $e');
    }
  }

  Future<dynamic> _invoke(String method, [List<dynamic> args = const []]) async {
    if (!_isInitialized && !_failedInit) {
      await initialize();
    }
    final runtime = _runtime;
    if (runtime == null) {
      throw StateError('[JsAuthSource] JS runtime not available');
    }

    final reqId = ++_reqCounter;
    final completer = Completer<dynamic>();
    _pendingRequests[reqId] = completer;

    final argsJson = jsonEncode(args);
    final call = 'globalThis.__wisp_invoke_auth($reqId, ${jsonEncode(method)}, ${jsonEncode(argsJson)});';
    final res = runtime.evaluate(call);
    if (res.isError) {
      _pendingRequests.remove(reqId);
      throw Exception('JS invoke error: ${res.stringResult}');
    }
    while (runtime.executePendingJob() > 0) {}

    return await completer.future.timeout(const Duration(seconds: 45));
  }

  Future<void> login() async {
    try {
      await _invoke('login');
    } catch (e) {
      logger.e('[JsAuthSource/$id] Login failed: $e');
    }
  }

  Future<void> logout() async {
    try {
      await _invoke('logout');
      await ServiceSessionManager.instance.clearSession(serviceId);
    } catch (e) {
      logger.e('[JsAuthSource/$id] Logout failed: $e');
    }
  }

  Future<bool> isAuthenticated() async {
    try {
      final res = await _invoke('isAuthenticated');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    try {
      _runtime?.dispose();
    } catch (_) {}
    _runtime = null;
    _isInitialized = false;
  }
}
