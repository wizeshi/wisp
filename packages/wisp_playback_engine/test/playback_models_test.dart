import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_playback_engine/wisp_playback_engine.dart';

void main() {
  group('PlaybackEngineState equality', () {
    test('treats identical state snapshots as equal', () {
      final source = PlaybackSource(
        uri: Uri.parse('https://example.com/audio.m4a'),
        debugLabel: 'track-1',
      );
      final a = PlaybackEngineState(
        isPlaying: true,
        isBuffering: false,
        position: const Duration(seconds: 12),
        bufferedPosition: const Duration(seconds: 30),
        duration: const Duration(minutes: 3),
        volume: 0.85,
        source: source,
        audioBitrate: 256,
        audioSampleRate: 48000,
      );
      final b = PlaybackEngineState(
        isPlaying: true,
        isBuffering: false,
        position: const Duration(seconds: 12),
        bufferedPosition: const Duration(seconds: 30),
        duration: const Duration(minutes: 3),
        volume: 0.85,
        source: source,
        audioBitrate: 256,
        audioSampleRate: 48000,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('distinguishes states when any tracked field changes', () {
      final base = PlaybackEngineState.initial;
      expect(base.copyWith(isPlaying: true), isNot(equals(base)));
      expect(
        base.copyWith(position: const Duration(milliseconds: 250)),
        isNot(equals(base)),
      );
      expect(base.copyWith(volume: 0.5), isNot(equals(base)));
    });
  });
}
