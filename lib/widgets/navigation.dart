import 'package:flutter/material.dart';
import 'dart:io' show Platform, File;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/metadata_models.dart';
import '../models/library_folder.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/library_state.dart';
import '../services/wisp_audio_handler.dart';
import '../services/navigation_history.dart';
import 'library_item_context_menu.dart';
import 'playlist_folder_modals.dart';
import '../utils/liked_songs.dart';
import 'liked_songs_art.dart';

enum LibraryView { all, playlists, albums, artists }

enum LibrarySidebarEntryType { item, unassignedHeader }

class LibrarySidebarEntry {
  final LibrarySidebarEntryType type;
  final dynamic item;
  final String? folderId;

  const LibrarySidebarEntry.item(this.item, {this.folderId})
      : type = LibrarySidebarEntryType.item;

  const LibrarySidebarEntry.unassigned()
      : type = LibrarySidebarEntryType.unassignedHeader,
        item = null,
        folderId = null;
}

class WispNavigation extends StatefulWidget {
  final LibraryView selectedView;
  final ValueChanged<LibraryView> onViewChanged;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<dynamic> libraryItems;
  final ValueChanged<dynamic> onLibraryItemSelected;
  final double expandedWidth;
  final double collapsedWidth;

  const WispNavigation({
    super.key,
    required this.selectedView,
    required this.onViewChanged,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.libraryItems,
    required this.onLibraryItemSelected,
    this.expandedWidth = 240,
    this.collapsedWidth = 88,
  });

  @override
  State<WispNavigation> createState() => _WispNavigationState();
}

class _WispNavigationState extends State<WispNavigation> {
  bool _isCollapsed = false;
  bool _layoutCollapsed = false;

  bool _isLocalPath(String? path) {
    if (path == null || path.isEmpty) return false;
    return path.startsWith('/') || path.startsWith('file://');
  }

  bool _isDesktop() {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  @override
  Widget build(BuildContext context) {
    return _isDesktop() ? _buildDesktopSidebar() : _buildMobileBottomNav();
  }

  Widget _buildDesktopSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _isCollapsed ? widget.collapsedWidth : widget.expandedWidth,
      color: const Color(0xFF000000),
      onEnd: () {
        if (_layoutCollapsed != _isCollapsed) {
          setState(() => _layoutCollapsed = _isCollapsed);
        }
      },
      child: Column(
        crossAxisAlignment: _layoutCollapsed
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () {
                  setState(() => _isCollapsed = !_isCollapsed);
                },
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisAlignment: _layoutCollapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Image.asset('assets/wisp.png', width: 28, height: 28),
                    if (!_isCollapsed) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'wisp',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Builder(
                        builder: (buttonContext) {
                          return IconButton(
                            tooltip: 'Create',
                            icon: const Icon(Icons.add, color: Colors.white),
                            onPressed: () => _showCreateMenu(buttonContext),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Divider(color: Colors.grey[800], height: 1),

          // Library view selector
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _layoutCollapsed
                ? _buildCollapsedViewSelector()
                : _buildExpandedViewSelector(),
          ),

          // Library items list
          Expanded(
            child: ValueListenableBuilder<Route<dynamic>?>(
              valueListenable: NavigationHistory.instance.currentRoute,
              builder: (context, route, child) {
                return ListView.builder(
                  itemCount: widget.libraryItems.length,
                  itemBuilder: (context, index) {
                    final item = widget.libraryItems[index];
                    return _buildLibraryItem(item, isCollapsed: _layoutCollapsed);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateMenu(BuildContext buttonContext) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = buttonContext.findRenderObject() as RenderBox;
    final position = overlay.globalToLocal(box.localToGlobal(Offset.zero));

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned(
              left: position.dx,
              top: position.dy + box.size.height,
              child: Material(
                color: const Color(0xFF282828),
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 220,
                    maxWidth: 280,
                  ),
                  child: IntrinsicWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildCreateMenuItem(
                            dialogContext,
                            icon: Icons.create_new_folder_outlined,
                            label: 'Create folder',
                            onTap: () => PlaylistFolderModals.showCreateFolderDialog(context),
                          ),
                          _buildCreateMenuItem(
                            dialogContext,
                            icon: Icons.playlist_add,
                            label: 'Create playlist',
                            onTap: () {
                              PlaylistFolderModals.showCreatePlaylistDialog(
                                context,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCreateMenuItem(
    BuildContext dialogContext, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () {
        Navigator.of(dialogContext).pop();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey[300], size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }


  Widget _buildExpandedViewSelector() {
    final folderState = context.watch<LibraryFolderState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'YOUR LIBRARY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              if (widget.selectedView == LibraryView.playlists)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: PopupMenuButton<LibrarySortMode>(
                        tooltip: 'Sort',
                        icon: Icon(Icons.sort, color: Colors.grey[500], size: 18),
                        color: const Color(0xFF282828),
                        onSelected: folderState.setSortMode,
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: LibrarySortMode.original,
                            child: Text('Index', style: TextStyle(color: Colors.white)),
                          ),
                          PopupMenuItem(
                            value: LibrarySortMode.recentlyPlayed,
                            child: Text(
                              'Recently played',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          PopupMenuItem(
                            value: LibrarySortMode.custom,
                            child: Text(
                              'Custom order',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildViewButton(Icons.view_list, LibraryView.all),
            _buildViewButton(Icons.playlist_play, LibraryView.playlists),
            _buildViewButton(Icons.album, LibraryView.albums),
            _buildViewButton(Icons.person, LibraryView.artists),
          ],
        ),
      ],
    );
  }

  Widget _buildCollapsedViewSelector() {
    final icon = _iconForLibraryView(widget.selectedView);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF282828),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: colorScheme.primary, size: 24),
        ),
      ],
    );
  }

  IconData _iconForLibraryView(LibraryView view) {
    switch (view) {
      case LibraryView.all:
        return Icons.view_list;
      case LibraryView.playlists:
        return Icons.playlist_play;
      case LibraryView.albums:
        return Icons.album;
      case LibraryView.artists:
        return Icons.person;
    }
  }

  Widget _buildViewButton(IconData icon, LibraryView view) {
    final isSelected = widget.selectedView == view;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? Color(0xFF282828) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => widget.onViewChanged(view),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.all(8),
          child: Icon(
            icon,
            color: isSelected ? colorScheme.primary : Colors.grey[600],
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryItem(dynamic item, {required bool isCollapsed}) {
    final entry = item is LibrarySidebarEntry
        ? item
        : LibrarySidebarEntry.item(item);
    final folderState = context.watch<LibraryFolderState>();
    final libraryState = context.watch<LibraryState>();
    final isDesktop = _isDesktop();
    final allowDrag = widget.selectedView == LibraryView.playlists;
    final player = context.watch<WispAudioHandler>();

    if (entry.type == LibrarySidebarEntryType.unassignedHeader) {
      return _SidebarUnassignedHeader(
        enabled: allowDrag,
        onDrop: (playlistId) {
          folderState.movePlaylistIntoFolder(playlistId, null);
        },
      );
    }

    final resolvedItem = entry.item;
    final routeName = NavigationHistory.instance.currentRoute.value?.settings.name;
    final isCurrentRouteItem = switch (resolvedItem) {
      GenericPlaylist playlist => routeName == '/playlist/${playlist.id}',
      GenericAlbum album => routeName == '/album/${album.id}',
      GenericSimpleAlbum album => routeName == '/album/${album.id}',
      GenericSimpleArtist artist => routeName == '/artist/${artist.id}',
      _ => false,
    };
    final playbackType = player.playbackContextType;
    final playbackId = player.playbackContextID;
    final playbackName = player.playbackContextName?.trim();
    final isCurrentPlaybackItem = switch (resolvedItem) {
      GenericPlaylist playlist =>
        playbackType == 'playlist' &&
        (playbackId == playlist.id || playbackName == playlist.title.trim()),
      GenericAlbum album =>
        playbackType == 'album' &&
        (playbackId == album.id || playbackName == album.title.trim()),
      GenericSimpleAlbum album =>
        playbackType == 'album' &&
        (playbackId == album.id || playbackName == album.title.trim()),
      GenericSimpleArtist artist =>
        (playbackType == 'artist' &&
          (playbackId == artist.id || playbackName == artist.name.trim())) ||
        (player.currentTrack?.artists.any((a) => a.id == artist.id) ?? false),
      _ => false,
    };
    final titleColor = isCurrentPlaybackItem
        ? Theme.of(context).colorScheme.primary
        : Colors.white;
    String? imageUrl;
    String? filePath;
    String title = '';
    String? subtitle;

    final isLiked = resolvedItem is GenericPlaylist &&
        isLikedSongsPlaylistId(resolvedItem.id);

    if (resolvedItem is PlaylistFolder) {
      filePath = resolvedItem.thumbnailPath;
      title = resolvedItem.title;
      final count = libraryState.playlists
          .where((p) => folderState.folderIdForPlaylist(p.id) == resolvedItem.id)
          .length;
      subtitle = '$count playlist${count == 1 ? '' : 's'}';
    } else if (resolvedItem is GenericPlaylist) {
      imageUrl = resolvedItem.thumbnailUrl;
      title = resolvedItem.title;
      subtitle = resolvedItem.author.displayName;
    } else if (resolvedItem is GenericAlbum) {
      imageUrl = resolvedItem.thumbnailUrl;
      title = resolvedItem.title;
      subtitle = resolvedItem.artists.map((a) => a.name).join(', ');
    } else if (resolvedItem is GenericSimpleArtist) {
      imageUrl = resolvedItem.thumbnailUrl;
      title = resolvedItem.name;
      subtitle = 'Artist';
    } else {
      try {
        final dynamic obj = resolvedItem;
        if (obj.thumbnailUrl != null) {
          imageUrl = obj.thumbnailUrl as String;
        }
        if (obj.title != null) {
          title = obj.title as String;
        } else if (obj.name != null) {
          title = obj.name as String;
        }
      } catch (e) {
        title = 'Unknown';
      }
    }

    Widget tile = Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onSecondaryTapDown: (details) {
          LibraryItemContextMenu.show(
            context: context,
            item: resolvedItem,
            position: details.globalPosition,
            playlists: _extractItems<GenericPlaylist>(),
            albums: _extractItems<GenericAlbum>(),
            artists: _extractItems<GenericSimpleArtist>(),
            currentLibraryView: widget.selectedView,
            currentNavIndex: widget.selectedIndex,
          );
        },
        onTap: () {
          if (resolvedItem is PlaylistFolder) {
            folderState.toggleFolderCollapsed(resolvedItem.id);
            return;
          }
          widget.onLibraryItemSelected(resolvedItem);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isCurrentRouteItem
                ? const Color(0xFF282828)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCollapsed ? 8 : 12,
            vertical: 8,
          ).add(
            EdgeInsets.only(left: entry.folderId != null ? 12 : 0),
          ),
          child: Row(
            mainAxisAlignment:
                isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey[900],
                  child: filePath != null
                      ? Image.file(
                          File(filePath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, url, error) => Icon(
                            Icons.folder,
                            color: Colors.grey[700],
                          ),
                        )
                      : (isLiked
                          ? const LikedSongsArt()
                          : (imageUrl != null
                              ? (_isLocalPath(imageUrl)
                                  ? Image.file(
                                      File(imageUrl.replaceFirst('file://', '')),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, url, error) => Icon(
                                        Icons.music_note,
                                        color: Colors.grey[700],
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) {
                                        return Icon(
                                          Icons.music_note,
                                          color: Colors.grey[700],
                                        );
                                      },
                                      placeholder: (context, url) =>
                                          Container(color: Colors.grey[800]),
                                    ))
                              : Icon(Icons.music_note, color: Colors.grey[700]))),
                ),
              ),
              if (!isCollapsed) ...[
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 14,
                          fontWeight: resolvedItem is PlaylistFolder
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (resolvedItem is PlaylistFolder)
                  Icon(
                    folderState.isFolderCollapsed(resolvedItem.id)
                        ? Icons.chevron_right
                        : Icons.expand_more,
                    color: Colors.grey[500],
                    size: 20,
                  )
                /* else if (!isCollapsed &&
                    allowDrag &&
                    !isLiked &&
                    (resolvedItem is GenericPlaylist))
                  Icon(Icons.drag_handle, color: Colors.grey[600], size: 18), */
              ],
            ],
          ),
        ),
      ),
    );

    void ensureCustomSort() {
      if (!folderState.isCustomSort) {
        folderState.setSortMode(LibrarySortMode.custom);
      }
    }

    if (allowDrag && resolvedItem is PlaylistFolder) {
      final draggable = isDesktop
          ? Draggable<_SidebarFolderDragData>(
              data: _SidebarFolderDragData(resolvedItem.id),
              feedback: _SidebarDragFeedback(
                title: resolvedItem.title,
                icon: Icons.folder,
              ),
              childWhenDragging: Opacity(opacity: 0.4, child: tile),
              onDragStarted: ensureCustomSort,
              child: tile,
            )
          : LongPressDraggable<_SidebarFolderDragData>(
              delay: const Duration(milliseconds: 150),
              data: _SidebarFolderDragData(resolvedItem.id),
              feedback: _SidebarDragFeedback(
                title: resolvedItem.title,
                icon: Icons.folder,
              ),
              childWhenDragging: Opacity(opacity: 0.4, child: tile),
              onDragStarted: ensureCustomSort,
              child: tile,
            );
      final reorderTarget = DragTarget<_SidebarFolderDragData>(
        onWillAccept: (data) => data != null && data.folderId != resolvedItem.id,
        onAccept: (data) => folderState.moveFolderBefore(data.folderId, resolvedItem.id),
        builder: (context, candidate, rejected) => Container(
          decoration: candidate.isNotEmpty
              ? BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: draggable,
        ),
      );
      final playlistDropTarget = DragTarget<_SidebarPlaylistDragData>(
        onWillAccept: (data) => data != null,
        onAccept: (data) =>
            folderState.movePlaylistIntoFolder(data.playlistId, resolvedItem.id),
        builder: (context, candidate, rejected) => Container(
          decoration: candidate.isNotEmpty
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                )
              : null,
          child: reorderTarget,
        ),
      );
      tile = playlistDropTarget;
    }

    if (allowDrag && resolvedItem is GenericPlaylist && !isLiked) {
      final draggable = isDesktop
          ? Draggable<_SidebarPlaylistDragData>(
              data: _SidebarPlaylistDragData(resolvedItem.id, entry.folderId),
              feedback: _SidebarDragFeedback(
                title: resolvedItem.title,
                icon: Icons.playlist_play,
              ),
              childWhenDragging: Opacity(opacity: 0.4, child: tile),
              onDragStarted: ensureCustomSort,
              child: tile,
            )
          : LongPressDraggable<_SidebarPlaylistDragData>(
              delay: const Duration(milliseconds: 150),
              data: _SidebarPlaylistDragData(resolvedItem.id, entry.folderId),
              feedback: _SidebarDragFeedback(
                title: resolvedItem.title,
                icon: Icons.playlist_play,
              ),
              childWhenDragging: Opacity(opacity: 0.4, child: tile),
              onDragStarted: ensureCustomSort,
              child: tile,
            );
      final reorderTarget = DragTarget<_SidebarPlaylistDragData>(
        onWillAccept: (data) => data != null && data.playlistId != resolvedItem.id,
        onAccept: (data) {
          folderState.assignPlaylistToFolder(data.playlistId, entry.folderId);
          folderState.movePlaylistBefore(data.playlistId, resolvedItem.id);
        },
        builder: (context, candidate, rejected) => Container(
          decoration: candidate.isNotEmpty
              ? BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: draggable,
        ),
      );
      final folderDropTarget = DragTarget<_SidebarFolderDragData>(
        onWillAccept: (data) => data != null,
        onAccept: (data) =>
            folderState.moveFolderBeforePlaylist(data.folderId, resolvedItem.id),
        builder: (context, candidate, rejected) => Container(
          decoration: candidate.isNotEmpty
              ? BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: reorderTarget,
        ),
      );
      tile = folderDropTarget;
    }

    return tile;
  }

  Widget _buildMobileBottomNav() {
    final colorScheme = Theme.of(context).colorScheme;
    final destinations = [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home, color: colorScheme.primary),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search, color: colorScheme.primary),
        label: 'Search',
      ),
      NavigationDestination(
        icon: Icon(Icons.library_music_outlined),
        selectedIcon: Icon(Icons.library_music, color: colorScheme.primary),
        label: 'Library',
      ),
    ];
    final safeIndex = widget.selectedIndex.clamp(0, destinations.length - 1);
    return MediaQuery(
      data: MediaQuery.of(context).removePadding(removeTop: true),
      child: NavigationBar(
        maintainBottomViewPadding: true,
        selectedIndex: safeIndex,
        onDestinationSelected: widget.onDestinationSelected,
        backgroundColor: Colors.black,
        indicatorColor: colorScheme.primary.withOpacity(0.2),
        destinations: destinations,
        height: 56,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelPadding: EdgeInsets.all(0),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600
          ),
        ),
      ),
    );
  }

  List<T> _extractItems<T>() {
    return widget.libraryItems
        .map((item) => item is LibrarySidebarEntry ? item.item : item)
        .whereType<T>()
        .toList();
  }
}

class _SidebarPlaylistDragData {
  final String playlistId;
  final String? folderId;

  const _SidebarPlaylistDragData(this.playlistId, this.folderId);
}

class _SidebarFolderDragData {
  final String folderId;

  const _SidebarFolderDragData(this.folderId);
}

class _SidebarDragFeedback extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SidebarDragFeedback({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarUnassignedHeader extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onDrop;

  const _SidebarUnassignedHeader({required this.enabled, required this.onDrop});

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.only(left: 12, top: 12, bottom: 6),
      child: Text(
        'Unassigned',
        style: TextStyle(color: Colors.grey[500], fontSize: 11),
      ),
    );

    if (!enabled) return child;

    return DragTarget<_SidebarPlaylistDragData>(
      onWillAccept: (data) => data != null,
      onAccept: (data) => onDrop(data.playlistId),
      builder: (context, candidate, rejected) {
        return Container(
          decoration: candidate.isNotEmpty
              ? BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: child,
        );
      },
    );
  }
}
