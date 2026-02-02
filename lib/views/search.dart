/// Search view with debounced search and tabbed results
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/metadata/spotify.dart';
import '../providers/audio/player.dart';
import '../models/metadata_models.dart';
import '../widgets/navigation.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/library_item_context_menu.dart';
import '../widgets/hover_underline.dart';
import '../providers/search/search_state.dart';
import 'list_detail.dart';
import 'artist_detail.dart';

enum SearchTab { tracks, artists, albums, playlists }

class SearchView extends StatefulWidget {
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? initialLibraryView;
  final int? currentNavIndex;
  final VoidCallback? onOpenSettings;

  const SearchView({
    super.key,
    required this.playlists,
    required this.albums,
    required this.artists,
    this.initialLibraryView,
    this.currentNavIndex,
    this.onOpenSettings,
  });

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  late final TextEditingController _searchController;
  final _scrollController = ScrollController();
  Timer? _debounceTimer;
  late final SearchState _searchState;
  int _lastSubmitSignal = 0;

  SearchTab _selectedTab = SearchTab.tracks;
  bool _isLoading = false;
  String? _error;
  String _lastQuery = '';

  List<GenericSong> _tracks = [];
  List<GenericSimpleArtist> _artists = [];
  List<GenericAlbum> _albums = [];
  List<GenericPlaylist> _playlists = [];
  String _selectedSource = 'Spotify';
  int _hoveredSongIndex = -1;
  bool _isBestMatchHovered = false;
  String? _activePlayContext;

  @override
  void initState() {
    super.initState();
    _searchState = context.read<SearchState>();
    _searchController = _searchState.controller;
    _lastSubmitSignal = _searchState.submitSignal;
    _searchController.addListener(_onSearchChanged);
    _searchState.addListener(_onSearchSubmitted);

    final initialQuery = _searchController.text.trim();
    if (initialQuery.isNotEmpty) {
      _performSearch(initialQuery);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchState.removeListener(_onSearchSubmitted);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 750), () {
      final query = _searchController.text.trim();
      if (query.isEmpty && _lastQuery.isNotEmpty) {
        _clearResults();
        return;
      }
      if (query.isNotEmpty && query != _lastQuery) {
        _performSearch(query);
      }
    });
  }

  void _onSearchSubmitted() {
    if (_lastSubmitSignal == _searchState.submitSignal) return;
    _lastSubmitSignal = _searchState.submitSignal;
    _debounceTimer?.cancel();

    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _performSearch(query);
    } else {
      _clearResults();
    }
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _lastQuery = query;
    });

    final spotify = context.read<SpotifyProvider>();

    try {
      final results = await Future.wait([
        spotify.search(query, type: 'track', limit: 20),
        spotify.search(query, type: 'artist', limit: 20),
        spotify.search(query, type: 'album', limit: 20),
        spotify.search(query, type: 'playlist', limit: 20),
      ]);

      if (mounted) {
        setState(() {
          _tracks = List<GenericSong>.from(results[0]);
          _artists = List<GenericSimpleArtist>.from(results[1]);
          _albums = List<GenericAlbum>.from(results[2]);
          _playlists = List<GenericPlaylist>.from(results[3]);
          _isLoading = false;
        });
        // Reset scroll position when results change
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _clearSearch() {
    _searchState.clear();
  }

  void _clearResults() {
    setState(() {
      _lastQuery = '';
      _tracks = [];
      _artists = [];
      _albums = [];
      _playlists = [];
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final padding = isMobile ? 20.0 : 16.0;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Search header
          Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMobile) ...[
                  const Text(
                    'Search',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSearchField(),
                ] else ...[
                  if (_lastQuery.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Search results for "$_lastQuery"',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        _buildSourceSelector(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(color: Colors.grey[800]),
                  ],
                  if (_searchController.text.trim().isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Type in the titlebar search to begin',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ),
                ],
              ],
            ),
          ),
          // Tab chips (mobile only)
          if (isMobile && _lastQuery.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: _buildTabChips(),
            ),
          // Results
          Expanded(child: _buildContent(padding)),
        ],
      ),
    );
  }

  Widget _buildSourceSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSource,
          dropdownColor: const Color(0xFF181818),
          iconEnabledColor: Colors.grey[400],
          items: const [
            DropdownMenuItem(
              value: 'Spotify',
              child: Text('Spotify', style: TextStyle(color: Colors.white)),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedSource = value);
          },
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'What do you want to listen to?',
        hintStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.clear, color: Colors.grey[400]),
                onPressed: _clearSearch,
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF282828),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (value) {
        _searchState.submit();
      },
    );
  }

  Widget _buildTabChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: SearchTab.values.map((tab) {
          final isSelected = _selectedTab == tab;
          final count = _getCountForTab(tab);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              child: FilterChip(
                label: Text(
                  '${_getLabelForTab(tab)} ($count)',
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() => _selectedTab = tab);
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(0);
                  }
                },
                backgroundColor: const Color(0xFF282828),
                selectedColor: const Color(0xFF1DB954),
                checkmarkColor: Colors.black,
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getLabelForTab(SearchTab tab) {
    switch (tab) {
      case SearchTab.tracks:
        return 'Tracks';
      case SearchTab.artists:
        return 'Artists';
      case SearchTab.albums:
        return 'Albums';
      case SearchTab.playlists:
        return 'Playlists';
    }
  }

  int _getCountForTab(SearchTab tab) {
    switch (tab) {
      case SearchTab.tracks:
        return _tracks.length;
      case SearchTab.artists:
        return _artists.length;
      case SearchTab.albums:
        return _albums.length;
      case SearchTab.playlists:
        return _playlists.length;
    }
  }

  Widget _buildContent(double padding) {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    if (_lastQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'Search for songs, artists, albums, or playlists',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorWidget();
    }

    if (!isMobile) {
      return _buildDesktopResults(padding);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _buildResultsList(padding),
    );
  }

  Widget _buildDesktopResults(double padding) {
    if (_tracks.isEmpty &&
        _albums.isEmpty &&
        _artists.isEmpty &&
        _playlists.isEmpty) {
      return _buildEmptyState('No results found');
    }

    final bestMatch = _tracks.isNotEmpty ? _tracks.first : null;
    final songsToDisplay = _tracks.length > 1
        ? _tracks.skip(1).take(8).toList()
        : <GenericSong>[];
    final songsListHeight = _calculateSongsListHeight(songsToDisplay.length);

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth - 16; // minus gap
              final flexBasedWidth = availableWidth * 4 / 11;
              final bestMatchWidth = flexBasedWidth < songsListHeight
                  ? flexBasedWidth
                  : songsListHeight;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: bestMatchWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Best Match',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildBestMatchCard(
                          bestMatch,
                          maxWidth: songsListHeight,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _buildSongsCard(songsToDisplay)),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey[800]),
          const SizedBox(height: 16),
          _buildHorizontalSection('Albums', _albums.take(10).toList()),
          const SizedBox(height: 16),
          _buildHorizontalSection('Playlists', _playlists.take(10).toList()),
          const SizedBox(height: 16),
          _buildHorizontalSection('Artists', _artists.take(10).toList()),
        ],
      ),
    );
  }

  Widget _buildBestMatchCard(GenericSong? track, {required double maxWidth}) {
    if (track == null) {
      return _buildEmptyState('No best match');
    }

    final player = context.watch<AudioPlayerProvider>();
    final isCurrentPlaying =
        player.isPlaying && player.currentTrack?.id == track.id;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < maxWidth
            ? constraints.maxWidth
            : maxWidth;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: maxWidth),
          child: MouseRegion(
            onEnter: (_) => setState(() => _isBestMatchHovered = true),
            onExit: (_) => setState(() => _isBestMatchHovered = false),
            cursor: SystemMouseCursors.click,
            opaque: true,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                GestureDetector(
                  onTap: () => _openAlbumFromTrack(track),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: track.thumbnailUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: track.thumbnailUrl,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            color: Colors.grey[900],
                                            child: Icon(
                                              Icons.music_note,
                                              color: Colors.grey[600],
                                              size: 48,
                                            ),
                                          ),
                                  ),
                                  if (_isBestMatchHovered)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.black.withOpacity(0.45),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          track.title,
                          style: TextStyle(
                            color: isCurrentPlaying
                                ? const Color(0xFF1DB954)
                                : Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artists.map((a) => a.name).join(', '),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isBestMatchHovered)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: FloatingActionButton(
                      heroTag: 'bestMatchPlay',
                      mini: true,
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.black,
                      onPressed: () => _toggleTrackPlayback(track, 0),
                      child: Icon(
                        isCurrentPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongsCard(List<GenericSong> songs) {
    final player = context.watch<AudioPlayerProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Songs',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: songs.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No songs found',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  ]
                : songs.asMap().entries.map((entry) {
                    final displayIndex = entry.key + 1;
                    final song = entry.value;
                    final isEven = displayIndex % 2 == 0;
                    final isHovered = _hoveredSongIndex == displayIndex;
                    final isCurrentPlaying =
                        player.isPlaying && player.currentTrack?.id == song.id;
                    return Material(
                      color: Colors.transparent,
                      child: MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoveredSongIndex = displayIndex),
                        onExit: (_) => setState(() => _hoveredSongIndex = -1),
                        cursor: SystemMouseCursors.click,
                        child: InkWell(
                          onTap: () => _playSearchQueue(displayIndex),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isEven
                                  ? Colors.black.withOpacity(0.2)
                                  : Colors.transparent,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: song.thumbnailUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: song.thumbnailUrl,
                                                  fit: BoxFit.cover,
                                                )
                                              : Container(
                                                  color: Colors.grey[900],
                                                  child: Icon(
                                                    Icons.music_note,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                        ),
                                        if (isHovered)
                                          Positioned.fill(
                                            child: Container(
                                              color: Colors.black.withOpacity(
                                                0.45,
                                              ),
                                            ),
                                          ),
                                        if (isHovered)
                                          Positioned.fill(
                                            child: InkWell(
                                              onTap: () => _toggleTrackPlayback(
                                                song,
                                                displayIndex,
                                              ),
                                              child: Icon(
                                                isCurrentPlaying
                                                    ? Icons.pause
                                                    : Icons.play_arrow,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        style: TextStyle(
                                          color:
                                              player.currentTrack?.id == song.id
                                              ? const Color(0xFF1DB954)
                                              : Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        song.artists
                                            .map((a) => a.name)
                                            .join(', '),
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _formatDuration(song.durationSecs),
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalSection(String title, List<dynamic> items) {
    final player = context.watch<AudioPlayerProvider>();
    final isPaused = player.state == PlaybackState.paused;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              if (item is GenericAlbum) {
                final isActiveContext =
                    _activePlayContext == 'album:${item.id}';
                return _MiniAlbumCard(
                  album: item,
                  playlists: widget.playlists,
                  albums: widget.albums,
                  artists: widget.artists,
                  initialLibraryView:
                      widget.initialLibraryView ?? LibraryView.albums,
                  isActiveContext: isActiveContext,
                  isPlaying: player.isPlaying,
                  isPaused: isPaused,
                  onPlay: () => _playAlbum(context, item.id),
                );
              }
              if (item is GenericPlaylist) {
                final isActiveContext =
                    _activePlayContext == 'playlist:${item.id}';
                return _MiniPlaylistCard(
                  playlist: item,
                  playlists: widget.playlists,
                  albums: widget.albums,
                  artists: widget.artists,
                  initialLibraryView:
                      widget.initialLibraryView ?? LibraryView.playlists,
                  isActiveContext: isActiveContext,
                  isPlaying: player.isPlaying,
                  isPaused: isPaused,
                  onPlay: () => _playPlaylist(context, item.id),
                );
              }
              if (item is GenericSimpleArtist) {
                final isActiveContext =
                    _activePlayContext == 'artist:${item.id}';
                return _MiniArtistCard(
                  artist: item,
                  playlists: widget.playlists,
                  albums: widget.albums,
                  artists: widget.artists,
                  initialLibraryView:
                      widget.initialLibraryView ?? LibraryView.artists,
                  isActiveContext: isActiveContext,
                  isPlaying: player.isPlaying,
                  isPaused: isPaused,
                  onPlay: () => _playArtist(context, item.id),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  void _playSearchQueue(int index) {
    final player = context.read<AudioPlayerProvider>();
    if (_tracks.isEmpty) return;
    setState(() {
      _activePlayContext = 'song:${_tracks[index].id}';
    });
    player.setQueue(
      _tracks,
      startIndex: index,
      play: true,
      contextType: 'search',
      contextName: 'Search results',
    );
  }

  void _toggleTrackPlayback(GenericSong track, int index) {
    final player = context.read<AudioPlayerProvider>();
    if (player.currentTrack?.id == track.id) {
      if (player.isPlaying) {
        player.pause();
        return;
      }
      if (player.state == PlaybackState.paused) {
        player.play();
        return;
      }
    }
    _playSearchQueue(index);
  }

  Future<void> _playAlbum(BuildContext context, String albumId) async {
    final spotify = context.read<SpotifyProvider>();
    final player = context.read<AudioPlayerProvider>();
    try {
      final album = await spotify.getAlbumInfo(albumId);
      final tracks = album.songs ?? [];
      if (tracks.isEmpty) return;
      if (mounted) {
        setState(() => _activePlayContext = 'album:$albumId');
      }
      await player.setQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'album',
        contextName: album.title,
      );
    } catch (_) {}
  }

  Future<void> _playPlaylist(BuildContext context, String playlistId) async {
    final spotify = context.read<SpotifyProvider>();
    final player = context.read<AudioPlayerProvider>();
    try {
      final playlist = await spotify.getPlaylistInfo(playlistId);
      final items = playlist.songs ?? [];
      if (items.isEmpty) return;
      if (mounted) {
        setState(() => _activePlayContext = 'playlist:$playlistId');
      }
      final tracks = items
          .map(
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
          .toList();
      await player.setQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'playlist',
        contextName: playlist.title,
      );
    } catch (_) {}
  }

  Future<void> _playArtist(BuildContext context, String artistId) async {
    final spotify = context.read<SpotifyProvider>();
    final player = context.read<AudioPlayerProvider>();
    try {
      final artist = await spotify.getArtistInfo(artistId);
      final tracks = artist.topSongs;
      if (tracks.isEmpty) return;
      if (mounted) {
        setState(() => _activePlayContext = 'artist:$artistId');
      }
      await player.setQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'artist',
        contextName: artist.name,
      );
    } catch (_) {}
  }

  double _calculateSongsListHeight(int songCount) {
    if (songCount <= 0) return 64;
    return songCount * 60.0;
  }

  void _openAlbumFromTrack(GenericSong track) {
    final album = track.album;
    if (album == null) return;
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
              playlists: widget.playlists,
              albums: widget.albums,
              artists: widget.artists,
              initialLibraryView:
                  widget.initialLibraryView ?? LibraryView.albums,
              initialNavIndex: 1,
            ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildErrorWidget() {
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
            _error!,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _performSearch(_lastQuery),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(double padding) {
    switch (_selectedTab) {
      case SearchTab.tracks:
        return _buildTracksList(padding);
      case SearchTab.artists:
        return _buildArtistsList(padding);
      case SearchTab.albums:
        return _buildAlbumsList(padding);
      case SearchTab.playlists:
        return _buildPlaylistsList(padding);
    }
  }

  Widget _buildTracksList(double padding) {
    if (_tracks.isEmpty) {
      return _buildEmptyState('No tracks found');
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(padding),
      itemCount: _tracks.length,
      itemExtent: 72,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        return _TrackTile(
          track: track,
          onTap: () async {
            final player = context.read<AudioPlayerProvider>();
            await player.playTrack(track);
          },
          playlists: widget.playlists,
          albums: widget.albums,
          artists: widget.artists,
          currentLibraryView: widget.initialLibraryView,
          currentNavIndex: widget.currentNavIndex,
        );
      },
    );
  }

  Widget _buildArtistsList(double padding) {
    if (_artists.isEmpty) {
      return _buildEmptyState('No artists found');
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(padding),
      itemCount: _artists.length,
      itemExtent: 72,
      itemBuilder: (context, index) {
        final artist = _artists[index];
        return _ArtistTile(
          artist: artist,
          playlists: widget.playlists,
          albums: widget.albums,
          artists: widget.artists,
          currentLibraryView: widget.initialLibraryView,
          currentNavIndex: widget.currentNavIndex,
          onTap: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (context, animation, secondaryAnimation) =>
                    ArtistDetailView(
                      artistId: artist.id,
                      initialArtist: artist,
                      playlists: widget.playlists,
                      albums: widget.albums,
                      artists: widget.artists,
                      initialLibraryView:
                          widget.initialLibraryView ?? LibraryView.artists,
                      initialNavIndex: 1,
                    ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAlbumsList(double padding) {
    if (_albums.isEmpty) {
      return _buildEmptyState('No albums found');
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(padding),
      itemCount: _albums.length,
      itemExtent: 72,
      itemBuilder: (context, index) {
        final album = _albums[index];
        return _AlbumTile(
          album: album,
          playlists: widget.playlists,
          albums: widget.albums,
          artists: widget.artists,
          currentLibraryView: widget.initialLibraryView,
          currentNavIndex: widget.currentNavIndex,
          onTap: () {
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
                      playlists: widget.playlists,
                      albums: widget.albums,
                      artists: widget.artists,
                      initialLibraryView:
                          widget.initialLibraryView ?? LibraryView.albums,
                      initialNavIndex: 1,
                    ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistsList(double padding) {
    if (_playlists.isEmpty) {
      return _buildEmptyState('No playlists found');
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(padding),
      itemCount: _playlists.length,
      itemExtent: 72,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        return _PlaylistTile(
          playlist: playlist,
          playlists: widget.playlists,
          albums: widget.albums,
          artists: widget.artists,
          currentLibraryView: widget.initialLibraryView,
          currentNavIndex: widget.currentNavIndex,
          onTap: () {
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
                      playlists: widget.playlists,
                      albums: widget.albums,
                      artists: widget.artists,
                      initialLibraryView:
                          widget.initialLibraryView ?? LibraryView.playlists,
                      initialNavIndex: 1,
                    ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final GenericSong track;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _TrackTile({
    required this.track,
    required this.onTap,
    required this.playlists,
    required this.albums,
    required this.artists,
    this.currentLibraryView,
    this.currentNavIndex,
  });

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    final album = track.album;
    final primaryArtist = track.artists.isNotEmpty ? track.artists.first : null;
    return GestureDetector(
      onSecondaryTapDown: _isDesktop
          ? (details) {
              TrackContextMenu.show(
                context: context,
                track: track,
                position: details.globalPosition,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: currentLibraryView,
                currentNavIndex: currentNavIndex,
              );
            }
          : null,
      onLongPress: _isDesktop
          ? null
          : () {
              TrackContextMenu.show(
                context: context,
                track: track,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: currentLibraryView,
                currentNavIndex: currentNavIndex,
              );
            },
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 52,
            height: 52,
            child: track.thumbnailUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: track.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[800]),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[800],
                      child: Icon(Icons.music_note, color: Colors.grey[600]),
                    ),
                  )
                : Container(
                    color: Colors.grey[800],
                    child: Icon(Icons.music_note, color: Colors.grey[600]),
                  ),
          ),
        ),
        title: (_isDesktop && album != null && album.id.isNotEmpty)
            ? HoverUnderline(
                onTap: () {
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
                            playlists: playlists,
                            albums: albums,
                            artists: artists,
                            initialLibraryView:
                                currentLibraryView ?? LibraryView.albums,
                            initialNavIndex: currentNavIndex ?? 1,
                          ),
                    ),
                  );
                },
                builder: (isHovering) => Text(
                  track.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    decoration: isHovering
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : Text(
                track.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        subtitle: (_isDesktop && primaryArtist != null)
            ? HoverUnderline(
                onTap: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          ArtistDetailView(
                            artistId: primaryArtist.id,
                            initialArtist: primaryArtist,
                            playlists: playlists,
                            albums: albums,
                            artists: artists,
                            initialLibraryView:
                                currentLibraryView ?? LibraryView.artists,
                            initialNavIndex: currentNavIndex ?? 1,
                          ),
                    ),
                  );
                },
                onSecondaryTapDown: (details) {
                  LibraryItemContextMenu.show(
                    context: context,
                    item: primaryArtist,
                    position: details.globalPosition,
                    playlists: playlists,
                    albums: albums,
                    artists: artists,
                    currentLibraryView: currentLibraryView,
                    currentNavIndex: currentNavIndex,
                  );
                },
                builder: (isHovering) => Text(
                  track.artists.map((a) => a.name).join(', '),
                  style: TextStyle(
                    color: Colors.grey[400],
                    decoration: isHovering
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : Text(
                track.artists.map((a) => a.name).join(', '),
                style: TextStyle(color: Colors.grey[400]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: null,
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  final GenericSimpleArtist artist;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _ArtistTile({
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
        leading: ClipOval(
          child: SizedBox(
            width: 52,
            height: 52,
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
        title: isDesktop
            ? HoverUnderline(
                onTap: onTap,
                builder: (isHovering) => Text(
                  artist.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    decoration: isHovering
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : Text(
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

class _AlbumTile extends StatelessWidget {
  final GenericAlbum album;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _AlbumTile({
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
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 52,
            height: 52,
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
        title: isDesktop
            ? HoverUnderline(
                onTap: onTap,
                builder: (isHovering) => Text(
                  album.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    decoration: isHovering
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : Text(
                album.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        subtitle: Text(
          album.artists.map((a) => a.name).join(', '),
          style: TextStyle(color: Colors.grey[400]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final GenericPlaylist playlist;
  final VoidCallback onTap;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView? currentLibraryView;
  final int? currentNavIndex;

  const _PlaylistTile({
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
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 52,
            height: 52,
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
        title: isDesktop
            ? HoverUnderline(
                onTap: onTap,
                builder: (isHovering) => Text(
                  playlist.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    decoration: isHovering
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : Text(
                playlist.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        subtitle: Text(
          playlist.author.displayName,
          style: TextStyle(color: Colors.grey[400]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _MiniAlbumCard extends StatelessWidget {
  final GenericAlbum album;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final VoidCallback onPlay;
  final LibraryView initialLibraryView;
  final bool isActiveContext;
  final bool isPlaying;
  final bool isPaused;

  const _MiniAlbumCard({
    required this.album,
    required this.playlists,
    required this.albums,
    required this.artists,
    required this.onPlay,
    required this.initialLibraryView,
    required this.isActiveContext,
    required this.isPlaying,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final hover = ValueNotifier(false);
    return InkWell(
      onLongPress: isDesktop
          ? null
          : () {
              LibraryItemContextMenu.show(
                context: context,
                item: album,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: initialLibraryView,
                currentNavIndex: 1,
              );
            },
      onTap: () {
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
                  playlists: playlists,
                  albums: albums,
                  artists: artists,
                  initialLibraryView: initialLibraryView,
                  initialNavIndex: 1,
                ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => hover.value = true,
        onExit: (_) => hover.value = false,
        child: ValueListenableBuilder<bool>(
          valueListenable: hover,
          builder: (context, isHovered, _) {
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Container(
                  width: 160,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: album.thumbnailUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: album.thumbnailUrl,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: Colors.grey[900],
                                        child: Icon(
                                          Icons.album,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                              ),
                              if (isHovered)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.35),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        album.artists.map((a) => a.name).join(', '),
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isHovered)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: FloatingActionButton(
                      heroTag: 'albumPlay_${album.id}',
                      mini: true,
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.black,
                      onPressed: () {
                        if (isActiveContext) {
                          if (isPlaying) {
                            context.read<AudioPlayerProvider>().pause();
                            return;
                          }
                          if (isPaused) {
                            context.read<AudioPlayerProvider>().play();
                            return;
                          }
                        }
                        onPlay();
                      },
                      child: Icon(
                        isActiveContext && isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MiniPlaylistCard extends StatelessWidget {
  final GenericPlaylist playlist;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final VoidCallback onPlay;
  final LibraryView initialLibraryView;
  final bool isActiveContext;
  final bool isPlaying;
  final bool isPaused;

  const _MiniPlaylistCard({
    required this.playlist,
    required this.playlists,
    required this.albums,
    required this.artists,
    required this.onPlay,
    required this.initialLibraryView,
    required this.isActiveContext,
    required this.isPlaying,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final hover = ValueNotifier(false);
    return InkWell(
      onLongPress: isDesktop
          ? null
          : () {
              LibraryItemContextMenu.show(
                context: context,
                item: playlist,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: initialLibraryView,
                currentNavIndex: 1,
              );
            },
      onTap: () {
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
                  playlists: playlists,
                  albums: albums,
                  artists: artists,
                  initialLibraryView: initialLibraryView,
                  initialNavIndex: 1,
                ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => hover.value = true,
        onExit: (_) => hover.value = false,
        child: ValueListenableBuilder<bool>(
          valueListenable: hover,
          builder: (context, isHovered, _) {
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Container(
                  width: 160,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: playlist.thumbnailUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: playlist.thumbnailUrl,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: Colors.grey[900],
                                        child: Icon(
                                          Icons.playlist_play,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                              ),
                              if (isHovered)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.35),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        playlist.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        playlist.author.displayName,
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isHovered)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: FloatingActionButton(
                      heroTag: 'playlistPlay_${playlist.id}',
                      mini: true,
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.black,
                      onPressed: () {
                        if (isActiveContext) {
                          if (isPlaying) {
                            context.read<AudioPlayerProvider>().pause();
                            return;
                          }
                          if (isPaused) {
                            context.read<AudioPlayerProvider>().play();
                            return;
                          }
                        }
                        onPlay();
                      },
                      child: Icon(
                        isActiveContext && isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MiniArtistCard extends StatelessWidget {
  final GenericSimpleArtist artist;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final VoidCallback onPlay;
  final LibraryView initialLibraryView;
  final bool isActiveContext;
  final bool isPlaying;
  final bool isPaused;

  const _MiniArtistCard({
    required this.artist,
    required this.playlists,
    required this.albums,
    required this.artists,
    required this.onPlay,
    required this.initialLibraryView,
    required this.isActiveContext,
    required this.isPlaying,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final hover = ValueNotifier(false);
    return InkWell(
      onLongPress: isDesktop
          ? null
          : () {
              LibraryItemContextMenu.show(
                context: context,
                item: artist,
                playlists: playlists,
                albums: albums,
                artists: artists,
                currentLibraryView: initialLibraryView,
                currentNavIndex: 1,
              );
            },
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, animation, secondaryAnimation) =>
                ArtistDetailView(
                  artistId: artist.id,
                  initialArtist: artist,
                  playlists: playlists,
                  albums: albums,
                  artists: artists,
                  initialLibraryView: initialLibraryView,
                  initialNavIndex: 1,
                ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => hover.value = true,
        onExit: (_) => hover.value = false,
        child: ValueListenableBuilder<bool>(
          valueListenable: hover,
          builder: (context, isHovered, _) {
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Container(
                  width: 160,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: ClipOval(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: artist.thumbnailUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: artist.thumbnailUrl,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          color: Colors.grey[900],
                                          child: Icon(
                                            Icons.person,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                ),
                                if (isHovered)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black.withOpacity(0.35),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Artist',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (isHovered)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: FloatingActionButton(
                      heroTag: 'artistPlay_${artist.id}',
                      mini: true,
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.black,
                      onPressed: () {
                        if (isActiveContext) {
                          if (isPlaying) {
                            context.read<AudioPlayerProvider>().pause();
                            return;
                          }
                          if (isPaused) {
                            context.read<AudioPlayerProvider>().play();
                            return;
                          }
                        }
                        onPlay();
                      },
                      child: Icon(
                        isActiveContext && isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
