// Copyright © 2026 wizeshi

/// Central network connectivity state service wrapping connectivity_plus
library;

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:wisp/core/utils/logger.dart';

class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);

  /// Whether internet network connectivity is currently available.
  bool get isOnline => _isOnline;

  /// Stream of online boolean status changes.
  final StreamController<bool> _connectivityStreamController =
      StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged =>
      _connectivityStreamController.stream;
  bool _disposed = false;

  /// Initialize connectivity listeners at app startup.
  Future<void> initialize() async {
    if (_subscription != null) return;

    try {
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);
    } catch (e) {
      logger.w('[ConnectivityService] Failed initial connectivity check: $e');
      _isOnline = true;
      isOnlineNotifier.value = true;
    }

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateStatus(results);
    });
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final online =
        results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
    if (_isOnline != online) {
      _isOnline = online;
      isOnlineNotifier.value = online;
      _connectivityStreamController.add(online);
      logger.d(
        '[ConnectivityService] Connectivity changed: ${online ? 'online' : 'offline'} ($results)',
      );
    }
  }

  /// Perform an active connectivity check.
  Future<bool> checkOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);
      return _isOnline;
    } catch (e) {
      logger.w('[ConnectivityService] checkOnline failed: $e');
      return _isOnline;
    }
  }

  @visibleForTesting
  void setMockOnline(bool online) {
    _isOnline = online;
    isOnlineNotifier.value = online;
    _connectivityStreamController.add(online);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    _connectivityStreamController.close();
  }
}
