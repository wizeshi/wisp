// Copyright © 2026 wizeshi

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/custom_lyrics_storage.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationCachePath() async => tempDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final storage = CustomLyricsStorage.instance;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('wisp_custom_lyrics_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);
  });

  tearDownAll(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('CustomLyricsStorage Tests', () {
    final songA = GenericSong(
      id: 'spotify:track:4cOdK2wGLETKBW3PvgPWqT',
      title: 'Never Gonna Give You Up',
      artists: [
        GenericSimpleArtist(
          id: '1',
          name: 'Rick Astley',
          source: 'spotify',
          thumbnailUrl: '',
        ),
      ],
      source: 'spotify',
      thumbnailUrl: '',
      durationSecs: 213,
      explicit: false,
    );

    const ttmlSample = '''<tt xmlns="http://www.w3.org/ns/ttml">
  <body>
    <div>
      <p begin="00:00:01.000" end="00:00:05.000">
        <span begin="00:00:01.000" end="00:00:03.000">Never </span>
        <span begin="00:00:03.000" end="00:00:05.000">gonna</span>
      </p>
    </div>
  </body>
</tt>''';

    test('saves custom lyrics and updates synchronous index', () async {
      await storage.initialize();

      expect(storage.hasCustomLyricsSync(songA), isFalse);

      final result = await storage.saveCustomLyrics(
        song: songA,
        ttmlContent: ttmlSample,
      );

      expect(result.syncMode, equals(LyricsSyncMode.word));
      expect(result.lines.length, equals(1));
      expect(storage.hasCustomLyricsSync(songA), isTrue);

      final retrieved = await storage.getCustomLyrics(songA);
      expect(retrieved, isNotNull);
      expect(retrieved!.lines.length, equals(1));
      expect(retrieved.lines.first.content, equals('Never gonna'));
      expect(retrieved.lines.first.words.length, equals(2));
    });

    test('matches by Title + Artist fallback when ID differs', () async {
      final alternateSongA = GenericSong(
        id: 'youtube:video:dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artists: [
          GenericSimpleArtist(
            id: '2',
            name: 'Rick Astley',
            source: 'youtube',
            thumbnailUrl: '',
          ),
        ],
        source: 'youtube',
        thumbnailUrl: '',
        durationSecs: 213,
        explicit: false,
      );

      expect(storage.hasCustomLyricsSync(alternateSongA), isTrue);

      final retrieved = await storage.getCustomLyrics(alternateSongA);
      expect(retrieved, isNotNull);
      expect(retrieved!.lines.first.content, equals('Never gonna'));
    });

    test('removes custom lyrics and clears files from disk', () async {
      final removed = await storage.removeCustomLyrics(songA);
      expect(removed, isTrue);

      expect(storage.hasCustomLyricsSync(songA), isFalse);
      final retrieved = await storage.getCustomLyrics(songA);
      expect(retrieved, isNull);
    });
  });
}

