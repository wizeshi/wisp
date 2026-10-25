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
import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/shared/widgets/artwork/liked_songs_art.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/shared/widgets/layout/mobile_bottom_padding.dart';
import 'package:wisp/shared/widgets/rows/track_row.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import '../view.dart' show SharedListType, ListSortMethod;

class MobileAppleMusicListView extends StatefulWidget {
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

  const MobileAppleMusicListView({
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

  @override
  State<MobileAppleMusicListView> createState() =>
      _MobileAppleMusicListViewState();
}

class _MobileAppleMusicListViewState extends State<MobileAppleMusicListView> {
  bool _showTitle = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant MobileAppleMusicListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final shouldShow = widget.scrollController.offset > 200;
    if (shouldShow != _showTitle) {
      setState(() {
        _showTitle = shouldShow;
      });
    }
  }

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
        widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(widget.id);

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          leading: GenericIconButton(
            icon: const Icon(CupertinoIcons.back, color: Colors.white),
            onPressed: () => NavigationHistory.instance.goBack(),
          ),
          title: AnimatedOpacity(
            opacity: _showTitle ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          centerTitle: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: _showTitle ? 1 : 0,
        ),
        body: CustomScrollView(
          key: PageStorageKey('apple_mobile_${widget.type}_${widget.id}'),
          controller: widget.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: _buildHeader(context, isLikedPlaylist),
              ),
            ),
            SliverFixedExtentList(
              itemExtent: 60.0,
              delegate: SliverChildBuilderDelegate((context, rowIndex) {
                if (rowIndex >= widget.sortedIndices.length) return null;
                final originalIndex = widget.sortedIndices[rowIndex];
                if (originalIndex >= widget.songs.length) return null;
                final song = widget.songs[originalIndex];

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ),
                  child: RepaintBoundary(
                    child: TrackRow(
                      track: song,
                      style: AppStyle.AppleMusic,
                      viewContext: widget.viewContext,
                      index: null,
                      playIconLocation: PlayIconLocation.art,
                      showAlbumName: false,
                      showDuration: false,
                      showArtistInline: true,
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
                      onTap: () => widget.onPlayTrack(rowIndex),
                      onPlayPause: () => widget.onPlayTrack(rowIndex),
                      onAlbumTap: () => widget.onOpenAlbum?.call(song.album),
                      onArtistTap: (artist) =>
                          widget.onOpenArtist?.call(artist),
                      onMoreTap: (buttonContext) =>
                          widget.onTrackContextMenu(buttonContext, song, null),
                      onLongPress: () =>
                          widget.onTrackContextMenu(context, song, null),
                    ),
                  ),
                );
              }, childCount: widget.sortedIndices.length),
            ),
            if (widget.showRecommendations)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                  child: _buildRecommendations(context),
                ),
              ),
            const MobileBottomPaddingSliver(extra: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isLikedPlaylist) {
    final width = MediaQuery.of(context).size.width;
    final artWidth = (width * 0.85).clamp(160.0, double.infinity);
    final descriptionText = widget.description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Center(
          child: SizedBox(
            width: artWidth,
            height: artWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isLikedPlaylist
                  ? const LikedSongsArt()
                  : (widget.imageUrl.isNotEmpty
                        ? (_isLocalImagePath(widget.imageUrl)
                              ? Image.file(
                                  File(
                                    widget.imageUrl.replaceFirst('file://', ''),
                                  ),
                                  fit: BoxFit.cover,
                                  cacheWidth: 480,
                                  cacheHeight: 480,
                                  errorBuilder: (_, _, _) =>
                                      Container(color: Colors.grey[900]),
                                )
                              : CachedNetworkImage(
                                  imageUrl: widget.imageUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 480,
                                  memCacheHeight: 480,
                                  placeholder: (_, _) =>
                                      Container(color: Colors.grey[900]),
                                  errorWidget: (_, _, _) =>
                                      Container(color: Colors.grey[900]),
                                ))
                        : Container(
                            color: Colors.grey[900],
                            child: Icon(
                              widget.type == SharedListType.playlist
                                  ? Icons.playlist_play
                                  : Icons.album,
                              color: Colors.grey[600],
                              size: 64,
                            ),
                          )),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.subtitleUser != null)
              GestureDetector(
                onTap: () => widget.onOpenUser?.call(widget.subtitleUser!),
                child: Text(
                  widget.subtitleUser!.displayName,
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              )
            else if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
              Text(
                widget.subtitle!,
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            if (widget.totalTracks > 0) ...[
              const Text(' • ', style: TextStyle(color: Colors.grey)),
              Text(
                '${widget.totalTracks} songs',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
            if (widget.totalDurationSecs > 0) ...[
              const Text(', ', style: TextStyle(color: Colors.grey)),
              Text(
                _formatDuration(widget.totalDurationSecs),
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ],
        ),
        if (hasDescription) const SizedBox(height: 8),
        if (hasDescription)
          buildParsedText(
            context,
            descriptionText,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Selector<WispAudioHandler, bool>(
              selector: (context, player) => player.shuffleEnabled,
              builder: (context, shuffleActive, _) {
                return GenericIconButton.filled(
                  onPressed: widget.onShuffle,
                  icon: Icon(
                    CupertinoIcons.shuffle,
                    size: 18,
                    color: shuffleActive ? Colors.white : primaryColor,
                  ),
                  backgroundColor: shuffleActive
                      ? primaryColor
                      : Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                );
              },
            ),
            const SizedBox(width: 6),
            Selector<WispAudioHandler, bool>(
              selector: (context, player) =>
                  player.isPlaying &&
                  player.currentTrack != null &&
                  player.playbackContext?.matches(widget.viewContext) == true,
              builder: (context, isPlayingList, _) {
                return GenericFilledButton.icon(
                  onPressed: widget.isLoading ? null : widget.onPlayAll,
                  icon: Icon(
                    isPlayingList
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: 18,
                  ),
                  label: Text(isPlayingList ? 'Pause' : 'Play'),
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 24,
                  ),
                  borderRadius: BorderRadius.circular(100),
                );
              },
            ),
            const SizedBox(width: 6),
            Builder(
              builder: (buttonContext) {
                return GenericIconButton.filled(
                  onPressed: () => widget.onContextMenu(buttonContext, null),
                  icon: const Icon(
                    CupertinoIcons.ellipsis,
                    color: Colors.white70,
                    size: 22,
                  ),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Colors.white12),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recommended',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Based on what's in this playlist",
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
              GenericIconButton.filled(
                onPressed: widget.isLoadingRecommendations
                    ? null
                    : widget.onRefreshRecommendations,
                icon: widget.isLoadingRecommendations
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.refresh, size: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...widget.recommendedSongs.map((song) {
          final isAdding = widget.addingRecommendationTrackIDs.contains(
            song.id,
          );
          final isAdded = widget.addedRecommendationTrackIDs.contains(song.id);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: TrackRow(
              track: song,
              style: AppStyle.AppleMusic,
              viewContext: widget.viewContext,
              index: null,
              playIconLocation: PlayIconLocation.art,
              showAlbumName: false,
              showDuration: false,
              showSource: false,
              showArtistInline: true,
              trailing: SizedBox(
                width: 36,
                child: Center(
                  child: GenericIconButton(
                    padding: EdgeInsets.zero,
                    onPressed: (isAdding || isAdded)
                        ? null
                        : () => widget.onAddRecommendedTrack(song),
                    icon: isAdding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isAdded
                                ? CupertinoIcons.check_mark_circled
                                : CupertinoIcons.add_circled,
                            color: isAdded
                                ? Colors.green
                                : Theme.of(context).colorScheme.primary,
                            size: 22,
                          ),
                  ),
                ),
              ),
              onTap: () => widget.onAddRecommendedTrack(song),
              onPlayPause: () => widget.onAddRecommendedTrack(song),
              onAlbumTap: () => widget.onOpenAlbum?.call(song.album),
              onArtistTap: (artist) => widget.onOpenArtist?.call(artist),
              onLongPress: () => widget.onTrackContextMenu(context, song, null),
            ),
          );
        }),
      ],
    );
  }
}
