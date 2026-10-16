// Copyright © 2026 wizeshi

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/services/system/android_background_audio_service.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidBackgroundAudioService Tests', () {
    test('Non-Android platform gracefully handles acquireLocks and releaseLocks', () async {
      final service = AndroidBackgroundAudioService.instance;
      expect(service.locksAcquired, isFalse);

      // On non-Android (e.g. host running test), these are safe no-ops
      await service.acquireLocks();
      expect(service.locksAcquired, isFalse);

      await service.releaseLocks();
      expect(service.locksAcquired, isFalse);
    });

    test('Non-Android platform defaults isIgnoringBatteryOptimizations to true', () async {
      final service = AndroidBackgroundAudioService.instance;
      final ignoring = await service.isIgnoringBatteryOptimizations();
      expect(ignoring, isTrue);
    });

    test('Non-Android platform defaults isDataSaverRestricted to false', () async {
      final service = AndroidBackgroundAudioService.instance;
      final restricted = await service.isDataSaverRestricted();
      expect(restricted, isFalse);
    });
  });

  group('RepeatMode Cycling Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('RepeatMode enum has expected values and order (off, all, one)', () {
      expect(RepeatMode.values, equals([
        RepeatMode.off,
        RepeatMode.all,
        RepeatMode.one,
      ]));

      // Verify modular index advance logic used in toggleRepeat()
      var mode = RepeatMode.off;
      mode = RepeatMode.values[(mode.index + 1) % RepeatMode.values.length];
      expect(mode, equals(RepeatMode.all));

      mode = RepeatMode.values[(mode.index + 1) % RepeatMode.values.length];
      expect(mode, equals(RepeatMode.one));

      mode = RepeatMode.values[(mode.index + 1) % RepeatMode.values.length];
      expect(mode, equals(RepeatMode.off));
    });
  });
}
