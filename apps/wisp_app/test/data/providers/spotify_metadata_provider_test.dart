import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/sources/metadata/js_metadata_source.dart';
import 'package:wisp/data/sources/providers/service_session_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockSecureStore = {};

  setUpAll(() {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'write') {
        final key = methodCall.arguments['key'] as String;
        final value = methodCall.arguments['value'] as String;
        mockSecureStore[key] = value;
        return null;
      } else if (methodCall.method == 'read') {
        final key = methodCall.arguments['key'] as String;
        return mockSecureStore[key];
      } else if (methodCall.method == 'delete') {
        final key = methodCall.arguments['key'] as String;
        mockSecureStore.remove(key);
        return null;
      }
      return null;
    });
  });

  group('SpotifyMetadataProvider / JsMetadataSource Tests', () {
    late ServiceSessionManager sessionManager;

    setUp(() async {
      sessionManager = ServiceSessionManager.instance;
      await sessionManager.clearSession('spotify');
    });

    test('JsMetadataSource initializes with correct properties', () {
      final provider = JsMetadataSource(providerId: 'spotify', serviceId: 'spotify');
      expect(provider.providerId, equals('spotify'));
      expect(provider.serviceId, equals('spotify'));
      expect(provider.isAuthenticated, isFalse);
    });

    test('Auth state updates reactively when session changes in vault', () async {
      final provider = JsMetadataSource(providerId: 'spotify', serviceId: 'spotify');
      expect(provider.isAuthenticated, isFalse);

      bool notified = false;
      provider.addListener(() {
        notified = true;
      });

      await sessionManager.setSession('spotify', {
        'cookies': {'sp_dc': 'test_cookie_123'},
        'userId': 'spotify_user_xyz',
        'displayName': 'Wisp Tester',
      });

      expect(provider.isAuthenticated, isTrue);
      expect(provider.userId, equals('spotify_user_xyz'));
      expect(provider.userDisplayName, equals('Wisp Tester'));
      expect(notified, isTrue);

      await sessionManager.clearSession('spotify');
      expect(provider.isAuthenticated, isFalse);
    });

    test('JavaScript provider file exists and contains all required features', () {
      final manifestFile = File('../../providers/metadata/spotify/manifest.json');
      final indexFile = File('../../providers/metadata/spotify/index.js');

      expect(manifestFile.existsSync(), isTrue, reason: 'manifest.json must exist');
      expect(indexFile.existsSync(), isTrue, reason: 'index.js must exist');

      final content = indexFile.readAsStringSync();
      expect(content.contains('SpotifyMetadataProvider'), isTrue);
      expect(content.contains('getSimilarTracks'), isTrue);
      expect(content.contains('addPlaylistToFolder'), isTrue);
      expect(content.contains('removePlaylistFromFolder'), isTrue);
      expect(content.contains('getUserLibrary'), isTrue);
      expect(content.contains('wisp.auth.getTokens'), isTrue);
      expect(content.contains('all_organized'), isTrue);

      final authIndexFile = File('../../providers/auth/spotify/index.js');
      expect(authIndexFile.existsSync(), isTrue);
      expect(authIndexFile.readAsStringSync().contains('wisp.service.withRefreshLock'), isTrue);
    });

    test('Deprecated user top tracks and top artists return empty lists', () async {
      final provider = JsMetadataSource(providerId: 'spotify', serviceId: 'spotify');
      final topTracks = await provider.getUserTopTracks();
      final topArtists = await provider.getUserTopArtists();

      expect(topTracks, isEmpty);
      expect(topArtists, isEmpty);
    });
  });
}
