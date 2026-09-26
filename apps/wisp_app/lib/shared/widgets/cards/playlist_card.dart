// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/features/details/views/list_detail_view.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/playback/playback_selectors.dart';
import 'generic_card.dart';

String playlistSubtitle(GenericPlaylist playlist) {
  final author = playlist.author.displayName.trim();
  final description = playlist.description?.trim() ?? '';
  if (author.toLowerCase() == 'spotify' && description.isNotEmpty) {
    return description;
  }
  if (author.isEmpty && description.isNotEmpty) {
    return description;
  }
  return author;
}

class PlaylistCard extends StatelessWidget {
  final GenericPlaylist playlist;
  final double? width;

  const PlaylistCard({super.key, required this.playlist, this.width});

  Future<void> _startPlaylistPlayback(BuildContext context) async {
    final coordinator = context.read<PlaybackCoordinator>();

    switch (playlist.source) {
      case SongSource.spotify:
      case SongSource.spotifyInternal:
        {
          final spotify = context.read<SpotifyInternalProvider>();
          try {
            final playlist = await spotify.getPlaylistInfo(this.playlist.id);
            final items = playlist.songs ?? [];
            if (items.isEmpty) return;
            final tracks = items
                .map(
                  (item) => GenericSong(
                    id: item.id,
                    source: item.source,
                    title: item.title,
                    artists: item.artists,
                    thumbnailUrl: item.thumbnailUrl,
                    explicit: item.explicit,
                    album: item.album,
                    durationSecs: item.durationSecs,
                  ),
                )
                .toList();
            if (tracks.isEmpty) return;
            if (context.mounted) {
              await coordinator.setQueue(
                tracks,
                startIndex: 0,
                play: true,
                playbackContext: PlaybackContext(
                  type: PlaybackContextType.playlist,
                  name: playlist.title,
                  id: playlist.id,
                  source: playlist.source,
                ),
              );
            }
          } catch (_) {}
        }

      default:
        break;
    }
  }

  Future<void> _togglePlaylistPlayback(BuildContext context) async {
    final audioHandler = context.read<PlaybackCoordinator>().audioHandler;
    // Check if playlist is currently active, and if so, whether it's playing or paused. If it's active and playing, pause it; otherwise, play it.
    if (audioHandler != null) {
      if (audioHandler.playbackContext?.type == PlaybackContextType.playlist &&
          audioHandler.playbackContext?.id == playlist.id) {
        if (audioHandler.isPlaying) {
          return audioHandler.pause();
        } else {
          return audioHandler.play();
        }
      } else {
        // Playlist is not active, so play it.
        return _startPlaylistPlayback(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.watchIsPlayingPlaylist(
      playlistId: playlist.id,
      playlistTitle: playlist.title,
    );
    return GenericCard(
      title: playlist.title,
      subtitle: playlistSubtitle(playlist),
      artwork: ArtworkThumbnail(
        source: ArtworkSource.fromUrl(playlist.thumbnailUrl),
        size: ArtworkSize.large,
        fallbackIcon: Icons.playlist_play,
        semanticLabel: 'Artwork for ${playlist.title}',
      ),
      isPlaying: isPlaying,
      onTap: () => AppNavigation.instance.openSharedList(
        context,
        id: playlist.id,
        type: SharedListType.playlist,
        initialTitle: playlist.title,
        initialThumbnailUrl: playlist.thumbnailUrl,
      ),
      onPlay: () => _togglePlaylistPlayback(context),
      onSecondaryTapDown: (details) {
        EntityContextMenus.showPlaylistMenu(
          context,
          playlist: playlist,
          globalPosition: details.globalPosition,
        );
      },
      onLongPress: () {
        EntityContextMenus.showPlaylistMenu(context, playlist: playlist);
      },
      width: width,
    );
  }
}
