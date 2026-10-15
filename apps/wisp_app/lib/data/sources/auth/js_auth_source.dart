// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/providers/service_session_manager.dart';
import 'package:wisp/data/sources/providers/shared_js_runtime.dart';

/// Modular authentication provider powered by the shared JavaScript runtime.
class JsAuthSource extends ChangeNotifier {
  final String id;
  final String name;
  final String serviceId;
  final String script;
  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;
  String get displayName =>
      name.replaceAll(RegExp(r'\s+Auth$', caseSensitive: false), '');

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  JsAuthSource({
    required this.id,
    required this.name,
    required this.serviceId,
    required this.script,
  }) {
    ServiceSessionManager.instance.addListener(serviceId, _onSessionChanged);
    _checkInitialSession();
  }

  void _onSessionChanged(Map<String, dynamic>? session) {
    final authed = session != null &&
        (session['accessToken'] != null ||
            (session['cookies'] is Map &&
                (session['cookies'] as Map).isNotEmpty) ||
            session['cookie'] != null);
    if (_isAuthenticated != authed) {
      _isAuthenticated = authed;
      notifyListeners();
    }
  }

  Future<void> _checkInitialSession() async {
    final session = await ServiceSessionManager.instance.getSession(serviceId);
    _onSessionChanged(session);
  }

  Future<void> initialize() async {
    // Eager runtime creation is replaced with lazy evaluation in SharedJsRuntime.
    _isInitialized = true;
  }

  Future<void> _ensureLoaded() async {
    await SharedJsRuntime.instance.loadProvider(
      id: id,
      name: name,
      script: script,
      serviceId: serviceId,
      type: 'auth',
    );
  }


  Future<dynamic> _invoke(String method, [List<dynamic> args = const []]) async {
    await _ensureLoaded();
    return await SharedJsRuntime.instance.invokeAuth(id, method, args);
  }

  Future<void> login() async {
    try {
      await _invoke('login');
    } catch (e) {
      logger.e('[JsAuthSource/$id] Login failed: $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _invoke('logout');
      await ServiceSessionManager.instance.clearSession(serviceId);
    } catch (e) {
      logger.e('[JsAuthSource/$id] Logout failed: $e');
      rethrow;
    }
  }

  Future<bool> checkAuthenticated() async {
    try {
      final res = await _invoke('isAuthenticated');
      final authed = res == true;
      if (_isAuthenticated != authed) {
        _isAuthenticated = authed;
        notifyListeners();
      }
      return authed;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getTokens({bool forceRefresh = false}) async {
    try {
      final res = await _invoke('getTokens', [forceRefresh]);
      if (res is Map) {
        return res.cast<String, dynamic>();
      }
      return null;
    } catch (e) {
      logger.e('[JsAuthSource/$id] getTokens failed: $e');
      return null;
    }
  }

  @override
  void dispose() {
    ServiceSessionManager.instance.removeListener(serviceId, _onSessionChanged);
    SharedJsRuntime.instance.unloadProvider(id, type: 'auth');
    _isInitialized = false;
    super.dispose();
  }
}

