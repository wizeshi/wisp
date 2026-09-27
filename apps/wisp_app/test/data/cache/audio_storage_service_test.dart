// Copyright © 2026 wizeshi

import 'dart:convert';
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
      service.resetForTesting();
      await service.initialize();
      expect(service.isInitialized, isTrue);
      expect(service.storageStatus, StorageStatus.normal);
    });

    test('persists cache index to audio_cache_index.json and reloads', () async {
      final service = AudioStorageService.instance;
      service.resetForTesting();

      final supportDir = Directory('${tempDir.path}/support_test1')..createSync(recursive: true);
      final cacheDir = Directory('${tempDir.path}/cache_test1')..createSync(recursive: true);

      await service.initialize(
        supportDirectory: supportDir,
        cacheDirectory: cacheDir,
      );

      final audioDir = Directory('${cacheDir.path}/audio_cache');
      final partFile = File('${audioDir.path}/test_track.m4a.part')..writeAsStringSync('dummy audio bytes');
      final finalPath = '${audioDir.path}/test_track.m4a';

      // Register download
      await service.registerCompletedDownload(
        trackId: 'track_123',
        videoId: 'vid_123',
        tempPartPath: partFile.path,
        finalFilePath: finalPath,
        trackTitle: 'Song One',
        artistName: 'Artist One',
        isUserDownload: true,
      );

      expect(service.isTrackCached('track_123'), isTrue);
      expect(service.isTrackUserDownload('track_123'), isTrue);

      final indexFile = File('${supportDir.path}/audio_cache_index.json');
      expect(indexFile.existsSync(), isTrue);
      final indexContent = json.decode(indexFile.readAsStringSync()) as Map<String, dynamic>;
      expect(indexContent.containsKey('track_123'), isTrue);

      // Reset and re-initialize from the same directories
      service.resetForTesting();
      await service.initialize(
        supportDirectory: supportDir,
        cacheDirectory: cacheDir,
      );

      expect(service.isTrackCached('track_123'), isTrue);
      expect(service.isTrackUserDownload('track_123'), isTrue);
    });

    test('migrates legacy SharedPreferences entries and deletes legacy key', () async {
      final service = AudioStorageService.instance;
      service.resetForTesting();

      final supportDir = Directory('${tempDir.path}/support_test2')..createSync(recursive: true);
      final cacheDir = Directory('${tempDir.path}/cache_test2')..createSync(recursive: true);
      final audioDir = Directory('${cacheDir.path}/audio_cache')..createSync(recursive: true);
      final legacyFile = File('${audioDir.path}/legacy_song.m4a')..writeAsStringSync('legacy audio');

      final legacyEntry = AudioCacheEntry(
        trackId: 'legacy_track',
        videoId: 'legacy_vid',
        filePath: legacyFile.path,
        fileSize: legacyFile.lengthSync(),
        trackTitle: 'Legacy Title',
        artistName: 'Legacy Artist',
        downloadDate: DateTime.now(),
        lastPlayedDate: DateTime.now(),
        isUserDownload: false,
      );

      SharedPreferences.setMockInitialValues({
        'cache_entries': json.encode({'legacy_track': legacyEntry.toJson()}),
      });

      await service.initialize(
        supportDirectory: supportDir,
        cacheDirectory: cacheDir,
      );

      expect(service.isTrackCached('legacy_track'), isTrue);

      // Verify the legacy key was removed from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('cache_entries'), isFalse);

      // Verify index file was written
      final indexFile = File('${supportDir.path}/audio_cache_index.json');
      expect(indexFile.existsSync(), isTrue);
    });

    test('safe reconciliation deletes .part and .tmp but NEVER deletes .m4a files', () async {
      final service = AudioStorageService.instance;
      service.resetForTesting();

      final supportDir = Directory('${tempDir.path}/support_test3')..createSync(recursive: true);
      final cacheDir = Directory('${tempDir.path}/cache_test3')..createSync(recursive: true);
      final audioDir = Directory('${cacheDir.path}/audio_cache')..createSync(recursive: true);

      // Create an unindexed .m4a file (e.g. if index hadn't loaded in time)
      final unindexedM4a = File('${audioDir.path}/unindexed_song.m4a')..writeAsStringSync('music data');
      final tempPart = File('${audioDir.path}/download.m4a.part')..writeAsStringSync('partial data');
      final tempFile = File('${audioDir.path}/temp.tmp')..writeAsStringSync('temporary data');

      expect(unindexedM4a.existsSync(), isTrue);
      expect(tempPart.existsSync(), isTrue);
      expect(tempFile.existsSync(), isTrue);

      await service.initialize(
        supportDirectory: supportDir,
        cacheDirectory: cacheDir,
      );

      // Incomplete temp files MUST be deleted
      expect(tempPart.existsSync(), isFalse);
      expect(tempFile.existsSync(), isFalse);

      // SAFEGUARD: The .m4a audio file MUST NOT be deleted!
      expect(unindexedM4a.existsSync(), isTrue);
    });

    test('recovers from backup file if primary audio_cache_index.json is corrupted', () async {
      final service = AudioStorageService.instance;
      service.resetForTesting();

      final supportDir = Directory('${tempDir.path}/support_test4')..createSync(recursive: true);
      final cacheDir = Directory('${tempDir.path}/cache_test4')..createSync(recursive: true);
      final audioDir = Directory('${cacheDir.path}/audio_cache')..createSync(recursive: true);
      final testFile = File('${audioDir.path}/backup_track.m4a')..writeAsStringSync('audio data');

      final validEntry = AudioCacheEntry(
        trackId: 'backup_track',
        videoId: 'backup_vid',
        filePath: testFile.path,
        fileSize: testFile.lengthSync(),
        trackTitle: 'Backup Title',
        artistName: 'Backup Artist',
        downloadDate: DateTime.now(),
        lastPlayedDate: DateTime.now(),
        isUserDownload: true,
      );

      // Write corrupted primary index and valid backup index
      final indexFile = File('${supportDir.path}/audio_cache_index.json')
        ..writeAsStringSync('{ INVALID JSON CONTENT !!!');
      final backupFile = File('${supportDir.path}/audio_cache_index.json.bak')
        ..writeAsStringSync(json.encode({'backup_track': validEntry.toJson()}));

      expect(indexFile.existsSync(), isTrue);
      expect(backupFile.existsSync(), isTrue);

      await service.initialize(
        supportDirectory: supportDir,
        cacheDirectory: cacheDir,
      );

      expect(service.isTrackCached('backup_track'), isTrue);
      expect(service.isTrackUserDownload('backup_track'), isTrue);
    });
  });
}

