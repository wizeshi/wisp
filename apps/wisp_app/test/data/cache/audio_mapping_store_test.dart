// Copyright © 2026 wizeshi

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wisp/data/cache/audio/audio_mapping_store.dart';

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
    tempDir = Directory.systemTemp.createTempSync('wisp_audio_mapping_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir);
  });

  tearDownAll(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('AudioMappingStore Canonical Key Generation', () {
    test('normalizes, tokenizes, and alphabetically sorts title and artists', () {
      final key = AudioMappingStore.canonicalKey(
        title: 'Let It Happen',
        artists: ['Tame Impala'],
      );
      expect(key, 'happen_impala_it_let_tame');
    });

    test('ignores special characters, punctuation, and extra whitespace', () {
      final key = AudioMappingStore.canonicalKey(
        title: 'Let It Happen! (Official Audio)',
        artists: ['Tame Impala', 'Kevin Parker'],
      );
      // Tokens: audio, happen, impala, it, kevin, let, official, parker, tame
      expect(
        key,
        'audio_happen_impala_it_kevin_let_official_parker_tame',
      );
    });

    test('handles empty or missing artist gracefully', () {
      final key = AudioMappingStore.canonicalKey(
        title: 'Intro',
        artists: [],
      );
      expect(key, 'intro');
    });
  });

  group('AudioMappingStore multi-provider storage', () {
    test('stores and retrieves multiple provider mappings for a canonical key', () async {
      final store = AudioMappingStore.instance;
      await store.initialize(supportDirectory: tempDir);
      await store.clear();

      final key = AudioMappingStore.canonicalKey(
        title: 'Let It Happen',
        artists: ['Tame Impala'],
      );

      // Add YouTube resolution
      await store.setMapping(
        key,
        AudioMappingItem(
          providerID: 'youtube',
          mediaID: '7x6q6u8GkXE',
          manualOverride: false,
        ),
      );

      // Add Qobuz resolution
      await store.setMapping(
        key,
        AudioMappingItem(
          providerID: 'qobuz',
          mediaID: '123456789',
          manualOverride: true,
        ),
      );

      await store.flush();

      // Retrieve single provider
      final ytEntry = store.getMapping(key, 'youtube');
      expect(ytEntry, isNotNull);
      expect(ytEntry!.providerID, 'youtube');
      expect(ytEntry.mediaID, '7x6q6u8GkXE');
      expect(ytEntry.manualOverride, isFalse);

      final qobuzEntry = store.getMapping(key, 'qobuz');
      expect(qobuzEntry, isNotNull);
      expect(qobuzEntry!.providerID, 'qobuz');
      expect(qobuzEntry.mediaID, '123456789');
      expect(qobuzEntry.manualOverride, isTrue);

      // Retrieve all mappings for key
      final all = store.getMappings(key);
      expect(all.length, 2);

      // Remove specific provider
      await store.removeMapping(key, providerId: 'youtube');
      expect(store.getMapping(key, 'youtube'), isNull);
      expect(store.getMapping(key, 'qobuz'), isNotNull);

      // Clean up
      await store.clear();
      expect(store.contains(key), isFalse);
    });
  });
}

