/// Shared Like button widget
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metadata_models.dart';
import '../providers/metadata/spotify.dart';

class LikeButton extends StatefulWidget {
  final GenericSong? track;
  final double iconSize;
  final EdgeInsets padding;
  final BoxConstraints constraints;
  final bool showTooltip;

  const LikeButton({
    super.key,
    required this.track,
    this.iconSize = 18,
    this.padding = const EdgeInsets.all(4),
    this.constraints = const BoxConstraints(minWidth: 28, minHeight: 28),
    this.showTooltip = true,
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  @override
  void initState() {
    super.initState();
    final track = widget.track;
    if (track != null && track.source == SongSource.spotify) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<SpotifyProvider>().ensureLikedTracksLoaded();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    if (track == null) {
      return const SizedBox.shrink();
    }

    final isSpotify = track.source == SongSource.spotify;

    return Selector<SpotifyProvider, bool>(
      selector: (context, spotify) =>
          isSpotify ? spotify.isTrackLiked(track.id) : false,
      builder: (context, isLiked, child) {
        final icon = isLiked ? Icons.favorite : Icons.favorite_border;
        final colorScheme = Theme.of(context).colorScheme;
        final color = !isSpotify
            ? Colors.grey[600]
            : isLiked
                ? colorScheme.primary
                : Colors.grey[400];

        final button = IconButton(
          padding: widget.padding,
          constraints: widget.constraints,
          icon: Icon(icon, size: widget.iconSize, color: color),
          onPressed: isSpotify
              ? () async {
                  await context
                      .read<SpotifyProvider>()
                      .toggleTrackLike(track);
                }
              : null,
        );

        if (!widget.showTooltip) {
          return button;
        }

        return Tooltip(
          message: isSpotify
              ? (isLiked ? 'Remove from Likes' : 'Add to Likes')
              : 'Spotify only',
          child: button,
        );
      },
    );
  }
}
