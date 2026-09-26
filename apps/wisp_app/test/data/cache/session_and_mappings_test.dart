// Copyright © 2026 wizeshi

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/data/cache/youtube/youtube_mapping_store.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/services/audio/playback_session_store.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';

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
    tempDir = Directory.systemTemp.createTempSync('wisp_session_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);
  });

  tearDownAll(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('PreferencesProvider keepPositionBetweenRestarts', () {
    test('defaults to false and toggles state correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = PreferencesProvider();
      expect(provider.keepPositionBetweenRestarts, isFalse);

      await provider.setKeepPositionBetweenRestarts(true);
      expect(provider.keepPositionBetweenRestarts, isTrue);

      final isEnabledStatic =
          await PreferencesProvider.isKeepPositionBetweenRestartsEnabled();
      expect(isEnabledStatic, isTrue);
    });
  });

  group('YouTubeMappingStore', () {
    test('stores, retrieves, flushes, and migrates from legacy SharedPreferences', () async {
      final legacyData = {
        'track_1': 'yt_vid_1',
        'track_2': 'yt_vid_2',
      };
      SharedPreferences.setMockInitialValues({
        'youtube_video_id_cache': json.encode(legacyData),
      });

      final store = YouTubeMappingStore.instance;
      await store.initialize(supportDirectory: tempDir);

      // Verify migration
      expect(store.getVideoId('track_1'), 'yt_vid_1');
      expect(store.getVideoId('track_2'), 'yt_vid_2');
      expect(store.contains('track_1'), isTrue);

      // Verify legacy SharedPreferences key was removed to free space
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('youtube_video_id_cache'), isFalse);

      // Add a new track with rich metadata
      await store.setVideoId(
        'track_3',
        'yt_vid_3',
        title: 'Song Title',
        durationSecs: 210,
        isManualOverride: true,
      );
      await store.flush();

      final entry = store.getEntry('track_3');
      expect(entry, isNotNull);
      expect(entry!.videoId, 'yt_vid_3');
      expect(entry.isManualOverride, isTrue);
      expect(entry.durationSecs, 210);

      // Verify snapshot
      final snapshot = store.getSnapshot();
      expect(snapshot['track_3'], 'yt_vid_3');
      expect(snapshot.length, 3);

      // Verify clear
      await store.clear();
      expect(store.count, 0);
      expect(store.getVideoId('track_1'), isNull);
    });
  });

  group('PlaybackSessionStore', () {
    test('migrates legacy SharedPreferences queue, saves and loads session with positionMs', () async {
      final legacySong = GenericSong(
        id: 'spotify:track:abc',
        source: SongSource.spotify,
        title: 'Song A',
        artists: [
          GenericSimpleArtist(
            id: 'art1',
            source: SongSource.spotify,
            name: 'Artist A',
            thumbnailUrl: '',
          ),
        ],
        thumbnailUrl: 'https://example.com/art.jpg',
        explicit: false,
        durationSecs: 180,
      );

      SharedPreferences.setMockInitialValues({
        'audio_queue': json.encode([legacySong.toJson()]),
        'current_index': 0,
        'shuffle_enabled': true,
        'repeat_mode': RepeatMode.all.toString(),
      });

      final store = PlaybackSessionStore.instance;
      final session = await store.loadSession(supportDirectory: tempDir);

      expect(session, isNotNull);
      expect(session!.queue.length, 1);
      expect(session.queue.first.title, 'Song A');
      expect(session.currentIndex, 0);
      expect(session.shuffleEnabled, isTrue);
      expect(session.repeatMode, RepeatMode.all);

      // Verify legacy keys were removed from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('audio_queue'), isFalse);
      expect(prefs.containsKey('current_index'), isFalse);

      // Update session with positionMs
      final updatedSession = PlaybackSession(
        queue: session.queue,
        originalQueue: session.originalQueue,
        currentIndex: 0,
        positionMs: 45000, // 45 seconds into song
        shuffleEnabled: false,
        repeatMode: RepeatMode.off,
      );

      store.saveSession(updatedSession, immediate: true);

      // Reload session
      final reloaded = await store.loadSession(supportDirectory: tempDir);
      expect(reloaded, isNotNull);
      expect(reloaded!.positionMs, 45000);
      expect(reloaded.shuffleEnabled, isFalse);
    });
  });
}
