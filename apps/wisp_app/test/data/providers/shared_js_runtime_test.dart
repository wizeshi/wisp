import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/sources/providers/shared_js_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedJsRuntime Tests', () {
    final runtime = SharedJsRuntime.instance;

    test('Initializes lazily and loads provider on demand', () async {
      expect(runtime.isProviderLoaded('mock_test_audio'), isFalse);

      const mockScript = '''
        function searchAudio(query) {
          return [
            {
              mediaId: 'test_123',
              title: 'Test Song ' + (query.title || ''),
              artist: 'Test Artist',
              durationSecs: 180
            }
          ];
        }
        function getStreamUrl(mediaId, options) {
          return {
            url: 'https://cdn.example.com/' + mediaId + '.mp3',
            format: 'mp3',
            bitrate: 320
          };
        }
        module.exports = { searchAudio: searchAudio, getStreamUrl: getStreamUrl };
      ''';

      await runtime.loadProvider(
        id: 'mock_test_audio',
        name: 'Mock Audio',
        script: mockScript,
      );

      expect(runtime.isProviderLoaded('mock_test_audio'), isTrue);

      // Search audio via shared runtime
      final searchResult = await runtime.searchAudio('mock_test_audio', {'title': 'Hello'});
      expect(searchResult, isA<List>());
      expect(searchResult.length, equals(1));
      expect(searchResult[0]['mediaId'], equals('test_123'));
      expect(searchResult[0]['title'], equals('Test Song Hello'));

      // Resolve stream URL via shared runtime
      final streamResult = await runtime.getStreamUrl('mock_test_audio', 'test_123', {'preferredQuality': 'high'});
      expect(streamResult, isA<Map>());
      expect(streamResult['url'], equals('https://cdn.example.com/test_123.mp3'));
      expect(streamResult['format'], equals('mp3'));
      expect(streamResult['bitrate'], equals(320));
    });

    test('Isolates multiple providers in the same runtime', () async {
      const providerAScript = '''
        function getLyrics(query) {
          return { provider: 'A', title: query.title };
        }
        module.exports = { getLyrics: getLyrics };
      ''';

      const providerBScript = '''
        function getLyrics(query) {
          return { provider: 'B', title: query.title };
        }
        module.exports = { getLyrics: getLyrics };
      ''';

      await runtime.loadProvider(id: 'lyrics_a', name: 'Provider A', script: providerAScript);
      await runtime.loadProvider(id: 'lyrics_b', name: 'Provider B', script: providerBScript);

      final resA = await runtime.getLyrics('lyrics_a', {'title': 'Song 1'});
      final resB = await runtime.getLyrics('lyrics_b', {'title': 'Song 2'});

      expect(resA!['provider'], equals('A'));
      expect(resA['title'], equals('Song 1'));
      expect(resB!['provider'], equals('B'));
      expect(resB['title'], equals('Song 2'));
    });

    test('Unloads providers cleanly', () {
      expect(runtime.isProviderLoaded('lyrics_a', type: 'lyrics'), isTrue);
      runtime.unloadProvider('lyrics_a', type: 'lyrics');
      expect(runtime.isProviderLoaded('lyrics_a', type: 'lyrics'), isFalse);
    });

    test('Allows identical provider IDs across different subsystems without collision', () async {
      // Mock metadata provider with id 'spotify'
      const mockMetadataScript = '''
        function search(query) {
          return { from: 'metadata_provider', query: query };
        }
        module.exports = { search: search };
      ''';

      // Mock auth provider with id 'spotify'
      const mockAuthScript = '''
        function getTokens(force) {
          return { from: 'auth_provider', tokens: { accessToken: 'secret_tok' } };
        }
        module.exports = { getTokens: getTokens };
      ''';

      await runtime.loadProvider(
        id: 'spotify',
        name: 'Spotify Metadata',
        script: mockMetadataScript,
        type: 'metadata',
      );

      await runtime.loadProvider(
        id: 'spotify',
        name: 'Spotify Auth',
        script: mockAuthScript,
        type: 'auth',
      );

      expect(runtime.isProviderLoaded('spotify', type: 'metadata'), isTrue);
      expect(runtime.isProviderLoaded('spotify', type: 'auth'), isTrue);

      // Metadata call must reach metadata provider
      final metaRes = await runtime.invokeMetadata('spotify', 'search', ['hello']);
      expect(metaRes, isA<Map>());
      expect(metaRes['from'], equals('metadata_provider'));

      // Auth call must reach auth provider and resolve getTokens
      final authRes = await runtime.invokeAuth('spotify', 'getTokens', [false]);
      expect(authRes, isA<Map>());
      expect(authRes['from'], equals('auth_provider'));
      expect(authRes['tokens']['accessToken'], equals('secret_tok'));
    });

    test('Loads real Spotify auth provider and checks getTokens method', () async {
      final file = File('../../providers/auth/spotify/index.js');
      expect(file.existsSync(), isTrue);
      final script = await file.readAsString();
      await runtime.loadProvider(
        id: 'spotify_real',
        name: 'Spotify Auth Real',
        script: script,
        serviceId: 'spotify',
        type: 'auth',
      );
      expect(runtime.isProviderLoaded('spotify_real', type: 'auth'), isTrue);

      // getTokens should execute cleanly without "not a function" error
      final res = await runtime.invokeAuth('spotify_real', 'getTokens', [false]);
      // If unauthenticated, it returns null or throws/logs not authenticated, but NOT "is not a function"
      expect(res, anyOf(isNull, isA<Map>()));
    });
  });
}


