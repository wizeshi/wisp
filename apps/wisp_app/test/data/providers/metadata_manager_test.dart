// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/models/metadata_provider.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/data/sources/youtube/youtube_metadata.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

class MockMetadataProvider extends MetadataProvider {
  final String _id;
  final String _displayName;

  MockMetadataProvider({required String id, required String displayName})
      : _id = id,
        _displayName = displayName;

  @override
  String get name => _id;

  @override
  String get displayName => _displayName;

  @override
  String get providerId => _id;

  @override
  Future<SearchResults> search(
    String query, {
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    return SearchResults(
      tracks: [
        GenericSong(
          id: '$_id:track:1',
          source: 'spotify',
          title: 'Track from $_id for "$query"',
          artists: const [],
          thumbnailUrl: '',
          explicit: false,
          durationSecs: 180,
        ),
      ],
      artists: const [],
      albums: const [],
      playlists: const [],
      bestMatch: null,
    );
  }

  @override
  Future<GenericSong> getTrackInfo(
    String trackId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    return GenericSong(
      id: trackId,
      source: 'spotify',
      title: 'Info from $_id for $trackId',
      artists: const [],
      thumbnailUrl: '',
      explicit: false,
      durationSecs: 200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YouTubeMetadataProvider Tests', () {
    test('inherits MetadataProvider contract correctly', () {
      final yt = YouTubeMetadataProvider();
      expect(yt.providerId, equals('youtube'));
      expect(yt.name, equals('youtube'));
      expect(yt.displayName, equals('YouTube'));
      expect(yt.description, contains('YouTube'));
      expect(yt.logoURL, contains('YouTube'));
      expect(yt.iconURL, contains('YouTube'));
      expect(yt.isAuthenticated, isFalse);
      expect(yt.dumpJson()['providerId'], equals('youtube'));
    });

    test('getTrackInfo throws UnimplementedError', () async {
      final yt = YouTubeMetadataProvider();
      expect(() => yt.getTrackInfo('any_id'), throwsUnimplementedError);
    });
  });

  group('MetadataManager Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('registers and resolves providers case-insensitively', () {
      final mock1 = MockMetadataProvider(id: 'spotify', displayName: 'Spotify');
      final mock2 = MockMetadataProvider(id: 'youtube', displayName: 'YouTube');
      final mock3 = MockMetadataProvider(id: 'custom_service', displayName: 'Custom Service');

      final manager = MetadataManager(
        spotifyProvider: mock1,
        youtubeProvider: mock2,
      );
      manager.registerProvider(mock3);

      expect(manager.allProviders.length, equals(3));
      expect(manager.getProvider('spotify'), equals(mock1));
      expect(manager.getProvider('Spotify'), equals(mock1));
      expect(manager.getProvider('SPOTIFY'), equals(mock1));
      expect(manager.getProvider('youtube'), equals(mock2));
      expect(manager.getProvider('YouTube'), equals(mock2));
      expect(manager.getProvider('custom_service'), equals(mock3));
      expect(manager.getProvider('Custom Service'), equals(mock3));
      expect(manager.getProvider('unknown'), isNull);
    });

    test('routes search by providerId or defaults to activeCatalogProvider', () async {
      final mock1 = MockMetadataProvider(id: 'spotify', displayName: 'Spotify');
      final mock2 = MockMetadataProvider(id: 'youtube', displayName: 'YouTube');

      final manager = MetadataManager(
        spotifyProvider: mock1,
        youtubeProvider: mock2,
      );

      // Default should route to Spotify
      final resDefault = await manager.search('hello');
      expect(resDefault.tracks.first.id, equals('spotify:track:1'));

      // Explicit YouTube
      final resYt = await manager.search('hello', providerId: 'youtube');
      expect(resYt.tracks.first.id, equals('youtube:track:1'));

      // Explicit Spotify by display name
      final resSp = await manager.search('hello', providerId: 'Spotify');
      expect(resSp.tracks.first.id, equals('spotify:track:1'));
    });

    test('searchAll queries all available providers concurrently', () async {
      final mock1 = MockMetadataProvider(id: 'spotify', displayName: 'Spotify');
      final mock2 = MockMetadataProvider(id: 'youtube', displayName: 'YouTube');

      final manager = MetadataManager(
        spotifyProvider: mock1,
        youtubeProvider: mock2,
      );

      final allResults = await manager.searchAll('test query');
      expect(allResults.containsKey('spotify'), isTrue);
      expect(allResults.containsKey('youtube'), isTrue);
      expect(allResults['spotify']!.tracks.first.title, contains('spotify'));
      expect(allResults['youtube']!.tracks.first.title, contains('youtube'));
    });

    test('filters availableProviders based on PreferencesProvider', () async {
      SharedPreferences.setMockInitialValues({
        'disabled_provider_ids': ['metadata:youtube'],
      });

      final prefs = PreferencesProvider();
      await Future.delayed(const Duration(milliseconds: 20));

      final mock1 = MockMetadataProvider(id: 'spotify', displayName: 'Spotify');
      final mock2 = MockMetadataProvider(id: 'youtube', displayName: 'YouTube');

      final manager = MetadataManager(
        spotifyProvider: mock1,
        youtubeProvider: mock2,
        preferences: prefs,
      );

      expect(manager.availableProviders.length, equals(1));
      expect(manager.availableProviders.first.providerId, equals('spotify'));
      expect(manager.isProviderEnabled('spotify'), isTrue);
      expect(manager.isProviderEnabled('youtube'), isFalse);

      // Verify type-scoping: disabling metadata:youtube does not disable lyrics:youtube
      expect(prefs.isProviderEnabled('youtube', type: 'lyrics'), isTrue);

      // Enable YouTube metadata
      await prefs.setProviderEnabled('youtube', true, type: 'metadata');
      expect(manager.availableProviders.length, equals(2));
      expect(manager.isProviderEnabled('youtube'), isTrue);
    });

    test('delegates getTrackInfo polymorphically', () async {
      final mock1 = MockMetadataProvider(id: 'spotify', displayName: 'Spotify');
      final mock2 = MockMetadataProvider(id: 'youtube', displayName: 'YouTube');

      final manager = MetadataManager(
        spotifyProvider: mock1,
        youtubeProvider: mock2,
      );

      final track1 = await manager.getTrackInfo('t1', providerId: 'spotify');
      expect(track1.title, contains('spotify'));

      final track2 = await manager.getTrackInfo('t2', providerId: 'youtube');
      expect(track2.title, contains('youtube'));
    });
  });
}
