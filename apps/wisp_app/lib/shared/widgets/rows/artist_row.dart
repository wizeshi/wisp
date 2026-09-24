import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/shared/widgets/rows/generic_row.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/playback/playback_selectors.dart';

class ArtistRow extends StatelessWidget {
  final GenericSimpleArtist artist;
  final double width;
  final double height;
  final EdgeInsetsGeometry padding;
  final GenericRowPlayPosition playPosition;

  final String? subtitle;
  final Color? backgroundColor;
  final bool showSubtitle;

  const ArtistRow({
    super.key,
    required this.artist,
    this.subtitle,
    this.width = 160,
    this.height = 48,
    this.padding = EdgeInsets.zero,
    this.playPosition = GenericRowPlayPosition.end,
    this.backgroundColor,
    this.showSubtitle = true,
  });

  Future<void> _startArtistPlayback(BuildContext context) async {
    final coordinator = context.read<PlaybackCoordinator>();

    switch (artist.source) {
      case SongSource.spotify:
      case SongSource.spotifyInternal:
        {
          final spotify = context.read<SpotifyInternalProvider>();
          try {
            final artist = await spotify.getArtistInfo(this.artist.id);
            final tracks = artist.topSongs;
            if (tracks.isEmpty) return;
            if (context.mounted) {
              await coordinator.setQueue(
                tracks,
                startIndex: 0,
                play: true,
                playbackContext: PlaybackContext(
                  type: PlaybackContextType.artist,
                  name: artist.name,
                  id: artist.id,
                  source: artist.source,
                ),
              );
            }
          } catch (_) {}
        }

      default:
        break;
    }
  }

  Future<void> _toggleArtistPlayback(BuildContext context) async {
    final audioHandler = context.read<PlaybackCoordinator>().audioHandler;
    // Check if artist is currently active, and if so, whether it's playing or paused. If it's active and playing, pause it; otherwise, play it.
    if (audioHandler != null) {
      if (audioHandler.playbackContext?.type == PlaybackContextType.artist &&
          audioHandler.playbackContext?.id == artist.id) {
        if (audioHandler.isPlaying) {
          return audioHandler.pause();
        } else {
          return audioHandler.play();
        }
      } else {
        // Artist is not active, so play it.
        return _startArtistPlayback(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.watchIsPlayingArtist(
      artistId: artist.id,
      artistName: artist.name,
    );
    return GenericRow(
      width: width,
      height: height,
      padding: padding,
      playPosition: playPosition,
      backgroundColor: backgroundColor,
      showSubtitle: showSubtitle,
      title: artist.name,
      subtitle: subtitle ?? 'Artist',
      artwork: ArtworkThumbnail(
        source: ArtworkSource.fromUrl(artist.thumbnailUrl),
        size: ArtworkSize.large,
        shape: ArtworkShape.circle,
        fallbackIcon: Icons.person,
        semanticLabel: 'Photo of ${artist.name}',
      ),
      isPlaying: isPlaying,
      onTap: () =>
          AppNavigation.instance.openArtist(context, artistId: artist.id),
      onPlay: () => _toggleArtistPlayback(context),
      onSecondaryTapDown: (details) {
        EntityContextMenus.showArtistMenu(
          context,
          artist: artist,
          globalPosition: details.globalPosition,
        );
      },
      onLongPress: () {
        EntityContextMenus.showArtistMenu(context, artist: artist);
      },
    );
  }
}
