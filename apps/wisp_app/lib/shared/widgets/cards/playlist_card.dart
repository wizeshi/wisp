// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/features/playback/services/playlist_playback_helper.dart';
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
  final String? subtitle;
  final double? width;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.subtitle,
    this.width,
  });

  factory PlaylistCard.fromSimplePlaylist({
    Key? key,
    required GenericSimplePlaylist playlist,
    String? subtitle,
    double? width,
  }) {
    return PlaylistCard(
      key: key,
      playlist: playlist.toPlaylist(),
      subtitle: subtitle,
      width: width,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.watchIsPlayingPlaylist(
      playlistId: playlist.id,
      playlistTitle: playlist.title,
    );
    return GenericCard(
      title: playlist.title,
      subtitle: subtitle ?? playlistSubtitle(playlist),
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
      onPlay: () => PlaylistPlaybackHelper.togglePlaylistPlayback(context, playlist),
      onDoubleTap: () => PlaylistPlaybackHelper.playPlaylist(context, playlist),
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
