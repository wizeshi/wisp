import 'package:flutter/material.dart';

import '../../models/metadata_models.dart';
import '../artwork/artwork_thumbnail.dart';
import '../playback/playback_selectors.dart';
import 'generic_card.dart';

class TrackCard extends StatelessWidget {
  final GenericSong track;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;
  final double? width;

  const TrackCard({
    super.key,
    required this.track,
    required this.onTap,
    required this.onPlay,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.watchIsPlayingTrack(track.id);
    return GenericCard(
      title: track.title,
      subtitle: track.artists.map((artist) => artist.name).join(', '),
      artwork: ArtworkThumbnail(
        source: ArtworkSource.fromUrl(track.thumbnailUrl),
        size: ArtworkSize.large,
        fallbackIcon: Icons.music_note,
        semanticLabel: 'Artwork for ${track.title}',
      ),
      isPlaying: isPlaying,
      onTap: onTap,
      onPlay: onPlay,
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      width: width,
    );
  }
}
