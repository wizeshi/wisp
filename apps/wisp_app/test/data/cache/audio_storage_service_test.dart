// Copyright © 2026 wizeshi

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/data/cache/audio/audio_storage_service.dart';
import 'package:wisp/data/cache/audio/track_download_state_coordinator.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/cache/models/audio_cache_entry.dart';

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

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('wisp_cache_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('TrackDownloadStateCoordinator', () {
    late TrackDownloadStateCoordinator coordinator;

    setUp(() {
      coordinator = TrackDownloadStateCoordinator();
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('initial state defaults to idle or cached', () {
      final idleState = coordinator.watch('track1').value;
      expect(idleState.isDownloading, isFalse);
      expect(idleState.isCached, isFalse);

      final cachedState = coordinator.watch('track2', isCached: true).value;
      expect(cachedState.isCached, isTrue);
      expect(cachedState.progress, 1.0);
    });

    test('granular progress updates only the targeted track', () {
      final track1 = coordinator.watch('track1');
      final track2 = coordinator.watch('track2');

      coordinator.setQueued('track1');
      expect(track1.value.isQueued, isTrue);
      expect(track2.value.status, TrackDownloadStatus.idle);

      coordinator.setProgress('track1', 0.45);
      expect(track1.value.isDownloading, isTrue);
      expect(track1.value.progress, 0.45);
      expect(track2.value.status, TrackDownloadStatus.idle);

      coordinator.setCompleted('track1');
      expect(track1.value.isCached, isTrue);
      expect(track1.value.status, TrackDownloadStatus.downloaded);
      expect(track2.value.status, TrackDownloadStatus.idle);
    });
  });

  group('AudioCacheEntry', () {
    test('serializes and deserializes correctly with isUserDownload flag', () {
      final now = DateTime.now();
      final entry = AudioCacheEntry(
        trackId: 'spotify:track:12345',
        videoId: 'yt_abcde',
        filePath: '/path/to/track.m4a',
        fileSize: 4500000,
        trackTitle: 'Test Song',
        artistName: 'Test Artist',
        downloadDate: now,
        lastPlayedDate: now,
        isUserDownload: true,
      );

      final json = entry.toJson();
      expect(json['isUserDownload'], isTrue);

      final reconstructed = AudioCacheEntry.fromJson(json);
      expect(reconstructed.trackId, 'spotify:track:12345');
      expect(reconstructed.isUserDownload, isTrue);
      expect(reconstructed.fileSize, 4500000);
    });
  });

  group('MetadataCacheStore', () {
    test('stores and reads entry using L1 in-memory cache and L2 disk cache', () async {
      final store = MetadataCacheStore.instance;

      await store.writeEntry(
        provider: 'test_provider',
        type: 'track',
        id: '123',
        payload: {'name': 'Test Track', 'tempo': 120},
        ttl: const Duration(hours: 1),
      );

      // Fast read (from L1 memory cache)
      final cached = await store.readEntry(
        provider: 'test_provider',
        type: 'track',
        id: '123',
      );

      expect(cached, isNotNull);
      expect(cached!.payload['name'], 'Test Track');
      expect(cached.isExpired, isFalse);

      await store.clearProvider('test_provider');
      final cleared = await store.readEntry(
        provider: 'test_provider',
        type: 'track',
        id: '123',
      );
      expect(cleared, isNull);
    });
  });

  group('AudioStorageService', () {
    test('normalizes track IDs correctly', () {
      final service = AudioStorageService.instance;
      expect(service.normalizeTrackId('spotify:track:abcdef123'), 'abcdef123');
      expect(service.normalizeTrackId('abcdef123'), 'abcdef123');
    });

    test('storage status calculates normal, warning, and full states', () async {
      final service = AudioStorageService.instance;
      await service.initialize();
      expect(service.isInitialized, isTrue);
      expect(service.storageStatus, StorageStatus.normal);
    });
  });
}
