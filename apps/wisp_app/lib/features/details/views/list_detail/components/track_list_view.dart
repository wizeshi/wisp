// Copyright © 2026 wizeshi

part of '../../list_detail_view.dart';

extension _ListDetailTrackList on _SharedListDetailViewState {
  Widget _buildTrackRow(
    BuildContext context,
    int rowIndex, {
    required double availableWidth,
    required bool isMobile,
    AppStyle visualStyle = AppStyle.Spotify,
  }) {
    final player = context.read<global_audio_player.WispAudioHandler>();
    final index = _sortedIndices[rowIndex];
    final item = _items[index];
    final song = _toGenericSong(item);
    final album = _getAlbum(item);
    final visibleColumns = _getVisibleColumns(availableWidth);
    final isPlaylist = widget.type == SharedListType.playlist;
    final viewContext = _viewContext;
    final isApple = WispStyleTokens.fromStyle(visualStyle).isApple;

    final isCurrentHere = player.currentTrack?.id == song.id &&
        player.playbackContext?.matches(viewContext) == true;

    void handlePlayPause() {
      if (isCurrentHere) {
        _toggleCurrentTrackPlayback(player);
      } else {
        _playQueueAt(rowIndex);
      }
    }

    return TrackRow(
      track: song,
      style: visualStyle,
      viewContext: viewContext,
      index: (isApple || isMobile) ? null : rowIndex,
      playIconLocation: (isApple || isMobile) ? PlayIconLocation.art : null,
      height: 44,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 12,
        vertical: 10,
      ),
      indexColumnWidth: 40,
      dateColumnWidth: 120,
      showArtistColumn: !isMobile && visibleColumns.showArtistColumn,
      showArtistInline: isMobile || visibleColumns.showArtistInline,
      showAlbumName: !isMobile && (isApple || isPlaylist) && visibleColumns.showAlbum,
      showDuration: !isMobile && visibleColumns.showTime,
      showDateAdded: !isMobile && isPlaylist && visibleColumns.showAddedAt,
      showSource: !isMobile,
      dateAdded: _getAddedAt(item),
      onAlbumTap: (!isMobile && album != null && album.id.isNotEmpty)
          ? () => _openSharedList(
              SharedListType.album,
              album.id,
              title: album.title,
              thumbnailUrl: album.thumbnailUrl,
            )
          : null,
      onAlbumSecondaryTapDown: (!isMobile && album != null && album.id.isNotEmpty)
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
      onArtistTap: isMobile ? null : (artist) => _openArtist(artist),
      onArtistSecondaryTapDown: isMobile
          ? null
          : (artist, details) => EntityContextMenus.showArtistMenu(
              context,
              artist: artist,
              globalPosition: details.globalPosition,
            ),
      onTap: isMobile
          ? handlePlayPause
          : () => _handleRowDoubleClick(song.id, () => _playQueueAt(rowIndex)),
      onPlayPause: handlePlayPause,
      onSecondaryTapDown: (details) =>
          _showSongContextMenu(song, globalPosition: details.globalPosition),
      onLongPress: isMobile ? () => _showSongContextMenu(song) : null,
      onMoreTap: (buttonContext) =>
          _showSongContextMenu(song, anchorContext: buttonContext),
      trailing: isMobile
          ? null
          : SizedBox(
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

  /// Proper (Sliver-based) virtualization for the song list. This is placed
  /// directly in the parent CustomScrollView's `slivers` list (see
  /// _SpotifyListDetailRenderer and _AppleMusicListDetailRenderer) so Flutter's
  /// own RenderSliverFixedExtentList decides which rows to build, keep resident,
  /// and dispose as the user scrolls in O(1) constant time without manual
  /// scroll-offset tracking or layout invalidation.
  Widget _buildSongsSliver({
    required double availableWidth,
    bool isMobile = false,
    AppStyle visualStyle = AppStyle.Spotify,
  }) {
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

    final rowHeight = isMobile
        ? _SharedListDetailViewState._rowHeightMobile
        : _SharedListDetailViewState._rowHeightDesktop;

    return SliverFixedExtentList(
      itemExtent: rowHeight,
      delegate: SliverChildBuilderDelegate(
        (context, rowIndex) {
          return RepaintBoundary(
            child: Builder(
              builder: (itemContext) {
                return _buildTrackRow(
                  itemContext,
                  rowIndex,
                  availableWidth: availableWidth,
                  isMobile: isMobile,
                  visualStyle: visualStyle,
                );
              },
            ),
          );
        },
        childCount: _sortedIndices.length,
      ),
    );
  }

  String _getThumbnail(_ListItem item) {
    if (item is GenericSong) return item.thumbnailUrl;
    if (item is PlaylistItem) return item.thumbnailUrl;
    return '';
  }
}
