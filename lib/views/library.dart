/// Library view with paginated tabs for playlists, albums, and artists
library;

import 'dart:io' show Platform, File;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/metadata/spotify_internal.dart';
import '../models/metadata_models.dart';
import '../models/library_folder.dart';
import '../providers/library/library_state.dart';
import '../widgets/navigation.dart';
import '../widgets/playlist_folder_modals.dart';
import '../providers/library/library_folders.dart';
import '../providers/library/local_playlists.dart';
import '../providers/preferences/preferences_provider.dart';
import '../utils/liked_songs.dart';
import '../widgets/liked_songs_art.dart';
import '../services/metadata_cache.dart';
import '../services/app_navigation.dart';
import '../widgets/provider_disabled_state.dart';
import '../widgets/entity_context_menus.dart';
import 'list_detail.dart';

bool _isLocalThumbnailPath(String path) {
  return path.startsWith('/') || path.startsWith('file://');
}

Widget _buildPlaylistThumbnail(GenericPlaylist playlist) {
  if (isLikedSongsPlaylistId(playlist.id)) {
    return const LikedSongsArt();
  }

  final url = playlist.thumbnailUrl;
  if (url.isEmpty) {
    return Container(
      color: Colors.grey[800],
      child: Icon(Icons.playlist_play, color: Colors.grey[600]),
    );
  }

  if (_isLocalThumbnailPath(url)) {
    final path = url.replaceFirst('file://', '');
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, url, error) => Container(
        color: Colors.grey[800],
        child: Icon(Icons.playlist_play, color: Colors.grey[600]),
      ),
    );
  }

  return CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    placeholder: (context, url) => Container(color: Colors.grey[800]),
    errorWidget: (context, url, error) => Container(
      color: Colors.grey[800],
      child: Icon(Icons.playlist_play, color: Colors.grey[600]),
    ),
  );
}

class LibraryTabView extends StatefulWidget {
  final List<GenericPlaylist> initialPlaylists;
  final List<GenericAlbum> initialAlbums;
  final List<GenericSimpleArtist> initialArtists;
  final ValueListenable<int>? refreshSignal;

  const LibraryTabView({
    super.key,
    required this.initialPlaylists,
    required this.initialAlbums,
    required this.initialArtists,
    this.refreshSignal,
  });

  @override
  State<LibraryTabView> createState() => LibraryTabViewState();
}

class LibraryTabViewState extends State<LibraryTabView> {
  LibraryView _selectedTab = LibraryView.playlists;

  final _playlistScrollController = ScrollController();
  final _albumScrollController = ScrollController();
  final _artistScrollController = ScrollController();

  List<GenericPlaylist> _remotePlaylists = [];
  List<GenericPlaylist> _localPlaylists = [];
  Set<String> _hiddenProviderIds = {};
  List<GenericAlbum> _albums = [];
  List<GenericSimpleArtist> _artists = [];

  bool _isLoadingPlaylists = false;
  bool _isLoadingAlbums = false;
  bool _isLoadingArtists = false;

  bool _hasMorePlaylists = true;
  bool _hasMoreAlbums = true;
  bool _hasMoreArtists = true;

  String? _playlistError;
  String? _albumError;
  String? _artistError;

  bool _dragModeEnabled = false;
  VoidCallback? _localPlaylistListener;
  VoidCallback? _refreshListener;
  int _lastRefreshTick = 0;

  List<GenericPlaylist> get _displayPlaylists {
    final localById = {for (final p in _localPlaylists) p.id: p};
    final merged = <GenericPlaylist>[];
    final seen = <String>{};

    for (final playlist in _remotePlaylists) {
      if (_hiddenProviderIds.contains(playlist.id)) {
        continue;
      }
      merged.add(localById[playlist.id] ?? playlist);
      seen.add(playlist.id);
    }

    for (final playlist in _localPlaylists) {
      if (!seen.contains(playlist.id)) {
        merged.add(playlist);
      }
    }

    return merged;
  }

  @override
  void initState() {
    super.initState();
    final localState = context.read<LocalPlaylistState>();
    _localPlaylists = List.from(localState.genericPlaylists);
    _hiddenProviderIds = Set.from(localState.hiddenProviderPlaylistIds);
    _remotePlaylists = widget.initialPlaylists
        .where((p) => !localState.isLocalPlaylistId(p.id))
        .toList();

    _localPlaylistListener = () {
      if (!mounted) return;
      setState(() {
        _localPlaylists = List.from(localState.genericPlaylists);
        _hiddenProviderIds = Set.from(localState.hiddenProviderPlaylistIds);
      });
      context
          .read<LibraryFolderState>()
          .syncPlaylists(context.read<LibraryState>().playlists);
    };
    localState.addListener(_localPlaylistListener!);
    _albums = List.from(widget.initialAlbums);
    _artists = List.from(widget.initialArtists);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<LibraryFolderState>()
          .syncPlaylists(context.read<LibraryState>().playlists);
    });

    _playlistScrollController.addListener(_onPlaylistScroll);
    _albumScrollController.addListener(_onAlbumScroll);
    _artistScrollController.addListener(_onArtistScroll);

    final refreshSignal = widget.refreshSignal;
    if (refreshSignal != null) {
      _lastRefreshTick = refreshSignal.value;
      _refreshListener = () {
        if (!mounted) return;
        if (refreshSignal.value == _lastRefreshTick) return;
        _lastRefreshTick = refreshSignal.value;
        forceRefresh();
      };
      refreshSignal.addListener(_refreshListener!);
    }
  }

  @override
  void dispose() {
    if (_refreshListener != null) {
      widget.refreshSignal?.removeListener(_refreshListener!);
    }
    if (_localPlaylistListener != null) {
      context.read<LocalPlaylistState>().removeListener(_localPlaylistListener!);
    }
    _playlistScrollController.dispose();
    _albumScrollController.dispose();
    _artistScrollController.dispose();
    super.dispose();
  }

  void _onPlaylistScroll() {
    if (_playlistScrollController.position.pixels >=
        _playlistScrollController.position.maxScrollExtent - 200) {
      _loadMorePlaylists();
    }
  }

  void _onAlbumScroll() {
    if (_albumScrollController.position.pixels >=
        _albumScrollController.position.maxScrollExtent - 200) {
      _loadMoreAlbums();
    }
  }

  void _onArtistScroll() {
    if (_artistScrollController.position.pixels >=
        _artistScrollController.position.maxScrollExtent - 200) {
      _loadMoreArtists();
    }
  }

  int get _providerPlaylistCount => _remotePlaylists
      .where((playlist) => !isLikedSongsPlaylistId(playlist.id))
      .length;

  GenericPlaylist _resolveLikedPlaylistTemplate() {
    final existingRemote = _remotePlaylists.where((playlist) {
      return isLikedSongsPlaylistId(playlist.id);
    });
    if (existingRemote.isNotEmpty) {
      return existingRemote.first;
    }

    final existingLocal = _localPlaylists.where((playlist) {
      return isLikedSongsPlaylistId(playlist.id);
    });
    if (existingLocal.isNotEmpty) {
      return existingLocal.first;
    }

    return buildLikedSongsPlaylist(
      userDisplayName: context.read<SpotifyInternalProvider>().userDisplayName,
    );
  }

  void _ensureLikedPlaylistInRemote() {
    final hasLiked = _remotePlaylists.any((playlist) {
      return isLikedSongsPlaylistId(playlist.id);
    });
    if (hasLiked) return;
    _remotePlaylists = [_resolveLikedPlaylistTemplate(), ..._remotePlaylists];
  }

  Future<void> _loadMorePlaylists({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (_isLoadingPlaylists || !_hasMorePlaylists) return;

    setState(() => _isLoadingPlaylists = true);

    final spotify = context.read<SpotifyInternalProvider>();

    try {
      final morePlaylists = await spotify.getUserPlaylists(
        limit: 50,
        offset: _providerPlaylistCount,
        policy: policy,
      );

      if (mounted) {
        setState(() {
          _remotePlaylists.addAll(morePlaylists);
          _ensureLikedPlaylistInRemote();
          _hasMorePlaylists = morePlaylists.length == 50;
          _isLoadingPlaylists = false;
          _playlistError = null;
        });
        context.read<LibraryState>().setLibrary(
              playlists: List<GenericPlaylist>.from(_remotePlaylists),
              albums: _albums,
              artists: _artists,
            );
        context
            .read<LibraryFolderState>()
            .syncPlaylists(context.read<LibraryState>().playlists);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _playlistError = e.toString();
          _isLoadingPlaylists = false;
        });
      }
    }
  }

  Future<void> _loadMoreAlbums({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (_isLoadingAlbums || !_hasMoreAlbums) return;

    setState(() => _isLoadingAlbums = true);

    final spotify = context.read<SpotifyInternalProvider>();

    try {
      final moreAlbums = await spotify.getUserAlbums(
        limit: 50,
        offset: _albums.length,
        policy: policy,
      );

      if (mounted) {
        setState(() {
          _albums.addAll(moreAlbums);
          _hasMoreAlbums = moreAlbums.length == 50;
          _isLoadingAlbums = false;
          _albumError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _albumError = e.toString();
          _isLoadingAlbums = false;
        });
      }
    }
  }

  Future<void> _loadMoreArtists({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (_isLoadingArtists || !_hasMoreArtists) return;

    setState(() => _isLoadingArtists = true);

    final spotify = context.read<SpotifyInternalProvider>();

    try {
      final moreArtists = await spotify.getUserFollowedArtists(
        limit: 50,
        after: _artists.isNotEmpty ? _artists.last.id : null,
        policy: policy,
      );

      if (mounted) {
        setState(() {
          _artists.addAll(moreArtists);
          _hasMoreArtists = moreArtists.length == 50;
          _isLoadingArtists = false;
          _artistError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _artistError = e.toString();
          _isLoadingArtists = false;
        });
      }
    }
  }

  Future<void> _refreshPlaylists({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final likedTemplate = _resolveLikedPlaylistTemplate();
    setState(() {
      _remotePlaylists = [likedTemplate];
      _hasMorePlaylists = true;
      _playlistError = null;
    });
    await _loadMorePlaylists(policy: policy);
  }

  Future<void> _refreshAlbums({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    setState(() {
      _albums = [];
      _hasMoreAlbums = true;
      _albumError = null;
    });
    await _loadMoreAlbums(policy: policy);
  }

  Future<void> _refreshArtists({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    setState(() {
      _artists = [];
      _hasMoreArtists = true;
      _artistError = null;
    });
    await _loadMoreArtists(policy: policy);
  }

  Future<void> forceRefresh({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshAlways,
  }) async {
    switch (_selectedTab) {
      case LibraryView.playlists:
      case LibraryView.all:
        await _refreshPlaylists(policy: policy);
        break;
      case LibraryView.albums:
        await _refreshAlbums(policy: policy);
        break;
      case LibraryView.artists:
        await _refreshArtists(policy: policy);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesProvider>();
    if (!preferences.metadataSpotifyEnabled) {
      return const ProviderDisabledState();
    }

    final isMobile = Platform.isAndroid || Platform.isIOS;
    final padding = isMobile ? 20.0 : 16.0;
    final folderState = context.watch<LibraryFolderState>();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMobile)
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Your Library',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (_selectedTab == LibraryView.playlists)
                        _buildSortMenuButton(folderState, isMobile: true),
                      if (_selectedTab == LibraryView.playlists &&
                          folderState.isCustomSort)
                        _buildDragToggleButton(),
                      _buildCreateMenuButton(),
                    ],
                  ),
                const SizedBox(height: 16),
                _buildTabChips(),
              ],
            ),
          ),
          // Content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildTabContent(padding),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildTabChip(LibraryView.playlists, 'Playlists', _displayPlaylists.length),
          const SizedBox(width: 8),
          _buildTabChip(LibraryView.albums, 'Albums', _albums.length),
          const SizedBox(width: 8),
          _buildTabChip(LibraryView.artists, 'Artists', _artists.length),
        ],
      ),
    );
  }

  Widget _buildSortMenuButton(
    LibraryFolderState folderState, {
    required bool isMobile,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: PopupMenuButton<LibrarySortMode>(
        tooltip: 'Sort',
        icon: Icon(
          Icons.sort,
          color: Colors.grey[400],
          size: isMobile ? 22 : 18,
        ),
        color: const Color(0xFF282828),
        onSelected: (mode) {
          folderState.setSortMode(mode);
          if (mode != LibrarySortMode.custom && isMobile) {
            setState(() => _dragModeEnabled = false);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: LibrarySortMode.original,
            child: Text('Index', style: TextStyle(color: Colors.white)),
          ),
          const PopupMenuItem(
            value: LibrarySortMode.recentlyPlayed,
            child: Text('Recently played', style: TextStyle(color: Colors.white)),
          ),
          const PopupMenuItem(
            value: LibrarySortMode.custom,
            child: Text('Custom order', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDragToggleButton() {
    return IconButton(
      tooltip: _dragModeEnabled ? 'Disable drag' : 'Enable drag',
      icon: Icon(
        Icons.drag_handle,
        color: _dragModeEnabled ? Colors.white : Colors.grey[500],
      ),
      onPressed: () {
        setState(() => _dragModeEnabled = !_dragModeEnabled);
      },
    );
  }

  Widget _buildCreateMenuButton() {
    return IconButton(
      tooltip: 'Create',
      icon: Icon(Icons.add, color: Colors.grey[300]),
      onPressed: _showCreateMenu,
    );
  }

  Future<void> _showCreateMenu() async {
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF1B1B1B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined, color: Colors.white),
                title: const Text('Create folder', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await PlaylistFolderModals.showCreateFolderDialog(this.context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Create playlist', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await PlaylistFolderModals.showCreatePlaylistDialog(
                    this.context,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabChip(LibraryView tab, String label, int count) {
    final isSelected = _selectedTab == tab;
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      child: ChoiceChip(
        label: Text(
          '$label ($count)',
          style: TextStyle(
            color: isSelected ? colorScheme.onPrimary : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          if (!selected) return;
          setState(() {
            _selectedTab = tab;
            if (tab != LibraryView.playlists) {
              _dragModeEnabled = false;
            }
          });
        },
        backgroundColor: const Color(0xFF282828),
        selectedColor: colorScheme.primary,
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildTabContent(double padding) {
    switch (_selectedTab) {
      case LibraryView.playlists:
        return _buildPlaylistsContent(padding);
      case LibraryView.all:
        return _buildPlaylistsContent(padding);
      case LibraryView.albums:
        return _buildAlbumsContent(padding);
      case LibraryView.artists:
        return _buildArtistsContent(padding);
    }
  }

  Widget _buildPlaylistsContent(double padding) {
    final folderState = context.watch<LibraryFolderState>();
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final allowDrag = folderState.isCustomSort && (!isMobile || _dragModeEnabled);

    if (_playlistError != null && _displayPlaylists.isEmpty) {
      return _buildErrorWidget(_playlistError!, _refreshPlaylists);
    }

    if (_displayPlaylists.isEmpty && !_isLoadingPlaylists) {
      return _buildEmptyState('No playlists in your library');
    }

    GenericPlaylist? likedPlaylist;
    for (final playlist in _displayPlaylists) {
      if (isLikedSongsPlaylistId(playlist.id)) {
        likedPlaylist = playlist;
        break;
      }
    }
    final filteredPlaylists = _displayPlaylists
        .where((playlist) => !isLikedSongsPlaylistId(playlist.id))
        .toList();
    final groups = folderState.buildPlaylistGroups(filteredPlaylists);
    final entries = <_PlaylistListEntry>[];

    if (likedPlaylist != null) {
      entries.add(_PlaylistListEntry.playlist(likedPlaylist, folderId: null));
    }
    final folderCounts = <String, int>{
      for (final group in groups.folders) group.folder.id: group.playlists.length,
    };

    for (final group in groups.folders) {
      entries.add(_PlaylistListEntry.folder(group.folder));
      if (!folderState.isFolderCollapsed(group.folder.id)) {
        for (final playlist in group.playlists) {
          entries.add(
            _PlaylistListEntry.playlist(
              playlist,
              folderId: group.folder.id,
            ),
          );
        }
      }
    }

    if (groups.folders.isNotEmpty) {
      entries.add(const _PlaylistListEntry.unassignedHeader());
    }

    for (final playlist in groups.unassigned) {
      entries.add(_PlaylistListEntry.playlist(playlist, folderId: null));
    }

    return RefreshIndicator(
      onRefresh: _refreshPlaylists,
      child: ListView.builder(
        key: const ValueKey('playlists'),
        controller: _playlistScrollController,
        padding: EdgeInsets.zero,
        itemCount:
            entries.length +
            (_hasMorePlaylists || _isLoadingPlaylists ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= entries.length) {
            return _buildLoadingIndicator(
              _isLoadingPlaylists,
              horizontalPadding: padding,
            );
          }

          final entry = entries[index];
          if (entry.type == _PlaylistListEntryType.unassignedHeader) {
            return _UnassignedHeader(
              horizontalPadding: padding,
              enabled: allowDrag,
              onDrop: (playlistId) {
                folderState.movePlaylistIntoFolder(playlistId, null);
              },
            );
          }

          if (entry.type == _PlaylistListEntryType.folder && entry.folder != null) {
            return _FolderListTile(
              folder: entry.folder!,
              horizontalPadding: padding,
              playlists: _displayPlaylists,
              albums: _albums,
              artists: _artists,
              currentLibraryView: _selectedTab,
              currentNavIndex: 2,
              playlistCount: folderCounts[entry.folder!.id] ?? 0,
              enableDrag: allowDrag,
              onFolderDrop: (playlistId) {
                folderState.movePlaylistIntoFolder(playlistId, entry.folder!.id);
              },
              onFolderReorder: (folderId) {
                if (folderId == entry.folder!.id) return;
                folderState.moveFolderBefore(folderId, entry.folder!.id);
              },
            );
          }

          final playlist = entry.playlist!;
          final isLiked = isLikedSongsPlaylistId(playlist.id);
          final targetFolderId = entry.folderId;
          if (isLiked) {
            return _PlaylistListTile(
              playlist: playlist,
              horizontalPadding: padding,
              onTap: () => _openPlaylist(playlist),
              playlists: _displayPlaylists,
              albums: _albums,
              artists: _artists,
              currentLibraryView: _selectedTab,
              currentNavIndex: 2,
            );
          }
          return _DraggablePlaylistTile(
            playlist: playlist,
            horizontalPadding: padding,
            folderId: targetFolderId,
            enableDrag: allowDrag,
            playlists: _displayPlaylists,
            albums: _albums,
            artists: _artists,
            currentLibraryView: _selectedTab,
            currentNavIndex: 2,
            onTap: () => _openPlaylist(playlist),
            onPlaylistDrop: (draggedId) {
              folderState.assignPlaylistToFolder(draggedId, targetFolderId);
              folderState.movePlaylistBefore(draggedId, playlist.id);
            },
          );
        },
      ),
    );
  }

  Widget _buildAlbumsContent(double padding) {
    if (_albumError != null && _albums.isEmpty) {
      return _buildErrorWidget(_albumError!, _refreshAlbums);
    }

    if (_albums.isEmpty && !_isLoadingAlbums) {
      return _buildEmptyState('No albums in your library');
    }

    return RefreshIndicator(
      onRefresh: _refreshAlbums,
      child: ListView.builder(
        key: const ValueKey('albums'),
        controller: _albumScrollController,
        padding: EdgeInsets.zero,
        itemCount:
            _albums.length + (_hasMoreAlbums || _isLoadingAlbums ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _albums.length) {
            return _buildLoadingIndicator(
              _isLoadingAlbums,
              horizontalPadding: padding,
            );
          }

          final album = _albums[index];
          return _AlbumListTile(
            album: album,
            horizontalPadding: padding,
            onTap: () => _openAlbum(album),
            playlists: _displayPlaylists,
            albums: _albums,
            artists: _artists,
            currentLibraryView: _selectedTab,
            currentNavIndex: 2,
          );
        },
      ),
    );
  }

  Widget _buildArtistsContent(double padding) {
    if (_artistError != null && _artists.isEmpty) {
      return _buildErrorWidget(_artistError!, _refreshArtists);
    }

    if (_artists.isEmpty && !_isLoadingArtists) {
      return _buildEmptyState('No artists in your library');
    }

    return RefreshIndicator(
      onRefresh: _refreshArtists,
      child: ListView.builder(
        key: const ValueKey('artists'),
        controller: _artistScrollController,
        padding: EdgeInsets.zero,
        itemCount:
            _artists.length + (_hasMoreArtists || _isLoadingArtists ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _artists.length) {
            return _buildLoadingIndicator(
              _isLoadingArtists,
              horizontalPadding: padding,
            );
          }

          final artist = _artists[index];
          return _ArtistListTile(
            artist: artist,
            horizontalPadding: padding,
            onTap: () => _openArtist(artist),
            playlists: _displayPlaylists,
            albums: _albums,
            artists: _artists,
            currentLibraryView: _selectedTab,
            currentNavIndex: 2,
          );
        },
      ),
    );
  }

  Widget _buildLoadingIndicator(
    bool isLoading, {
    double horizontalPadding = 0,
  }) {
    if (!isLoading) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 16),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildErrorWidget(String error, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: TextStyle(color: Colors.grey[400], fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music_outlined, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }

  void _openPlaylist(GenericPlaylist playlist) {
    AppNavigation.instance.openSharedList(
      context,
      id: playlist.id,
      type: SharedListType.playlist,
      initialTitle: playlist.title,
      initialThumbnailUrl: playlist.thumbnailUrl,
    );
  }

  void _openAlbum(GenericAlbum album) {
    AppNavigation.instance.openSharedList(
      context,
      id: album.id,
      type: SharedListType.album,
      initialTitle: album.title,
      initialThumbnailUrl: album.thumbnailUrl,
    );
  }

  void _openArtist(GenericSimpleArtist artist) {
    AppNavigation.instance.openArtist(
      context,
      artistId: artist.id,
      initialArtist: artist,
    );
  }
}

class _PlaylistListTile extends StatelessWidget {
  final GenericPlaylist playlist;
  final double horizontalPadding;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;
  final Widget? trailing;
  final EdgeInsetsGeometry? contentPadding;

  const _PlaylistListTile({
    required this.playlist,
    required this.horizontalPadding,
    required this.onTap,
    required this.playlists,
    required this.albums,
    required this.artists,
    this.currentLibraryView,
    this.currentNavIndex,
    this.trailing,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return GestureDetector(
      onSecondaryTapDown: isDesktop
          ? (details) {
              EntityContextMenus.showPlaylistMenu(
                context,
                playlist: playlist,
                globalPosition: details.globalPosition,
              );
            }
          : null,
      onLongPress: isDesktop
          ? null
          : () {
              EntityContextMenus.showPlaylistMenu(
                context,
                playlist: playlist,
              );
            },
      child: ListTile(
        onTap: onTap,
        contentPadding:
            contentPadding ??
            EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 0),
        trailing: trailing,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 56,
            height: 56,
            child: _buildPlaylistThumbnail(playlist),
          ),
        ),
        title: Text(
          playlist.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Playlist • ${playlist.author.displayName}',
          style: TextStyle(color: Colors.grey[400]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

enum _PlaylistListEntryType { folder, playlist, unassignedHeader }

class _PlaylistListEntry {
  final _PlaylistListEntryType type;
  final PlaylistFolder? folder;
  final GenericPlaylist? playlist;
  final String? folderId;

  const _PlaylistListEntry._({
    required this.type,
    this.folder,
    this.playlist,
    this.folderId,
  });

  const _PlaylistListEntry.folder(PlaylistFolder folder)
      : this._(type: _PlaylistListEntryType.folder, folder: folder);

  const _PlaylistListEntry.playlist(
    GenericPlaylist playlist, {
    required String? folderId,
  }) : this._(
          type: _PlaylistListEntryType.playlist,
          playlist: playlist,
          folderId: folderId,
        );

  const _PlaylistListEntry.unassignedHeader()
      : this._(type: _PlaylistListEntryType.unassignedHeader);
}

class _PlaylistDragData {
  final String playlistId;
  final String? folderId;

  const _PlaylistDragData(this.playlistId, this.folderId);
}

class _FolderDragData {
  final String folderId;

  const _FolderDragData(this.folderId);
}

class _UnassignedHeader extends StatelessWidget {
  final double horizontalPadding;
  final bool enabled;
  final ValueChanged<String> onDrop;

  const _UnassignedHeader({
    required this.horizontalPadding,
    required this.enabled,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: EdgeInsets.only(
        left: horizontalPadding,
        right: horizontalPadding,
        top: 6,
        bottom: 6,
      ),
      child: Text(
        'UNASSIGNED',
        style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );

    if (!enabled) return child;

    return DragTarget<_PlaylistDragData>(
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

class _FolderListTile extends StatefulWidget {
  final PlaylistFolder folder;
  final double horizontalPadding;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;
  final int playlistCount;
  final bool enableDrag;
  final ValueChanged<String> onFolderDrop;
  final ValueChanged<String> onFolderReorder;

  const _FolderListTile({
    required this.folder,
    required this.horizontalPadding,
    required this.playlists,
    required this.albums,
    required this.artists,
    required this.currentLibraryView,
    required this.currentNavIndex,
    required this.enableDrag,
    required this.playlistCount,
    required this.onFolderDrop,
    required this.onFolderReorder,
  });

  @override
  State<_FolderListTile> createState() => _FolderListTileState();
}

class _FolderListTileState extends State<_FolderListTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final folderState = context.watch<LibraryFolderState>();
    final isCollapsed = folderState.isFolderCollapsed(widget.folder.id);
    final tile = GestureDetector(
      onSecondaryTapDown: isDesktop
          ? (details) {
              EntityContextMenus.showFolderMenu(
                context,
                folder: widget.folder,
                globalPosition: details.globalPosition,
              );
            }
          : null,
      onLongPress: isDesktop
          ? null
          : () {
              EntityContextMenus.showFolderMenu(
                context,
                folder: widget.folder,
              );
            },
      child: ListTile(
        onTap: () {
          folderState.toggleFolderCollapsed(widget.folder.id);
        },
        contentPadding: EdgeInsets.symmetric(
          horizontal: widget.horizontalPadding,
          vertical: 4,
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 56,
            height: 56,
            child: widget.folder.thumbnailPath != null
                ? Image.file(
                    File(widget.folder.thumbnailPath!),
                    fit: BoxFit.cover,
                  )
                : Container(
                    color: Colors.grey[800],
                    child: Icon(Icons.folder, color: Colors.grey[600]),
                  ),
          ),
        ),
        title: Text(
          widget.folder.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${widget.playlistCount} playlist${widget.playlistCount == 1 ? '' : 's'}',
          style: TextStyle(color: Colors.grey[400]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.enableDrag && !isDesktop)
              const Icon(Icons.drag_handle, color: Colors.grey),
            Icon(
              isCollapsed ? Icons.chevron_right : Icons.expand_more,
              color: Colors.grey[500],
            ),
          ],
        ),
      ),
    );

    if (!widget.enableDrag) {
      return tile;
    }

    final draggable = LongPressDraggable<_FolderDragData>(
      delay: const Duration(milliseconds: 150),
      data: _FolderDragData(widget.folder.id),
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: _DragFeedback(title: widget.folder.title, icon: Icons.folder),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );

    final reorderTarget = DragTarget<_FolderDragData>(
      onWillAccept: (data) {
        final accept = data != null && data.folderId != widget.folder.id;
        if (accept != _isHovered) {
          setState(() => _isHovered = accept);
        }
        return accept;
      },
      onLeave: (_) => setState(() => _isHovered = false),
      onAccept: (data) {
        setState(() => _isHovered = false);
        widget.onFolderReorder(data.folderId);
      },
      builder: (context, candidate, rejected) {
        return Container(
          decoration: _isHovered
              ? BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: draggable,
        );
      },
    );

    final playlistDropTarget = DragTarget<_PlaylistDragData>(
      onWillAccept: (data) => data != null,
      onAccept: (data) => widget.onFolderDrop(data.playlistId),
      builder: (context, candidate, rejected) {
        return Container(
          decoration: candidate.isNotEmpty
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                )
              : null,
          child: reorderTarget,
        );
      },
    );

    return playlistDropTarget;
  }
}

class _DraggablePlaylistTile extends StatelessWidget {
  final GenericPlaylist playlist;
  final double horizontalPadding;
  final String? folderId;
  final bool enableDrag;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;
  final VoidCallback onTap;
  final ValueChanged<String> onPlaylistDrop;

  const _DraggablePlaylistTile({
    required this.playlist,
    required this.horizontalPadding,
    required this.folderId,
    required this.enableDrag,
    required this.playlists,
    required this.albums,
    required this.artists,
    required this.currentLibraryView,
    required this.currentNavIndex,
    required this.onTap,
    required this.onPlaylistDrop,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    Widget tile = _PlaylistListTile(
      playlist: playlist,
      horizontalPadding: horizontalPadding,
      onTap: onTap,
      playlists: playlists,
      albums: albums,
      artists: artists,
      currentLibraryView: currentLibraryView,
      currentNavIndex: currentNavIndex,
      trailing: enableDrag && !isDesktop
          ? const Icon(Icons.drag_handle, color: Colors.grey)
          : null,
      contentPadding: EdgeInsets.only(
        left: horizontalPadding + (folderId != null ? 20 : 0),
        right: horizontalPadding,
        top: 4,
        bottom: 4,
      ),
    );

    if (!enableDrag) {
      return tile;
    }

    final draggable = LongPressDraggable<_PlaylistDragData>(
      delay: const Duration(milliseconds: 150),
      data: _PlaylistDragData(playlist.id, folderId),
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: _DragFeedback(title: playlist.title, icon: Icons.playlist_play),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );

    final reorderTarget = DragTarget<_PlaylistDragData>(
      onWillAccept: (data) => data != null && data.playlistId != playlist.id,
      onAccept: (data) => onPlaylistDrop(data.playlistId),
      builder: (context, candidate, rejected) {
        return Container(
          decoration: candidate.isNotEmpty
              ? BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: draggable,
        );
      },
    );

    return reorderTarget;
  }
}

class _DragFeedback extends StatelessWidget {
  final String title;
  final IconData icon;

  const _DragFeedback({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _AlbumListTile extends StatelessWidget {
  final GenericAlbum album;
  final double horizontalPadding;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _AlbumListTile({
    required this.album,
    required this.horizontalPadding,
    required this.onTap,
    required this.playlists,
    required this.albums,
    required this.artists,
    this.currentLibraryView,
    this.currentNavIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return GestureDetector(
      onSecondaryTapDown: isDesktop
          ? (details) {
              EntityContextMenus.showAlbumMenu(
                context,
                album: album,
                globalPosition: details.globalPosition,
              );
            }
          : null,
      onLongPress: isDesktop
          ? null
          : () {
              EntityContextMenus.showAlbumMenu(
                context,
                album: album,
              );
            },
      child: ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 4,
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 56,
            height: 56,
            child: album.thumbnailUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: album.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[800]),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[800],
                      child: Icon(Icons.album, color: Colors.grey[600]),
                    ),
                  )
                : Container(
                    color: Colors.grey[800],
                    child: Icon(Icons.album, color: Colors.grey[600]),
                  ),
          ),
        ),
        title: Text(
          album.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Album • ${album.artists.map((a) => a.name).join(', ')}',
          style: TextStyle(color: Colors.grey[400]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ArtistListTile extends StatelessWidget {
  final GenericSimpleArtist artist;
  final double horizontalPadding;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _ArtistListTile({
    required this.artist,
    required this.horizontalPadding,
    required this.onTap,
    required this.playlists,
    required this.albums,
    required this.artists,
    this.currentLibraryView,
    this.currentNavIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return GestureDetector(
      onSecondaryTapDown: isDesktop
          ? (details) {
              EntityContextMenus.showArtistMenu(
                context,
                artist: artist,
                globalPosition: details.globalPosition,
              );
            }
          : null,
      onLongPress: isDesktop
          ? null
          : () {
              EntityContextMenus.showArtistMenu(
                context,
                artist: artist,
              );
            },
      child: ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 4,
        ),
        leading: ClipOval(
          child: SizedBox(
            width: 56,
            height: 56,
            child: artist.thumbnailUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: artist.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[800]),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[800],
                      child: Icon(Icons.person, color: Colors.grey[600]),
                    ),
                  )
                : Container(
                    color: Colors.grey[800],
                    child: Icon(Icons.person, color: Colors.grey[600]),
                  ),
          ),
        ),
        title: Text(
          artist.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('Artist', style: TextStyle(color: Colors.grey[400])),
      ),
    );
  }
}
