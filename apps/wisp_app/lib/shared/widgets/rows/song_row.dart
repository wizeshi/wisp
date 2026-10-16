// Copyright © 2026 wizeshi

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/shared/widgets/playback/playback_selectors.dart';
import 'generic_row.dart';

/// A standard row widget representing a single [GenericSong] in lists where
/// playback is driven by song identity rather than a structured parent view
/// context (e.g. Home quick tiles, simple item lists).
class SongRow extends StatelessWidget {
  final GenericSong song;
  final double width;
  final double height;
  final EdgeInsetsGeometry padding;
  final GenericRowPlayPosition playPosition;
  final Color? backgroundColor;
  final bool showSubtitle;
  final bool isCollapsed;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  const SongRow({
    super.key,
    required this.song,
    this.width = 160,
    this.height = 48,
    this.padding = EdgeInsets.zero,
    this.playPosition = GenericRowPlayPosition.end,
    this.backgroundColor,
    this.showSubtitle = true,
    this.isCollapsed = false,
    this.trailing,
    this.onTap,
    this.onPlay,
    this.onLongPress,
    this.onSecondaryTapDown,
  });

  static Future<void> playSong(BuildContext context, GenericSong song) async {
    final coordinator = context.read<PlaybackCoordinator>();
    await coordinator.setQueue([song], startIndex: 0, play: true);
  }

  static Future<void> toggleSongPlayback(
    BuildContext context,
    GenericSong song,
  ) async {
    final player = context.read<WispAudioHandler>();
    if (player.currentTrack?.id == song.id) {
      final coordinator = context.read<PlaybackCoordinator>();
      if (player.isPlaying) {
        unawaited(coordinator.pause());
        return;
      }
      if (player.state == PlaybackState.paused) {
        unawaited(coordinator.play());
        return;
      }
    }
    await playSong(context, song);
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.watchIsPlayingTrack(song.id);
    final subtitleText = song.artists.map((a) => a.name).join(', ');

    return GenericRow(
      width: width,
      height: height,
      padding: padding,
      playPosition: playPosition,
      backgroundColor: backgroundColor,
      showSubtitle: showSubtitle,
      isCollapsed: isCollapsed,
      trailing: trailing,
      title: song.title,
      subtitle: subtitleText.isNotEmpty ? subtitleText : null,
      artwork: ArtworkThumbnail(
        source: ArtworkSource.fromUrl(song.thumbnailUrl),
        size: ArtworkSize.large,
        fallbackIcon: Icons.music_note,
        semanticLabel: 'Artwork for ${song.title}',
      ),
      isPlaying: isPlaying,
      onTap: onTap ?? () => toggleSongPlayback(context, song),
      onPlay: onPlay ?? () => toggleSongPlayback(context, song),
      onDoubleTap: () => playSong(context, song),
      onSecondaryTapDown: onSecondaryTapDown ??
          (details) {
            EntityContextMenus.showTrackMenu(
              context,
              track: song,
              globalPosition: details.globalPosition,
            );
          },
      onLongPress: onLongPress ??
          () {
            EntityContextMenus.showTrackMenu(context, track: song);
          },
    );
  }
}
