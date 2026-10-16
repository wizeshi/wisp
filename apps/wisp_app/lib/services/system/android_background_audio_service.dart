// Copyright © 2026 wizeshi

library;

import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:wisp/core/utils/logger.dart';

/// Manages native Android CPU WakeLock and Wi-Fi Lock during audio playback to
/// ensure background streaming, decryption, and track transitions remain uninterrupted.
class AndroidBackgroundAudioService {
  static final AndroidBackgroundAudioService instance = AndroidBackgroundAudioService._();
  AndroidBackgroundAudioService._();

  static const MethodChannel _channel = MethodChannel('dev.wizeshi.wisp/background_audio');
  bool _locksAcquired = false;

  bool get locksAcquired => _locksAcquired;

  Future<void> acquireLocks() async {
    if (!Platform.isAndroid || _locksAcquired) return;
    try {
      final success = await _channel.invokeMethod<bool>('acquireLocks');
      if (success == true) {
        _locksAcquired = true;
        logger.d('[BackgroundAudio] Acquired partial wake lock and wifi lock');
      }
    } catch (e) {
      logger.w('[BackgroundAudio] Failed to acquire background locks: $e');
    }
  }

  Future<void> releaseLocks() async {
    if (!Platform.isAndroid || !_locksAcquired) return;
    try {
      final success = await _channel.invokeMethod<bool>('releaseLocks');
      if (success == true) {
        _locksAcquired = false;
        logger.d('[BackgroundAudio] Released partial wake lock and wifi lock');
      }
    } catch (e) {
      logger.w('[BackgroundAudio] Failed to release background locks: $e');
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isDataSaverRestricted() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isDataSaverRestricted') ?? false;
    } catch (e) {
      return false;
    }
  }
}

