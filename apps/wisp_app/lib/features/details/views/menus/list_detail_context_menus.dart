// Copyright © 2026 wizeshi

part of '../list_detail_view.dart';

extension _ListDetailContextMenus on _SharedListDetailViewState {
  Rect? _anchorRectFromContext(BuildContext? anchorContext) {
    if (anchorContext == null) return null;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox;
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
  }

  Future<void> _showPlaylistDeletePlaceholder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete playlist?'),
          content: const Text(
            'Delete confirmation is still a placeholder for now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Delete playlist placeholder')),
    );
  }

  Future<void> _showListContextMenu({
    BuildContext? anchorContext,
    Offset? globalPosition,
  }) async {
    final actions = _buildListContextActions();
    if (actions.isEmpty) return;
    await showAdaptiveContextMenu(
      context: context,
      actions: actions,
      anchorRect: _anchorRectFromContext(anchorContext),
      globalPosition: globalPosition,
    );
  }

  List<ContextMenuAction> _buildListContextActions() {
    final listSongs = _buildQueueSongs();
    final title = widget.type == SharedListType.playlist
        ? (_playlist?.title ?? 'Playlist')
        : (_album?.title ?? 'Album');
    final source = widget.type == SharedListType.playlist
        ? _playlist?.source
        : _album?.source;

    final downloadSubmenu = [
      ContextMenuAction(
        id: 'download-metadata',
        label: 'Download Metadata',
        icon: Icons.description_outlined,
        onSelected: (_) async {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download metadata placeholder')),
          );
        },
      ),
      ContextMenuAction(
        id: 'download-cache',
        label: 'Download Audio',
        icon: Icons.download_outlined,
        onSelected: (_) => _downloadAll(),
      ),
    ];

    if (widget.type == SharedListType.playlist) {
      final folderState = context.read<LibraryFolderState>();
      final folders = folderState.folders;
      final currentFolderId = folderState.folderIdForPlaylist(widget.id);

      final moveToFolderChildren = <ContextMenuAction>[
        ContextMenuAction(
          id: 'move-no-folder',
          label: currentFolderId == null ? '✓ No Folder' : 'No Folder',
          icon: Icons.folder_off_outlined,
          onSelected: (_) =>
              folderState.movePlaylistIntoFolder(widget.id, null),
        ),
        for (final folder in folders)
          ContextMenuAction(
            id: 'move-folder-${folder.id}',
            label: currentFolderId == folder.id
                ? '✓ ${folder.title}'
                : folder.title,
            icon: Icons.folder,
            onSelected: (_) =>
                folderState.movePlaylistIntoFolder(widget.id, folder.id),
          ),
      ];

      return [
        ContextMenuAction(
          id: 'add-queue',
          label: 'Add to Queue',
          icon: Icons.queue_music,
          onSelected: (_) => _appendTracksToQueue(
            listSongs,
            contextType: 'playlist',
            contextName: title,
            contextSource: source,
          ),
        ),
        ContextMenuAction(
          id: 'add-tastes',
          label: 'Add to Tastes',
          icon: Icons.auto_awesome,
          onSelected: (_) async {
            final tracks = listSongs.isNotEmpty ? listSongs : _buildQueueSongs();
            if (tracks.isEmpty) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No tracks available in playlist')),
              );
              return;
            }
            await ListeningHabitsService.instance.enqueueTasteIngestion(
              tracks,
              sourceTitle: title,
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Adding ${tracks.length} songs to your tastes in the background...',
                ),
              ),
            );
          },
        ),
        ContextMenuAction(
          id: 'edit-details',
          label: 'Edit Details',
          icon: Icons.edit,
          onSelected: (_) async => _showEditDialog(),
        ),
        ContextMenuAction(
          id: 'delete',
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: (_) => _showPlaylistDeletePlaceholder(),
        ),
        ContextMenuAction(
          id: 'download',
          label: 'Download',
          icon: Icons.download,
          children: downloadSubmenu,
        ),
        ContextMenuAction(
          id: 'move-folder',
          label: 'Move to Folder',
          icon: Icons.folder_open,
          children: moveToFolderChildren,
        ),
        ContextMenuAction(
          id: 'share',
          label: 'Share',
          icon: Icons.share,
          onSelected: (_) async => _showShareDialog(),
        ),
      ];
    }

    final album = _album;
    final libraryState = context.read<LibraryState>();
    final isSaved = album != null && libraryState.isAlbumSaved(album.id);
    return [
      ContextMenuAction(
        id: 'toggle-library',
        label: isSaved ? 'Remove from Library' : 'Add to Library',
        icon: isSaved ? Icons.bookmark_remove : Icons.bookmark_add,
        iconColor: isSaved ? Theme.of(context).colorScheme.primary : null,
        onSelected: (_) => _toggleSaveAlbum(isSaved),
      ),
      ContextMenuAction(
        id: 'add-queue',
        label: 'Add to Queue',
        icon: Icons.queue_music,
        onSelected: (_) => _appendTracksToQueue(
          listSongs,
          contextType: 'album',
          contextName: title,
          contextSource: source,
        ),
      ),
      ContextMenuAction(
        id: 'add-tastes',
        label: 'Add to Tastes',
        icon: Icons.auto_awesome,
        onSelected: (_) async {
          final tracks = listSongs.isNotEmpty ? listSongs : _buildQueueSongs();
          if (tracks.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No tracks available in album')),
            );
            return;
          }
          await ListeningHabitsService.instance.enqueueTasteIngestion(
            tracks,
            sourceTitle: title,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Adding ${tracks.length} songs to your tastes in the background...',
              ),
            ),
          );
        },
      ),
      ContextMenuAction(
        id: 'download',
        label: 'Download',
        icon: Icons.download,
        children: downloadSubmenu,
      ),
      ContextMenuAction(
        id: 'share',
        label: 'Share',
        icon: Icons.share,
        onSelected: (_) async => _showShareDialog(),
      ),
    ];
  }

  Future<void> _showSongContextMenu(
    GenericSong song, {
    Offset? globalPosition,
    BuildContext? anchorContext,
  }) async {
    unawaited(_spotifyInternal.ensureLikedTracksLoaded());

    final hasLikedTracksState = _spotifyInternal.hasLoadedLikedTracks;
    final isLiked =
        hasLikedTracksState && _spotifyInternal.isTrackLiked(song.id);
    final cacheManager = AudioCacheManager.instance;
    final isCached = cacheManager.isTrackCached(song.id);
    final isDownloading = cacheManager.isDownloading(song.id);
    final progress = cacheManager.getDownloadProgress(song.id) ?? 0;
    final hasAlbum = song.album != null && song.album!.id.isNotEmpty;
    final hasOneArtist = song.artists.length == 1;

    final cacheLabel = isDownloading
        ? 'Downloading ${(progress * 100).toStringAsFixed(0)}%'
        : (isCached ? 'Remove from Audio Cache' : 'Add to Audio Cache');

    final actions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'likes-toggle',
        label: hasLikedTracksState
            ? (isLiked ? 'Remove from Likes' : 'Add to Likes')
            : 'Like / Unlike',
        icon: hasLikedTracksState && isLiked
            ? Icons.favorite
            : Icons.favorite_border,
        iconColor: isLiked ? Theme.of(context).colorScheme.primary : null,
        onSelected: (_) => _spotifyInternal.toggleTrackLike(song),
      ),
      ContextMenuAction(
        id: 'playlist-add',
        label: 'Add to Playlist',
        icon: Icons.playlist_add,
        onSelected: (_) async {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add to playlist placeholder')),
          );
        },
      ),
      ContextMenuAction(
        id: 'cache-toggle',
        label: cacheLabel,
        icon: isCached ? Icons.delete_outline : Icons.download_outlined,
        iconColor: isCached ? Theme.of(context).colorScheme.primary : null,
        enabled: !isDownloading,
        onSelected: (_) async {
          if (isCached) {
            await cacheManager.removeFromCache(song.id);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Removed from audio cache')),
            );
            return;
          }

          final player = context.read<global_audio_player.WispAudioHandler>();
          final result = await player.downloadTrack(song);
          if (!mounted) return;
          final message = switch (result) {
            QueueDownloadResult.queued => 'Queued track for download',
            QueueDownloadResult.alreadyCached => 'Track already cached',
            QueueDownloadResult.alreadyQueued =>
              'Track already in download queue',
            QueueDownloadResult.blockedByNetworkPolicy =>
              'Downloads blocked by your WiFi/Ethernet-only setting',
            QueueDownloadResult.blockedByNetworkOnlyMode =>
              'Downloads blocked because Network-only mode is enabled',
          };
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        },
      ),
      ContextMenuAction(
        id: 'youtube-alt',
        label: 'Search Alternatives',
        icon: Icons.ondemand_video,
        onSelected: (_) async {
          final player = context.read<global_audio_player.WispAudioHandler>();
          final previousVideoId = YouTubeProvider.getCachedVideoId(song.id);
          final selectedVideoId = await AppNavigation.instance
              .openYouTubeAlternatives(song);
          if (!mounted || selectedVideoId == null) return;

          final hasChanged = selectedVideoId.isEmpty
              ? previousVideoId != null
              : previousVideoId != selectedVideoId;

          if (selectedVideoId.isEmpty) {
            await YouTubeProvider.removeCachedVideoId(song.id);
            if (hasChanged) {
              await player.onYouTubeAlternativeUpdated(
                song.id,
                previousVideoId: previousVideoId,
              );
            }
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('YouTube mapping cleared')),
            );
            return;
          }
          await YouTubeProvider.setCachedVideoId(song.id, selectedVideoId);
          if (hasChanged) {
            await player.onYouTubeAlternativeUpdated(
              song.id,
              previousVideoId: previousVideoId,
            );
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('YouTube alternative saved')),
          );
        },
      ),
      ContextMenuAction(
        id: 'share',
        label: 'Share',
        icon: Icons.share,
        onSelected: (_) async {
          await EntityContextMenus.copySpotifyShareUrl(
            context,
            source: song.source,
            type: 'track',
            id: song.id,
          );
        },
      ),
      if (hasAlbum)
        ContextMenuAction(
          id: 'go-album',
          label: 'Go to Album',
          icon: Icons.album,
          onSelected: (_) async {
            final album = song.album!;
            _openSharedList(
              SharedListType.album,
              album.id,
              title: album.title,
              thumbnailUrl: album.thumbnailUrl,
            );
          },
        ),
      if (hasOneArtist)
        ContextMenuAction(
          id: 'go-artist',
          label: 'Go to Artist',
          icon: Icons.person,
          onSelected: (_) async => _openArtist(song.artists.first),
        )
      else
        ContextMenuAction(
          id: 'artists-submenu',
          label: 'Artists',
          icon: Icons.groups,
          children: [
            for (final artist in song.artists)
              ContextMenuAction(
                id: 'artist-${artist.id}',
                label: artist.name,
                icon: Icons.person_outline,
                onSelected: (_) async => _openArtist(artist),
              ),
          ],
        ),
    ];

    await showAdaptiveContextMenu(
      context: context,
      actions: actions,
      anchorRect: _anchorRectFromContext(anchorContext),
      globalPosition: globalPosition,
      mobileHeaderBuilder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: CachedNetworkImage(
                    imageUrl: song.thumbnailUrl,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[900],
                      child: Icon(Icons.music_note, color: Colors.grey[600]),
                    ),
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[850]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artists.map((artist) => artist.name).join(', '),
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(_sourceIcon(song.source), color: Colors.grey[300]),
            ],
          ),
        );
      },
    );
  }

  void _showShareDialog() {
    final isSpotify =
        _playlist?.source == SongSource.spotify ||
        _playlist?.source == SongSource.spotifyInternal ||
        _album?.source == SongSource.spotify ||
        _album?.source == SongSource.spotifyInternal ||
        widget.id.startsWith('spotify:');

    if (isSpotify) {
      final typePath = widget.type == SharedListType.playlist
          ? 'playlist'
          : 'album';
      final id = widget.id.split(':').last;
      final url = 'https://open.spotify.com/$typePath/$id';

      Clipboard.setData(ClipboardData(text: url)).then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link copied to clipboard')),
          );
        }
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share not implemented for this source yet'),
      ),
    );
  }

  void _showEditDialog() {
    if (widget.type == SharedListType.playlist && _playlist != null) {
      PlaylistFolderModals.showRenamePlaylistDialog(context, _playlist!);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit not available for this item')),
    );
  }
}

