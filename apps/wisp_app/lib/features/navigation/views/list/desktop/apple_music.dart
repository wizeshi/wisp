// Copyright © 2026 wizeshi

import 'dart:io' show File;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';

import 'package:wisp/core/utils/text_parser.dart';
import 'package:wisp/core/utils/liked_songs.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/shared/widgets/artwork/artwork_thumbnail.dart';
import 'package:wisp/shared/widgets/artwork/liked_songs_art.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/shared/widgets/display/hover_underline.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
import 'package:wisp/shared/widgets/rows/track_row.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import '../view.dart' show SharedListType, ListSortMethod;

class DesktopAppleMusicListView extends StatelessWidget {
  final String id;
  final SharedListType type;
  final String title;
  final String? subtitle;
  final GenericSimpleUser? subtitleUser;
  final String imageUrl;
  final String? subtitleImageUrl;
  final String? description;
  final int totalTracks;
  final int totalDurationSecs;
  final bool isLiked;
  final bool isLoading;
  final PlaybackContext viewContext;

  final List<GenericSong> songs;
  final List<DateTime?>? datesAdded;
  final List<int> sortedIndices;

  final ListSortMethod sortMethod;
  final bool sortAscending;

  final bool showRecommendations;
  final List<GenericSong> recommendedSongs;
  final bool isLoadingRecommendations;
  final Set<String> addingRecommendationTrackIDs;
  final Set<String> addedRecommendationTrackIDs;

  final VoidCallback onPlayAll;
  final VoidCallback onShuffle;
  final VoidCallback onToggleLoop;
  final VoidCallback onDownloadAll;
  final VoidCallback onToggleLike;
  final void Function(BuildContext context, Offset? position) onContextMenu;
  final void Function(int sortedIndex) onPlayTrack;
  final void Function(GenericSong song) onTrackToggleLike;
  final void Function(BuildContext context, GenericSong song, Offset? position)
  onTrackContextMenu;
  final void Function(ListSortMethod method) onSort;
  final ValueChanged<String> onSearchQueryChanged;
  final void Function(GenericSimpleAlbum? album)? onOpenAlbum;
  final void Function(GenericSimpleArtist artist)? onOpenArtist;
  final void Function(GenericSong song) onAddRecommendedTrack;
  final VoidCallback onRefreshRecommendations;
  final void Function(GenericSimpleUser user)? onOpenUser;
  final ScrollController scrollController;

  const DesktopAppleMusicListView({
    super.key,
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.subtitleUser,
    required this.imageUrl,
    this.subtitleImageUrl,
    this.description,
    required this.totalTracks,
    required this.totalDurationSecs,
    required this.isLiked,
    required this.isLoading,
    required this.viewContext,
    required this.songs,
    this.datesAdded,
    required this.sortedIndices,
    required this.sortMethod,
    required this.sortAscending,
    required this.showRecommendations,
    required this.recommendedSongs,
    required this.isLoadingRecommendations,
    required this.addingRecommendationTrackIDs,
    required this.addedRecommendationTrackIDs,
    required this.onPlayAll,
    required this.onShuffle,
    required this.onToggleLoop,
    required this.onDownloadAll,
    required this.onToggleLike,
    required this.onContextMenu,
    required this.onPlayTrack,
    required this.onTrackToggleLike,
    required this.onTrackContextMenu,
    required this.onSort,
    required this.onSearchQueryChanged,
    this.onOpenAlbum,
    this.onOpenArtist,
    required this.onAddRecommendedTrack,
    required this.onRefreshRecommendations,
    this.onOpenUser,
    required this.scrollController,
  });

  bool _isLocalImagePath(String path) {
    return path.startsWith('file://') ||
        path.startsWith('/') ||
        (path.length > 2 && path[1] == ':');
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final isLikedPlaylist =
        type == SharedListType.playlist && isLikedSongsPlaylistId(id);

    return SafeArea(
      bottom: false,
      child: WispSmoothScroll(
        controller: scrollController,
        builder: (context, controller, physics) => CustomScrollView(
          key: PageStorageKey('apple_desktop_${type}_$id'),
          controller: controller,
          physics: physics,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
                child: _buildHeader(context, isLikedPlaylist),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Column(
                      children: [
                        _buildTableHeader(constraints.maxWidth),
                        const SizedBox(height: 6),
                        const Divider(height: 1, color: Colors.white12),
                      ],
                    );
                  },
                ),
              ),
            ),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.crossAxisExtent - 64;
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  sliver: _buildSongList(availableWidth),
                );
              },
            ),
            if (showRecommendations)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                sliver: SliverToBoxAdapter(
                  child: _buildRecommendations(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isLikedPlaylist) {
    final width = MediaQuery.of(context).size.width;
    final headerHeight = (width * 0.125).clamp(240.0, 340.0);
    final baseFontSize = (width * 0.00075).clamp(1.0, 1.4);
    final descriptionText = description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;

    return Container(
      width: double.infinity,
      height: headerHeight,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 600;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: isLikedPlaylist
                      ? const LikedSongsArt()
                      : (imageUrl.isNotEmpty
                            ? (_isLocalImagePath(imageUrl)
                                  ? Image.file(
                                      File(
                                        imageUrl.replaceFirst('file://', ''),
                                      ),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          Container(color: Colors.grey[800]),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) =>
                                          Container(color: Colors.grey[800]),
                                      errorWidget: (_, _, _) =>
                                          Container(color: Colors.grey[800]),
                                    ))
                            : Icon(
                                type == SharedListType.playlist
                                    ? Icons.playlist_play
                                    : Icons.album,
                                color: Colors.grey[600],
                                size: 48,
                              )),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 52 * baseFontSize,
                        height: 0.95,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasDescription) const SizedBox(height: 6),
                    if (hasDescription)
                      buildParsedText(
                        context,
                        descriptionText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '$totalTracks ${totalTracks == 1 ? "item" : "items"}',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(' • ', style: TextStyle(color: Colors.white70)),
                        Text(
                          _formatDuration(totalDurationSecs),
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ArtworkThumbnail(
                          source: ArtworkSource.network(subtitleImageUrl ?? ''),
                          size: ArtworkSize.tiny,
                          sizeOverride: 20.0,
                          semanticLabel:
                              'Profile Picture of ${subtitleUser?.displayName ?? subtitle ?? ''}',
                          shape: ArtworkShape.circle,
                        ),
                        const SizedBox(width: 6),
                        HoverUnderline(
                          cursor: SystemMouseCursors.click,
                          onTap: () => onOpenUser?.call(subtitleUser!),
                          builder: (isHovering) => Text(
                            subtitleUser?.displayName ?? subtitle ?? '',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              decoration: isHovering
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Selector<WispAudioHandler, bool>(
                          selector: (context, player) =>
                              player.isPlaying &&
                              player.currentTrack != null &&
                              player.playbackContext?.matches(viewContext) ==
                                  true,
                          builder: (context, isPlayingList, _) {
                            return _buildPlaybackButton(
                              context,
                              onPressed: isLoading ? null : onPlayAll,
                              icon: isPlayingList
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              label: isPlayingList ? 'Pause' : 'Play',
                              isCompact: isCompact,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Selector<WispAudioHandler, bool>(
                          selector: (context, player) => player.shuffleEnabled,
                          builder: (context, shuffleActive, _) {
                            return _buildPlaybackButton(
                              context,
                              onPressed: isLoading ? null : onShuffle,
                              icon: Icons.shuffle,
                              label: 'Shuffle',
                              isCompact: isCompact,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlaybackButton(
    BuildContext context, {
    void Function()? onPressed,
    required IconData icon,
    required String label,
    required bool isCompact,
  }) {
    if (isCompact) {
      return GenericIconButton.filled(
        onPressed: onPressed,
        backgroundColor: Theme.of(context).colorScheme.primary,
        minimumSize: const Size(40, 36),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(6),
        icon: Icon(icon, size: 20),
      );
    }

    return GenericFilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      minimumSize: isCompact ? const Size(80, 32) : const Size(112, 36),
      textStyle: TextStyle(
        fontSize: isCompact ? 12 : 14,
        fontWeight: FontWeight.w600,
      ),
      borderRadius: BorderRadius.circular(6),
    );
  }

  Widget _buildTableHeader(double availableWidth) {
    final isPlaylist = type == SharedListType.playlist;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 48,
            child: Center(
              child: Icon(
                CupertinoIcons.music_note,
                size: 16,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: _buildSortableColumn('Title', ListSortMethod.title),
          ),
          Expanded(
            flex: 2,
            child: _buildSortableColumn('Artist', ListSortMethod.author),
          ),
          if (isPlaylist && availableWidth > 600)
            Expanded(
              flex: 2,
              child: _buildSortableColumn('Album', ListSortMethod.album),
            ),
          const SizedBox(width: 36),
          SizedBox(
            width: 70,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildSortableColumn(
                '',
                ListSortMethod.duration,
                icon: const Icon(
                  CupertinoIcons.time,
                  size: 16,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSortableColumn(
    String label,
    ListSortMethod method, {
    Widget? icon,
  }) {
    final isSelected = sortMethod == method;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onSort(method),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?icon,
            if (label.isNotEmpty)
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[400],
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(
                sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: Colors.white,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSongList(double availableWidth) {
    final isPlaylist = type == SharedListType.playlist;

    return SliverFixedExtentList(
      itemExtent: 62.0,
      delegate: SliverChildBuilderDelegate((context, rowIndex) {
        if (rowIndex >= sortedIndices.length) return null;
        final originalIndex = sortedIndices[rowIndex];
        if (originalIndex >= songs.length) return null;
        final song = songs[originalIndex];

        return RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: TrackRow(
              track: song,
              style: AppStyle.AppleMusic,
              viewContext: viewContext,
              index: null,
              playIconLocation: PlayIconLocation.art,
              showAlbumName: isPlaylist && availableWidth > 600,
              showDuration: true,
              showArtistColumn: true,
              showArtistInline: false,
              trailing: SizedBox(
                width: 36,
                child: Center(
                  child: LikeButton(
                    track: song,
                    hoverOnlyWhenUnliked: true,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              onTap: () => onPlayTrack(rowIndex),
              onPlayPause: () => onPlayTrack(rowIndex),
              onAlbumTap: () => onOpenAlbum?.call(song.album),
              onArtistTap: (artist) => onOpenArtist?.call(artist),
              onMoreTap: (buttonContext) =>
                  onTrackContextMenu(buttonContext, song, null),
              onSecondaryTapDown: (details) =>
                  onTrackContextMenu(context, song, details.globalPosition),
            ),
          ),
        );
      }, childCount: sortedIndices.length),
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Colors.white12),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recommended',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "based on what's in this playlist",
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                ],
              ),
              GenericFilledButton.icon(
                onPressed: isLoadingRecommendations
                    ? null
                    : onRefreshRecommendations,
                icon: isLoadingRecommendations
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...recommendedSongs.map((song) {
          final isAdding = addingRecommendationTrackIDs.contains(song.id);
          final isAdded = addedRecommendationTrackIDs.contains(song.id);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: TrackRow(
              track: song,
              style: AppStyle.AppleMusic,
              viewContext: viewContext,
              index: null,
              playIconLocation: PlayIconLocation.art,
              showAlbumName: false,
              showDuration: false,
              showArtistColumn: true,
              showArtistInline: false,
              onTap: () => onAddRecommendedTrack(song),
              onPlayPause: () => onAddRecommendedTrack(song),
              onAlbumTap: () => onOpenAlbum?.call(song.album),
              onArtistTap: (artist) => onOpenArtist?.call(artist),
              trailing: GenericFilledButton(
                onPressed: (isAdding || isAdded)
                    ? null
                    : () => onAddRecommendedTrack(song),
                child: isAdding
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isAdded ? 'Added' : 'Add'),
              ),
            ),
          );
        }),
      ],
    );
  }
}
