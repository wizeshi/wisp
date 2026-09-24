// Copyright © 2026 wizeshi

import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:wisp/shared/widgets/rows/album_row.dart';
import 'package:wisp/shared/widgets/rows/artist_row.dart';
import 'package:wisp/shared/widgets/rows/folder_row.dart';
import 'package:wisp/shared/widgets/rows/generic_row.dart';
import 'package:wisp/shared/widgets/rows/playlist_row.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/models/library_folder.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/features/shell/navigation/navigation_history.dart';
import 'package:wisp/shared/widgets/menus/playlist_folder_modals.dart';
import 'package:wisp/core/utils/liked_songs.dart';

enum LibraryView { all, playlists, albums, artists }

enum LibrarySidebarEntryType { item, unassignedHeader }

typedef _SidebarPlaybackHighlight = ({
  bool isPlaying,
  PlaybackContextType? contextType,
  String? contextId,
  String? contextName,
  String currentArtistIds,
});

Widget widgetForThumbnail(Widget child, bool isArtist) {
  if (isArtist) {
    return ClipOval(child: child);
  }
  return ClipRRect(borderRadius: BorderRadius.circular(4), child: child);
}

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
    this.libraryItems = const [],
    required this.onLibraryItemSelected,
    this.expandedWidth = 240,
    this.collapsedWidth = 88,
  });

  @override
  State<WispNavigation> createState() => _WispNavigationState();
}

class _WispNavigationState extends State<WispNavigation> {
  bool _isCollapsed = false;
  bool _isHoveringHeader = false;
  bool _layoutCollapsed = false;

  bool _isDesktop() {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  String _itemTitle(dynamic item) {
    if (item is PlaylistFolder) return item.title;
    if (item is GenericPlaylist) return item.title;
    if (item is GenericAlbum || item is GenericSimpleAlbum) {
      try {
        return (item as dynamic).title as String? ?? '';
      } catch (_) {
        return '';
      }
    }
    if (item is GenericSimpleArtist || item is GenericArtist) {
      try {
        return (item as dynamic).name as String? ?? '';
      } catch (_) {
        return '';
      }
    }
    return '';
  }

  String? _itemId(dynamic item) {
    if (item is PlaylistFolder) return item.id;
    if (item is GenericPlaylist) return item.id;
    try {
      return (item as dynamic).id as String?;
    } catch (_) {
      return null;
    }
  }

  GenericAlbum? _libraryAlbumById(LibraryState library, String id) {
    for (final album in library.albums) {
      if (album.id == id) return album;
    }
    return null;
  }

  dynamic _resolveLibraryAlbum(LibraryState library, dynamic raw) {
    final id = _itemId(raw);
    if (id == null) return raw;
    return _libraryAlbumById(library, id) ?? raw;
  }

  List<dynamic> _computeLibraryItems(
    LibraryState library,
    LibraryFolderState folderState,
    LibraryView view,
  ) {
    switch (view) {
      case LibraryView.playlists:
        GenericPlaylist? likedPlaylist;
        for (final playlist in library.playlists) {
          if (isLikedSongsPlaylistId(playlist.id)) {
            likedPlaylist = playlist;
            break;
          }
        }
        final filteredPlaylists = library.playlists
            .where((p) => !isLikedSongsPlaylistId(p.id))
            .toList();
        final groups = folderState.buildPlaylistGroups(filteredPlaylists);
        final entries = <LibrarySidebarEntry>[];
        if (likedPlaylist != null) {
          entries.add(LibrarySidebarEntry.item(likedPlaylist));
        }
        for (final group in groups.folders) {
          entries.add(LibrarySidebarEntry.item(group.folder));
          if (!folderState.isFolderCollapsed(group.folder.id)) {
            for (final playlist in group.playlists) {
              entries.add(
                LibrarySidebarEntry.item(playlist, folderId: group.folder.id),
              );
            }
          }
        }
        if (groups.folders.isNotEmpty) {
          entries.add(const LibrarySidebarEntry.unassigned());
        }
        for (final playlist in groups.unassigned) {
          entries.add(LibrarySidebarEntry.item(playlist, folderId: null));
        }
        return entries;
      case LibraryView.albums:
        return library.albums;
      case LibraryView.artists:
        return library.artists;
      case LibraryView.all:
        GenericPlaylist? likedPlaylist;
        final folderMap = <String, PlaylistFolder>{
          for (final f in folderState.folders) f.id: f,
        };
        final topLevelItems = <dynamic>[];
        final folderPlaylists = <String, List<GenericPlaylist>>{};
        final seenPlaylistIds = <String>{};
        final seenTopLevelIds = <String>{};

        void processItem(dynamic raw) {
          if (raw == null) return;
          if (raw is LibrarySidebarEntry) {
            if (raw.type == LibrarySidebarEntryType.unassignedHeader) return;
            processItem(raw.item);
            return;
          }

          if (raw is PlaylistFolder) {
            folderMap[raw.id] = raw;
            if (seenTopLevelIds.add(raw.id)) {
              topLevelItems.add(raw);
            }
            return;
          }

          if (raw is GenericPlaylist) {
            if (isLikedSongsPlaylistId(raw.id)) {
              likedPlaylist ??= raw;
              return;
            }
            if (!seenPlaylistIds.add(raw.id)) return;

            final folderId = folderState.folderIdForPlaylist(raw.id);
            if (folderId != null && folderMap.containsKey(folderId)) {
              folderPlaylists.putIfAbsent(folderId, () => []).add(raw);
            } else {
              if (seenTopLevelIds.add(raw.id)) {
                topLevelItems.add(raw);
              }
            }
            return;
          }

          if (raw is GenericAlbum || raw is GenericSimpleAlbum) {
            final id = _itemId(raw);
            if (id != null && seenTopLevelIds.add(id)) {
              topLevelItems.add(_resolveLibraryAlbum(library, raw));
            }
            return;
          }

          if (raw is GenericSimpleArtist || raw is GenericArtist) {
            final id = _itemId(raw);
            if (id != null && seenTopLevelIds.add(id)) {
              topLevelItems.add(raw);
            }
            return;
          }

          if (raw is Map<String, dynamic>) {
            final t = raw['__typename'] as String? ?? raw['type'] as String?;
            final uri = raw['uri'] as String? ?? raw['id'] as String? ?? '';
            final id = uri.isNotEmpty ? uri : (raw['id'] as String? ?? '');

            if (t == 'Folder' || t == 'folder') {
              final folder =
                  folderState.getFolderById(id) ??
                  PlaylistFolder(
                    id: id,
                    title: raw['name'] as String? ?? 'Folder',
                    createdAt: DateTime.now(),
                  );
              folderMap[folder.id] = folder;
              if (seenTopLevelIds.add(folder.id)) {
                topLevelItems.add(folder);
              }
              return;
            }

            if (t == 'Playlist' ||
                t == 'playlist' ||
                uri.contains('playlist')) {
              final p = GenericPlaylist(
                id: id,
                source: SongSource.spotifyInternal,
                title: raw['name'] as String? ?? '',
                thumbnailUrl: raw['image']?['url'] as String? ?? '',
                author: GenericSimpleUser(
                  id: '',
                  source: SongSource.spotifyInternal,
                  displayName: '',
                  avatarUrl: null,
                  followerCount: null,
                  profileUrl: null,
                ),
                songs: null,
                durationSecs: 0,
              );
              processItem(p);
              return;
            }

            if (t == 'Album' || t == 'album' || uri.contains('album')) {
              final album = GenericSimpleAlbum(
                id: id,
                source: SongSource.spotifyInternal,
                title: raw['name'] as String? ?? '',
                artists: const [],
                thumbnailUrl: raw['image']?['url'] as String? ?? '',
                label: '',
                releaseDate: DateTime.now(),
              );
              processItem(_resolveLibraryAlbum(library, album));
              return;
            }

            if (t == 'Artist' || t == 'artist' || uri.contains('artist')) {
              final artist = GenericSimpleArtist(
                id: id,
                source: SongSource.spotifyInternal,
                name: raw['name'] as String? ?? '',
                thumbnailUrl: raw['image']?['url'] as String? ?? '',
              );
              processItem(artist);
              return;
            }
          }
        }

        final allOrganized = library.allOrganized;
        if (allOrganized != null) {
          for (final item in allOrganized) {
            processItem(item);
          }
        }

        for (final folder in folderState.folders) {
          processItem(folder);
        }

        for (final playlist in library.playlists) {
          processItem(playlist);
        }

        for (final album in library.albums) {
          processItem(album);
        }

        for (final artist in library.artists) {
          processItem(artist);
        }

        DateTime? itemLastPlayed(dynamic item) {
          if (item is PlaylistFolder) {
            final children = folderPlaylists[item.id];
            if (children == null || children.isEmpty) return null;
            DateTime? latest;
            for (final child in children) {
              final t = folderState.lastPlayedForItem(child.id);
              if (t != null && (latest == null || t.isAfter(latest))) {
                latest = t;
              }
            }
            return latest;
          }
          final id = _itemId(item);
          return id != null ? folderState.lastPlayedForItem(id) : null;
        }

        switch (folderState.sortMode) {
          case LibrarySortMode.recent:
            topLevelItems.sort((a, b) {
              final aTime = itemLastPlayed(a);
              final bTime = itemLastPlayed(b);
              if (aTime != null && bTime != null) {
                return bTime.compareTo(aTime);
              }
              if (aTime != null) return -1;
              if (bTime != null) return 1;
              return 0;
            });
            for (final entry in folderPlaylists.entries) {
              entry.value.sort((a, b) {
                final aTime = folderState.lastPlayedForItem(a.id);
                final bTime = folderState.lastPlayedForItem(b.id);
                if (aTime != null && bTime != null) {
                  return bTime.compareTo(aTime);
                }
                if (aTime != null) return -1;
                if (bTime != null) return 1;
                return 0;
              });
            }
            break;
          case LibrarySortMode.recentlyAdded:
            // Preserve addition order (folders by createdAt descending, items as loaded)
            for (final entry in folderPlaylists.entries) {
              entry.value.sort((a, b) => 0);
            }
            break;
          case LibrarySortMode.alphabetical:
            topLevelItems.sort((a, b) {
              return _itemTitle(
                a,
              ).toLowerCase().compareTo(_itemTitle(b).toLowerCase());
            });
            for (final entry in folderPlaylists.entries) {
              entry.value.sort((a, b) {
                return a.title.toLowerCase().compareTo(b.title.toLowerCase());
              });
            }
            break;
        }

        final allEntries = <LibrarySidebarEntry>[];
        if (likedPlaylist != null) {
          allEntries.add(LibrarySidebarEntry.item(likedPlaylist));
        }

        for (final item in topLevelItems) {
          if (item is PlaylistFolder) {
            allEntries.add(LibrarySidebarEntry.item(item));
            if (!folderState.isFolderCollapsed(item.id)) {
              final children = folderPlaylists[item.id] ?? const [];
              for (final child in children) {
                allEntries.add(
                  LibrarySidebarEntry.item(child, folderId: item.id),
                );
              }
            }
          } else if (item is GenericPlaylist) {
            allEntries.add(LibrarySidebarEntry.item(item, folderId: null));
          } else {
            allEntries.add(LibrarySidebarEntry.item(item));
          }
        }

        return allEntries;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isDesktop() ? _buildDesktopSidebar() : _buildMobileBottomNav();
  }

  Widget _buildDesktopSidebar() {
    final libraryState = context.watch<LibraryState>();
    final folderState = context.watch<LibraryFolderState>();
    final libraryItems = _computeLibraryItems(
      libraryState,
      folderState,
      LibraryView.all,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _isCollapsed ? widget.collapsedWidth : widget.expandedWidth,
      color: Colors.grey[900]?.withValues(alpha: 0.3),
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
          // Library view selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
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
                  itemCount: libraryItems.length,
                  itemBuilder: (context, index) {
                    final item = libraryItems[index];
                    return _SidebarLibraryItem(
                      builder: (folderState, libraryState, playback) =>
                          _buildLibraryItem(
                            item,
                            isCollapsed: _layoutCollapsed,
                            folderState: folderState,
                            libraryState: libraryState,
                            playback: playback,
                          ),
                    );
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Stack(
            children: [
              Positioned(
                left: position.dx,
                top: position.dy + box.size.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {},
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
                                onTap: () =>
                                    PlaylistFolderModals.showCreateFolderDialog(
                                      context,
                                    ),
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
              ),
            ],
          ),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHoveringHeader = true),
                onExit: (_) => setState(() => _isHoveringHeader = false),
                child: Row(
                  spacing: 4,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 85),
                      curve: Curves.easeOut,
                      width: _isHoveringHeader ? 24 : 0,
                      child: ClipRect(
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 100),
                          curve: Curves.easeIn,
                          offset: Offset.zero,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 100),
                            opacity: _isHoveringHeader ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !_isHoveringHeader,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minHeight: 24,
                                  minWidth: 24,
                                  maxHeight: 24,
                                  maxWidth: 24,
                                ),
                                tooltip: 'Collapse Sidebar',
                                icon: Icon(
                                  Symbols.left_panel_close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () => {
                                  setState(() => _isCollapsed = !_isCollapsed),
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      'Your Library',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SizedBox(
                height: 24,
                width: 24,
                child: PopupMenuButton<LibrarySortMode>(
                  padding: EdgeInsets.zero,
                  tooltip: 'Sort',
                  color: const Color(0xFF282828),
                  onSelected: (mode) {
                    folderState.setSortMode(mode);
                    context
                        .read<SpotifyInternalProvider>()
                        .fetchUserLibrarySorted(sortMode: mode);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.comfortable,
                  ),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: LibrarySortMode.recent,
                      child: Text(
                        'Recent',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    PopupMenuItem(
                      value: LibrarySortMode.recentlyAdded,
                      child: Text(
                        'Recently added',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    PopupMenuItem(
                      value: LibrarySortMode.alphabetical,
                      child: Text(
                        'Alphabetical',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                  icon: Icon(Icons.sort, color: Colors.grey[500], size: 16),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Builder(
              builder: (buttonContext) {
                return FilledButton.icon(
                  label: Text(
                    "Create",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black38,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  icon: Icon(Icons.add, color: Colors.white, size: 20),
                  onPressed: () => _showCreateMenu(buttonContext),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCollapsedViewSelector() {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringHeader = true),
      onExit: (_) => setState(() => _isHoveringHeader = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _isHoveringHeader
              ? IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minHeight: 32,
                    minWidth: 32,
                    maxHeight: 32,
                    maxWidth: 32,
                  ),
                  tooltip: 'Expand Sidebar',
                  icon: Icon(
                    Symbols.left_panel_open,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
                )
              : Container(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minHeight: 32,
                    minWidth: 32,
                    maxHeight: 32,
                    maxWidth: 32,
                  ),
                  child: Icon(
                    Symbols.library_music,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildLibraryItem(
    dynamic item, {
    required bool isCollapsed,
    required LibraryFolderState folderState,
    required LibraryState libraryState,
    required _SidebarPlaybackHighlight playback,
  }) {
    final entry = item is LibrarySidebarEntry
        ? item
        : LibrarySidebarEntry.item(item);

    if (entry.type == LibrarySidebarEntryType.unassignedHeader) {
      return const SizedBox.shrink();
    }

    final resolvedItem = entry.item;

    const basePadding = EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0);
    const folderChildIndent = 8.0;
    final rowPadding = entry.folderId != null
        ? basePadding.add(const EdgeInsets.only(left: folderChildIndent))
        : basePadding;

    const playButtonPosition = GenericRowPlayPosition.cover;

    Widget tile;
    if (resolvedItem is PlaylistFolder) {
      tile = FolderRow(
        folder: resolvedItem,
        padding: rowPadding,
        playPosition: playButtonPosition,
      );
    } else if (resolvedItem is GenericPlaylist) {
      tile = PlaylistRow(
        playlist: resolvedItem,
        padding: rowPadding,
        playPosition: playButtonPosition,
      );
    } else if (resolvedItem is GenericAlbum ||
        resolvedItem is GenericSimpleAlbum) {
      tile = AlbumRow(
        album: resolvedItem,
        padding: rowPadding,
        playPosition: playButtonPosition,
      );
    } else if (resolvedItem is GenericSimpleArtist ||
        resolvedItem is GenericArtist) {
      tile = ArtistRow(
        artist: resolvedItem,
        padding: rowPadding,
        playPosition: playButtonPosition,
      );
    } else {
      return const SizedBox.shrink();
    }

    // Folders can no longer be dragged themselves, but they still act as
    // drop targets so playlists can be dragged into them.
    if (resolvedItem is PlaylistFolder) {
      return DragTarget<_SidebarPlaylistDragData>(
        onWillAccept: (data) => data != null,
        onAccept: (data) {
          folderState.movePlaylistIntoFolder(data.playlistId, resolvedItem.id);
          context.read<SpotifyInternalProvider>().addPlaylistToFolder(
            playlistId: data.playlistId,
            folderId: resolvedItem.id,
          );
        },
        builder: (context, candidate, rejected) => Container(
          decoration: candidate.isNotEmpty
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                )
              : null,
          child: tile,
        ),
      );
    }

    final isLiked =
        resolvedItem is GenericPlaylist &&
        isLikedSongsPlaylistId(resolvedItem.id);

    if (resolvedItem is GenericPlaylist && !isLiked) {
      final feedbackWidth = isCollapsed
          ? widget.collapsedWidth
          : widget.expandedWidth;

      final draggable = Draggable<_SidebarPlaylistDragData>(
        data: _SidebarPlaylistDragData(resolvedItem.id, entry.folderId),
        feedback: _SidebarDragFeedback(width: feedbackWidth, child: tile),
        childWhenDragging: Opacity(opacity: 0.4, child: tile),
        child: tile,
      );

      return DragTarget<_SidebarPlaylistDragData>(
        onWillAccept: (data) =>
            data != null && data.playlistId != resolvedItem.id,
        onAccept: (data) {
          final prevFolderId = data.folderId;
          final targetFolderId = entry.folderId;
          folderState.assignPlaylistToFolder(data.playlistId, targetFolderId);
          folderState.movePlaylistBefore(data.playlistId, resolvedItem.id);
          if (prevFolderId != null && targetFolderId == null) {
            context.read<SpotifyInternalProvider>().removePlaylistFromFolder(
              playlistId: data.playlistId,
            );
          } else if (targetFolderId != null && targetFolderId != prevFolderId) {
            context.read<SpotifyInternalProvider>().addPlaylistToFolder(
              playlistId: data.playlistId,
              folderId: targetFolderId,
            );
          }
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
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelPadding: EdgeInsets.all(0),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SidebarLibraryItem extends StatelessWidget {
  final Widget Function(
    LibraryFolderState folderState,
    LibraryState libraryState,
    _SidebarPlaybackHighlight playback,
  )
  builder;

  const _SidebarLibraryItem({required this.builder});

  @override
  Widget build(BuildContext context) {
    final folderState = context.watch<LibraryFolderState>();
    final libraryState = context.watch<LibraryState>();
    final playback = context
        .select<WispAudioHandler, _SidebarPlaybackHighlight>((player) {
          final track = player.currentTrack;
          return (
            isPlaying: player.isPlaying,
            contextType: player.playbackContext?.type,
            contextId: player.playbackContext?.id,
            contextName: player.playbackContext?.name.trim(),
            currentArtistIds: track == null || track.artists.isEmpty
                ? ''
                : track.artists.map((artist) => artist.id).join('\u0001'),
          );
        });
    return builder(folderState, libraryState, playback);
  }
}

class _SidebarPlaylistDragData {
  final String playlistId;
  final String? folderId;

  const _SidebarPlaylistDragData(this.playlistId, this.folderId);
}

/// Drag feedback that mirrors the actual sidebar row (instead of a compact
/// icon+title chip), so what follows the cursor while dragging a playlist
/// looks the same as the row does at rest.
class _SidebarDragFeedback extends StatelessWidget {
  final double width;
  final Widget child;

  const _SidebarDragFeedback({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E1E1E),
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
