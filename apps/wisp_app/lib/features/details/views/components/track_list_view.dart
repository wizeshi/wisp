// Copyright © 2026 wizeshi

part of '../list_detail_view.dart';

extension _ListDetailTrackList on _SharedListDetailViewState {
  Widget _buildSongTitleWithIcons(
    GenericSong song, {
    required bool isCurrentTrack,
    required bool isDesktop,
    required bool isAppleStyle,
  }) {
    return ClipRRect(
      child: Row(
        children: [
          if (isAppleStyle && song.explicit) ...[
            Icon(Icons.explicit, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 2),
          ],
          if (isAppleStyle) ...[
            ValueListenableBuilder<TrackDownloadProgress>(
              valueListenable: AudioCacheManager.instance.watchTrack(song.id),
              builder: (context, state, _) {
                final isCached = state.isCached;
                final isDownloading = state.isDownloading;
                if (!isCached && !isDownloading) return const SizedBox.shrink();
                if (isDownloading) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        value: state.progress,
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Colors.grey[800],
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.offline_pin,
                    size: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ],
          Text(
            song.title,
            style: TextStyle(
              color: isCurrentTrack
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Builds a row with optional explicit/cached icons followed by the artist list.
  Widget _buildArtistWithIcons(
    GenericSong song,
    List<GenericSimpleArtist> artists, {
    required bool isDesktop,
    required bool isAppleStyle,
  }) {
    return Row(
      children: [
        if (!isAppleStyle && song.explicit) ...[
          Icon(Icons.explicit, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 2),
        ],
        if (!isAppleStyle) ...[
          ValueListenableBuilder<TrackDownloadProgress>(
            valueListenable: AudioCacheManager.instance.watchTrack(song.id),
            builder: (context, state, _) {
              final isCached = state.isCached;
              final isDownloading = state.isDownloading;
              if (!isCached && !isDownloading) return const SizedBox.shrink();
              if (isDownloading) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      value: state.progress,
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                      backgroundColor: Colors.grey[800],
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.offline_pin,
                  size: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              );
            },
          ),
        ],
        Expanded(child: _buildArtistLine(artists, isDesktop: isDesktop)),
      ],
    );
  }

  Widget _buildDesktopTrackRow(
    BuildContext context,
    int rowIndex, {
    required double availableWidth,
  }) {
    final player = context.read<global_audio_player.WispAudioHandler>();
    final index = _sortedIndices[rowIndex];
    final item = _items[index];
    final song = _toGenericSong(item);
    final album = _getAlbum(item);
    final visibleColumns = _getVisibleColumns(availableWidth);
    final isPlaylist = widget.type == SharedListType.playlist;
    final viewContext = _viewContext;
    // Computed here (during build) rather than inside `onPlayPause` below â€”
    // `context.select` (which this wraps) is only valid during build, not
    // inside a callback invoked later on tap.
    final isCurrentHere = context.watchIsCurrentTrackHere(
      trackId: song.id,
      viewContext: viewContext,
    );
    final isApple =
        context.select<PreferencesProvider, AppStyle>((p) => p.style) ==
        AppStyle.AppleMusic;

    return TrackRow(
      track: song,
      viewContext: viewContext,
      index: rowIndex,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      indexColumnWidth: 40,
      dateColumnWidth: 120,
      showArtistColumn: visibleColumns.showArtistColumn,
      showArtistInline: visibleColumns.showArtistInline,
      showAlbumName: (isApple || isPlaylist) && visibleColumns.showAlbum,
      showDuration: visibleColumns.showTime,
      showDateAdded: isPlaylist && visibleColumns.showAddedAt,
      showSource: true,
      dateAdded: _getAddedAt(item),
      onAlbumTap: (album != null && album.id.isNotEmpty)
          ? () => _openSharedList(
              SharedListType.album,
              album.id,
              title: album.title,
              thumbnailUrl: album.thumbnailUrl,
            )
          : null,
      onAlbumSecondaryTapDown: (album != null && album.id.isNotEmpty)
          ? (details) => EntityContextMenus.showAlbumMenu(
              context,
              album: GenericAlbum(
                id: album.id,
                source: album.source,
                title: album.title,
                thumbnailUrl: album.thumbnailUrl,
                artists: album.artists,
                label: album.label,
                releaseDate: album.releaseDate,
                explicit: song.explicit,
                durationSecs: 0,
              ),
              globalPosition: details.globalPosition,
            )
          : null,
      onArtistTap: (artist) => _openArtist(artist),
      onArtistSecondaryTapDown: (artist, details) =>
          EntityContextMenus.showArtistMenu(
            context,
            artist: artist,
            globalPosition: details.globalPosition,
          ),
      onTap: () => _handleRowDoubleClick(song.id, () => _playQueueAt(rowIndex)),
      onPlayPause: () {
        if (isCurrentHere) {
          _toggleCurrentTrackPlayback(player);
        } else {
          _playQueueAt(rowIndex);
        }
      },
      onSecondaryTapDown: (details) =>
          _showSongContextMenu(song, globalPosition: details.globalPosition),
      onMoreTap: (buttonContext) =>
          _showSongContextMenu(song, anchorContext: buttonContext),
      trailing: SizedBox(
        width: 28,
        child: LikeButton(
          track: song,
          iconSize: 16,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          color: Theme.of(context).colorScheme.primary,
          hoverOnlyWhenUnliked: true,
        ),
      ),
    );
  }

  Widget _buildSongRow(
    BuildContext context,
    int rowIndex, {
    required bool isMobile,
    required bool isAppleStyle,
    required double availableWidth,
  }) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return Builder(
      builder: (context) {
        // `player` is only needed here to pass into onPressed/onTap
        // callbacks, so `read` (no rebuild) is enough for it.
        final player = context.read<global_audio_player.WispAudioHandler>();
        final index = _sortedIndices[rowIndex];
        final item = _items[index];
        final song = _toGenericSong(item);
        final isCurrentTrack = context
            .select<global_audio_player.WispAudioHandler, bool>(
              (p) => p.currentTrack?.id == song.id,
            );
        final isPlayingThisTrack =
            isCurrentTrack &&
            context.select<global_audio_player.WispAudioHandler, bool>(
              (p) => p.isPlaying,
            );
        final album = _getAlbum(item);
        final artists = _getArtists(item);
        final visibleColumns = _getVisibleColumns(availableWidth);

        final isHovering = _hoveredSongIds.contains(song.id);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (!isDesktop) return;
            _safeSetState(() => _hoveredSongIds.add(song.id));
          },
          onExit: (_) {
            if (!isDesktop) return;
            _safeSetState(() => _hoveredSongIds.remove(song.id));
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: isDesktop
                ? (details) {
                    _showSongContextMenu(
                      song,
                      globalPosition: details.globalPosition,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    _showSongContextMenu(song);
                  },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: isDesktop
                    ? () => _handleRowDoubleClick(
                        song.id,
                        () => _playQueueAt(rowIndex),
                      )
                    : () {
                        if (isCurrentTrack) {
                          _toggleCurrentTrackPlayback(player);
                        } else {
                          _playQueueAt(rowIndex);
                        }
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Row(
                    children: [
                      if (isDesktop && !isAppleStyle) ...[
                        SizedBox(
                          width: 40,
                          child: isHovering
                              ? IconButton(
                                  icon: Icon(
                                    isPlayingThisTrack
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    if (isCurrentTrack) {
                                      _toggleCurrentTrackPlayback(player);
                                    } else {
                                      _playQueueAt(rowIndex);
                                    }
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                )
                              : Text(
                                  '${rowIndex + 1}',
                                  style: TextStyle(color: Colors.grey[400]),
                                  textAlign: TextAlign.center,
                                ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  color: Colors.grey[900],
                                  child: CachedNetworkImage(
                                    imageUrl: _getThumbnail(item),
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                    memCacheWidth: 88,
                                    memCacheHeight: 88,
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                    ),
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[800]),
                                  ),
                                ),
                              ),
                              if (isDesktop && isAppleStyle) ...[
                                AnimatedOpacity(
                                  opacity: isHovering ? 1 : 0,
                                  duration: const Duration(milliseconds: 120),
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                  ),
                                ),
                                if (isHovering)
                                  Positioned.fill(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          if (isCurrentTrack) {
                                            _toggleCurrentTrackPlayback(player);
                                          } else {
                                            _playQueueAt(rowIndex);
                                          }
                                        },
                                        child: Icon(
                                          isPlayingThisTrack
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildSongTitleWithIcons(
                              song,
                              isCurrentTrack: isCurrentTrack,
                              isDesktop: isDesktop,
                              isAppleStyle: isAppleStyle,
                            ),
                            if (!isAppleStyle ||
                                isMobile ||
                                visibleColumns.showArtistInline) ...[
                              const SizedBox(height: 2),
                              _buildArtistWithIcons(
                                song,
                                artists,
                                isDesktop: isDesktop,
                                isAppleStyle: isAppleStyle,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!isMobile && isAppleStyle) ...[
                        // Artist column - only shown when artist column should be visible
                        if (visibleColumns.showArtistColumn)
                          Expanded(
                            flex: 2,
                            child: _buildArtistWithIcons(
                              song,
                              artists,
                              isDesktop: isDesktop,
                              isAppleStyle: isAppleStyle,
                            ),
                          ),
                        // Album column - hidden when album is not visible
                        if (visibleColumns.showAlbum)
                          Expanded(
                            flex: 2,
                            child:
                                (isDesktop &&
                                    album != null &&
                                    album.id.isNotEmpty)
                                ? HoverUnderline(
                                    onTap: () {
                                      _openSharedList(
                                        SharedListType.album,
                                        album.id,
                                        title: album.title,
                                        thumbnailUrl: album.thumbnailUrl,
                                      );
                                    },
                                    onSecondaryTapDown: (details) {
                                      EntityContextMenus.showAlbumMenu(
                                        context,
                                        album: GenericAlbum(
                                          id: album.id,
                                          source: album.source,
                                          title: album.title,
                                          thumbnailUrl: album.thumbnailUrl,
                                          artists: album.artists,
                                          label: album.label,
                                          releaseDate: album.releaseDate,
                                          explicit: song.explicit,
                                          durationSecs: 0,
                                        ),
                                        globalPosition: details.globalPosition,
                                      );
                                    },
                                    builder: (isHovering) => Text(
                                      _getAlbumTitle(item),
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                        decoration: isHovering
                                            ? TextDecoration.underline
                                            : TextDecoration.none,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                : Text(
                                    _getAlbumTitle(item),
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                        // Time column - hidden at smallest width
                        if (visibleColumns.showTime)
                          SizedBox(
                            width: 70,
                            child: Text(
                              _formatDuration(_getDuration(item)),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        SizedBox(
                          width: 48, // Updated width
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Builder(
                              builder: (buttonContext) => IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                                icon: Icon(
                                  CupertinoIcons.ellipsis,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 18,
                                ),
                                onPressed: () => {
                                  _showSongContextMenu(
                                    song,
                                    anchorContext: buttonContext,
                                  ),
                                },
                                onLongPress: null,
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        // Spotify style - Album column
                        if (!isMobile &&
                            widget.type == SharedListType.playlist &&
                            visibleColumns.showAlbum)
                          Expanded(
                            flex: 2,
                            child:
                                (isDesktop &&
                                    album != null &&
                                    album.id.isNotEmpty)
                                ? HoverUnderline(
                                    onTap: () {
                                      _openSharedList(
                                        SharedListType.album,
                                        album.id,
                                        title: album.title,
                                        thumbnailUrl: album.thumbnailUrl,
                                      );
                                    },
                                    onSecondaryTapDown: (details) {
                                      _showSongContextMenu(
                                        song,
                                        globalPosition: details.globalPosition,
                                      );
                                    },
                                    builder: (isHovering) => Text(
                                      _getAlbumTitle(item),
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                        decoration: isHovering
                                            ? TextDecoration.underline
                                            : TextDecoration.none,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : Text(
                                    _getAlbumTitle(item),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                          )
                        else if (!isMobile &&
                            widget.type != SharedListType.playlist)
                          const SizedBox(width: 80),
                        // Spotify style - Added At column
                        if (!isMobile &&
                            widget.type == SharedListType.playlist &&
                            visibleColumns.showAddedAt)
                          SizedBox(
                            width: 120,
                            child: Text(
                              _formatAddedAt(_getAddedAt(item)),
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else if (!isMobile &&
                            widget.type != SharedListType.playlist)
                          const SizedBox(width: 120),
                        if (isDesktop) ...[
                          AnimatedOpacity(
                            opacity: isHovering ? 1 : 0,
                            duration: const Duration(milliseconds: 120),
                            child: IgnorePointer(
                              ignoring: !isHovering,
                              child: SizedBox(
                                width: 28,
                                child: LikeButton(
                                  track: song,
                                  iconSize: 16,
                                  padding: const EdgeInsets.all(2),
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Spotify style - Duration column
                        if (visibleColumns.showTime)
                          SizedBox(
                            width: isMobile ? 40 : 80,
                            child: Text(
                              _formatDuration(_getDuration(item)),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          )
                        else if (!isMobile)
                          const SizedBox(width: 80),
                        SizedBox(width: isMobile ? 0 : 12),
                        !isMobile
                            ? SizedBox(
                                width: 32,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Icon(
                                    Icons.graphic_eq,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    size: isMobile ? 16 : 18,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ],
                      if (isMobile && isAppleStyle)
                        SizedBox(
                          width: 40,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Builder(
                              builder: (buttonContext) => IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                                icon: Icon(
                                  CupertinoIcons.ellipsis,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _showSongContextMenu(
                                    song,
                                    anchorContext: buttonContext,
                                  );
                                },
                                onLongPress: null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Proper (Sliver-based) virtualization for the mobile Spotify-style
  /// song list. This is placed directly in the parent CustomScrollView's
  /// `slivers` list (see _SpotifyListDetailRenderer) instead of behind a
  /// SliverToBoxAdapter, so Flutter's own RenderSliverList decides which
  /// rows to build/keep-alive/dispose as the user scrolls -- no manual
  /// scroll-offset tracking, no manually-sliced start/end window, and no
  /// full-window rebuild on every scroll tick.
  Widget _buildMobileSpotifySongsSliver({required double availableWidth}) {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_sortedIndices.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No songs to display',
            style: TextStyle(color: Colors.grey[400]),
          ),
        ),
      );
    }

    return SliverFixedExtentList(
      itemExtent: _SharedListDetailViewState._rowHeightMobile,
      delegate: SliverChildBuilderDelegate(
        (context, rowIndex) => _buildSongRow(
          context,
          rowIndex,
          isMobile: true,
          isAppleStyle: false,
          availableWidth: availableWidth,
        ),
        childCount: _sortedIndices.length,
      ),
    );
  }

  Widget _buildSongList({
    bool isMobile = false,
    _ListVisualStyle visualStyle = _ListVisualStyle.spotify,
    required double availableWidth,
  }) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_sortedIndices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No songs to display',
          style: TextStyle(color: Colors.grey[400]),
        ),
      );
    }

    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final isAppleStyle = visualStyle == _ListVisualStyle.apple;
    final totalCount = _sortedIndices.length;
    final controller = isMobile
        ? _mobileScrollController
        : _desktopScrollController;
    final useVirtualizedWindow =
        controller.hasClients || _songListTopOffsetNotifier.value >= 0;

    if (useVirtualizedWindow) {
      _scheduleSongListOffsetUpdate(controller);
      final rowHeight = isMobile
          ? _SharedListDetailViewState._rowHeightMobile
          : _SharedListDetailViewState._rowHeightDesktop;
      final viewport = controller.hasClients
          ? controller.position.viewportDimension
          : 0;
      final scrollOffset = controller.hasClients ? controller.offset : 0;
      final effectiveOffset = (scrollOffset - _songListTopOffsetNotifier.value)
          .clamp(0.0, double.infinity);
      final initialWindowSize =
          ((viewport / rowHeight).ceil() +
                  _SharedListDetailViewState._windowBuffer * 2)
              .clamp(0, totalCount);

      int startIndex;
      int endIndex;
      if (!controller.hasClients || viewport == 0) {
        startIndex = 0;
        endIndex = totalCount == 0
            ? 0
            : (initialWindowSize - 1).clamp(0, totalCount - 1);
      } else {
        final first =
            (effectiveOffset / rowHeight).floor() -
            _SharedListDetailViewState._windowBuffer;
        final last =
            ((effectiveOffset + viewport) / rowHeight).ceil() +
            _SharedListDetailViewState._windowBuffer;
        startIndex = first.clamp(0, totalCount - 1);
        endIndex = last.clamp(0, totalCount - 1);
      }

      final visibleCount = totalCount == 0 ? 0 : (endIndex - startIndex + 1);
      final topSpacer = startIndex * rowHeight;
      final bottomSpacer = (totalCount - endIndex - 1) * rowHeight;

      return Column(
        children: [
          SizedBox(key: _songListKey, height: 0),
          if (topSpacer > 0) SizedBox(height: topSpacer),
          ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleCount,
            itemBuilder: (context, idx) {
              return Builder(
                builder: (context) {
                  final rowIndex = startIndex + idx;

                  if (isDesktop) {
                    return _buildDesktopTrackRow(
                      context,
                      rowIndex,
                      availableWidth: availableWidth,
                    );
                  }

                  // `player` is only needed here to pass into onPressed/onTap
                  // callbacks, so `read` (no rebuild) is enough for it.
                  final player = context
                      .read<global_audio_player.WispAudioHandler>();
                  final index = _sortedIndices[rowIndex];
                  final item = _items[index];
                  final song = _toGenericSong(item);
                  final isCurrentTrack = context
                      .select<global_audio_player.WispAudioHandler, bool>(
                        (p) => p.currentTrack?.id == song.id,
                      );
                  final isPlayingThisTrack =
                      isCurrentTrack &&
                      context
                          .select<global_audio_player.WispAudioHandler, bool>(
                            (p) => p.isPlaying,
                          );
                  final album = _getAlbum(item);
                  final artists = _getArtists(item);
                  final visibleColumns = _getVisibleColumns(availableWidth);

                  final isHovering = _hoveredSongIds.contains(song.id);
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) {
                      if (!isDesktop) return;
                      _safeSetState(() => _hoveredSongIds.add(song.id));
                    },
                    onExit: (_) {
                      if (!isDesktop) return;
                      _safeSetState(() => _hoveredSongIds.remove(song.id));
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapUp: isDesktop
                          ? (details) {
                              _showSongContextMenu(
                                song,
                                globalPosition: details.globalPosition,
                              );
                            }
                          : null,
                      onLongPress: isDesktop
                          ? null
                          : () {
                              _showSongContextMenu(song);
                            },
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          mouseCursor: SystemMouseCursors.click,
                          onTap: isDesktop
                              ? () => _handleRowDoubleClick(
                                  song.id,
                                  () => _playQueueAt(rowIndex),
                                )
                              : () {
                                  if (isCurrentTrack) {
                                    _toggleCurrentTrackPlayback(player);
                                  } else {
                                    _playQueueAt(rowIndex);
                                  }
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Row(
                              children: [
                                if (isDesktop && !isAppleStyle) ...[
                                  SizedBox(
                                    width: 40,
                                    child: isHovering
                                        ? IconButton(
                                            icon: Icon(
                                              isPlayingThisTrack
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              if (isCurrentTrack) {
                                                _toggleCurrentTrackPlayback(
                                                  player,
                                                );
                                              } else {
                                                _playQueueAt(rowIndex);
                                              }
                                            },
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                          )
                                        : Text(
                                            '${rowIndex + 1}',
                                            style: TextStyle(
                                              color: Colors.grey[400],
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Container(
                                            color: Colors.grey[900],
                                            child: CachedNetworkImage(
                                              imageUrl: _getThumbnail(item),
                                              fit: BoxFit.cover,
                                              filterQuality:
                                                  FilterQuality.medium,
                                              memCacheWidth: 88,
                                              memCacheHeight: 88,
                                              errorWidget:
                                                  (context, url, error) => Icon(
                                                    Icons.music_note,
                                                    color: Colors.grey[700],
                                                  ),
                                              placeholder: (context, url) =>
                                                  Container(
                                                    color: Colors.grey[800],
                                                  ),
                                            ),
                                          ),
                                        ),
                                        if (isDesktop && isAppleStyle) ...[
                                          AnimatedOpacity(
                                            opacity: isHovering ? 1 : 0,
                                            duration: const Duration(
                                              milliseconds: 120,
                                            ),
                                            child: Container(
                                              color: Colors.black.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                          ),
                                          if (isHovering)
                                            Positioned.fill(
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap: () {
                                                    if (isCurrentTrack) {
                                                      _toggleCurrentTrackPlayback(
                                                        player,
                                                      );
                                                    } else {
                                                      _playQueueAt(rowIndex);
                                                    }
                                                  },
                                                  child: Icon(
                                                    isPlayingThisTrack
                                                        ? Icons.pause
                                                        : Icons.play_arrow,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildSongTitleWithIcons(
                                        song,
                                        isCurrentTrack: isCurrentTrack,
                                        isDesktop: isDesktop,
                                        isAppleStyle: isAppleStyle,
                                      ),
                                      if (!isAppleStyle ||
                                          isMobile ||
                                          visibleColumns.showArtistInline) ...[
                                        const SizedBox(height: 2),
                                        _buildArtistWithIcons(
                                          song,
                                          artists,
                                          isDesktop: isDesktop,
                                          isAppleStyle: isAppleStyle,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (!isMobile && isAppleStyle) ...[
                                  // Artist column - only shown when artist column should be visible
                                  if (visibleColumns.showArtistColumn)
                                    Expanded(
                                      flex: 2,
                                      child: _buildArtistWithIcons(
                                        song,
                                        artists,
                                        isDesktop: isDesktop,
                                        isAppleStyle: isAppleStyle,
                                      ),
                                    ),
                                  // Album column - hidden when album is not visible
                                  if (visibleColumns.showAlbum)
                                    Expanded(
                                      flex: 2,
                                      child:
                                          (isDesktop &&
                                              album != null &&
                                              album.id.isNotEmpty)
                                          ? HoverUnderline(
                                              onTap: () {
                                                _openSharedList(
                                                  SharedListType.album,
                                                  album.id,
                                                  title: album.title,
                                                  thumbnailUrl:
                                                      album.thumbnailUrl,
                                                );
                                              },
                                              onSecondaryTapDown: (details) {
                                                EntityContextMenus.showAlbumMenu(
                                                  context,
                                                  album: GenericAlbum(
                                                    id: album.id,
                                                    source: album.source,
                                                    title: album.title,
                                                    thumbnailUrl:
                                                        album.thumbnailUrl,
                                                    artists: album.artists,
                                                    label: album.label,
                                                    releaseDate:
                                                        album.releaseDate,
                                                    explicit: song.explicit,
                                                    durationSecs: 0,
                                                  ),
                                                  globalPosition:
                                                      details.globalPosition,
                                                );
                                              },
                                              builder: (isHovering) => Text(
                                                _getAlbumTitle(item),
                                                style: TextStyle(
                                                  color: Colors.grey[400],
                                                  fontSize: 12,
                                                  decoration: isHovering
                                                      ? TextDecoration.underline
                                                      : TextDecoration.none,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            )
                                          : Text(
                                              _getAlbumTitle(item),
                                              style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                    ),
                                  // Time column - hidden at smallest width
                                  if (visibleColumns.showTime)
                                    SizedBox(
                                      width: 70,
                                      child: Text(
                                        _formatDuration(_getDuration(item)),
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  SizedBox(
                                    width: 48, // Updated width
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Builder(
                                        builder: (buttonContext) => IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          icon: Icon(
                                            CupertinoIcons.ellipsis,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            size: 18,
                                          ),
                                          onPressed: () => {
                                            _showSongContextMenu(
                                              song,
                                              anchorContext: buttonContext,
                                            ),
                                          },
                                          onLongPress: null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  // Spotify style - Album column
                                  if (!isMobile &&
                                      widget.type == SharedListType.playlist &&
                                      visibleColumns.showAlbum)
                                    Expanded(
                                      flex: 2,
                                      child:
                                          (isDesktop &&
                                              album != null &&
                                              album.id.isNotEmpty)
                                          ? HoverUnderline(
                                              onTap: () {
                                                _openSharedList(
                                                  SharedListType.album,
                                                  album.id,
                                                  title: album.title,
                                                  thumbnailUrl:
                                                      album.thumbnailUrl,
                                                );
                                              },
                                              onSecondaryTapDown: (details) {
                                                _showSongContextMenu(
                                                  song,
                                                  globalPosition:
                                                      details.globalPosition,
                                                );
                                              },
                                              builder: (isHovering) => Text(
                                                _getAlbumTitle(item),
                                                style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 12,
                                                  decoration: isHovering
                                                      ? TextDecoration.underline
                                                      : TextDecoration.none,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                            )
                                          : Text(
                                              _getAlbumTitle(item),
                                              style: TextStyle(
                                                color: Colors.grey[500],
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
                                    )
                                  else if (!isMobile &&
                                      widget.type != SharedListType.playlist)
                                    const SizedBox(width: 80),
                                  // Spotify style - Added At column
                                  if (!isMobile &&
                                      widget.type == SharedListType.playlist &&
                                      visibleColumns.showAddedAt)
                                    SizedBox(
                                      width: 120,
                                      child: Text(
                                        _formatAddedAt(_getAddedAt(item)),
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                  else if (!isMobile &&
                                      widget.type != SharedListType.playlist)
                                    const SizedBox(width: 120),
                                  if (isDesktop) ...[
                                    AnimatedOpacity(
                                      opacity: isHovering ? 1 : 0,
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      child: IgnorePointer(
                                        ignoring: !isHovering,
                                        child: SizedBox(
                                          width: 28,
                                          child: LikeButton(
                                            track: song,
                                            iconSize: 16,
                                            padding: const EdgeInsets.all(2),
                                            constraints: const BoxConstraints(
                                              minWidth: 24,
                                              minHeight: 24,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  // Spotify style - Duration column
                                  if (visibleColumns.showTime)
                                    SizedBox(
                                      width: isMobile ? 40 : 80,
                                      child: Text(
                                        _formatDuration(_getDuration(item)),
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    )
                                  else if (!isMobile)
                                    const SizedBox(width: 80),
                                  SizedBox(width: isMobile ? 0 : 12),
                                  !isMobile
                                      ? SizedBox(
                                          width: 32,
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Icon(
                                              Icons.graphic_eq,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              size: isMobile ? 16 : 18,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ],
                                if (isMobile && isAppleStyle)
                                  SizedBox(
                                    width: 40,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Builder(
                                        builder: (buttonContext) => IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          icon: Icon(
                                            CupertinoIcons.ellipsis,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            _showSongContextMenu(
                                              song,
                                              anchorContext: buttonContext,
                                            );
                                          },
                                          onLongPress: null,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (bottomSpacer > 0) SizedBox(height: bottomSpacer),
        ],
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCount,
      itemBuilder: (context, idx) {
        return Builder(
          builder: (context) {
            if (isDesktop) {
              return _buildDesktopTrackRow(
                context,
                idx,
                availableWidth: availableWidth,
              );
            }

            final player = context.read<global_audio_player.WispAudioHandler>();
            final index = _sortedIndices[idx];
            final item = _items[index];
            final isEven = idx % 2 == 0;
            final song = _toGenericSong(item);
            final isCurrentTrack = context
                .select<global_audio_player.WispAudioHandler, bool>(
                  (p) => p.currentTrack?.id == song.id,
                );
            final isPlayingThisTrack =
                isCurrentTrack &&
                context.select<global_audio_player.WispAudioHandler, bool>(
                  (p) => p.isPlaying,
                );
            final album = _getAlbum(item);
            final artists = _getArtists(item);
            final visibleColumns = _getVisibleColumns(availableWidth);

            final isHovering = _hoveredSongIds.contains(song.id);
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) {
                if (!isDesktop) return;
                _safeSetState(() => _hoveredSongIds.add(song.id));
              },
              onExit: (_) {
                if (!isDesktop) return;
                _safeSetState(() => _hoveredSongIds.remove(song.id));
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapUp: isDesktop
                    ? (details) {
                        _showSongContextMenu(
                          song,
                          globalPosition: details.globalPosition,
                        );
                      }
                    : null,
                onLongPress: isDesktop
                    ? null
                    : () {
                        _showSongContextMenu(song);
                      },
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    onTap: isDesktop
                        ? () => _handleRowDoubleClick(
                            song.id,
                            () => _playQueueAt(idx),
                          )
                        : () {
                            if (isCurrentTrack) {
                              _toggleCurrentTrackPlayback(player);
                            } else {
                              _playQueueAt(idx);
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isAppleStyle
                            ? Colors.transparent
                            : (isEven
                                  ? Colors.transparent
                                  : Colors.black.withValues(alpha: 0.15)),
                        borderRadius: isAppleStyle
                            ? BorderRadius.zero
                            : BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          if (isDesktop && !isAppleStyle) ...[
                            SizedBox(
                              width: 40,
                              child: isHovering
                                  ? IconButton(
                                      icon: Icon(
                                        isPlayingThisTrack
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        if (isCurrentTrack) {
                                          _toggleCurrentTrackPlayback(player);
                                        } else {
                                          _playQueueAt(idx);
                                        }
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                    )
                                  : Text(
                                      '${idx + 1}',
                                      style: TextStyle(color: Colors.grey[400]),
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.grey[900],
                                      child: CachedNetworkImage(
                                        imageUrl: _getThumbnail(item),
                                        filterQuality: FilterQuality.medium,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 88,
                                        memCacheHeight: 88,
                                        errorWidget: (context, url, error) =>
                                            Icon(
                                              Icons.music_note,
                                              color: Colors.grey[700],
                                            ),
                                        placeholder: (context, url) =>
                                            Container(color: Colors.grey[800]),
                                      ),
                                    ),
                                  ),
                                  if (isDesktop && isAppleStyle) ...[
                                    AnimatedOpacity(
                                      opacity: isHovering ? 1 : 0,
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      child: Container(
                                        color: Colors.black.withValues(
                                          alpha: 0.45,
                                        ),
                                      ),
                                    ),
                                    if (isHovering)
                                      Positioned.fill(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () {
                                              if (isCurrentTrack) {
                                                _toggleCurrentTrackPlayback(
                                                  player,
                                                );
                                              } else {
                                                _playQueueAt(idx);
                                              }
                                            },
                                            child: Icon(
                                              isPlayingThisTrack
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildSongTitleWithIcons(
                                  song,
                                  isCurrentTrack: isCurrentTrack,
                                  isDesktop: isDesktop,
                                  isAppleStyle: isAppleStyle,
                                ),
                                if (!isAppleStyle ||
                                    isMobile ||
                                    visibleColumns.showArtistInline) ...[
                                  const SizedBox(height: 2),
                                  _buildArtistWithIcons(
                                    song,
                                    artists,
                                    isDesktop: isDesktop,
                                    isAppleStyle: isAppleStyle,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!isMobile && isAppleStyle) ...[
                            // Artist column - only shown when artist column should be visible
                            if (visibleColumns.showArtistColumn)
                              Expanded(
                                flex: 2,
                                child: _buildArtistWithIcons(
                                  song,
                                  artists,
                                  isDesktop: isDesktop,
                                  isAppleStyle: isAppleStyle,
                                ),
                              ),
                            // Album column - hidden when album is not visible
                            if (visibleColumns.showAlbum)
                              Expanded(
                                flex: 2,
                                child:
                                    (isDesktop &&
                                        album != null &&
                                        album.id.isNotEmpty)
                                    ? HoverUnderline(
                                        onTap: () {
                                          _openSharedList(
                                            SharedListType.album,
                                            album.id,
                                            title: album.title,
                                            thumbnailUrl: album.thumbnailUrl,
                                          );
                                        },
                                        onSecondaryTapDown: (details) {
                                          EntityContextMenus.showAlbumMenu(
                                            context,
                                            album: GenericAlbum(
                                              id: album.id,
                                              source: album.source,
                                              title: album.title,
                                              thumbnailUrl: album.thumbnailUrl,
                                              artists: album.artists,
                                              label: album.label,
                                              releaseDate: album.releaseDate,
                                              explicit: song.explicit,
                                              durationSecs: 0,
                                            ),
                                            globalPosition:
                                                details.globalPosition,
                                          );
                                        },
                                        builder: (isHovering) => Text(
                                          _getAlbumTitle(item),
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 12,
                                            decoration: isHovering
                                                ? TextDecoration.underline
                                                : TextDecoration.none,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )
                                    : Text(
                                        _getAlbumTitle(item),
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                            // Time column - hidden at smallest width
                            if (visibleColumns.showTime)
                              SizedBox(
                                width: 70,
                                child: Text(
                                  _formatDuration(_getDuration(item)),
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            SizedBox(
                              width: 24,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Builder(
                                  builder: (buttonContext) => IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 24,
                                      minHeight: 24,
                                    ),
                                    icon: Icon(
                                      CupertinoIcons.ellipsis,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      size: 18,
                                    ),
                                    onLongPress: null,
                                    onPressed: () {
                                      _showSongContextMenu(
                                        song,
                                        anchorContext: buttonContext,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            // Spotify style - Album column
                            if (!isMobile &&
                                widget.type == SharedListType.playlist &&
                                visibleColumns.showAlbum)
                              Expanded(
                                flex: 2,
                                child:
                                    (isDesktop &&
                                        album != null &&
                                        album.id.isNotEmpty)
                                    ? HoverUnderline(
                                        onTap: () {
                                          _openSharedList(
                                            SharedListType.album,
                                            album.id,
                                            title: album.title,
                                            thumbnailUrl: album.thumbnailUrl,
                                          );
                                        },
                                        onSecondaryTapDown: (details) {
                                          EntityContextMenus.showAlbumMenu(
                                            context,
                                            album: GenericAlbum(
                                              id: album.id,
                                              source: album.source,
                                              title: album.title,
                                              thumbnailUrl: album.thumbnailUrl,
                                              artists: album.artists,
                                              label: album.label,
                                              releaseDate: album.releaseDate,
                                              explicit: song.explicit,
                                              durationSecs: 0,
                                            ),
                                            globalPosition:
                                                details.globalPosition,
                                          );
                                        },
                                        builder: (isHovering) => Text(
                                          _getAlbumTitle(item),
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12,
                                            decoration: isHovering
                                                ? TextDecoration.underline
                                                : TextDecoration.none,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      )
                                    : Text(
                                        _getAlbumTitle(item),
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                              )
                            else if (!isMobile &&
                                widget.type != SharedListType.playlist)
                              const SizedBox(width: 80),
                            // Spotify style - Added At column
                            if (!isMobile &&
                                widget.type == SharedListType.playlist &&
                                visibleColumns.showAddedAt)
                              SizedBox(
                                width: 120,
                                child: Text(
                                  _formatAddedAt(_getAddedAt(item)),
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            else if (!isMobile &&
                                widget.type != SharedListType.playlist)
                              const SizedBox(width: 120),
                            if (isDesktop) ...[
                              AnimatedOpacity(
                                opacity: isHovering ? 1 : 0,
                                duration: const Duration(milliseconds: 120),
                                child: IgnorePointer(
                                  ignoring: !isHovering,
                                  child: SizedBox(
                                    width: 28,
                                    child: LikeButton(
                                      track: song,
                                      iconSize: 16,
                                      padding: const EdgeInsets.all(2),
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                        minHeight: 24,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            // Spotify style - Duration column
                            if (visibleColumns.showTime)
                              SizedBox(
                                width: isMobile ? 40 : 80,
                                child: Text(
                                  _formatDuration(_getDuration(item)),
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              )
                            else if (!isMobile)
                              const SizedBox(width: 80),
                            SizedBox(width: isMobile ? 0 : 12),
                            !isMobile
                                ? SizedBox(
                                    width: 32,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Icon(
                                        Icons.graphic_eq,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        size: isMobile ? 16 : 18,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getThumbnail(_ListItem item) {
    if (item is GenericSong) return item.thumbnailUrl;
    if (item is PlaylistItem) return item.thumbnailUrl;
    return '';
  }

  Widget _buildArtistLine(
    List<GenericSimpleArtist> artists, {
    required bool isDesktop,
  }) {
    if (artists.isEmpty) {
      return Text(
        artists.map((a) => a.name).join(', '),
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Wrap(
      children: [
        for (int i = 0; i < artists.length; i++) ...[
          HoverUnderline(
            onTap: () => _openArtist(artists[i]),
            onSecondaryTapDown: (details) {
              EntityContextMenus.showArtistMenu(
                context,
                artist: artists[i],
                globalPosition: details.globalPosition,
              );
            },
            builder: (isHovering) => Text(
              artists[i].name,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                decoration: isHovering
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (i < artists.length - 1)
            Text(', ', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ],
    );
  }
}