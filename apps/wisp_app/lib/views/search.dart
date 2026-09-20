// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wisp/ui/cards/album_card.dart';
import 'package:wisp/ui/cards/artist_card.dart';
import 'package:wisp/ui/cards/best_match_card.dart';
import 'package:wisp/ui/cards/playlist_card.dart';
import 'package:wisp/ui/rails/card_rail.dart';
import 'package:wisp/ui/rows/album_row.dart';
import 'package:wisp/ui/rows/artist_row.dart';
import 'package:wisp/ui/rows/generic_row.dart';
import 'package:wisp/ui/rows/playlist_row.dart';
import 'package:wisp/ui/rows/track_row.dart';

import '../models/metadata_models.dart';
import '../providers/library/library_folders.dart';
import '../providers/metadata/spotify_internal.dart';
import '../providers/metadata/youtube.dart';
import '../providers/preferences/preferences_provider.dart';
import '../providers/search/search_state.dart';
import '../services/app_navigation.dart';
import '../services/playback/playback_coordinator.dart';
import '../services/wisp_audio_handler.dart';
import '../widgets/entity_context_menus.dart';
import '../widgets/like_button.dart';
import '../widgets/navigation.dart';
import '../widgets/provider_disabled_state.dart';

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

  String? _activePlayContext;
  SearchTab _selectedTab = SearchTab.tracks;

  static const int _desktopTopSongsCount = 4;

  double _desktopTopPanelHeight() {
    const rowTotalHeight = 70.0;
    return rowTotalHeight * _desktopTopSongsCount;
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

    final selectedSource =
        availableSources.contains(_searchState.selectedSource)
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

    // Record to history only when we got at least some results and no error
    // blew the whole search away.
    if (_error == null && (_tracks.isNotEmpty || _artists.isNotEmpty || _albums.isNotEmpty || _playlists.isNotEmpty)) {
      _searchState.addToHistory(query);
    }

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

    // The parent Scaffold has resizeToAvoidBottomInset: false (the player bar
    // and nav bar live outside it in the Column, so enabling it there causes
    // the body to over-shrink). We handle keyboard avoidance here instead.
    final keyboardHeight =
        isDesktop ? 0.0 : MediaQuery.viewInsetsOf(context).bottom;

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
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: _buildContent(isDesktop, effectiveSource),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDesktop, String effectiveSource) {
    if (_lastQuery.isEmpty) {
      // Mobile shows history (or the original placeholder when empty).
      // Desktop keeps the simple centred prompt — history lives in the
      // title bar dropdown instead.
      return isDesktop
          ? _buildPromptState()
          : _buildMobileHistoryOrPrompt();
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
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

    VoidCallback? onPlay;
    VoidCallback? onTap;

    switch (best.kind) {
      case SearchBestMatchKind.track:
        final track = best.track!;
        onTap = () => _playSearchTrack(track);
        onPlay = () => _toggleTrackPlayback(track);
      case SearchBestMatchKind.artist:
        final artist = best.artist!;
        onPlay = () => _toggleContextPlayback(
              contextKey: 'artist:${artist.id}',
              playAction: () => _playArtist(context, artist.id),
            );
      case SearchBestMatchKind.album:
        final album = best.album!;
        onPlay = () => _toggleContextPlayback(
              contextKey: 'album:${album.id}',
              playAction: () => _playAlbum(context, album.id),
            );
      case SearchBestMatchKind.playlist:
        final playlist = best.playlist!;
        onPlay = () => _toggleContextPlayback(
              contextKey: 'playlist:${playlist.id}',
              playAction: () => _playPlaylist(context, playlist.id),
            );
    }

    return BestMatchCard(
      bestMatch: best,
      isMobile: true,
      onTap: onTap,
      onPlay: onPlay,
    );
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
                _labelForTab(tab),
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
              side: const BorderSide(color: Colors.transparent),
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
    final searchContext = PlaybackContext(
      type: PlaybackContextType.searchResults,
      name: _lastQuery,
      id: '',
      source: SongSource.values.firstWhere(
        (source) => source.name == _searchState.selectedSource,
        orElse: () => SongSource.spotify,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: TrackRow(
        track: track,
        viewContext: searchContext,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        showArtistInline: true,
        showDuration: true,
        durationColumnWidth: 50,
        onTap: () => _playSearchTrack(track),
        onPlayPause: () => _toggleTrackPlayback(track),
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
        onMoreTap: (buttonContext) =>
            _openTrackMenuFromButton(buttonContext, track),
        onArtistTap: (artist) {
          AppNavigation.instance.openArtist(
            context,
            artistId: artist.id,
            initialArtist: artist,
          );
        },
      ),
    );
  }

  Widget _buildMobileArtistRow(GenericSimpleArtist artist) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ArtistRow(
        artist: artist,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        playPosition: GenericRowPlayPosition.cover,
      ),
    );
  }

  Widget _buildMobileAlbumRow(GenericAlbum album) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: AlbumRow(
        album: album,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        playPosition: GenericRowPlayPosition.cover,
      ),
    );
  }

  Widget _buildMobilePlaylistRow(GenericPlaylist playlist) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: PlaylistRow(
        playlist: playlist,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        playPosition: GenericRowPlayPosition.cover,
      ),
    );
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

  Widget _buildDesktopContent() {
    final songs = _buildSuggestedSongs();

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDesktopTopRow(songs),
            const SizedBox(height: 24),
            if (_artists.isNotEmpty) ...[
              CardRail(
                title: 'Artists',
                items: _artists.toList(),
                itemBuilder: (context, artist) {
                  return ArtistCard(artist: artist);
                },
              ),
            ],
            if (_albums.isNotEmpty) ...[
              CardRail(
                title: 'Albums',
                items: _albums.toList(),
                itemBuilder: (context, album) {
                  return AlbumCard(album: album);
                },
              ),
            ],
            if (_playlists.isNotEmpty) ...[
              CardRail(
                title: 'Playlists',
                items: _playlists.toList(),
                itemBuilder: (context, playlist) {
                  return PlaylistCard(playlist: playlist);
                },
              ),
            ],
          ],
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

    VoidCallback? onPlay;
    switch (best.kind) {
      case SearchBestMatchKind.track:
        final track = best.track!;
        onPlay = () => _toggleTrackPlayback(track);
      case SearchBestMatchKind.artist:
        final artist = best.artist!;
        onPlay = () => _toggleContextPlayback(
              contextKey: 'artist:${artist.id}',
              playAction: () => _playArtist(context, artist.id),
            );
      case SearchBestMatchKind.album:
        final album = best.album!;
        onPlay = () => _toggleContextPlayback(
              contextKey: 'album:${album.id}',
              playAction: () => _playAlbum(context, album.id),
            );
      case SearchBestMatchKind.playlist:
        final playlist = best.playlist!;
        onPlay = () => _toggleContextPlayback(
              contextKey: 'playlist:${playlist.id}',
              playAction: () => _playPlaylist(context, playlist.id),
            );
    }

    return BestMatchCard(
      bestMatch: best,
      onPlay: onPlay,
    );
  }

  Widget _buildSongsPanel(List<GenericSong> songs, {int maxItems = 4}) {
    if (songs.isEmpty) {
      return _buildEmptyCard('No songs found');
    }

    final visibleSongs = songs.take(maxItems).toList();
    final searchContext = PlaybackContext(
      type: PlaybackContextType.searchResults,
      name: _lastQuery,
      id: '',
      source: SongSource.values.firstWhere(
        (source) => source.name == _searchState.selectedSource,
        orElse: () => SongSource.spotify,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: visibleSongs.map((track) {
        return TrackRow(
          track: track,
          viewContext: searchContext,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          showArtistInline: true,
          showDuration: true,
          durationColumnWidth: 60,
          onArtistTap: (artist) {
            AppNavigation.instance.openArtist(
              context,
              artistId: artist.id,
              initialArtist: artist,
            );
          },
          onArtistSecondaryTapDown: (artist, details) {
            EntityContextMenus.showArtistMenu(
              context,
              artist: artist,
              globalPosition: details.globalPosition,
            );
          },
          onTap: () => _playSearchTrack(track),
          onPlayPause: () => _toggleTrackPlayback(track),
          onSecondaryTapDown: (details) {
            EntityContextMenus.showTrackMenu(
              context,
              track: track,
              globalPosition: details.globalPosition,
            );
          },
          onMoreTap: (buttonContext) =>
              _openTrackMenuFromButton(buttonContext, track),
          trailing: SizedBox(
            width: 28,
            child: LikeButton(
              track: track,
              showTooltip: false,
              hoverOnlyWhenUnliked: true,
              iconSize: 16,
              padding: const EdgeInsets.all(2),
              constraints: const BoxConstraints(
                minWidth: 24,
                minHeight: 24,
              ),
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      }).toList(),
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
                (source) =>
                    Icon(_sourceIcon(source), size: 18, color: Colors.white),
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

  // ---------------------------------------------------------------------------
  // Mobile: history or prompt (shown when query is empty)
  // ---------------------------------------------------------------------------

  Widget _buildMobileHistoryOrPrompt() {
    return ListenableBuilder(
      listenable: _searchState,
      builder: (context, _) {
        final history = _searchState.history;
        if (history.isEmpty) return _buildPromptState();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent searches',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _searchState.clearHistory,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[500],
                    textStyle: const TextStyle(fontSize: 12),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  child: const Text('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...history.map((query) => _buildMobileHistoryItem(query)),
          ],
        );
      },
    );
  }

  Widget _buildMobileHistoryItem(String query) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        _searchController.text = query;
        _searchController.selection = TextSelection.collapsed(
          offset: query.length,
        );
        _searchState.submit();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.history, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                query,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _searchState.removeFromHistory(query),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.close, size: 16, color: Colors.grey[600]),
              ),
            ),
          ],
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
        color: Colors.white.withValues(alpha: 0.04),
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
    final bestTrack = _bestMatch?.kind == SearchBestMatchKind.track
        ? _bestMatch?.track
        : null;
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

    final playback = context.read<PlaybackCoordinator>();
    setState(() => _activePlayContext = 'song:${queue[index].id}');

    unawaited(
      playback.setQueue(
        queue,
        startIndex: index,
        play: true,
        playbackContext: PlaybackContext(
          type: PlaybackContextType.searchResults,
          name: _lastQuery,
          id: '',
          source: SongSource.values.firstWhere(
            (source) => source.name == _searchState.selectedSource,
          ),
        ),
      ),
    );
  }

  void _toggleTrackPlayback(GenericSong track) {
    final player = context.read<WispAudioHandler>();
    if (player.currentTrack?.id == track.id) {
      final playback = context.read<PlaybackCoordinator>();
      if (player.isPlaying) {
        unawaited(playback.pause());
        return;
      }
      if (player.state == PlaybackState.paused) {
        unawaited(playback.play());
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
    final playback = context.read<PlaybackCoordinator>();

    if (_activePlayContext == contextKey) {
      if (player.isPlaying) {
        unawaited(playback.pause());
        return;
      }
      if (player.state == PlaybackState.paused) {
        unawaited(playback.play());
        return;
      }
    }

    unawaited(playAction());
  }

  Future<void> _playAlbum(BuildContext context, String albumId) async {
    final spotify = context.read<SpotifyInternalProvider>();
    final playback = context.read<PlaybackCoordinator>();

    try {
      final album = await spotify.getAlbumInfo(albumId);
      final tracks = album.songs ?? [];
      if (tracks.isEmpty) return;

      if (mounted) {
        setState(() => _activePlayContext = 'album:$albumId');
      }

      await playback.setQueue(
        tracks,
        startIndex: 0,
        play: true,
        playbackContext: PlaybackContext(
          type: PlaybackContextType.album,
          name: album.title,
          id: album.id,
          source: album.source,
        ),
      );
    } catch (_) {}
  }

  Future<void> _playPlaylist(BuildContext context, String playlistId) async {
    final spotify = context.read<SpotifyInternalProvider>();
    final playback = context.read<PlaybackCoordinator>();

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

      await playback.setQueue(
        tracks,
        startIndex: 0,
        play: true,
        playbackContext: PlaybackContext(
          type: PlaybackContextType.playlist,
          name: playlist.title,
          id: playlist.id,
          source: playlist.source,
        ),
      );

      if (context.mounted) {
        context.read<LibraryFolderState>().markPlaylistPlayed(playlistId);
      }
    } catch (_) {}
  }

  Future<void> _playArtist(BuildContext context, String artistId) async {
    final spotify = context.read<SpotifyInternalProvider>();
    final playback = context.read<PlaybackCoordinator>();

    try {
      final artist = await spotify.getArtistInfo(artistId);
      final tracks = artist.topSongs;
      if (tracks.isEmpty) return;

      if (mounted) {
        setState(() => _activePlayContext = 'artist:$artistId');
      }

      await playback.setQueue(
        tracks,
        startIndex: 0,
        play: true,
        playbackContext: PlaybackContext(
          type: PlaybackContextType.artist,
          name: artist.name,
          id: artist.id,
          source: artist.source,
        ),
      );
    } catch (_) {}
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
}
