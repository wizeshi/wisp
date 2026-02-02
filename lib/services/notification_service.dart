/// Notification service for download progress
library;

import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger.dart';
import 'desktop_notification_center.dart';

/// Service for showing download progress notifications on mobile
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  
  NotificationService._();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  
  /// Notification channel ID for downloads
  static const String _downloadChannelId = 'download_progress';
  static const String _downloadChannelName = 'Download Progress';
  static const String _downloadChannelDesc = 'Shows progress of audio downloads';
  
  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _initialized = true;
      return; // Desktop doesn't need notifications
    }
    
    try {
      // Android settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      await _notifications.initialize(initSettings);
      
      // Create Android notification channel
      if (Platform.isAndroid) {
        final androidPlugin = _notifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            _downloadChannelId,
            _downloadChannelName,
            description: _downloadChannelDesc,
            importance: Importance.low, // Silent notification
            showBadge: false,
            playSound: false,
            enableVibration: false,
          ),
        );
      }
      
      _initialized = true;
      logger.i('[Notification] Service initialized successfully');
    } catch (e) {
      logger.e('[Notification] Error initializing notifications', error: e);
    }
  }
  
  /// Show or update download progress notification
  Future<void> showDownloadProgress({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      DesktopNotificationCenter.instance.showProgress(
        id: id,
        title: title,
        body: body,
        progress: progress,
        maxProgress: maxProgress,
      );
      return;
    }
    if (!_initialized || (!Platform.isAndroid && !Platform.isIOS)) {
      logger.d('[Notification] Not showing (initialized=$_initialized, platform=${Platform.isAndroid ? 'Android' : Platform.isIOS ? 'iOS' : 'Other'})');
      return;
    }
    
    logger.d('[Notification] Showing progress: $title ($progress/$maxProgress)');
    try {
      final androidDetails = AndroidNotificationDetails(
        _downloadChannelId,
        _downloadChannelName,
        channelDescription: _downloadChannelDesc,
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: maxProgress,
        progress: progress,
        ongoing: true,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
        silent: true,
        category: AndroidNotificationCategory.progress,
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
      );
      
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications.show(id, title, body, details);
      logger.d('[Notification] Progress notification shown (id=$id)');
    } catch (e) {
      logger.e('[Notification] Error showing progress notification', error: e);
    }
  }
  
  /// Show download complete notification
  Future<void> showDownloadComplete({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      DesktopNotificationCenter.instance.showComplete(
        id: id,
        title: title,
        body: body,
      );
      return;
    }
    if (!_initialized || (!Platform.isAndroid && !Platform.isIOS)) return;
    
    logger.d('[Notification] Showing completion: $title');
    try {
      final androidDetails = AndroidNotificationDetails(
        _downloadChannelId,
        _downloadChannelName,
        channelDescription: _downloadChannelDesc,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: false,
        playSound: false,
        enableVibration: false,
        silent: true,
        autoCancel: true,
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
      );
      
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications.show(id, title, body, details);
      logger.d('[Notification] Complete notification shown (id=$id)');
      
      // Auto dismiss after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        cancelNotification(id);
      });
    } catch (e) {
      logger.e('[Notification] Error showing complete notification', error: e);
    }
  }

  /// Show a generic alert notification
  Future<void> showAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      DesktopNotificationCenter.instance.showComplete(
        id: id,
        title: title,
        body: body,
      );
      return;
    }
    if (!_initialized || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      final androidDetails = AndroidNotificationDetails(
        _downloadChannelId,
        _downloadChannelName,
        channelDescription: _downloadChannelDesc,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: false,
        playSound: false,
        enableVibration: false,
        silent: true,
        autoCancel: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(id, title, body, details);
    } catch (e) {
      logger.e('[Notification] Error showing alert notification', error: e);
    }
  }
  
  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      DesktopNotificationCenter.instance.dismiss(id);
      return;
    }
    if (!_initialized || (!Platform.isAndroid && !Platform.isIOS)) return;
    
    try {
      await _notifications.cancel(id);
    } catch (e) {
      logger.e('Error cancelling notification', error: e);
    }
  }
  
  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      DesktopNotificationCenter.instance.clearAll();
      return;
    }
    if (!_initialized || (!Platform.isAndroid && !Platform.isIOS)) return;
    
    try {
      await _notifications.cancelAll();
    } catch (e) {
      logger.e('Error cancelling all notifications', error: e);
    }
  }
}
