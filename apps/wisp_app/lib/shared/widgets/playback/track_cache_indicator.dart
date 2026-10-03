// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/data/models/metadata_models.dart';

/// Cache/download state indicator for a single track:
/// - Cached: displays [Icons.offline_pin] in primary color
/// - Downloading: displays a small [CircularProgressIndicator] showing download progress
/// - Neither: collapses to [SizedBox.shrink]
class TrackCacheIndicator extends StatelessWidget {
  final String trackId;
  final double fontScaling;

  const TrackCacheIndicator({
    super.key,
    required this.trackId,
    this.fontScaling = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TrackDownloadProgress>(
      valueListenable: AudioCacheManager.instance.watchTrack(trackId),
      builder: (context, state, _) {
        final isCached = state.isCached;
        final isDownloading = state.isDownloading;
        if (!isCached && !isDownloading) return const SizedBox.shrink();
        if (isDownloading) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: SizedBox(
              width: 12 * fontScaling,
              height: 12 * fontScaling,
              child: CircularProgressIndicator(
                value: state.progress,
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Colors.grey[800],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            Icons.offline_pin,
            size: 12 * fontScaling,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}

/// Explicit badge + cache/download indicator row for a track.
///
/// Renders:
/// 1. [Icons.explicit] (if [track.explicit] is true) + 4px spacing
/// 2. [TrackCacheIndicator] (offline pin or download progress ring)
///
/// If neither badge applies, this collapses down without occupying space.
class TrackBadges extends StatelessWidget {
  final GenericSong track;
  final double fontScaling;

  const TrackBadges({
    super.key,
    required this.track,
    this.fontScaling = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (track.explicit) ...[
          Icon(
            Icons.explicit,
            size: 14 * fontScaling,
            color: Colors.grey[500],
          ),
          const SizedBox(width: 4),
        ],
        TrackCacheIndicator(
          trackId: track.id,
          fontScaling: fontScaling,
        ),
      ],
    );
  }
}
