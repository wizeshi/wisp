import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/sources/youtube/youtube_audio.dart';
import 'package:wisp/data/sources/audio/audio_source.dart';

void main() {
  group('YouTubeStreamResult Tests', () {
    test('creates default YouTubeStreamResult with fallback values', () {
      const result = YouTubeStreamResult(url: 'https://rr.googlevideo.com/videoplayback?id=123');
      expect(result.url, 'https://rr.googlevideo.com/videoplayback?id=123');
      expect(result.format, 'm4a');
      expect(result.bitrate, 160);
    });

    test('creates custom YouTubeStreamResult with opus format and custom bitrate', () {
      const result = YouTubeStreamResult(
        url: 'https://rr.googlevideo.com/videoplayback?id=456',
        format: 'opus',
        bitrate: 251,
      );
      expect(result.url, 'https://rr.googlevideo.com/videoplayback?id=456');
      expect(result.format, 'opus');
      expect(result.bitrate, 251);
    });

    test('AudioStreamResult maps format and bitrate accurately', () {
      const stream = YouTubeStreamResult(
        url: 'https://rr.googlevideo.com/videoplayback?id=789',
        format: 'opus',
        bitrate: 160,
      );

      final audioResult = AudioStreamResult(
        url: stream.url,
        headers: {'User-Agent': 'test-agent'},
        format: stream.format,
        bitrate: stream.bitrate,
        expiresAt: DateTime.now().add(const Duration(hours: 4)),
      );

      expect(audioResult.format, 'opus');
      expect(audioResult.bitrate, 160);
      expect(audioResult.url, stream.url);
    });
  });
}

