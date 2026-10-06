// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/features/playback/services/playlist_playback_helper.dart';
import 'package:wisp/shared/widgets/rows/generic_row.dart';
import 'package:wisp/features/details/views/list_detail_view.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/shared/widgets/artwork/liked_songs_art.dart';
import 'package:wisp/core/utils/liked_songs.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/playback/playback_selectors.dart';

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
  final double height;
  final EdgeInsetsGeometry padding;
  final GenericRowPlayPosition playPosition;
  final Color? backgroundColor;
  final bool showSubtitle;
  final bool isCollapsed;

  const PlaylistRow({
    super.key,
    required this.playlist,
    this.width = 160,
    this.height = 48,
    this.padding = EdgeInsets.zero,
    this.playPosition = GenericRowPlayPosition.end,
    this.backgroundColor,
    this.showSubtitle = true,
    this.isCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.watchIsPlayingPlaylist(
      playlistId: playlist.id,
      playlistTitle: playlist.title,
    );
    return GenericRow(
      width: width,
      height: height,
      padding: padding,
      playPosition: playPosition,
      backgroundColor: backgroundColor,
      showSubtitle: showSubtitle,
      isCollapsed: isCollapsed,
      title: playlist.title,
      subtitle: playlistSubtitle(playlist),
      artwork: (playlist.title == "Liked Songs" || isLikedSongsPlaylistId(playlist.id))
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LikedSongsArt(size: ArtworkSize.large.logicalSize),
            )
          : ArtworkThumbnail(
              source: ArtworkSource.fromUrl(playlist.thumbnailUrl),
              size: ArtworkSize.large,
              fallbackIcon: Icons.playlist_play,
              semanticLabel: 'Artwork for ${playlist.title}',
            ),
      isPlaying: isPlaying,
      onTap: () {
        if (playlist.source.toLowerCase() == 'spotify' && playlist.title == "DJ" && playlist.author.displayName == "Spotify") {
          AppNavigation.instance.navigateToDJView(context);
        } else {
          AppNavigation.instance.openSharedList(
            context,
            id: playlist.id,
            type: SharedListType.playlist,
            initialTitle: playlist.title,
            initialThumbnailUrl: playlist.thumbnailUrl,
          );
        }
      },
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
    );
  }
}
