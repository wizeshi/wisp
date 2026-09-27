// Copyright © 2026 wizeshi

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  group('ServiceSessionManager Tests', () {
    final manager = ServiceSessionManager.instance;

    test('get, set, clear in-memory and persistent sessions', () async {
      await manager.setSession('test_service', {
        'accessToken': 'test_token_123',
        'expiresAtMs': 9999999999,
        'cookies': {'sp_dc': 'mock_cookie'}
      });

      final session = await manager.getSession('test_service');
      expect(session, isNotNull);
      expect(session!['accessToken'], 'test_token_123');
      expect(session['cookies']['sp_dc'], 'mock_cookie');
      expect(mockSecureStore['wisp_service_session_test_service'], isNotNull);

      await manager.clearSession('test_service');
      final cleared = await manager.getSession('test_service');
      expect(cleared, isNull);
      expect(mockSecureStore['wisp_service_session_test_service'], isNull);
    });

    test('withRefreshLock executes only once for concurrent requests', () async {
      int executionCount = 0;

      Future<Map<String, dynamic>?> simulateRefresh() async {
        executionCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return {
          'accessToken': 'fresh_token_$executionCount',
          'expiresAtMs': 9999999999,
        };
      }

      // Launch 3 concurrent refresh requests
      final future1 = manager.withRefreshLock('concurrent_service', simulateRefresh);
      final future2 = manager.withRefreshLock('concurrent_service', simulateRefresh);
      final future3 = manager.withRefreshLock('concurrent_service', simulateRefresh);

      final results = await Future.wait([future1, future2, future3]);

      // All 3 callers must receive the exact same refreshed session
      expect(results[0], isNotNull);
      expect(results[0]!['accessToken'], 'fresh_token_1');
      expect(results[1]!['accessToken'], 'fresh_token_1');
      expect(results[2]!['accessToken'], 'fresh_token_1');

      // The actual network refresh function was only invoked once!
      expect(executionCount, 1);
    });
  });
}
