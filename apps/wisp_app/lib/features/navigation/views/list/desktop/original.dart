// Copyright © 2026 wizeshi

import 'dart:io' show File;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:provider/provider.dart';
import 'package:wisp/core/theme/app_theme.dart';

import 'package:wisp/core/theme/cover_art_palette_provider.dart';
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

class DesktopOriginalListView extends StatefulWidget {
  final String id;
  final SharedListType type;
  final String title;
  final String? subtitle;
  final List<GenericSimpleArtist>? subtitleArtists;
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
  final void Function(GenericSong song) onAddRecommendedTrack;
  final VoidCallback onRefreshRecommendations;
  final void Function(GenericSimpleAlbum? album)? onOpenAlbum;
  final void Function(GenericSimpleArtist artist)? onOpenArtist;
  final void Function(GenericSimpleUser user)? onOpenUser;
  final ScrollController scrollController;

  const DesktopOriginalListView({
    super.key,
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.subtitleUser,
    this.subtitleArtists,
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
    required this.onAddRecommendedTrack,
    required this.onRefreshRecommendations,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.onOpenUser,
    required this.scrollController,
  });

  @override
  State<DesktopOriginalListView> createState() =>
      _DesktopOriginalListViewState();
}

class _DesktopOriginalListViewState extends State<DesktopOriginalListView> {
  bool _showStickyBar = false;
  Color _stickyBarColor = const Color(0xFF1E1E1E);
  bool _searchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  Future<ColorScheme?>? _paletteFuture;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _paletteFuture = context.read<CoverArtPaletteProvider>().paletteForImageUrl(
      widget.imageUrl,
    );
  }

  @override
  void didUpdateWidget(covariant DesktopOriginalListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
    if (oldWidget.imageUrl != widget.imageUrl) {
      _paletteFuture = context
          .read<CoverArtPaletteProvider>()
          .paletteForImageUrl(widget.imageUrl);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final shouldShow = widget.scrollController.offset > 240;
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
    final contentSurfaceColor = Theme.of(context).colorScheme.surface;

    return FutureBuilder<ColorScheme?>(
      future: _paletteFuture,
      builder: (context, snapshot) {
        final headerColor = snapshot.data?.primary ?? const Color(0xFF222222);
        _stickyBarColor = headerColor;

        return Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.35, 1],
                    colors: [
                      headerColor.withValues(alpha: 0.35),
                      contentSurfaceColor.withValues(alpha: 0.8),
                      contentSurfaceColor,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: WispSmoothScroll(
                controller: widget.scrollController,
                builder: (context, controller, physics) => CustomScrollView(
                  key: PageStorageKey(
                    'orig_desktop_${widget.type}_${widget.id}',
                  ),
                  controller: controller,
                  physics: physics,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
                        child: _buildHeader(context, isLikedPlaylist),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      sliver: SliverToBoxAdapter(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Column(
                              children: [
                                _buildTableHeader(constraints.maxWidth),
                                const SizedBox(height: 4),
                                const Divider(),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    SliverLayoutBuilder(
                      builder: (sliverContext, sliverConstraints) {
                        return SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          sliver: _buildSongList(
                            sliverConstraints.crossAxisExtent - 56,
                          ),
                        );
                      },
                    ),
                    if (widget.showRecommendations)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                        sliver: SliverToBoxAdapter(
                          child: _buildRecommendations(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(bottom: false, child: _buildStickyBar(context)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArtwork(bool isLikedPlaylist) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 200,
        height: 200,
        child: isLikedPlaylist
            ? const LikedSongsArt()
            : (widget.imageUrl.isNotEmpty
                  ? (_isLocalImagePath(widget.imageUrl)
                        ? Image.file(
                            File(widget.imageUrl.replaceFirst('file://', '')),
                            fit: BoxFit.cover,
                            cacheWidth: 480,
                            cacheHeight: 480,
                            errorBuilder: (_, _, _) =>
                                Container(color: Colors.grey[850]),
                          )
                        : CachedNetworkImage(
                            imageUrl: widget.imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 480,
                            memCacheHeight: 480,
                            placeholder: (_, _) =>
                                Container(color: Colors.grey[850]),
                            errorWidget: (_, _, _) =>
                                Container(color: Colors.grey[850]),
                          ))
                  : Container(
                      color: Colors.grey[850],
                      child: Icon(
                        widget.type == SharedListType.playlist
                            ? Icons.playlist_play
                            : Icons.album,
                        color: Colors.grey[600],
                        size: 56,
                      ),
                    )),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isLikedPlaylist) {
    final descriptionText = widget.description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildArtwork(isLikedPlaylist),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                widget.type == SharedListType.playlist ? 'PLAYLIST' : 'ALBUM',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  height: 1.05,
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (widget.subtitleUser != null) ...[
                    ArtworkThumbnail(
                      source: ArtworkSource.network(
                        widget.subtitleImageUrl ?? '',
                      ),
                      size: ArtworkSize.tiny,
                      sizeOverride: 20.0,
                      semanticLabel:
                          'Profile Picture of ${widget.subtitleUser?.displayName ?? widget.subtitle ?? ''}',
                      shape: ArtworkShape.circle,
                    ),
                    const SizedBox(width: 6),
                    HoverUnderline(
                      onTap: () =>
                          widget.onOpenUser?.call(widget.subtitleUser!),
                      builder: (hovering) => Text(
                        widget.subtitleUser!.displayName,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          decoration: hovering
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                  ] else if (widget.subtitle != null &&
                      widget.subtitle!.isNotEmpty)
                    Text(
                      widget.subtitle!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (widget.totalTracks > 0) ...[
                    const Text(' • ', style: TextStyle(color: Colors.grey)),
                    Text(
                      '${widget.totalTracks} songs',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                  if (widget.totalDurationSecs > 0) ...[
                    const Text(', ', style: TextStyle(color: Colors.grey)),
                    Text(
                      _formatDuration(widget.totalDurationSecs),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        _buildHeaderActions(context),
      ],
    );
  }

  Widget _buildHeaderActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top row: search field and sort method dropdown justified to the right
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: _searchExpanded ? 200 : 36,
              height: 36,
              decoration: _searchExpanded
                  ? BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: _searchExpanded
                  ? Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.search,
                            size: 18,
                            color: Colors.white70,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Search in list...',
                              hintStyle: TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: widget.onSearchQueryChanged,
                          ),
                        ),
                        GenericIconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            widget.onSearchQueryChanged('');
                            setState(() => _searchExpanded = false);
                          },
                        ),
                      ],
                    )
                  : GenericIconButton(
                      onPressed: () => setState(() => _searchExpanded = true),
                      icon: Icon(
                        Icons.search,
                        color: Colors.grey[400],
                        size: 22,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<ListSortMethod>(
              tooltip: 'Sort by',
              color: const Color(0xFF282828),
              onSelected: widget.onSort,
              itemBuilder: (context) => [
                _buildSortMenuItem('Index', ListSortMethod.position),
                _buildSortMenuItem('Title', ListSortMethod.title),
                _buildSortMenuItem('Artist', ListSortMethod.author),
                if (widget.type == SharedListType.playlist)
                  _buildSortMenuItem('Album', ListSortMethod.album),
                if (widget.type == SharedListType.playlist)
                  _buildSortMenuItem('Date added', ListSortMethod.addedAt),
                _buildSortMenuItem('Duration', ListSortMethod.duration),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _sortMethodLabel(widget.sortMethod),
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Bottom row: play/pause, shuffle, loop, download, context menu justified to the right
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 10,
          children: [
            Builder(
              builder: (buttonContext) {
                return GestureDetector(
                  onTapDown: (details) => widget.onContextMenu(
                    buttonContext,
                    details.globalPosition,
                  ),
                  child: GenericIconButton(
                    onPressed: () => widget.onContextMenu(buttonContext, null),
                    icon: Icon(
                      Icons.more_horiz,
                      color: Colors.grey[400],
                      size: 24,
                    ),
                  ),
                );
              },
            ),
            GenericIconButton(
              onPressed: widget.onDownloadAll,
              icon: Icon(
                Icons.download_for_offline_outlined,
                color: Colors.grey[400],
                size: 24,
              ),
            ),
            Selector<WispAudioHandler, RepeatMode>(
              selector: (context, player) => player.repeatMode,
              builder: (context, repeatMode, _) {
                return GenericIconButton.filled(
                  onPressed: widget.onToggleLoop,
                  icon: Icon(
                    repeatMode == RepeatMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color: Colors.white,
                    size: 24,
                  ),
                  backgroundColor: repeatMode != RepeatMode.off
                      ? colorScheme.primary
                      : Colors.transparent,
                );
              },
            ),
            Selector<WispAudioHandler, bool>(
              selector: (context, player) => player.shuffleEnabled,
              builder: (context, shuffleActive, _) {
                return GenericIconButton.filled(
                  onPressed: widget.onShuffle,
                  icon: Icon(Icons.shuffle, color: Colors.white, size: 24),
                  backgroundColor: shuffleActive
                      ? colorScheme.primary
                      : Colors.transparent,
                );
              },
            ),
            Selector<WispAudioHandler, bool>(
              selector: (context, player) =>
                  player.isPlaying &&
                  player.currentTrack != null &&
                  player.playbackContext?.matches(widget.viewContext) == true,
              builder: (context, isPlayingList, _) {
                return SizedBox(
                  width: 48,
                  height: 48,
                  child: GenericFilledButton(
                    onPressed: widget.isLoading ? null : widget.onPlayAll,
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                    child: Icon(
                      isPlayingList ? Icons.pause : Icons.play_arrow,
                      size: 26,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  String _sortMethodLabel(ListSortMethod method) {
    switch (method) {
      case ListSortMethod.position:
        return 'Index';
      case ListSortMethod.title:
        return 'Title';
      case ListSortMethod.author:
        return 'Artist';
      case ListSortMethod.album:
        return 'Album';
      case ListSortMethod.addedAt:
        return 'Date added';
      case ListSortMethod.duration:
        return 'Duration';
      case ListSortMethod.source:
        return 'Source';
    }
  }

  PopupMenuItem<ListSortMethod> _buildSortMenuItem(
    String label,
    ListSortMethod method,
  ) {
    final isSelected = widget.sortMethod == method;
    return PopupMenuItem<ListSortMethod>(
      value: method,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isSelected)
            Icon(
              widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(double availableWidth) {
    final isPlaylist = widget.type == SharedListType.playlist;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 40,
            child: Text(
              '#',
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 60),
          Expanded(
            flex: 3,
            child: _buildSortableColumn('Title', ListSortMethod.title),
          ),
          if (isPlaylist && availableWidth > 600)
            Expanded(
              flex: 2,
              child: _buildSortableColumn('Album', ListSortMethod.album),
            ),
          if (isPlaylist && availableWidth > 800)
            SizedBox(
              width: 120,
              child: _buildSortableColumn('Date added', ListSortMethod.addedAt),
            ),
          const SizedBox(width: 36),
          SizedBox(
            width: 88,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildSortableColumn(
                '',
                ListSortMethod.duration,
                icon: const Icon(
                  Icons.access_time,
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
    final isSelected = widget.sortMethod == method;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onSort(method),
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
                widget.sortAscending
                    ? Icons.arrow_drop_up
                    : Icons.arrow_drop_down,
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
    final isPlaylist = widget.type == SharedListType.playlist;
    final showDate = availableWidth > 800 && widget.datesAdded != null;

    return SliverFixedExtentList(
      itemExtent: 64.0,
      delegate: SliverChildBuilderDelegate((context, rowIndex) {
        if (rowIndex >= widget.sortedIndices.length) return null;
        final originalIndex = widget.sortedIndices[rowIndex];
        if (originalIndex >= widget.songs.length) return null;
        final song = widget.songs[originalIndex];
        final dateAdded =
            (showDate &&
                widget.datesAdded != null &&
                originalIndex < widget.datesAdded!.length)
            ? widget.datesAdded![originalIndex]
            : null;

        return RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: TrackRow(
              track: song,
              style: AppStyle.Original,
              viewContext: widget.viewContext,
              index: rowIndex,
              showAlbumName: isPlaylist && availableWidth > 600,
              showDateAdded: showDate,
              dateAdded: dateAdded,
              showDuration: true,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              trailing: SizedBox(
                width: 36,
                child: Center(
                  child: LikeButton(track: song, hoverOnlyWhenUnliked: true),
                ),
              ),
              onTap: () => widget.onPlayTrack(rowIndex),
              onPlayPause: () => widget.onPlayTrack(rowIndex),
              onAlbumTap: () => widget.onOpenAlbum?.call(song.album),
              onArtistTap: (artist) => widget.onOpenArtist?.call(artist),
              onMoreTap: (buttonContext) =>
                  widget.onTrackContextMenu(buttonContext, song, null),
              onSecondaryTapDown: (details) => widget.onTrackContextMenu(
                context,
                song,
                details.globalPosition,
              ),
            ),
          ),
        );
      }, childCount: widget.sortedIndices.length),
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
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
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.recommendedSongs.length; i++) ...[
          () {
            final song = widget.recommendedSongs[i];
            final isAdding = widget.addingRecommendationTrackIDs.contains(
              song.id,
            );
            final isAdded = widget.addedRecommendationTrackIDs.contains(
              song.id,
            );

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: TrackRow(
                track: song,
                style: AppStyle.Original,
                viewContext: widget.viewContext,
                index: null,
                playIconLocation: PlayIconLocation.art,
                showAlbumName: true,
                showDuration: false,
                trailing: GenericFilledButton(
                  onPressed: (isAdding || isAdded)
                      ? null
                      : () => widget.onAddRecommendedTrack(song),
                  child: isAdding
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isAdded ? 'Added' : 'Add'),
                ),
                onTap: () => widget.onAddRecommendedTrack(song),
                onPlayPause: () => widget.onPlayTrack(i),
                onAlbumTap: () => widget.onOpenAlbum?.call(song.album),
                onArtistTap: (artist) => widget.onOpenArtist?.call(artist),
                onSecondaryTapDown: (details) => widget.onTrackContextMenu(
                  context,
                  song,
                  details.globalPosition,
                ),
              ),
            );
          }(),
        ],
      ],
    );
  }

  Widget _buildStickyBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedSlide(
      offset: _showStickyBar ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showStickyBar ? 1 : 0,
        duration: const Duration(milliseconds: 140),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: _stickyBarColor.withValues(alpha: 0.95),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Selector<WispAudioHandler, bool>(
                selector: (context, player) =>
                    player.isPlaying &&
                    player.currentTrack != null &&
                    player.playbackContext?.matches(widget.viewContext) == true,
                builder: (context, isPlayingList, _) {
                  return SizedBox(
                    width: 36,
                    height: 36,
                    child: GenericFilledButton(
                      onPressed: widget.isLoading ? null : widget.onPlayAll,
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      child: Icon(
                        isPlayingList ? Icons.pause : Icons.play_arrow,
                        size: 20,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
