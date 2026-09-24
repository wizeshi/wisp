// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';

/// Compact "Now Playing" banner shown at the top of the DJ view.
///
/// Shows a DJ Mode badge, track artwork, title, and artists. When [isPlaying]
/// is true, the badge has a pulsing live dot.
class DJNowPlayingBanner extends StatefulWidget {
  final GenericSong? track;
  final bool isPlaying;

  const DJNowPlayingBanner({
    super.key,
    required this.track,
    required this.isPlaying,
  });

  @override
  State<DJNowPlayingBanner> createState() => _DJNowPlayingBannerState();
}

class _DJNowPlayingBannerState extends State<DJNowPlayingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = widget.track;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: track != null
                  ? ArtworkThumbnail(
                      source: ArtworkSource.fromUrl(track.thumbnailUrl),
                      size: ArtworkSize.small,
                      sizeOverride: 56,
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Symbols.music_note,
                        size: 28,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            // Text info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge row
                  Row(
                    children: [
                      Builder(
                        builder: (context) {
                          final badgeBg = theme.colorScheme.primaryContainer;
                          final badgeFg =
                              ThemeData.estimateBrightnessForColor(badgeBg) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.isPlaying) ...[
                                  AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (_, _) => Opacity(
                                      opacity: _pulseAnimation.value,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: badgeFg,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Text(
                                  'DJ Mode',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: badgeFg,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (track != null) ...[
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      track.artists.map((a) => a.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    Text(
                      'Nothing playing — pick a vibe below!',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

