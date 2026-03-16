/// Background-capable audio handler with queue management.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
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
  final AudioPlayer _player = AudioPlayer();
  final YouTubeProvider _youtube = YouTubeProvider();
  final SpotifyAudioProvider _spotifyAudio = SpotifyAudioProvider();
  final SpotifyAudioDecryptor _spotifyDecryptor = const SpotifyAudioDecryptor();
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
  static const Duration _streamUrlTtl = Duration(minutes: 15);
  Duration _lastRawPosition = Duration.zero;
  Duration _lastNotifiedPosition = Duration.zero;
  int _lastPositionNotifyMs = 0;
  int _lastPositionUpdateMs = 0;
  int _lastMediaPositionMs = -1;
  int _lastMediaUpdateMs = 0;

  int _trackChangeToken = 0;
  bool _isHandlingCompletion = false;
  final Map<String, _StreamUrlCacheEntry> _streamUrlCache = {};

  // Getters
  PlaybackState get state => _state;
  GenericSong? get currentTrack => _currentTrack;
  List<GenericSong> get queueTracks => List.unmodifiable(_queue);
  List<GenericSong> get originalQueueTracks =>
      List.unmodifiable(_originalQueue);
  int get currentIndex => _currentIndex;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  bool get isPlaying => _state == PlaybackState.playing;
  bool get isLoading => _state == PlaybackState.loading;
  bool get isBuffering => _state == PlaybackState.loading;
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

  ConnectPlaybackSnapshot buildConnectSnapshot() {
    return ConnectPlaybackSnapshot(
      queue: List<GenericSong>.from(_queue),
      originalQueue: List<GenericSong>.from(_originalQueue),
      currentIndex: _currentIndex,
      positionMs: _player.position.inMilliseconds,
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
  }

  bool isTrackCached(String trackId) =>
      AudioCacheManager.instance.isTrackCached(trackId);

  WispAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    await _loadQueue();
    await YouTubeProvider.loadVideoIdCache();

    _processingStateSubscription = _player.processingStateStream.listen((
      state,
    ) {
      if (state == ProcessingState.completed) {
        _onCompleted();
      } else if (state == ProcessingState.loading ||
          state == ProcessingState.buffering) {
        _setState(PlaybackState.loading);
      } else if (state == ProcessingState.ready) {
        if (_player.playing) {
          _setState(PlaybackState.playing);
        } else if (_state != PlaybackState.idle) {
          _setState(PlaybackState.paused);
        }
      }
      _broadcastPlaybackState();
    });

    _playingSubscription = _player.playingStream.listen((playing) {
      if (_player.processingState == ProcessingState.ready) {
        _setState(playing ? PlaybackState.playing : PlaybackState.paused);
      }
      _broadcastPlaybackState();
    });

    _positionSubscription = _player.positionStream.listen((position) {
      _handlePositionUpdate(position);
      _handleRpcPositionTick();
    });

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
    _isHandlingCompletion = true;
    final token = _trackChangeToken;
    () async {
      logger.i('[Player] Track completed: ${_currentTrack?.title}');

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

  Future<void> _playAtIndex(int index, {int? token}) async {
    if (index < 0 || index >= _queue.length) return;
    final requestToken = token ?? ++_trackChangeToken;

    final track = _queue[index];
    logger.i(
      '[Player] Playing [${index + 1}/${_queue.length}]: ${track.title}',
    );

    _currentIndex = index;
    _currentTrack = track;
    _errorMessage = null;
    _setState(PlaybackState.loading);
    _updateMediaItem();

    try {
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

      _broadcastPlaybackState();
      _ensureRpcTimer();
      _updateDiscordPresence(force: true);
      _saveQueue();
      _queueCaching(track);
    } catch (e) {
      logger.e('[Player] Error', error: e);
      _errorMessage = e.toString();
      _setState(PlaybackState.error);

      if (_currentIndex < _queue.length - 1) {
        await Future.delayed(const Duration(seconds: 2));
        if (_state == PlaybackState.error) {
          await _advanceToNext();
        }
      }
    }
  }

  Future<AudioSource?> _getAudioSource(GenericSong track) async {
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
      logger.d('[Player] From cache');
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
              logger.d('[Player] Streaming decrypted Spotify via local proxy');
              return AudioSource.uri(proxyUri);
            } catch (error) {
              logger.w(
                '[Player] Spotify decrypt proxy unavailable, falling back',
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
              logger.d('[Player] Playing decrypted Spotify temp file');
              return AudioSource.file(decryptedPath);
            }
            logger.w(
              '[Player] Spotify decrypt temp fallback failed, trying raw stream',
            );
          }

          logger.d('[Player] Streaming from Spotify');
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
          '[Player] Spotify stream unavailable, falling back to YouTube',
        );
      } catch (e) {
        logger.w(
          '[Player] Spotify stream failed, falling back to YouTube',
          error: e,
        );
      }
    }

    if (!audioYouTubeEnabled) {
      throw Exception('YouTube audio provider is disabled in Preferences.');
    }

    String? videoId = YouTubeProvider.getCachedVideoId(track.id);
    if (videoId == null) {
      final artistNames = track.artists.map((a) => a.name).join(', ');
      final result = await _youtube.searchYouTube(artistNames, track.title);
      if (result == null) return null;
      videoId = result.videoId;
      YouTubeProvider.cacheVideoId(track.id, videoId);
    }

    logger.d('[Player] Streaming from YouTube');
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
          logger.d('[Player] Pre-resolved Spotify URL: ${track.title}');
          return;
        }
      } catch (e) {
        logger.w('[Player] Failed to pre-resolve Spotify URL', error: e);
      }
    }

    if (!audioYouTubeEnabled) {
      return;
    }

    String? videoId = YouTubeProvider.getCachedVideoId(track.id);
    if (videoId != null && _getCachedStreamUrl(videoId) != null) return;

    try {
      final artistNames = track.artists.map((a) => a.name).join(', ');
      if (videoId == null) {
        final result = await _youtube.searchYouTube(artistNames, track.title);
        if (result == null) return;
        videoId = result.videoId;
        YouTubeProvider.cacheVideoId(track.id, videoId);
      }

      await _getStreamUrlWithCache(videoId);
      logger.d('[Player] Pre-resolved next track URL: ${track.title}');
    } catch (e) {
      logger.w('[Player] Failed to pre-resolve next track', error: e);
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

        String? videoId = YouTubeProvider.getCachedVideoId(track.id);
        if (videoId == null) {
          final result = await _youtube.searchYouTube(artistNames, track.title);
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
        ? 'drawable/ic_repeat_on'
        : 'drawable/ic_repeat_off';
    return audio_service.MediaControl.custom(
      androidIcon: icon,
      label: 'Repeat',
      name: 'toggleRepeat',
    );
  }

  // AUDIO_SERVICE OVERRIDES
  @override
  Future<void> play() async {
    if (_player.audioSource == null && _currentTrack != null) {
      _errorMessage = null;
      _setState(PlaybackState.loading);
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

  @override
  Future<void> pause() async {
    await _player.pause();
    _ensureRpcTimer();
    _stopMprisTimer();
    _updateDiscordPresence(force: true);
  }

  Future<void> togglePlayPause() async => isPlaying ? pause() : play();

  @override
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
    if (addToQueue && !_queue.any((t) => t.id == track.id)) {
      _queue.add(track);
      _broadcastQueue();
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
    _broadcastQueue();
    _saveQueue();
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _currentTrack = null;
    _player.stop();
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
    notifyListeners();
  }

  void toggleShuffle() => setShuffleEnabled(!_shuffleEnabled);

  void setShuffleEnabled(bool enabled) {
    if (_shuffleEnabled == enabled) {
      _broadcastPlaybackState();
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
    _broadcastQueue();
    _saveQueue();
    notifyListeners();
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
    _broadcastPlaybackState();
  }

  // DOWNLOADS
  Future<void> downloadTrack(GenericSong track) async {
    final artistNames = track.artists.map((a) => a.name).join(', ');

    await AudioCacheManager.instance.queueDownload(
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
          final result = await _youtube.searchYouTube(artistNames, track.title);
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
    await _player.stop();
    _setState(PlaybackState.idle);
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
