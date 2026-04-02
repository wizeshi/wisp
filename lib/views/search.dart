library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/metadata_models.dart';
import '../providers/connect/connect_session_provider.dart';
import '../providers/library/library_folders.dart';
import '../providers/metadata/spotify_internal.dart';
import '../providers/metadata/youtube.dart';
import '../providers/preferences/preferences_provider.dart';
import '../providers/search/search_state.dart';
import '../services/app_navigation.dart';
import '../services/wisp_audio_handler.dart';
import '../widgets/entity_context_menus.dart';
import '../widgets/hover_underline.dart';
import '../widgets/like_button.dart';
import '../widgets/navigation.dart';
import '../widgets/provider_disabled_state.dart';
import 'list_detail.dart';

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
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;
  late final SearchState _searchState;
  int _lastSubmitSignal = 0;

  bool _isLoading = false;
  String? _error;
  String _lastQuery = '';

  List<GenericSong> _tracks = [];
  List<GenericSimpleArtist> _artists = [];
  List<GenericAlbum> _albums = [];
  List<GenericPlaylist> _playlists = [];
  SearchBestMatch? _bestMatch;

  int _hoveredSongIndex = -1;
  bool _isBestMatchHovered = false;
  String? _activePlayContext;
  bool _suppressRowTrackContextMenu = false;
  SearchTab _selectedTab = SearchTab.tracks;

  static const int _desktopTopSongsCount = 4;

  double _desktopTopPanelHeight() {
    const panelVerticalPadding = 0;
    const rowVisualHeight = 44.0 + 10.0 * 2;
    const rowVerticalMargin = 3.0 * 2;
    const rowTotalHeight = rowVisualHeight + rowVerticalMargin;
    return panelVerticalPadding + (rowTotalHeight * _desktopTopSongsCount);
  }

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
    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
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

  List<String> _availableSources(PreferencesProvider preferences) {
    final sources = <String>[];
    if (preferences.metadataSpotifyEnabled) {
      sources.add('Spotify');
    }
    if (preferences.metadataYouTubeEnabled) {
      sources.add('YouTube');
    }
    return sources;
  }

  IconData _sourceIcon(String source) {
    return source == 'YouTube' ? Icons.ondemand_video : Icons.music_note;
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;

    final preferences = context.read<PreferencesProvider>();
    final availableSources = _availableSources(preferences);
    if (availableSources.isEmpty) {
      setState(() {
        _isLoading = false;
        _tracks = [];
        _artists = [];
        _albums = [];
        _playlists = [];
        _bestMatch = null;
        _error = 'All metadata providers are disabled in Preferences.';
      });
      return;
    }

    final selectedSource = availableSources.contains(_searchState.selectedSource)
      ? _searchState.selectedSource
        : availableSources.first;

    setState(() {
      _isLoading = true;
      _error = null;
      _lastQuery = query;
    });

    final spotify = context.read<SpotifyInternalProvider>();
    final youtube = context.read<YouTubeMetadataProvider>();

    List<GenericSong> spotifyTracks = [];
    List<GenericSimpleArtist> spotifyArtists = [];
    List<GenericAlbum> spotifyAlbums = [];
    List<GenericPlaylist> spotifyPlaylists = [];
    SearchBestMatch? spotifyBestMatch;
    List<GenericSong> youtubeTracks = [];
    String? fetchError;

    if (selectedSource == 'YouTube') {
      try {
        youtubeTracks = await youtube.searchTracks(query, limit: 12);
      } catch (e) {
        fetchError = e.toString();
      }
    } else {
      try {
        final results = await spotify.search(query, limit: 20);
        spotifyTracks = results.tracks;
        spotifyArtists = results.artists;
        spotifyAlbums = results.albums;
        spotifyPlaylists = results.playlists;
        spotifyBestMatch = results.bestMatch;
      } catch (e) {
        fetchError = e.toString();
      }
    }

    if (!mounted) return;

    setState(() {
      _tracks = selectedSource == 'YouTube' ? youtubeTracks : spotifyTracks;
      _artists = selectedSource == 'YouTube' ? [] : spotifyArtists;
      _albums = selectedSource == 'YouTube' ? [] : spotifyAlbums;
      _playlists = selectedSource == 'YouTube' ? [] : spotifyPlaylists;
      _bestMatch = selectedSource == 'YouTube'
          ? (youtubeTracks.isNotEmpty
                ? SearchBestMatch.track(youtubeTracks.first)
                : null)
          : spotifyBestMatch;
      _error = fetchError != null && _tracks.isEmpty ? fetchError : null;
      _isLoading = false;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
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
      _bestMatch = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesProvider>();
    final selectedSource = context.select<SearchState, String>(
      (state) => state.selectedSource,
    );
    final availableSources = _availableSources(preferences);
    if (availableSources.isEmpty) {
      return const ProviderDisabledState();
    }

    final effectiveSource = availableSources.contains(selectedSource)
        ? selectedSource
        : availableSources.first;

    if (effectiveSource != selectedSource) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_searchState.selectedSource == effectiveSource) return;
        _searchState.setSelectedSource(effectiveSource);
      });
    }

    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (isDesktop)
            const SizedBox(height: 8)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Expanded(child: _buildSearchField()),
                  const SizedBox(width: 10),
                  _buildSourceSelector(availableSources, effectiveSource),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: _buildContent(isDesktop, effectiveSource),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDesktop, String effectiveSource) {
    if (_lastQuery.isEmpty) {
      return _buildPromptState();
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState();
    }

    final hasAny =
        _tracks.isNotEmpty ||
        _artists.isNotEmpty ||
        _albums.isNotEmpty ||
        _playlists.isNotEmpty;
    if (!hasAny) {
      return _buildEmptyState('No results found');
    }

    if (!isDesktop) {
      return _buildMobileContent(effectiveSource);
    }

    return _buildDesktopContent();
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _searchState.submit(),
    );
  }

  Widget _buildMobileContent(String effectiveSource) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Text(
          'Best Match',
          style: TextStyle(
            color: Colors.grey[300],
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildMobileBestMatchCard(),
        const SizedBox(height: 12),
        _buildMobileTypePills(effectiveSource),
        const SizedBox(height: 10),
        _buildMobileSelectedTypeList(effectiveSource),
      ],
    );
  }

  Widget _buildMobileBestMatchCard() {
    final best = _resolveBestMatch();
    if (best == null) {
      return _buildEmptyCard('No best match');
    }

    String title;
    String subtitle;
    String imageUrl;
    bool isPlaying = false;
    VoidCallback onTap;

    final player = context.watch<WispAudioHandler>();

    switch (best.kind) {
      case SearchBestMatchKind.track:
        final track = best.track!;
        title = track.title;
        subtitle = track.artists.map((a) => a.name).join(', ');
        imageUrl = track.thumbnailUrl;
        isPlaying = player.isPlaying && player.currentTrack?.id == track.id;
        onTap = () => _playSearchTrack(track);
      case SearchBestMatchKind.artist:
        final artist = best.artist!;
        title = artist.name;
        subtitle = 'Artist';
        imageUrl = artist.thumbnailUrl;
        isPlaying = _activePlayContext == 'artist:${artist.id}' && player.isPlaying;
        onTap = () {
          AppNavigation.instance.openArtist(
            context,
            artistId: artist.id,
            initialArtist: artist,
          );
        };
      case SearchBestMatchKind.album:
        final album = best.album!;
        title = album.title;
        subtitle = album.artists.map((a) => a.name).join(', ');
        imageUrl = album.thumbnailUrl;
        isPlaying = _activePlayContext == 'album:${album.id}' && player.isPlaying;
        onTap = () {
          AppNavigation.instance.openSharedList(
            context,
            id: album.id,
            type: SharedListType.album,
            initialTitle: album.title,
            initialThumbnailUrl: album.thumbnailUrl,
          );
        };
      case SearchBestMatchKind.playlist:
        final playlist = best.playlist!;
        title = playlist.title;
        subtitle = playlist.author.displayName;
        imageUrl = playlist.thumbnailUrl;
        isPlaying =
            _activePlayContext == 'playlist:${playlist.id}' && player.isPlaying;
        onTap = () {
          AppNavigation.instance.openSharedList(
            context,
            id: playlist.id,
            type: SharedListType.playlist,
            initialTitle: playlist.title,
            initialThumbnailUrl: playlist.thumbnailUrl,
          );
        };
    }

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showBestMatchContextMenu(best, globalPosition: details.globalPosition);
      },
      onLongPress: () => _showBestMatchContextMenu(best),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _buildMobileLeadingArtwork(
                imageUrl: imageUrl,
                isPlaying: isPlaying,
                icon: best.kind == SearchBestMatchKind.artist
                    ? Icons.person
                    : Icons.music_note,
                circular: best.kind == SearchBestMatchKind.artist,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBestMatchContextMenu(
    SearchBestMatch best, {
    Offset? globalPosition,
  }) {
    switch (best.kind) {
      case SearchBestMatchKind.track:
        final track = best.track;
        if (track == null) return;
        EntityContextMenus.showTrackMenu(
          context,
          track: track,
          globalPosition: globalPosition,
        );
      case SearchBestMatchKind.artist:
        final artist = best.artist;
        if (artist == null) return;
        EntityContextMenus.showArtistMenu(
          context,
          artist: artist,
          globalPosition: globalPosition,
        );
      case SearchBestMatchKind.album:
        final album = best.album;
        if (album == null) return;
        EntityContextMenus.showAlbumMenu(
          context,
          album: album,
          globalPosition: globalPosition,
        );
      case SearchBestMatchKind.playlist:
        final playlist = best.playlist;
        if (playlist == null) return;
        EntityContextMenus.showPlaylistMenu(
          context,
          playlist: playlist,
          globalPosition: globalPosition,
        );
    }
  }

  Widget _buildMobileTypePills(String effectiveSource) {
    final tabs = effectiveSource == 'YouTube'
        ? const [SearchTab.tracks]
        : SearchTab.values;

    if (!tabs.contains(_selectedTab)) {
      _selectedTab = tabs.first;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _selectedTab == tab;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                '${_labelForTab(tab)}',
                style: TextStyle(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Colors.white,
                ),
              ),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (_) => setState(() => _selectedTab = tab),
              backgroundColor: const Color(0xFF282828),
              selectedColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: BorderSide(
                color: Colors.transparent
              )
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMobileSelectedTypeList(String effectiveSource) {
    if (effectiveSource == 'YouTube') {
      return Column(
        children: _tracks
            .map((track) => _buildMobileTrackRow(track))
            .toList(growable: false),
      );
    }

    switch (_selectedTab) {
      case SearchTab.tracks:
        return Column(
          children: _tracks
              .map((track) => _buildMobileTrackRow(track))
              .toList(growable: false),
        );
      case SearchTab.artists:
        return Column(
          children: _artists
              .map((artist) => _buildMobileArtistRow(artist))
              .toList(growable: false),
        );
      case SearchTab.albums:
        return Column(
          children: _albums
              .map((album) => _buildMobileAlbumRow(album))
              .toList(growable: false),
        );
      case SearchTab.playlists:
        return Column(
          children: _playlists
              .map((playlist) => _buildMobilePlaylistRow(playlist))
              .toList(growable: false),
        );
    }
  }

  Widget _buildMobileTrackRow(GenericSong track) {
    final player = context.watch<WispAudioHandler>();
    final isPlaying = player.isPlaying && player.currentTrack?.id == track.id;

    return _MobileResultRow(
      title: track.title,
      subtitle: track.artists.map((a) => a.name).join(', '),
      imageUrl: track.thumbnailUrl,
      trailing: _formatDuration(track.durationSecs),
      isPlaying: isPlaying,
      icon: Icons.music_note,
      onTap: () => _playSearchTrack(track),
      onSecondaryTapDown: (details) {
        EntityContextMenus.showTrackMenu(
          context,
          track: track,
          globalPosition: details.globalPosition,
        );
      },
      onLongPress: () {
        EntityContextMenus.showTrackMenu(context, track: track);
      },
    );
  }

  Widget _buildMobileArtistRow(GenericSimpleArtist artist) {
    final player = context.watch<WispAudioHandler>();
    final isPlaying = _activePlayContext == 'artist:${artist.id}' && player.isPlaying;

    return _MobileResultRow(
      title: artist.name,
      subtitle: 'Artist',
      imageUrl: artist.thumbnailUrl,
      trailing: null,
      isPlaying: isPlaying,
      icon: Icons.person,
      circularImage: true,
      onTap: () {
        AppNavigation.instance.openArtist(
          context,
          artistId: artist.id,
          initialArtist: artist,
        );
      },
      onSecondaryTapDown: (details) {
        EntityContextMenus.showArtistMenu(
          context,
          artist: artist,
          globalPosition: details.globalPosition,
        );
      },
      onLongPress: () {
        EntityContextMenus.showArtistMenu(context, artist: artist);
      },
    );
  }

  Widget _buildMobileAlbumRow(GenericAlbum album) {
    final player = context.watch<WispAudioHandler>();
    final isPlaying = _activePlayContext == 'album:${album.id}' && player.isPlaying;

    return _MobileResultRow(
      title: album.title,
      subtitle: album.artists.map((a) => a.name).join(', '),
      imageUrl: album.thumbnailUrl,
      trailing: null,
      isPlaying: isPlaying,
      icon: Icons.album,
      onTap: () {
        AppNavigation.instance.openSharedList(
          context,
          id: album.id,
          type: SharedListType.album,
          initialTitle: album.title,
          initialThumbnailUrl: album.thumbnailUrl,
        );
      },
      onSecondaryTapDown: (details) {
        EntityContextMenus.showAlbumMenu(
          context,
          album: album,
          globalPosition: details.globalPosition,
        );
      },
      onLongPress: () {
        EntityContextMenus.showAlbumMenu(context, album: album);
      },
    );
  }

  Widget _buildMobilePlaylistRow(GenericPlaylist playlist) {
    final player = context.watch<WispAudioHandler>();
    final isPlaying =
        _activePlayContext == 'playlist:${playlist.id}' && player.isPlaying;

    return _MobileResultRow(
      title: playlist.title,
      subtitle: playlist.author.displayName,
      imageUrl: playlist.thumbnailUrl,
      trailing: null,
      isPlaying: isPlaying,
      icon: Icons.playlist_play,
      onTap: () {
        AppNavigation.instance.openSharedList(
          context,
          id: playlist.id,
          type: SharedListType.playlist,
          initialTitle: playlist.title,
          initialThumbnailUrl: playlist.thumbnailUrl,
        );
      },
      onSecondaryTapDown: (details) {
        EntityContextMenus.showPlaylistMenu(
          context,
          playlist: playlist,
          globalPosition: details.globalPosition,
        );
      },
      onLongPress: () {
        EntityContextMenus.showPlaylistMenu(context, playlist: playlist);
      },
    );
  }

  Widget _buildMobileLeadingArtwork({
    required String imageUrl,
    required bool isPlaying,
    required IconData icon,
    bool circular = false,
  }) {
    final artwork = SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        children: [
          Positioned.fill(
            child: _ArtworkImage(imageUrl: imageUrl, icon: icon),
          ),
          if (isPlaying)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.45),
                alignment: Alignment.center,
                child: _AnimatedQuickWaveform(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );

    if (circular) {
      return ClipOval(child: artwork);
    }

    return ClipRRect(borderRadius: BorderRadius.circular(6), child: artwork);
  }

  String _labelForTab(SearchTab tab) {
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

  int _countForTab(SearchTab tab, String effectiveSource) {
    if (effectiveSource == 'YouTube') {
      return tab == SearchTab.tracks ? _tracks.length : 0;
    }

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

  Widget _buildDesktopContent() {
    final songs = _buildSuggestedSongs();

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDesktopTopRow(songs),
              if (_artists.isNotEmpty) ...[
                const SizedBox(height: 34),
                _buildRailSection(
                  title: 'Artists',
                  items: _artists.take(10).toList(),
                ),
              ],
              if (_albums.isNotEmpty) ...[
                const SizedBox(height: 34),
                _buildRailSection(
                  title: 'Albums',
                  items: _albums.take(10).toList(),
                ),
              ],
              if (_playlists.isNotEmpty) ...[
                const SizedBox(height: 34),
                _buildRailSection(
                  title: 'Playlists',
                  items: _playlists.take(10).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTopRow(List<GenericSong> songs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1060;
        final effectiveHeight = _desktopTopPanelHeight();

        final songsPanelWithHeight = SizedBox(
          height: effectiveHeight,
          child: _buildSongsPanel(songs, maxItems: _desktopTopSongsCount),
        );

        final topResultPanel = SizedBox(
          height: effectiveHeight,
          child: _buildTopResultCard(),
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Best Match'),
              const SizedBox(height: 16),
              topResultPanel,
              const SizedBox(height: 24),
              _buildSectionTitle('Songs'),
              const SizedBox(height: 10),
              songsPanelWithHeight,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Best Match'),
                  const SizedBox(height: 20),
                  topResultPanel,
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Songs'),
                  const SizedBox(height: 20),
                  songsPanelWithHeight,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    );
  }

  Widget _buildTopResultCard() {
    final best = _resolveBestMatch();
    if (best == null) {
      return _buildEmptyCard('No top result');
    }

    final isArtist = best.kind == SearchBestMatchKind.artist;
    final player = context.watch<WispAudioHandler>();

    String title;
    String subtitle;
    String imageUrl;
    VoidCallback onTap;
    VoidCallback? onPlay;
    bool isPlaying = false;

    switch (best.kind) {
      case SearchBestMatchKind.track:
        final track = best.track!;
        title = track.title;
        subtitle = track.artists.map((a) => a.name).join(', ');
        imageUrl = track.thumbnailUrl;
        onTap = () => _openAlbumFromTrack(track);
        onPlay = () => _toggleTrackPlayback(track);
        isPlaying = player.isPlaying && player.currentTrack?.id == track.id;
      case SearchBestMatchKind.artist:
        final artist = best.artist!;
        title = artist.name;
        subtitle = 'Artist';
        imageUrl = artist.thumbnailUrl;
        onTap = () {
          AppNavigation.instance.openArtist(
            context,
            artistId: artist.id,
            initialArtist: artist,
          );
        };
        onPlay = () => _toggleContextPlayback(
              contextKey: 'artist:${artist.id}',
              playAction: () => _playArtist(context, artist.id),
            );
        isPlaying =
            _activePlayContext == 'artist:${artist.id}' && player.isPlaying;
      case SearchBestMatchKind.album:
        final album = best.album!;
        title = album.title;
        subtitle = album.artists.map((a) => a.name).join(', ');
        imageUrl = album.thumbnailUrl;
        onTap = () {
          AppNavigation.instance.openSharedList(
            context,
            id: album.id,
            type: SharedListType.album,
            initialTitle: album.title,
            initialThumbnailUrl: album.thumbnailUrl,
          );
        };
        onPlay = () => _toggleContextPlayback(
              contextKey: 'album:${album.id}',
              playAction: () => _playAlbum(context, album.id),
            );
        isPlaying = _activePlayContext == 'album:${album.id}' && player.isPlaying;
      case SearchBestMatchKind.playlist:
        final playlist = best.playlist!;
        title = playlist.title;
        subtitle = playlist.author.displayName;
        imageUrl = playlist.thumbnailUrl;
        onTap = () {
          AppNavigation.instance.openSharedList(
            context,
            id: playlist.id,
            type: SharedListType.playlist,
            initialTitle: playlist.title,
            initialThumbnailUrl: playlist.thumbnailUrl,
          );
        };
        onPlay = () => _toggleContextPlayback(
              contextKey: 'playlist:${playlist.id}',
              playAction: () => _playPlaylist(context, playlist.id),
            );
        isPlaying =
            _activePlayContext == 'playlist:${playlist.id}' && player.isPlaying;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isBestMatchHovered = true),
      onExit: (_) => setState(() => _isBestMatchHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapDown: (details) {
          final track = best.track;
          final artist = best.artist;
          final album = best.album;
          final playlist = best.playlist;
          if (track != null) {
            EntityContextMenus.showTrackMenu(
              context,
              track: track,
              globalPosition: details.globalPosition,
            );
          } else if (artist != null) {
            EntityContextMenus.showArtistMenu(
              context,
              artist: artist,
              globalPosition: details.globalPosition,
            );
          } else if (album != null) {
            EntityContextMenus.showAlbumMenu(
              context,
              album: album,
              globalPosition: details.globalPosition,
            );
          } else if (playlist != null) {
            EntityContextMenus.showPlaylistMenu(
              context,
              playlist: playlist,
              globalPosition: details.globalPosition,
            );
          }
        },
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.045),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 126,
                    height: 126,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isArtist ? 63 : 10),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _ArtworkImage(
                              imageUrl: imageUrl,
                              icon: isArtist ? Icons.person : Icons.music_note,
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: _isBestMatchHovered ? 1 : 0,
                            duration: const Duration(milliseconds: 170),
                            child: Container(
                              color: Colors.black.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 46,
                      fontWeight: FontWeight.w700,
                      height: 0.98,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[400], fontSize: 16),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            if (onPlay != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: _HoverPlayFab(
                  visible: _isBestMatchHovered,
                  isPlaying: isPlaying,
                  onPressed: onPlay,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongsPanel(List<GenericSong> songs, {int maxItems = 7}) {
    if (songs.isEmpty) {
      return _buildEmptyCard('No songs found');
    }

    final player = context.watch<WispAudioHandler>();
    final visibleSongs = songs.take(maxItems).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...visibleSongs.asMap().entries.map((entry) {
            final listIndex = entry.key;
            final track = entry.value;
            final isHovered = _hoveredSongIndex == listIndex;
          final isCurrent = player.currentTrack?.id == track.id;
          final isPlaying = isCurrent && player.isPlaying;

          return MouseRegion(
            onEnter: (_) => setState(() => _hoveredSongIndex = listIndex),
            onExit: (_) => setState(() => _hoveredSongIndex = -1),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _playSearchTrack(track),
              onSecondaryTapDown: (details) {
                if (_suppressRowTrackContextMenu) {
                  _suppressRowTrackContextMenu = false;
                  return;
                }
                EntityContextMenus.showTrackMenu(
                  context,
                  track: track,
                  globalPosition: details.globalPosition,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isHovered
                      ? Colors.white.withOpacity(0.085)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _ArtworkImage(
                                imageUrl: track.thumbnailUrl,
                                icon: Icons.music_note,
                              ),
                            ),
                            AnimatedOpacity(
                              opacity: isHovered ? 1 : 0,
                              duration: const Duration(milliseconds: 130),
                              child: Container(
                                color: Colors.black.withOpacity(0.45),
                              ),
                            ),
                            if (isHovered)
                              Positioned.fill(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _toggleTrackPlayback(track),
                                    child: Icon(
                                      isPlaying ? Icons.pause : Icons.play_arrow,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 29 / 2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _buildSongArtistsLine(track.artists),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    LikeButton(
                      track: track,
                      showTooltip: false,
                      showIfUnliked: isHovered,
                      iconSize: 16,
                      padding: const EdgeInsets.all(2),
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _formatDuration(track.durationSecs),
                      style: TextStyle(color: Colors.grey[400], fontSize: 22 / 2),
                    ),
                    const SizedBox(width: 4),
                    AnimatedOpacity(
                      opacity: isHovered ? 1 : 0.65,
                      duration: const Duration(milliseconds: 130),
                      child: Builder(
                        builder: (buttonContext) => IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          iconSize: 18,
                          constraints:
                              const BoxConstraints(minWidth: 28, minHeight: 28),
                          padding: EdgeInsets.zero,
                          tooltip: 'More actions',
                          onPressed: () =>
                              _openTrackMenuFromButton(buttonContext, track),
                          icon: Icon(Icons.more_horiz, color: Colors.grey[500]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          }),
        ],
      ),
    );
  }

  Widget _buildRailSection({required String title, required List<dynamic> items}) {
    final player = context.watch<WispAudioHandler>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 264,
          child: Stack(
            children: [
              ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 18),
                itemBuilder: (context, index) {
                  final item = items[index];

                  if (item is GenericSimpleArtist) {
                    final contextKey = 'artist:${item.id}';
                    return _RailCard(
                      title: item.name,
                      subtitle: 'Artist',
                      imageUrl: item.thumbnailUrl,
                      circularImage: true,
                      isPlaying:
                          _activePlayContext == contextKey && player.isPlaying,
                      onTap: () {
                        AppNavigation.instance.openArtist(
                          context,
                          artistId: item.id,
                          initialArtist: item,
                        );
                      },
                      onPlay: () => _toggleContextPlayback(
                        contextKey: contextKey,
                        playAction: () => _playArtist(context, item.id),
                      ),
                      onSecondaryTapDown: (details) {
                        EntityContextMenus.showArtistMenu(
                          context,
                          artist: item,
                          globalPosition: details.globalPosition,
                        );
                      },
                      onLongPress: () {
                        EntityContextMenus.showArtistMenu(context, artist: item);
                      },
                    );
                  }

                  if (item is GenericAlbum) {
                    final contextKey = 'album:${item.id}';
                    return _RailCard(
                      title: item.title,
                      subtitle: item.artists.map((a) => a.name).join(', '),
                      imageUrl: item.thumbnailUrl,
                      isPlaying:
                          _activePlayContext == contextKey && player.isPlaying,
                      onTap: () {
                        AppNavigation.instance.openSharedList(
                          context,
                          id: item.id,
                          type: SharedListType.album,
                          initialTitle: item.title,
                          initialThumbnailUrl: item.thumbnailUrl,
                        );
                      },
                      onPlay: () => _toggleContextPlayback(
                        contextKey: contextKey,
                        playAction: () => _playAlbum(context, item.id),
                      ),
                      onSecondaryTapDown: (details) {
                        EntityContextMenus.showAlbumMenu(
                          context,
                          album: item,
                          globalPosition: details.globalPosition,
                        );
                      },
                      onLongPress: () {
                        EntityContextMenus.showAlbumMenu(context, album: item);
                      },
                    );
                  }

                  if (item is GenericPlaylist) {
                    final contextKey = 'playlist:${item.id}';
                    return _RailCard(
                      title: item.title,
                      subtitle: item.author.displayName,
                      imageUrl: item.thumbnailUrl,
                      isPlaying:
                          _activePlayContext == contextKey && player.isPlaying,
                      onTap: () {
                        AppNavigation.instance.openSharedList(
                          context,
                          id: item.id,
                          type: SharedListType.playlist,
                          initialTitle: item.title,
                          initialThumbnailUrl: item.thumbnailUrl,
                        );
                      },
                      onPlay: () => _toggleContextPlayback(
                        contextKey: contextKey,
                        playAction: () => _playPlaylist(context, item.id),
                      ),
                      onSecondaryTapDown: (details) {
                        EntityContextMenus.showPlaylistMenu(
                          context,
                          playlist: item,
                          globalPosition: details.globalPosition,
                        );
                      },
                      onLongPress: () {
                        EntityContextMenus.showPlaylistMenu(
                          context,
                          playlist: item,
                        );
                      },
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
              if (items.length > 1)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF121212).withOpacity(0.78),
                          ],
                        ),
                      ),
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.chevron_right,
                          color: Colors.grey[400],
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourceSelector(
    List<String> availableSources,
    String selectedSource,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedSource,
          dropdownColor: const Color(0xFF181818),
          iconEnabledColor: Colors.grey[400],
          selectedItemBuilder: (_) => availableSources
              .map(
                (source) => Icon(
                  _sourceIcon(source),
                  size: 18,
                  color: Colors.white,
                ),
              )
              .toList(),
          items: availableSources
              .map(
                (source) => DropdownMenuItem<String>(
                  value: source,
                  child: Icon(
                    _sourceIcon(source),
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            _searchState.setSelectedSource(value);
            final query = _searchController.text.trim();
            if (query.isNotEmpty) {
              _performSearch(query);
            }
          },
        ),
      ),
    );
  }

  Widget _buildPromptState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 14),
          Text(
            'Search for songs, artists, albums, or playlists',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
            _error ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _performSearch(_lastQuery),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String label) {
    return Center(
      child: Text(
        label,
        style: TextStyle(color: Colors.grey[500], fontSize: 16),
      ),
    );
  }

  Widget _buildEmptyCard(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: Colors.grey[400])),
    );
  }

  SearchBestMatch? _resolveBestMatch() {
    if (_bestMatch != null) {
      return _bestMatch;
    }
    if (_tracks.isNotEmpty) {
      return SearchBestMatch.track(_tracks.first);
    }
    if (_artists.isNotEmpty) {
      return SearchBestMatch.artist(_artists.first);
    }
    if (_albums.isNotEmpty) {
      return SearchBestMatch.album(_albums.first);
    }
    if (_playlists.isNotEmpty) {
      return SearchBestMatch.playlist(_playlists.first);
    }
    return null;
  }

  List<GenericSong> _buildSuggestedSongs() {
    if (_tracks.isEmpty) return const [];
    final bestTrack =
        _bestMatch?.kind == SearchBestMatchKind.track ? _bestMatch?.track : null;
    if (bestTrack == null) {
      return _tracks.take(8).toList();
    }

    return _tracks.where((song) => song.id != bestTrack.id).take(8).toList();
  }

  void _playSearchTrack(GenericSong track) {
    if (_tracks.isEmpty) {
      _playSearchQueueWithTracks([track], 0);
      return;
    }

    final inResultsIndex = _tracks.indexWhere((item) => item.id == track.id);
    if (inResultsIndex >= 0) {
      _playSearchQueueWithTracks(_tracks, inResultsIndex);
      return;
    }

    _playSearchQueueWithTracks([track, ..._tracks], 0);
  }

  void _playSearchQueueWithTracks(List<GenericSong> queue, int index) {
    if (queue.isEmpty || index < 0 || index >= queue.length) return;

    final connect = context.read<ConnectSessionProvider>();
    setState(() => _activePlayContext = 'song:${queue[index].id}');

    unawaited(
      connect.requestSetQueue(
        queue,
        startIndex: index,
        play: true,
        contextType: 'search',
        contextName: 'Search results',
      ),
    );
  }

  void _toggleTrackPlayback(GenericSong track) {
    final player = context.read<WispAudioHandler>();
    if (player.currentTrack?.id == track.id) {
      final connect = context.read<ConnectSessionProvider>();
      if (player.isPlaying) {
        unawaited(connect.requestPause());
        return;
      }
      if (player.state == PlaybackState.paused) {
        unawaited(connect.requestPlay());
        return;
      }
    }

    _playSearchTrack(track);
  }

  void _toggleContextPlayback({
    required String contextKey,
    required Future<void> Function() playAction,
  }) {
    final player = context.read<WispAudioHandler>();
    final connect = context.read<ConnectSessionProvider>();

    if (_activePlayContext == contextKey) {
      if (player.isPlaying) {
        unawaited(connect.requestPause());
        return;
      }
      if (player.state == PlaybackState.paused) {
        unawaited(connect.requestPlay());
        return;
      }
    }

    unawaited(playAction());
  }

  Future<void> _playAlbum(BuildContext context, String albumId) async {
    final spotify = context.read<SpotifyInternalProvider>();
    final connect = context.read<ConnectSessionProvider>();

    try {
      final album = await spotify.getAlbumInfo(albumId);
      final tracks = album.songs ?? [];
      if (tracks.isEmpty) return;

      if (mounted) {
        setState(() => _activePlayContext = 'album:$albumId');
      }

      await connect.requestSetQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'album',
        contextName: album.title,
        contextID: album.id,
        contextSource: album.source,
      );
    } catch (_) {}
  }

  Future<void> _playPlaylist(BuildContext context, String playlistId) async {
    final spotify = context.read<SpotifyInternalProvider>();
    final connect = context.read<ConnectSessionProvider>();

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

      await connect.requestSetQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'playlist',
        contextName: playlist.title,
        contextID: playlist.id,
        contextSource: playlist.source,
      );

      context.read<LibraryFolderState>().markPlaylistPlayed(playlistId);
    } catch (_) {}
  }

  Future<void> _playArtist(BuildContext context, String artistId) async {
    final spotify = context.read<SpotifyInternalProvider>();
    final connect = context.read<ConnectSessionProvider>();

    try {
      final artist = await spotify.getArtistInfo(artistId);
      final tracks = artist.topSongs;
      if (tracks.isEmpty) return;

      if (mounted) {
        setState(() => _activePlayContext = 'artist:$artistId');
      }

      await connect.requestSetQueue(
        tracks,
        startIndex: 0,
        play: true,
        contextType: 'artist',
        contextName: artist.name,
        contextID: artist.id,
        contextSource: artist.source,
      );
    } catch (_) {}
  }

  void _openAlbumFromTrack(GenericSong track) {
    final album = track.album;
    if (album == null) return;

    AppNavigation.instance.openSharedList(
      context,
      id: album.id,
      type: SharedListType.album,
      initialTitle: album.title,
      initialThumbnailUrl: album.thumbnailUrl,
    );
  }

  void _openTrackMenuFromButton(BuildContext buttonContext, GenericSong track) {
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      EntityContextMenus.showTrackMenu(context, track: track);
      return;
    }

    final origin = renderBox.localToGlobal(Offset.zero);
    final anchorRect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      renderBox.size.width,
      renderBox.size.height,
    );

    EntityContextMenus.showTrackMenu(
      context,
      track: track,
      anchorRect: anchorRect,
    );
  }

  Widget _buildSongArtistsLine(List<GenericSimpleArtist> artists) {
    if (artists.isEmpty) {
      return Text(
        'Unknown artist',
        style: TextStyle(color: Colors.grey[400], fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Wrap(
      children: [
        for (int i = 0; i < artists.length; i++) ...[
          HoverUnderline(
            onTap: () {
              AppNavigation.instance.openArtist(
                context,
                artistId: artists[i].id,
                initialArtist: artists[i],
              );
            },
            onSecondaryTapDown: (details) {
              _suppressRowTrackContextMenu = true;
              EntityContextMenus.showArtistMenu(
                context,
                artist: artists[i],
                globalPosition: details.globalPosition,
              );
            },
            builder: (isHovering) => Text(
              artists[i].name,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
                decoration: isHovering
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (i < artists.length - 1)
            Text(', ', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ],
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

class _ArtworkImage extends StatelessWidget {
  final String imageUrl;
  final IconData icon;

  const _ArtworkImage({required this.imageUrl, required this.icon});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey[900],
          child: Icon(icon, color: Colors.grey[600]),
        ),
      );
    }

    return Container(
      color: Colors.grey[900],
      child: Icon(icon, color: Colors.grey[600]),
    );
  }
}

class _HoverPlayFab extends StatelessWidget {
  final bool visible;
  final bool isPlaying;
  final VoidCallback onPressed;
  final double size;
  final double elevation;

  const _HoverPlayFab({
    required this.visible,
    required this.isPlaying,
    required this.onPressed,
    this.size = 52,
    this.elevation = 6,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 0.55),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: visible ? 1 : 0,
          child: SizedBox(
            width: size,
            height: size,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: FloatingActionButton(
                heroTag: null,
                mouseCursor: SystemMouseCursors.click,
                elevation: elevation,
                shape: const CircleBorder(),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                onPressed: onPressed,
                child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileResultRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final String? trailing;
  final bool isPlaying;
  final IconData icon;
  final bool circularImage;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;

  const _MobileResultRow({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.trailing,
    required this.isPlaying,
    required this.icon,
    required this.onTap,
    this.onSecondaryTapDown,
    this.onLongPress,
    this.circularImage = false,
  });

  @override
  Widget build(BuildContext context) {
    final artwork = SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        children: [
          Positioned.fill(
            child: _ArtworkImage(imageUrl: imageUrl, icon: icon),
          ),
          if (isPlaying)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.45),
                alignment: Alignment.center,
                child: _AnimatedQuickWaveform(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onSecondaryTapDown: onSecondaryTapDown,
        onLongPress: onLongPress,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  circularImage
                      ? ClipOval(child: artwork)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: artwork,
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaying
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey[400], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null)
                    Text(
                      trailing!,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedQuickWaveform extends StatefulWidget {
  final Color color;

  const _AnimatedQuickWaveform({required this.color});

  @override
  State<_AnimatedQuickWaveform> createState() => _AnimatedQuickWaveformState();
}

class _AnimatedQuickWaveformState extends State<_AnimatedQuickWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * math.pi;
        double barHeight(double phase) {
          final value = (math.sin(t + phase) + 1) / 2;
          return 4 + value * 10;
        }

        return SizedBox(
          width: 16,
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _waveBar(widget.color, barHeight(0.0)),
              const SizedBox(width: 2),
              _waveBar(widget.color, barHeight(1.4)),
              const SizedBox(width: 2),
              _waveBar(widget.color, barHeight(2.8)),
            ],
          ),
        );
      },
    );
  }

  Widget _waveBar(Color color, double height) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _RailCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final bool circularImage;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;

  const _RailCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.isPlaying,
    required this.onTap,
    required this.onPlay,
    this.onSecondaryTapDown,
    this.onLongPress,
    this.circularImage = false,
  });

  @override
  State<_RailCard> createState() => _RailCardState();
}

class _RailCardState extends State<_RailCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    return GestureDetector(
      onSecondaryTapDown: widget.onSecondaryTapDown,
      onLongPress: isDesktop ? null : widget.onLongPress,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 206,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              widget.circularImage ? 100 : 8,
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _ArtworkImage(
                                    imageUrl: widget.imageUrl,
                                    icon: widget.circularImage
                                        ? Icons.person
                                        : Icons.music_note,
                                  ),
                                ),
                                AnimatedOpacity(
                                  opacity: _isHovered ? 1 : 0,
                                  duration: const Duration(milliseconds: 150),
                                  child: Container(
                                    color: Colors.black.withOpacity(0.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: _HoverPlayFab(
                            visible: _isHovered,
                            isPlaying: widget.isPlaying,
                            onPressed: widget.onPlay,
                            size: 40,
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
