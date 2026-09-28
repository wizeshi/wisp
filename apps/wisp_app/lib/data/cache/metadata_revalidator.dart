// Copyright © 2026 wizeshi

/// Generic stale-while-revalidate coordinator for metadata screens and resources
library;

import 'dart:io';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/services/system/connectivity_service.dart';

/// Optional cancellation token to abort a revalidation operation
/// (e.g. when widget is disposed or new navigation occurred).
class MetadataRevalidatorToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class MetadataRevalidator {
  MetadataRevalidator._();

  /// Executes a stale-while-revalidate workflow:
  /// 1. Reads cache first via [loadCache]. If present, triggers [onData] immediately.
  /// 2. Checks network connectivity via [ConnectivityService].
  /// 3. If offline, stops gracefully (retaining cached data if present).
  /// 4. If online, fetches fresh data via [fetchRemote] in the background.
  /// 5. Compares fresh data with cached data via [hasChanged].
  ///    Only if different does it trigger [onData] with the new data.
  /// 6. If background fetch fails while cached data is displayed, retains cached data.
  static Future<void> revalidate<T>({
    required Future<T?> Function() loadCache,
    required Future<T> Function() fetchRemote,
    required bool Function(T current, T fresh) hasChanged,
    required void Function(T data, {required bool fromCache}) onData,
    void Function(bool isRefreshing)? onRefreshing,
    void Function(Object error)? onError,
    MetadataRevalidatorToken? token,
    ConnectivityService? connectivityService,
  }) async {
    final connectivity = connectivityService ?? ConnectivityService.instance;
    T? cachedData;

    // 1. Check whether entity is already cached and display immediately if so
    try {
      cachedData = await loadCache();
      if (token?.isCancelled ?? false) return;
      if (cachedData != null) {
        onData(cachedData, fromCache: true);
      }
    } catch (e) {
      logger.w('[MetadataRevalidator] Cache read error: $e');
    }

    if (token?.isCancelled ?? false) return;

    // 2. Check network connectivity state
    final isOnline = connectivity.isOnline;
    if (token?.isCancelled ?? false) return;

    if (!isOnline) {
      logger.d('[MetadataRevalidator] Offline: skipping background refresh');
      if (cachedData == null) {
        onError?.call(const SocketException('No internet connection'));
      }
      return;
    }

    // 3. If online, attempt background refresh
    onRefreshing?.call(true);
    try {
      final freshData = await fetchRemote();
      if (token?.isCancelled ?? false) return;

      // 4. Update UI only if refreshed data differs from cached data
      if (cachedData == null || hasChanged(cachedData, freshData)) {
        logger.d('[MetadataRevalidator] Data changed (or no cache), updating UI');
        onData(freshData, fromCache: false);
      } else {
        logger.d('[MetadataRevalidator] Fresh data identical to cache, retaining current UI');
      }
    } catch (e) {
      logger.w('[MetadataRevalidator] Remote refresh error: $e');
      if (token?.isCancelled ?? false) return;
      // Retain cached data on background refresh errors
      if (cachedData == null) {
        onError?.call(e);
      }
    } finally {
      if (!(token?.isCancelled ?? false)) {
        onRefreshing?.call(false);
      }
    }
  }
}
