import 'dart:collection';

/// A resolved item which the playback engine can play without knowing about
/// Wisp's metadata providers, cache, or queue model.
class PlaybackSource {
  final Uri uri;
  final Map<String, String> headers;
  final Duration? expectedDuration;
  final String debugLabel;

  PlaybackSource({
    required this.uri,
    Map<String, String>? headers,
    this.expectedDuration,
    this.debugLabel = '',
  }) : assert(
         expectedDuration == null || !expectedDuration.isNegative,
         'Expected duration must be non-negative.',
       ),
       headers = UnmodifiableMapView(Map.of(headers ?? const {}));
}

class PlaybackEngineSettings {
  final bool gaplessEnabled;
  final bool crossfadeEnabled;
  final Duration crossfadeDuration;

  PlaybackEngineSettings({
    this.gaplessEnabled = false,
    this.crossfadeEnabled = false,
    this.crossfadeDuration = const Duration(seconds: 3),
  }) : assert(
         !crossfadeDuration.isNegative,
         'Crossfade duration must be non-negative.',
       );

  PlaybackEngineSettings copyWith({
    bool? gaplessEnabled,
    bool? crossfadeEnabled,
    Duration? crossfadeDuration,
  }) => PlaybackEngineSettings(
    gaplessEnabled: gaplessEnabled ?? this.gaplessEnabled,
    crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
    crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
  );
}

/// A playback failure reported by an engine operation or its native backend.
/// The handler can present [message] while retaining [operation] for logs and
/// retry policy without importing a backend-specific exception type.
class PlaybackEngineError {
  final String operation;
  final String message;
  final Object? cause;

  const PlaybackEngineError({
    required this.operation,
    required this.message,
    this.cause,
  });

  @override
  String toString() => '$operation: $message';
}

class PlaybackEngineState {
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final double volume;
  /// The source currently audible (or paused) in the active slot.
  final PlaybackSource? source;
  /// True once a next source has been opened in the private standby slot.
  final PlaybackSource? preloadedSource;
  /// True while a crossfade is running. Commands must be able to cancel it.
  final bool isTransitioning;
  final PlaybackEngineError? error;

  const PlaybackEngineState({
    required this.isPlaying,
    required this.isBuffering,
    required this.position,
    required this.duration,
    required this.volume,
    this.source,
    this.preloadedSource,
    this.isTransitioning = false,
    this.error,
  });

  PlaybackEngineState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    double? volume,
    PlaybackSource? source,
    PlaybackSource? preloadedSource,
    bool? isTransitioning,
    PlaybackEngineError? error,
  }) => PlaybackEngineState(
    isPlaying: isPlaying ?? this.isPlaying,
    isBuffering: isBuffering ?? this.isBuffering,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    volume: volume ?? this.volume,
    source: source ?? this.source,
    preloadedSource: preloadedSource ?? this.preloadedSource,
    isTransitioning: isTransitioning ?? this.isTransitioning,
    error: error ?? this.error,
  );

  static const initial = PlaybackEngineState(
    isPlaying: false,
    isBuffering: false,
    position: Duration.zero,
    duration: Duration.zero,
    volume: 1,
  );
}
