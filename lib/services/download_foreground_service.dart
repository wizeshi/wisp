/// Foreground service wrapper for background downloads on Android
library;

import 'dart:io' show Platform;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class DownloadForegroundService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'download_foreground',
        channelName: 'Download Service',
        channelDescription: 'Keeps downloads running in background',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
        showBadge: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static Future<void> start({required String title, required String text}) async {
    if (!Platform.isAndroid) return;
    await initialize();

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: text,
      callback: _startCallback,
    );
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_DownloadTaskHandler());
}

class _DownloadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
