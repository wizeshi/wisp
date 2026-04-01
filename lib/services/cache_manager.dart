/// Audio file cache manager with LRU-based size management
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'notification_service.dart';
import 'download_foreground_service.dart';
import '../utils/logger.dart';

/// Metadata for a cached audio file
  String _buildSafeCacheFileName(String trackId, String videoId) {
    final input = '$trackId|$videoId';
    final digest = sha1.convert(utf8.encode(input)).toString();
    return 'track_$digest.m4a';
  }
class CacheEntry {
  final String trackId;
  final String videoId;
  final String filePath;
  final int fileSize;
  final String? trackTitle;
  final String? artistName;
  final DateTime downloadDate;
  DateTime lastPlayedDate;

  CacheEntry({
    required this.trackId,
    required this.videoId,
    required this.filePath,
    required this.fileSize,
    this.trackTitle,
    this.artistName,
    required this.downloadDate,
    required this.lastPlayedDate,
  });

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'videoId': videoId,
    'filePath': filePath,
    'fileSize': fileSize,
    'trackTitle': trackTitle,
    'artistName': artistName,
    'downloadDate': downloadDate.toIso8601String(),
    'lastPlayedDate': lastPlayedDate.toIso8601String(),
  };

  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
    trackId: json['trackId'] as String,
    videoId: json['videoId'] as String,
    filePath: json['filePath'] as String,
    fileSize: json['fileSize'] as int,
    trackTitle: json['trackTitle'] as String?,
    artistName: json['artistName'] as String?,
    downloadDate: DateTime.parse(json['downloadDate'] as String),
    lastPlayedDate: DateTime.parse(json['lastPlayedDate'] as String),
  );

}

/// Download task status
enum DownloadStatus { queued, downloading, completed, failed, cancelled }

enum QueueDownloadResult {
  queued,
  alreadyCached,
  alreadyQueued,
  blockedByNetworkPolicy,
  blockedByNetworkOnlyMode,
}

/// A download task
class DownloadTask {
  final String trackId;
  final String trackTitle;
  final String artistName;
  final DateTime queuedAt;
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

/// Singleton cache manager
class AudioCacheManager extends ChangeNotifier {
  static AudioCacheManager? _instance;
  static AudioCacheManager get instance => _instance ??= AudioCacheManager._();

  AudioCacheManager._();

  String _normalizeTrackId(String trackId) {
    final trimmed = trackId.trim();
    if (!trimmed.contains(':')) return trimmed;
    final parts = trimmed.split(':');
    return parts.isNotEmpty ? parts.last : trimmed;
  }

  // Settings
  int _maxCacheSizeBytes = 750 * 1024 * 1024; // 750MB default
  int _maxConcurrentDownloads = 2;
  int _preDownloadCount = 1;
  bool _wifiOnlyDownloads = true;
  bool _autoCacheEnabled = true;
  bool _networkOnlyMode = false;

  // State
  final Map<String, CacheEntry> _cacheEntries = {};
  final Map<String, DownloadTask> _downloadQueue = {};
  final List<String> _activeDownloads = [];
  final Map<String, DateTime> _retryAfter = {};
  Directory? _cacheDirectory;
  bool _initialized = false;
  int _currentCacheSize = 0;
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

  // Getters
  int get maxCacheSizeBytes => _maxCacheSizeBytes;
  int get maxCacheSizeMB => _maxCacheSizeBytes ~/ (1024 * 1024);
  int get currentCacheSizeBytes => _currentCacheSize;
  int get currentCacheSizeMB => _currentCacheSize ~/ (1024 * 1024);
  int get cachedTrackCount => _cacheEntries.length;
  int get maxConcurrentDownloads => _maxConcurrentDownloads;
  int get preDownloadCount => _preDownloadCount;
  bool get wifiOnlyDownloads => _wifiOnlyDownloads;
  bool get autoCacheEnabled => _autoCacheEnabled;
  bool get networkOnlyMode => _networkOnlyMode;
  bool get isOnWifi => _isOnWifi;
  Map<String, DownloadTask> get downloadQueue =>
      Map.unmodifiable(_downloadQueue);
  Set<String> get cachedTrackIds => _cacheEntries.keys.toSet();

  List<CacheEntry> get downloadedTracks {
    final entries = _cacheEntries.values.toList()
      ..sort((a, b) => b.downloadDate.compareTo(a.downloadDate));
    return List.unmodifiable(entries);
  }

  List<DownloadTask> get recentActiveDownloads {
    final active = _downloadQueue.values
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

  /// Initialize the cache manager
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Get cache directory
      final appDir = await getApplicationCacheDirectory();
      _cacheDirectory = Directory('${appDir.path}/audio_cache');
      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
      }

      // Load settings
      await _loadSettings();

      // Load cache entries
      await _loadCacheEntries();

      // Calculate current cache size
      await _calculateCacheSize();

      // Setup connectivity monitoring
      _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
      final result = await _connectivity.checkConnectivity();
      _isOnWifi = _isWifiOrEthernet(result);

      _initialized = true;
      logger.i("[CacheManager] Initilizing at ${_cacheDirectory!.path}");
      logger.i(
        '[CacheManager] Initialization complete: ${_cacheEntries.length} entries, ${currentCacheSizeMB}MB used',
      );
    } catch (e) {
      logger.e('[CacheManager] Initialization error', error: e);
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> result) {
    final wasWifi = _isOnWifi;
    _isOnWifi = _isWifiOrEthernet(result);
    if (wasWifi != _isOnWifi) {
      logger.d(
        '[CacheManager] Preferred network connectivity changed (WiFi/Ethernet): ${_isOnWifi ? 'connected' : 'disconnected'}',
      );
    }
    notifyListeners();
    // Process queue if we're on WiFi/Ethernet now
    if (_isOnWifi) {
      _processDownloadQueue();
    }
  }

  /// Check if a track is cached
  bool isTrackCached(String trackId) {
    final key = _normalizeTrackId(trackId);
    return _cacheEntries.containsKey(key);
  }

  /// Get the cached file path for a track
  String? getCachedPath(String trackId) {
    if (_networkOnlyMode) {
      logger.d('[CacheManager] Cache disabled (network-only mode)');
      return null;
    }

    final key = _normalizeTrackId(trackId);
    final entry = _cacheEntries[key];
    if (entry == null) {
      logger.d('[CacheManager] Cache miss: $trackId');
      return null;
    }

    // Check if file exists
    final file = File(entry.filePath);
    if (!file.existsSync()) {
      // File missing, remove entry
      logger.w('[CacheManager] Cache entry missing file: $trackId');
      _cacheEntries.remove(key);
      _saveCacheEntries();
      return null;
    }

    logger.d('[CacheManager] Cache hit: $trackId');
    return entry.filePath;
  }

  /// Mark a track as played (updates lastPlayedDate for LRU)
  Future<void> markAsPlayed(String trackId) async {
    final key = _normalizeTrackId(trackId);
    final entry = _cacheEntries[key];
    if (entry != null) {
      entry.lastPlayedDate = DateTime.now();
      await _saveCacheEntries();
      logger.d('[CacheManager] Marked as played: $trackId');
    }
  }

  /// Queue a track for download
  ///
  /// [resolveAndGetStream] is called lazily when the download actually starts,
  /// not when queued. This prevents rate limiting when bulk downloading.
  Future<QueueDownloadResult> queueDownload({
    required String trackId,
    required String trackTitle,
    required String artistName,
    required Future<(String videoId, String streamUrl)> Function()
    resolveAndGetStream,
    Map<String, String>? requestHeaders,
  }) async {
    final key = _normalizeTrackId(trackId);
    if (!_initialized) await initialize();
    if (_networkOnlyMode) {
      logger.d('[CacheManager] Download skipped (network-only mode): $trackTitle');
      return QueueDownloadResult.blockedByNetworkOnlyMode;
    }
    if (!await _hasPreferredNetwork()) {
      logger.d(
        '[CacheManager] Download blocked by network policy at queue time: $trackTitle',
      );
      return QueueDownloadResult.blockedByNetworkPolicy;
    }
    if (isTrackCached(key)) {
      logger.d('[CacheManager] Download skipped (already cached): $trackTitle');
      return QueueDownloadResult.alreadyCached;
    }
    if (_downloadQueue.containsKey(key)) {
      logger.d('[CacheManager] Download skipped (already queued): $trackTitle');
      return QueueDownloadResult.alreadyQueued;
    }

    logger.i('[CacheManager] Queued download: $trackTitle - $artistName');
    _downloadQueue[key] = DownloadTask(
      trackId: key,
      trackTitle: trackTitle,
      artistName: artistName,
    );
    notifyListeners();
    _updateForegroundServiceProgress(force: true);

    // Store the resolve callback for later (YouTube search happens when download starts)
    _pendingDownloads[key] = _PendingDownload(
      resolveAndGetStream: resolveAndGetStream,
      requestHeaders: requestHeaders,
    );

    _processDownloadQueue();
    return QueueDownloadResult.queued;
  }

  final Map<String, _PendingDownload> _pendingDownloads = {};

  /// Process the download queue
  void _processDownloadQueue() {
    if (_wifiOnlyDownloads && !_isOnWifi) {
      logger.d('[CacheManager] Skipping downloads - not on WiFi/Ethernet');
      return;
    }

    final queuedCount = _downloadQueue.values
        .where((t) => t.status == DownloadStatus.queued)
        .length;
    if (queuedCount > 0) {
      logger.d(
        '[CacheManager] Processing queue: $queuedCount queued, ${_activeDownloads.length}/$_maxConcurrentDownloads active',
      );
    }

    // Start downloads up to max concurrent
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
      logger.d('[CacheManager] Checking network connectivity for download...');
      final result = await _connectivity.checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        if (_wifiOnlyDownloads) {
          logger.w(
            '[CacheManager] Connectivity unknown; using last known WiFi state: $_isOnWifi',
          );
          return _isOnWifi;
        }
        logger.w('[CacheManager] Connectivity unknown; allowing download.');
        return true;
      }
      if (_wifiOnlyDownloads && !_isWifiOrEthernet(result)) {
        logger.w(
          '[CacheManager] Not on WiFi/Ethernet. Skipping download due to settings.',
        );
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Start downloading a track
  Future<void> _startDownload(String trackId) async {
    final task = _downloadQueue[trackId];
    final pending = _pendingDownloads[trackId];
    if (task == null) return;
    if (pending == null) {
      logger.w('[CacheManager] Missing pending download: ${task.trackTitle}');
      task.status = DownloadStatus.failed;
      task.errorMessage = 'Missing download resolver';
      onDownloadComplete?.call(trackId, false, task.errorMessage);
      notifyListeners();
      return;
    }

    var shouldRemovePending = false;

    logger.i('[CacheManager] Starting download: ${task.trackTitle}');
    task.status = DownloadStatus.downloading;
    task.cancelToken = CancelToken();
    _activeDownloads.add(trackId);
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
        '[CacheManager] Network unavailable for ${task.trackTitle}; retrying in ${delay.inSeconds}s',
      );
      _activeDownloads.remove(trackId);
      notifyListeners();
      Future.delayed(delay, () {
        _retryAfter.remove(trackId);
        _processDownloadQueue();
      });
      await _updateForegroundService();
      return;
    }

    try {
      // Ensure space is available
      await _ensureSpace(50 * 1024 * 1024); // Assume 50MB per track max

      // Resolve video ID and get stream URL (YouTube search happens HERE, not at queue time)
      logger.d('[CacheManager] Resolving video for: ${task.trackTitle}');
      final (resolvedId, streamUrl) = await pending.resolveAndGetStream();

      // Download to file (sanitize for Windows/Unix)
      final fileName = _buildSafeCacheFileName(
        _normalizeTrackId(trackId),
        resolvedId,
      );
      final filePath = '${_cacheDirectory!.path}/$fileName';

      // Show initial notification
      final notificationId = trackId.hashCode;
      logger.d(
        '[CacheManager] Requesting initial notification (id=$notificationId)',
      );
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
        await sourceFile.copy(filePath);
        task.progress = 1.0;
        onDownloadProgress?.call(trackId, task.progress);
        notifyListeners();
        await NotificationService.instance.showDownloadProgress(
          id: notificationId,
          title: task.trackTitle,
          body: '${task.artistName} • 100%',
          progress: 100,
          maxProgress: 100,
        );
        _updateForegroundServiceProgress(force: true);
      } else {
        await _dio.download(
          streamUrl,
          filePath,
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
              onDownloadProgress?.call(trackId, task.progress);
              notifyListeners();

              // Update notification every 5%
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

      // Verify file exists and get size
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Downloaded file not found');
      }
      final fileSize = await file.length();

      // Create cache entry
      final entry = CacheEntry(
        trackId: trackId,
        videoId: resolvedId,
        filePath: filePath,
        fileSize: fileSize,
        trackTitle: task.trackTitle,
        artistName: task.artistName,
        downloadDate: DateTime.now(),
        lastPlayedDate: DateTime.now(),
      );

      _cacheEntries[trackId] = entry;
      _currentCacheSize += fileSize;

      task.status = DownloadStatus.completed;
      task.progress = 1.0;

      await _saveCacheEntries();
      onDownloadComplete?.call(trackId, true, null);
      onCacheChanged?.call();

      _updateForegroundServiceProgress(force: true);

      // Show completion notification
      logger.d(
        '[CacheManager] Requesting completion notification (id=$notificationId)',
      );
      await NotificationService.instance.showDownloadComplete(
        id: notificationId,
        title: 'Download complete',
        body: '${task.trackTitle} • ${task.artistName}',
      );

      logger.i(
        '[CacheManager] Downloaded: ${task.trackTitle} (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB)',
      );
      shouldRemovePending = true;
      _retryAfter.remove(trackId);
    } catch (e) {
      // Cancel notification on error
      final notificationId = trackId.hashCode;
      await NotificationService.instance.cancelNotification(notificationId);

      if (e is DioException && e.type == DioExceptionType.cancel) {
        task.status = DownloadStatus.cancelled;
        logger.i('[CacheManager] Download cancelled: ${task.trackTitle}');
        shouldRemovePending = true;
        _retryAfter.remove(trackId);
      } else {
        task.retryCount++;
        if (task.retryCount < 3) {
          // Retry with exponential backoff
          task.status = DownloadStatus.queued;
          task.progress = 0;
          final delay = Duration(seconds: task.retryCount * 2);
          _retryAfter[trackId] = DateTime.now().add(delay);
          logger.w(
            '[CacheManager] Retry ${task.retryCount}/3 for ${task.trackTitle} in ${delay.inSeconds}s',
          );
          Future.delayed(delay, () {
            _retryAfter.remove(trackId);
            _processDownloadQueue();
          });
        } else {
          task.status = DownloadStatus.failed;
          task.errorMessage = e.toString();
          logger.e('[CacheManager] Download failed: ${task.trackTitle}', error: e);
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
    final overallPercent = ((totalProgress / total) * 100).clamp(0, 100).toInt();
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
    final overallPercent = ((totalProgress / total) * 100).clamp(0, 100).toInt();
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

  /// Cancel a download
  void cancelDownload(String trackId) {
    final task = _downloadQueue[trackId];
    if (task != null) {
      logger.i('[CacheManager] Cancelling download: ${task.trackTitle}');
      task.cancelToken?.cancel();
      _downloadQueue.remove(trackId);
      _pendingDownloads.remove(trackId);
      _retryAfter.remove(trackId);
      _activeDownloads.remove(trackId);
      NotificationService.instance.cancelNotification(trackId.hashCode);
      notifyListeners();
      _updateForegroundServiceProgress(force: true);
      if (_activeDownloads.isEmpty) {
        DownloadForegroundService.stop();
      }
    }
  }

  /// Cancel all downloads
  void cancelAllDownloads() {
    for (final task in _downloadQueue.values) {
      task.cancelToken?.cancel();
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

  /// Check if a track is currently downloading
  bool isDownloading(String trackId) {
    final key = _normalizeTrackId(trackId);
    return _downloadQueue.containsKey(key);
  }

  /// Get download progress for a track (0.0 to 1.0, null if not downloading)
  double? getDownloadProgress(String trackId) {
    final key = _normalizeTrackId(trackId);
    final task = _downloadQueue[key];
    return task?.progress;
  }

  /// Get download status for a track
  DownloadStatus? getDownloadStatus(String trackId) {
    final key = _normalizeTrackId(trackId);
    return _downloadQueue[key]?.status;
  }

  /// Remove a track from cache
  Future<void> removeFromCache(String trackId) async {
    logger.i('[CacheManager] Manually removing track from cache: $trackId');
    await _removeEntry(trackId);
    await _calculateCacheSize();
    logger.d(
      '[CacheManager] Track removed. Cache size: ${(_currentCacheSize / (1024 * 1024)).toStringAsFixed(2)} MB / ${(_maxCacheSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
    );
    notifyListeners();
  }

  /// Update last played date for a track (for LRU ordering)
  Future<void> updateLastPlayed(String trackId) async {
    await markAsPlayed(trackId);
  }

  /// Ensure there's enough space for a new download
  Future<void> _ensureSpace(int requiredBytes) async {
    if (_currentCacheSize + requiredBytes <= _maxCacheSizeBytes) {
      return;
    }

    final sizeMB = (requiredBytes / 1024 / 1024).toStringAsFixed(1);
    final currentMB = (_currentCacheSize / 1024 / 1024).toStringAsFixed(1);
    final maxMB = (_maxCacheSizeBytes / 1024 / 1024).toStringAsFixed(0);
    logger.d(
      '[CacheManager] Need ${sizeMB}MB space (current: ${currentMB}MB / ${maxMB}MB)',
    );

    // Check if we need to free space
    while (_currentCacheSize + requiredBytes > _maxCacheSizeBytes &&
        _cacheEntries.isNotEmpty) {
      await _evictOldest();
    }
  }

  /// Evict the oldest (by last played date) cache entry
  Future<void> _evictOldest() async {
    if (_cacheEntries.isEmpty) return;

    // Find oldest entry
    CacheEntry? oldest;
    for (final entry in _cacheEntries.values) {
      if (oldest == null ||
          entry.lastPlayedDate.isBefore(oldest.lastPlayedDate)) {
        oldest = entry;
      }
    }

    if (oldest != null) {
      logger.d('[CacheManager] Evicting oldest entry: ${oldest.trackId}');
      await _removeEntry(oldest.trackId);
    }
  }

  /// Remove a cache entry
  Future<void> _removeEntry(String trackId) async {
    final key = _normalizeTrackId(trackId);
    final entry = _cacheEntries[key];
    if (entry == null) return;

    // Delete file
    try {
      final file = File(entry.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      logger.e('[CacheManager] Error deleting file', error: e);
    }

    _currentCacheSize -= entry.fileSize;
    _cacheEntries.remove(key);
    await _saveCacheEntries();
    onCacheChanged?.call();
    notifyListeners();
  }

  /// Clear all cached files
  Future<void> clearCache() async {
    // Cancel all downloads first
    cancelAllDownloads();

    // Delete all files
    for (final entry in _cacheEntries.values) {
      try {
        final file = File(entry.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        logger.e('[CacheManager] Error deleting file', error: e);
      }
    }

    _cacheEntries.clear();
    _currentCacheSize = 0;
    await _saveCacheEntries();
    onCacheChanged?.call();
    notifyListeners();
    logger.i('[CacheManager] Cache cleared');
  }

  /// Calculate total cache size
  Future<void> _calculateCacheSize() async {
    _currentCacheSize = 0;
    for (final entry in _cacheEntries.values) {
      _currentCacheSize += entry.fileSize;
    }
  }

  // Settings methods
  Future<void> setMaxCacheSize(int sizeBytes) async {
    final sizeMB = (sizeBytes / 1024 / 1024).toStringAsFixed(0);
    logger.d('[CacheManager] Max cache size changed: ${sizeMB}MB');
    _maxCacheSizeBytes = sizeBytes;
    await _saveSettings();
    // Evict if over limit
    while (_currentCacheSize > _maxCacheSizeBytes && _cacheEntries.isNotEmpty) {
      await _evictOldest();
    }
    notifyListeners();
  }

  Future<void> setMaxConcurrentDownloads(int count) async {
    logger.d('[CacheManager] Max concurrent downloads: $count');
    _maxConcurrentDownloads = count.clamp(1, 5);
    await _saveSettings();
    _processDownloadQueue();
    notifyListeners();
  }

  Future<void> setPreDownloadCount(int count) async {
    logger.d('[CacheManager] Pre-download count: $count');
    _preDownloadCount = count.clamp(0, 5);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setWifiOnlyDownloads(bool value) async {
    logger.d(
      '[CacheManager] WiFi/Ethernet-only downloads: ${value ? "enabled" : "disabled"}',
    );
    _wifiOnlyDownloads = value;
    await _saveSettings();
    if (!value || _isOnWifi) {
      _processDownloadQueue();
    }
    notifyListeners();
  }

  Future<void> setAutoCacheEnabled(bool value) async {
    logger.d('[CacheManager] Auto-cache: ${value ? 'enabled' : 'disabled'}');
    _autoCacheEnabled = value;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setNetworkOnlyMode(bool value) async {
    logger.d(
      '[CacheManager] Network-only mode: ${value ? "enabled" : "disabled"}',
    );
    _networkOnlyMode = value;
    await _saveSettings();
    if (value) {
      cancelAllDownloads();
    }
    notifyListeners();
  }

  // Persistence
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _maxCacheSizeBytes =
          prefs.getInt('cache_max_size') ?? (750 * 1024 * 1024);
      _maxConcurrentDownloads = prefs.getInt('cache_max_concurrent') ?? 2;
      _preDownloadCount = prefs.getInt('cache_pre_download') ?? 1;
      _wifiOnlyDownloads = prefs.getBool('cache_wifi_only') ?? true;
      _autoCacheEnabled = prefs.getBool('cache_auto_cache') ?? true;
      _networkOnlyMode = prefs.getBool('cache_network_only') ?? false;
    } catch (e) {
      logger.e('[CacheManager] Error loading settings', error: e);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cache_max_size', _maxCacheSizeBytes);
      await prefs.setInt('cache_max_concurrent', _maxConcurrentDownloads);
      await prefs.setInt('cache_pre_download', _preDownloadCount);
      await prefs.setBool('cache_wifi_only', _wifiOnlyDownloads);
      await prefs.setBool('cache_auto_cache', _autoCacheEnabled);
      await prefs.setBool('cache_network_only', _networkOnlyMode);
    } catch (e) {
      logger.e('[CacheManager] Error saving settings', error: e);
    }
  }

  Future<void> _loadCacheEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entriesJson = prefs.getString('cache_entries');
      if (entriesJson != null) {
        final Map<String, dynamic> entriesMap = json.decode(entriesJson);
        for (final entry in entriesMap.entries) {
          try {
            final cacheEntry = CacheEntry.fromJson(
              entry.value as Map<String, dynamic>,
            );
            // Verify file exists
            if (File(cacheEntry.filePath).existsSync()) {
              _cacheEntries[entry.key] = cacheEntry;
            }
          } catch (e) {
            logger.w('[CacheManager] Error loading entry ${entry.key}', error: e);
          }
        }
      }
    } catch (e) {
      logger.e('[CacheManager] Error loading cache entries', error: e);
    }
  }

  Future<void> _saveCacheEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entriesMap = <String, dynamic>{};
      for (final entry in _cacheEntries.entries) {
        entriesMap[entry.key] = entry.value.toJson();
      }
      await prefs.setString('cache_entries', json.encode(entriesMap));
    } catch (e) {
      logger.e('[CacheManager] Error saving cache entries', error: e);
    }
  }

  @override
  void dispose() {
    cancelAllDownloads();
    _dio.close();
    super.dispose();
  }
}

/// Helper class for pending downloads
class _PendingDownload {
  /// Returns (videoId, streamUrl) - does YouTube search + stream resolution lazily
  final Future<(String videoId, String streamUrl)> Function()
  resolveAndGetStream;
  final Map<String, String>? requestHeaders;

  _PendingDownload({
    required this.resolveAndGetStream,
    this.requestHeaders,
  });
}
