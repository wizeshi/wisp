// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp_audio_output_info/models/types.dart';
import 'package:wisp_playback_engine/wisp_playback_engine.dart';

import '../models/metadata_models.dart';
import '../services/cache_manager.dart';
import '../services/discord_rpc_service.dart';
import '../utils/logger.dart';
import '../providers/audio/youtube.dart';
import '../providers/preferences/preferences_provider.dart';
import '../services/connect/connect_models.dart';

enum PlaybackState {
  idle,
  loading,
  playing,
  paused,
  error;

  String toJson() => name;

  static PlaybackState fromJson(String json) {
    return PlaybackState.values.firstWhere(
      (e) => e.name == json,
      orElse: () => PlaybackState.idle,
    );
  }
}

enum RepeatMode {
  off,
  all,
  one;

  String toJson() => name;

  static RepeatMode fromJson(String json) {
    return RepeatMode.values.firstWhere(
      (e) => e.name == json,
      orElse: () => RepeatMode.off,
    );
  }
}

class _StreamUrlCacheEntry {
  final String url;
  final DateTime expiresAt;

  _StreamUrlCacheEntry({required this.url, required this.expiresAt});

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class WispAudioHandler extends audio_service.BaseAudioHandler
    with ChangeNotifier {
  final WispPlaybackEngine _engine;
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
  bool _gaplessPlaybackEnabled = false;
  bool _crossfadeEnabled = false;
  double _crossfadeDurationSeconds = 3.0;

  // Playback context
  String? _playbackContextType;
  String? _playbackContextName;
  String? _playbackContextID;
  SongSource? _playbackContextSource;

  // Mirrors the engine's own PlaybackEngineState so getters stay cheap and
  // synchronous. This handler never reaches into the engine's players —
  // only into this cached snapshot and `_engine.state`/public methods.
  double _engineVolume = 1.0;
  bool _engineIsPlaying = false;
  bool _engineIsBuffering = false;
  bool _engineIsTransitioning = false;
  PlaybackEngineError? _lastEngineError;
  List<AudioOutputDevice> _availableOutputDevices = const [];
  AudioOutputDevice? _activeOutputDevice;

  // Preload bookkeeping. Unlike the old handler, this is index/track
  // bookkeeping only — the engine owns whatever slots/players it needs to
  // actually hold the preloaded audio.
  int _preloadGeneration = 0;
  bool _isPreloadInProgress = false;
  int? _preloadedNextIndex;
  GenericSong? _preloadedNextTrack;
  String? _lastFailedPreloadTrackId;
  int _lastPreloadFailureMs = 0;
  static const Duration _preloadRetryCooldown = Duration(seconds: 2);

  // Explicit "the user asked to pause" intent. A position tick from the
  // engine can arrive just as pause() is being processed; without this a
  // late crossfade-transition check could ignore the pause and start
  // transitioning into the next track anyway.
  bool _userPaused = false;

  // Subscriptions
  StreamSubscription<PlaybackEngineState>? _engineStateSubscription;
  StreamSubscription<void>? _engineCompletedSubscription;
  StreamSubscription<List<AudioOutputDevice>>? _outputDevicesSubscription;
  StreamSubscription<AudioOutputDevice?>? _activeOutputDeviceSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _rpcTimer;
  Timer? _mprisTimer;
  int _rpcLastSecond = -1;

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
  // Set while _prepareCurrentTrackOnStartup() is in-flight so that play()
  // can wait for it instead of racing to call loadCurrent() concurrently.
  Future<void>? _startupPrepareFuture;
  bool _isHandlingCompletion = false;
  bool _isTrackTransitioning = false;

  static const int _prefetchWindowSize = 5;
  int _prefetchGeneration = 0;
  final Map<String, PlaybackSource> _prefetchedSources = {};
  final Map<String, Future<PlaybackSource?>> _prefetchSourceTasks = {};
  final Map<String, _StreamUrlCacheEntry> _streamUrlCache = {};
  // In-flight tasks to avoid duplicate resolver requests for same id
  final Map<String, Future<String>> _streamUrlTasks = {};
  final Map<String, Future<String?>> _videoIdTasks = {};

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
  Duration get position => _engine.state.position;
  Duration get throttledPosition => _lastNotifiedPosition;
  Duration get interpolatedPosition => _getInterpolatedPosition();
  Duration get duration => _isHandoffHost
      ? (_lastKnownDuration ?? _engine.state.duration)
      : (_engine.state.duration > Duration.zero
            ? _engine.state.duration
            : _lastKnownDuration ?? Duration.zero);
  double get volume => _engineVolume;
  double get userVolume => _savedVolume ?? _lastVolume;
  bool get isOnline => _isOnline;
  String? get errorMessage => _errorMessage;
  String? get playbackContextType => _playbackContextType;
  String? get playbackContextName => _playbackContextName;
  String? get playbackContextID => _playbackContextID;
  SongSource? get playbackContextSource => _playbackContextSource;
  List<AudioOutputDevice> get outputDevices => _availableOutputDevices;
  AudioOutputDevice? get activeOutputDevice => _activeOutputDevice;

  ConnectPlaybackSnapshot buildConnectSnapshot() {
    return ConnectPlaybackSnapshot(
      queue: List<GenericSong>.from(_queue),
      originalQueue: List<GenericSong>.from(_originalQueue),
      currentIndex: _currentIndex,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      isPlaying: isPlaying,
      shuffleEnabled: _shuffleEnabled,
      repeatMode: _repeatMode.toString(),
      contextType: _playbackContextType,
      contextName: _playbackContextName,
      contextId: _playbackContextID,
      contextSource: _playbackContextSource,
      volume: _engineVolume,
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
      '[Handoff] WispAudioHandler.applyConnectSnapshot: applied snapshot currentIndex=$_currentIndex isPlaying=$isPlaying positionMs=${position.inMilliseconds}',
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
        '[Handoff] WispAudioHandler.applyPassiveConnectSnapshot: applied passive snapshot updated currentIndex=$_currentIndex isPlaying=$isPlaying',
      );
    }
  }

  /// Applies a delta (partial state update) to reduce unnecessary reloads.
  /// Only updates fields that are present in the delta.
  Future<void> applyDelta(ConnectStateDelta delta) async {
    bool changed = false;

    if (delta.positionMs != null) {
      final targetPosition = Duration(milliseconds: delta.positionMs!);
      await seek(targetPosition);
      changed = true;
    }

    if (delta.currentIndex != null) {
      if (delta.currentIndex != _currentIndex &&
          delta.currentIndex! >= 0 &&
          delta.currentIndex! < _queue.length) {
        await skipToQueueItem(delta.currentIndex!);
        changed = true;
      }
    }

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

    if (delta.shuffleEnabled != null) {
      if (delta.shuffleEnabled != _shuffleEnabled) {
        setShuffleEnabled(delta.shuffleEnabled!);
        changed = true;
      }
    }

    if (delta.repeatMode != null) {
      final mode = _repeatModeFromString(delta.repeatMode!);
      if (mode != _repeatMode) {
        await setRepeatMode(mode);
        changed = true;
      }
    }

    if (delta.queue != null) {
      await setQueue(
        delta.queue!,
        startIndex:
            delta.currentIndex ??
            _currentIndex.clamp(0, delta.queue!.length - 1),
        play: delta.isPlaying ?? isPlaying,
      );
      changed = true;
    }

    if (delta.volume != null) {
      await setVolume(delta.volume!.clamp(0.0, 1.0));
      changed = true;
    }

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

  WispAudioHandler({WispPlaybackEngine? engine})
    : _engine = engine ?? MediaKitPlaybackEngine() {
    _init();
  }

  Future<void> _init() async {
    await _configureAudioSession();
    await _loadQueue();
    await YouTubeProvider.loadVideoIdCache();
    _gaplessPlaybackEnabled =
        await PreferencesProvider.isGaplessPlaybackEnabled();
    _crossfadeEnabled = await PreferencesProvider.isCrossfadeEnabled();
    _crossfadeDurationSeconds =
        await PreferencesProvider.isCrossfadeDurationSeconds();
    await _engine.updateSettings(_buildEngineSettings());
    _attachEngineListeners();

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
      await _engine.setVolume(initialVolume);
      if (initialVolume > 0) {
        _lastVolume = initialVolume;
      }
    }

    _startupPrepareFuture = _prepareCurrentTrackOnStartup();
    try {
      await _startupPrepareFuture;
    } finally {
      _startupPrepareFuture = null;
    }
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  PlaybackEngineSettings _buildEngineSettings() => PlaybackEngineSettings(
    gaplessEnabled: _gaplessPlaybackEnabled,
    crossfadeEnabled: _crossfadeEnabled,
    crossfadeDuration: Duration(
      milliseconds: (_crossfadeDurationSeconds * 1000).round(),
    ),
  );

  // ENGINE WIRING
  //
  // Everything below this point is the only place this handler looks at the
  // engine's stream of state. There is no volume ramp, no second player, and
  // no fade timer here — those live inside whichever WispPlaybackEngine is
  // injected. This handler just reacts to state (for UI/session/RPC) and
  // decides, based on queue position, when to call preloadNext() and
  // transitionToPreloaded().
  void _attachEngineListeners() {
    _engineStateSubscription?.cancel();
    _engineCompletedSubscription?.cancel();
    _outputDevicesSubscription?.cancel();
    _activeOutputDeviceSubscription?.cancel();

    _engineStateSubscription = _engine.states.listen(
      _handleEngineState,
      onError: (Object e, StackTrace st) {
        logger.e('[Audio/Engine] state stream error', error: e, stackTrace: st);
      },
    );

    // The engine only emits this when the active source finishes on its
    // own. If a crossfade already moved us onto the next source ahead of
    // time, this simply won't fire for the track that got faded out.
    _engineCompletedSubscription = _engine.completed.listen((_) {
      _onCompleted();
    });

    _outputDevicesSubscription = _engine.outputDevices.listen((devices) {
      print("[Audio/Player] output devices: $devices");

      _availableOutputDevices = devices;
      notifyListeners();
    });

    _activeOutputDeviceSubscription = _engine.activeOutputDevice.listen((
      device,
    ) {
      _activeOutputDevice = device;
      notifyListeners();
    });
  }

  void _handleEngineState(PlaybackEngineState engineState) {
    _engineVolume = engineState.volume;
    _engineIsTransitioning = engineState.isTransitioning;
    _engineIsBuffering = engineState.isBuffering;
    _engineIsPlaying = engineState.isPlaying;

    if (engineState.duration > Duration.zero) {
      _lastKnownDuration = engineState.duration;
    }

    if (engineState.error != null && !identical(engineState.error, _lastEngineError)) {
      _lastEngineError = engineState.error;
      logger.e('[Audio/Engine] ${engineState.error}');
      _errorMessage = engineState.error!.message;
      _setState(PlaybackState.error);
      _setTrackTransitioning(false);
    }

    _handlePositionUpdate(engineState.position);
    _handleRpcPositionTick();

    // Don't let a mid-transition buffering/playing blip flip our
    // higher-level state — _transitionToNext()/_loadTrackAtIndex() already
    // own state transitions while a transition/load is in flight.
    if (!_engineIsTransitioning && !_isTrackTransitioning && _currentTrack != null) {
      if (_engineIsBuffering) {
        _setState(PlaybackState.loading);
      } else if (_engineIsPlaying) {
        _setState(PlaybackState.playing);
      } else if (_state == PlaybackState.playing ||
          _state == PlaybackState.loading) {
        _setState(PlaybackState.paused);
      }
    }

    _broadcastPlaybackState();

    if (!_engineIsTransitioning) {
      unawaited(
        _maybeSchedulePreload(engineState.position, engineState.duration),
      );
      if (_crossfadeEnabled) {
        unawaited(
          _maybeStartCrossfadeTransition(
            engineState.position,
            engineState.duration,
          ),
        );
      }
    }
  }

  void _handlePositionUpdate(Duration position) {
    _lastRawPosition = position;
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

  void _handleRpcPositionTick() {
    if (_currentTrack == null) return;
    if (!isPlaying) return;
    final seconds = position.inSeconds;
    if (seconds != _rpcLastSecond) {
      _rpcLastSecond = seconds;
      _updateDiscordPresence();
    }
  }

  void _handleMprisTick() {
    if (_currentTrack == null) return;
    if (!isPlaying) return;
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

  // PRELOAD + TRANSITION SCHEDULING
  //
  // This is the "queue owner" half of the crossfade contract: decide what
  // the next track is and when it's time to switch to it. The engine does
  // the actual mixing once transitionToPreloaded() is called.
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

  void _clearPreloadBookkeeping() {
    _preloadGeneration++;
    _preloadedNextIndex = null;
    _preloadedNextTrack = null;
  }

  bool _isPreloadReady(int nextIndex, GenericSong nextTrack) {
    return _preloadedNextIndex == nextIndex &&
        _preloadedNextTrack?.id == nextTrack.id &&
        _engine.state.preloadedSource != null;
  }

  Future<bool> _waitForPreloadReady(
    int nextIndex,
    GenericSong nextTrack, {
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 150),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_isPreloadReady(nextIndex, nextTrack)) return true;
      await Future.delayed(pollInterval);
    }
    return _isPreloadReady(nextIndex, nextTrack);
  }

  Future<void> _maybeSchedulePreload(
    Duration position,
    Duration trackDuration,
  ) async {
    if (!_playlistPlaybackEnabled || _currentTrack == null) return;
    if (trackDuration <= Duration.zero) return;

    final crossfadeWindow = Duration(
      milliseconds: (_crossfadeDurationSeconds * 1000).round(),
    );
    final preloadLead = _crossfadeEnabled
        ? crossfadeWindow + const Duration(seconds: 10)
        : const Duration(seconds: 10);
    final remaining = trackDuration - position;
    if (remaining > preloadLead) return;

    final nextIndex = _nextQueueIndex();
    if (nextIndex == null) return;
    final nextTrack = _queue[nextIndex];

    if (_isPreloadReady(nextIndex, nextTrack)) return;
    if (_isPreloadInProgress) return;
    if (_lastFailedPreloadTrackId == nextTrack.id &&
        DateTime.now().millisecondsSinceEpoch - _lastPreloadFailureMs <
            _preloadRetryCooldown.inMilliseconds) {
      return;
    }

    unawaited(_scheduleNextTrackPreload());
  }

  Future<void> _scheduleNextTrackPreload() async {
    if (!_playlistPlaybackEnabled || _queue.isEmpty || _currentIndex < 0) {
      return;
    }
    if (_isPreloadInProgress) return;

    final nextIndex = _nextQueueIndex();
    if (nextIndex == null) {
      _clearPreloadBookkeeping();
      unawaited(_engine.clearPreload());
      return;
    }

    final generation = ++_preloadGeneration;
    final trackChangeToken = _trackChangeToken;
    final nextTrack = _queue[nextIndex];

    if (_lastFailedPreloadTrackId == nextTrack.id &&
        DateTime.now().millisecondsSinceEpoch - _lastPreloadFailureMs <
            _preloadRetryCooldown.inMilliseconds) {
      return;
    }

    _preloadedNextIndex = nextIndex;
    _preloadedNextTrack = nextTrack;
    _isPreloadInProgress = true;

    try {
      final source = await _getPlaybackSourceWithRetry(nextTrack);
      if (source == null) {
        throw Exception('Could not get audio source for ${nextTrack.title}');
      }

      // Validate before handing anything to the engine — a track change or
      // queue mutation may have made this preload stale while we awaited
      // network I/O above.
      final stillValid =
          generation == _preloadGeneration &&
          trackChangeToken == _trackChangeToken &&
          _preloadedNextIndex == nextIndex &&
          _preloadedNextTrack?.id == nextTrack.id;
      if (!stillValid) return;

      await _engine.preloadNext(source);
      _lastFailedPreloadTrackId = null;
    } catch (e) {
      logger.w('[Audio/Player] Preload failed', error: e);
      _clearPreloadBookkeeping();
      _lastFailedPreloadTrackId = nextTrack.id;
      _lastPreloadFailureMs = DateTime.now().millisecondsSinceEpoch;
      unawaited(_engine.clearPreload());
    } finally {
      _isPreloadInProgress = false;
    }
  }

  Future<void> _maybeStartCrossfadeTransition(
    Duration position,
    Duration trackDuration,
  ) async {
    if (_isTrackTransitioning || _engineIsTransitioning) return;
    if (!_crossfadeEnabled || _currentTrack == null || _userPaused) return;
    if (trackDuration <= Duration.zero) return;

    final crossfadeWindow = Duration(
      milliseconds: (_crossfadeDurationSeconds * 1000).round(),
    );
    if (trackDuration <= crossfadeWindow) return;

    const startLead = Duration(milliseconds: 600);
    final remaining = trackDuration - position;
    if (remaining > crossfadeWindow + startLead) return;

    final nextIndex = _nextQueueIndex();
    if (nextIndex == null) return;
    final nextTrack = _queue[nextIndex];

    if (!_isPreloadReady(nextIndex, nextTrack)) {
      _preloadedNextIndex = nextIndex;
      _preloadedNextTrack = nextTrack;
      await _scheduleNextTrackPreload();
      if (!await _waitForPreloadReady(nextIndex, nextTrack)) return;
    }

    if (_engineIsTransitioning || _userPaused) return;
    await _transitionToNext();
  }

  /// Asks the engine to swap onto whatever it already has preloaded. All
  /// fading (or the lack of it, for gapless) happens inside the engine.
  ///
  /// The next track is *already preloaded* by the time this is called (both
  /// callers verify that via `_isPreloadReady`), so as far as the UI/session
  /// is concerned the swap is effectively immediate — the engine is fading
  /// into it right now. We update our bookkeeping synchronously up front
  /// instead of waiting on `_engine.transitionToPreloaded()` to resolve:
  /// that future's completion is tied to the engine's own fade/output
  /// lifecycle and isn't a reliable signal for "the new track is now
  /// current" — gating the UI update on it is what caused the old bug
  /// where the player bar would flicker toward the next track, revert to
  /// the outgoing one, and only actually switch once the outgoing track's
  /// full duration had elapsed.
  ///
  /// Because nothing here is a real load (the source is already buffered),
  /// we deliberately do NOT flip `_isTrackTransitioning` — that flag exists
  /// for genuine hard loads in `_loadTrackAtIndex()` where the UI should
  /// show a spinner while waiting on network/buffering. A crossfade/gapless
  /// swap has nothing to spin for.
  Future<void> _transitionToNext({int? token}) async {
    final nextIndex = _preloadedNextIndex;
    final nextTrack = _preloadedNextTrack;
    if (nextIndex == null || nextTrack == null) return;

    final requestToken = token ?? ++_trackChangeToken;

    // Clear + commit bookkeeping immediately (and before any `await`) so a
    // second, concurrently-triggered call to this method sees
    // `_preloadedNextIndex == null` and bails out at the guard above,
    // rather than racing on the engine call below.
    _preloadedNextIndex = null;
    _preloadedNextTrack = null;
    _currentIndex = nextIndex;
    _currentTrack = nextTrack;
    _errorMessage = null;
    _updateMediaItem();
    _setState(PlaybackState.playing);
    _broadcastPlaybackState();
    _ensureRpcTimer();
    _ensureMprisTimer();
    _updateDiscordPresence(force: true);
    _saveQueue();
    _queueCaching(nextTrack);
    notifyListeners();
    unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: nextIndex));
    unawaited(_scheduleNextTrackPreload());

    try {
      await _engine.transitionToPreloaded(play: true);
    } catch (e) {
      logger.w('[Audio/Player] Transition to preloaded track failed', error: e);
      // We've already committed to the new track in the UI/session — the
      // engine call failing after the fade has visually/audibly started is
      // an engine-level playback error, not a reason to snap the UI back
      // to the track that's already fading out.
      if (requestToken == _trackChangeToken) {
        _errorMessage = e.toString();
        _setState(PlaybackState.error);
      }
    }
  }

  Future<void> setGaplessPlaybackEnabled(bool enabled) async {
    if (_gaplessPlaybackEnabled == enabled) return;
    _gaplessPlaybackEnabled = enabled;
    await _engine.updateSettings(_buildEngineSettings());
    if (_playlistPlaybackEnabled) {
      unawaited(_scheduleNextTrackPreload());
    } else {
      _clearPreloadBookkeeping();
      unawaited(_engine.clearPreload());
    }
    notifyListeners();
  }

  Future<void> setCrossfadeEnabled(bool enabled) async {
    if (_crossfadeEnabled == enabled) return;
    _crossfadeEnabled = enabled;
    await _engine.updateSettings(_buildEngineSettings());
    if (_playlistPlaybackEnabled) {
      unawaited(_scheduleNextTrackPreload());
    } else {
      _clearPreloadBookkeeping();
      unawaited(_engine.clearPreload());
    }
    notifyListeners();
  }

  Future<void> setCrossfadeDurationSeconds(double seconds) async {
    final normalized = seconds.clamp(1.0, 6.0).toDouble();
    if (_crossfadeDurationSeconds == normalized) return;
    _crossfadeDurationSeconds = normalized;
    await _engine.updateSettings(_buildEngineSettings());
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
    if (_state == PlaybackState.error) {
      return audio_service.AudioProcessingState.error;
    }
    if (isLoading) {
      return audio_service.AudioProcessingState.loading;
    }
    if (_state == PlaybackState.idle) {
      return audio_service.AudioProcessingState.idle;
    }
    if (_engineIsBuffering) {
      return audio_service.AudioProcessingState.buffering;
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

  /// Handle track completion. This only fires for a source that reached its
  /// natural end without us pre-empting it with a transition — i.e. gapless
  /// mode (where the swap happens right at the end instead of early), no
  /// special mode at all, or a crossfade whose preload wasn't ready in time.
  void _onCompleted() {
    if (_isHandlingCompletion) return;
    if (_engineIsTransitioning || _isTrackTransitioning) return;

    _isHandlingCompletion = true;
    final token = _trackChangeToken;
    () async {
      logger.i('[Audio/Player] Track completed: ${_currentTrack?.title}');

      if (_repeatMode == RepeatMode.one) {
        await _engine.seek(Duration.zero);
        if (token != _trackChangeToken) return;
        await _engine.play();
        return;
      }

      if (_playlistPlaybackEnabled && _queue.isNotEmpty) {
        final nextIndex = _nextQueueIndex();
        if (nextIndex != null) {
          final nextTrack = _queue[nextIndex];
          if (_isPreloadReady(nextIndex, nextTrack)) {
            await _transitionToNext(token: token);
            return;
          }

          unawaited(_scheduleNextTrackPreload());
          if (await _waitForPreloadReady(nextIndex, nextTrack)) {
            if (token != _trackChangeToken) return;
            await _transitionToNext(token: token);
            return;
          }
        }
      }

      if (_queue.isNotEmpty) {
        await _advanceToNext(token: token);
      } else {
        _setState(PlaybackState.idle);
      }
    }().whenComplete(() {
      _isHandlingCompletion = false;
    });
  }

  Future<void> _prepareCurrentTrackOnStartup() async {
    if (_currentTrack == null || _engine.state.source != null) return;
    try {
      await _loadTrackAtIndex(_currentIndex < 0 ? 0 : _currentIndex, play: false);
      unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: _currentIndex));
      unawaited(_scheduleNextTrackPreload());
    } catch (e) {
      logger.w('[Audio/Player] Startup prepare failed', error: e);
    }
  }

  Future<void> _schedulePlaybackPrefetchWindow({int? anchorIndex}) async {
    if (_queue.isEmpty) return;

    final currentIndex = anchorIndex ?? _currentIndex;
    if (currentIndex < 0 || currentIndex >= _queue.length) return;

    // When in handoff host mode, only prefetch the current track (for smooth
    // unlinking). Skip prefetching the full window since playback happens
    // on the target device.
    if (_isHandoffHost) {
      final track = _queue[currentIndex];
      if (!_prefetchedSources.containsKey(track.id) &&
          !_prefetchSourceTasks.containsKey(track.id)) {
        final generation = _prefetchGeneration;
        final task = _prefetchTrackSource(track, generation);
        _prefetchSourceTasks[track.id] = task;
        final source = await task;
        _prefetchSourceTasks.remove(track.id);
        if (generation != _prefetchGeneration) return;
        if (source != null) {
          _prefetchedSources[track.id] = source;
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

    final keepIds = <String>{for (final index in indices) _queue[index].id};
    _prefetchedSources.removeWhere((trackId, _) => !keepIds.contains(trackId));

    for (final index in indices) {
      if (generation != _prefetchGeneration) return;
      final track = _queue[index];
      if (_prefetchedSources.containsKey(track.id) ||
          _prefetchSourceTasks.containsKey(track.id)) {
        continue;
      }

      final task = _prefetchTrackSource(track, generation);
      _prefetchSourceTasks[track.id] = task;
      final source = await task;
      _prefetchSourceTasks.remove(track.id);
      if (generation != _prefetchGeneration) return;
      if (source != null) {
        _prefetchedSources[track.id] = source;
      }
    }
  }

  Future<PlaybackSource?> _prefetchTrackSource(
    GenericSong track,
    int generation,
  ) async {
    if (!_isOnline) return null;

    try {
      final source = await _getPlaybackSource(track, allowPrefetched: false);
      if (generation != _prefetchGeneration) return null;
      return source;
    } catch (e) {
      logger.w('[Audio/Player] Failed to prefetch track source', error: e);
      return null;
    }
  }

  void _invalidatePlaybackPrefetch({bool clearSources = false}) {
    _prefetchGeneration++;
    _prefetchSourceTasks.clear();
    if (clearSources) {
      _prefetchedSources.clear();
    }
  }

  /// Loads `_queue[index]` as the engine's current (active) source. This
  /// replaces the old handler's `_playAtIndex`/`_loadPlaylistPlayback` split
  /// — with a single-active-slot engine API there is no separate "playlist"
  /// vs "single track" load path any more.
  Future<void> _loadTrackAtIndex(
    int index, {
    required bool play,
    Duration position = Duration.zero,
    int? token,
  }) async {
    if (_queue.isEmpty) return;
    final requestToken = token ?? ++_trackChangeToken;
    final safeIndex = index.clamp(0, _queue.length - 1);
    final track = _queue[safeIndex];

    logger.i(
      '[Audio/Player] Loading [${safeIndex + 1}/${_queue.length}]: ${track.title}',
    );

    _currentIndex = safeIndex;
    _currentTrack = track;
    _errorMessage = null;
    _clearPreloadBookkeeping();
    unawaited(_engine.clearPreload());
    _setTrackTransitioning(true);
    _setState(PlaybackState.loading);
    _updateMediaItem();

    try {
      final source = await _getPlaybackSourceWithRetry(track);
      if (requestToken != _trackChangeToken) return;
      if (source == null) {
        throw Exception('Could not get audio source for ${track.title}');
      }

      await _engine.loadCurrent(source, position: position, play: play);
      if (requestToken != _trackChangeToken) return;

      _currentIndex = safeIndex;
      _currentTrack = track;
      _forcePositionUpdate(position);
      _setState(play ? PlaybackState.playing : PlaybackState.paused);
      _broadcastPlaybackState();
      if (play) {
        _ensureRpcTimer();
        _ensureMprisTimer();
      } else {
        _stopMprisTimer();
      }
      _updateDiscordPresence(force: true);
      _saveQueue();
      _queueCaching(track);
      notifyListeners();
      unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: safeIndex));
      unawaited(_scheduleNextTrackPreload());
    } catch (e) {
      logger.e('[Audio/Player] Track load error', error: e);
      _errorMessage = e.toString();
      _setState(PlaybackState.error);

      if (safeIndex < _queue.length - 1) {
        await Future.delayed(const Duration(seconds: 2));
        if (_state == PlaybackState.error && requestToken == _trackChangeToken) {
          await _advanceToNext();
        }
      }
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

    await _loadTrackAtIndex(nextIndex, play: true, token: token ?? ++_trackChangeToken);
  }

  Future<void> _reloadCurrentTrackSource() async {
    final track = _currentTrack;
    if (track == null) return;
    final wasPlaying = _engineIsPlaying;
    final targetPosition = _engine.state.position;
    await _loadTrackAtIndex(_currentIndex, play: wasPlaying, position: targetPosition);
  }

  bool _shouldRefreshSourceOnLoadError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('403') ||
        message.contains('forbidden') ||
        message.contains('expired');
  }

  Future<void> _invalidateTrackSourceCaches(GenericSong track) async {
    _prefetchedSources.remove(track.id);
    _prefetchSourceTasks.remove(track.id);

    final cachedVideoId = YouTubeProvider.getCachedVideoId(track.id);
    if (cachedVideoId != null && cachedVideoId.isNotEmpty) {
      _streamUrlCache.remove(cachedVideoId);
    }
  }

  Future<PlaybackSource?> _getPlaybackSourceWithRetry(
    GenericSong track, {
    bool allowPrefetched = true,
  }) async {
    try {
      return await _getPlaybackSource(track, allowPrefetched: allowPrefetched);
    } catch (e) {
      if (!_shouldRefreshSourceOnLoadError(e)) {
        rethrow;
      }

      await _invalidateTrackSourceCaches(track);
      return await _getPlaybackSource(track, allowPrefetched: false);
    }
  }

  Future<PlaybackSource?> _getPlaybackSource(
    GenericSong track, {
    bool allowPrefetched = true,
  }) async {
    if (allowPrefetched) {
      final prefetched = _prefetchedSources[track.id];
      if (prefetched != null) {
        return prefetched;
      }
    }

    final cacheManager = AudioCacheManager.instance;
    final audioYouTubeEnabled =
        await PreferencesProvider.isAudioYouTubeEnabled();

    if (!audioYouTubeEnabled) {
      throw Exception('All audio providers are disabled in Preferences.');
    }

    final expectedDuration = track.durationSecs > 0
        ? Duration(seconds: track.durationSecs)
        : null;

    final cachedPath = cacheManager.getCachedPath(track.id);
    if (cachedPath != null && File(cachedPath).existsSync()) {
      await cacheManager.updateLastPlayed(track.id);
      return PlaybackSource(
        uri: Uri.file(cachedPath),
        expectedDuration: expectedDuration,
        debugLabel: track.title,
      );
    }

    if (!_isOnline) {
      throw Exception('Offline and track not cached');
    }

    String? videoId = YouTubeProvider.getCachedVideoId(track.id);
    videoId ??= await _getVideoIdForTrack(track);
    if (videoId == null) return null;

    final streamUrl = await _getStreamUrlWithCache(videoId);

    // Must match YouTubeProvider.userAgentForPlatform() — this is the same
    // client identity used to validate the URL, so playback and validation
    // agree.
    final userAgent = YouTubeProvider.userAgentForPlatform();

    // Note: unlike the old just_audio-based path, there's no per-platform
    // ClippingAudioSource workaround for inflated HE-AAC durations here —
    // the engine already clips a suspiciously-long reported duration
    // against `expectedDuration` (see PlaybackSource.expectedDuration and
    // the engine's own duration-reporting logic) for every platform.
    return PlaybackSource(
      uri: Uri.parse(streamUrl),
      headers: {'User-Agent': userAgent},
      expectedDuration: expectedDuration,
      debugLabel: track.title,
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

    final audioYouTubeEnabled =
        await PreferencesProvider.isAudioYouTubeEnabled();
    if (!audioYouTubeEnabled) return;

    final cacheManager = AudioCacheManager.instance;
    if (cacheManager.isTrackCached(track.id)) {
      return;
    }

    String? videoId = YouTubeProvider.getCachedVideoId(track.id);
    if (videoId != null && _getCachedStreamUrl(videoId) != null) return;

    try {
      videoId ??= await _getVideoIdForTrack(track);
      if (videoId == null) return;

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
        final audioYouTubeEnabled =
            await PreferencesProvider.isAudioYouTubeEnabled();

        if (!audioYouTubeEnabled) {
          throw Exception('All audio providers are disabled in Preferences.');
        }

        String? videoId = YouTubeProvider.getCachedVideoId(track.id);
        videoId ??= await _getVideoIdForTrack(track);
        if (videoId == null) throw Exception('Could not find video');
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

    var task = _streamUrlTasks[videoId];
    if (task != null) return await task;

    final completer = Completer<String>();
    _streamUrlTasks[videoId] = completer.future;
    try {
      final streamUrl = await _youtube.getStreamUrl(videoId);
      _streamUrlCache[videoId] = _StreamUrlCacheEntry(
        url: streamUrl,
        expiresAt: DateTime.now().add(_streamUrlTtl),
      );
      completer.complete(streamUrl);
      return streamUrl;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _streamUrlTasks.remove(videoId);
    }
  }

  Future<String?> _getVideoIdForTrack(GenericSong track) async {
    var task = _videoIdTasks[track.id];
    if (task != null) return await task;

    final completer = Completer<String?>();
    _videoIdTasks[track.id] = completer.future;
    try {
      final artistNames = track.artists.map((a) => a.name).join(', ');
      final result = await _youtube.searchYouTube(
        artistNames,
        track.title,
        durationSecs: track.durationSecs,
      );
      final videoId = result?.videoId;
      if (videoId != null) {
        YouTubeProvider.cacheVideoId(track.id, videoId);
      }
      completer.complete(videoId);
      return videoId;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _videoIdTasks.remove(track.id);
    }
  }

  Future<void> _updateDiscordPresence({bool force = false}) async {
    final track = _currentTrack;
    if (track == null) {
      await _clearDiscordPresence();
      return;
    }

    if (force) {
      _rpcLastSecond = position.inSeconds;
    }

    await DiscordRpcService.instance.updatePresence(
      track: track,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
      contextId: _playbackContextID,
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

  // AUDIO_SERVICE OVERRIDES
  @override
  Future<void> play() async {
    _userPaused = false;

    if (isLoading || isBuffering || isTrackTransitioning) {
      logger.d('[Audio/Player] Ignoring play intent while track is loading');
      return;
    }

    // If the startup source-prepare is still running, wait for it before
    // checking whether we need to load a source ourselves. Without this,
    // both _prepareCurrentTrackOnStartup() and play() can race to call
    // loadCurrent() concurrently.
    if (_engine.state.source == null && _currentTrack != null) {
      final startupFuture = _startupPrepareFuture;
      if (startupFuture != null) {
        await startupFuture;
      }
    }

    if (_engine.state.source == null && _currentTrack != null) {
      final requestToken = ++_trackChangeToken;
      await _loadTrackAtIndex(
        _currentIndex < 0 ? 0 : _currentIndex,
        play: true,
        token: requestToken,
      );
      return;
    }

    try {
      await _engine.play();
    } catch (e) {
      _errorMessage = e.toString();
      _setState(PlaybackState.error);
      return;
    }
    _ensureRpcTimer();
    _ensureMprisTimer();
    _updateDiscordPresence(force: true);
    unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: _currentIndex));
    unawaited(_scheduleNextTrackPreload());
  }

  @override
  Future<void> pause() async {
    _userPaused = true;
    try {
      await _engine.pause();
    } catch (_) {}
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
    await _engine.seek(position);
    _forcePositionUpdate(position);
    _ensureRpcTimer();
    _ensureMprisTimer();
    _updateDiscordPresence(force: true);
    _clearPreloadBookkeeping();
    unawaited(_engine.clearPreload());
    unawaited(_schedulePlaybackPrefetchWindow(anchorIndex: _currentIndex));
    unawaited(_scheduleNextTrackPreload());
  }

  Future<void> setVolume(double volume) async {
    await _engine.setVolume(volume);
    _savedVolume = volume;
    if (volume > 0) {
      _lastVolume = volume;
    }
    await _saveVolumePrefs();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    final current = _engineVolume;
    if (current == 0) {
      final restore = _lastVolume <= 0 ? 1.0 : _lastVolume.clamp(0.0, 1.0);
      await setVolume(restore);
    } else {
      _lastVolume = current;
      await setVolume(0);
    }
  }

  Future<void> setOutputDevice(String deviceId) =>
      _engine.setOutputDevice(deviceId);

  @override
  Future<void> skipToNext() async => skipNext();

  @override
  Future<void> skipToPrevious() async => skipPrevious();

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final token = ++_trackChangeToken;
    await _loadTrackAtIndex(index, play: true, token: token);
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
      await seek(Duration.zero);
      return;
    }
    int prevIndex = _currentIndex - 1;
    if (prevIndex < 0) {
      prevIndex = _repeatMode == RepeatMode.all ? _queue.length - 1 : 0;
    }
    await _loadTrackAtIndex(prevIndex, play: true, token: token);
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
        break;
      case audio_service.AudioServiceRepeatMode.all:
        setRepeatModeUi(RepeatMode.all);
        break;
      case audio_service.AudioServiceRepeatMode.none:
      default:
        setRepeatModeUi(RepeatMode.off);
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
    _clearPreloadBookkeeping();
    unawaited(_engine.clearPreload());
    if (addToQueue && !_queue.any((t) => t.id == track.id)) {
      _queue.add(track);
      _broadcastQueue();
      _invalidatePlaybackPrefetch();
    }
    final index = _queue.indexWhere((t) => t.id == track.id);
    if (index >= 0) {
      await _loadTrackAtIndex(index, play: true, token: token);
    } else {
      _queue.add(track);
      _broadcastQueue();
      await _loadTrackAtIndex(_queue.length - 1, play: true, token: token);
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
    try {
      await _engine.stop();
    } catch (_) {}
    _clearPreloadBookkeeping();
    _invalidatePlaybackPrefetch(clearSources: true);

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
      _saveQueue();
      notifyListeners();
      return;
    }

    if (play) {
      await _loadTrackAtIndex(
        startIndex.clamp(0, _queue.length - 1),
        play: true,
        token: token,
      );
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
    _clearPreloadBookkeeping();
    unawaited(_engine.clearPreload());
    _invalidatePlaybackPrefetch();
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) {
      unawaited(_engine.stop());
      _clearPreloadBookkeeping();
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
    _clearPreloadBookkeeping();
    unawaited(_engine.clearPreload());
    _prefetchedSources.remove(removedTrack.id);
    _prefetchSourceTasks.remove(removedTrack.id);
    _invalidatePlaybackPrefetch();
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _currentTrack = null;
    unawaited(_engine.stop());
    _clearPreloadBookkeeping();
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
    _clearPreloadBookkeeping();
    unawaited(_engine.clearPreload());
    _invalidatePlaybackPrefetch();
    notifyListeners();
  }

  /// Set whether this device is the host (requesting) device in a handoff
  /// link. When true, stream URL prefetching for the queue is skipped
  /// (playback happens on the target device). Only the current track is
  /// prefetched to smooth unlinking.
  void setIsHandoffHost(bool value) {
    if (_isHandoffHost != value) {
      _isHandoffHost = value;
      if (value) {
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
      _currentIndex = 0;
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
    _clearPreloadBookkeeping();
    unawaited(_engine.clearPreload());
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
    _clearPreloadBookkeeping();
    unawaited(_engine.clearPreload());
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
        final audioYouTubeEnabled =
            await PreferencesProvider.isAudioYouTubeEnabled();

        if (!audioYouTubeEnabled) {
          throw Exception('All audio providers are disabled in Preferences.');
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
    _prefetchedSources.remove(trackId);
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
      await prefs.setDouble('player_volume', _engineVolume);
      await prefs.setDouble('player_last_volume', _lastVolume);
    } catch (e) {
      logger.e('[Audio/Player] Save volume error', error: e);
    }
  }

  Map<String, dynamic> dumpInfo() {
    final engineState = _engine.state;
    return {
      'state': _state.toJson(),
      'isPlaying': isPlaying,
      'isLoading': isLoading,
      'isBuffering': isBuffering,
      'isOnline': _isOnline,
      'errorMessage': _errorMessage,
      'currentTrack': _currentTrack?.toJson(),
      'queue': _queue.map((track) => track.toJson()).toList(),
      'originalQueue': _originalQueue.map((track) => track.toJson()).toList(),
      'currentIndex': _currentIndex,
      'trackChangeToken': _trackChangeToken,
      'shuffleEnabled': _shuffleEnabled,
      'repeatMode': _repeatMode.toString(),
      'gaplessPlaybackEnabled': _gaplessPlaybackEnabled,
      'crossfadeEnabled': _crossfadeEnabled,
      'crossfadeDurationSeconds': _crossfadeDurationSeconds,
      'isTrackTransitioning': _isTrackTransitioning,
      'preloadedNextIndex': _preloadedNextIndex,
      'preloadedNextTrack': _preloadedNextTrack?.toJson(),
      'isPreloadInProgress': _isPreloadInProgress,
      'preloadGeneration': _preloadGeneration,
      'engine': {
        'isPlaying': engineState.isPlaying,
        'isBuffering': engineState.isBuffering,
        'positionMs': engineState.position.inMilliseconds,
        'durationMs': engineState.duration.inMilliseconds,
        'volume': engineState.volume,
        'sourceUri': engineState.source?.uri.toString(),
        'preloadedSourceUri': engineState.preloadedSource?.uri.toString(),
        'isTransitioning': engineState.isTransitioning,
        'error': engineState.error?.toString(),
      },
      'savedVolume': _savedVolume,
      'lastVolume': _lastVolume,
      'lastRawPositionMs': _lastRawPosition.inMilliseconds,
      'lastNotifiedPositionMs': _lastNotifiedPosition.inMilliseconds,
      'lastPositionNotifyMs': _lastPositionNotifyMs,
      'lastPositionUpdateMs': _lastPositionUpdateMs,
      'lastKnownDurationMs': _lastKnownDuration?.inMilliseconds,
      'rpcLastSecond': _rpcLastSecond,
      'playlistPlaybackEnabled': _playlistPlaybackEnabled,
      'playbackContextType': _playbackContextType,
      'playbackContextName': _playbackContextName,
      'playbackContextID': _playbackContextID,
      'playbackContextSource': _playbackContextSource?.toString(),
      'isHandoffHost': _isHandoffHost,
      'prefetchWindowSize': _prefetchWindowSize,
      'prefetchGeneration': _prefetchGeneration,
      'prefetchedSources': _prefetchedSources.keys.toList(),
      'prefetchSourceTasks': _prefetchSourceTasks.keys.toList(),
      'streamUrlCache': _streamUrlCache.map(
        (key, value) => MapEntry(key, {
          'url': value.url,
          'expiresAt': value.expiresAt.toIso8601String(),
          'isValid': value.isValid,
        }),
      ),
      'streamUrlTasks': _streamUrlTasks.keys.toList(),
      'videoIdTasks': _videoIdTasks.keys.toList(),
      'outputDevices': _availableOutputDevices
          .map((d) => {'id': d.id, 'name': d.name})
          .toList(),
      'activeOutputDevice': _activeOutputDevice == null
          ? null
          : {'id': _activeOutputDevice!.id, 'name': _activeOutputDevice!.name},
      'subscriptions': {
        'engineState': _engineStateSubscription != null,
        'engineCompleted': _engineCompletedSubscription != null,
        'outputDevices': _outputDevicesSubscription != null,
        'activeOutputDevice': _activeOutputDeviceSubscription != null,
        'connectivity': _connectivitySubscription != null,
      },
      'timers': {'rpc': _rpcTimer != null, 'mpris': _mprisTimer != null},
    };
  }

  @override
  Future<void> stop() async {
    await _engine.stop();
    _clearPreloadBookkeeping();
    _setState(PlaybackState.idle);
  }

  @override
  void dispose() {
    _saveVolumePrefs();
    _engineStateSubscription?.cancel();
    _engineCompletedSubscription?.cancel();
    _outputDevicesSubscription?.cancel();
    _activeOutputDeviceSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _stopRpcTimer();
    _stopMprisTimer();
    DiscordRpcService.instance.dispose();
    unawaited(_engine.dispose());
    _youtube.dispose();
    super.dispose();
  }
}