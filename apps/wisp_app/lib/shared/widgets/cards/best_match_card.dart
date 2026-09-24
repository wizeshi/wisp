import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/metadata_models.dart';
import '../../providers/preferences/preferences_provider.dart';
import '../../services/app_navigation.dart';
import '../../theme/app_theme.dart';
import '../../views/list_detail.dart';
import '../../widgets/entity_context_menus.dart';
import '../artwork/artwork_thumbnail.dart';
import '../overlay/cover_play_button.dart';
import '../overlay/hover.dart';
import '../playback/playback_selectors.dart';

/// A card representing the best match / top result in search.
///
/// Supports tracks, artists, albums, and playlists, and adapts to both
/// Spotify and Apple Music styles, as well as desktop and mobile layouts.
class BestMatchCard extends StatelessWidget {
  final SearchBestMatch bestMatch;
  final bool isMobile;
  final double? height;
  final AppStyle? style;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;

  const BestMatchCard({
    super.key,
    required this.bestMatch,
    this.isMobile = false,
    this.height,
    this.style,
    this.onTap,
    this.onPlay,
    this.onLongPress,
    this.onSecondaryTapDown,
  });

  void _showContextMenu(BuildContext context, {Offset? globalPosition}) {
    switch (bestMatch.kind) {
      case SearchBestMatchKind.track:
        final track = bestMatch.track;
        if (track != null) {
          EntityContextMenus.showTrackMenu(
            context,
            track: track,
            globalPosition: globalPosition,
          );
        }
      case SearchBestMatchKind.artist:
        final artist = bestMatch.artist;
        if (artist != null) {
          EntityContextMenus.showArtistMenu(
            context,
            artist: artist,
            globalPosition: globalPosition,
          );
        }
      case SearchBestMatchKind.album:
        final album = bestMatch.album;
        if (album != null) {
          EntityContextMenus.showAlbumMenu(
            context,
            album: album,
            globalPosition: globalPosition,
          );
        }
      case SearchBestMatchKind.playlist:
        final playlist = bestMatch.playlist;
        if (playlist != null) {
          EntityContextMenus.showPlaylistMenu(
            context,
            playlist: playlist,
            globalPosition: globalPosition,
          );
        }
    }
  }

  void _defaultTap(BuildContext context) {
    switch (bestMatch.kind) {
      case SearchBestMatchKind.track:
        final track = bestMatch.track;
        if (track == null) return;
        final album = track.album;
        if (album != null) {
          AppNavigation.instance.openSharedList(
            context,
            id: album.id,
            type: SharedListType.album,
            initialTitle: album.title,
            initialThumbnailUrl: album.thumbnailUrl,
          );
        }
      case SearchBestMatchKind.artist:
        final artist = bestMatch.artist;
        if (artist == null) return;
        AppNavigation.instance.openArtist(
          context,
          artistId: artist.id,
          initialArtist: artist,
        );
      case SearchBestMatchKind.album:
        final album = bestMatch.album;
        if (album == null) return;
        AppNavigation.instance.openSharedList(
          context,
          id: album.id,
          type: SharedListType.album,
          initialTitle: album.title,
          initialThumbnailUrl: album.thumbnailUrl,
        );
      case SearchBestMatchKind.playlist:
        final playlist = bestMatch.playlist;
        if (playlist == null) return;
        AppNavigation.instance.openSharedList(
          context,
          id: playlist.id,
          type: SharedListType.playlist,
          initialTitle: playlist.title,
          initialThumbnailUrl: playlist.thumbnailUrl,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle =
        style ?? context.select<PreferencesProvider, AppStyle>((p) => p.style);
    final isApple = effectiveStyle == AppStyle.AppleMusic;

    final String title;
    final String subtitle;
    final String imageUrl;
    final String kindLabel;
    final bool isArtist = bestMatch.kind == SearchBestMatchKind.artist;
    final bool isPlaying;

    switch (bestMatch.kind) {
      case SearchBestMatchKind.track:
        final track = bestMatch.track!;
        title = track.title;
        subtitle = track.artists.map((a) => a.name).join(', ');
        imageUrl = track.thumbnailUrl;
        kindLabel = 'Song';
        isPlaying = context.watchIsPlayingTrack(track.id);
      case SearchBestMatchKind.artist:
        final artist = bestMatch.artist!;
        title = artist.name;
        subtitle = 'Artist';
        imageUrl = artist.thumbnailUrl;
        kindLabel = 'Artist';
        isPlaying = context.watchIsPlayingArtist(
          artistId: artist.id,
          artistName: artist.name,
        );
      case SearchBestMatchKind.album:
        final album = bestMatch.album!;
        title = album.title;
        subtitle = album.artists.map((a) => a.name).join(', ');
        imageUrl = album.thumbnailUrl;
        kindLabel = 'Album';
        isPlaying = context.watchIsPlayingAlbum(
          albumId: album.id,
          albumTitle: album.title,
        );
      case SearchBestMatchKind.playlist:
        final playlist = bestMatch.playlist!;
        title = playlist.title;
        subtitle = playlist.author.displayName;
        imageUrl = playlist.thumbnailUrl;
        kindLabel = 'Playlist';
        isPlaying = context.watchIsPlayingPlaylist(
          playlistId: playlist.id,
          playlistTitle: playlist.title,
        );
    }

    final handleTap = onTap ?? () => _defaultTap(context);
    final handleSecondaryTap = onSecondaryTapDown ??
        (details) => _showContextMenu(
              context,
              globalPosition: details.globalPosition,
            );
    final handleLongPress = onLongPress ?? () => _showContextMenu(context);

    if (isMobile) {
      return _buildMobileCard(
        context: context,
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        isArtist: isArtist,
        isPlaying: isPlaying,
        onTap: handleTap,
        onSecondaryTapDown: handleSecondaryTap,
        onLongPress: handleLongPress,
      );
    }

    return _buildDesktopCard(
      context: context,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      kindLabel: kindLabel,
      isArtist: isArtist,
      isPlaying: isPlaying,
      isApple: isApple,
      onTap: handleTap,
      onSecondaryTapDown: handleSecondaryTap,
      onLongPress: handleLongPress,
    );
  }

  Widget _buildMobileCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String imageUrl,
    required bool isArtist,
    required bool isPlaying,
    required VoidCallback onTap,
    required GestureTapDownCallback onSecondaryTapDown,
    required VoidCallback onLongPress,
  }) {
    return GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      onLongPress: onLongPress,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CoverPlayOverlay(
                  isPlaying: isPlaying,
                  onPressed: onPlay,
                  waveformSize: 18,
                  child: ArtworkThumbnail(
                    source: ArtworkSource.fromUrl(imageUrl),
                    size: ArtworkSize.medium,
                    shape: isArtist ? ArtworkShape.circle : ArtworkShape.rounded,
                    fallbackIcon: isArtist ? Icons.person : Icons.music_note,
                    semanticLabel: 'Artwork for $title',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String imageUrl,
    required String kindLabel,
    required bool isArtist,
    required bool isPlaying,
    required bool isApple,
    required VoidCallback onTap,
    required GestureTapDownCallback onSecondaryTapDown,
    required VoidCallback onLongPress,
  }) {
    final theme = Theme.of(context);

    return HoverRegion(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      onLongPress: Platform.isWindows || Platform.isMacOS || Platform.isLinux
          ? null
          : onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Builder(
        builder: (context) {
          final isHovered = HoverRegion.of(context) ?? false;

          return Container(
            width: double.infinity,
            height: height ?? double.infinity,
            decoration: BoxDecoration(
              color: isHovered
                  ? Colors.white.withValues(alpha: isApple ? 0.08 : 0.075)
                  : Colors.white.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(14),
              border: isApple
                  ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: ArtworkThumbnail(
                              source: ArtworkSource.fromUrl(imageUrl),
                              size: ArtworkSize.large,
                              shape: isArtist
                                  ? ArtworkShape.circle
                                  : ArtworkShape.rounded,
                              fallbackIcon: isArtist
                                  ? Icons.person
                                  : Icons.music_note,
                              semanticLabel: 'Artwork for $title',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              kindLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onPlay != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: IgnorePointer(
                      ignoring: !isHovered && !isPlaying,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        offset: (isHovered || isPlaying)
                            ? Offset.zero
                            : const Offset(0, 0.4),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 140),
                          opacity: (isHovered || isPlaying) ? 1 : 0,
                          child: Material(
                            elevation: 8,
                            shape: const CircleBorder(),
                            color: theme.colorScheme.primary,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onPlay,
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: theme.colorScheme.onPrimary,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
