// Copyright © 2026 wizeshi

part of '../list_detail_view.dart';

extension _ListDetailRecommendations on _SharedListDetailViewState {
  bool _shouldShowRecommendations() {
    if (widget.type != SharedListType.playlist) return false;
    if (isLikedSongsPlaylistId(widget.id)) return false;
    if (_playlist == null) return false;
    if (_playlist!.source != SongSource.spotifyInternal) return false;
    final localPlaylists = context.read<LocalPlaylistState>();
    if (localPlaylists.isLocalPlaylistId(widget.id)) return false;
    return _playlist!.id.trim().isNotEmpty;
  }

  void _clearRecommendationsState() {
    _recommendedSongs = [];
    _recommendationsError = null;
    _isLoadingRecommendations = false;
    _skippedRecommendationTrackIDs.clear();
    _addedRecommendationTrackIDs.clear();
    _addingRecommendationTrackIDs.clear();
  }

  void _appendSkippedRecommendationTrackIDs(Iterable<String> trackIDs) {
    for (final trackID in trackIDs) {
      final normalized = trackID.trim();
      if (normalized.isEmpty) continue;
      if (_skippedRecommendationTrackIDs.contains(normalized)) continue;
      _skippedRecommendationTrackIDs.add(normalized);
    }
  }

  void _markCurrentRecommendationsAsSkipped() {
    _appendSkippedRecommendationTrackIDs(
      _recommendedSongs
          .where((track) => !_addedRecommendationTrackIDs.contains(track.id))
          .map((track) => track.id),
    );
  }

  Future<void> _loadRecommendationsIfEligible({
    bool forceRefresh = false,
    bool markCurrentAsSkipped = false,
  }) async {
    if (!_shouldShowRecommendations()) {
      if (!mounted) {
        _clearRecommendationsState();
        return;
      }
      _safeSetState(_clearRecommendationsState);
      return;
    }

    if (_isLoadingRecommendations) return;
    if (!forceRefresh && _recommendedSongs.isNotEmpty) return;

    final playlistID = _playlist?.id ?? widget.id;
    if (playlistID.trim().isEmpty) return;

    if (markCurrentAsSkipped) {
      _markCurrentRecommendationsAsSkipped();
    }

    if (mounted) {
      _safeSetState(() {
        _isLoadingRecommendations = true;
        _recommendationsError = null;
      });
    } else {
      _isLoadingRecommendations = true;
      _recommendationsError = null;
    }

    try {
      final recommendations = await _spotifyInternal.getRecommended(
        playlistID,
        _skippedRecommendationTrackIDs,
        numResults: 20,
      );
      if (!mounted) {
        _recommendedSongs = recommendations.take(10).toList();
        _isLoadingRecommendations = false;
        return;
      }
      _safeSetState(() {
        _recommendedSongs = recommendations.take(10).toList();
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      if (!mounted) {
        _recommendationsError = 'Failed to load recommendations: $e';
        _isLoadingRecommendations = false;
        return;
      }
      _safeSetState(() {
        _recommendationsError = 'Failed to load recommendations: $e';
        _isLoadingRecommendations = false;
      });
    }
  }

  Future<void> _refreshRecommendations() async {
    await _loadRecommendationsIfEligible(
      forceRefresh: true,
      markCurrentAsSkipped: true,
    );
  }

  Future<void> _addRecommendedTrack(PlaylistItem item) async {
    final playlist = _playlist;
    if (playlist == null || item.id.trim().isEmpty) return;
    if (_addingRecommendationTrackIDs.contains(item.id)) return;
    if (_addedRecommendationTrackIDs.contains(item.id)) return;

    _safeSetState(() {
      _addingRecommendationTrackIDs.add(item.id);
    });

    try {
      await _spotifyInternal.addTracksToPlaylist(playlist.id, [item.id]);
      if (!mounted) return;
      _safeSetState(() {
        _addingRecommendationTrackIDs.remove(item.id);
        _addedRecommendationTrackIDs.add(item.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to playlist'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _safeSetState(() {
        _addingRecommendationTrackIDs.remove(item.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add track: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _playRecommendedAt(int index) async {
    if (index < 0 || index >= _recommendedSongs.length) return;
    final queue = _recommendedSongs.map(_toGenericSong).toList();
    if (queue.isEmpty) return;

    final playlist = _playlist;
    final libraryFolders = context.read<LibraryFolderState>();
    await context.read<PlaybackCoordinator>().setQueue(
      queue,
      startIndex: index,
      play: true,
      playbackContext: PlaybackContext(
        type: PlaybackContextType.playlist,
        id: playlist?.id ?? widget.id,
        name: playlist?.title ?? '',
        source: playlist?.source ?? SongSource.spotifyInternal,
      ),
      shuffleEnabled: false,
    );
    if (!mounted) return;

    if (widget.type == SharedListType.playlist) {
      libraryFolders.markPlaylistPlayed(widget.id);
      context.read<SpotifyInternalProvider>().reportItemPlayed(
        itemId: widget.id,
        itemType: 'playlist',
      );
    } else if (widget.type == SharedListType.album) {
      libraryFolders.markItemPlayed(widget.id);
      context.read<SpotifyInternalProvider>().reportItemPlayed(
        itemId: widget.id,
        itemType: 'album',
      );
    }
  }

  Future<void> _toggleRecommendedTrackPlayback(
    global_audio_player.WispAudioHandler player,
    int index,
  ) async {
    if (index < 0 || index >= _recommendedSongs.length) return;
    final song = _toGenericSong(_recommendedSongs[index]);
    final isCurrentTrack = player.currentTrack?.id == song.id;
    if (isCurrentTrack) {
      _toggleCurrentTrackPlayback(player);
      return;
    }
    await _playRecommendedAt(index);
  }

  Widget _buildRecommendedSection({
    required bool isMobile,
    _ListVisualStyle visualStyle = _ListVisualStyle.spotify,
  }) {
    if (!_shouldShowRecommendations()) {
      return const SizedBox.shrink();
    }

    final isAppleStyle = visualStyle == _ListVisualStyle.apple;
    final songs = _recommendedSongs;
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 0 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: isMobile
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: isMobile
                        ? const EdgeInsets.fromLTRB(8, 12, 0, 8)
                        : EdgeInsets.zero,
                    child: Column(
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
                          "based on what's in this playlist",
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isMobile)
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: IconButton(
                        onPressed: _isLoadingRecommendations
                            ? null
                            : _refreshRecommendations,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 34,
                        ),
                        icon: _isLoadingRecommendations
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Refresh recommendations',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: isMobile ? 0 : 4),
          if (_recommendationsError != null && songs.isEmpty)
            Padding(
              padding: isMobile
                  ? const EdgeInsets.fromLTRB(0, 0, 0, 8)
                  : const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                _recommendationsError!,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
          if (_isLoadingRecommendations && songs.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: CircularProgressIndicator(),
              ),
            )
          else if (songs.isEmpty)
            Padding(
              padding: isMobile
                  ? const EdgeInsets.only(top: 8, bottom: 8)
                  : const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text(
                'No recommendations available right now.',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            )
          else
            ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: songs.length,
              separatorBuilder: (context, index) =>
                  SizedBox(height: isMobile ? 2 : 6),
              itemBuilder: (context, index) {
                final item = songs[index];
                return _buildRecommendedSongRow(
                  item: item,
                  index: index,
                  isMobile: isMobile,
                  isDesktop: isDesktop,
                  isAppleStyle: isAppleStyle,
                );
              },
            ),
          if (isMobile)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: OutlinedButton(
                  onPressed: _isLoadingRecommendations
                      ? null
                      : _refreshRecommendations,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white70,
                  ),
                  child: _isLoadingRecommendations
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Refresh'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecommendedSongRow({
    required PlaylistItem item,
    required int index,
    required bool isMobile,
    required bool isDesktop,
    required bool isAppleStyle,
  }) {
    final song = _toGenericSong(item);
    final isAdding = _addingRecommendationTrackIDs.contains(item.id);
    final isAdded = _addedRecommendationTrackIDs.contains(item.id);
    final album = item.album;

    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final isCurrentTrack = player.currentTrack?.id == song.id;
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
            onLongPress: isDesktop ? null : () => _showSongContextMenu(song),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                mouseCursor: SystemMouseCursors.click,
                onTap: () => _playRecommendedAt(index),
                child: Container(
                  padding: isMobile
                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                      : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
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
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                    ),
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[800]),
                                  ),
                                ),
                              ),
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
                                        unawaited(
                                          _toggleRecommendedTrackPlayback(
                                            player,
                                            index,
                                          ),
                                        );
                                      },
                                      child: Icon(
                                        isCurrentTrack && player.isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrentTrack
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _buildRecommendedArtistLine(
                              item.artists,
                              isDesktop: isDesktop,
                            ),
                          ],
                        ),
                      ),
                      // On mobile we hide the album column and replace the Add button
                      if (!isMobile) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: isMobile ? 2 : 3,
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
                                  builder: (isAlbumHovering) => Text(
                                    album.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                      decoration: isAlbumHovering
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    ),
                                  ),
                                )
                              : Text(
                                  album?.title ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                      ],

                      SizedBox(
                        width: isMobile ? 44 : 74,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: isMobile
                              ? (isAdding
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : OutlinedButton(
                                        onPressed: (isAdding || isAdded)
                                            ? null
                                            : () => _addRecommendedTrack(item),
                                        style: OutlinedButton.styleFrom(
                                          shape: const CircleBorder(),
                                          side: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                          padding: const EdgeInsets.all(8),
                                          minimumSize: const Size(36, 36),
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor:
                                              Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.5),
                                          disabledForegroundColor:
                                              Colors.white70,
                                        ),
                                        child: isAdded
                                            ? const Icon(Icons.check, size: 18)
                                            : const Icon(Icons.add, size: 18),
                                      ))
                              : FilledButton(
                                  onPressed: (isAdding || isAdded)
                                      ? null
                                      : () => _addRecommendedTrack(item),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(54, 34),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    enabledMouseCursor:
                                        SystemMouseCursors.click,
                                    disabledMouseCursor:
                                        SystemMouseCursors.basic,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.35),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.18),
                                    disabledForegroundColor: Colors.white70,
                                    elevation: 0,
                                  ),
                                  child: isAdding
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(isAdded ? 'Added' : 'Add'),
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

  Widget _buildRecommendedArtistLine(
    List<GenericSimpleArtist> artists, {
    required bool isDesktop,
  }) {
    if (artists.isEmpty) {
      return Text(
        'Unknown artist',
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    if (!isDesktop) {
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
