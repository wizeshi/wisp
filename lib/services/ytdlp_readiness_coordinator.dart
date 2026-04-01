library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../providers/audio/youtube.dart';
import '../utils/logger.dart';
import 'notification_service.dart';
import 'ytdlp_manager.dart';

enum YtDlpReadinessState { idle, initializing, ready, failed }

class YtDlpNotReadyException implements Exception {
  final String message;

  YtDlpNotReadyException(this.message);

  @override
  String toString() => 'YtDlpNotReadyException: $message';
}

class YtDlpReadinessCoordinator extends ChangeNotifier {
  static final YtDlpReadinessCoordinator instance =
      YtDlpReadinessCoordinator._();

  YtDlpReadinessCoordinator._();

  static const int _notificationId = 42001;

  YtDlpReadinessState _state = YtDlpReadinessState.idle;
  String? _lastError;
  Future<void>? _initializeFuture;

  YtDlpReadinessState get state => _state;
  String? get lastError => _lastError;

  bool get isReady => !_requiresYtDlp || _state == YtDlpReadinessState.ready;

  bool get isInitializing =>
      _requiresYtDlp && _state == YtDlpReadinessState.initializing;

  bool get hasFailed => _state == YtDlpReadinessState.failed;

  bool get _requiresYtDlp =>
      Platform.isAndroid || Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  Future<void> startInitialization() async {
    if (!_requiresYtDlp) {
      _setState(YtDlpReadinessState.ready);
      return;
    }

    if (_state == YtDlpReadinessState.ready) return;
    if (_initializeFuture != null) {
      await _initializeFuture;
      return;
    }

    final future = _runInitialization();
    _initializeFuture = future;
    try {
      await future;
    } finally {
      _initializeFuture = null;
    }
  }

  void startInitializationInBackground() {
    unawaited(startInitialization());
  }

  Future<void> waitUntilReady() async {
    if (!_requiresYtDlp) return;

    if (_state == YtDlpReadinessState.ready) return;
    if (_state == YtDlpReadinessState.failed) {
      throw YtDlpNotReadyException(_lastError ?? 'YT-DLP initialization failed.');
    }

    await startInitialization();

    if (_state != YtDlpReadinessState.ready) {
      throw YtDlpNotReadyException(_lastError ?? 'YT-DLP initialization failed.');
    }
  }

  Future<void> _runInitialization() async {
    _lastError = null;
    _setState(YtDlpReadinessState.initializing);

    await _showDesktopProgress('YT-DLP is initializing...');

    try {
      if (Platform.isAndroid) {
        await _showDesktopProgress('Checking YT-DLP on Android...');
        await YouTubeProvider.updateYtDlp(throwOnFailure: true);
      } else {
        await _showDesktopProgress('Checking YT-DLP on desktop...');
        final path = await YtDlpManager.instance.ensureReady(
          notifyOnFailure: false,
        );
        if (path == null || path.isEmpty) {
          throw Exception('YT-DLP binary is unavailable.');
        }
      }

      _setState(YtDlpReadinessState.ready);
      await NotificationService.instance.showDownloadComplete(
        id: _notificationId,
        title: 'YT-DLP ready',
        body: 'You can now load songs.',
      );
    } catch (e) {
      _lastError = e.toString();
      _setState(YtDlpReadinessState.failed);
      await NotificationService.instance.showAlert(
        id: _notificationId,
        title: 'YT-DLP failed',
        body: 'Failed to initialize YT-DLP. Restart the app to retry.',
      );
      logger.e('[YT-DLP] Initialization failed', error: e);
    }
  }

  Future<void> _showDesktopProgress(String body) async {
    await NotificationService.instance.showDownloadProgress(
      id: _notificationId,
      title: 'YT-DLP',
      body: body,
      progress: 0,
      maxProgress: 0,
    );
  }

  void _setState(YtDlpReadinessState nextState) {
    if (_state == nextState) return;
    _state = nextState;
    notifyListeners();
  }
}
