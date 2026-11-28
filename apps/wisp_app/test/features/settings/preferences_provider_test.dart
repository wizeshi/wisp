// Copyright © 2026 wizeshi

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

Future<void> _waitUntilLoaded(PreferencesProvider provider) async {
  if (provider.isLoaded) return;
  final completer = Completer<void>();
  void listener() {
    if (provider.isLoaded && !completer.isCompleted) {
      completer.complete();
    }
  }

  provider.addListener(listener);
  try {
    await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    provider.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PreferencesProvider paused background widgets', () {
    test('defaults to all PausedBackgroundWidget values when unset', () async {
      SharedPreferences.setMockInitialValues({});

      final provider = PreferencesProvider();
      await _waitUntilLoaded(provider);

      expect(
        provider.pausedBackgroundWidgetsEnabled,
        equals(PausedBackgroundWidget.values),
      );
      expect(
        provider.pausedBackgroundWidgetsEnabled,
        contains(PausedBackgroundWidget.lyricsPreview),
      );
    });

    test('preserves explicitly saved empty list', () async {
      SharedPreferences.setMockInitialValues({
        'paused_background_widgets_enabled': <String>[],
      });

      final provider = PreferencesProvider();
      await _waitUntilLoaded(provider);

      expect(provider.pausedBackgroundWidgetsEnabled, isEmpty);
    });
  });

  group('PreferencesProvider LAN Connect', () {
    test('defaults to true when unset and persists toggles', () async {
      SharedPreferences.setMockInitialValues({});

      final provider = PreferencesProvider();
      await _waitUntilLoaded(provider);
      expect(provider.lanConnectEnabled, isTrue);

      await provider.setLanConnectEnabled(false);
      expect(provider.lanConnectEnabled, isFalse);

      final reloaded = PreferencesProvider();
      await _waitUntilLoaded(reloaded);
      expect(reloaded.lanConnectEnabled, isFalse);

      await reloaded.setLanConnectEnabled(true);
      expect(reloaded.lanConnectEnabled, isTrue);
    });
  });
}
