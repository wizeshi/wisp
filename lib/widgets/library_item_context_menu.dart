/// Context menu for library items (playlist/album/artist)
library;

import 'dart:io' show Platform, File;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metadata_models.dart';
import '../models/library_folder.dart';
import '../providers/metadata/spotify_internal.dart';
import '../services/metadata_cache.dart';
import '../services/app_navigation.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/local_playlists.dart';
import '../views/list_detail.dart';
import 'navigation.dart';
import 'playlist_folder_modals.dart';

class LibraryItemContextMenu {
  static bool get _isDesktop => Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  static void show({
    required BuildContext context,
    required dynamic item,
    Offset? position,
    required List<GenericPlaylist> playlists,
    required List<GenericAlbum> albums,
    required List<GenericSimpleArtist> artists,
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  }) {
    if (_isMobile) {
      _showMobileMenu(
        context: context,
        item: item,
        playlists: playlists,
        albums: albums,
        artists: artists,
        currentLibraryView: currentLibraryView,
        currentNavIndex: currentNavIndex,
      );
      return;
    }

    if (!_isDesktop) return;

    _showDesktopMenu(
      context: context,
      item: item,
      position: position ?? Offset.zero,
      playlists: playlists,
      albums: albums,
      artists: artists,
      currentLibraryView: currentLibraryView,
      currentNavIndex: currentNavIndex,
    );
  }

  static void _showDesktopMenu({
    required BuildContext context,
    required dynamic item,
    required Offset position,
    required List<GenericPlaylist> playlists,
    required List<GenericAlbum> albums,
    required List<GenericSimpleArtist> artists,
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  }) {
    final localState = context.read<LocalPlaylistState>();
    final localPlaylist = item is GenericPlaylist
        ? localState.getById(item.id)
        : null;

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
                top: position.dy,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {},
                  child: Material(
                    color: const Color(0xFF282828),
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 220),
                      child: IntrinsicWidth(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (item is PlaylistFolder) ...[
                                _buildDesktopMenuButton(
                                  context: dialogContext,
                                  child: _buildDesktopMenuItem(
                                    Icons.edit,
                                    'Rename',
                                  ),
                                  onTap: () {
                                    PlaylistFolderModals.showRenameFolderDialog(
                                      context,
                                      item,
                                    );
                                  },
                                ),
                                _buildDesktopMenuButton(
                                  context: dialogContext,
                                  child: _buildDesktopMenuItem(
                                    Icons.image_outlined,
                                    'Change thumbnail',
                                  ),
                                  onTap: () {
                                    PlaylistFolderModals.showChangeThumbnailDialog(
                                      context,
                                      item,
                                    );
                                  },
                                ),
                                _buildDesktopMenuButton(
                                  context: dialogContext,
                                  child: _buildDesktopMenuItem(
                                    Icons.delete_outline,
                                    'Delete',
                                  ),
                                  onTap: () {
                                    context
                                        .read<LibraryFolderState>()
                                        .deleteFolder(item.id);
                                  },
                                ),
                              ] else ...[
                                _buildDesktopMenuButton(
                                  context: dialogContext,
                                  child: _buildDesktopMenuItem(
                                    Icons.open_in_new,
                                    'Open',
                                  ),
                                  onTap: () {
                                    _navigateToItem(
                                      context,
                                      item,
                                      playlists,
                                      albums,
                                      artists,
                                      currentLibraryView,
                                      currentNavIndex,
                                    );
                                  },
                                ),
                                const SizedBox(height: 4),
                                _buildDesktopMenuButton(
                                  context: dialogContext,
                                  child: _buildDesktopMenuItem(
                                    Icons.download_outlined,
                                    'Download Metadata',
                                  ),
                                  onTap: () {
                                    _downloadMetadata(context, item);
                                  },
                                ),
                                if (item is GenericPlaylist) ...[
                                  const SizedBox(height: 4),
                                  _buildDesktopMenuButton(
                                    context: dialogContext,
                                    closeMenu: false,
                                    child: _buildDesktopMenuItem(
                                      Icons.folder,
                                      'Add to folder',
                                    ),
                                    onTap: () {
                                      PlaylistFolderModals.showAddToFolderSubmenu(
                                        context,
                                        playlist: item,
                                        position: Offset(
                                          position.dx + 230,
                                          position.dy,
                                        ),
                                        parentMenuContext: dialogContext,
                                      );
                                    },
                                  ),
                                  if (localPlaylist != null) ...[
                                    const SizedBox(height: 4),
                                    _buildDesktopMenuButton(
                                      context: dialogContext,
                                      child: _buildDesktopMenuItem(
                                        Icons.edit,
                                        'Rename',
                                      ),
                                      onTap: () {
                                        PlaylistFolderModals.showRenamePlaylistDialog(
                                          context,
                                          item,
                                        );
                                      },
                                    ),
                                    _buildDesktopMenuButton(
                                      context: dialogContext,
                                      child: _buildDesktopMenuItem(
                                        Icons.image_outlined,
                                        'Change thumbnail',
                                      ),
                                      onTap: () {
                                        PlaylistFolderModals
                                            .showChangePlaylistThumbnailDialog(
                                          context,
                                          item,
                                        );
                                      },
                                    ),
                                    _buildDesktopMenuButton(
                                      context: dialogContext,
                                      child: _buildDesktopMenuItem(
                                        Icons.delete_outline,
                                        'Delete',
                                      ),
                                      onTap: () {
                                        PlaylistFolderModals
                                            .deletePlaylistWithSync(
                                          context,
                                          item.id,
                                        );
                                      },
                                    ),
                                    if (localPlaylist.isLinked)
                                      _buildDesktopMenuButton(
                                        context: dialogContext,
                                        child: _buildDesktopMenuItem(
                                          Icons.link_off,
                                          'Detach from provider',
                                        ),
                                        onTap: () {
                                          context
                                              .read<LocalPlaylistState>()
                                              .detachFromProvider(item.id);
                                        },
                                      ),
                                  ],
                                ],
                              ],
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
    ).then((_) => PlaylistFolderModals.hideAddToFolderSubmenu());
  }

  static void _showMobileMenu({
    required BuildContext context,
    required dynamic item,
    required List<GenericPlaylist> playlists,
    required List<GenericAlbum> albums,
    required List<GenericSimpleArtist> artists,
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  }) {
    final localState = context.read<LocalPlaylistState>();
    final localPlaylist = item is GenericPlaylist
        ? localState.getById(item.id)
        : null;
    final title = _getItemTitle(item);
    final subtitle = _getItemSubtitle(item);
    final icon = _getItemIcon(item);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.4,
          minChildSize: 0.3,
          maxChildSize: 0.7,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF282828),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 52,
                          height: 52,
                          color: Colors.grey[900],
                          child: _getItemThumbnail(item) != null
                              ? (item is PlaylistFolder
                                  ? Image.file(
                                      File(_getItemThumbnail(item)!),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Icon(
                                        icon,
                                        color: Colors.grey[700],
                                      ),
                                    )
                                  : Image.network(
                                      _getItemThumbnail(item)!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Icon(
                                        icon,
                                        color: Colors.grey[700],
                                      ),
                                    ))
                              : Icon(icon, color: Colors.grey[700]),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: Colors.grey[700], height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (item is PlaylistFolder) ...[
                        _buildMobileMenuItem(
                          icon: Icons.edit,
                          label: 'Rename',
                          onTap: () {
                            Navigator.pop(context);
                            PlaylistFolderModals.showRenameFolderDialog(
                              context,
                              item,
                            );
                          },
                        ),
                        _buildMobileMenuItem(
                          icon: Icons.image_outlined,
                          label: 'Change thumbnail',
                          onTap: () {
                            Navigator.pop(context);
                            PlaylistFolderModals.showChangeThumbnailDialog(
                              context,
                              item,
                            );
                          },
                        ),
                        _buildMobileMenuItem(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          onTap: () {
                            Navigator.pop(context);
                            context
                                .read<LibraryFolderState>()
                                .deleteFolder(item.id);
                          },
                        ),
                      ] else ...[
                        _buildMobileMenuItem(
                          icon: Icons.open_in_new,
                          label: 'Open',
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToItem(
                              context,
                              item,
                              playlists,
                              albums,
                              artists,
                              currentLibraryView,
                              currentNavIndex,
                            );
                          },
                        ),
                        _buildMobileMenuItem(
                          icon: Icons.download_outlined,
                          label: 'Download Metadata',
                          onTap: () {
                            Navigator.pop(context);
                            _downloadMetadata(context, item);
                          },
                        ),
                        if (item is GenericPlaylist)
                          _buildMobileMenuItem(
                            icon: Icons.folder,
                            label: 'Add to folder',
                            onTap: () {
                              Navigator.pop(context);
                              PlaylistFolderModals.showAddToFolderMenu(
                                context,
                                playlist: item,
                              );
                            },
                          ),
                        if (localPlaylist != null) ...[
                          _buildMobileMenuItem(
                            icon: Icons.edit,
                            label: 'Rename',
                            onTap: () {
                              Navigator.pop(context);
                              PlaylistFolderModals.showRenamePlaylistDialog(
                                context,
                                item,
                              );
                            },
                          ),
                          _buildMobileMenuItem(
                            icon: Icons.image_outlined,
                            label: 'Change thumbnail',
                            onTap: () {
                              Navigator.pop(context);
                              PlaylistFolderModals
                                  .showChangePlaylistThumbnailDialog(
                                context,
                                item,
                              );
                            },
                          ),
                          _buildMobileMenuItem(
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            onTap: () {
                              Navigator.pop(context);
                              PlaylistFolderModals.deletePlaylistWithSync(
                                context,
                                item.id,
                              );
                            },
                          ),
                          if (localPlaylist.isLinked)
                            _buildMobileMenuItem(
                              icon: Icons.link_off,
                              label: 'Detach from provider',
                              onTap: () {
                                Navigator.pop(context);
                                context
                                    .read<LocalPlaylistState>()
                                    .detachFromProvider(item.id);
                              },
                            ),
                        ],
                      ],
                    ],
                  ),
                ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static Widget _buildMobileMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _getItemTitle(dynamic item) {
    if (item is PlaylistFolder) return item.title;
    if (item is GenericPlaylist) return item.title;
    if (item is GenericAlbum) return item.title;
    if (item is GenericSimpleAlbum) return item.title;
    if (item is GenericSimpleArtist) return item.name;
    return 'Item';
  }

  static String _getItemSubtitle(dynamic item) {
    if (item is PlaylistFolder) return 'Folder';
    if (item is GenericPlaylist) return item.author.displayName;
    if (item is GenericAlbum) {
      return item.artists.map((a) => a.name).join(', ');
    }
    if (item is GenericSimpleAlbum) {
      return item.artists.map((a) => a.name).join(', ');
    }
    if (item is GenericSimpleArtist) return 'Artist';
    return '';
  }

  static String? _getItemThumbnail(dynamic item) {
    if (item is PlaylistFolder && item.thumbnailPath != null) {
      return item.thumbnailPath;
    }
    if (item is GenericPlaylist && item.thumbnailUrl.isNotEmpty) {
      return item.thumbnailUrl;
    }
    if (item is GenericAlbum && item.thumbnailUrl.isNotEmpty) {
      return item.thumbnailUrl;
    }
    if (item is GenericSimpleAlbum && item.thumbnailUrl.isNotEmpty) {
      return item.thumbnailUrl;
    }
    if (item is GenericSimpleArtist && item.thumbnailUrl.isNotEmpty) {
      return item.thumbnailUrl;
    }
    return null;
  }

  static IconData _getItemIcon(dynamic item) {
    if (item is PlaylistFolder) return Icons.folder;
    if (item is GenericPlaylist) return Icons.playlist_play;
    if (item is GenericAlbum || item is GenericSimpleAlbum) return Icons.album;
    if (item is GenericSimpleArtist) return Icons.person;
    return Icons.music_note;
  }

  static Widget _buildDesktopMenuItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[300], size: 20),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  static Widget _buildDesktopMenuButton({
    required BuildContext context,
    required Widget child,
    required VoidCallback onTap,
    bool closeMenu = true,
  }) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () {
        if (closeMenu) {
          Navigator.of(context).pop();
        }
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    );
  }

  static void _navigateToItem(
    BuildContext context,
    dynamic item,
    List<GenericPlaylist> playlists,
    List<GenericAlbum> albums,
    List<GenericSimpleArtist> artists,
    LibraryView? currentLibraryView,
    int? currentNavIndex,
  ) {
    if (item is GenericPlaylist) {
      AppNavigation.instance.openSharedList(
        context,
        id: item.id,
        type: SharedListType.playlist,
        initialTitle: item.title,
        initialThumbnailUrl: item.thumbnailUrl,
      );
      return;
    }

    if (item is GenericAlbum) {
      AppNavigation.instance.openSharedList(
        context,
        id: item.id,
        type: SharedListType.album,
        initialTitle: item.title,
        initialThumbnailUrl: item.thumbnailUrl,
      );
      return;
    }

    if (item is GenericSimpleAlbum) {
      AppNavigation.instance.openSharedList(
        context,
        id: item.id,
        type: SharedListType.album,
        initialTitle: item.title,
        initialThumbnailUrl: item.thumbnailUrl,
      );
      return;
    }

    if (item is GenericSimpleArtist) {
      AppNavigation.instance.openArtist(
        context,
        artistId: item.id,
        initialArtist: item,
      );
    }
  }

  static Future<void> _downloadMetadata(BuildContext context, dynamic item) async {
    final spotify = context.read<SpotifyInternalProvider>();
    try {
      if (item is GenericPlaylist) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downloading playlist metadata...')),
          );
        }
        final playlist = await spotify.getPlaylistInfo(
          item.id,
          policy: MetadataFetchPolicy.refreshAlways,
        );
        final items = <PlaylistItem>[...?(playlist.songs)];
        var offset = items.length;
        while (playlist.hasMore == true && offset < (playlist.total ?? 0)) {
          final more = await spotify.getMorePlaylistTracks(
            item.id,
            offset: offset,
            policy: MetadataFetchPolicy.refreshAlways,
          );
          if (more.isEmpty) break;
          items.addAll(more);
          offset = items.length;
          if (more.length < 50) break;
        }
      } else if (item is GenericAlbum) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downloading album metadata...')),
          );
        }
        final album = await spotify.getAlbumInfo(
          item.id,
          policy: MetadataFetchPolicy.refreshAlways,
        );
        final items = <GenericSong>[...?(album.songs)];
        var offset = items.length;
        while (album.hasMore == true && offset < (album.total ?? 0)) {
          final more = await spotify.getMoreAlbumTracks(
            item.id,
            offset: offset,
            policy: MetadataFetchPolicy.refreshAlways,
          );
          if (more.isEmpty) break;
          items.addAll(more);
          offset = items.length;
          if (more.length < 50) break;
        }
      } else if (item is GenericSimpleArtist) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downloading artist metadata...')),
          );
        }
        await spotify.getArtistInfo(
          item.id,
          policy: MetadataFetchPolicy.refreshAlways,
        );
      } else if (item is GenericSimpleAlbum) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downloading album metadata...')),
          );
        }
        final album = await spotify.getAlbumInfo(
          item.id,
          policy: MetadataFetchPolicy.refreshAlways,
        );
        final items = <GenericSong>[...?(album.songs)];
        var offset = items.length;
        while (album.hasMore == true && offset < (album.total ?? 0)) {
          final more = await spotify.getMoreAlbumTracks(
            item.id,
            offset: offset,
            policy: MetadataFetchPolicy.refreshAlways,
          );
          if (more.isEmpty) break;
          items.addAll(more);
          offset = items.length;
          if (more.length < 50) break;
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Metadata downloaded')), 
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download metadata: $e')),
        );
      }
    }
  }
}
