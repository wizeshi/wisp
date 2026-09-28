// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/cache/metadata_revalidator.dart';
import 'package:wisp/services/system/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataRevalidator Tests', () {
    final connectivity = ConnectivityService.instance;

    setUp(() {
      connectivity.setMockOnline(true);
    });

    test('Cache hit displays immediately, then refreshes when online and diff exists', () async {
      final emissions = <String>[];
      final fromCacheFlags = <bool>[];
      bool isRefreshingState = false;

      await MetadataRevalidator.revalidate<String>(
        connectivityService: connectivity,
        loadCache: () async => 'cached_playlist_v1',
        fetchRemote: () async => 'fresh_playlist_v2',
        hasChanged: (curr, fresh) => curr != fresh,
        onData: (data, {required fromCache}) {
          emissions.add(data);
          fromCacheFlags.add(fromCache);
        },
        onRefreshing: (refreshing) {
          isRefreshingState = refreshing;
        },
      );

      // 1. Immediately received cached data
      // 2. Then received updated fresh data
      expect(emissions, equals(['cached_playlist_v1', 'fresh_playlist_v2']));
      expect(fromCacheFlags, equals([true, false]));
      expect(isRefreshingState, isFalse);
    });

    test('Cache hit displays immediately and skips UI update if fresh data is identical', () async {
      final emissions = <String>[];
      final fromCacheFlags = <bool>[];

      await MetadataRevalidator.revalidate<String>(
        connectivityService: connectivity,
        loadCache: () async => 'same_content',
        fetchRemote: () async => 'same_content',
        hasChanged: (curr, fresh) => curr != fresh,
        onData: (data, {required fromCache}) {
          emissions.add(data);
          fromCacheFlags.add(fromCache);
        },
      );

      // Only cached data was emitted, fresh data was identical so onData wasn't invoked again
      expect(emissions, equals(['same_content']));
      expect(fromCacheFlags, equals([true]));
    });

    test('Cache hit displays immediately and stops without remote fetch when offline', () async {
      connectivity.setMockOnline(false);
      final emissions = <String>[];
      bool remoteFetched = false;

      await MetadataRevalidator.revalidate<String>(
        connectivityService: connectivity,
        loadCache: () async => 'cached_offline_playlist',
        fetchRemote: () async {
          remoteFetched = true;
          return 'fresh_data';
        },
        hasChanged: (curr, fresh) => curr != fresh,
        onData: (data, {required fromCache}) {
          emissions.add(data);
        },
        onError: (err) {
          fail('Should not trigger onError when cached data is present');
        },
      );

      expect(emissions, equals(['cached_offline_playlist']));
      expect(remoteFetched, isFalse);
    });

    test('Cache miss fetches remote data and emits fresh when online', () async {
      connectivity.setMockOnline(true);
      final emissions = <String>[];
      final fromCacheFlags = <bool>[];

      await MetadataRevalidator.revalidate<String>(
        connectivityService: connectivity,
        loadCache: () async => null,
        fetchRemote: () async => 'fresh_data_only',
        hasChanged: (curr, fresh) => curr != fresh,
        onData: (data, {required fromCache}) {
          emissions.add(data);
          fromCacheFlags.add(fromCache);
        },
      );

      expect(emissions, equals(['fresh_data_only']));
      expect(fromCacheFlags, equals([false]));
    });

    test('Cache miss triggers onError when offline', () async {
      connectivity.setMockOnline(false);
      final emissions = <String>[];
      Object? receivedError;

      await MetadataRevalidator.revalidate<String>(
        connectivityService: connectivity,
        loadCache: () async => null,
        fetchRemote: () async => 'should_not_reach',
        hasChanged: (curr, fresh) => curr != fresh,
        onData: (data, {required fromCache}) {
          emissions.add(data);
        },
        onError: (err) {
          receivedError = err;
        },
      );

      expect(emissions, isEmpty);
      expect(receivedError, isNotNull);
    });

    test('Cache hit retains cached data without crashing if background fetch throws', () async {
      connectivity.setMockOnline(true);
      final emissions = <String>[];
      Object? receivedError;

      await MetadataRevalidator.revalidate<String>(
        connectivityService: connectivity,
        loadCache: () async => 'good_cached_data',
        fetchRemote: () async => throw Exception('500 Internal Server Error'),
        hasChanged: (curr, fresh) => curr != fresh,
        onData: (data, {required fromCache}) {
          emissions.add(data);
        },
        onError: (err) {
          receivedError = err;
        },
      );

      // Cached data remained displayed and onError was NOT called to disrupt user
      expect(emissions, equals(['good_cached_data']));
      expect(receivedError, isNull);
    });

    test('Token cancellation halts revalidator callbacks', () async {
      connectivity.setMockOnline(true);
      final token = MetadataRevalidatorToken();
      final emissions = <String>[];

      token.cancel();

      await MetadataRevalidator.revalidate<String>(
        connectivityService: connectivity,
        token: token,
        loadCache: () async => 'cached_data',
        fetchRemote: () async => 'fresh_data',
        hasChanged: (curr, fresh) => curr != fresh,
        onData: (data, {required fromCache}) {
          emissions.add(data);
        },
      );

      expect(emissions, isEmpty);
    });
  });
}
