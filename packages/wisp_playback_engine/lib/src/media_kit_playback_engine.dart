import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'playback_engine.dart';
import 'playback_models.dart';

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

  final _states = StreamController<PlaybackEngineState>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _outputDevices =
      StreamController<List<PlaybackOutputDevice>>.broadcast();
  final _activeOutputDevice =
      StreamController<PlaybackOutputDevice?>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  MediaKitPlaybackEngine({
    PlaybackEngineSettings? settings,
  }) : _settings = settings ?? PlaybackEngineSettings() {
    MediaKit.ensureInitialized();
    _first = Player();
    _second = Player();
    _active = _first;
    _standby = _second;
    _listenToPlayers();
    _publishOutputDevices(_first.state.audioDevices);
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
  Stream<List<PlaybackOutputDevice>> get outputDevices => _outputDevices.stream;

  @override
  Stream<PlaybackOutputDevice?> get activeOutputDevice =>
      _activeOutputDevice.stream;

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
          _isTransitioning = shouldFade;
          _publishState();
          if (shouldFade) {
            if (!await _crossfade()) return;
          } else {
            await _active.stop();
            _swapSlots();
            await _active.setVolume(_volume * 100);
            if (play) await _active.play();
          }
          _preloadedSource = null;
          _isTransitioning = false;
          _activeSource = incomingSource;
          _lastError = null;
          _publishState();
        } catch (error) {
          _isTransitioning = false;
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
    final device = _first.state.audioDevices
        .where((candidate) => candidate.name == deviceId)
        .firstOrNull;
    if (device == null) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Unknown audio device');
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
    await _outputDevices.close();
    await _activeOutputDevice.close();
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
    await _active.setVolume(_volume * 100);
    return true;
  }

  void _cancelTransition() {
    _transitionGeneration++;
    _isTransitioning = false;
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
      _subscriptions.add(player.stream.audioDevices.listen(_publishOutputDevices));
      _subscriptions.add(player.stream.audioDevice.listen((device) {
        if (!identical(player, _active)) return;
        _activeOutputDevice.add(_toOutputDevice(device));
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
    _state = PlaybackEngineState(
      isPlaying: _active.state.playing,
      isBuffering: _active.state.buffering,
      position: _active.state.position,
      duration: _reportedDuration(),
      volume: _volume,
      source: _activeSource,
      preloadedSource: _preloadedSource,
      isTransitioning: _isTransitioning,
      error: _lastError,
    );
    _states.add(_state);
  }

  Duration _reportedDuration() {
    final actual = _active.state.duration;
    final expected = _activeSource?.expectedDuration;
    if (expected == null || expected <= Duration.zero) return actual;
    // Some native decoders report an inflated duration for HE-AAC. Metadata
    // is a safer upper bound, while a genuinely shorter native duration is
    // retained so callers can still detect truncated streams.
    if (actual <= Duration.zero || actual > expected) return expected;
    return actual;
  }

  void _publishOutputDevices(List<AudioDevice> devices) {
    if (_disposed) return;
    _outputDevices.add(devices.map(_toOutputDevice).toList(growable: false));
  }

  PlaybackOutputDevice _toOutputDevice(AudioDevice device) =>
      PlaybackOutputDevice(
        id: device.name,
        name: device.description.isEmpty ? device.name : device.description,
      );

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operations.then((_) {
      if (_disposed) throw StateError('Playback engine has been disposed');
      return action();
    });
    _operations = next.catchError((_) {});
    return next;
  }
}
