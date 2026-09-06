import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/providers/metadata/spotify_internal.dart';
import 'package:wisp/services/app_navigation.dart';
import 'package:wisp/services/playback/playback_coordinator.dart';
import 'package:wisp/services/wisp_audio_handler.dart';
import 'package:wisp/ui/rows/generic_row.dart';
import 'package:wisp/views/list_detail.dart';
import 'package:wisp/widgets/entity_context_menus.dart';

import '../../models/metadata_models.dart';
import '../artwork/artwork_thumbnail.dart';
import '../playback/playback_selectors.dart';

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

class PlaylistRow extends StatelessWidget {
  final GenericPlaylist playlist;
  final double width;

  const PlaylistRow({super.key, required this.playlist, this.width = 160});

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
    final startTime = DateTime.now();
    print(
      'Toggling playlist playback for ${playlist.title} at ${startTime.toIso8601String()}',
    );

    final audioHandler = context.read<PlaybackCoordinator>().audioHandler;
    // Check if playlist is currently active, and if so, whether it's playing or paused. If it's active and playing, pause it; otherwise, play it.
    if (audioHandler != null) {
      if (audioHandler.playbackContext?.type == PlaybackContextType.playlist &&
          audioHandler.playbackContext?.id == playlist.id) {
        if (audioHandler.isPlaying) {
          print(
            'Pausing playlist playback for ${playlist.title} at ${DateTime.now().toIso8601String()}',
          );
          print(
            'Time taken to pause: ${DateTime.now().difference(startTime).inMilliseconds} ms',
          );
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
    return GenericRow(
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
