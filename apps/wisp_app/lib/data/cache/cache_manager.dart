// Copyright © 2026 wizeshi

/// Audio file cache and download queue manager
library;

import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/audio/audio_storage_service.dart';
import 'package:wisp/data/cache/audio/track_download_state_coordinator.dart';
import 'package:wisp/data/cache/models/audio_cache_entry.dart';
import 'package:wisp/services/notifications/download_foreground_service.dart';
import 'package:wisp/services/notifications/notification_service.dart';

export 'package:wisp/data/cache/audio/audio_storage_service.dart';
export 'package:wisp/data/cache/audio/track_download_state_coordinator.dart';
export 'package:wisp/data/cache/models/audio_cache_entry.dart';

/// Download task status
enum DownloadStatus { queued, downloading, completed, failed, cancelled }

enum QueueDownloadResult {
  queued,
  alreadyCached,
  alreadyQueued,
  blockedByNetworkPolicy,
  blockedByNetworkOnlyMode,
  storageLimitReached,
}

/// A download task
class DownloadTask {
  final String trackId;
  final String trackTitle;
  final String artistName;
  final DateTime queuedAt;
  final bool isUserDownload;
  DownloadStatus status;
  double progress;
  String? errorMessage;
  int retryCount;
  CancelToken? cancelToken;

  DownloadTask({
    required this.trackId,
    required this.trackTitle,
    required this.artistName,
    DateTime? queuedAt,
    this.isUserDownload = true,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.errorMessage,
    this.retryCount = 0,
    this.cancelToken,
  }) : queuedAt = queuedAt ?? DateTime.now();
}

/// Callback types for download events
typedef DownloadProgressCallback =
    void Function(String trackId, double progress);
typedef DownloadCompleteCallback =
    void Function(String trackId, bool success, String? error);
typedef CacheChangedCallback = void Function();

/// Singleton cache and download manager
class AudioCacheManager extends ChangeNotifier {
  static AudioCacheManager? _instance;
  static AudioCacheManager get instance => _instance ??= AudioCacheManager._();

  AudioCacheManager._() {
    _storage.addListener(_handleStorageChanged);
  }

  final AudioStorageService _storage = AudioStorageService.instance;
  final TrackDownloadStateCoordinator _coordinator =
      TrackDownloadStateCoordinator();

  // Settings
  int _maxConcurrentDownloads = 2;
  int _preDownloadCount = 1;
  bool _wifiOnlyDownloads = true;
  bool _autoCacheEnabled = true;
  bool _networkOnlyMode = false;

  // Queue state
  final Map<String, DownloadTask> _downloadQueue = {};
  final List<String> _activeDownloads = [];
  final Map<String, DateTime> _retryAfter = {};
  final Map<String, _PendingDownload> _pendingDownloads = {};
  bool _initialized = false;
  int _lastOverallProgressPercent = -1;

  // Dio instance for downloads
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  // Connectivity
  final Connectivity _connectivity = Connectivity();
  bool _isOnWifi = false;

  bool _isWifiOrEthernet(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  // Callbacks
  DownloadProgressCallback? onDownloadProgress;
  DownloadCompleteCallback? onDownloadComplete;
  CacheChangedCallback? onCacheChanged;

  void _handleStorageChanged() {
    onCacheChanged?.call();
    notifyListeners();
  }

  // Coordinator accessor for granular per-track watchers
  TrackDownloadStateCoordinator get coordinator => _coordinator;

  /// Returns a granular `ValueListenable` scoped to [trackId].
  ///
  /// UI components should listen to this rather than listening to the entire
  /// [AudioCacheManager] to avoid unnecessary global rebuilds.
  ValueListenable<TrackDownloadProgress> watchTrack(String trackId) {
    return _coordinator.watch(trackId, isCached: isTrackCached(trackId));
  }

  // Storage getters delegated to AudioStorageService
  AudioStorageService get storage => _storage;
  Directory? get cacheDirectory => _storage.cacheDirectory;
  int get maxCacheSizeBytes => _storage.maxCacheSizeBytes;
  int get maxCacheSizeMB => _storage.maxCacheSizeMB;
  int get currentCacheSizeBytes => _storage.totalCacheSizeBytes;
  int get currentCacheSizeMB => _storage.totalCacheSizeMB;
  int get userDownloadsSizeBytes => _storage.userDownloadsSizeBytes;
  int get userDownloadsSizeMB => _storage.userDownloadsSizeMB;
  int get autoCacheSizeBytes => _storage.autoCacheSizeBytes;
  int get autoCacheSizeMB => _storage.autoCacheSizeMB;
  int get cachedTrackCount => _storage.cachedTrackCount;
  int get userDownloadCount => _storage.userDownloadCount;
  int get autoCacheCount => _storage.autoCacheCount;
  StorageStatus get storageStatus => _storage.storageStatus;
  bool get isStorageFull => _storage.isStorageFull;
  Set<String> get cachedTrackIds => _storage.cachedTrackIds;

  List<AudioCacheEntry> get downloadedTracks => _storage.userDownloads;

  int get maxConcurrentDownloads => _maxConcurrentDownloads;
  int get preDownloadCount => _preDownloadCount;
  bool get wifiOnlyDownloads => _wifiOnlyDownloads;
  bool get autoCacheEnabled => _autoCacheEnabled;
  bool get networkOnlyMode => _networkOnlyMode;
  bool get isOnWifi => _isOnWifi;

  Map<String, DownloadTask> get downloadQueue =>
      Map.unmodifiable(_downloadQueue);

  List<DownloadTask> get recentActiveDownloads {
    final active =
        _downloadQueue.values
            .where(
              (task) =>
                  task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.queued,
            )
            .toList()
          ..sort((a, b) {
            final rankA = a.status == DownloadStatus.downloading ? 0 : 1;
            final rankB = b.status == DownloadStatus.downloading ? 0 : 1;
            if (rankA != rankB) {
              return rankA.compareTo(rankB);
            }
            return b.queuedAt.compareTo(a.queuedAt);
          });
    return List.unmodifiable(active);
  }

  String _normalizeTrackId(String trackId) =>
      _storage.normalizeTrackId(trackId);

  /// Initialize the cache manager and storage service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _storage.initialize();
      await _loadSettings();

      _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
      final result = await _connectivity.checkConnectivity();
      _isOnWifi = _isWifiOrEthernet(result);

      _initialized = true;
      logger.i(
        '[AudioCacheManager] Initialized: ${_storage.cachedTrackCount} tracks (${_storage.totalCacheSizeMB}MB used)',
      );
      notifyListeners();
    } catch (e) {
      logger.e('[AudioCacheManager] Initialization error', error: e);
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> result) {
    final wasWifi = _isOnWifi;
    _isOnWifi = _isWifiOrEthernet(result);
    if (wasWifi != _isOnWifi) {
      logger.d(
        '[AudioCacheManager] Preferred network connectivity changed (WiFi/Ethernet): ${_isOnWifi ? 'connected' : 'disconnected'}',
      );
    }
    notifyListeners();
    if (_isOnWifi) {
      _processDownloadQueue();
    }
  }

  bool isTrackCached(String trackId) => _storage.isTrackCached(trackId);

  bool isTrackUserDownload(String trackId) =>
      _storage.isTrackUserDownload(trackId);

  String? getCachedPath(String trackId) {
    if (_networkOnlyMode) {
      logger.d('[AudioCacheManager] Cache disabled (network-only mode)');
      return null;
    }
    return _storage.getCachedPath(trackId);
  }

  Future<void> markAsPlayed(String trackId) =>
      _storage.updateLastPlayed(trackId);

  Future<void> updateLastPlayed(String trackId) =>
      _storage.updateLastPlayed(trackId);

  /// Queue a track for download.
  ///
  /// Set [isUserDownload] to true (default) for explicit user downloads,
  /// or false for transient auto-cache during streaming.
  Future<QueueDownloadResult> queueDownload({
    required String trackId,
    required String trackTitle,
    required String artistName,
    required Future<(String videoId, String streamUrl)> Function()
    resolveAndGetStream,
    Map<String, String>? requestHeaders,
    bool isUserDownload = true,
  }) async {
    final key = _normalizeTrackId(trackId);
    if (!_initialized) await initialize();

    if (_networkOnlyMode) {
      logger.d(
        '[AudioCacheManager] Download skipped (network-only mode): $trackTitle',
      );
      return QueueDownloadResult.blockedByNetworkOnlyMode;
    }
    if (!await _hasPreferredNetwork()) {
      logger.d(
        '[AudioCacheManager] Download blocked by network policy at queue time: $trackTitle',
      );
      return QueueDownloadResult.blockedByNetworkPolicy;
    }

    if (isTrackCached(key)) {
      if (isUserDownload && !isTrackUserDownload(key)) {
        await _storage.promoteToUserDownload(key);
      }
      logger.d(
        '[AudioCacheManager] Download skipped (already cached): $trackTitle',
      );
      return QueueDownloadResult.alreadyCached;
    }

    if (_downloadQueue.containsKey(key)) {
      logger.d(
        '[AudioCacheManager] Download skipped (already queued): $trackTitle',
      );
      return QueueDownloadResult.alreadyQueued;
    }

    // If storage is full and this is auto-cache, pause auto-caching
    if (!isUserDownload && _storage.isStorageFull) {
      logger.w(
        '[AudioCacheManager] Auto-cache paused: Storage quota reached and no auto-cache entries left to prune.',
      );
      return QueueDownloadResult.storageLimitReached;
    }

    logger.i(
      '[AudioCacheManager] Queued download: $trackTitle - $artistName (userDownload: $isUserDownload)',
    );
    _downloadQueue[key] = DownloadTask(
      trackId: key,
      trackTitle: trackTitle,
      artistName: artistName,
      isUserDownload: isUserDownload,
    );

    _coordinator.setQueued(key);
    notifyListeners();
    _updateForegroundServiceProgress(force: true);

    _pendingDownloads[key] = _PendingDownload(
      resolveAndGetStream: resolveAndGetStream,
      requestHeaders: requestHeaders,
    );

    _processDownloadQueue();
    return QueueDownloadResult.queued;
  }

  void _processDownloadQueue() {
    if (_wifiOnlyDownloads && !_isOnWifi) {
      logger.d(
        '[AudioCacheManager] Skipping downloads - not on WiFi/Ethernet',
      );
      return;
    }

    final queuedCount = _downloadQueue.values
        .where((t) => t.status == DownloadStatus.queued)
        .length;
    if (queuedCount > 0) {
      logger.d(
        '[AudioCacheManager] Processing queue: $queuedCount queued, ${_activeDownloads.length}/$_maxConcurrentDownloads active',
      );
    }

    while (_activeDownloads.length < _maxConcurrentDownloads) {
      final now = DateTime.now();
      final nextTask = _downloadQueue.entries
          .where((e) => e.value.status == DownloadStatus.queued)
          .where((e) {
            final retryAt = _retryAfter[e.key];
            return retryAt == null || !retryAt.isAfter(now);
          })
          .map((e) => e.key)
          .firstOrNull;

      if (nextTask == null) break;

      _startDownload(nextTask);
    }
  }

  Future<bool> _hasPreferredNetwork() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        if (_wifiOnlyDownloads) return _isOnWifi;
        return true;
      }
      if (_wifiOnlyDownloads && !_isWifiOrEthernet(result)) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startDownload(String trackId) async {
    final task = _downloadQueue[trackId];
    final pending = _pendingDownloads[trackId];
    if (task == null) return;
    if (pending == null) {
      logger.w(
        '[AudioCacheManager] Missing pending download: ${task.trackTitle}',
      );
      task.status = DownloadStatus.failed;
      task.errorMessage = 'Missing download resolver';
      _coordinator.setFailed(trackId, task.errorMessage);
      onDownloadComplete?.call(trackId, false, task.errorMessage);
      notifyListeners();
      return;
    }

    var shouldRemovePending = false;

    logger.i('[AudioCacheManager] Starting download: ${task.trackTitle}');
    task.status = DownloadStatus.downloading;
    task.cancelToken = CancelToken();
    _activeDownloads.add(trackId);
    _coordinator.setProgress(trackId, 0.0);
    notifyListeners();

    await DownloadForegroundService.start(
      title: 'Downloading audio',
      text: _formatOverallProgressText(),
    );

    if (!await _hasPreferredNetwork()) {
      task.status = DownloadStatus.queued;
      task.progress = 0;
      final delay = const Duration(seconds: 10);
      _retryAfter[trackId] = DateTime.now().add(delay);
      logger.w(
        '[AudioCacheManager] Network unavailable for ${task.trackTitle}; retrying in ${delay.inSeconds}s',
      );
      _activeDownloads.remove(trackId);
      _coordinator.setQueued(trackId);
      notifyListeners();
      Future.delayed(delay, () {
        _retryAfter.remove(trackId);
        _processDownloadQueue();
      });
      await _updateForegroundService();
      return;
    }

    String? tempPartPath;

    try {
      // Resolve video ID and get stream URL
      logger.d('[AudioCacheManager] Resolving video for: ${task.trackTitle}');
      final (resolvedId, streamUrl) = await pending.resolveAndGetStream();

      final fileName = _storage.buildSafeCacheFileName(
        _normalizeTrackId(trackId),
        resolvedId,
      );
      final finalFilePath = '${_storage.cacheDirectory!.path}/$fileName';
      tempPartPath = '$finalFilePath.part';

      final notificationId = trackId.hashCode;
      await NotificationService.instance.showDownloadProgress(
        id: notificationId,
        title: task.trackTitle,
        body: '${task.artistName} • 0%',
        progress: 0,
        maxProgress: 100,
      );

      final sourceUri = Uri.tryParse(streamUrl);
      final isLocalSource = sourceUri != null && sourceUri.scheme == 'file';

      if (isLocalSource) {
        final localPath = sourceUri.toFilePath();
        final sourceFile = File(localPath);
        if (!await sourceFile.exists()) {
          throw Exception('Resolved local source file not found');
        }
        await sourceFile.copy(tempPartPath);
        task.progress = 1.0;
        _coordinator.setProgress(trackId, 1.0);
        onDownloadProgress?.call(trackId, 1.0);
      } else {
        await _dio.download(
          streamUrl,
          tempPartPath,
          cancelToken: task.cancelToken,
          options: Options(
            headers: {
              ...?pending.requestHeaders,
              'User-Agent': Platform.isAndroid
                  ? 'com.google.android.youtube/19.29.37 (Linux; U; Android 14) gzip'
                  : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          ),
          onReceiveProgress: (received, total) {
            if (total > 0) {
              task.progress = received / total;
              // Update ONLY the granular track coordinator so visible track rows don't storm
              _coordinator.setProgress(trackId, task.progress);
              onDownloadProgress?.call(trackId, task.progress);

              // Update OS notification every 5%
              final progressPercent = (task.progress * 100).toInt();
              if (progressPercent % 5 == 0) {
                NotificationService.instance.showDownloadProgress(
                  id: notificationId,
                  title: task.trackTitle,
                  body: '${task.artistName} • $progressPercent%',
                  progress: progressPercent,
                  maxProgress: 100,
                );
                _updateForegroundServiceProgress();
              }
            }
          },
        );
      }

      // Atomically register completed file into storage
      final entry = await _storage.registerCompletedDownload(
        trackId: trackId,
        videoId: resolvedId,
        tempPartPath: tempPartPath,
        finalFilePath: finalFilePath,
        trackTitle: task.trackTitle,
        artistName: task.artistName,
        isUserDownload: task.isUserDownload,
      );

      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      _coordinator.setCompleted(trackId);

      onDownloadComplete?.call(trackId, true, null);
      onCacheChanged?.call();
      notifyListeners();

      _updateForegroundServiceProgress(force: true);

      await NotificationService.instance.showDownloadComplete(
        id: notificationId,
        title: 'Download complete',
        body: '${task.trackTitle} • ${task.artistName}',
      );

      logger.i(
        '[AudioCacheManager] Downloaded: ${task.trackTitle} (${(entry.fileSize / 1024 / 1024).toStringAsFixed(1)}MB)',
      );
      shouldRemovePending = true;
      _retryAfter.remove(trackId);
    } catch (e) {
      final notificationId = trackId.hashCode;
      await NotificationService.instance.cancelNotification(notificationId);

      // Clean up partial file on failure
      if (tempPartPath != null) {
        try {
          final tempFile = File(tempPartPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }

      if (e is DioException && e.type == DioExceptionType.cancel) {
        task.status = DownloadStatus.cancelled;
        _coordinator.setRemoved(trackId);
        logger.i('[AudioCacheManager] Download cancelled: ${task.trackTitle}');
        shouldRemovePending = true;
        _retryAfter.remove(trackId);
      } else {
        task.retryCount++;
        if (task.retryCount < 3) {
          task.status = DownloadStatus.queued;
          task.progress = 0;
          _coordinator.setQueued(trackId);
          final delay = Duration(seconds: task.retryCount * 2);
          _retryAfter[trackId] = DateTime.now().add(delay);
          logger.w(
            '[AudioCacheManager] Retry ${task.retryCount}/3 for ${task.trackTitle} in ${delay.inSeconds}s',
          );
          Future.delayed(delay, () {
            _retryAfter.remove(trackId);
            _processDownloadQueue();
          });
        } else {
          task.status = DownloadStatus.failed;
          task.errorMessage = e.toString();
          _coordinator.setFailed(trackId, e.toString());
          logger.e(
            '[AudioCacheManager] Download failed: ${task.trackTitle}',
            error: e,
          );
          onDownloadComplete?.call(trackId, false, e.toString());
          shouldRemovePending = true;
          _retryAfter.remove(trackId);
        }
      }
    } finally {
      _activeDownloads.remove(trackId);
      if (shouldRemovePending) {
        _pendingDownloads.remove(trackId);
      }
      notifyListeners();
      _processDownloadQueue();
      await _updateForegroundService();
    }
  }

  Future<void> _updateForegroundService() async {
    if (_activeDownloads.isNotEmpty) return;
    await DownloadForegroundService.stop();
  }

  String _formatOverallProgressText() {
    final total = _downloadQueue.length;
    if (total == 0) return 'Preparing downloads…';
    final completed = _downloadQueue.values
        .where((task) => task.status == DownloadStatus.completed)
        .length;
    final totalProgress = _downloadQueue.values.fold<double>(
      0,
      (sum, task) => sum + task.progress.clamp(0.0, 1.0),
    );
    final overallPercent =
        ((totalProgress / total) * 100).clamp(0, 100).toInt();
    final activeCount = _activeDownloads.length;
    return '$activeCount active • $completed/$total ($overallPercent%)';
  }

  Future<void> _updateForegroundServiceProgress({bool force = false}) async {
    if (_downloadQueue.isEmpty) {
      if (!Platform.isAndroid) {
        await NotificationService.instance.cancelDownloadGroupSummary();
      }
      return;
    }
    final total = _downloadQueue.length;
    final totalProgress = _downloadQueue.values.fold<double>(
      0,
      (sum, task) => sum + task.progress.clamp(0.0, 1.0),
    );
    final overallPercent =
        ((totalProgress / total) * 100).clamp(0, 100).toInt();
    if (!force && overallPercent == _lastOverallProgressPercent) return;
    _lastOverallProgressPercent = overallPercent;

    await DownloadForegroundService.start(
      title: 'Downloading audio',
      text: _formatOverallProgressText(),
    );

    if (!Platform.isAndroid) {
      await NotificationService.instance.showDownloadGroupSummary(
        title: 'Downloads',
        body: _formatOverallProgressText(),
        ongoing: _activeDownloads.isNotEmpty,
      );
    }
  }

  void cancelDownload(String trackId) {
    final key = _normalizeTrackId(trackId);
    final task = _downloadQueue[key];
    if (task != null) {
      logger.i('[AudioCacheManager] Cancelling download: ${task.trackTitle}');
      task.cancelToken?.cancel();
      _downloadQueue.remove(key);
      _pendingDownloads.remove(key);
      _retryAfter.remove(key);
      _activeDownloads.remove(key);
      _coordinator.setRemoved(key);
      NotificationService.instance.cancelNotification(key.hashCode);
      notifyListeners();
      _updateForegroundServiceProgress(force: true);
      if (_activeDownloads.isEmpty) {
        DownloadForegroundService.stop();
      }
    }
  }

  void cancelAllDownloads() {
    for (final task in _downloadQueue.values) {
      task.cancelToken?.cancel();
      _coordinator.setRemoved(task.trackId);
      NotificationService.instance.cancelNotification(task.trackId.hashCode);
    }
    _downloadQueue.clear();
    _pendingDownloads.clear();
    _retryAfter.clear();
    _activeDownloads.clear();
    notifyListeners();
    DownloadForegroundService.stop();
    NotificationService.instance.cancelDownloadGroupSummary();
  }

  bool isDownloading(String trackId) {
    final key = _normalizeTrackId(trackId);
    return _downloadQueue.containsKey(key);
  }

  double? getDownloadProgress(String trackId) {
    final key = _normalizeTrackId(trackId);
    return _downloadQueue[key]?.progress;
  }

  DownloadStatus? getDownloadStatus(String trackId) {
    final key = _normalizeTrackId(trackId);
    return _downloadQueue[key]?.status;
  }

  Future<void> removeFromCache(String trackId) async {
    final key = _normalizeTrackId(trackId);
    await _storage.removeEntry(key);
    _coordinator.setRemoved(key);
    notifyListeners();
  }

  /// Clear all cache entries
  Future<void> clearCache() async {
    cancelAllDownloads();
    await _storage.clearAll();
    notifyListeners();
  }

  /// Clear only auto-cached entries
  Future<void> clearAutoCache() async {
    await _storage.clearAutoCache();
    notifyListeners();
  }

  /// Clear only user downloads
  Future<void> clearUserDownloads() async {
    await _storage.clearUserDownloads();
    notifyListeners();
  }

  // Settings
  Future<void> setMaxCacheSize(int sizeBytes) async {
    await _storage.setMaxCacheSizeBytes(sizeBytes);
    notifyListeners();
  }

  Future<void> setMaxConcurrentDownloads(int count) async {
    _maxConcurrentDownloads = count.clamp(1, 5);
    await _saveSettings();
    _processDownloadQueue();
    notifyListeners();
  }

  Future<void> setPreDownloadCount(int count) async {
    _preDownloadCount = count.clamp(0, 5);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setWifiOnlyDownloads(bool value) async {
    _wifiOnlyDownloads = value;
    await _saveSettings();
    if (!value || _isOnWifi) {
      _processDownloadQueue();
    }
    notifyListeners();
  }

  Future<void> setAutoCacheEnabled(bool value) async {
    _autoCacheEnabled = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setNetworkOnlyMode(bool value) async {
    _networkOnlyMode = value;
    await _saveSettings();
    if (value) {
      cancelAllDownloads();
    }
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _maxConcurrentDownloads = prefs.getInt('cache_max_concurrent') ?? 2;
      _preDownloadCount = prefs.getInt('cache_pre_download') ?? 1;
      _wifiOnlyDownloads = prefs.getBool('cache_wifi_only') ?? true;
      _autoCacheEnabled = prefs.getBool('cache_auto_cache') ?? true;
      _networkOnlyMode = prefs.getBool('cache_network_only') ?? false;
    } catch (e) {
      logger.e('[AudioCacheManager] Error loading settings', error: e);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cache_max_concurrent', _maxConcurrentDownloads);
      await prefs.setInt('cache_pre_download', _preDownloadCount);
      await prefs.setBool('cache_wifi_only', _wifiOnlyDownloads);
      await prefs.setBool('cache_auto_cache', _autoCacheEnabled);
      await prefs.setBool('cache_network_only', _networkOnlyMode);
    } catch (e) {
      logger.e('[AudioCacheManager] Error saving settings', error: e);
    }
  }

  @override
  void dispose() {
    _storage.removeListener(_handleStorageChanged);
    _coordinator.dispose();
    cancelAllDownloads();
    _dio.close();
    super.dispose();
  }
}

class _PendingDownload {
  final Future<(String videoId, String streamUrl)> Function()
  resolveAndGetStream;
  final Map<String, String>? requestHeaders;

  _PendingDownload({required this.resolveAndGetStream, this.requestHeaders});
}
