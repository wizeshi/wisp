import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:io' show Platform, File;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../models/metadata_models.dart';
import '../models/library_folder.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/library_state.dart';
import '../providers/metadata/spotify_internal.dart';
import '../services/playback/playback_coordinator.dart';
import '../services/wisp_audio_handler.dart';
import '../services/navigation_history.dart';
import 'playlist_folder_modals.dart';
import 'entity_context_menus.dart';
import '../utils/liked_songs.dart';
import 'liked_songs_art.dart';

enum LibraryView { all, playlists, albums, artists }

enum LibrarySidebarEntryType { item, unassignedHeader }

typedef _SidebarPlaybackHighlight = ({
  bool isPlaying,
  String? contextType,
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
  static const _sidebarOpenDelay = Duration(milliseconds: 160);

  bool _isCollapsed = false;
  bool _isHoveringHeader = false;
  bool _layoutCollapsed = false;
  String? _hoveredSidebarItemKey;
  String? _lastSidebarTapKey;
  Duration? _lastSidebarTapTime;
  Offset? _lastSidebarTapPosition;
  Timer? _sidebarOpenTimer;
  String? _pendingSidebarOpenKey;
  Timer? _sidebarRippleTimer;
  String? _sidebarRippleKey;

  @override
  void dispose() {
    _sidebarOpenTimer?.cancel();
    _sidebarRippleTimer?.cancel();
    super.dispose();
  }

  bool _isLocalPath(String? path) {
    if (path == null || path.isEmpty) return false;
    return path.startsWith('/') || path.startsWith('file://');
  }

  bool _isDesktop() {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  String _sidebarItemHoverKey(dynamic resolvedItem) {
    if (resolvedItem is PlaylistFolder) return 'folder:${resolvedItem.id}';
    if (resolvedItem is GenericPlaylist) return 'playlist:${resolvedItem.id}';
    if (resolvedItem is GenericAlbum) return 'album:${resolvedItem.id}';
    if (resolvedItem is GenericSimpleArtist) return 'artist:${resolvedItem.id}';
    try {
      final dynamic obj = resolvedItem;
      final id = obj.id;
      if (id != null) return '${resolvedItem.runtimeType}:$id';
      final title = obj.title ?? obj.name;
      if (title != null) return '${resolvedItem.runtimeType}:$title';
    } catch (_) {
      // Ignore and fall back below.
    }
    return resolvedItem.runtimeType.toString();
  }

  Future<void> _playSidebarItem(dynamic resolvedItem) async {
    if (resolvedItem is GenericPlaylist) {
      final tracks =
          resolvedItem.songs
              ?.map(
                (item) => GenericSong(
                  id: item.id,
                  source: item.source,
                  title: item.title,
                  artists: item.artists,
                  thumbnailUrl: item.thumbnailUrl,
                  explicit: item.explicit,
                  album: item.album,
                  durationSecs: item.durationSecs,
                ),
              )
              .toList() ??
          const <GenericSong>[];
      final queueTracks = tracks.isNotEmpty
          ? tracks
          : (await context.read<SpotifyInternalProvider>().getPlaylistInfo(
                      resolvedItem.id,
                    )).songs
                    ?.map(
                      (item) => GenericSong(
                        id: item.id,
                        source: item.source,
                        title: item.title,
                        artists: item.artists,
                        thumbnailUrl: item.thumbnailUrl,
                        explicit: item.explicit,
                        album: item.album,
                        durationSecs: item.durationSecs,
                      ),
                    )
                    .toList() ??
                const <GenericSong>[];
      if (queueTracks.isEmpty || !mounted) return;
      await context.read<PlaybackCoordinator>().setQueue(
        queueTracks,
        startIndex: 0,
        play: true,
        contextType: 'playlist',
        contextName: resolvedItem.title,
        contextID: resolvedItem.id,
        contextSource: resolvedItem.source,
      );
      if (!mounted) return;
      context.read<LibraryFolderState>().markPlaylistPlayed(resolvedItem.id);
      context.read<SpotifyInternalProvider>().reportItemPlayed(
        itemId: resolvedItem.id,
        itemType: 'playlist',
      );
      return;
    }

    if (resolvedItem is GenericAlbum || resolvedItem is GenericSimpleAlbum) {
      final albumId = resolvedItem.id as String;
      final fullAlbum = await context
          .read<SpotifyInternalProvider>()
          .getAlbumInfo(albumId);
      final tracks = fullAlbum.songs ?? const <GenericSong>[];
      if (tracks.isEmpty || !mounted) return;
      await context.read<PlaybackCoordinator>().setQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'album',
        contextName: fullAlbum.title,
        contextID: fullAlbum.id,
        contextSource: fullAlbum.source,
      );
      if (!mounted) return;
      context.read<LibraryFolderState>().markItemPlayed(albumId);
      context.read<SpotifyInternalProvider>().reportItemPlayed(
        itemId: albumId,
        itemType: 'album',
      );
      return;
    }

    if (resolvedItem is GenericSimpleArtist) {
      final artist = await context
          .read<SpotifyInternalProvider>()
          .getArtistInfo(resolvedItem.id);
      final tracks = artist.topSongs;
      if (tracks.isEmpty || !mounted) return;
      await context.read<PlaybackCoordinator>().setQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'artist',
        contextName: artist.name,
        contextID: artist.id,
        contextSource: artist.source,
      );
      if (!mounted) return;
      context.read<LibraryFolderState>().markItemPlayed(resolvedItem.id);
      context.read<SpotifyInternalProvider>().reportItemPlayed(
        itemId: resolvedItem.id,
        itemType: 'artist',
      );
    }
  }

  bool _isSidebarItemActive(dynamic resolvedItem, WispAudioHandler player) {
    final playbackType = player.playbackContextType;
    final playbackId = player.playbackContextID;
    final playbackName = player.playbackContextName?.trim();

    return switch (resolvedItem) {
      GenericPlaylist playlist =>
        playbackType == 'playlist' &&
            (playbackId == playlist.id ||
                playbackName == playlist.title.trim()),
      GenericAlbum album =>
        playbackType == 'album' &&
            (playbackId == album.id || playbackName == album.title.trim()),
      GenericSimpleAlbum album =>
        playbackType == 'album' &&
            (playbackId == album.id || playbackName == album.title.trim()),
      GenericSimpleArtist artist =>
        (playbackType == 'artist' &&
                (playbackId == artist.id ||
                    playbackName == artist.name.trim())) ||
            (player.currentTrack?.artists.any((a) => a.id == artist.id) ??
                false),
      _ => false,
    };
  }

  Future<void> _handleSidebarPlay(dynamic resolvedItem) async {
    final player = context.read<WispAudioHandler>();
    final coordinator = context.read<PlaybackCoordinator>();
    final isActive = _isSidebarItemActive(resolvedItem, player);

    if (isActive) {
      if (player.isPlaying) {
        await coordinator.pause();
      } else {
        if (player.isLoading || player.isBuffering) {
          return;
        }
        await coordinator.play();
      }
      return;
    }

    await _playSidebarItem(resolvedItem);
  }

  void _handleSidebarPrimaryPointerDown(
    PointerDownEvent event,
    dynamic resolvedItem,
  ) {
    if (!_isDesktop() ||
        event.buttons != kPrimaryButton ||
        resolvedItem is PlaylistFolder) {
      return;
    }

    final key = _sidebarItemHoverKey(resolvedItem);
    final previousKey = _lastSidebarTapKey;
    final previousTime = _lastSidebarTapTime;
    final previousPosition = _lastSidebarTapPosition;
    final isDoubleTap =
        previousKey == key &&
        previousTime != null &&
        previousPosition != null &&
        event.timeStamp - previousTime <= kDoubleTapTimeout &&
        (event.position - previousPosition).distance <= kDoubleTapSlop;

    if (isDoubleTap) {
      final pendingOpen = _sidebarOpenTimer;
      if (_pendingSidebarOpenKey == key && (pendingOpen?.isActive ?? false)) {
        pendingOpen!.cancel();
        _sidebarOpenTimer = null;
        _pendingSidebarOpenKey = null;
        widget.onLibraryItemSelected(resolvedItem);
      }
      _sidebarRippleTimer?.cancel();
      _lastSidebarTapKey = null;
      _lastSidebarTapTime = null;
      _lastSidebarTapPosition = null;
      _playSidebarItem(resolvedItem);
      return;
    }

    _lastSidebarTapKey = key;
    _lastSidebarTapTime = event.timeStamp;
    _lastSidebarTapPosition = event.position;
    _scheduleSidebarRipple(key);
    _sidebarOpenTimer?.cancel();
    _pendingSidebarOpenKey = key;
    _sidebarOpenTimer = Timer(_sidebarOpenDelay, () {
      if (_pendingSidebarOpenKey != key) return;
      _sidebarOpenTimer = null;
      _pendingSidebarOpenKey = null;
      if (mounted) {
        widget.onLibraryItemSelected(resolvedItem);
      }
    });
  }

  void _scheduleSidebarRipple(String key) {
    _sidebarRippleTimer?.cancel();
    _sidebarRippleTimer = Timer(kDoubleTapTimeout, () {
      if (mounted && _lastSidebarTapKey == key) {
        _showSidebarRipple(key);
      }
    });
  }

  void _showSidebarRipple(String key) {
    _sidebarRippleTimer?.cancel();
    setState(() => _sidebarRippleKey = key);
    _sidebarRippleTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted && _sidebarRippleKey == key) {
        setState(() => _sidebarRippleKey = null);
      }
    });
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
              final folder = folderState.getFolderById(id) ??
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

            if (t == 'Playlist' || t == 'playlist' || uri.contains('playlist')) {
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
              return _itemTitle(a).toLowerCase().compareTo(_itemTitle(b).toLowerCase());
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
                allEntries.add(LibrarySidebarEntry.item(child, folderId: item.id));
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
                                  maxWidth: 24
                                ),
                                tooltip: 'Collapse Sidebar',
                                icon: Icon(Symbols.left_panel_close, color: Colors.white, size: 20),
                                onPressed: () => {
                                  setState(() => _isCollapsed = !_isCollapsed)
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
                    context.read<SpotifyInternalProvider>().fetchUserLibrarySorted(sortMode: mode);
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
                  icon: Icon(
                    Icons.sort,
                    color: Colors.grey[500],
                    size: 16,
                  ),
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
                    )
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black38,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                maxWidth: 32
              ),
              tooltip: 'Expand Sidebar',
              icon: Icon(Symbols.left_panel_open, color: Colors.white, size: 28),
              onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
            )
            : Container(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minHeight: 32,
                minWidth: 32,
                maxHeight: 32, 
                maxWidth: 32
              ),
              child: Icon(Symbols.library_music, color: Colors.white, size: 28),
            )
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
    final isDesktop = _isDesktop();
    final allowDrag = true;

    if (entry.type == LibrarySidebarEntryType.unassignedHeader) {
      return SizedBox.shrink();
    }

    final resolvedItem = entry.item;
    final playbackType = playback.contextType;
    final playbackId = playback.contextId;
    final playbackName = playback.contextName;
    final isCurrentPlaybackItem = switch (resolvedItem) {
      GenericPlaylist playlist =>
        playbackType == 'playlist' &&
            (playbackId == playlist.id ||
                playbackName == playlist.title.trim()),
      GenericAlbum album =>
        playbackType == 'album' &&
            (playbackId == album.id || playbackName == album.title.trim()),
      GenericSimpleAlbum album =>
        playbackType == 'album' &&
            (playbackId == album.id || playbackName == album.title.trim()),
      GenericSimpleArtist artist =>
        (playbackType == 'artist' &&
                (playbackId == artist.id ||
                    playbackName == artist.name.trim())) ||
            (playback.currentArtistIds.isNotEmpty &&
                playback.currentArtistIds.split('\u0001').contains(artist.id)),
      _ => false,
    };
    final titleColor = isCurrentPlaybackItem
        ? Theme.of(context).colorScheme.primary
        : Colors.white;
    final isArtist = resolvedItem is GenericSimpleArtist;
    final hoverKey = _sidebarItemHoverKey(resolvedItem);
    final showHoverPlayOverlay =
        isDesktop &&
        resolvedItem is! PlaylistFolder &&
        _hoveredSidebarItemKey == hoverKey;
    String? imageUrl;
    String? filePath;
    String title = '';
    String? subtitle;
    final isLiked =
        resolvedItem is GenericPlaylist &&
        isLikedSongsPlaylistId(resolvedItem.id);

    if (resolvedItem is PlaylistFolder) {
      filePath = resolvedItem.thumbnailPath;
      title = resolvedItem.title;
      final count = libraryState.playlists
          .where(
            (p) => folderState.folderIdForPlaylist(p.id) == resolvedItem.id,
          )
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
    } else if (resolvedItem is GenericSimpleAlbum) {
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

    Widget tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: isDesktop
          ? (_) {
              if (resolvedItem is! PlaylistFolder) {
                setState(() => _hoveredSidebarItemKey = hoverKey);
              }
            }
          : null,
      onExit: isDesktop
          ? (_) {
              if (_hoveredSidebarItemKey == hoverKey) {
                setState(() => _hoveredSidebarItemKey = null);
              }
            }
          : null,
      child: Listener(
        onPointerDown: (event) =>
            _handleSidebarPrimaryPointerDown(event, resolvedItem),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onSecondaryTapDown: !isDesktop ? null : (details) {
            if (resolvedItem is GenericPlaylist) {
              EntityContextMenus.showPlaylistMenu(
                context,
                playlist: resolvedItem,
                globalPosition: details.globalPosition,
              );
              return;
            }
            if (resolvedItem is GenericAlbum ||
                resolvedItem is GenericSimpleAlbum) {
              EntityContextMenus.showAlbumMenu(
                context,
                album: resolvedItem,
                globalPosition: details.globalPosition,
              );
              return;
            }
            if (resolvedItem is GenericSimpleArtist) {
              EntityContextMenus.showArtistMenu(
                context,
                artist: resolvedItem,
                globalPosition: details.globalPosition,
              );
              return;
            }
            if (resolvedItem is PlaylistFolder) {
              EntityContextMenus.showFolderMenu(
                context,
                folder: resolvedItem,
                globalPosition: details.globalPosition,
              );
            }
          },
          onLongPress: isDesktop ? null : () {
            if (resolvedItem is GenericPlaylist) {
              EntityContextMenus.showPlaylistMenu(
                context,
                playlist: resolvedItem,
              );
              return;
            }
            if (resolvedItem is GenericAlbum ||
                resolvedItem is GenericSimpleAlbum) {
              EntityContextMenus.showAlbumMenu(context, album: resolvedItem);
              return;
            }
            if (resolvedItem is GenericSimpleArtist) {
              EntityContextMenus.showArtistMenu(context, artist: resolvedItem);
              return;
            }
            if (resolvedItem is PlaylistFolder) {
              EntityContextMenus.showFolderMenu(context, folder: resolvedItem);
            }
          },
          onTap: resolvedItem is PlaylistFolder
              ? () => folderState.toggleFolderCollapsed(resolvedItem.id)
              : null,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    EdgeInsets.symmetric(
                      horizontal: isCollapsed ? 8 : 12,
                      vertical: 8,
                    ).add(
                      EdgeInsets.only(
                        left: ((entry.folderId != null) && !isCollapsed)
                            ? 12
                            : 0,
                      ),
                    ),
                child: Row(
              mainAxisAlignment: isCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                widgetForThumbnail(
                  showHoverPlayOverlay
                      ? _SidebarHoverPlayThumbnail(
                          showOverlay: true,
                          isActive: isCurrentPlaybackItem,
                          isPlaying: playback.isPlaying,
                          onPlayPressed: () => _handleSidebarPlay(resolvedItem),
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
                                                      File(
                                                        imageUrl.replaceFirst(
                                                          'file://',
                                                          '',
                                                        ),
                                                      ),
                                                      filterQuality: FilterQuality.medium,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            url,
                                                            error,
                                                          ) => Icon(
                                                            Icons.music_note,
                                                            color: Colors
                                                                .grey[700],
                                                          ),
                                                    )
                                                  : CachedNetworkImage(
                                                      imageUrl: imageUrl,
                                                      filterQuality: FilterQuality.medium,
                                                      fit: BoxFit.cover,
                                                      errorWidget:
                                                          (
                                                            context,
                                                            url,
                                                            error,
                                                          ) {
                                                            return Icon(
                                                              Icons.music_note,
                                                              color: Colors
                                                                  .grey[700],
                                                            );
                                                          },
                                                      placeholder:
                                                          (context, url) =>
                                                              Container(
                                                                color: Colors
                                                                    .grey[800],
                                                              ),
                                                    ))
                                            : Icon(
                                                Icons.music_note,
                                                color: Colors.grey[700],
                                              ))),
                          ),
                        )
                      : Container(
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
                                                    File(
                                                      imageUrl.replaceFirst(
                                                        'file://',
                                                        '',
                                                      ),
                                                    ),
                                                    fit: BoxFit.cover,
                                                    filterQuality: FilterQuality.medium,
                                                    errorBuilder:
                                                        (context, url, error) =>
                                                            Icon(
                                                              Icons.music_note,
                                                              color: Colors
                                                                  .grey[700],
                                                            ),
                                                  )
                                                : CachedNetworkImage(
                                                    imageUrl: imageUrl,
                                                    fit: BoxFit.cover,
                                                    filterQuality: FilterQuality.medium,
                                                    errorWidget:
                                                        (context, url, error) {
                                                          return Icon(
                                                            Icons.music_note,
                                                            color: Colors
                                                                .grey[700],
                                                          );
                                                        },
                                                    placeholder:
                                                        (context, url) =>
                                                            Container(
                                                              color: Colors
                                                                  .grey[800],
                                                            ),
                                                  ))
                                          : Icon(
                                              Icons.music_note,
                                              color: Colors.grey[700],
                                            ))),
                        ),
                  isArtist,
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
                                ? FontWeight.w700
                                : FontWeight.w600,
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
                  if (isCurrentPlaybackItem && playback.isPlaying) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.volume_up,
                      color: Theme.of(context).colorScheme.primary,
                      size: 16,
                    ),
                  ] else if (resolvedItem is PlaylistFolder)
                    Icon(
                      folderState.isFolderCollapsed(resolvedItem.id)
                          ? Icons.chevron_right
                          : Icons.expand_more,
                      color: Colors.grey[500],
                      size: 20,
                    ),
                ],
              ],
                ),
              ),
              if (_sidebarRippleKey == hoverKey)
                const Positioned.fill(
                  child: IgnorePointer(child: _SidebarClickRipple()),
                ),
            ],
          ),
          ),
        ),
      ),
    );

    void ensureCustomSort() {
      if (_pendingSidebarOpenKey == hoverKey) {
        _sidebarOpenTimer?.cancel();
        _sidebarOpenTimer = null;
        _pendingSidebarOpenKey = null;
        _sidebarRippleTimer?.cancel();
      }
    }

    if (allowDrag && resolvedItem is PlaylistFolder) {
      final draggable = LongPressDraggable<_SidebarFolderDragData>(
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
        onWillAccept: (data) =>
            data != null && data.folderId != resolvedItem.id,
        onAccept: (data) =>
            folderState.moveFolderBefore(data.folderId, resolvedItem.id),
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
        onAccept: (data) {
          folderState.movePlaylistIntoFolder(
            data.playlistId,
            resolvedItem.id,
          );
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
          child: reorderTarget,
        ),
      );
      tile = playlistDropTarget;
    }

    if (allowDrag && resolvedItem is GenericPlaylist && !isLiked) {
      final draggable = LongPressDraggable<_SidebarPlaylistDragData>(
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
      final folderDropTarget = DragTarget<_SidebarFolderDragData>(
        onWillAccept: (data) => data != null,
        onAccept: (data) => folderState.moveFolderBeforePlaylist(
          data.folderId,
          resolvedItem.id,
        ),
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

  const _SidebarLibraryItem(
    {required this.builder}
  );

  @override
  Widget build(BuildContext context) {
    final folderState = context.watch<LibraryFolderState>();
    final libraryState = context.watch<LibraryState>();
    final playback = context.select<WispAudioHandler, _SidebarPlaybackHighlight>(
      (player) {
        final track = player.currentTrack;
        return (
          isPlaying: player.isPlaying,
          contextType: player.playbackContextType,
          contextId: player.playbackContextID,
          contextName: player.playbackContextName?.trim(),
          currentArtistIds: track == null || track.artists.isEmpty
              ? ''
              : track.artists.map((artist) => artist.id).join('\u0001'),
        );
      },
    );
    return builder(folderState, libraryState, playback);
  }
}

class _SidebarClickRipple extends StatelessWidget {
  const _SidebarClickRipple();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final diameter = constraints.biggest.longestSide * 1.5;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            builder: (context, progress, child) => Center(
              child: Container(
                width: diameter * progress,
                height: diameter * progress,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16 * (1 - progress)),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
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

class _SidebarHoverPlayThumbnail extends StatelessWidget {
  final Widget child;
  final bool showOverlay;
  final bool isActive;
  final bool isPlaying;
  final VoidCallback onPlayPressed;

  const _SidebarHoverPlayThumbnail({
    required this.child,
    required this.showOverlay,
    required this.isActive,
    required this.isPlaying,
    required this.onPlayPressed,
  });

  @override
  Widget build(BuildContext context) {
    final icon = isActive && isPlaying ? Icons.pause : Icons.play_arrow;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: showOverlay ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: IgnorePointer(
                ignoring: !showOverlay,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  alignment: Alignment.center,
                  child: IconButton(
                    icon: Icon(icon, color: Colors.white, size: 28),
                    onPressed: onPlayPressed,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    splashRadius: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
