// Copyright © 2026 wizeshi

import 'dart:io' show File;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
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

class MobileSpotifyListView extends StatefulWidget {
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
  final VoidCallback onToggleLike;
  final void Function(BuildContext context, Offset? position) onContextMenu;
  final void Function(int sortedIndex) onPlayTrack;
  final void Function(GenericSong song) onTrackToggleLike;
  final void Function(BuildContext context, GenericSong song, Offset? position)
  onTrackContextMenu;
  final void Function(ListSortMethod method) onSort;
  final void Function(GenericSong song) onAddRecommendedTrack;
  final VoidCallback onRefreshRecommendations;
  final void Function(GenericSimpleAlbum? album)? onOpenAlbum;
  final void Function(GenericSimpleArtist artist)? onOpenArtist;
  final void Function(GenericSimpleUser user)? onOpenUser;
  final ScrollController scrollController;

  const MobileSpotifyListView({
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
    required this.onToggleLike,
    required this.onContextMenu,
    required this.onPlayTrack,
    required this.onTrackToggleLike,
    required this.onTrackContextMenu,
    required this.onSort,
    required this.onAddRecommendedTrack,
    required this.onRefreshRecommendations,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.onOpenUser,
    required this.scrollController,
  });

  @override
  State<MobileSpotifyListView> createState() => _MobileSpotifyListViewState();
}

class _MobileSpotifyListViewState extends State<MobileSpotifyListView> {
  bool _showStickyBar = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant MobileSpotifyListView oldWidget) {
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
    final shouldShow = widget.scrollController.offset > 280;
    if (shouldShow != _showStickyBar) {
      setState(() {
        _showStickyBar = shouldShow;
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
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min $secs sec';
  }

  @override
  Widget build(BuildContext context) {
    final isLikedPlaylist =
        widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(widget.id);
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF121212),
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: _showStickyBar
                ? const Color(0xFF121212)
                : Colors.transparent,
            elevation: _showStickyBar ? 2 : 0,
            leading: GenericIconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => NavigationHistory.instance.goBack(),
            ),
            title: AnimatedOpacity(
              opacity: _showStickyBar ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          body: CustomScrollView(
            key: PageStorageKey('spotify_mobile_${widget.type}_${widget.id}'),
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.paddingOf(context).top + 48,
                    16,
                    0,
                  ),
                  child: _buildHeader(context, isLikedPlaylist),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: const Color(0xFF121212),
                  child: _buildActionsRow(context),
                ),
              ),
              SliverFixedExtentList(
                itemExtent: 56.0,
                delegate: SliverChildBuilderDelegate((context, rowIndex) {
                  if (rowIndex >= widget.sortedIndices.length) return null;
                  final originalIndex = widget.sortedIndices[rowIndex];
                  if (originalIndex >= widget.songs.length) return null;
                  final song = widget.songs[originalIndex];

                  return RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TrackRow(
                        track: song,
                        style: AppStyle.Spotify,
                        viewContext: widget.viewContext,
                        index: null,
                        showAlbumName: false,
                        showDuration: false,
                        trailing: SizedBox(
                          width: 36,
                          child: Center(
                            child: LikeButton(
                              track: song,
                              hoverOnlyWhenUnliked: false,
                            ),
                          ),
                        ),
                        onTap: () => widget.onPlayTrack(rowIndex),
                        onPlayPause: () => widget.onPlayTrack(rowIndex),
                        onAlbumTap: () => widget.onOpenAlbum?.call(song.album),
                        onArtistTap: (artist) =>
                            widget.onOpenArtist?.call(artist),
                        onMoreTap: (buttonContext) => widget.onTrackContextMenu(
                          buttonContext,
                          song,
                          null,
                        ),
                        onSecondaryTapDown: (details) =>
                            widget.onTrackContextMenu(
                              context,
                              song,
                              details.globalPosition,
                            ),
                      ),
                    ),
                  );
                }, childCount: widget.sortedIndices.length),
              ),
              if (widget.showRecommendations)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: _buildRecommendations(context),
                  ),
                ),
              const MobileBottomPaddingSliver(extra: 0),
            ],
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + kToolbarHeight - 25,
          right: 16,
          child: IgnorePointer(
            ignoring: !_showStickyBar,
            child: AnimatedScale(
              scale: _showStickyBar ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: _showStickyBar ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: Selector<WispAudioHandler, bool>(
                      selector: (context, player) =>
                          player.isPlaying &&
                          player.currentTrack != null &&
                          player.playbackContext?.matches(widget.viewContext) ==
                              true,
                      builder: (context, isPlayingList, _) {
                        return GenericFilledButton(
                          onPressed: widget.isLoading ? null : widget.onPlayAll,
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          child: Icon(
                            isPlayingList ? Icons.pause : Icons.play_arrow,
                            size: 28,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool isLikedPlaylist) {
    final width = MediaQuery.of(context).size.width;
    final artWidth = (width * 0.72).clamp(160.0, 280.0);
    final descriptionText = widget.description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SizedBox(
            width: artWidth,
            height: artWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isLikedPlaylist
                  ? const LikedSongsArt()
                  : (widget.imageUrl.isNotEmpty
                        ? (_isLocalImagePath(widget.imageUrl)
                              ? Image.file(
                                  File(
                                    widget.imageUrl.replaceFirst('file://', ''),
                                  ),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      Container(color: Colors.grey[900]),
                                )
                              : CachedNetworkImage(
                                  imageUrl: widget.imageUrl,
                                  fit: BoxFit.cover,
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
        const SizedBox(height: 16),
        Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasDescription) const SizedBox(height: 6),
        if (hasDescription)
          buildParsedText(
            context,
            descriptionText,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (widget.subtitleUser != null)
              GestureDetector(
                onTap: () => widget.onOpenUser?.call(widget.subtitleUser!),
                child: Text(
                  widget.subtitleUser!.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              )
            else if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
              Text(
                widget.subtitle!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
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
      ],
    );
  }

  Widget _buildActionsRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Selector<WispAudioHandler, bool>(
          selector: (context, player) => player.shuffleEnabled,
          builder: (context, shuffleActive, _) {
            return GenericIconButton(
              onPressed: widget.onShuffle,
              icon: Icon(
                Icons.shuffle,
                color: shuffleActive ? colorScheme.primary : Colors.grey[400],
                size: 24,
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Builder(
          builder: (buttonContext) {
            return GestureDetector(
              onTapDown: (details) =>
                  widget.onContextMenu(buttonContext, details.globalPosition),
              child: GenericIconButton(
                onPressed: () => widget.onContextMenu(buttonContext, null),
                icon: Icon(Icons.more_horiz, color: Colors.grey[400], size: 24),
              ),
            );
          },
        ),
        const Spacer(),
        Selector<WispAudioHandler, bool>(
          selector: (context, player) =>
              player.isPlaying &&
              player.currentTrack != null &&
              player.playbackContext?.matches(widget.viewContext) == true,
          builder: (context, isPlayingList, _) {
            return SizedBox(
              width: 50,
              height: 50,
              child: GenericFilledButton(
                onPressed: widget.isLoading ? null : widget.onPlayAll,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
                child: Icon(
                  isPlayingList ? Icons.pause : Icons.play_arrow,
                  size: 28,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recommended',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "based on what's in this playlist",
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
                    : const Icon(Icons.refresh, size: 16),
                backgroundColor: const Color(0xFF282828),
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
              style: AppStyle.Spotify,
              viewContext: widget.viewContext,
              index: null,
              playIconLocation: PlayIconLocation.art,
              showAlbumName: false,
              showDuration: false,
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
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isAdded
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            color: isAdded
                                ? colorScheme.primary
                                : Colors.white70,
                            size: 22,
                          ),
                  ),
                ),
              ),
              onTap: () => widget.onAddRecommendedTrack(song),
              onPlayPause: () => widget.onAddRecommendedTrack(song),
              onAlbumTap: () => widget.onOpenAlbum?.call(song.album),
              onArtistTap: (artist) => widget.onOpenArtist?.call(artist),
              onSecondaryTapDown: (details) => widget.onTrackContextMenu(
                context,
                song,
                details.globalPosition,
              ),
            ),
          );
        }),
      ],
    );
  }
}
