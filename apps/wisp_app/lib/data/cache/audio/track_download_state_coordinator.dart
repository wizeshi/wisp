// Copyright © 2026 wizeshi

import 'package:flutter/foundation.dart';

enum TrackDownloadStatus {
  idle,
  queued,
  downloading,
  downloaded,
  failed,
}

/// Immutable state describing download and cache status for a single track.
class TrackDownloadProgress {
  final String trackId;
  final TrackDownloadStatus status;
  final double progress;
  final bool isCached;
  final String? errorMessage;

  const TrackDownloadProgress({
    required this.trackId,
    this.status = TrackDownloadStatus.idle,
    this.progress = 0.0,
    this.isCached = false,
    this.errorMessage,
  });

  bool get isDownloading => status == TrackDownloadStatus.downloading;
  bool get isQueued => status == TrackDownloadStatus.queued;
}

/// Granular coordinator managing per-track download progress.
///
/// Rather than calling global `notifyListeners()` on every Dio progress chunk,
/// widgets bind directly to `watch(trackId)`. Only the specific track that is
/// downloading or state-changing rebuilds.
class TrackDownloadStateCoordinator {
  final Map<String, ValueNotifier<TrackDownloadProgress>> _notifiers = {};

  /// Returns a `ValueListenable` scoped specifically to [trackId].
  ValueListenable<TrackDownloadProgress> watch(
    String trackId, {
    bool isCached = false,
  }) {
    return _getOrCreateNotifier(trackId, isCached: isCached);
  }

  ValueNotifier<TrackDownloadProgress> _getOrCreateNotifier(
    String trackId, {
    bool isCached = false,
  }) {
    return _notifiers.putIfAbsent(
      trackId,
      () => ValueNotifier(
        TrackDownloadProgress(
          trackId: trackId,
          status: isCached ? TrackDownloadStatus.downloaded : TrackDownloadStatus.idle,
          progress: isCached ? 1.0 : 0.0,
          isCached: isCached,
        ),
      ),
    );
  }

  void setQueued(String trackId) {
    final notifier = _notifiers[trackId];
    final current = notifier?.value;
    final isCached = current?.isCached ?? false;
    _getOrCreateNotifier(trackId).value = TrackDownloadProgress(
      trackId: trackId,
      status: TrackDownloadStatus.queued,
      progress: 0.0,
      isCached: isCached,
    );
  }

  void setProgress(String trackId, double progress) {
    final notifier = _notifiers[trackId];
    final current = notifier?.value;
    final isCached = current?.isCached ?? false;
    _getOrCreateNotifier(trackId).value = TrackDownloadProgress(
      trackId: trackId,
      status: TrackDownloadStatus.downloading,
      progress: progress.clamp(0.0, 1.0),
      isCached: isCached,
    );
  }

  void setCompleted(String trackId) {
    _getOrCreateNotifier(trackId).value = TrackDownloadProgress(
      trackId: trackId,
      status: TrackDownloadStatus.downloaded,
      progress: 1.0,
      isCached: true,
    );
  }

  void setFailed(String trackId, String? errorMessage) {
    final notifier = _notifiers[trackId];
    final current = notifier?.value;
    final isCached = current?.isCached ?? false;
    _getOrCreateNotifier(trackId).value = TrackDownloadProgress(
      trackId: trackId,
      status: TrackDownloadStatus.failed,
      progress: 0.0,
      isCached: isCached,
      errorMessage: errorMessage,
    );
  }

  void setRemoved(String trackId) {
    _getOrCreateNotifier(trackId).value = TrackDownloadProgress(
      trackId: trackId,
      status: TrackDownloadStatus.idle,
      progress: 0.0,
      isCached: false,
    );
  }

  void setCachedState(String trackId, bool isCached) {
    final notifier = _notifiers[trackId];
    final current = notifier?.value;
    if (current == null) {
      _notifiers[trackId] = ValueNotifier(
        TrackDownloadProgress(
          trackId: trackId,
          status: isCached ? TrackDownloadStatus.downloaded : TrackDownloadStatus.idle,
          progress: isCached ? 1.0 : 0.0,
          isCached: isCached,
        ),
      );
    } else if (current.isCached != isCached) {
      notifier!.value = TrackDownloadProgress(
        trackId: trackId,
        status: isCached
            ? TrackDownloadStatus.downloaded
            : (current.isDownloading ? TrackDownloadStatus.downloading : TrackDownloadStatus.idle),
        progress: isCached ? 1.0 : current.progress,
        isCached: isCached,
        errorMessage: current.errorMessage,
      );
    }
  }

  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
  }
}
