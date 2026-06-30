/// Background-capable audio handler with queue management.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/metadata_models.dart';
import '../services/cache_manager.dart';
import '../services/discord_rpc_service.dart';
import '../utils/logger.dart';
import '../providers/audio/youtube.dart';
import '../providers/audio/spotify_audio.dart';
import '../providers/preferences/preferences_provider.dart';
import '../services/connect/connect_models.dart';
import '../services/spotify/spotify_audio_decryptor.dart';
import '../services/spotify/spotify_decrypt_streaming_proxy.dart';
import '../services/ytdlp_readiness_coordinator.dart';

enum PlaybackState { idle, loading, playing, paused, error }

enum RepeatMode { off, all, one }

class _StreamUrlCacheEntry {
  final String url;
  final DateTime expiresAt;

  _StreamUrlCacheEntry({required this.url, required this.expiresAt});

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class WispAudioHandler extends audio_service.BaseAudioHandler
    with ChangeNotifier {
  final AudioPlayer _primaryPlayer = AudioPlayer();
  final AudioPlayer _secondaryPlayer = AudioPlayer();
  final YouTubeProvider _youtube = YouTubeProvider();
  final SpotifyAudioProvider _spotifyAudio = SpotifyAudioProvider();
  final SpotifyAudioDecryptor _spotifyDecryptor = const SpotifyAudioDecryptor();
  final Connectivity _connectivity = Connectivity();

  bool _useSecondaryAsActivePlayer = false;

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
  bool _gaplessPlaybackEnabled = false;
  bool _crossfadeEnabled = false;
  double _crossfadeDurationSeconds = 3.0;

  // Playback context
  String? _playbackContextType;
  String? _playbackContextName;
  String? _playbackContextID;
  SongSource? _playbackContextSource;

  // Subscriptions
  StreamSubscription? _positionSubscription;
  StreamSubscription? _processingStateSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription? _currentIndexSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _rpcTimer;
  Timer? _crossfadeTimer;
  int _rpcLastSecond = -1;
  Timer? _mprisTimer;

  static const Duration _positionNotifyInterval = Duration(milliseconds: 200);
  static const Duration _streamUrlTtl = Duration(minutes: 15);
  Duration _lastRawPosition = Duration.zero;
  Duration _lastNotifiedPosition = Duration.zero;
  int _lastPositionNotifyMs = 0;
  int _lastPositionUpdateMs = 0;
  int _lastMediaPositionMs = -1;
  int _lastMediaUpdateMs = 0;
  Duration? _lastKnownDuration;

  int _trackChangeToken = 0;
  bool _isHandlingCompletion = false;
  bool _isTrackTransitioning = false;
  bool _crossfadeFadeOutActive = false;
  bool _crossfadeFadeInActive = false;
  bool _isCrossfading = false;
  double _crossfadeTargetVolume = 1.0;
  int _crossfadePreloadGeneration = 0;
  int? _preloadedNextIndex;
  GenericSong? _preloadedNextTrack;
  String? _inactivePreloadTrackId;
  static const int _prefetchWindowSize = 5;
  int _prefetchGeneration = 0;
  final Map<String, AudioSource> _prefetchedAudioSources = {};
  final Map<String, Future<AudioSource?>> _prefetchSourceTasks = {};
  final Map<String, _StreamUrlCacheEntry> _streamUrlCache = {};

  // Handoff state: true when this device is the host (requesting) device in a handoff link
  bool _isHandoffHost = false;

  // Getters
  PlaybackState get state => _state;
  GenericSong? get currentTrack => _currentTrack;
  List<GenericSong> get queueTracks => List.unmodifiable(_queue);
  List<GenericSong> get originalQueueTracks =>
      List.unmodifiable(_originalQueue);
  int get currentIndex => _currentIndex;
  int get trackChangeToken => _trackChangeToken;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  bool get isPlaying => _state == PlaybackState.playing;
  bool get isLoading => _state == PlaybackState.loading;
  bool get isBuffering => _state == PlaybackState.loading;
  bool get isTrackTransitioning => _isTrackTransitioning;
  bool get gaplessPlaybackEnabled => _gaplessPlaybackEnabled;
  bool get crossfadeEnabled => _crossfadeEnabled;
  double get crossfadeDurationSeconds => _crossfadeDurationSeconds;
    bool get _playlistPlaybackEnabled =>
      _gaplessPlaybackEnabled || _crossfadeEnabled;
    AudioPlayer get _player =>
      _useSecondaryAsActivePlayer ? _secondaryPlayer : _primaryPlayer;
    AudioPlayer get _inactivePlayer =>
      _useSecondaryAsActivePlayer ? _primaryPlayer : _secondaryPlayer;
    Duration get position => _player.position;
  Duration get throttledPosition => _lastNotifiedPosition;
  Duration get interpolatedPosition => _getInterpolatedPosition();
  Duration get duration => _isHandoffHost
      ? _lastKnownDuration ?? _player.duration ?? Duration.zero
      : _player.duration ?? _lastKnownDuration ?? Duration.zero;
  double get volume => _player.volume;
  double get userVolume => _savedVolume ?? _lastVolume;
  bool get isOnline => _isOnline;
  String? get errorMessage => _errorMessage;
  String? get playbackContextType => _playbackContextType;
  String? get playbackContextName => _playbackContextName;
  String? get playbackContextID => _playbackContextID;
  SongSource? get playbackContextSource => _playbackContextSource;

  ConnectPlaybackSnapshot buildConnectSnapshot() {
    return ConnectPlaybackSnapshot(
      queue: List<GenericSong>.from(_queue),
      originalQueue: List<GenericSong>.from(_originalQueue),
      currentIndex: _currentIndex,
      positionMs: _player.position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      isPlaying: isPlaying,
      shuffleEnabled: _shuffleEnabled,
      repeatMode: _repeatMode.toString(),
      contextType: _playbackContextType,
      contextName: _playbackContextName,
      contextId: _playbackContextID,
      contextSource: _playbackContextSource,
      volume: _player.volume,
      resolvedYoutubeIds: getResolvedYoutubeIdsForTracks(_queue),
    );
  }

  Map<String, String> getResolvedYoutubeIdsForTracks(List<GenericSong> tracks) {
    final ids = <String, String>{};
    for (final track in tracks) {
      final resolved = YouTubeProvider.getCachedVideoId(track.id);
      if (resolved != null && resolved.isNotEmpty) {
        ids[track.id] = resolved;
      }
    }
    return ids;
  }

  Future<void> applyConnectSnapshot(
    ConnectPlaybackSnapshot snapshot, {
    bool autoPlay = true,
    bool preserveVolume = false,
  }) async {
    logger.d(
      '[Handoff] WispAudioHandler.applyConnectSnapshot: incoming snapshot queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
    );
    await YouTubeProvider.mergeVideoIdCache(snapshot.resolvedYoutubeIds);

    await setQueue(
      snapshot.queue,
      startIndex: snapshot.currentIndex < 0 ? 0 : snapshot.currentIndex,
      play: autoPlay,
      contextType: snapshot.contextType,
      contextName: snapshot.contextName,
      contextID: snapshot.contextId,
      contextSource: snapshot.contextSource,
      shuffleEnabled: snapshot.shuffleEnabled,
      originalQueue: snapshot.originalQueue,
    );

    await setRepeatMode(_repeatModeFromString(snapshot.repeatMode));

    if (!preserveVolume && snapshot.volume != null) {
      await setVolume(snapshot.volume!.clamp(0.0, 1.0));
    }

    final targetPosition = Duration(milliseconds: snapshot.positionMs);
    if (targetPosition > Duration.zero) {
      await seek(targetPosition);
    }

    if (!snapshot.isPlaying) {
      await pause();
    } else if (autoPlay) {
      await play();
    }
    logger.d(
      '[Handoff] WispAudioHandler.applyConnectSnapshot: applied snapshot currentIndex=$_currentIndex isPlaying=${isPlaying} positionMs=${_player.position.inMilliseconds}',
    );
  }

  /// Applies remote snapshot metadata without reloading audio sources.
  ///
  /// Used by host/controller devices in linked modes so UI stays in sync
  /// without triggering stream URL fetching on every snapshot refresh.
  void applyPassiveConnectSnapshot(ConnectPlaybackSnapshot snapshot) {
    logger.d(
      '[Handoff] WispAudioHandler.applyPassiveConnectSnapshot: incoming passive snapshot queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
    );
    bool sameQueueById(List<GenericSong> a, List<GenericSong> b) {
      if (identical(a, b)) return true;
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i].id != b[i].id) return false;
      }
      return true;
    }

    var changed = false;

    if (!sameQueueById(_queue, snapshot.queue)) {
      _queue = List<GenericSong>.from(snapshot.queue);
      changed = true;
    }

    if (!sameQueueById(_originalQueue, snapshot.originalQueue)) {
      _originalQueue = List<GenericSong>.from(snapshot.originalQueue);
      changed = true;
    }

    final nextIndex = _queue.isEmpty
        ? -1
        : snapshot.currentIndex.clamp(0, _queue.length - 1);
    if (_currentIndex != nextIndex) {
      _currentIndex = nextIndex;
      changed = true;
    }

    final nextTrack = (_currentIndex >= 0 && _currentIndex < _queue.length)
        ? _queue[_currentIndex]
        : null;
    if (_currentTrack?.id != nextTrack?.id) {
      _currentTrack = nextTrack;
      changed = true;
    }

    if (_shuffleEnabled != snapshot.shuffleEnabled) {
      _shuffleEnabled = snapshot.shuffleEnabled;
      changed = true;
    }

    final serviceRepeatMode = _repeatModeFromString(snapshot.repeatMode);
    final repeatMode = switch (serviceRepeatMode) {
      audio_service.AudioServiceRepeatMode.one => RepeatMode.one,
      audio_service.AudioServiceRepeatMode.all => RepeatMode.all,
      audio_service.AudioServiceRepeatMode.none => RepeatMode.off,
      _ => RepeatMode.off,
    };
    if (_repeatMode != repeatMode) {
      _repeatMode = repeatMode;
      changed = true;
    }

    if (_playbackContextType != snapshot.contextType ||
        _playbackContextName != snapshot.contextName ||
        _playbackContextID != snapshot.contextId ||
        _playbackContextSource != snapshot.contextSource) {
      _playbackContextType = snapshot.contextType;
      _playbackContextName = snapshot.contextName;
      _playbackContextID = snapshot.contextId;
      _playbackContextSource = snapshot.contextSource;
      changed = true;
    }

    final nextDuration = snapshot.durationMs != null && snapshot.durationMs! > 0
        ? Duration(milliseconds: snapshot.durationMs!)
        : null;
    if (_lastKnownDuration != nextDuration) {
      _lastKnownDuration = nextDuration;
      changed = true;
    }

    _forcePositionUpdate(Duration(milliseconds: snapshot.positionMs));
    if (changed) {
      _broadcastQueue();
      _broadcastPlaybackState();
      _updateMediaItem();
      notifyListeners();
      logger.d(
        '[Handoff] WispAudioHandler.applyPassiveConnectSnapshot: applied passive snapshot updated currentIndex=$_currentIndex isPlaying=${isPlaying}',
      );
    }
  }

  /// Applies a delta (partial state update) to reduce unnecessary reloads.
  /// Only updates fields that are present in the delta.
  Future<void> applyDelta(ConnectStateDelta delta) async {
    bool changed = false;

    // Apply position if present
    if (delta.positionMs != null) {
      final targetPosition = Duration(milliseconds: delta.positionMs!);
      await seek(targetPosition);
      changed = true;
    }

    // Apply current index if present
    if (delta.currentIndex != null) {
      if (delta.currentIndex != _currentIndex &&
          delta.currentIndex! >= 0 &&
          delta.currentIndex! < _queue.length) {
        await skipToQueueItem(delta.currentIndex!);
        changed = true;
      }
    }

    // Apply playing state if present
    if (delta.isPlaying != null) {
      if (delta.isPlaying!) {
        if (!isPlaying) {
          await play();
          changed = true;
        }
      } else {
        if (isPlaying) {
          await pause();
          changed = true;
        }
      }
    }

    // Apply shuffle if present
    if (delta.shuffleEnabled != null) {
      if (delta.shuffleEnabled != _shuffleEnabled) {
        setShuffleEnabled(delta.shuffleEnabled!);
        changed = true;
      }
    }

    // Apply repeat mode if present
    if (delta.repeatMode != null) {
      final mode = _repeatModeFromString(delta.repeatMode!);
      if (mode != _repeatMode) {
        await setRepeatMode(mode);
        changed = true;
      }
    }

    // Apply queue if present (fallback to full snapshot)
    if (delta.queue != null) {
      await setQueue(
        delta.queue!,
        startIndex: delta.currentIndex ?? _currentIndex.clamp(0, delta.queue!.length - 1),
        play: delta.isPlaying ?? isPlaying,
      );
      changed = true;
    }

    // Apply volume if present
    if (delta.volume != null) {
      await setVolume(delta.volume!.clamp(0.0, 1.0));
      changed = true;
    }

    // Apply duration if present (for UI sync)
    if (delta.durationMs != null) {
      final nextDuration = delta.durationMs! > 0
          ? Duration(milliseconds: delta.durationMs!)
          : null;
      if (_lastKnownDuration != nextDuration) {
        _lastKnownDuration = nextDuration;
        changed = true;
      }
    }

    if (changed) {
      _broadcastQueue();
      _broadcastPlaybackState();
      _updateMediaItem();
      notifyListeners();
    }
  }

  bool isTrackCached(String trackId) =>
      AudioCacheManager.instance.isTrackCached(trackId);

  WispAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    await _loadQueue();
    await YouTubeProvider.loadVideoIdCache();
    _gaplessPlaybackEnabled =
        await PreferencesProvider.isGaplessPlaybackEnabled();
    _crossfadeEnabled = await PreferencesProvider.isCrossfadeEnabled();
    _crossfadeDurationSeconds =
        await PreferencesProvider.isCrossfadeDurationSeconds();
    JustAudioMediaKit.prefetchPlaylist = _gaplessPlaybackEnabled;

    _attachActivePlayerListeners();
    _scheduleNextTrackPreload();

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
      await _primaryPlayer.setVolume(initialVolume);
      await _secondaryPlayer.setVolume(initialVolume);
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
    _updateCrossfadeVolume(position);
    if (_crossfadeEnabled && !_isCrossfading) {
      unawaited(_maybeStartCrossfade(position));
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _updateMediaSessionPosition(position, nowMs);
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
    _updateMediaSessionPosition(position, nowMs, force: true);
    _lastNotifiedPosition = position;
    _lastPositionNotifyMs = nowMs;
    _lastPositionUpdateMs = nowMs;
    notifyListeners();
  }

  void _updateMediaSessionPosition(
    Duration position,
    int nowMs, {
    bool force = false,
  }) {
    if (_currentTrack == null) return;
    if (!force && nowMs - _lastMediaUpdateMs < 1000) return;
    final posMs = position.inMilliseconds;
    if (!force && posMs == _lastMediaPositionMs) return;
    _lastMediaPositionMs = posMs;
    _lastMediaUpdateMs = nowMs;

    try {
      playbackState.add(
        playbackState.value.copyWith(
          playing: isPlaying,
          processingState: _mapProcessingState(),
          updatePosition: position,
        ),
      );
    } catch (_) {}
  }

  Duration _getInterpolatedPosition() {
    if (_lastPositionUpdateMs == 0) return _lastNotifiedPosition;
    if (!isPlaying || isBuffering) return _lastNotifiedPosition;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = nowMs - _lastPositionUpdateMs;
    if (elapsedMs <= 0) return _lastNotifiedPosition;

    var predicted = _lastNotifiedPosition + Duration(milliseconds: elapsedMs);

    if (_lastRawPosition > Duration.zero && predicted > _lastRawPosition) {
      predicted = _lastRawPosition;
    }

    final trackDuration = duration;
    if (trackDuration > Duration.zero && predicted > trackDuration) {
      predicted = trackDuration;
    }

    return predicted;
  }

  bool _isAtTrackEnd() {
    final trackDuration = _player.duration;
    if (trackDuration == null || trackDuration <= Duration.zero) {
      return false;
    }

    final position = _player.position;
    final threshold = trackDuration - const Duration(milliseconds: 400);
    return position >= threshold;
  }

  // RPC and MPRIS timers to update Discord and MPRIS every second
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
    _updateMediaSessionPosition(
      position,
      DateTime.now().millisecondsSinceEpoch,
      force: true,
    );
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
      _broadcastPlaybackState();
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

  void _setTrackTransitioning(bool value) {
    if (_isTrackTransitioning == value) return;
    _isTrackTransitioning = value;
    notifyListeners();
  }

  void _attachActivePlayerListeners() {
    _positionSubscription?.cancel();
    _processingStateSubscription?.cancel();
    _playingSubscription?.cancel();
    _currentIndexSubscription?.cancel();

    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (!_playlistPlaybackEnabled || !(_player.hasNext || _player.hasPrevious)) {
        return;
      }
      if (index == null || index == _currentIndex) {
        return;
      }
      if (index < 0 || index >= _queue.length) {
        return;
      }
      _currentIndex = index;
      _currentTrack = _queue[index];
      _errorMessage = null;
      _updateMediaItem();
      _saveQueue();
      _queueCaching(_currentTrack!);
      unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: index));
      notifyListeners();
    });

    _processingStateSubscription = _player.processingStateStream.listen((
      state,
    ) {
      if (state == ProcessingState.completed) {
        _onCompleted();
      } else if (state == ProcessingState.loading ||
          state == ProcessingState.buffering) {
        if (_isTrackTransitioning || !_player.playing) {
          _setState(PlaybackState.loading);
        }
      } else if (state == ProcessingState.ready) {
        if (_isTrackTransitioning) {
          _setTrackTransitioning(false);
        }
        if (_player.playing) {
          _setState(PlaybackState.playing);
        } else if (_state != PlaybackState.idle) {
          _setState(PlaybackState.paused);
        }
      }
      _broadcastPlaybackState();
    });

    _playingSubscription = _player.playingStream.listen((playing) {
      final wasPlaying = _state == PlaybackState.playing;
      if (_player.processingState == ProcessingState.ready) {
        if (!playing && wasPlaying && _isAtTrackEnd()) {
          logger.w(
            '[Audio/Player] Fallback completion trigger: playing=false at track end',
          );
          _onCompleted();
          _broadcastPlaybackState();
          return;
        }
        _setState(playing ? PlaybackState.playing : PlaybackState.paused);
      }
      _broadcastPlaybackState();
    });

    _positionSubscription = _player.positionStream.listen((position) {
      _handlePositionUpdate(position);
      _handleRpcPositionTick();
    });
  }

  void _invalidateCrossfadePreload() {
    _crossfadePreloadGeneration++;
    _preloadedNextIndex = null;
    _preloadedNextTrack = null;
    _inactivePreloadTrackId = null;
  }

  Future<void> _clearInactivePlayer() async {
    try {
      await _inactivePlayer.stop();
    } catch (_) {}
    _inactivePreloadTrackId = null;
  }

  bool _isCrossfadePreloadStillValid(
    int generation,
    int nextIndex,
    int trackChangeToken,
  ) {
    if (generation != _crossfadePreloadGeneration) return false;
    if (trackChangeToken != _trackChangeToken) return false;
    if (_preloadedNextIndex != nextIndex) return false;
    if (nextIndex < 0 || nextIndex >= _queue.length) return false;
    if (_preloadedNextTrack?.id != _queue[nextIndex].id) return false;
    return true;
  }

  bool _isInactivePreloadReady(int nextIndex, GenericSong nextTrack) {
    return _inactivePlayer.audioSource != null &&
        _preloadedNextIndex == nextIndex &&
        _preloadedNextTrack?.id == nextTrack.id &&
        _inactivePreloadTrackId == nextTrack.id;
  }

  void _invalidatePlaybackPrefetch({bool clearSources = false}) {
    _prefetchGeneration++;
    _prefetchSourceTasks.clear();
    if (clearSources) {
      _prefetchedAudioSources.clear();
    }
  }

  int? _nextQueueIndex() {
    if (_queue.isEmpty || _currentIndex < 0) {
      return null;
    }

    final nextIndex = _currentIndex + 1;
    if (nextIndex < _queue.length) {
      return nextIndex;
    }

    if (_repeatMode == RepeatMode.all) {
      return 0;
    }

    return null;
  }

  Future<void> _scheduleNextTrackPreload() async {
    if (!_crossfadeEnabled || _queue.isEmpty || _currentIndex < 0) {
      return;
    }

    final nextIndex = _nextQueueIndex();
    if (nextIndex == null) {
      _invalidateCrossfadePreload();
      return;
    }

    final generation = _crossfadePreloadGeneration;
    final trackChangeToken = _trackChangeToken;
    final nextTrack = _queue[nextIndex];
    _preloadedNextIndex = nextIndex;
    _preloadedNextTrack = nextTrack;

    try {
      final source = await _getAudioSource(nextTrack);
      if (!_isCrossfadePreloadStillValid(
        generation,
        nextIndex,
        trackChangeToken,
      )) {
        return;
      }

      if (source == null) {
        _invalidateCrossfadePreload();
        return;
      }

      await _inactivePlayer.stop();
      if (!_isCrossfadePreloadStillValid(
        generation,
        nextIndex,
        trackChangeToken,
      )) {
        return;
      }

      await _inactivePlayer.setAudioSource(source);
      await _inactivePlayer.setVolume(0);
      if (!_isCrossfadePreloadStillValid(
        generation,
        nextIndex,
        trackChangeToken,
      )) {
        await _clearInactivePlayer();
        return;
      }

      _inactivePreloadTrackId = nextTrack.id;
    } catch (e) {
      logger.w('[Audio/Player] Crossfade preload failed', error: e);
      _invalidateCrossfadePreload();
      await _clearInactivePlayer();
    }
  }

  Future<void> _cancelCrossfade({bool stopInactive = true}) async {
    if (!_isCrossfading && !_crossfadeFadeInActive && !_crossfadeFadeOutActive) {
      return;
    }

    _stopCrossfadeTimer();
    _isCrossfading = false;
    _crossfadeFadeOutActive = false;
    _crossfadeFadeInActive = false;
    if (stopInactive) {
      try {
        await _inactivePlayer.stop();
      } catch (_) {}
    }
  }

  Future<void> _maybeStartCrossfade(Duration position) async {
    if (!_crossfadeEnabled || _isCrossfading || _currentTrack == null) {
      return;
    }

    final trackDuration = _player.duration;
    if (trackDuration == null || trackDuration <= Duration.zero) {
      return;
    }

    final crossfadeWindow = Duration(
      milliseconds: (_crossfadeDurationSeconds * 1000).round(),
    );
    if (trackDuration <= crossfadeWindow) {
      return;
    }

    const startLead = Duration(milliseconds: 600);

    final remaining = trackDuration - position;
    if (remaining > crossfadeWindow + startLead) {
      return;
    }

    await _startFadeIn();
  }

  Future<void> _startFadeIn() async {
    if (!_crossfadeEnabled || _isCrossfading || _currentTrack == null) {
      return;
    }

    final nextIndex = _nextQueueIndex();
    if (nextIndex == null) {
      return;
    }

    final nextTrack = _queue[nextIndex];
    if (!_isInactivePreloadReady(nextIndex, nextTrack)) {
      _preloadedNextIndex = nextIndex;
      _preloadedNextTrack = nextTrack;
      await _clearInactivePlayer();
      await _scheduleNextTrackPreload();
      if (!_isInactivePreloadReady(nextIndex, nextTrack)) {
        return;
      }
    }

    final previousIndex = _currentIndex;
    final previousTrack = _currentTrack;

    _isCrossfading = true;
    _crossfadeFadeOutActive = true;
    _crossfadeFadeInActive = true;
    _crossfadeTargetVolume = _player.volume <= 0 ? 1.0 : _player.volume;

    _useSecondaryAsActivePlayer = !_useSecondaryAsActivePlayer;
    _attachActivePlayerListeners();

    _currentIndex = nextIndex;
    _currentTrack = nextTrack;
    _updateMediaItem();
    _broadcastPlaybackState();
    _saveQueue();
    notifyListeners();

    try {
      await _player.setVolume(0);
      await _inactivePlayer.setVolume(_crossfadeTargetVolume);
      await _player.play();
      _startCrossfadeTimer();
    } catch (e) {
      logger.w('[Audio/Player] Failed to start crossfade', error: e);
      _useSecondaryAsActivePlayer = !_useSecondaryAsActivePlayer;
      _attachActivePlayerListeners();
      _isCrossfading = false;
      _crossfadeFadeOutActive = false;
      _crossfadeFadeInActive = false;
      _currentIndex = previousIndex;
      _currentTrack = previousTrack;
      if (previousTrack != null) {
        _updateMediaItem();
        _saveQueue();
      }
      _broadcastPlaybackState();
      notifyListeners();
      await _clearInactivePlayer();
    }
  }

  void _startCrossfadeTimer() {
    _stopCrossfadeTimer();

    final fadeDurationMs =
        (_crossfadeDurationSeconds * 1000).clamp(1, 6000).toInt();
    final startTimeMs = DateTime.now().millisecondsSinceEpoch;
    final targetVolume = _crossfadeTargetVolume <= 0 ? 1.0 : _crossfadeTargetVolume;

    _crossfadeTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isCrossfading) {
        timer.cancel();
        return;
      }

      final elapsedMs = DateTime.now().millisecondsSinceEpoch - startTimeMs;
      final progress = (elapsedMs / fadeDurationMs).clamp(0.0, 1.0);
      final curve = progress * (2.0 - progress);
      final fadeOutVolume = targetVolume * (1.0 - curve);
      final fadeInVolume = targetVolume * curve;

      unawaited(_inactivePlayer.setVolume(fadeOutVolume.clamp(0.0, 1.0)));
      unawaited(_player.setVolume(fadeInVolume.clamp(0.0, 1.0)));

      if (progress >= 1.0) {
        timer.cancel();
        unawaited(_completeCrossfade());
      }
    });
  }

  Future<void> _completeCrossfade() async {
    if (!_isCrossfading) {
      return;
    }

    _stopCrossfadeTimer();
    _isCrossfading = false;
    _crossfadeFadeOutActive = false;
    _crossfadeFadeInActive = false;

    try {
      await _inactivePlayer.stop();
    } catch (_) {}

    _invalidateCrossfadePreload();
    _broadcastPlaybackState();
    _ensureRpcTimer();
    _ensureMprisTimer();
    _updateDiscordPresence(force: true);
    notifyListeners();
    _saveQueue();
    unawaited(_scheduleNextTrackPreload());
  }

  Future<void> setGaplessPlaybackEnabled(bool enabled) async {
    if (_gaplessPlaybackEnabled == enabled) return;
    _gaplessPlaybackEnabled = enabled;
    JustAudioMediaKit.prefetchPlaylist =
        _gaplessPlaybackEnabled || _crossfadeEnabled;
    if (_gaplessPlaybackEnabled || _crossfadeEnabled) {
      unawaited(_scheduleNextTrackPreload());
    } else {
      _invalidateCrossfadePreload();
    }
    notifyListeners();
  }

  Future<void> setCrossfadeEnabled(bool enabled) async {
    if (_crossfadeEnabled == enabled) return;
    _crossfadeEnabled = enabled;
    JustAudioMediaKit.prefetchPlaylist =
        _gaplessPlaybackEnabled || _crossfadeEnabled;
    if (_crossfadeEnabled) {
      unawaited(_scheduleNextTrackPreload());
    } else {
      _stopCrossfadeTimer();
      _invalidateCrossfadePreload();
    }
    notifyListeners();
  }

  Future<void> setCrossfadeDurationSeconds(double seconds) async {
    final normalized = seconds.clamp(1.0, 6.0).toDouble();
    if (_crossfadeDurationSeconds == normalized) return;
    _crossfadeDurationSeconds = normalized;
    notifyListeners();
  }

  void _broadcastPlaybackState() {
    try {
      playbackState.add(
        audio_service.PlaybackState(
          playing: isPlaying,
          processingState: _mapProcessingState(),
          controls: [
            _shuffleControl(_shuffleEnabled),
            audio_service.MediaControl.skipToPrevious,
            if (isPlaying)
              audio_service.MediaControl.pause
            else
              audio_service.MediaControl.play,
            audio_service.MediaControl.skipToNext,
            _repeatControl(
              _repeatMode == RepeatMode.one
                  ? audio_service.AudioServiceRepeatMode.one
                  : _repeatMode == RepeatMode.all
                  ? audio_service.AudioServiceRepeatMode.all
                  : audio_service.AudioServiceRepeatMode.none,
            ),
          ],
          systemActions: const {
            audio_service.MediaAction.seek,
            audio_service.MediaAction.seekForward,
            audio_service.MediaAction.seekBackward,
            audio_service.MediaAction.setShuffleMode,
            audio_service.MediaAction.setRepeatMode,
          },
          shuffleMode: _shuffleEnabled
              ? audio_service.AudioServiceShuffleMode.all
              : audio_service.AudioServiceShuffleMode.none,
          repeatMode: _repeatMode == RepeatMode.one
              ? audio_service.AudioServiceRepeatMode.one
              : _repeatMode == RepeatMode.all
              ? audio_service.AudioServiceRepeatMode.all
              : audio_service.AudioServiceRepeatMode.none,
          updatePosition: position,
        ),
      );
    } catch (_) {}
  }

  audio_service.AudioProcessingState _mapProcessingState() {
    if (_player.processingState == ProcessingState.completed) {
      return audio_service.AudioProcessingState.completed;
    }
    if (isLoading) {
      return audio_service.AudioProcessingState.loading;
    }
    if (_state == PlaybackState.idle) {
      return audio_service.AudioProcessingState.idle;
    }
    return audio_service.AudioProcessingState.ready;
  }

  void _updateMediaItem() {
    if (_currentTrack == null) return;
    try {
      mediaItem.add(_toMediaItem(_currentTrack!));
    } catch (_) {}
  }

  void _broadcastQueue() {
    try {
      queue.add(_queue.map(_toMediaItem).toList());
    } catch (_) {}
  }

  audio_service.MediaItem _toMediaItem(GenericSong track) {
    return audio_service.MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artists.map((a) => a.name).join(', '),
      album: track.album?.title ?? '',
      artUri: Uri.parse(track.thumbnailUrl),
      duration: Duration(seconds: track.durationSecs),
    );
  }

  /// Handle track completion
  void _onCompleted() {
    if (_isHandlingCompletion) return;
    if (_isCrossfading ||
        _crossfadeFadeOutActive ||
        _crossfadeFadeInActive ||
        _isTrackTransitioning ||
        _player.playing) {
      return;
    }
    _isHandlingCompletion = true;
    final token = _trackChangeToken;
    () async {
      logger.i('[Audio/Player] Track completed: ${_currentTrack?.title}');

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
      unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: _currentIndex));
      unawaited(_scheduleNextTrackPreload());
    } catch (e) {
      logger.w('[Audio/Player] Startup prepare failed', error: e);
    }
  }

  /// Load the current track into the player for gapless/lazy playlist playback
  Future<AudioSource?> _buildSingleTrackSource(GenericSong track) async {
    return await _getAudioSource(track);
  }

  Future<void> _schedulePlaybackPrefetchWindow({int? anchorIndex}) async {
    if (_queue.isEmpty) return;

    final currentIndex = anchorIndex ?? _currentIndex;
    if (currentIndex < 0 || currentIndex >= _queue.length) return;

    // When in handoff host mode, only prefetch the current track (for smooth unlinking).
    // Skip prefetching the full window since playback happens on the target device.
    if (_isHandoffHost) {
      if (currentIndex >= 0 && currentIndex < _queue.length) {
        final currentTrack = _queue[currentIndex];
        if (!_prefetchedAudioSources.containsKey(currentTrack.id) &&
            !_prefetchSourceTasks.containsKey(currentTrack.id)) {
          final generation = _prefetchGeneration;
          final task = _prefetchTrackSource(currentTrack, generation);
          _prefetchSourceTasks[currentTrack.id] = task;
          final source = await task;
          _prefetchSourceTasks.remove(currentTrack.id);
          if (generation != _prefetchGeneration) return;
          if (source != null) {
            _prefetchedAudioSources[currentTrack.id] = source;
          }
        }
      }
      return;
    }

    final generation = _prefetchGeneration;
    final indices = <int>[];
    final seen = <int>{};

    for (var offset = 1; offset <= _prefetchWindowSize; offset++) {
      final nextIndex = _queueIndexAfter(currentIndex, offset);
      if (nextIndex == null) break;
      if (nextIndex == currentIndex) continue;
      if (!seen.add(nextIndex)) continue;
      indices.add(nextIndex);
    }

    final keepIds = <String>{
      for (final index in indices) _queue[index].id,
    };
    _prefetchedAudioSources.removeWhere(
      (trackId, _) => !keepIds.contains(trackId),
    );

    for (final index in indices) {
      if (generation != _prefetchGeneration) return;
      final track = _queue[index];
      if (_prefetchedAudioSources.containsKey(track.id) ||
          _prefetchSourceTasks.containsKey(track.id)) {
        continue;
      }

      final task = _prefetchTrackSource(track, generation);
      _prefetchSourceTasks[track.id] = task;
      final source = await task;
      _prefetchSourceTasks.remove(track.id);
      if (generation != _prefetchGeneration) return;
      if (source != null) {
        _prefetchedAudioSources[track.id] = source;
      }
    }
  }

  Future<AudioSource?> _prefetchTrackSource(
    GenericSong track,
    int generation,
  ) async {
    if (!_isOnline) return null;

    try {
      final source = await _getAudioSource(track, allowPrefetched: false);
      if (generation != _prefetchGeneration) return null;
      return source;
    } catch (e) {
      logger.w('[Audio/Player] Failed to prefetch track source', error: e);
      return null;
    }
  }

  int? _queueIndexAfter(int index, int offset) {
    if (_queue.isEmpty || index < 0 || index >= _queue.length) {
      return null;
    }

    final nextIndex = index + offset;
    if (nextIndex < _queue.length) {
      return nextIndex;
    }

    if (_repeatMode != RepeatMode.all) {
      return null;
    }

    return nextIndex % _queue.length;
  }

  Future<void> _loadPlaylistPlayback(
    int index, {
    required bool play,
    Duration initialPosition = Duration.zero,
    int? token,
  }) async {
    if (_queue.isEmpty) return;

    final requestToken = token ?? ++_trackChangeToken;
    final safeIndex = index.clamp(0, _queue.length - 1);
    final track = _queue[safeIndex];

    _currentIndex = safeIndex;
    _currentTrack = track;
    _errorMessage = null;
    _setTrackTransitioning(true);
    _setState(PlaybackState.loading);
    _updateMediaItem();

    try {
      await _cancelCrossfade(stopInactive: true);
      await _clearInactivePlayer();
      await _player.stop();
      if (requestToken != _trackChangeToken) return;

      // Load just the current track to start
      final currentSource = await _buildSingleTrackSource(track);
      if (requestToken != _trackChangeToken) return;
      if (currentSource == null) {
        throw Exception('Could not get audio source for ${track.title}');
      }

      _crossfadeFadeOutActive = false;
      _crossfadeFadeInActive = false;
      _crossfadeTargetVolume = _lastVolume <= 0 ? 1.0 : _lastVolume;
      _stopCrossfadeTimer();

      // Set just the current track with lazy preparation enabled
      await _player.setAudioSources(
        [currentSource],
        initialIndex: 0,
        initialPosition: initialPosition,
        preload: false, // Load each item just in time
      );
      if (requestToken != _trackChangeToken) return;

      await _player.seek(initialPosition);
      _forcePositionUpdate(initialPosition);
      if (requestToken != _trackChangeToken) return;

      if (play) {
        await _player.play();
        if (requestToken != _trackChangeToken) return;
        _setState(PlaybackState.playing);
      } else {
        _setState(PlaybackState.paused);
      }

      _broadcastPlaybackState();
      _ensureRpcTimer();
      if (play) {
        _ensureMprisTimer();
      } else {
        _stopMprisTimer();
      }
      _updateDiscordPresence(force: true);
      _saveQueue();
      _queueCaching(track);
      _invalidateCrossfadePreload();
      unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: safeIndex));
      unawaited(_scheduleNextTrackPreload());
    } catch (e) {
      logger.e('[Audio/Player] Playlist playback load error', error: e);
      _errorMessage = e.toString();
      _setState(PlaybackState.error);
    } finally {
      if (requestToken == _trackChangeToken) {
        _setTrackTransitioning(false);
      }
    }
  }

  Future<void> _advanceToNext({int? token}) async {
    int nextIndex = _currentIndex + 1;

    if (nextIndex >= _queue.length) {
      if (_repeatMode == RepeatMode.all) {
        nextIndex = 0;
      } else {
        logger.i('[Audio/Player] Reached end of queue');
        _setState(PlaybackState.idle);
        return;
      }
    }

    // Use the same explicit transition path as manual skip to avoid
    // desynchronization between currentIndex/UI and audible track.
    if (_playlistPlaybackEnabled) {
      await _playAtIndex(nextIndex, token: token ?? ++_trackChangeToken);
      return;
    }

    await _playAtIndex(nextIndex, token: token);
  }

  Future<void> _reloadCurrentTrackSource() async {
    final track = _currentTrack;
    if (track == null) return;

    final requestToken = ++_trackChangeToken;
    final wasPlaying = _player.playing;
    final targetPosition = _player.position;

    _errorMessage = null;
    _setTrackTransitioning(true);
    _setState(PlaybackState.loading);

    try {
      if (_playlistPlaybackEnabled) {
        await _loadPlaylistPlayback(
          _currentIndex,
          play: wasPlaying,
          initialPosition: targetPosition,
          token: requestToken,
        );
        return;
      }

      await _cancelCrossfade(stopInactive: true);
      await _clearInactivePlayer();
      await _player.stop();
      if (requestToken != _trackChangeToken || _currentTrack?.id != track.id) {
        return;
      }

      final source = await _getAudioSource(track);
      if (requestToken != _trackChangeToken || _currentTrack?.id != track.id) {
        return;
      }
      if (source == null) {
        throw Exception('Could not get audio source');
      }

      await _player.setAudioSource(source);
      if (requestToken != _trackChangeToken || _currentTrack?.id != track.id) {
        return;
      }

      final duration = _player.duration;
      final seekPosition =
          duration != null && targetPosition > duration ? duration : targetPosition;
      await _player.seek(seekPosition);
      _forcePositionUpdate(seekPosition);
      if (requestToken != _trackChangeToken || _currentTrack?.id != track.id) {
        return;
      }

      if (wasPlaying) {
        await _player.play();
      }

      _setState(wasPlaying ? PlaybackState.playing : PlaybackState.paused);
      _broadcastPlaybackState();
      _ensureRpcTimer();
      _ensureMprisTimer();
      _updateDiscordPresence(force: true);
      _invalidateCrossfadePreload();
      unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: _currentIndex));
      unawaited(_scheduleNextTrackPreload());
    } catch (e) {
      logger.e('[Audio/Player] Failed to reload current track source', error: e);
      _errorMessage = e.toString();
      _setState(PlaybackState.error);
    } finally {
      if (requestToken == _trackChangeToken) {
        _setTrackTransitioning(false);
      }
    }
  }

  Future<void> _playAtIndex(int index, {int? token}) async {
    if (index < 0 || index >= _queue.length) return;
    final requestToken = token ?? ++_trackChangeToken;

    final track = _queue[index];
    logger.i(
      '[Audio/Player] Playing [${index + 1}/${_queue.length}]: ${track.title}',
    );

    _errorMessage = null;
    _setTrackTransitioning(true);
    _setState(PlaybackState.loading);
    _updateMediaItem();

    try {
      if (_playlistPlaybackEnabled) {
        await _loadPlaylistPlayback(
          index,
          play: true,
          token: requestToken,
        );
        return;
      }

      _currentIndex = index;
      _currentTrack = track;

      await _cancelCrossfade(stopInactive: true);
      await _clearInactivePlayer();
      await _player.stop();
      if (requestToken != _trackChangeToken) return;

      final source = await _getAudioSource(track);
      if (requestToken != _trackChangeToken) return;
      if (source == null) {
        throw Exception('Could not get audio source');
      }

      await _player.setAudioSource(source);
      if (requestToken != _trackChangeToken) return;

      await _player.seek(Duration.zero);
      _forcePositionUpdate(Duration.zero);
      if (requestToken != _trackChangeToken) return;

      await _player.play();
      if (requestToken != _trackChangeToken) return;

      _currentIndex = index;
      _currentTrack = track;
      _broadcastPlaybackState();
      _ensureRpcTimer();
      _updateDiscordPresence(force: true);
      _saveQueue();
      _queueCaching(track);
      _invalidateCrossfadePreload();
      unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: index));
      unawaited(_scheduleNextTrackPreload());
    } catch (e) {
      logger.e('[Audio/Player] Error', error: e);
      _errorMessage = e.toString();
      _setState(PlaybackState.error);

      if (_currentIndex < _queue.length - 1) {
        await Future.delayed(const Duration(seconds: 2));
        if (_state == PlaybackState.error) {
          await _advanceToNext();
        }
      }
    } finally {
      if (requestToken == _trackChangeToken) {
        _setTrackTransitioning(false);
      }
    }
  }

  Future<AudioSource?> _getAudioSource(
    GenericSong track, {
    bool allowPrefetched = true,
  }) async {
    if (allowPrefetched) {
      final prefetched = _prefetchedAudioSources[track.id];
      if (prefetched != null) {
        return prefetched;
      }
    }

    final cacheManager = AudioCacheManager.instance;
    final audioSpotifyEnabled =
        await PreferencesProvider.isAudioSpotifyEnabled();
    final audioYouTubeEnabled =
        await PreferencesProvider.isAudioYouTubeEnabled();

    if (!audioSpotifyEnabled && !audioYouTubeEnabled) {
      throw Exception('All audio providers are disabled in Preferences.');
    }

    final cachedPath = cacheManager.getCachedPath(track.id);
    if (cachedPath != null && File(cachedPath).existsSync()) {
      await cacheManager.updateLastPlayed(track.id);
      return AudioSource.file(cachedPath);
    }

    if (!_isOnline) {
      throw Exception('Offline and track not cached');
    }

    if (audioSpotifyEnabled &&
        (track.source == SongSource.spotify ||
            track.source == SongSource.spotifyInternal)) {
      try {
        final spotify = await _spotifyAudio.resolveStream(track);
        if (spotify != null && spotify.streamUrl.isNotEmpty) {
          if (spotify.mayRequireDecryption && spotify.audioKey != null) {
            try {
              final proxyUri = await SpotifyDecryptStreamingProxy.instance
                  .registerStream(
                    cacheKey: spotify.resolvedId,
                    streamUrl: spotify.streamUrl,
                    audioKey: spotify.audioKey!,
                    fallbackStreamUrls: spotify.fallbackStreamUrls,
                    headers: spotify.requestHeaders,
                  );
              logger.d('[Audio/Player] Streaming decrypted Spotify via local proxy');
              return AudioSource.uri(proxyUri);
            } catch (error) {
              logger.w(
                '[Audio/Player] Spotify decrypt proxy unavailable, falling back',
                error: error,
              );
            }

            final decryptedPath = await _spotifyDecryptor
                .downloadAndDecryptToTemp(
                  cacheKey: spotify.resolvedId,
                  url: spotify.streamUrl,
                  audioKey: spotify.audioKey!,
                  headers: spotify.requestHeaders,
                );
            if (decryptedPath != null && File(decryptedPath).existsSync()) {
              logger.d('[Audio/Player] Playing decrypted Spotify temp file');
              return AudioSource.file(decryptedPath);
            }
            logger.w(
              '[Audio/Player] Spotify decrypt temp fallback failed, trying raw stream',
            );
          }

          return AudioSource.uri(
            Uri.parse(spotify.streamUrl),
            headers: {
              ...spotify.requestHeaders,
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          );
        }
        logger.d(
          '[Audio/Player] Spotify stream unavailable, falling back to YouTube',
        );
      } catch (e) {
        logger.w(
          '[Audio/Player] Spotify stream failed, falling back to YouTube',
          error: e,
        );
      }
    }

    if (!audioYouTubeEnabled) {
      throw Exception('YouTube audio provider is disabled in Preferences.');
    }

    await YtDlpReadinessCoordinator.instance.waitUntilReady();

    String? videoId = YouTubeProvider.getCachedVideoId(track.id);
    if (videoId == null) {
      final artistNames = track.artists.map((a) => a.name).join(', ');
      final result = await _youtube.searchYouTube(
        artistNames,
        track.title,
        durationSecs: track.durationSecs,
      );
      if (result == null) return null;
      videoId = result.videoId;
      YouTubeProvider.cacheVideoId(track.id, videoId);
    }

    final streamUrl = await _getStreamUrlWithCache(videoId);

    final userAgent = Platform.isAndroid
        ? 'com.google.android.youtube/19.29.37 (Linux; U; Android 14) gzip'
        : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

    return AudioSource.uri(
      Uri.parse(streamUrl),
      headers: {'User-Agent': userAgent},
    );
  }

  void _queueCaching(GenericSong track) {
    final cacheManager = AudioCacheManager.instance;
    if (!cacheManager.autoCacheEnabled) return;

    _queueTrackCache(track);

    if (_currentIndex + 1 < _queue.length) {
      _preResolveNextTrack(_queue[_currentIndex + 1]);
    }
  }

  Future<void> _preResolveNextTrack(GenericSong track) async {
    if (!_isOnline) return;

    final audioSpotifyEnabled =
        await PreferencesProvider.isAudioSpotifyEnabled();
    final audioYouTubeEnabled =
        await PreferencesProvider.isAudioYouTubeEnabled();
    if (!audioSpotifyEnabled && !audioYouTubeEnabled) return;

    final cacheManager = AudioCacheManager.instance;
    if (cacheManager.isTrackCached(track.id)) {
      return;
    }

    if (audioSpotifyEnabled &&
        (track.source == SongSource.spotify ||
            track.source == SongSource.spotifyInternal)) {
      try {
        final spotify = await _spotifyAudio.resolveStream(track);
        if (spotify != null) {
          logger.d('[Audio/Player] Pre-resolved Spotify URL: ${track.title}');
          return;
        }
      } catch (e) {
        logger.w('[Audio/Player] Failed to pre-resolve Spotify URL', error: e);
      }
    }

    if (!audioYouTubeEnabled) {
      return;
    }

    await YtDlpReadinessCoordinator.instance.waitUntilReady();

    String? videoId = YouTubeProvider.getCachedVideoId(track.id);
    if (videoId != null && _getCachedStreamUrl(videoId) != null) return;

    try {
      final artistNames = track.artists.map((a) => a.name).join(', ');
      if (videoId == null) {
        final result = await _youtube.searchYouTube(
          artistNames,
          track.title,
          durationSecs: track.durationSecs,
        );
        if (result == null) return;
        videoId = result.videoId;
        YouTubeProvider.cacheVideoId(track.id, videoId);
      }

      await _getStreamUrlWithCache(videoId);
      logger.d('[Audio/Player] Pre-resolved next track URL: ${track.title}');
    } catch (e) {
      logger.w('[Audio/Player] Failed to pre-resolve next track', error: e);
    }
  }

  Future<void> _queueTrackCache(GenericSong track) async {
    final cacheManager = AudioCacheManager.instance;
    if (cacheManager.isTrackCached(track.id) ||
        cacheManager.isDownloading(track.id)) {
      return;
    }

    final artistNames = track.artists.map((a) => a.name).join(', ');
    cacheManager.queueDownload(
      trackId: track.id,
      trackTitle: track.title,
      artistName: artistNames,
      resolveAndGetStream: () async {
        final audioSpotifyEnabled =
            await PreferencesProvider.isAudioSpotifyEnabled();
        final audioYouTubeEnabled =
            await PreferencesProvider.isAudioYouTubeEnabled();

        if (!audioSpotifyEnabled && !audioYouTubeEnabled) {
          throw Exception('All audio providers are disabled in Preferences.');
        }

        if (audioSpotifyEnabled &&
            (track.source == SongSource.spotify ||
                track.source == SongSource.spotifyInternal)) {
          final spotify = await _spotifyAudio.resolveStream(track);
          if (spotify != null) {
            if (spotify.mayRequireDecryption && spotify.audioKey != null) {
              final decryptedPath = await _spotifyDecryptor
                  .downloadAndDecryptToTemp(
                    cacheKey: spotify.resolvedId,
                    url: spotify.streamUrl,
                    audioKey: spotify.audioKey!,
                    headers: spotify.requestHeaders,
                  );
              if (decryptedPath != null) {
                return (
                  'dec_${spotify.resolvedId}',
                  Uri.file(decryptedPath).toString(),
                );
              }
            }
            return (spotify.resolvedId, spotify.streamUrl);
          }
        }

        if (!audioYouTubeEnabled) {
          throw Exception('YouTube audio provider is disabled in Preferences.');
        }

        await YtDlpReadinessCoordinator.instance.waitUntilReady();

        String? videoId = YouTubeProvider.getCachedVideoId(track.id);
        if (videoId == null) {
          final result = await _youtube.searchYouTube(
            artistNames,
            track.title,
            durationSecs: track.durationSecs,
          );
          if (result == null) throw Exception('Could not find video');
          videoId = result.videoId;
          YouTubeProvider.cacheVideoId(track.id, videoId);
        }
        final streamUrl = await _getStreamUrlWithCache(videoId);
        return (videoId, streamUrl);
      },
    );
  }

  String? _getCachedStreamUrl(String videoId) {
    final entry = _streamUrlCache[videoId];
    if (entry == null) return null;
    if (!entry.isValid) {
      _streamUrlCache.remove(videoId);
      return null;
    }
    return entry.url;
  }

  Future<String> _getStreamUrlWithCache(String videoId) async {
    final cached = _getCachedStreamUrl(videoId);
    if (cached != null) return cached;

    final streamUrl = await _youtube.getStreamUrl(videoId);
    _streamUrlCache[videoId] = _StreamUrlCacheEntry(
      url: streamUrl,
      expiresAt: DateTime.now().add(_streamUrlTtl),
    );
    return streamUrl;
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
      contextId: _playbackContextID
    );
  }

  Future<void> _clearDiscordPresence() async {
    _rpcLastSecond = -1;
    await DiscordRpcService.instance.clearPresence();
    _stopRpcTimer();
  }

  static audio_service.MediaControl _shuffleControl(bool enabled) =>
      audio_service.MediaControl.custom(
        androidIcon: enabled
            ? 'drawable/ic_shuffle_on'
            : 'drawable/ic_shuffle_off',
        label: 'Shuffle',
        name: 'toggleShuffle',
      );

  static audio_service.MediaControl _repeatControl(
    audio_service.AudioServiceRepeatMode mode,
  ) {
    final icon = mode == audio_service.AudioServiceRepeatMode.one
        ? 'drawable/ic_repeat_one'
        : mode == audio_service.AudioServiceRepeatMode.all
        ? 'drawable/ic_repeat'
        : 'drawable/ic_repeat_on';
    return audio_service.MediaControl.custom(
      androidIcon: icon,
      label: 'Repeat',
      name: 'toggleRepeat',
    );
  }

  // AUDIO_SERVICE OVERRIDES
  @override
  Future<void> play() async {
    if (isLoading || isBuffering || isTrackTransitioning) {
      logger.d('[Audio/Player] Ignoring play intent while track is loading');
      return;
    }

    if (_player.audioSource == null && _currentTrack != null) {
      final requestToken = ++_trackChangeToken;
      _errorMessage = null;
      _setTrackTransitioning(true);
      _setState(PlaybackState.loading);
      try {
        if (_playlistPlaybackEnabled) {
          await _loadPlaylistPlayback(
            _currentIndex < 0 ? 0 : _currentIndex,
            play: true,
            token: requestToken,
          );
          return;
        }

        final source = await _getAudioSource(_currentTrack!);
        if (requestToken != _trackChangeToken) return;
        if (source == null) return;
        await _player.setAudioSource(source);
        if (requestToken != _trackChangeToken) return;
      } catch (e) {
        _errorMessage = e.toString();
        _setState(PlaybackState.error);
        return;
      } finally {
        if (requestToken == _trackChangeToken) {
          _setTrackTransitioning(false);
        }
      }
    }
    await _player.play();
    _ensureRpcTimer();
    _ensureMprisTimer();
    _updateDiscordPresence(force: true);
    unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: _currentIndex));
    unawaited(_scheduleNextTrackPreload());
  }

  @override
  Future<void> pause() async {
    await _cancelCrossfade(stopInactive: false);
    try {
      await _inactivePlayer.pause();
    } catch (_) {}
    await _player.pause();
    _setState(PlaybackState.paused);
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
      return;
    }

    if (isLoading || isBuffering || isTrackTransitioning) {
      logger.d(
        '[Audio/Player] Ignoring toggle play intent while track is loading',
      );
      return;
    }

    await play();
  }

  @override
  Future<void> seek(Duration position) async {
    await _cancelCrossfade(stopInactive: true);
    await _player.seek(position);
    _forcePositionUpdate(position);
    _ensureRpcTimer();
    _ensureMprisTimer();
    _updateDiscordPresence(force: true);
    _invalidateCrossfadePreload();
    unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: _currentIndex));
    unawaited(_scheduleNextTrackPreload());
  }

  Future<void> setVolume(double volume) async {
    await _primaryPlayer.setVolume(volume);
    await _secondaryPlayer.setVolume(volume);
    _savedVolume = volume;
    if (volume > 0) {
      _lastVolume = volume;
    }
    await _saveVolumePrefs();
    notifyListeners();
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

  @override
  Future<void> skipToNext() async => skipNext();

  @override
  Future<void> skipToPrevious() async => skipPrevious();

  Future<void> skipNext() async {
    if (_queue.isEmpty) return;
    await _cancelCrossfade(stopInactive: true);
    final token = ++_trackChangeToken;
    if (_playlistPlaybackEnabled && _player.hasNext) {
      final nextIndex = _currentIndex + 1;
      if (nextIndex >= 0 && nextIndex < _queue.length) {
        await _playAtIndex(nextIndex, token: token);
      }
      return;
    }
    await _advanceToNext(token: token);
  }

  Future<void> skipPrevious() async {
    if (_queue.isEmpty) return;
    await _cancelCrossfade(stopInactive: true);
    final token = ++_trackChangeToken;
    if (_playlistPlaybackEnabled && _player.hasPrevious) {
      if (position.inSeconds > 3) {
        await _player.seek(Duration.zero);
        return;
      } else {
        var prevIndex = _currentIndex - 1;
        if (prevIndex < 0) {
          prevIndex = _repeatMode == RepeatMode.all ? _queue.length - 1 : 0;
        }
        if (prevIndex >= 0 && prevIndex < _queue.length) {
          await _playAtIndex(prevIndex, token: token);
        }
      }
      return;
    }
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

  @override
  Future<void> setShuffleMode(
    audio_service.AudioServiceShuffleMode shuffleMode,
  ) async {
    final shouldEnable =
        shuffleMode == audio_service.AudioServiceShuffleMode.all;
    setShuffleEnabled(shouldEnable);
  }

  @override
  Future<void> setRepeatMode(
    audio_service.AudioServiceRepeatMode repeatMode,
  ) async {
    switch (repeatMode) {
      case audio_service.AudioServiceRepeatMode.one:
        setRepeatModeUi(RepeatMode.one);
        await _player.setLoopMode(LoopMode.one);
        break;
      case audio_service.AudioServiceRepeatMode.all:
        setRepeatModeUi(RepeatMode.all);
        await _player.setLoopMode(LoopMode.all);
        break;
      case audio_service.AudioServiceRepeatMode.none:
      default:
        setRepeatModeUi(RepeatMode.off);
        await _player.setLoopMode(LoopMode.off);
        break;
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'toggleShuffle':
        toggleShuffle();
        break;
      case 'toggleRepeat':
        toggleRepeat();
        break;
      default:
        break;
    }
  }

  // PUBLIC API
  Future<void> playTrack(GenericSong track, {bool addToQueue = true}) async {
    final token = ++_trackChangeToken;
    await _cancelCrossfade(stopInactive: true);
    _invalidateCrossfadePreload();
    if (addToQueue && !_queue.any((t) => t.id == track.id)) {
      _queue.add(track);
      _broadcastQueue();
      _invalidatePlaybackPrefetch();
    }
    final index = _queue.indexWhere((t) => t.id == track.id);
    if (index >= 0) {
      await _playAtIndex(index, token: token);
    } else {
      _queue.add(track);
      _broadcastQueue();
      await _playAtIndex(_queue.length - 1, token: token);
    }
  }

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
    // Stop any crossfade and playback before changing queue.
    await _cancelCrossfade(stopInactive: true);
    try {
      await _primaryPlayer.stop();
    } catch (_) {}
    try {
      await _secondaryPlayer.stop();
    } catch (_) {}

    _useSecondaryAsActivePlayer = false;
    
    // Invalidate any preloaded crossfade or prefetched sources since the queue is going to change.
    _invalidateCrossfadePreload();
    _invalidatePlaybackPrefetch(clearSources: true);
    
    // Overwrite the new queue and context info.
    _queue = List.from(tracks);
    _originalQueue = originalQueue ?? [];
    _shuffleEnabled = shuffleEnabled;
    _playbackContextType = contextType;
    _playbackContextName = contextName;
    _playbackContextID = contextID;
    _playbackContextSource = contextSource;
    
    _broadcastQueue();

    if (_queue.isEmpty) {
      _currentIndex = -1;
      _currentTrack = null;
      _invalidatePlaybackPrefetch(clearSources: true);
      _saveQueue();
      notifyListeners();
      return;
    }

    if (play) {
      await _playAtIndex(startIndex.clamp(0, _queue.length - 1), token: token);
    } else {
      _currentIndex = startIndex.clamp(0, _queue.length - 1);
      _currentTrack = _queue[_currentIndex];
      _updateMediaItem();
      _saveQueue();
      notifyListeners();
    }
  }

  void addToQueue(GenericSong track) {
    _queue.add(track);
    _broadcastQueue();
    _saveQueue();
    _invalidateCrossfadePreload();
    _invalidatePlaybackPrefetch();
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) {
      _primaryPlayer.stop();
      _secondaryPlayer.stop();
      _invalidateCrossfadePreload();
      _invalidatePlaybackPrefetch(clearSources: true);
      _currentTrack = null;
      _currentIndex = -1;
      _setState(PlaybackState.idle);
      _clearDiscordPresence();
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
    final removedTrack = _queue[index];
    _queue.removeAt(index);
    _broadcastQueue();
    _saveQueue();
    _invalidateCrossfadePreload();
    _prefetchedAudioSources.remove(removedTrack.id);
    _prefetchSourceTasks.remove(removedTrack.id);
    _invalidatePlaybackPrefetch();
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _currentTrack = null;
    unawaited(_cancelCrossfade(stopInactive: true));
    unawaited(_primaryPlayer.stop());
    unawaited(_secondaryPlayer.stop());
    _useSecondaryAsActivePlayer = false;
    _invalidateCrossfadePreload();
    _invalidatePlaybackPrefetch(clearSources: true);
    _setState(PlaybackState.idle);
    _broadcastQueue();
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
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    _broadcastQueue();
    _saveQueue();
    _invalidateCrossfadePreload();
    _invalidatePlaybackPrefetch();
    notifyListeners();
  }

  /// Set whether this device is the host (requesting) device in a handoff link.
  /// When true, stream URL prefetching for the queue is skipped (playback happens
  /// on the target device). Only the current track is prefetched to smooth unlinking.
  void setIsHandoffHost(bool value) {
    if (_isHandoffHost != value) {
      _isHandoffHost = value;
      if (value) {
        // Clear prefetched sources when entering handoff host mode
        _invalidatePlaybackPrefetch(clearSources: true);
      }
    }
  }

  void toggleShuffle() => setShuffleEnabled(!_shuffleEnabled);

  void setShuffleEnabled(bool enabled) {
    if (_shuffleEnabled == enabled) {
      _broadcastPlaybackState();
      return;
    }

    if (_queue.isEmpty) {
      _shuffleEnabled = enabled;
      _saveQueue();
      notifyListeners();
      _broadcastPlaybackState();
      return;
    }

    // Resolve a stable current track first so queue mutations cannot throw.
    final currentTrack = (_currentIndex >= 0 && _currentIndex < _queue.length)
        ? _queue[_currentIndex]
        : _currentTrack;

    _shuffleEnabled = enabled;
    if (_shuffleEnabled && _queue.length > 1) {
      _originalQueue = List.from(_queue);
      final others = List<GenericSong>.from(_queue);
      if (currentTrack != null) {
        others.removeWhere((track) => track.id == currentTrack.id);
      }
      others.shuffle();
      _queue = currentTrack != null ? [currentTrack, ...others] : others;
      _currentIndex = currentTrack != null ? 0 : 0;
    } else if (!_shuffleEnabled && _originalQueue.isNotEmpty) {
      _queue = List.from(_originalQueue);
      if (currentTrack != null) {
        _currentIndex = _queue.indexWhere((t) => t.id == currentTrack.id);
      } else {
        _currentIndex = 0;
      }
      if (_currentIndex < 0 || _currentIndex >= _queue.length) {
        _currentIndex = 0;
      }
      _originalQueue = [];
    }

    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _currentTrack = _queue[_currentIndex];
    } else {
      _currentTrack = _queue.isNotEmpty ? _queue.first : null;
      _currentIndex = _currentTrack == null ? -1 : 0;
    }

    _broadcastQueue();
    _updateMediaItem();
    _saveQueue();
    notifyListeners();
    _invalidateCrossfadePreload();
    _invalidatePlaybackPrefetch();
    _broadcastPlaybackState();
  }

  void toggleRepeat() {
    final next =
        RepeatMode.values[(_repeatMode.index + 1) % RepeatMode.values.length];
    setRepeatModeUi(next);
  }

  void setRepeatModeUi(RepeatMode mode) {
    if (_repeatMode == mode) {
      _broadcastPlaybackState();
      return;
    }
    _repeatMode = mode;
    _saveQueue();
    notifyListeners();
    _invalidateCrossfadePreload();
    _invalidatePlaybackPrefetch();
    _broadcastPlaybackState();
  }

  // DOWNLOADS
  Future<QueueDownloadResult> downloadTrack(GenericSong track) async {
    final artistNames = track.artists.map((a) => a.name).join(', ');

    return AudioCacheManager.instance.queueDownload(
      trackId: track.id,
      trackTitle: track.title,
      artistName: artistNames,
      resolveAndGetStream: () async {
        final audioSpotifyEnabled =
            await PreferencesProvider.isAudioSpotifyEnabled();
        final audioYouTubeEnabled =
            await PreferencesProvider.isAudioYouTubeEnabled();

        if (!audioSpotifyEnabled && !audioYouTubeEnabled) {
          throw Exception('All audio providers are disabled in Preferences.');
        }

        if (audioSpotifyEnabled &&
            (track.source == SongSource.spotify ||
                track.source == SongSource.spotifyInternal)) {
          final spotify = await _spotifyAudio.resolveStream(track);
          if (spotify != null) {
            if (spotify.mayRequireDecryption && spotify.audioKey != null) {
              final decryptedPath = await _spotifyDecryptor
                  .downloadAndDecryptToTemp(
                    cacheKey: spotify.resolvedId,
                    url: spotify.streamUrl,
                    audioKey: spotify.audioKey!,
                    headers: spotify.requestHeaders,
                  );
              if (decryptedPath != null) {
                return (
                  'dec_${spotify.resolvedId}',
                  Uri.file(decryptedPath).toString(),
                );
              }
            }
            return (spotify.resolvedId, spotify.streamUrl);
          }
        }

        if (!audioYouTubeEnabled) {
          throw Exception('YouTube audio provider is disabled in Preferences.');
        }

        String? videoId = YouTubeProvider.getCachedVideoId(track.id);
        if (videoId == null) {
          final result = await _youtube.searchYouTube(
            artistNames,
            track.title,
            durationSecs: track.durationSecs,
          );
          if (result == null) throw Exception('Could not find video');
          videoId = result.videoId;
          YouTubeProvider.cacheVideoId(track.id, videoId);
        }
        final streamUrl = await _youtube.getStreamUrl(videoId);
        return (videoId, streamUrl);
      },
    );
  }

  Future<Map<QueueDownloadResult, int>> downloadTracks(
    List<GenericSong> tracks,
  ) async {
    final results = <QueueDownloadResult, int>{};
    for (final track in tracks) {
      try {
        final result = await downloadTrack(track);
        results.update(result, (count) => count + 1, ifAbsent: () => 1);
      } catch (_) {}
    }
    return results;
  }

  void cancelDownload(String trackId) =>
      AudioCacheManager.instance.cancelDownload(trackId);

  Future<void> removeFromCache(String trackId) async =>
      AudioCacheManager.instance.removeFromCache(trackId);

  Future<void> onYouTubeAlternativeUpdated(
    String trackId, {
    String? previousVideoId,
  }) async {
    await removeFromCache(trackId);
    _prefetchedAudioSources.remove(trackId);
    _prefetchSourceTasks.remove(trackId);

    if (previousVideoId != null && previousVideoId.isNotEmpty) {
      _streamUrlCache.remove(previousVideoId);
    }

    final updatedVideoId = YouTubeProvider.getCachedVideoId(trackId);
    if (updatedVideoId != null && updatedVideoId.isNotEmpty) {
      _streamUrlCache.remove(updatedVideoId);
    }

    if (_currentTrack?.id != trackId) return;
    await _reloadCurrentTrackSource();
  }

  double? getDownloadProgress(String trackId) =>
      AudioCacheManager.instance.getDownloadProgress(trackId);

  bool isTrackDownloading(String trackId) =>
      AudioCacheManager.instance.isDownloading(trackId);

  // PERSISTENCE
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
        _originalQueue = list
            .map((item) => GenericSong.fromJson(item))
            .toList();
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
      final contextType = prefs.getString('playback_context_type');
      final contextName = prefs.getString('playback_context_name');
      final contextId = prefs.getString('playback_context_id');
      _playbackContextType = contextType?.isNotEmpty == true
          ? contextType
          : null;
      _playbackContextName = contextName?.isNotEmpty == true
          ? contextName
          : null;
      _playbackContextID = contextId?.isNotEmpty == true ? contextId : null;
      final contextSourceRaw = prefs.getString('playback_context_source');
      if (contextSourceRaw != null && contextSourceRaw.isNotEmpty) {
        _playbackContextSource = SongSource.values.firstWhere(
          (e) => e.toString() == contextSourceRaw,
          orElse: () => SongSource.spotify,
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
      _broadcastQueue();
      _updateMediaItem();
      notifyListeners();
    } catch (e) {
      logger.e('[Audio/Player] Load queue error', error: e);
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
      await prefs.setString(
        'playback_context_type',
        _playbackContextType ?? '',
      );
      await prefs.setString(
        'playback_context_name',
        _playbackContextName ?? '',
      );
      await prefs.setString('playback_context_id', _playbackContextID ?? '');
      await prefs.setString(
        'playback_context_source',
        _playbackContextSource?.toString() ?? '',
      );
    } catch (e) {
      logger.e('[Audio/Player] Save queue error', error: e);
    }
  }

  Future<void> _saveVolumePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('player_volume', _player.volume);
      await prefs.setDouble('player_last_volume', _lastVolume);
    } catch (e) {
      logger.e('[Audio/Player] Save volume error', error: e);
    }
  }

  void _updateCrossfadeVolume(Duration position) {
    // Stub: crossfade volume transition logic to be implemented
    // When enabled, will fade out current track and fade in next track
  }

  void _stopCrossfadeTimer() {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
  }

  audio_service.AudioServiceRepeatMode _repeatModeFromString(String value) {
    switch (value) {
      case 'RepeatMode.one':
        return audio_service.AudioServiceRepeatMode.one;
      case 'RepeatMode.all':
        return audio_service.AudioServiceRepeatMode.all;
      case 'RepeatMode.off':
      default:
        return audio_service.AudioServiceRepeatMode.none;
    }
  }

  @override
  Future<void> stop() async {
    _stopCrossfadeTimer();
    await _primaryPlayer.stop();
    await _secondaryPlayer.stop();
    _invalidateCrossfadePreload();
    _setState(PlaybackState.idle);
  }

  @override
  void dispose() {
    _saveVolumePrefs();
    _positionSubscription?.cancel();
    _processingStateSubscription?.cancel();
    _playingSubscription?.cancel();
    _currentIndexSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _stopCrossfadeTimer();
    _stopRpcTimer();
    DiscordRpcService.instance.dispose();
    _primaryPlayer.dispose();
    _secondaryPlayer.dispose();
    _youtube.dispose();
    super.dispose();
  }
}
