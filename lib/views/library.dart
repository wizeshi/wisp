/// Library view with paginated tabs for playlists, albums, and artists
library;

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/metadata/spotify.dart';
import '../models/metadata_models.dart';
import '../widgets/navigation.dart';
import '../widgets/library_item_context_menu.dart';
import 'list_detail.dart';
import 'artist_detail.dart';

class LibraryTabView extends StatefulWidget {
  final List<GenericPlaylist> initialPlaylists;
  final List<GenericAlbum> initialAlbums;
  final List<GenericSimpleArtist> initialArtists;

  const LibraryTabView({
    super.key,
    required this.initialPlaylists,
    required this.initialAlbums,
    required this.initialArtists,
  });

  @override
  State<LibraryTabView> createState() => _LibraryTabViewState();
}

class _LibraryTabViewState extends State<LibraryTabView> {
  LibraryView _selectedTab = LibraryView.playlists;

  final _playlistScrollController = ScrollController();
  final _albumScrollController = ScrollController();
  final _artistScrollController = ScrollController();

  List<GenericPlaylist> _playlists = [];
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

  @override
  void initState() {
    super.initState();
    _playlists = List.from(widget.initialPlaylists);
    _albums = List.from(widget.initialAlbums);
    _artists = List.from(widget.initialArtists);

    _playlistScrollController.addListener(_onPlaylistScroll);
    _albumScrollController.addListener(_onAlbumScroll);
    _artistScrollController.addListener(_onArtistScroll);
  }

  @override
  void dispose() {
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

  Future<void> _loadMorePlaylists() async {
    if (_isLoadingPlaylists || !_hasMorePlaylists) return;

    setState(() => _isLoadingPlaylists = true);

    final spotify = context.read<SpotifyProvider>();

    try {
      final morePlaylists = await spotify.getUserPlaylists(
        limit: 50,
        offset: _playlists.length,
      );

      if (mounted) {
        setState(() {
          _playlists.addAll(morePlaylists);
          _hasMorePlaylists = morePlaylists.length == 50;
          _isLoadingPlaylists = false;
          _playlistError = null;
        });
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

  Future<void> _loadMoreAlbums() async {
    if (_isLoadingAlbums || !_hasMoreAlbums) return;

    setState(() => _isLoadingAlbums = true);

    final spotify = context.read<SpotifyProvider>();

    try {
      final moreAlbums = await spotify.getUserAlbums(
        limit: 50,
        offset: _albums.length,
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

  Future<void> _loadMoreArtists() async {
    if (_isLoadingArtists || !_hasMoreArtists) return;

    setState(() => _isLoadingArtists = true);

    final spotify = context.read<SpotifyProvider>();

    try {
      final moreArtists = await spotify.getUserFollowedArtists(
        limit: 50,
        after: _artists.isNotEmpty ? _artists.last.id : null,
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

  Future<void> _refreshPlaylists() async {
    setState(() {
      _playlists = [];
      _hasMorePlaylists = true;
      _playlistError = null;
    });
    await _loadMorePlaylists();
  }

  Future<void> _refreshAlbums() async {
    setState(() {
      _albums = [];
      _hasMoreAlbums = true;
      _albumError = null;
    });
    await _loadMoreAlbums();
  }

  Future<void> _refreshArtists() async {
    setState(() {
      _artists = [];
      _hasMoreArtists = true;
      _artistError = null;
    });
    await _loadMoreArtists();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final padding = isMobile ? 20.0 : 16.0;

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
                  const Text(
                    'Your Library',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
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
          _buildTabChip(LibraryView.playlists, 'Playlists', _playlists.length),
          const SizedBox(width: 8),
          _buildTabChip(LibraryView.albums, 'Albums', _albums.length),
          const SizedBox(width: 8),
          _buildTabChip(LibraryView.artists, 'Artists', _artists.length),
        ],
      ),
    );
  }

  Widget _buildTabChip(LibraryView tab, String label, int count) {
    final isSelected = _selectedTab == tab;
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      child: FilterChip(
        label: Text(
          '$label ($count)',
          style: TextStyle(
            color: isSelected ? colorScheme.onPrimary : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _selectedTab = tab);
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
      case LibraryView.albums:
        return _buildAlbumsContent(padding);
      case LibraryView.artists:
        return _buildArtistsContent(padding);
    }
  }

  Widget _buildPlaylistsContent(double padding) {
    if (_playlistError != null && _playlists.isEmpty) {
      return _buildErrorWidget(_playlistError!, _refreshPlaylists);
    }

    if (_playlists.isEmpty && !_isLoadingPlaylists) {
      return _buildEmptyState('No playlists in your library');
    }

    return RefreshIndicator(
      onRefresh: _refreshPlaylists,
      child: ListView.builder(
        key: const ValueKey('playlists'),
        controller: _playlistScrollController,
        padding: EdgeInsets.all(padding),
        itemCount:
            _playlists.length +
            (_hasMorePlaylists || _isLoadingPlaylists ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _playlists.length) {
            return _buildLoadingIndicator(_isLoadingPlaylists);
          }

          final playlist = _playlists[index];
          return _PlaylistListTile(
            playlist: playlist,
            onTap: () => _openPlaylist(playlist),
            playlists: _playlists,
            albums: _albums,
            artists: _artists,
            currentLibraryView: _selectedTab,
            currentNavIndex: 2,
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
        padding: EdgeInsets.all(padding),
        itemCount:
            _albums.length + (_hasMoreAlbums || _isLoadingAlbums ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _albums.length) {
            return _buildLoadingIndicator(_isLoadingAlbums);
          }

          final album = _albums[index];
          return _AlbumListTile(
            album: album,
            onTap: () => _openAlbum(album),
            playlists: _playlists,
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
        padding: EdgeInsets.all(padding),
        itemCount:
            _artists.length + (_hasMoreArtists || _isLoadingArtists ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _artists.length) {
            return _buildLoadingIndicator(_isLoadingArtists);
          }

          final artist = _artists[index];
          return _ArtistListTile(
            artist: artist,
            onTap: () => _openArtist(artist),
            playlists: _playlists,
            albums: _albums,
            artists: _artists,
            currentLibraryView: _selectedTab,
            currentNavIndex: 2,
          );
        },
      ),
    );
  }

  Widget _buildLoadingIndicator(bool isLoading) {
    if (!isLoading) return const SizedBox.shrink();

    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            SharedListDetailView(
              id: playlist.id,
              type: SharedListType.playlist,
              initialTitle: playlist.title,
              initialThumbnailUrl: playlist.thumbnailUrl,
              playlists: _playlists,
              albums: _albums,
              artists: _artists,
              initialLibraryView: LibraryView.playlists,
              initialNavIndex: 2,
            ),
      ),
    );
  }

  void _openAlbum(GenericAlbum album) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            SharedListDetailView(
              id: album.id,
              type: SharedListType.album,
              initialTitle: album.title,
              initialThumbnailUrl: album.thumbnailUrl,
              playlists: _playlists,
              albums: _albums,
              artists: _artists,
              initialLibraryView: LibraryView.albums,
              initialNavIndex: 2,
            ),
      ),
    );
  }

  void _openArtist(GenericSimpleArtist artist) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ArtistDetailView(
              artistId: artist.id,
              initialArtist: artist,
              playlists: _playlists,
              albums: _albums,
              artists: _artists,
              initialLibraryView: LibraryView.artists,
              initialNavIndex: 2,
            ),
      ),
    );
  }
}

class _PlaylistListTile extends StatelessWidget {
  final GenericPlaylist playlist;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _PlaylistListTile({
    required this.playlist,
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
              LibraryItemContextMenu.show(
                context: context,
                item: playlist,
                position: details.globalPosition,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: currentLibraryView,
                currentNavIndex: currentNavIndex,
              );
            }
          : null,
      onLongPress: isDesktop
          ? null
          : () {
              LibraryItemContextMenu.show(
                context: context,
                item: playlist,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: currentLibraryView,
                currentNavIndex: currentNavIndex,
              );
            },
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 56,
            height: 56,
            child: playlist.thumbnailUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: playlist.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[800]),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[800],
                      child: Icon(Icons.playlist_play, color: Colors.grey[600]),
                    ),
                  )
                : Container(
                    color: Colors.grey[800],
                    child: Icon(Icons.playlist_play, color: Colors.grey[600]),
                  ),
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

class _AlbumListTile extends StatelessWidget {
  final GenericAlbum album;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _AlbumListTile({
    required this.album,
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
              LibraryItemContextMenu.show(
                context: context,
                item: album,
                position: details.globalPosition,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: currentLibraryView,
                currentNavIndex: currentNavIndex,
              );
            }
          : null,
      onLongPress: isDesktop
          ? null
          : () {
              LibraryItemContextMenu.show(
                context: context,
                item: album,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: currentLibraryView,
                currentNavIndex: currentNavIndex,
              );
            },
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
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
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _ArtistListTile({
    required this.artist,
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
              LibraryItemContextMenu.show(
                context: context,
                item: artist,
                position: details.globalPosition,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: currentLibraryView,
                currentNavIndex: currentNavIndex,
              );
            }
          : null,
      onLongPress: isDesktop
          ? null
          : () {
              LibraryItemContextMenu.show(
                context: context,
                item: artist,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: currentLibraryView,
                currentNavIndex: currentNavIndex,
              );
            },
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
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
