// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/services/system/credentials.dart';

/// Centralized, service-agnostic session vault for providers (e.g. Spotify, Apple Music).
/// Manages persistent storage, in-memory caching, and refresh concurrency locks.
class ServiceSessionManager {
  static final ServiceSessionManager instance = ServiceSessionManager._();
  ServiceSessionManager._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Map<String, Map<String, dynamic>> _inMemorySessions = {};
  final Map<String, Completer<Map<String, dynamic>?>> _activeRefreshLocks = {};
  final Map<String, Set<void Function(Map<String, dynamic>?)>> _listeners = {};

  static const String _storagePrefix = 'wisp_service_session_';

  /// Retrieve the active session for a given service realm (e.g. 'spotify', 'apple_music').
  Future<Map<String, dynamic>?> getSession(String serviceId) async {
    // 1. Check in-memory cache
    if (_inMemorySessions.containsKey(serviceId)) {
      return _inMemorySessions[serviceId];
    }

    // 2. Read from secure storage
    try {
      final str = await _storage.read(key: '$_storagePrefix$serviceId');
      if (str != null && str.trim().isNotEmpty) {
        final data = jsonDecode(str) as Map<String, dynamic>;
        _inMemorySessions[serviceId] = data;
        return data;
      }
    } catch (e) {
      logger.e('[ServiceSessionManager] Failed to read session for $serviceId: $e');
    }

    // 3. Fallback / seed from legacy credentials if available
    if (serviceId == 'spotify') {
      final legacySession = await _seedLegacySpotifySession();
      if (legacySession != null) {
        await setSession('spotify', legacySession);
        return legacySession;
      }
    }

    return null;
  }

  /// Store or update session data for a service realm.
  Future<void> setSession(String serviceId, Map<String, dynamic> session) async {
    _inMemorySessions[serviceId] = session;
    try {
      await _storage.write(
        key: '$_storagePrefix$serviceId',
        value: jsonEncode(session),
      );
      logger.i('[ServiceSessionManager] Updated session for service "$serviceId"');
    } catch (e) {
      logger.e('[ServiceSessionManager] Failed to write session for $serviceId: $e');
    }
    _notifyListeners(serviceId, session);
  }

  /// Clear the session on logout.
  Future<void> clearSession(String serviceId) async {
    _inMemorySessions.remove(serviceId);
    try {
      await _storage.delete(key: '$_storagePrefix$serviceId');
      logger.i('[ServiceSessionManager] Cleared session for service "$serviceId"');
    } catch (e) {
      logger.e('[ServiceSessionManager] Failed to clear session for $serviceId: $e');
    }
    _notifyListeners(serviceId, null);
  }

  /// Run refresh logic under a host-level mutex lock per serviceId.
  /// If multiple callers trigger a refresh at the same time, only the first executes [refreshFn];
  /// subsequent callers await the same completion and receive the fresh tokens.
  Future<Map<String, dynamic>?> withRefreshLock(
    String serviceId,
    Future<Map<String, dynamic>?> Function() refreshFn,
  ) async {
    final existingLock = _activeRefreshLocks[serviceId];
    if (existingLock != null) {
      logger.i('[ServiceSessionManager] Awaiting existing refresh lock for service "$serviceId"...');
      return await existingLock.future;
    }

    final completer = Completer<Map<String, dynamic>?>();
    _activeRefreshLocks[serviceId] = completer;

    try {
      logger.i('[ServiceSessionManager] Acquired refresh lock for service "$serviceId"');
      final result = await refreshFn();
      if (result != null) {
        await setSession(serviceId, result);
      }
      completer.complete(result);
      return result;
    } catch (e, stack) {
      logger.e(
        '[ServiceSessionManager] Error in refresh lock for service "$serviceId": $e',
        error: e,
        stackTrace: stack,
      );
      completer.completeError(e, stack);
      rethrow;
    } finally {
      _activeRefreshLocks.remove(serviceId);
    }
  }

  /// Subscribe to session changes for a given service realm.
  void addListener(String serviceId, void Function(Map<String, dynamic>?) listener) {
    _listeners.putIfAbsent(serviceId, () => {}).add(listener);
  }

  /// Unsubscribe from session changes.
  void removeListener(String serviceId, void Function(Map<String, dynamic>?) listener) {
    _listeners[serviceId]?.remove(listener);
  }

  void _notifyListeners(String serviceId, Map<String, dynamic>? session) {
    final listeners = _listeners[serviceId];
    if (listeners == null) return;
    for (final listener in List.of(listeners)) {
      try {
        listener(session);
      } catch (e) {
        logger.e('[ServiceSessionManager] Error notifying listener for $serviceId: $e');
      }
    }
  }

  /// Migration helper: seeds the 'spotify' session from existing CredentialsService data
  Future<Map<String, dynamic>?> _seedLegacySpotifySession() async {
    try {
      final creds = CredentialsService();
      final cookie = await creds.getSpotifyLyricsCookie();
      if (cookie != null && cookie.trim().isNotEmpty) {
        logger.i('[ServiceSessionManager] Seeding spotify session from legacy stored cookie');
        return {
          'cookies': {
            'sp_dc': _extractSpDc(cookie),
          },
        };
      }
    } catch (_) {}
    return null;
  }

  String _extractSpDc(String cookie) {
    for (final seg in cookie.split(';')) {
      final part = seg.trim();
      if (part.toLowerCase().startsWith('sp_dc=')) {
        return part.substring(6).trim();
      }
    }
    return cookie.trim();
  }
}
