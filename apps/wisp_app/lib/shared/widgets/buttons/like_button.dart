// Copyright © 2026 wizeshi

/// Shared Like button widget
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/shared/widgets/overlay/hover.dart';

class LikeButton extends StatefulWidget {
  final GenericSong? track;
  final double iconSize;
  final EdgeInsets padding;
  final BoxConstraints constraints;
  final bool showTooltip;
  final bool showIfUnliked;
  final Color color;
  final IconData? likedIcon;
  final IconData? notLikedIcon;

  /// When true, the button stays hidden until the row it's in is hovered,
  /// *except* while the track is liked, in which case it's always visible
  /// — the like-button behavior most music apps use in dense track lists
  /// (see [TrackRow]). Requires an ambient [HoverRegion] (i.e. this button
  /// needs to sit somewhere inside one) to know when that is; with none,
  /// it behaves as if never hovered.
  final bool hoverOnlyWhenUnliked;

  const LikeButton({
    super.key,
    required this.track,
    this.iconSize = 18,
    this.padding = const EdgeInsets.all(4),
    this.constraints = const BoxConstraints(minWidth: 28, minHeight: 28),
    this.showTooltip = true,
    this.showIfUnliked = true,
    this.color = Colors.white,
    this.likedIcon = Icons.favorite,
    this.notLikedIcon = Icons.favorite_border,
    this.hoverOnlyWhenUnliked = false,
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  @override
  void initState() {
    super.initState();
    final track = widget.track;
    if (track != null &&
        (track.source == SongSource.spotify ||
            track.source == SongSource.spotifyInternal)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<SpotifyInternalProvider>().ensureLikedTracksLoaded();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    if (track == null) {
      return const SizedBox.shrink();
    }

    final isLiked = context.select<SpotifyInternalProvider, bool>(
      (spotify) => spotify.isTrackLiked(track.id),
    );

    if (!widget.showIfUnliked && !isLiked) {
      return const SizedBox.shrink();
    }

    final isSpotifyTrack =
        track.source == SongSource.spotify ||
        track.source == SongSource.spotifyInternal;

    return Selector<SpotifyInternalProvider, bool>(
      selector: (context, spotify) =>
          isSpotifyTrack ? spotify.isTrackLiked(track.id) : false,
      builder: (context, isLiked, child) {
        final icon = isLiked ? widget.likedIcon : widget.notLikedIcon;
        final color = !isSpotifyTrack
            ? Colors.white
            : isLiked
            ? widget.color
            : Colors.white;

        final button = IconButton(
          padding: widget.padding,
          constraints: widget.constraints,
          icon: Icon(icon, size: widget.iconSize, color: color),
          onPressed: isSpotifyTrack
              ? () async {
                  await context.read<SpotifyInternalProvider>().toggleTrackLike(
                    track,
                  );
                }
              : null,
        );

        Widget content = widget.showTooltip
            ? Tooltip(
                message: isSpotifyTrack
                    ? (isLiked ? 'Remove from Likes' : 'Add to Likes')
                    : 'Spotify only',
                child: button,
              )
            : button;

        if (widget.hoverOnlyWhenUnliked) {
          content = HoverVisible(alwaysVisible: isLiked, child: content);
        }

        return content;
      },
    );
  }
}
