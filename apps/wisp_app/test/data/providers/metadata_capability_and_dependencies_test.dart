// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/models/metadata_provider.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/data/sources/providers/provider_dependency_validator.dart';
import 'package:wisp/data/sources/youtube/youtube_metadata.dart';

class CustomCapabilityProvider extends MetadataProvider {
  final String _id;
  final Set<MetadataCapability> _caps;

  CustomCapabilityProvider({
    required String id,
    required Set<MetadataCapability> capabilities,
  })  : _id = id,
        _caps = capabilities;

  @override
  String get name => _id;

  @override
  String get providerId => _id;

  @override
  String get displayName => _id.toUpperCase();

  @override
  Set<MetadataCapability> get capabilities => _caps;

  @override
  Future<SearchResults> search(
    String query, {
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    return SearchResults(
      tracks: [],
      artists: [],
      albums: [],
      playlists: [],
      bestMatch: null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataCapability Tests', () {
    test('fromString parses variations correctly', () {
      expect(MetadataCapability.fromString('search'), equals(MetadataCapability.search));
      expect(MetadataCapability.fromString('SEARCH'), equals(MetadataCapability.search));
      expect(MetadataCapability.fromString('home'), equals(MetadataCapability.home));
      expect(MetadataCapability.fromString('canvas'), equals(MetadataCapability.canvas));
      expect(MetadataCapability.fromString('npv'), equals(MetadataCapability.npv));
      expect(MetadataCapability.fromString('library'), equals(MetadataCapability.library));
      expect(
        MetadataCapability.fromString('playlist_management'),
        equals(MetadataCapability.playlistManagement),
      );
      expect(
        MetadataCapability.fromString('playlistManagement'),
        equals(MetadataCapability.playlistManagement),
      );
      expect(
        MetadataCapability.fromString('playlist-management'),
        equals(MetadataCapability.playlistManagement),
      );
      expect(
        MetadataCapability.fromString('recommendations'),
        equals(MetadataCapability.recommendations),
      );
      expect(
        MetadataCapability.fromString('user_profile'),
        equals(MetadataCapability.userProfile),
      );
      expect(
        MetadataCapability.fromString('userProfile'),
        equals(MetadataCapability.userProfile),
      );
      expect(MetadataCapability.fromString('nonexistent_feature'), isNull);
    });

    test('toJson produces standardized string', () {
      expect(MetadataCapability.playlistManagement.toJson(), equals('playlist_management'));
      expect(MetadataCapability.userProfile.toJson(), equals('user_profile'));
      expect(MetadataCapability.search.toJson(), equals('search'));
    });

    test('YouTube provider capabilities are restricted to search', () {
      final yt = YouTubeMetadataProvider();
      expect(yt.capabilities, equals({MetadataCapability.search}));
      expect(yt.supports(MetadataCapability.search), isTrue);
      expect(yt.supports(MetadataCapability.home), isFalse);
      expect(yt.supports(MetadataCapability.canvas), isFalse);
      expect(yt.supports(MetadataCapability.recommendations), isFalse);
    });

    test('MetadataManager delegates hasCapability and getProvidersWithCapability', () {
      final p1 = CustomCapabilityProvider(
        id: 'full_featured',
        capabilities: {
          MetadataCapability.search,
          MetadataCapability.home,
          MetadataCapability.canvas,
          MetadataCapability.recommendations,
        },
      );
      final p2 = CustomCapabilityProvider(
        id: 'search_only',
        capabilities: {MetadataCapability.search},
      );

      final manager = MetadataManager();
      manager.registerProvider(p1);
      manager.registerProvider(p2);

      expect(manager.hasCapability(MetadataCapability.home), isTrue);
      expect(manager.hasCapability(MetadataCapability.canvas, providerId: 'full_featured'), isTrue);
      expect(manager.hasCapability(MetadataCapability.canvas, providerId: 'search_only'), isFalse);
      expect(manager.hasCapability(MetadataCapability.canvas, source: 'search_only'), isFalse);

      final homeProviders = manager.getProvidersWithCapability(MetadataCapability.home);
      expect(homeProviders.length, equals(1));
      expect(homeProviders.first.providerId, equals('full_featured'));

      final searchProviders = manager.getProvidersWithCapability(MetadataCapability.search);
      expect(searchProviders.length, equals(2));
    });
  });

  group('ProviderDependencyValidator Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('parseDependency parses typed and untyped dependencies', () {
      final (type1, id1) = ProviderDependencyValidator.parseDependency('auth/spotify');
      expect(type1, equals('auth'));
      expect(id1, equals('spotify'));

      final (type2, id2) = ProviderDependencyValidator.parseDependency('lyrics/betterlyrics');
      expect(type2, equals('lyrics'));
      expect(id2, equals('betterlyrics'));

      final (type3, id3) = ProviderDependencyValidator.parseDependency('spotify');
      expect(type3, isNull);
      expect(id3, equals('spotify'));
    });

    test('checkDependency flags missing dependencies', () {
      final res = ProviderDependencyValidator.checkDependency('auth/nonexistent');
      expect(res.isSatisfied, isFalse);
      expect(res.status, equals(DependencyStatus.missing));
    });

    test('areDependenciesSatisfied returns false when required dependency is missing', () {
      final satisfied = ProviderDependencyValidator.areDependenciesSatisfied([
        'auth/missing_auth_service',
      ]);
      expect(satisfied, isFalse);
    });

    test('areDependenciesSatisfied returns true for empty dependencies', () {
      final satisfied = ProviderDependencyValidator.areDependenciesSatisfied([]);
      expect(satisfied, isTrue);
    });
  });
}
