// Copyright © 2026 wizeshi

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/features/details/views/list_detail_view.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/playback/playback_selectors.dart';
import 'generic_card.dart';

class AlbumCard extends StatelessWidget {
  final GenericAlbum album;
  final String? subtitle;
  final double? width;

  const AlbumCard({
    super.key,
    required this.album,
    this.subtitle,
    this.width,
  });

  factory AlbumCard.fromSimpleAlbum({
    Key? key,
    required GenericSimpleAlbum album,
    String? subtitle,
    double? width,
  }) {
    return AlbumCard(
      key: key,
      album: album.toAlbum(),
      subtitle: subtitle,
      width: width,
    );
  }

  Future<void> _startAlbumPlayback(BuildContext context) async {
    final coordinator = context.read<PlaybackCoordinator>();
    final metadataManager = context.read<MetadataManager>();

    try {
      final fullAlbum = await metadataManager.getAlbumInfo(
        album.id,
        source: album.source,
      );
      final tracks = fullAlbum.songs ?? [];
      if (tracks.isEmpty) return;
      if (context.mounted) {
        await coordinator.setQueue(
          tracks,
          startIndex: 0,
          play: true,
          playbackContext: PlaybackContext(
            type: PlaybackContextType.album,
            name: fullAlbum.title,
            id: fullAlbum.id,
            source: fullAlbum.source,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _toggleAlbumPlayback(BuildContext context) async {
    final audioHandler = context.read<PlaybackCoordinator>().audioHandler;
    // Check if album is currently active, and if so, whether it's playing or paused. If it's active and playing, pause it; otherwise, play it.
    if (audioHandler != null) {
      if (audioHandler.playbackContext?.type == PlaybackContextType.album &&
          audioHandler.playbackContext?.id == album.id) {
        if (audioHandler.isPlaying) {
          return audioHandler.pause();
        } else {
          return audioHandler.play();
        }
      } else {
        // Album is not active, so play it.
        return _startAlbumPlayback(context);
      }
    }
  }

  Future<void> _playAlbum(BuildContext context) async {
    final audioHandler = context.read<PlaybackCoordinator>().audioHandler;
    if (audioHandler != null &&
        audioHandler.playbackContext?.type == PlaybackContextType.album &&
        audioHandler.playbackContext?.id == album.id) {
      if (!audioHandler.isPlaying) {
        return audioHandler.play();
      }
      return _startAlbumPlayback(context);
    }
    return _startAlbumPlayback(context);
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.watchIsPlayingAlbum(
      albumId: album.id,
      albumTitle: album.title,
    );
    return GenericCard(
      title: album.title,
      subtitle:
          subtitle ?? album.artists.map((artist) => artist.name).join(', '),
      artwork: ArtworkThumbnail(
        source: ArtworkSource.fromUrl(album.thumbnailUrl),
        size: ArtworkSize.large,
        fallbackIcon: Icons.album,
        semanticLabel: 'Artwork for ${album.title}',
      ),
      isPlaying: isPlaying,
      onTap: () => AppNavigation.instance.openSharedList(
        context,
        id: album.id,
        type: SharedListType.album,
        initialTitle: album.title,
        initialThumbnailUrl: album.thumbnailUrl,
      ),
      onPlay: () => _toggleAlbumPlayback(context),
      onDoubleTap: () => _playAlbum(context),
      onSecondaryTapDown: (details) {
        EntityContextMenus.showAlbumMenu(
          context,
          album: album,
          globalPosition: details.globalPosition,
        );
      },
      onLongPress: () {
        EntityContextMenus.showAlbumMenu(context, album: album);
      },
      width: width,
    );
  }
}
