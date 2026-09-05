import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:wisp_audio_output_info/models/types.dart';
import 'package:wisp_audio_output_info/wisp_audio_output_info.dart';

import 'playback_engine.dart';
import 'playback_models.dart';

void log(String message) {
  if (kDebugMode) {
    print('[MediaKitPlaybackEngine]: $message');
  }
  return;
}

/// A two-slot MediaKit engine. The inactive slot is private so callers cannot
/// accidentally disrupt a preload or a transition.
class MediaKitPlaybackEngine implements WispPlaybackEngine {
  late final Player _first;
  late final Player _second;
  late Player _active;
  late Player _standby;

  PlaybackEngineSettings _settings;
  PlaybackEngineState _state = PlaybackEngineState.initial;
  PlaybackSource? _preloadedSource;
  PlaybackSource? _activeSource;
  PlaybackEngineError? _lastError;
  double _volume = 1;
  bool _disposed = false;
  int _transitionGeneration = 0;
  bool _isTransitioning = false;
  Future<void> _operations = Future.value();

  // While a crossfade is running, `_active`/`_standby` still refer to the
  // outgoing/incoming *players* (they only swap once the fade physically
  // finishes, since that's when it's safe to reuse the outgoing slot for
  // the next preload). But callers should see position/duration/source for
  // the incoming track from the moment the fade starts, not from whenever
  // the swap happens — otherwise `state` keeps reporting the outgoing
  // track's numbers for the entire crossfade window, which makes it look
  // like nothing has changed until the fade finishes. `_reportingPlayer`
  // and `_fadeOutgoingSource` let `_publishState()`/`_cancelTransition()`
  // report (and restore, on abort) the correct track independently of
  // when the underlying slot swap actually occurs.
  Player? _reportingPlayer;
  PlaybackSource? _fadeOutgoingSource;

  final _states = StreamController<PlaybackEngineState>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  MediaKitPlaybackEngine({
    PlaybackEngineSettings? settings,
  }) : _settings = settings ?? PlaybackEngineSettings() {
    MediaKit.ensureInitialized();
    
    log('[MediaKitPlaybackEngine]: initialized with settings: $_settings');
    
    _first = Player();
    _second = Player();
    _active = _first;
    _standby = _second;

    _listenToPlayers();
  }

  @override
  PlaybackEngineSettings get settings => _settings;

  @override
  PlaybackEngineState get state => _state;

  @override
  Stream<PlaybackEngineState> get states => _states.stream;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<List<AudioOutputDevice>> get outputDevices => WispAudioOutputInfo.outputDevices;

  @override
  Stream<AudioOutputDevice?> get activeOutputDevice => WispAudioOutputInfo.activeOutputDevice;

  @override
  Future<void> updateSettings(PlaybackEngineSettings settings) =>
      _enqueue(() async {
        _settings = settings;
        if (!settings.crossfadeEnabled && _preloadedSource != null) {
          // Keep a gapless preload when requested, but discard a crossfade-only
          // standby player so it cannot unexpectedly start later.
          if (!settings.gaplessEnabled) {
            await _standby.stop();
            _preloadedSource = null;
          }
        }
        _publishState();
      });

  @override
  Future<void> loadCurrent(
    PlaybackSource source, {
    Duration position = Duration.zero,
    bool play = false,
  }) {
    _cancelTransition();
    return _enqueue(() async {
      try {
        _isTransitioning = false;
        _preloadedSource = null;
        _activeSource = source;
        await _standby.stop();
        await _active.open(_media(source), play: false);
        await _active.setVolume(_volume * 100);
        if (position > Duration.zero) await _active.seek(position);
        if (play) await _active.play();
        _lastError = null;
        _publishState();
      } catch (error) {
        _publishFailure('loadCurrent', error);
        rethrow;
      }
    });
  }

  @override
  Future<void> preloadNext(PlaybackSource source) => _enqueue(() async {
        if (!_settings.gaplessEnabled && !_settings.crossfadeEnabled) return;
        try {
          await _standby.open(_media(source), play: false);
          await _standby.setVolume(
            _settings.crossfadeEnabled ? 0 : _volume * 100,
          );
          _preloadedSource = source;
          _lastError = null;
          _publishState();
        } catch (error) {
          _publishFailure('preloadNext', error);
          rethrow;
        }
      });

  @override
  Future<void> clearPreload() {
    _cancelTransition();
    return _enqueue(() async {
      _isTransitioning = false;
      _preloadedSource = null;
      await _standby.stop();
      _publishState();
    });
  }

  @override
  Future<void> transitionToPreloaded({bool play = true}) => _enqueue(() async {
        if (_preloadedSource == null) return;

        try {
          final shouldFade = _settings.crossfadeEnabled &&
              _settings.crossfadeDuration > Duration.zero &&
              _active.state.playing &&
              play;
          final incomingSource = _preloadedSource!;

          if (shouldFade) {
            // The fade is starting now: as far as callers are concerned the
            // incoming track is "current" from this instant, even though
            // internally we keep fading the outgoing player in the
            // background under the old `_active` reference until the fade
            // completes and the slots swap.
            _fadeOutgoingSource = _activeSource;
            _reportingPlayer = _standby;
            _activeSource = incomingSource;
          }
          _isTransitioning = shouldFade;
          _publishState();

          if (shouldFade) {
            if (!await _crossfade()) return;
          } else {
            await _active.stop();
            _swapSlots();
            await _active.setVolume(_volume * 100);
            if (play) await _active.play();
            _activeSource = incomingSource;
          }
          _preloadedSource = null;
          _isTransitioning = false;
          _reportingPlayer = null;
          _fadeOutgoingSource = null;
          _lastError = null;
          _publishState();
        } catch (error) {
          _isTransitioning = false;
          _reportingPlayer = null;
          _fadeOutgoingSource = null;
          _publishFailure('transitionToPreloaded', error);
          rethrow;
        }
      });

  @override
  Future<void> play() => _enqueue(() async {
        try {
          await _active.play();
          _lastError = null;
          _publishState();
        } catch (error) {
          _publishFailure('play', error);
          rethrow;
        }
      });

  @override
  Future<void> pause() {
    _cancelTransition();
    return _enqueue(() async {
      await _active.pause();
      _publishState();
    });
  }

  @override
  Future<void> seek(Duration position) {
    _cancelTransition();
    return _enqueue(() async {
      await _active.seek(position);
      _publishState();
    });
  }

  @override
  Future<void> setVolume(double volume) => _enqueue(() async {
    _volume = volume.clamp(0, 1).toDouble();
    await Future.wait([
      _active.setVolume(_volume * 100),
      if (_preloadedSource != null) _standby.setVolume(_volume * 100),
    ]);
    _publishState();
  });

  @override
  Future<void> setOutputDevice(String deviceId) => _enqueue(() async {
    log('[MediaKitPlaybackEngine] setOutputDevice: $deviceId');

    log('[MediaKitPlaybackEngine] _first.state.audioDevices: ${_first.state.audioDevices.map((d) => d.name).toList()}');

    unawaited((() async {
      final audioDevices = await (_first.platform as NativePlayer).getProperty('audio-device-list');
      log('[MediaKitPlaybackEngine] mpv inner state: ${audioDevices}');
    })());

    String filteredDeviceId = deviceId;

    if (Platform.isWindows) {
      filteredDeviceId = "wasapi/${deviceId.split('.').last}";
    }

    final device = _first.state.audioDevices
        .where((candidate) => candidate.name == filteredDeviceId)
        .firstOrNull;
    if (device == null) {
      throw ArgumentError.value(filteredDeviceId, 'deviceId', 'Unknown audio device');
    }
    // Both slots must use the same route or a crossfade can split between
    // hardware outputs.
    await _first.setAudioDevice(device);
    await _second.setAudioDevice(device);
  });

  @override
  Future<void> stop() {
    _cancelTransition();
    return _enqueue(() async {
      _isTransitioning = false;
      _preloadedSource = null;
      _activeSource = null;
      await Future.wait([_first.stop(), _second.stop()]);
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _operations.catchError((_) {});
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await Future.wait([_first.dispose(), _second.dispose()]);
    await _states.close();
    await _completed.close();
  }

  Future<bool> _crossfade() async {
    final outgoing = _active;
    final incoming = _standby;
    await incoming.setVolume(0);
    final generation = ++_transitionGeneration;
    await incoming.play();

    const frame = Duration(milliseconds: 32);
    final frames = (_settings.crossfadeDuration.inMilliseconds /
            frame.inMilliseconds)
        .ceil()
        .clamp(1, 10000);
    final frameCount = frames.toInt();
    for (var frameIndex = 1; frameIndex <= frameCount; frameIndex++) {
      if (generation != _transitionGeneration || _disposed) {
        return _abortCrossfade(outgoing, incoming);
      }
      final progress = frameIndex / frameCount;
      await Future.wait([
        outgoing.setVolume((1 - progress) * _volume * 100),
        incoming.setVolume(progress * _volume * 100),
      ]);
      if (frameIndex < frameCount) await Future<void>.delayed(frame);
    }
    if (generation != _transitionGeneration || _disposed) {
      return _abortCrossfade(outgoing, incoming);
    }
    await outgoing.stop();
    _swapSlots();
    // `_active` now *is* the former incoming player, so the reporting
    // override is no longer needed — `_active` alone is accurate again.
    _reportingPlayer = null;
    _fadeOutgoingSource = null;
    await _active.setVolume(_volume * 100);
    return true;
  }

  void _cancelTransition() {
    _transitionGeneration++;
    _isTransitioning = false;
    if (_reportingPlayer != null) {
      // A fade was reporting the incoming track as active; since it's being
      // cancelled before the slots ever swapped, the outgoing track is
      // still the one genuinely playing (or about to be paused/stopped/
      // seeked by whichever command triggered this cancellation), so put
      // the reported source back.
      _reportingPlayer = null;
      _activeSource = _fadeOutgoingSource;
      _fadeOutgoingSource = null;
    }
  }

  Future<bool> _abortCrossfade(Player outgoing, Player incoming) async {
    // A command can invalidate a fade while its operation is still awaiting
    // a native volume update. Restore the source that remains active before
    // the queued command (pause, seek, stop, or load) is allowed to run.
    await Future.wait([
      outgoing.setVolume(_volume * 100),
      incoming.stop(),
    ]);
    _isTransitioning = false;
    _reportingPlayer = null;
    _activeSource = _fadeOutgoingSource ?? _activeSource;
    _fadeOutgoingSource = null;
    _publishState();
    return false;
  }

  void _swapSlots() {
    final previous = _active;
    _active = _standby;
    _standby = previous;
    _publishState();
  }

  Media _media(PlaybackSource source) => Media(
    source.uri.toString(),
    httpHeaders: source.headers.isEmpty ? null : source.headers,
  );

  void _listenToPlayers() {
    for (final player in [_first, _second]) {
      _subscriptions.add(player.stream.playing.listen((_) => _publishState()));
      _subscriptions.add(player.stream.buffering.listen((_) => _publishState()));
      _subscriptions.add(player.stream.position.listen((_) => _publishState()));
      _subscriptions.add(player.stream.duration.listen((_) => _publishState()));
      _subscriptions.add(player.stream.completed.listen((didComplete) {
        if (didComplete && identical(player, _active) && !_disposed) {
          _completed.add(null);
        }
      }));
      _subscriptions.add(player.stream.error.listen((error) {
        if (identical(player, _active)) {
          _publishFailure('nativePlayback', error);
        }
      }));
    }
  }

  void _publishFailure(String operation, Object error) {
    _lastError = PlaybackEngineError(
      operation: operation,
      message: error.toString(),
      cause: error,
    );
    _publishState();
  }

  void _publishState() {
    if (_disposed) return;
    // During a crossfade this is the incoming player, so position/duration/
    // isPlaying line up with `_activeSource` (also already flipped to the
    // incoming track) instead of lagging behind until the slots swap.
    final reportingPlayer = _reportingPlayer ?? _active;
    _state = PlaybackEngineState(
      isPlaying: reportingPlayer.state.playing,
      isBuffering: reportingPlayer.state.buffering,
      position: reportingPlayer.state.position,
      duration: _reportedDuration(reportingPlayer),
      volume: _volume,
      source: _activeSource,
      preloadedSource: _preloadedSource,
      isTransitioning: _isTransitioning,
      error: _lastError,
    );
    _states.add(_state);
  }

  Duration _reportedDuration(Player player) {
    final actual = player.state.duration;
    final expected = _activeSource?.expectedDuration;
    if (expected == null || expected <= Duration.zero) return actual;
    // Some native decoders report an inflated duration for HE-AAC. Metadata
    // is a safer upper bound, while a genuinely shorter native duration is
    // retained so callers can still detect truncated streams.
    if (actual <= Duration.zero || actual > expected) return expected;
    return actual;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operations.then((_) {
      if (_disposed) throw StateError('Playback engine has been disposed');
      return action();
    });
    _operations = next.catchError((_) {});
    return next;
  }
}