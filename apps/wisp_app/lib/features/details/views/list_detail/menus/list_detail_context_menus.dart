// Copyright © 2026 wizeshi

part of '../../list_detail_view.dart';

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
  }) => EntityContextMenus.showTrackMenu(
    context,
    track: song,
    globalPosition: globalPosition,
    anchorRect: _anchorRectFromContext(anchorContext),
  );

  void _showShareDialog() {
    final effectiveSource =
        _playlist?.source ?? _album?.source ?? 'spotify';
    final typePath = widget.type == SharedListType.playlist
        ? 'playlist'
        : 'album';
    EntityContextMenus.copyShareUrl(
      context,
      source: effectiveSource,
      type: typePath,
      id: widget.id,
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

