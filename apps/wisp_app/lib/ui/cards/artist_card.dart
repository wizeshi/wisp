import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/providers/metadata/spotify_internal.dart';
import 'package:wisp/services/app_navigation.dart';
import 'package:wisp/services/playback/playback_coordinator.dart';
import 'package:wisp/services/wisp_audio_handler.dart';
import 'package:wisp/widgets/entity_context_menus.dart';

import '../../models/metadata_models.dart';
import '../artwork/artwork_thumbnail.dart';
import '../playback/playback_selectors.dart';
import 'generic_card.dart';

/// A [GenericCard] for a [GenericSimpleArtist], with circular artwork.
///
/// Takes [GenericSimpleArtist] (id/name/thumbnailUrl only) rather than the
/// full [GenericArtist] — a card never needs an artist's top songs or
/// albums, and [GenericSimpleArtist] is what's already available in every
/// list/search/rail context this card is meant for.
class ArtistCard extends StatelessWidget {
  final GenericSimpleArtist artist;
  final double width;

  /// Optional subtitle override (e.g. "Artist", a follower count). Null by
  /// default since [GenericSimpleArtist] has no such field to derive one
  /// from — pass one explicitly if the calling screen has it.
  final String? subtitle;

  const ArtistCard({
    super.key,
    required this.artist,
    this.subtitle,
    this.width = 160,
  });

  Future<void> _startArtistPlayback(BuildContext context) async {
    final coordinator = context.read<PlaybackCoordinator>();

    switch (artist.source) {
      case SongSource.spotify:
      case SongSource.spotifyInternal: {
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
      } else { // Artist is not active, so play it.
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
    return GenericCard(
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
      onTap: () => AppNavigation.instance.openArtist(
        context, 
        artistId: artist.id
      ),
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
      width: width,
    );
  }
}