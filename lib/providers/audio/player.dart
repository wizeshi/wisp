/// Audio player provider with queue management using just_audio
/// SIMPLIFIED: Minimal state, no guard flags, use processingStateStream directly
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../models/metadata_models.dart';
import '../../services/cache_manager.dart';
import '../../services/discord_rpc_service.dart';
import '../../utils/logger.dart';
import 'youtube.dart';

enum PlaybackState { idle, loading, playing, paused, error }

enum RepeatMode { off, all, one }

class AudioPlayerProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final YouTubeProvider _youtube = YouTubeProvider();
  final Connectivity _connectivity = Connectivity();

  double _lastVolume = 1.0;
  double? _savedVolume;

  // State
  PlaybackState _state = PlaybackState.idle;
  GenericSong? _currentTrack;
  List<GenericSong> _queue = [];
  List<GenericSong> _originalQueue = [];
  int _currentIndex = -1;
  bool _shuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.off;
  bool _isOnline = true;
  String? _errorMessage;

  // Playback context
  String? _playbackContextType;
  String? _playbackContextName;
  String? _playbackContextID;
  SongSource? _playbackContextSource;

  // Subscriptions
  StreamSubscription? _positionSubscription;
  StreamSubscription? _processingStateSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _rpcTimer;
  int _rpcLastSecond = -1;
  Timer? _mprisTimer;

  static const Duration _positionNotifyInterval = Duration(milliseconds: 200);
  Duration _lastRawPosition = Duration.zero;
  Duration _lastNotifiedPosition = Duration.zero;
  int _lastPositionNotifyMs = 0;
  int _lastPositionUpdateMs = 0;

  int _trackChangeToken = 0;
  bool _isHandlingCompletion = false;

  // Getters
  PlaybackState get state => _state;
  GenericSong? get currentTrack => _currentTrack;
  List<GenericSong> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  bool get isPlaying => _state == PlaybackState.playing;
  bool get isLoading => _state == PlaybackState.loading;
  bool get isBuffering => _state == PlaybackState.loading; // Simplified
  Duration get position => _player.position;
  Duration get throttledPosition => _lastNotifiedPosition;
  Duration get interpolatedPosition => _getInterpolatedPosition();
  Duration get duration => _player.duration ?? Duration.zero;
  double get volume => _player.volume;
  bool get isOnline => _isOnline;
  String? get errorMessage => _errorMessage;
  String? get playbackContextType => _playbackContextType;
  String? get playbackContextName => _playbackContextName;
  String? get playbackContextID => _playbackContextID;
  SongSource? get playbackContextSource => _playbackContextSource;

  bool isTrackCached(String trackId) =>
      AudioCacheManager.instance.isTrackCached(trackId);

  AudioPlayerProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadQueue();
    await YouTubeProvider.loadVideoIdCache();

    // Listen ONLY to processingState for completion detection
    // This is the key simplification - we use a separate stream
    _processingStateSubscription = _player.processingStateStream.listen((
      state,
    ) {
      if (state == ProcessingState.completed) {
        _onCompleted();
      } else if (state == ProcessingState.loading ||
          state == ProcessingState.buffering) {
        _setState(PlaybackState.loading);
      } else if (state == ProcessingState.ready) {
        // Ready state - check if playing
        if (_player.playing) {
          _setState(PlaybackState.playing);
        } else if (_state != PlaybackState.idle) {
          _setState(PlaybackState.paused);
        }
      }
    });

    // Separate listener for play/pause state
    _playingSubscription = _player.playingStream.listen((playing) {
      if (_player.processingState == ProcessingState.ready) {
        _setState(playing ? PlaybackState.playing : PlaybackState.paused);
      }
    });

    // Position updates for UI + Discord RPC throttling
    _positionSubscription = _player.positionStream.listen((position) {
      _handlePositionUpdate(position);
      _handleRpcPositionTick();
    });

    // Connectivity
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      result,
    ) {
      _isOnline = !result.contains(ConnectivityResult.none);
      notifyListeners();
    });
    final result = await _connectivity.checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);

    if (_savedVolume != null) {
      final initialVolume = _savedVolume!.clamp(0.0, 1.0);
      await _player.setVolume(initialVolume);
      if (initialVolume > 0) {
        _lastVolume = initialVolume;
      }
    }

    await _prepareCurrentTrackOnStartup();

  }

  void _handleRpcPositionTick() {
    if (_currentTrack == null) return;
    final seconds = _player.position.inSeconds;
    if (!isPlaying) return;
    if (seconds != _rpcLastSecond) {
      _rpcLastSecond = seconds;
      _updateDiscordPresence();
    }
  }

  void _handlePositionUpdate(Duration position) {
    _lastRawPosition = position;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastPositionNotifyMs <
        _positionNotifyInterval.inMilliseconds) {
      return;
    }
    _lastNotifiedPosition = position;
    _lastPositionNotifyMs = nowMs;
    _lastPositionUpdateMs = nowMs;
    notifyListeners();
  }

  void _forcePositionUpdate(Duration position) {
    _lastRawPosition = position;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastNotifiedPosition = position;
    _lastPositionNotifyMs = nowMs;
    _lastPositionUpdateMs = nowMs;
    notifyListeners();
  }

  Duration _getInterpolatedPosition() {
    if (_lastPositionUpdateMs == 0) return _lastNotifiedPosition;
    if (!isPlaying || isBuffering) return _lastNotifiedPosition;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = nowMs - _lastPositionUpdateMs;
    if (elapsedMs <= 0) return _lastNotifiedPosition;

    var predicted =
        _lastNotifiedPosition + Duration(milliseconds: elapsedMs);

    if (_lastRawPosition > Duration.zero && predicted > _lastRawPosition) {
      predicted = _lastRawPosition;
    }

    final trackDuration = duration;
    if (trackDuration > Duration.zero && predicted > trackDuration) {
      predicted = trackDuration;
    }

    return predicted;
  }

  void _ensureRpcTimer() {
    if (!isPlaying || _currentTrack == null || _rpcTimer != null) return;
    _rpcTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentTrack == null) {
        _clearDiscordPresence();
        return;
      }
      _handleRpcPositionTick();
    });
  }

  void _handleMprisTick() {
    if (_currentTrack == null) return;
    if (!isPlaying) return;
    final position = _player.position;
  }

  void _ensureMprisTimer() {
    if (!isPlaying || _currentTrack == null || _mprisTimer != null) return;
    _mprisTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentTrack == null) return;
      _handleMprisTick();
    });
  }

  void _stopMprisTimer() {
    _mprisTimer?.cancel();
    _mprisTimer = null;
  }

  void _stopRpcTimer() {
    _rpcTimer?.cancel();
    _rpcTimer = null;
  }

  void _setState(PlaybackState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
      if (_currentTrack == null || newState == PlaybackState.idle) {
        _clearDiscordPresence();
        _stopMprisTimer();
      } else {
        if (isPlaying) {
          _ensureRpcTimer();
          _ensureMprisTimer();
        } else {
          _stopRpcTimer();
          _stopMprisTimer();
        }
        _updateDiscordPresence(force: true);
      }
    }
  }

  /// Handle track completion - called ONCE when processingState becomes completed
  void _onCompleted() {
    if (_isHandlingCompletion) return;
    _isHandlingCompletion = true;
    final token = _trackChangeToken;
    () async {
      logger.i('[Player] ▶ Track completed: ${_currentTrack?.title}');

      if (_repeatMode == RepeatMode.one) {
        await _player.seek(Duration.zero);
        if (token != _trackChangeToken) return;
        await _player.play();
      } else if (_queue.isNotEmpty) {
        await _advanceToNext(token: token);
      }
    }().whenComplete(() {
      _isHandlingCompletion = false;
    });
  }

  Future<void> _prepareCurrentTrackOnStartup() async {
    if (_currentTrack == null || _player.audioSource != null) return;
    try {
      final source = await _getAudioSource(_currentTrack!);
      if (source == null) return;
      await _player.setAudioSource(source);
      if (!_player.playing) {
        _setState(PlaybackState.paused);
      }
    } catch (e) {
      logger.w('[Player] Startup prepare failed', error: e);
    }
  }

  /// Advance to next track in queue
  Future<void> _advanceToNext({int? token}) async {
    int nextIndex = _currentIndex + 1;

    if (nextIndex >= _queue.length) {
      if (_repeatMode == RepeatMode.all) {
        nextIndex = 0;
      } else {
        logger.i('[Player] End of queue');
        _setState(PlaybackState.idle);
        return;
      }
    }

    await _playAtIndex(nextIndex, token: token);
  }

  /// Core method: play track at index (internal use)
  Future<void> _playAtIndex(int index, {int? token}) async {
    if (index < 0 || index >= _queue.length) return;
    final requestToken = token ?? ++_trackChangeToken;

    final track = _queue[index];
    logger.i('[Player] Playing [${index + 1}/${_queue.length}]: ${track.title}');

    _currentIndex = index;
    _currentTrack = track;
    _errorMessage = null;
    _setState(PlaybackState.loading);

    try {
      await _player.stop();
      if (requestToken != _trackChangeToken) return;

      final source = await _getAudioSource(track);
      if (requestToken != _trackChangeToken) return;
      if (source == null) {
        throw Exception('Could not get audio source');
      }

      // Load and wait for player to be ready before starting playback
      await _player.setAudioSource(source);
      if (requestToken != _trackChangeToken) return;
      
      // Ensure position is at start (prevents skip issues)
      await _player.seek(Duration.zero);
      _forcePositionUpdate(Duration.zero);
      if (requestToken != _trackChangeToken) return;
      
      // Start playback
      await _player.play();
      if (requestToken != _trackChangeToken) return;

      _ensureRpcTimer();
      _updateDiscordPresence(force: true);
      _saveQueue();
      _queueCaching(track);
    } catch (e) {
      logger.e('[Player] Error', error: e);
      _errorMessage = e.toString();
      _setState(PlaybackState.error);

      // Auto-skip on error after delay
      if (_currentIndex < _queue.length - 1) {
        await Future.delayed(const Duration(seconds: 2));
        if (_state == PlaybackState.error) {
          await _advanceToNext();
        }
      }
    }
  }

  /// Get audio source for track (cache or stream)
  Future<AudioSource?> _getAudioSource(GenericSong track) async {
    final cacheManager = AudioCacheManager.instance;

    // Try cache first
    final cachedPath = cacheManager.getCachedPath(track.id);
    if (cachedPath != null && File(cachedPath).existsSync()) {
      logger.d('[Player] 📦 From cache');
      await cacheManager.updateLastPlayed(track.id);
      return AudioSource.file(cachedPath);
    }

    if (!_isOnline) {
      throw Exception('Offline and track not cached');
    }

    // Get video ID
    String? videoId = YouTubeProvider.getCachedVideoId(track.id);
    if (videoId == null) {
      final artistNames = track.artists.map((a) => a.name).join(', ');
      final result = await _youtube.searchYouTube(artistNames, track.title, durationSecs: track.durationSecs);
      if (result == null) return null;
      videoId = result.videoId;
      YouTubeProvider.cacheVideoId(track.id, videoId);
    }

    // Get stream URL
    logger.d('[Player] 🎵 Streaming from YouTube');
    final streamUrl = await _youtube.getStreamUrl(videoId);

    final userAgent = Platform.isAndroid
        ? 'com.google.android.youtube/19.29.37 (Linux; U; Android 14) gzip'
        : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

    return AudioSource.uri(
      Uri.parse(streamUrl),
      headers: {'User-Agent': userAgent},
    );
  }

  /// Queue caching for current and next tracks
  void _queueCaching(GenericSong track) {
    final cacheManager = AudioCacheManager.instance;
    if (!cacheManager.autoCacheEnabled) return;

    // Download previous tracks for caching
    _queueTrackCache(track);

    // Pre-resolve next track's URL (don't download) to minimize skip delay
    if (_currentIndex + 1 < _queue.length) {
      _preResolveNextTrack(_queue[_currentIndex + 1]);
    }
  }

  /// Pre-resolve the next track's video ID and cache it (doesn't download)
  Future<void> _preResolveNextTrack(GenericSong track) async {
    // Check if already cached
    String? videoId = YouTubeProvider.getCachedVideoId(track.id);
    if (videoId != null) return;

    try {
      final artistNames = track.artists.map((a) => a.name).join(', ');
      final result = await _youtube.searchYouTube(artistNames, track.title, durationSecs: track.durationSecs);
      if (result == null) return;
      YouTubeProvider.cacheVideoId(track.id, result.videoId);
      logger.d('[Player] Pre-resolved next track: ${track.title}');
    } catch (e) {
      logger.w('[Player] Failed to pre-resolve next track', error: e);
    }
  }

  Future<void> _queueTrackCache(GenericSong track) async {
    final cacheManager = AudioCacheManager.instance;
    if (cacheManager.isTrackCached(track.id) 
    || cacheManager.isDownloading(track.id)) {
        return;
    }

    final artistNames = track.artists.map((a) => a.name).join(', ');
    cacheManager.queueDownload(
      trackId: track.id,
      trackTitle: track.title,
      artistName: artistNames,
      resolveAndGetStream: () async {
        String? videoId = YouTubeProvider.getCachedVideoId(track.id);
        if (videoId == null) {
          final result = await _youtube.searchYouTube(artistNames, track.title, durationSecs: track.durationSecs);
          if (result == null) throw Exception('Could not find video');
          videoId = result.videoId;
          YouTubeProvider.cacheVideoId(track.id, videoId);
        }
        final streamUrl = await _youtube.getStreamUrl(videoId);
        return (videoId, streamUrl);
      },
    );
  }


  Future<void> _updateDiscordPresence({bool force = false}) async {
    final track = _currentTrack;
    if (track == null) {
      await _clearDiscordPresence();
      return;
    }

    if (force) {
      _rpcLastSecond = _player.position.inSeconds;
    }

    await DiscordRpcService.instance.updatePresence(
      track: track,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
    );
  }

  Future<void> _clearDiscordPresence() async {
    _rpcLastSecond = -1;
    await DiscordRpcService.instance.clearPresence();
    _stopRpcTimer();
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Play a specific track
  Future<void> playTrack(GenericSong track, {bool addToQueue = true}) async {
    final token = ++_trackChangeToken;
    if (addToQueue && !_queue.any((t) => t.id == track.id)) {
      _queue.add(track);
    }
    final index = _queue.indexWhere((t) => t.id == track.id);
    if (index >= 0) {
      await _playAtIndex(index, token: token);
    } else {
      _queue.add(track);
      await _playAtIndex(_queue.length - 1, token: token);
    }
  }

  /// Set queue and optionally start playing
  Future<void> setQueue(
    List<GenericSong> tracks, {
    int startIndex = 0,
    bool play = true,
    String? contextType,
    String? contextName,
    String? contextID,
    SongSource? contextSource,
    bool shuffleEnabled = false,
    List<GenericSong>? originalQueue,
  }) async {
    final token = ++_trackChangeToken;
    _queue = List.from(tracks);
    _originalQueue = originalQueue ?? [];
    _shuffleEnabled = shuffleEnabled;
    _playbackContextType = contextType;
    _playbackContextName = contextName;
    _playbackContextID = contextID;
    _playbackContextSource = contextSource;

    if (_queue.isEmpty) {
      _currentIndex = -1;
      _currentTrack = null;
      _saveQueue();
      notifyListeners();
      return;
    }

    if (play) {
      await _playAtIndex(startIndex.clamp(0, _queue.length - 1), token: token);
    } else {
      _currentIndex = startIndex.clamp(0, _queue.length - 1);
      _currentTrack = _queue[_currentIndex];
      _saveQueue();
      notifyListeners();
    }
  }

  Future<void> play() async {
    if (_player.audioSource == null && _currentTrack != null) {
      try {
        final source = await _getAudioSource(_currentTrack!);
        if (source == null) return;
        await _player.setAudioSource(source);
      } catch (e) {
        _errorMessage = e.toString();
        _setState(PlaybackState.error);
        return;
      }
    }
    await _player.play();
    _ensureRpcTimer();
    _ensureMprisTimer();
    _updateDiscordPresence(force: true);
  }
  Future<void> pause() async {
    await _player.pause();
    _ensureRpcTimer();
    _stopMprisTimer();
    _updateDiscordPresence(force: true);
  }
  Future<void> togglePlayPause() async => isPlaying ? pause() : play();
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _forcePositionUpdate(position);
    _ensureRpcTimer();
    _ensureMprisTimer();
    _updateDiscordPresence(force: true);
  }
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    _savedVolume = volume;
    if (volume > 0) {
      _lastVolume = volume;
    }
    await _saveVolumePrefs();
    notifyListeners(); // Ensure UI updates immediately
  }

  Future<void> toggleMute() async {
    final current = _player.volume;
    if (current == 0) {
      final restore = _lastVolume <= 0 ? 1.0 : _lastVolume.clamp(0.0, 1.0);
      await setVolume(restore);
    } else {
      _lastVolume = current;
      await setVolume(0);
    }
  }

  Future<void> skipNext() async {
    if (_queue.isEmpty) return;
    final token = ++_trackChangeToken;
    await _advanceToNext(token: token);
  }

  Future<void> skipPrevious() async {
    if (_queue.isEmpty) return;
    final token = ++_trackChangeToken;
    if (position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    int prevIndex = _currentIndex - 1;
    if (prevIndex < 0) {
      prevIndex = _repeatMode == RepeatMode.all ? _queue.length - 1 : 0;
    }
    await _playAtIndex(prevIndex, token: token);
  }

  void addToQueue(GenericSong track) {
    _queue.add(track);
    _saveQueue();
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) {
      _player.stop();
      _currentTrack = null;
      _currentIndex = -1;
      _setState(PlaybackState.idle);
      _clearDiscordPresence();
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
    _queue.removeAt(index);
    _saveQueue();
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _currentTrack = null;
    _player.stop();
    _setState(PlaybackState.idle);
    _saveQueue();
    notifyListeners();
    _clearDiscordPresence();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex == _currentIndex) return;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == _currentIndex) return;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    
    if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    }
    else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
    
    _saveQueue();
    notifyListeners();
  }

  void toggleShuffle() => setShuffleEnabled(!_shuffleEnabled);

  void setShuffleEnabled(bool enabled) {
    if (_shuffleEnabled == enabled) {
      return;
    }

    _shuffleEnabled = enabled;
    if (_shuffleEnabled && _queue.length > 1) {
      _originalQueue = List.from(_queue);
      final current = _currentIndex >= 0 ? _queue[_currentIndex] : null;
      final others = List<GenericSong>.from(_queue);
      if (current != null) others.removeAt(_currentIndex);
      others.shuffle();
      _queue = current != null ? [current, ...others] : others;
      _currentIndex = current != null ? 0 : _currentIndex;
    } else if (!_shuffleEnabled && _originalQueue.isNotEmpty) {
      final current = _currentIndex >= 0 ? _queue[_currentIndex] : null;
      _queue = List.from(_originalQueue);
      _currentIndex = current != null
          ? _queue.indexWhere((t) => t.id == current.id)
          : 0;
      if (_currentIndex < 0) _currentIndex = 0;
      _originalQueue = [];
    }
    _saveQueue();
    notifyListeners();
  }

  void toggleRepeat() {
    final next =
        RepeatMode.values[(_repeatMode.index + 1) % RepeatMode.values.length];
    setRepeatMode(next);
  }

  void setRepeatMode(RepeatMode mode) {
    if (_repeatMode == mode) {
      return;
    }
    _repeatMode = mode;
    _saveQueue();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DOWNLOADS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> downloadTrack(GenericSong track) async {
    final artistNames = track.artists.map((a) => a.name).join(', ');

    // Pass a callback that resolves video ID lazily when download starts
    // This prevents rate limiting when bulk downloading
    await AudioCacheManager.instance.queueDownload(
      trackId: track.id,
      trackTitle: track.title,
      artistName: artistNames,
      resolveAndGetStream: () async {
        // Check cache first
        String? videoId = YouTubeProvider.getCachedVideoId(track.id);
        if (videoId == null) {
          final result = await _youtube.searchYouTube(artistNames, track.title, durationSecs: track.durationSecs);
          if (result == null) throw Exception('Could not find video');
          videoId = result.videoId;
          YouTubeProvider.cacheVideoId(track.id, videoId);
        }
        final streamUrl = await _youtube.getStreamUrl(videoId);
        return (videoId, streamUrl);
      },
    );
  }

  Future<void> downloadTracks(List<GenericSong> tracks) async {
    for (final track in tracks) {
      try {
        await downloadTrack(track);
      } catch (_) {}
    }
  }

  void cancelDownload(String trackId) =>
      AudioCacheManager.instance.cancelDownload(trackId);
  Future<void> removeFromCache(String trackId) async =>
      AudioCacheManager.instance.removeFromCache(trackId);
  double? getDownloadProgress(String trackId) =>
      AudioCacheManager.instance.getDownloadProgress(trackId);
  bool isTrackDownloading(String trackId) =>
      AudioCacheManager.instance.isDownloading(trackId);

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('audio_queue');
      if (queueJson != null) {
        final list = json.decode(queueJson) as List;
        _queue = list.map((item) => GenericSong.fromJson(item)).toList();
      }
      final originalQueueJson = prefs.getString('audio_original_queue');
      if (originalQueueJson != null) {
        final list = json.decode(originalQueueJson) as List;
        _originalQueue = list.map((item) => GenericSong.fromJson(item)).toList();
      }
      _currentIndex = prefs.getInt('current_index') ?? -1;
      _shuffleEnabled = prefs.getBool('shuffle_enabled') ?? false;
      final repeatStr = prefs.getString('repeat_mode');
      if (repeatStr != null) {
        _repeatMode = RepeatMode.values.firstWhere(
          (e) => e.toString() == repeatStr,
          orElse: () => RepeatMode.off,
        );
      }
      _savedVolume = prefs.getDouble('player_volume');
      final savedLastVolume = prefs.getDouble('player_last_volume');
      if (savedLastVolume != null) {
        _lastVolume = savedLastVolume;
      }
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        _currentTrack = _queue[_currentIndex];
      }
      notifyListeners();
    } catch (e) {
      logger.e('[Player] Load queue error', error: e);
    }
  }

  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'audio_queue',
        json.encode(_queue.map((t) => t.toJson()).toList()),
      );
      await prefs.setString(
        'audio_original_queue',
        json.encode(_originalQueue.map((t) => t.toJson()).toList()),
      );
      await prefs.setInt('current_index', _currentIndex);
      await prefs.setBool('shuffle_enabled', _shuffleEnabled);
      await prefs.setString('repeat_mode', _repeatMode.toString());
    } catch (e) {
      logger.e('[Player] Save queue error', error: e);
    }
  }

  Future<void> _saveVolumePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('player_volume', _player.volume);
      await prefs.setDouble('player_last_volume', _lastVolume);
    } catch (e) {
      logger.e('[Player] Save volume error', error: e);
    }
  }

  @override
  void dispose() {
    _saveVolumePrefs();
    _positionSubscription?.cancel();
    _processingStateSubscription?.cancel();
    _playingSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _stopRpcTimer();
    DiscordRpcService.instance.dispose();
    _player.dispose();
    _youtube.dispose();
    super.dispose();
  }
}

