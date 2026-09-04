import 'playback_models.dart';

/// Backend-neutral playback contract. Queue and handoff code deliberately do
/// not see the two players used to implement a crossfade.
abstract interface class WispPlaybackEngine {
  PlaybackEngineSettings get settings;
  PlaybackEngineState get state;
  Stream<PlaybackEngineState> get states;
  /// Emits when the active source finishes naturally. The queue owner decides
  /// whether that means repeat, advance, or stop.
  Stream<void> get completed;
  Stream<List<PlaybackOutputDevice>> get outputDevices;
  Stream<PlaybackOutputDevice?> get activeOutputDevice;

  Future<void> updateSettings(PlaybackEngineSettings settings);
  Future<void> loadCurrent(PlaybackSource source, {
    Duration position = Duration.zero,
    bool play = false,
  });
  Future<void> preloadNext(PlaybackSource source);
  /// Cancels any prepared next source and any active crossfade.
  Future<void> clearPreload();
  Future<void> transitionToPreloaded({bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setOutputDevice(String deviceId);
  Future<void> stop();
  Future<void> dispose();
}
