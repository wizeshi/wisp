/// Shared playlist/album detail view
library;

import 'dart:async';
import 'dart:math';
import 'dart:io' show Platform, File;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wisp/utils/text_parser.dart';

import '../models/metadata_models.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../services/playback/playback_coordinator.dart';
import '../providers/library/library_folders.dart';
import '../providers/metadata/spotify_internal.dart';
import '../providers/library/local_playlists.dart';
import '../providers/preferences/preferences_provider.dart';
import '../providers/theme/cover_art_palette_provider.dart';
import '../providers/library/library_state.dart';
import '../widgets/hover_underline.dart';
import '../widgets/navigation.dart';
import '../widgets/playlist_folder_modals.dart';
import '../widgets/adaptive_context_menu.dart';
import '../widgets/entity_context_menus.dart';
import '../widgets/like_button.dart';
import '../services/app_navigation.dart';
import '../services/cache_manager.dart';
import '../services/metadata_cache.dart';
import '../providers/audio/youtube.dart';
import '../utils/liked_songs.dart';
import '../widgets/liked_songs_art.dart';
import '../widgets/provider_disabled_state.dart';
import '../views/youtube_alternatives.dart';

enum SharedListType { playlist, album }

enum _SortMethod { position, title, author, album, addedAt, duration, source }

enum _ListVisualStyle { spotify, apple }

typedef _ListItem = Object;

class SharedListDetailView extends StatefulWidget {
  final String id;
  final SharedListType type;
  final String? initialTitle;
  final String? initialThumbnailUrl;
  final List<GenericPlaylist> playlists;
  final List<GenericAlbum> albums;
  final List<GenericSimpleArtist> artists;
  final LibraryView initialLibraryView;
  final int initialNavIndex;

  const SharedListDetailView({
    super.key,
    required this.id,
    required this.type,
    this.initialTitle,
    this.initialThumbnailUrl,
    required this.playlists,
    required this.albums,
    required this.artists,
    required this.initialLibraryView,
    required this.initialNavIndex,
  });

  @override
  State<SharedListDetailView> createState() => _SharedListDetailViewState();
}

class _SharedListDetailViewState extends State<SharedListDetailView> {
  bool _isLoading = true;
  GenericPlaylist? _playlist;
  GenericAlbum? _album;
  List<int> _sortedIndices = [];
  _SortMethod _sortMethod = _SortMethod.position;
  bool _ascending = true;
  bool _showSearch = false;
  String _searchQuery = '';
  static const double _rowHeightDesktop = 64;
  static const double _rowHeightMobile = 64;
  static const int _windowBuffer = 6;
  double _songListTopOffset = 0;
  final GlobalKey _headerKey = GlobalKey();
  final ScrollController _desktopScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();
  final GlobalKey _songListKey = GlobalKey();
  final GlobalKey _mobileActionsKey = GlobalKey();
  VoidCallback? _likedTracksListener;
  late final SpotifyInternalProvider _spotifyInternal;
  bool _showStickyBar = false;
  Color _stickyBarColor = const Color(0xFF1E1E1E);
  String? _stickyCoverUrl;
  double? _mobileHeaderExtent;

  // Column visibility breakpoints (in pixels)
  static const double _breakpointFullColumns =
      600; // All columns: # Song Artist Album Time (+ Added At for Spotify)
  static const double _breakpointNoAddedAt =
      500; // Hide Added At (Spotify only): # Song Artist Album Time
  static const double _breakpointNoAlbum =
      450; // Hide Album: # Song Artist Time
  static const double _breakpointNoArtistColumn =
      425; // Hide Artist column, Artist inline: # Song Time
  static const double _breakpointNoTime =
      400; // Hide Time: # Song (Artist inline)

  bool _isLocalImagePath(String path) {
    return path.startsWith('/') || path.startsWith('file://');
  }

  /// Determines which columns to show based on available width
  /// For Apple Music desktop: Album disappears first -> Artist column disappears (goes inline) -> Time disappears
  /// For Spotify desktop: Added At disappears -> Album disappears -> Artist column disappears (goes inline) -> Duration disappears
  ({
    bool showAlbum,
    bool showArtistColumn,
    bool showTime,
    bool showArtistInline,
    bool showAddedAt,
  })
  _getVisibleColumns(double availableWidth) {
    if (availableWidth >= _breakpointFullColumns) {
      // All columns visible
      return (
        showAlbum: true,
        showArtistColumn: true,
        showTime: true,
        showArtistInline: false,
        showAddedAt: true,
      );
    } else if (availableWidth >= _breakpointNoAddedAt) {
      // Hide added at (Spotify), keep album and artist column
      return (
        showAlbum: true,
        showArtistColumn: true,
        showTime: true,
        showArtistInline: false,
        showAddedAt: false,
      );
    } else if (availableWidth >= _breakpointNoAlbum) {
      // Hide album, keep artist column
      return (
        showAlbum: false,
        showArtistColumn: true,
        showTime: true,
        showArtistInline: false,
        showAddedAt: false,
      );
    } else if (availableWidth >= _breakpointNoArtistColumn) {
      // Hide album and artist column, artist goes inline
      return (
        showAlbum: false,
        showArtistColumn: false,
        showTime: true,
        showArtistInline: true,
        showAddedAt: false,
      );
    } else if (availableWidth >= _breakpointNoTime) {
      // Hide time too, artist still inline
      return (
        showAlbum: false,
        showArtistColumn: false,
        showTime: false,
        showArtistInline: true,
        showAddedAt: false,
      );
    } else {
      // Minimal view
      return (
        showAlbum: false,
        showArtistColumn: false,
        showTime: false,
        showArtistInline: true,
        showAddedAt: false,
      );
    }
  }

  bool _preShuffleEnabled = false;
  List<GenericSong> _preShuffledQueue = [];
  final Set<String> _hoveredSongIds = {};
  List<PlaylistItem> _recommendedSongs = [];
  final List<String> _skippedRecommendationTrackIDs = [];
  final Set<String> _addedRecommendationTrackIDs = {};
  final Set<String> _addingRecommendationTrackIDs = {};
  bool _isLoadingRecommendations = false;
  String? _recommendationsError;
  double? _desktopHeaderExtent;

  @override
  void initState() {
    super.initState();
    _spotifyInternal = context.read<SpotifyInternalProvider>();
    unawaited(_spotifyInternal.ensureLikedTracksLoaded());
    _desktopScrollController.addListener(
      () => _handleScroll(_desktopScrollController),
    );
    _mobileScrollController.addListener(
      () => _handleScroll(_mobileScrollController),
    );
    if (widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(widget.id)) {
      _likedTracksListener = () {
        if (!mounted) return;
        setState(_rebuildIndices);
      };
      _spotifyInternal.addListener(_likedTracksListener!);
    }
    _loadListDetails();
  }

  Future<void> _toggleSaveAlbum(bool isSaved) async {
    final album = _album;
    if (album == null) return;
    final spotifyInternal = context.read<SpotifyInternalProvider>();
    if (!spotifyInternal.isAuthenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Spotify (Internal) is not connected.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      if (isSaved) {
        await spotifyInternal.unsaveAlbum(album.id);
        if (mounted) context.read<LibraryState>().removeAlbum(album.id);
      } else {
        await spotifyInternal.saveAlbum(album.id);
        if (mounted) context.read<LibraryState>().addAlbum(album);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSaved ? 'Album removed from library' : 'Album saved',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update album: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    if (_likedTracksListener != null) {
      _spotifyInternal.removeListener(_likedTracksListener!);
    }
    _desktopScrollController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  void _handleScroll(ScrollController controller) {
    if (!controller.hasClients) return;
    if (_hoveredSongIds.isNotEmpty) {
      _hoveredSongIds.clear();
    }
    _updateStickyBarVisibility(controller);
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleStickyBarUpdate(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final headerContext = _headerKey.currentContext;
      final headerBox = headerContext?.findRenderObject() as RenderBox?;
      if (headerBox != null) {
        if (controller == _mobileScrollController) {
          _setMobileHeaderExtent(headerBox.size.height);
        } else if (controller == _desktopScrollController) {
          _setDesktopHeaderExtent(headerBox.size.height);
        }
      }
      _updateStickyBarVisibility(controller);
    });
  }

  void _updateStickyBarVisibility(ScrollController controller) {
    if (!controller.hasClients) return;
    if (controller == _mobileScrollController && _mobileHeaderExtent != null) {
      final actionsContext = _mobileActionsKey.currentContext;
      final scrollable = actionsContext != null
          ? Scrollable.of(actionsContext)
          : null;
      final actionsBox = actionsContext?.findRenderObject() as RenderBox?;
      final scrollBox = scrollable?.context.findRenderObject() as RenderBox?;
      if (actionsBox != null && scrollBox != null) {
        final offset = actionsBox
            .localToGlobal(Offset.zero, ancestor: scrollBox)
            .dy;
        final shouldShow = offset + actionsBox.size.height <= 0 && mounted;
        if (shouldShow != _showStickyBar && mounted) {
          setState(() => _showStickyBar = shouldShow);
        }
        return;
      }

      final threshold = (_mobileHeaderExtent! - kToolbarHeight).clamp(
        0.0,
        double.infinity,
      );
      final shouldShow = controller.offset >= threshold;
      if (shouldShow != _showStickyBar && mounted) {
        setState(() => _showStickyBar = shouldShow);
      }
      return;
    }
    final desktopHeaderExtent = _desktopHeaderExtent;
    if (desktopHeaderExtent != null) {
      final shouldShow = controller.offset >= desktopHeaderExtent && mounted;
      if (shouldShow != _showStickyBar && mounted) {
        setState(() => _showStickyBar = shouldShow);
      }
      return;
    }

    final headerContext = _headerKey.currentContext;
    if (headerContext == null) return;
    final scrollable = Scrollable.of(headerContext);
    final headerBox = headerContext.findRenderObject() as RenderBox?;
    final scrollBox = scrollable.context.findRenderObject() as RenderBox?;
    if (headerBox == null || scrollBox == null) return;
    final offset = headerBox.localToGlobal(Offset.zero, ancestor: scrollBox).dy;
    final shouldShow = offset + headerBox.size.height <= 0 && mounted;
    if (shouldShow != _showStickyBar && mounted) {
      setState(() => _showStickyBar = shouldShow);
    }
  }

  void _setMobileHeaderExtent(double extent) {
    if (_mobileHeaderExtent == extent) return;
    _mobileHeaderExtent = extent;
  }

  void _setDesktopHeaderExtent(double? extent) {
    if (_desktopHeaderExtent == extent) return;
    _desktopHeaderExtent = extent;
  }

  double _scrollBackgroundProgress(ScrollController controller) {
    if (!controller.hasClients) return 0;
    final normalized = (controller.offset / 180).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(normalized);
  }

  Future<void> _updateStickyBarColor(String imageUrl) async {
    if (imageUrl.isEmpty) {
      if (_stickyBarColor != Colors.black && mounted) {
        setState(() => _stickyBarColor = Colors.black);
      }
      return;
    }
    if (_stickyCoverUrl == imageUrl) return;
    _stickyCoverUrl = imageUrl;
    ColorScheme? scheme;
    try {
      final paletteProvider = context.read<CoverArtPaletteProvider>();
      scheme = await paletteProvider.paletteForImageUrl(imageUrl);
    } catch (_) {
      scheme = null;
    }
    if (!mounted || _stickyCoverUrl != imageUrl) return;

    final fakeColor = HSLColor.fromColor(scheme?.primary ?? const Color(0xFF1E1E1E));
    final nextColor = fakeColor.withLightness(
      log(fakeColor.lightness + 1) / log(3)
    ).toColor();

    if (nextColor != _stickyBarColor) {
      setState(() => _stickyBarColor = nextColor);
    }
  }

  void _scheduleSongListOffsetUpdate(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final listContext = _songListKey.currentContext;
      if (listContext == null) return;
      final scrollable = Scrollable.of(listContext);
      final listBox = listContext.findRenderObject() as RenderBox?;
      final scrollBox = scrollable.context.findRenderObject() as RenderBox?;
      if (listBox == null || scrollBox == null) return;
      final listTop = listBox
          .localToGlobal(Offset.zero, ancestor: scrollBox)
          .dy;
      final listStartOffset = controller.offset + listTop;
      if ((listStartOffset - _songListTopOffset).abs() > 1) {
        setState(() {
          _songListTopOffset = listStartOffset;
        });
      }
    });
  }

  Future<void> _loadListDetails() async {
    if (!context.read<PreferencesProvider>().metadataSpotifyEnabled) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    final spotifyInternal = context.read<SpotifyInternalProvider>();
    final localPlaylists = context.read<LocalPlaylistState>();
    setState(() => _isLoading = true);

    try {
      if (widget.type == SharedListType.playlist) {
        if (!isLikedSongsPlaylistId(widget.id) &&
            localPlaylists.isLocalPlaylistId(widget.id)) {
          final localPlaylist = localPlaylists.getGenericPlaylist(widget.id);
          if (localPlaylist != null) {
            _playlist = localPlaylist;
            _rebuildIndices();
            setState(() => _isLoading = false);
          }

          final localEntry = localPlaylists.getById(widget.id);
          if (localEntry?.isLinked == true &&
              localEntry?.linkedSource == SongSource.spotifyInternal &&
              localEntry?.linkedId != null) {
            final providerPlaylist = await _fetchSpotifyPlaylistWithTracks(
              spotifyInternal,
              localEntry!.linkedId!,
            );
            await localPlaylists.syncFromProvider(
              id: widget.id,
              providerTracks: providerPlaylist.songs ?? const [],
            );
            if (mounted) {
              final updated = localPlaylists.getGenericPlaylist(widget.id);
              if (updated != null) {
                _playlist = updated;
                _rebuildIndices();
                setState(() => _isLoading = false);
              }
            }
          }
          return;
        }
        if (isLikedSongsPlaylistId(widget.id)) {
          const limit = 50;
          final items = <PlaylistItem>[];

          final freshFirst = await spotifyInternal.getUserSavedTracks(
            limit: limit,
            offset: 0,
            policy: MetadataFetchPolicy.refreshAlways,
          );
          items.addAll(freshFirst);

          var offset = items.length;
          while (true) {
            final page = await spotifyInternal.getUserSavedTracks(
              limit: limit,
              offset: offset,
              policy: MetadataFetchPolicy.refreshIfExpired,
            );
            if (page.isEmpty) break;
            items.addAll(page);
            offset = items.length;
            if (page.length < limit) break;
          }

          spotifyInternal.setLikedTracksFromItems(items);
          _playlist = _buildLikedSongsPlaylist(
            items,
            spotifyInternal.userDisplayName,
          );
          return;
        }
        _playlist = await _fetchSpotifyPlaylistWithTracks(
          spotifyInternal,
          widget.id,
        );
      } else {
        final album = await spotifyInternal.getAlbumInfo(
          widget.id,
          offset: 0,
          limit: 50,
          policy: MetadataFetchPolicy.refreshAlways,
        );
        final items = <GenericSong>[...?(album.songs)];

        int offset = items.length;
        while (album.hasMore == true && offset < (album.total ?? 0)) {
          final moreAlbum = await spotifyInternal.getAlbumInfo(
            widget.id,
            offset: offset,
            limit: 50,
            policy: MetadataFetchPolicy.refreshIfExpired,
          );
          final more = moreAlbum.songs ?? const <GenericSong>[];
          if (more.isEmpty) break;
          items.addAll(more);
          offset = items.length;
          if (more.length < 50) break;
        }

        _album = GenericAlbum(
          id: album.id,
          source: album.source,
          title: album.title,
          thumbnailUrl: album.thumbnailUrl,
          artists: album.artists,
          label: album.label,
          releaseDate: album.releaseDate,
          explicit: album.explicit,
          songs: items,
          durationSecs: album.durationSecs,
          total: album.total ?? items.length,
          hasMore: false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load list: $e')));
      }
    } finally {
      _rebuildIndices();
      if (mounted) {
        setState(() => _isLoading = false);
      }
      unawaited(_loadRecommendationsIfEligible(forceRefresh: true));
    }
  }

  bool _shouldShowRecommendations() {
    if (widget.type != SharedListType.playlist) return false;
    if (isLikedSongsPlaylistId(widget.id)) return false;
    if (_playlist == null) return false;
    if (_playlist!.source != SongSource.spotifyInternal) return false;
    final localPlaylists = context.read<LocalPlaylistState>();
    if (localPlaylists.isLocalPlaylistId(widget.id)) return false;
    return _playlist!.id.trim().isNotEmpty;
  }

  void _clearRecommendationsState() {
    _recommendedSongs = [];
    _recommendationsError = null;
    _isLoadingRecommendations = false;
    _skippedRecommendationTrackIDs.clear();
    _addedRecommendationTrackIDs.clear();
    _addingRecommendationTrackIDs.clear();
  }

  void _appendSkippedRecommendationTrackIDs(Iterable<String> trackIDs) {
    for (final trackID in trackIDs) {
      final normalized = trackID.trim();
      if (normalized.isEmpty) continue;
      if (_skippedRecommendationTrackIDs.contains(normalized)) continue;
      _skippedRecommendationTrackIDs.add(normalized);
    }
  }

  void _markCurrentRecommendationsAsSkipped() {
    _appendSkippedRecommendationTrackIDs(
      _recommendedSongs
          .where((track) => !_addedRecommendationTrackIDs.contains(track.id))
          .map((track) => track.id),
    );
  }

  Future<void> _loadRecommendationsIfEligible({
    bool forceRefresh = false,
    bool markCurrentAsSkipped = false,
  }) async {
    if (!_shouldShowRecommendations()) {
      if (!mounted) {
        _clearRecommendationsState();
        return;
      }
      setState(_clearRecommendationsState);
      return;
    }

    if (_isLoadingRecommendations) return;
    if (!forceRefresh && _recommendedSongs.isNotEmpty) return;

    final playlistID = _playlist?.id ?? widget.id;
    if (playlistID.trim().isEmpty) return;

    if (markCurrentAsSkipped) {
      _markCurrentRecommendationsAsSkipped();
    }

    if (mounted) {
      setState(() {
        _isLoadingRecommendations = true;
        _recommendationsError = null;
      });
    } else {
      _isLoadingRecommendations = true;
      _recommendationsError = null;
    }

    try {
      final recommendations = await _spotifyInternal.getRecommended(
        playlistID,
        _skippedRecommendationTrackIDs,
        numResults: 20,
      );
      if (!mounted) {
        _recommendedSongs = recommendations.take(10).toList();
        _isLoadingRecommendations = false;
        return;
      }
      setState(() {
        _recommendedSongs = recommendations.take(10).toList();
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      if (!mounted) {
        _recommendationsError = 'Failed to load recommendations: $e';
        _isLoadingRecommendations = false;
        return;
      }
      setState(() {
        _recommendationsError = 'Failed to load recommendations: $e';
        _isLoadingRecommendations = false;
      });
    }
  }

  Future<void> _refreshRecommendations() async {
    await _loadRecommendationsIfEligible(
      forceRefresh: true,
      markCurrentAsSkipped: true,
    );
  }

  Future<void> _addRecommendedTrack(PlaylistItem item) async {
    final playlist = _playlist;
    if (playlist == null || item.id.trim().isEmpty) return;
    if (_addingRecommendationTrackIDs.contains(item.id)) return;
    if (_addedRecommendationTrackIDs.contains(item.id)) return;

    setState(() {
      _addingRecommendationTrackIDs.add(item.id);
    });

    try {
      await _spotifyInternal.addTracksToPlaylist(playlist.id, [item.id]);
      if (!mounted) return;
      setState(() {
        _addingRecommendationTrackIDs.remove(item.id);
        _addedRecommendationTrackIDs.add(item.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to playlist'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addingRecommendationTrackIDs.remove(item.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add track: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _playRecommendedAt(int index) async {
    if (index < 0 || index >= _recommendedSongs.length) return;
    final queue = _recommendedSongs.map(_toGenericSong).toList();
    if (queue.isEmpty) return;

    final playlist = _playlist;
    final libraryFolders = context.read<LibraryFolderState>();
    await context.read<PlaybackCoordinator>().setQueue(
      queue,
      startIndex: index,
      play: true,
      contextType: 'playlist',
      contextName: playlist?.title ?? '',
      contextID: playlist?.id ?? widget.id,
      contextSource: playlist?.source,
      shuffleEnabled: false,
    );
    if (!mounted) return;

    if (widget.type == SharedListType.playlist) {
      libraryFolders.markPlaylistPlayed(widget.id);
    }
  }

  Future<void> _toggleRecommendedTrackPlayback(
    global_audio_player.WispAudioHandler player,
    int index,
  ) async {
    if (index < 0 || index >= _recommendedSongs.length) return;
    final song = _toGenericSong(_recommendedSongs[index]);
    final isCurrentTrack = player.currentTrack?.id == song.id;
    if (isCurrentTrack) {
      _toggleCurrentTrackPlayback(player);
      return;
    }
    await _playRecommendedAt(index);
  }

  void _toggleCurrentTrackPlayback(
    global_audio_player.WispAudioHandler player,
  ) {
    final coordinator = context.read<PlaybackCoordinator>();
    if (player.isPlaying) {
      unawaited(coordinator.pause());
      return;
    }

    if (player.isLoading || player.isBuffering) {
      return;
    }

    unawaited(coordinator.play());
  }

  Future<GenericPlaylist> _fetchSpotifyPlaylistWithTracks(
    SpotifyInternalProvider spotify,
    String playlistId,
  ) async {
    final playlist = await spotify.getPlaylistInfo(
      playlistId,
      offset: 0,
      limit: 50,
      policy: MetadataFetchPolicy.refreshAlways,
    );
    final items = <PlaylistItem>[...?(playlist.songs)];

    int offset = items.length;
    while (playlist.hasMore == true && offset < (playlist.total ?? 0)) {
      final morePlaylist = await spotify.getPlaylistInfo(
        playlistId,
        offset: offset,
        limit: 50,
        policy: MetadataFetchPolicy.refreshIfExpired,
      );
      final more = morePlaylist.songs ?? const <PlaylistItem>[];
      if (more.isEmpty) break;
      items.addAll(more);
      offset = items.length;
      if (more.length < 50) break;
    }

    return GenericPlaylist(
      id: playlist.id,
      source: playlist.source,
      title: playlist.title,
      description: playlist.description,
      thumbnailUrl: playlist.thumbnailUrl,
      author: playlist.author,
      songs: items,
      durationSecs: playlist.durationSecs,
      total: playlist.total ?? items.length,
      hasMore: false,
    );
  }

  GenericPlaylist _buildLikedSongsPlaylist(
    List<PlaylistItem> items,
    String? displayName,
  ) {
    final durationSecs = items.fold<int>(
      0,
      (sum, item) => sum + item.durationSecs,
    );
    return GenericPlaylist(
      id: likedSongsPlaylistId,
      source: SongSource.spotifyInternal,
      title: likedSongsTitle,
      thumbnailUrl: '',
      author: GenericSimpleUser(
        id: 'liked_songs_user',
        source: SongSource.spotifyInternal,
        displayName: displayName ?? 'You',
      ),
      songs: items,
      durationSecs: durationSecs,
      total: items.length,
      hasMore: false,
    );
  }

  List<_ListItem> get _items {
    if (widget.type == SharedListType.playlist) {
      if (isLikedSongsPlaylistId(widget.id)) {
        final items = _playlist?.songs ?? [];
        final spotifyInternal = context.read<SpotifyInternalProvider>();
        return items
            .where((item) => spotifyInternal.isTrackLiked(item.id))
            .toList();
      }
      return _playlist?.songs ?? [];
    }
    return _album?.songs ?? [];
  }

  void _rebuildIndices() {
    final items = _items;
    final indices = List<int>.generate(items.length, (i) => i);

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      indices.removeWhere((i) => !_matchesQuery(items[i], query));
    }

    indices.sort((a, b) {
      int compare;
      switch (_sortMethod) {
        case _SortMethod.position:
          compare = a.compareTo(b);
          break;
        case _SortMethod.title:
          compare = _getTitle(items[a]).compareTo(_getTitle(items[b]));
          break;
        case _SortMethod.author:
          final authorA = _getAuthor(items[a]).toLowerCase();
          final authorB = _getAuthor(items[b]).toLowerCase();
          compare = authorA.compareTo(authorB);
          if (compare == 0) {
            final albumA = _getAlbumTitle(items[a]).toLowerCase();
            final albumB = _getAlbumTitle(items[b]).toLowerCase();
            compare = albumA.compareTo(albumB);
            if (compare == 0) {
              compare = _getTitle(
                items[a],
              ).toLowerCase().compareTo(_getTitle(items[b]).toLowerCase());
            }
          }
          break;
        case _SortMethod.album:
          compare = _getAlbumTitle(
            items[a],
          ).compareTo(_getAlbumTitle(items[b]));
          break;
        case _SortMethod.addedAt:
          final addedA = _getAddedAt(items[a]);
          final addedB = _getAddedAt(items[b]);
          if (addedA == null && addedB == null) {
            compare = 0;
          } else if (addedA == null) {
            compare = -1;
          } else if (addedB == null) {
            compare = 1;
          } else {
            compare = addedA.compareTo(addedB);
          }
          break;
        case _SortMethod.duration:
          compare = _getDuration(items[a]).compareTo(_getDuration(items[b]));
          break;
        case _SortMethod.source:
          compare = _getSource(items[a]).compareTo(_getSource(items[b]));
          break;
      }
      return _ascending ? compare : -compare;
    });

    _sortedIndices = indices;
  }

  bool _matchesQuery(_ListItem item, String query) {
    final title = _getTitle(item).toLowerCase();
    final author = _getAuthor(item).toLowerCase();
    final album = _getAlbumTitle(item).toLowerCase();
    return title.contains(query) ||
        author.contains(query) ||
        album.contains(query);
  }

  void _sortBy(_SortMethod method, {bool? ascending}) {
    if (ascending != null) {
      _ascending = ascending;
      _sortMethod = method;
    } else if (method == _sortMethod) {
      if (_ascending) {
        _ascending = false;
      } else {
        _sortMethod = _SortMethod.position;
        _ascending = true;
      }
    } else {
      _sortMethod = method;
      _ascending = true;
    }
    setState(_rebuildIndices);
  }

  void _handleTitleHeaderTap() {
    if (_sortMethod == _SortMethod.title && _ascending) {
      _sortBy(_SortMethod.title, ascending: false);
    } else if (_sortMethod == _SortMethod.title && !_ascending) {
      _sortBy(_SortMethod.author, ascending: true);
    } else if (_sortMethod == _SortMethod.author && _ascending) {
      _sortBy(_SortMethod.author, ascending: false);
    } else if (_sortMethod == _SortMethod.author && !_ascending) {
      _sortBy(_SortMethod.title, ascending: true);
    } else {
      _sortBy(_SortMethod.title, ascending: true);
    }
  }

  String _getTitle(_ListItem item) {
    if (item is GenericSong) return item.title;
    if (item is PlaylistItem) return item.title;
    return '';
  }

  String _getAuthor(_ListItem item) {
    final artists = _getArtists(item);
    if (artists.isEmpty) return '';
    return artists.first.name;
  }

  String _getAlbumTitle(_ListItem item) {
    if (item is GenericSong) return item.album?.title ?? '';
    if (item is PlaylistItem) return item.album?.title ?? '';
    return '';
  }

  GenericSimpleAlbum? _getAlbum(_ListItem item) {
    if (item is GenericSong) return item.album;
    if (item is PlaylistItem) return item.album;
    return null;
  }

  int _getDuration(_ListItem item) {
    if (item is GenericSong) return item.durationSecs;
    if (item is PlaylistItem) return item.durationSecs;
    return 0;
  }

  DateTime? _getAddedAt(_ListItem item) {
    if (item is PlaylistItem) return item.addedAt;
    return null;
  }

  String _formatAddedAt(DateTime? date) {
    if (date == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[(date.month - 1).clamp(0, 11)];
    return '$month ${date.day}, ${date.year}';
  }

  String _getSource(_ListItem item) {
    if (item is GenericSong) return item.source.name;
    if (item is PlaylistItem) return item.source.name;
    return '';
  }

  List<GenericSimpleArtist> _getArtists(_ListItem item) {
    if (item is GenericSong) return item.artists;
    if (item is PlaylistItem) return item.artists;
    return [];
  }

  GenericSong _toGenericSong(_ListItem item) {
    if (item is GenericSong) return item;
    if (item is PlaylistItem) {
      return GenericSong(
        id: item.id,
        source: item.source,
        title: item.title,
        artists: item.artists,
        thumbnailUrl: item.thumbnailUrl,
        explicit: item.explicit,
        album: item.album,
        durationSecs: item.durationSecs,
      );
    }
    return GenericSong(
      id: '',
      source: SongSource.spotify,
      title: '',
      artists: [],
      thumbnailUrl: '',
      explicit: false,
      durationSecs: 0,
    );
  }

  List<GenericSong> _buildQueueSongs() {
    return _sortedIndices
        .map((index) => _toGenericSong(_items[index]))
        .toList();
  }

  Future<void> _playQueueAt(int index) async {
    final player = context.read<global_audio_player.WispAudioHandler>();
    if (widget.type == SharedListType.playlist) {
      context.read<LibraryFolderState>().markPlaylistPlayed(widget.id);
    }
    final originalQueue = _buildQueueSongs();
    final queue = List<GenericSong>.from(originalQueue);
    if (queue.isEmpty || index < 0 || index >= queue.length) return;

    final contextType = widget.type == SharedListType.playlist
        ? 'playlist'
        : 'album';
    final contextName = widget.type == SharedListType.playlist
        ? (_playlist?.title ?? '')
        : (_album?.title ?? '');
    final contextID = widget.id;
    final contextSource = widget.type == SharedListType.playlist
        ? _playlist?.source
        : _album?.source;

    var startIndex = index;
    if (player.shuffleEnabled && queue.length > 1) {
      final current = queue[index];
      queue.removeAt(index);
      queue.shuffle(Random());
      queue.insert(0, current);
      startIndex = 0;
    }

    await context.read<PlaybackCoordinator>().setQueue(
      queue,
      startIndex: startIndex,
      play: true,
      contextType: contextType,
      contextName: contextName,
      contextID: contextID,
      contextSource: contextSource,
      shuffleEnabled: player.shuffleEnabled,
      originalQueue: player.shuffleEnabled ? originalQueue : null,
    );
    if (widget.type == SharedListType.playlist) {
      if (mounted) {
        context.read<LibraryFolderState>().markPlaylistPlayed(widget.id);
      }
    }
    if (_preShuffleEnabled) {
      setState(() {
        _preShuffleEnabled = false;
        _preShuffledQueue = [];
      });
    }
  }

  Future<void> _playFromStart({bool shuffle = false}) async {
    final player = context.read<global_audio_player.WispAudioHandler>();
    if (widget.type == SharedListType.playlist) {
      context.read<LibraryFolderState>().markPlaylistPlayed(widget.id);
    }
    final originalQueue = _buildQueueSongs();
    final queue = _preShuffleEnabled
        ? List<GenericSong>.from(_preShuffledQueue)
        : List<GenericSong>.from(originalQueue);
    if (queue.isEmpty) return;

    final shouldShuffle = shuffle || player.shuffleEnabled;
    if (!_preShuffleEnabled && shouldShuffle) {
      queue.shuffle(Random());
    }

    final contextType = widget.type == SharedListType.playlist
        ? 'playlist'
        : 'album';
    final contextName = widget.type == SharedListType.playlist
        ? (_playlist?.title ?? '')
        : (_album?.title ?? '');
    final contextID = widget.id;
    final contextSource = widget.type == SharedListType.playlist
        ? _playlist?.source
        : _album?.source;

    await context.read<PlaybackCoordinator>().setQueue(
      queue,
      startIndex: 0,
      play: true,
      contextType: contextType,
      contextName: contextName,
      contextID: contextID,
      contextSource: contextSource,
      shuffleEnabled: _preShuffleEnabled || shouldShuffle,
      originalQueue: (_preShuffleEnabled || shouldShuffle)
          ? originalQueue
          : null,
    );
    if (widget.type == SharedListType.playlist) {
      if (mounted) {
        context.read<LibraryFolderState>().markPlaylistPlayed(widget.id);
      }
    }
    if (_preShuffleEnabled) {
      setState(() {
        _preShuffleEnabled = false;
        _preShuffledQueue = [];
      });
    }
  }

  bool _isCurrentListPlaying(global_audio_player.WispAudioHandler player) {
    final contextType = widget.type == SharedListType.playlist
        ? 'playlist'
        : 'album';
    final contextName = widget.type == SharedListType.playlist
        ? (_playlist?.title ?? '')
        : (_album?.title ?? '');
    final contextId = widget.id;

    if (player.currentTrack == null ||
        player.playbackContextType != contextType) {
      return false;
    }

    final playerContextId = player.playbackContextID;
    if (playerContextId != null && playerContextId.isNotEmpty) {
      return playerContextId == contextId;
    }

    final playerContextName = player.playbackContextName;
    if (playerContextName == null || playerContextName.isEmpty) {
      return false;
    }

    return playerContextName == contextName;
  }

  void _toggleListShuffle(global_audio_player.WispAudioHandler player) {
    if (_isCurrentListPlaying(player)) {
      player.toggleShuffle();
      return;
    }

    setState(() {
      _preShuffleEnabled = !_preShuffleEnabled;
      if (_preShuffleEnabled) {
        final queue = _buildQueueSongs();
        _preShuffledQueue = List<GenericSong>.from(queue)..shuffle(Random());
      } else {
        _preShuffledQueue = [];
      }
    });
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  /// Download all tracks in the list
  Future<void> _downloadAll() async {
    final tracks = _buildQueueSongs();
    if (tracks.isEmpty) return;

    final cacheManager = AudioCacheManager.instance;
    final alreadyCached = tracks
        .where((t) => cacheManager.isTrackCached(t.id))
        .length;
    final toDownload = tracks.length - alreadyCached;

    if (toDownload == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All tracks are already cached'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text(
          'Download All',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Download $toDownload tracks for offline playback?\n\n${alreadyCached > 0 ? '$alreadyCached tracks already cached.' : ''}',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) {
        return;
      }
      final player = context.read<global_audio_player.WispAudioHandler>();
      final results = await player.downloadTracks(tracks);
      if (mounted) {
        final queued = results[QueueDownloadResult.queued] ?? 0;
        final blockedPolicy =
            results[QueueDownloadResult.blockedByNetworkPolicy] ?? 0;
        final blockedNetworkOnly =
            results[QueueDownloadResult.blockedByNetworkOnlyMode] ?? 0;

        var message =
            'Queued $queued track${queued == 1 ? '' : 's'} for download';
        if (queued == 0 && (blockedPolicy > 0 || blockedNetworkOnly > 0)) {
          message = blockedPolicy > 0
              ? 'Downloads blocked by your WiFi/Ethernet-only setting'
              : 'Downloads blocked because Network-only mode is enabled';
        } else if (blockedPolicy > 0 || blockedNetworkOnly > 0) {
          message += ' • ${blockedPolicy + blockedNetworkOnly} blocked';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

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

  Future<void> _appendTracksToQueue(
    List<GenericSong> tracks, {
    required String contextType,
    required String contextName,
    SongSource? contextSource,
  }) async {
    if (tracks.isEmpty) return;

    final player = context.read<global_audio_player.WispAudioHandler>();
    final mergedQueue = List<GenericSong>.from(player.queueTracks);
    final seen = mergedQueue
        .map((track) => '${track.source.name}:${track.id}')
        .toSet();

    var addedCount = 0;
    for (final track in tracks) {
      final key = '${track.source.name}:${track.id}';
      if (seen.add(key)) {
        mergedQueue.add(track);
        addedCount += 1;
      }
    }

    if (addedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All tracks are already in queue')),
      );
      return;
    }

    var startIndex = 0;
    final currentTrackId = player.currentTrack?.id;
    if (currentTrackId != null) {
      final foundIndex = mergedQueue.indexWhere(
        (track) => track.id == currentTrackId,
      );
      if (foundIndex >= 0) {
        startIndex = foundIndex;
      }
    }

    await context.read<PlaybackCoordinator>().setQueue(
      mergedQueue,
      startIndex: startIndex,
      play: player.currentTrack != null ? player.isPlaying : false,
      contextType: player.playbackContextType ?? contextType,
      contextName: player.playbackContextName ?? contextName,
      contextID: player.playbackContextID,
      contextSource: player.playbackContextSource ?? contextSource,
      shuffleEnabled: player.shuffleEnabled,
      originalQueue: player.shuffleEnabled
          ? List<GenericSong>.from(player.originalQueueTracks)
          : null,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added $addedCount track${addedCount == 1 ? '' : 's'} to queue',
        ),
      ),
    );
  }

  IconData _sourceIcon(SongSource source) {
    switch (source) {
      case SongSource.youtube:
        return Icons.ondemand_video;
      case SongSource.soundcloud:
        return Icons.cloud;
      case SongSource.spotify:
      case SongSource.spotifyInternal:
      case SongSource.local:
        return Icons.music_note;
    }
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
  }) async {
    unawaited(_spotifyInternal.ensureLikedTracksLoaded());

    final hasLikedTracksState = _spotifyInternal.hasLoadedLikedTracks;
    final isLiked =
        hasLikedTracksState && _spotifyInternal.isTrackLiked(song.id);
    final cacheManager = AudioCacheManager.instance;
    final isCached = cacheManager.isTrackCached(song.id);
    final isDownloading = cacheManager.isDownloading(song.id);
    final progress = cacheManager.getDownloadProgress(song.id) ?? 0;
    final hasAlbum = song.album != null && song.album!.id.isNotEmpty;
    final hasOneArtist = song.artists.length == 1;

    final cacheLabel = isDownloading
        ? 'Downloading ${(progress * 100).toStringAsFixed(0)}%'
        : (isCached ? 'Remove from Audio Cache' : 'Add to Audio Cache');

    final actions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'likes-toggle',
        label: hasLikedTracksState
            ? (isLiked ? 'Remove from Likes' : 'Add to Likes')
            : 'Like / Unlike',
        icon: hasLikedTracksState && isLiked
            ? Icons.favorite
            : Icons.favorite_border,
        iconColor: isLiked ? Theme.of(context).colorScheme.primary : null,
        onSelected: (_) => _spotifyInternal.toggleTrackLike(song),
      ),
      ContextMenuAction(
        id: 'playlist-add',
        label: 'Add to Playlist',
        icon: Icons.playlist_add,
        onSelected: (_) async {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add to playlist placeholder')),
          );
        },
      ),
      ContextMenuAction(
        id: 'cache-toggle',
        label: cacheLabel,
        icon: isCached ? Icons.delete_outline : Icons.download_outlined,
        iconColor: isCached ? Theme.of(context).colorScheme.primary : null,
        enabled: !isDownloading,
        onSelected: (_) async {
          if (isCached) {
            await cacheManager.removeFromCache(song.id);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Removed from audio cache')),
            );
            return;
          }

          final player = context.read<global_audio_player.WispAudioHandler>();
          final result = await player.downloadTrack(song);
          if (!mounted) return;
          final message = switch (result) {
            QueueDownloadResult.queued => 'Queued track for download',
            QueueDownloadResult.alreadyCached => 'Track already cached',
            QueueDownloadResult.alreadyQueued =>
              'Track already in download queue',
            QueueDownloadResult.blockedByNetworkPolicy =>
              'Downloads blocked by your WiFi/Ethernet-only setting',
            QueueDownloadResult.blockedByNetworkOnlyMode =>
              'Downloads blocked because Network-only mode is enabled',
          };
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        },
      ),
      ContextMenuAction(
        id: 'youtube-alt',
        label: 'Search Alternatives',
        icon: Icons.ondemand_video,
        onSelected: (_) async {
          final player = context.read<global_audio_player.WispAudioHandler>();
          final previousVideoId = YouTubeProvider.getCachedVideoId(song.id);
          final selectedVideoId = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => YouTubeAlternativesView(track: song),
            ),
          );
          if (!mounted || selectedVideoId == null) return;

          final hasChanged = selectedVideoId.isEmpty
              ? previousVideoId != null
              : previousVideoId != selectedVideoId;

          if (selectedVideoId.isEmpty) {
            await YouTubeProvider.removeCachedVideoId(song.id);
            if (hasChanged) {
              await player.onYouTubeAlternativeUpdated(
                song.id,
                previousVideoId: previousVideoId,
              );
            }
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('YouTube mapping cleared')),
            );
            return;
          }
          await YouTubeProvider.setCachedVideoId(song.id, selectedVideoId);
          if (hasChanged) {
            await player.onYouTubeAlternativeUpdated(
              song.id,
              previousVideoId: previousVideoId,
            );
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('YouTube alternative saved')),
          );
        },
      ),
      ContextMenuAction(
        id: 'share',
        label: 'Share',
        icon: Icons.share,
        onSelected: (_) async {
          await EntityContextMenus.copySpotifyShareUrl(
            context,
            source: song.source,
            type: 'track',
            id: song.id,
          );
        },
      ),
      if (hasAlbum)
        ContextMenuAction(
          id: 'go-album',
          label: 'Go to Album',
          icon: Icons.album,
          onSelected: (_) async {
            final album = song.album!;
            _openSharedList(
              SharedListType.album,
              album.id,
              title: album.title,
              thumbnailUrl: album.thumbnailUrl,
            );
          },
        ),
      if (hasOneArtist)
        ContextMenuAction(
          id: 'go-artist',
          label: 'Go to Artist',
          icon: Icons.person,
          onSelected: (_) async => _openArtist(song.artists.first),
        )
      else
        ContextMenuAction(
          id: 'artists-submenu',
          label: 'Artists',
          icon: Icons.groups,
          children: [
            for (final artist in song.artists)
              ContextMenuAction(
                id: 'artist-${artist.id}',
                label: artist.name,
                icon: Icons.person_outline,
                onSelected: (_) async => _openArtist(artist),
              ),
          ],
        ),
    ];

    await showAdaptiveContextMenu(
      context: context,
      actions: actions,
      anchorRect: _anchorRectFromContext(anchorContext),
      globalPosition: globalPosition,
      mobileHeaderBuilder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: CachedNetworkImage(
                    imageUrl: song.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[900],
                      child: Icon(Icons.music_note, color: Colors.grey[600]),
                    ),
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[850]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artists.map((artist) => artist.name).join(', '),
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(_sourceIcon(song.source), color: Colors.grey[300]),
            ],
          ),
        );
      },
    );
  }

  void _showShareDialog() {
    final isSpotify =
        _playlist?.source == SongSource.spotify ||
        _playlist?.source == SongSource.spotifyInternal ||
        _album?.source == SongSource.spotify ||
        _album?.source == SongSource.spotifyInternal ||
        widget.id.startsWith('spotify:');

    if (isSpotify) {
      final typePath = widget.type == SharedListType.playlist
          ? 'playlist'
          : 'album';
      final id = widget.id.split(':').last;
      final url = 'https://open.spotify.com/$typePath/$id';

      Clipboard.setData(ClipboardData(text: url)).then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link copied to clipboard')),
          );
        }
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share not implemented for this source yet'),
      ),
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

  /// Build cache indicator widget for a track
  Widget _buildCacheIndicator(String trackId) {
    return AnimatedBuilder(
      animation: AudioCacheManager.instance,
      builder: (context, _) {
        final cacheManager = AudioCacheManager.instance;
        final isCached = cacheManager.isTrackCached(trackId);
        final isDownloading = cacheManager.isDownloading(trackId);

        if (!isCached && !isDownloading) {
          return const SizedBox(width: 20);
        }

        if (isDownloading) {
          final progress = cacheManager.getDownloadProgress(trackId) ?? 0;
          return SizedBox(
            width: 20,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor: Colors.grey[800],
                  ),
                ),
              ],
            ),
          );
        }

        return SizedBox(
          width: 20,
          child: Icon(
            Icons.download_done,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }

  int _totalDurationSecs() {
    return _items.fold<int>(0, (sum, item) => sum + _getDuration(item));
  }

  void _openSharedList(
    SharedListType type,
    String id, {
    String? title,
    String? thumbnailUrl,
  }) {
    AppNavigation.instance.openSharedList(
      context,
      id: id,
      type: type,
      initialTitle: title,
      initialThumbnailUrl: thumbnailUrl,
    );
  }

  void _openArtist(GenericSimpleArtist artist) {
    AppNavigation.instance.openArtist(
      context,
      artistId: artist.id,
      initialArtist: artist,
    );
  }

  void _openUser(GenericSimpleUser user) {
    AppNavigation.instance.openUser(
      context,
      userId: user.id,
      initialUser: GenericUser(
        id: user.id,
        source: user.source,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        followerCount: user.followerCount,
        followingCount: null,
        recentArtists: const [],
        publicPlaylists: const [],
        followers: const [],
        following: const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<PreferencesProvider>();
    if (!preferences.metadataSpotifyEnabled) {
      return const ProviderDisabledState();
    }
    final style = preferences.style;

    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final title =
        widget.initialTitle ?? _playlist?.title ?? _album?.title ?? '';
    final imageUrl =
        widget.initialThumbnailUrl ??
        _playlist?.thumbnailUrl ??
        _album?.thumbnailUrl ??
        '';
    final subtitle = widget.type == SharedListType.playlist
        ? _playlist?.author.displayName
        : _album?.artists.map((a) => a.name).join(', ');

    final subtitleUser = widget.type == SharedListType.playlist
        ? _playlist?.author
        : null;

    final subtitleImageUrl = widget.type == SharedListType.playlist
        ? _playlist?.author.avatarUrl
        : (_album != null && _album!.artists.isNotEmpty)
        ? _album!.artists.first.thumbnailUrl
        : null;

    final total = widget.type == SharedListType.playlist
        ? (_playlist?.total ?? _items.length)
        : (_album?.total ?? _items.length);

    final description = widget.type == SharedListType.playlist
        ? _playlist?.description
        : null;

    _updateStickyBarColor(imageUrl);

    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _buildListContentByStyle(
            style: style,
            title: title,
            subtitle: subtitle,
            subtitleUser: subtitleUser,
            imageUrl: imageUrl,
            subtitleImageUrl: subtitleImageUrl,
            total: total,
            isDesktop: isDesktop,
            description: description,
          );

    if (isDesktop) {
      return Scaffold(backgroundColor: Colors.transparent, body: content);
    }

    if (style == 'Apple Music') {
      final contentSurfaceColor = Theme.of(context).colorScheme.surface;
      return Scaffold(
        backgroundColor: contentSurfaceColor,
        extendBodyBehindAppBar: true,
        appBar: _isLoading
            ? AppBar(
                backgroundColor: contentSurfaceColor,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(CupertinoIcons.back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              )
            : null,
        body: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        clipBehavior: Clip.none,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: AnimatedOpacity(
          opacity: _showStickyBar ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _showStickyBar
              ? Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _showStickyBar
                ? _buildStickyPlayAction(useAppleStyle: false, protrude: true)
                : const SizedBox.shrink(),
          ),
          if (!_showStickyBar) _buildSortButton(),
        ],
      ),
      body: content,
    );
  }

  Widget _buildStickyPlayAction({
    required bool useAppleStyle,
    required bool protrude,
  }) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final isPlayingList = _isCurrentListPlaying(player) && player.isPlaying;
        final colorScheme = Theme.of(context).colorScheme;
        final icon = isPlayingList ? Icons.pause : Icons.play_arrow;
        void onPressed() {
          if (_items.isEmpty) return;
          if (_isCurrentListPlaying(player)) {
            _toggleCurrentTrackPlayback(player);
          } else {
            _playFromStart();
          }
        }

        final button = useAppleStyle
            ? FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(72, 44),
                  shape: const StadiumBorder(),
                ),
                child: Icon(icon, size: 20),
              )
            : Material(
                color: colorScheme.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPressed,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(icon, color: colorScheme.onPrimary, size: 32),
                  ),
                ),
              );

        if (!protrude) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: button,
          );
        }

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            width: useAppleStyle ? 88 : 70,
            height: kToolbarHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [Positioned(bottom: -20, child: button)],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSortButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: PopupMenuButton<_SortMethod>(
        icon: const Icon(Icons.sort),
        onSelected: (method) => _sortBy(method),
        itemBuilder: (context) => [
          _buildSortMenuItem(_SortMethod.position, 'Original Order'),
          _buildSortMenuItem(_SortMethod.title, 'Title'),
          _buildSortMenuItem(_SortMethod.author, 'Artist'),
          if (widget.type == SharedListType.playlist)
            _buildSortMenuItem(_SortMethod.album, 'Album'),
          if (widget.type == SharedListType.playlist)
            _buildSortMenuItem(_SortMethod.addedAt, 'Date Added'),
        ],
      ),
    );
  }

  PopupMenuItem<_SortMethod> _buildSortMenuItem(
    _SortMethod method,
    String label,
  ) {
    return PopupMenuItem<_SortMethod>(value: method, child: Text(label));
  }

  Widget _buildListContentByStyle({
    required String style,
    required String title,
    required String? subtitle,
    required GenericSimpleUser? subtitleUser,
    required String? subtitleImageUrl,
    required String imageUrl,
    required int total,
    required bool isDesktop,
    required String? description,
  }) {
    switch (style) {
      case 'Apple Music':
        return _AppleMusicListDetailRenderer(
          view: this,
          title: title,
          subtitle: subtitle,
          subtitleUser: subtitleUser,
          subtitleImageUrl: subtitleImageUrl,
          imageUrl: imageUrl,
          total: total,
          isDesktop: isDesktop,
          description: description,
        );
      case 'YouTube Music':
        return _SpotifyListDetailRenderer(
          view: this,
          title: title,
          subtitle: subtitle,
          subtitleUser: subtitleUser,
          subtitleImageUrl: subtitleImageUrl,
          imageUrl: imageUrl,
          total: total,
          isDesktop: isDesktop,
          description: description,
        );
      case 'Spotify':
      default:
        return _SpotifyListDetailRenderer(
          view: this,
          title: title,
          subtitle: subtitle,
          subtitleUser: subtitleUser,
          subtitleImageUrl: subtitleImageUrl,
          imageUrl: imageUrl,
          total: total,
          isDesktop: isDesktop,
          description: description,
        );
    }
  }

  Widget _buildMobileHeader(
    String title,
    String? subtitle,
    GenericSimpleUser? subtitleUser,
    String imageUrl,
    int total,
    String? description,
  ) {
    final descriptionText = description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;
    final isLiked =
        widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(widget.id);
    return Column(
      children: [
        // Album art - 70% width as per old design
        Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.grey[900],
                  child: isLiked
                      ? const LikedSongsArt()
                      : (imageUrl.isNotEmpty
                            ? (_isLocalImagePath(imageUrl)
                                  ? Image.file(
                                      File(
                                        imageUrl.replaceFirst('file://', ''),
                                      ),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, url, error) =>
                                          Icon(
                                            widget.type ==
                                                    SharedListType.playlist
                                                ? Icons.playlist_play
                                                : Icons.album,
                                            color: Colors.grey[600],
                                            size: 64,
                                          ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: Colors.grey[800],
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Icon(
                                            widget.type ==
                                                    SharedListType.playlist
                                                ? Icons.playlist_play
                                                : Icons.album,
                                            color: Colors.grey[600],
                                            size: 64,
                                          ),
                                    ))
                            : Icon(
                                widget.type == SharedListType.playlist
                                    ? Icons.playlist_play
                                    : Icons.album,
                                color: Colors.grey[600],
                                size: 64,
                              )),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Title and info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    Text(
                      ' • ',
                      style: TextStyle(color: Colors.grey[500], fontSize: 20),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: subtitleUser == null
                            ? null
                            : () => _openUser(subtitleUser),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            color: subtitleUser == null
                                ? Colors.grey[400]
                                : Colors.white,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(_totalDurationSecs()),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  Text(' • ', style: TextStyle(color: Colors.grey[500])),
                  Text(
                    '$total songs',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
              if (hasDescription) ...[
                const SizedBox(height: 6),
                buildParsedText(
                  context,
                  descriptionText,
                  linkStyle: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 13,
                  ),
                  style: TextStyle(color: Colors.grey[300], fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileActionsRow() {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final shuffleActive = (_isCurrentListPlaying(player)
            ? player.shuffleEnabled
            : _preShuffleEnabled);
        final repeatActive =
            player.repeatMode != global_audio_player.RepeatMode.off;
        return SizedBox(
          height: 56,
          child: Row(
            children: [
              // Left side: Download + More
              IconButton(
                icon: const Icon(Icons.download_outlined),
                color: Colors.white,
                onPressed: () => _downloadAll(),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz),
                color: Colors.white,
                onPressed: () => _showListContextMenu(),
              ),
              const Spacer(),
              // Right side: Loop + Shuffle + Play
              IconButton(
                icon: Icon(
                  player.repeatMode == global_audio_player.RepeatMode.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                ),
                color: repeatActive ? colorScheme.primary : Colors.white,
                onPressed: player.toggleRepeat,
              ),
              IconButton(
                icon: const Icon(Icons.shuffle),
                color: shuffleActive ? colorScheme.primary : Colors.white,
                onPressed: () => _toggleListShuffle(player),
              ),
              const SizedBox(width: 8),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.play_arrow, size: 32),
                  color: colorScheme.onPrimary,
                  onPressed: () {
                    if (_items.isNotEmpty) {
                      _playFromStart();
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    String title,
    String? subtitle,
    GenericSimpleUser? subtitleUser,
    String? subtitleImageUrl,
    String imageUrl,
    int total,
    String? description,
  ) {
    final descriptionText = description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;
    final isLiked =
        widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(widget.id);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      decoration: const BoxDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 176,
              height: 176,
              color: Colors.grey[900],
              child: isLiked
                  ? const LikedSongsArt()
                  : (imageUrl.isNotEmpty
                        ? (_isLocalImagePath(imageUrl)
                              ? Image.file(
                                  File(imageUrl.replaceFirst('file://', '')),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, url, error) =>
                                      Container(color: Colors.grey[800]),
                                )
                              : CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(color: Colors.grey[800]),
                                ))
                        : Icon(
                            widget.type == SharedListType.playlist
                                ? Icons.playlist_play
                                : Icons.album,
                            color: Colors.grey[600],
                            size: 48,
                          )),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  widget.type == SharedListType.playlist ? 'PLAYLIST' : 'ALBUM',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    height: 0.95,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasDescription) const SizedBox(height: 4),
                if (hasDescription)
                  buildParsedText(
                    context,
                    descriptionText,
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                    ),
                    linkStyle: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (subtitleImageUrl != null) ...[
                      MouseRegion(
                        cursor: subtitleUser == null
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: subtitleUser == null
                              ? null
                              : () => _openUser(subtitleUser),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 24,
                              height: 24,
                              color: Colors.grey[900],
                              child: _isLocalImagePath(subtitleImageUrl)
                                  ? Image.file(
                                      File(
                                        subtitleImageUrl.replaceFirst(
                                          'file://',
                                          '',
                                        ),
                                      ),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, url, error) =>
                                          Container(color: Colors.grey[800]),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: subtitleImageUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          Container(color: Colors.grey[800]),
                                      errorWidget: (context, url, error) =>
                                          Container(color: Colors.grey[800]),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                    ],
                    if (subtitle != null)
                      Flexible(
                        child: subtitleUser == null
                            ? Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : HoverUnderline(
                                onTap: () => _openUser(subtitleUser),
                                builder: (isHovering) => Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    decoration: isHovering
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                      ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '•',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ),
                    Text(
                      '$total songs',
                      style: TextStyle(color: Colors.grey[300], fontSize: 15),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '•',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                    Text(
                      _formatDuration(_totalDurationSecs()),
                      style: TextStyle(color: Colors.grey[300], fontSize: 15),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsRow(bool isDesktop, {Gradient? backgroundGradient}) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final shuffleActive = (_isCurrentListPlaying(player)
            ? player.shuffleEnabled
            : _preShuffleEnabled);
        final repeatActive =
            player.repeatMode != global_audio_player.RepeatMode.off;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(gradient: backgroundGradient),
          alignment: Alignment.bottomLeft,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rowWidth = math.max(constraints.maxWidth, 920.0);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: SizedBox(
                    width: rowWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 54,
                              height: 54,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: FilledButton(
                                  onPressed: () {
                                    if (!_isLoading) {
                                      if (_isCurrentListPlaying(player)) {
                                        _toggleCurrentTrackPlayback(player);
                                      } else {
                                        _playFromStart();
                                      }
                                    }
                                  },
                                  style: FilledButton.styleFrom(
                                    enabledMouseCursor:
                                        SystemMouseCursors.click,
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    padding: EdgeInsets.zero,
                                    shape: const CircleBorder(),
                                  ),
                                  child: Icon(
                                    _isCurrentListPlaying(player) &&
                                            player.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () {
                                _toggleListShuffle(player);
                              },
                              icon: Icon(
                                Icons.shuffle,
                                color: shuffleActive
                                    ? colorScheme.primary
                                    : Colors.white70,
                              ),
                            ),
                            IconButton(
                              onPressed: player.toggleRepeat,
                              icon: Icon(
                                player.repeatMode ==
                                        global_audio_player.RepeatMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                color: repeatActive
                                    ? colorScheme.primary
                                    : Colors.white70,
                              ),
                            ),
                            IconButton(
                              onPressed: _isLoading ? null : _downloadAll,
                              icon: const Icon(
                                Icons.download,
                                color: Colors.white70,
                              ),
                            ),
                            Builder(
                              builder: (buttonContext) {
                                return IconButton(
                                  onPressed: () {
                                    if (isDesktop) {
                                      _showListContextMenu(
                                        anchorContext: buttonContext,
                                      );
                                    } else {
                                      _showListContextMenu();
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.more_horiz,
                                    color: Colors.white70,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              width: _showSearch ? 12 : 0,
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              width: _showSearch ? (isDesktop ? 240 : 160) : 0,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 160),
                                opacity: _showSearch ? 1 : 0,
                                child: IgnorePointer(
                                  ignoring: !_showSearch,
                                  child: TextField(
                                    onChanged: (value) {
                                      setState(() {
                                        _searchQuery = value;
                                        _rebuildIndices();
                                      });
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Search in list',
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.black.withValues(
                                        alpha: 0.4,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _showSearch = !_showSearch;
                                  if (!_showSearch) {
                                    _searchQuery = '';
                                    _rebuildIndices();
                                  }
                                });
                              },
                              icon: Icon(
                                Icons.search,
                                color: _showSearch
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey[300],
                              ),
                            ),
                            const SizedBox(width: 8),
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: DropdownButton<_SortMethod>(
                                value: _sortMethod,
                                mouseCursor: SystemMouseCursors.click,
                                dropdownColor: Colors.grey[900],
                                underline: const SizedBox.shrink(),
                                items: const [
                                  DropdownMenuItem(
                                    value: _SortMethod.position,
                                    child: Text('Index'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.title,
                                    child: Text('Title'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.author,
                                    child: Text('Author'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.album,
                                    child: Text('Album'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.addedAt,
                                    child: Text('Date Added'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.duration,
                                    child: Text('Duration'),
                                  ),
                                  DropdownMenuItem(
                                    value: _SortMethod.source,
                                    child: Text('Source'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _sortBy(value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStickyNowPlayingBar({
    required String title,
    required bool isDesktop,
  }) {
    final textColor = _stickyBarColor.computeLuminance() < 0.45
        ? Colors.white
        : Colors.black;
    final colorScheme = Theme.of(context).colorScheme;
    final barMargin = isDesktop
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 16);

    return AnimatedSlide(
      offset: _showStickyBar ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showStickyBar ? 1 : 0,
        duration: const Duration(milliseconds: 140),
        child: Container(
          height: isDesktop ? 58 : 52,
          margin: barMargin,
          decoration: BoxDecoration(
            color: _stickyBarColor.withValues(alpha: isDesktop ? 0.96 : 0.92),
            borderRadius: BorderRadius.circular(isDesktop ? 0 : 14),
            boxShadow: isDesktop
                ? const []
                : const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            children: [
              SizedBox(width: isDesktop ? 14 : 6),
              Consumer<global_audio_player.WispAudioHandler>(
                builder: (context, player, child) {
                  final isPlayingList = _isCurrentListPlaying(player);
                  final isPlaying = isPlayingList && player.isPlaying;
                  return SizedBox(
                    width: 40,
                    height: 40,
                    child: Material(
                      color: colorScheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          if (_items.isEmpty) return;
                          if (isPlayingList) {
                            _toggleCurrentTrackPlayback(player);
                          } else {
                            _playFromStart();
                          }
                        },
                        child: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: colorScheme.onPrimary,
                          size: 22,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: isDesktop ? 24 : 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortableHeader({
    required String text,
    required _SortMethod method,
    TextAlign textAlign = TextAlign.left,
    VoidCallback? onTap,
  }) {
    final headerStyle = TextStyle(color: Colors.grey[400], fontSize: 12);
    final isSorted = _sortMethod == method;
    final sortIcon = isSorted
        ? Icon(
            _ascending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: Colors.white,
          )
        : null;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: textAlign == TextAlign.right
          ? MainAxisAlignment.end
          : textAlign == TextAlign.center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Text(
          text,
          style: isSorted
              ? headerStyle.copyWith(color: Colors.white)
              : headerStyle,
        ),
        if (sortIcon != null) ...[const SizedBox(width: 4), sortIcon],
      ],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap ?? () => _sortBy(method),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildListHeaderContent({
    _ListVisualStyle visualStyle = _ListVisualStyle.spotify,
    required double availableWidth,
  }) {
    final visibleColumns = _getVisibleColumns(availableWidth);

    if (visualStyle == _ListVisualStyle.apple) {
      return Row(
        children: [
          SizedBox(
            width: 40,
            child: _buildSortableHeader(
              text: '#',
              method: _SortMethod.position,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 4),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildSortableHeader(
                text: 'Song',
                method: _SortMethod.title,
              ),
            ),
          ),
          // Artist column - shown when artist column should be visible
          if (visibleColumns.showArtistColumn)
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildSortableHeader(
                  text: 'Artist',
                  method: _SortMethod.author,
                ),
              ),
            ),
          // Album column - hidden at smaller widths
          if (visibleColumns.showAlbum)
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildSortableHeader(
                  text: 'Album',
                  method: _SortMethod.album,
                ),
              ),
            ),
          // Time column - hidden at smallest width
          if (visibleColumns.showTime)
            SizedBox(
              width: 70,
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildSortableHeader(
                  text: 'Time',
                  method: _SortMethod.duration,
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          const SizedBox(
            width: 48,
          ), // Adjusted space for more context menu room
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Align(
              alignment: Alignment.center,
              child: _buildSortableHeader(
                text: '#',
                method: _SortMethod.position,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 44),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildSortableHeader(
                text: _sortMethod == _SortMethod.author ? 'Author' : 'Title',
                method: _SortMethod.author == _sortMethod
                    ? _SortMethod.author
                    : _SortMethod.title,
                onTap: _handleTitleHeaderTap,
              ),
            ),
          ),
          if (widget.type == SharedListType.playlist && visibleColumns.showAlbum)
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.center,
                child: _buildSortableHeader(
                  text: 'Album',
                  method: _SortMethod.album,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (widget.type == SharedListType.playlist)
            const SizedBox(width: 80)
          else
            const SizedBox(width: 80),
          if (widget.type == SharedListType.playlist &&
              visibleColumns.showAddedAt)
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.center,
                child: _buildSortableHeader(
                  text: 'Added',
                  method: _SortMethod.addedAt,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (widget.type == SharedListType.playlist)
            const SizedBox(width: 120)
          else
            const SizedBox(width: 120),
          const SizedBox(
            width: 24,
            child: Icon(Icons.download_done, size: 14, color: Colors.grey),
          ),
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildSortableHeader(
                text: 'Time',
                method: _SortMethod.duration,
                textAlign: TextAlign.right,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildSortableHeader(
                text: '',
                method: _SortMethod.source,
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongList({
    bool isMobile = false,
    _ListVisualStyle visualStyle = _ListVisualStyle.spotify,
    required double availableWidth,
  }) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_sortedIndices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No songs to display',
          style: TextStyle(color: Colors.grey[400]),
        ),
      );
    }

    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    final isAppleStyle = visualStyle == _ListVisualStyle.apple;
    final totalCount = _sortedIndices.length;
    final controller = isMobile
        ? _mobileScrollController
        : _desktopScrollController;
    final useVirtualizedWindow =
        controller.hasClients || _songListTopOffset >= 0;

    if (useVirtualizedWindow) {
      _scheduleSongListOffsetUpdate(controller);
      final rowHeight = isMobile ? _rowHeightMobile : _rowHeightDesktop;
      final viewport = controller.hasClients
          ? controller.position.viewportDimension
          : 0;
      final scrollOffset = controller.hasClients ? controller.offset : 0;
      final effectiveOffset = (scrollOffset - _songListTopOffset).clamp(
        0.0,
        double.infinity,
      );
      final initialWindowSize =
          ((viewport / rowHeight).ceil() + _windowBuffer * 2).clamp(
            0,
            totalCount,
          );

      int startIndex;
      int endIndex;
      if (!controller.hasClients || viewport == 0) {
        startIndex = 0;
        endIndex = totalCount == 0
            ? 0
            : (initialWindowSize - 1).clamp(0, totalCount - 1);
      } else {
        final first = (effectiveOffset / rowHeight).floor() - _windowBuffer;
        final last =
            ((effectiveOffset + viewport) / rowHeight).ceil() + _windowBuffer;
        startIndex = first.clamp(0, totalCount - 1);
        endIndex = last.clamp(0, totalCount - 1);
      }

      final visibleCount = totalCount == 0 ? 0 : (endIndex - startIndex + 1);
      final topSpacer = startIndex * rowHeight;
      final bottomSpacer = (totalCount - endIndex - 1) * rowHeight;

      return Column(
        children: [
          SizedBox(key: _songListKey, height: 0),
          if (topSpacer > 0) SizedBox(height: topSpacer),
          ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleCount,
            itemBuilder: (context, idx) {
              final player = context
                  .watch<global_audio_player.WispAudioHandler>();
              final rowIndex = startIndex + idx;
              final index = _sortedIndices[rowIndex];
              final item = _items[index];
              final song = _toGenericSong(item);
              final isCurrentTrack = player.currentTrack?.id == song.id;
              final album = _getAlbum(item);
              final artists = _getArtists(item);
              final visibleColumns = _getVisibleColumns(availableWidth);

              final isHovering = _hoveredSongIds.contains(song.id);
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) {
                  if (!isDesktop) return;
                  setState(() => _hoveredSongIds.add(song.id));
                },
                onExit: (_) {
                  if (!isDesktop) return;
                  setState(() => _hoveredSongIds.remove(song.id));
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapUp: isDesktop
                      ? (details) {
                          _showSongContextMenu(
                            song,
                            globalPosition: details.globalPosition,
                          );
                        }
                      : null,
                  onLongPress: isDesktop
                      ? null
                      : () {
                          _showSongContextMenu(song);
                        },
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: isDesktop
                          ? null
                          : () {
                              if (isCurrentTrack) {
                                _toggleCurrentTrackPlayback(player);
                              } else {
                                _playQueueAt(rowIndex);
                              }
                            },
                      onDoubleTap: isDesktop
                          ? () => _playQueueAt(rowIndex)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Row(
                          children: [
                            if (isDesktop && !isAppleStyle) ...[
                              SizedBox(
                                width: 40,
                                child: isHovering
                                    ? IconButton(
                                        icon: Icon(
                                          isCurrentTrack && player.isPlaying
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          if (isCurrentTrack) {
                                            _toggleCurrentTrackPlayback(player);
                                          } else {
                                            _playQueueAt(rowIndex);
                                          }
                                        },
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                      )
                                    : Text(
                                        '${rowIndex + 1}',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.grey[900],
                                        child: CachedNetworkImage(
                                          imageUrl: _getThumbnail(item),
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) =>
                                              Icon(
                                                Icons.music_note,
                                                color: Colors.grey[700],
                                              ),
                                          placeholder: (context, url) =>
                                              Container(
                                                color: Colors.grey[800],
                                              ),
                                        ),
                                      ),
                                    ),
                                    if (isDesktop && isAppleStyle) ...[
                                      AnimatedOpacity(
                                        opacity: isHovering ? 1 : 0,
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        child: Container(
                                          color: Colors.black.withValues(
                                            alpha: 0.45,
                                          ),
                                        ),
                                      ),
                                      if (isHovering)
                                        Positioned.fill(
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: () {
                                                if (isCurrentTrack) {
                                                  _toggleCurrentTrackPlayback(
                                                    player,
                                                  );
                                                } else {
                                                  _playQueueAt(rowIndex);
                                                }
                                              },
                                              child: Icon(
                                                isCurrentTrack &&
                                                        player.isPlaying
                                                    ? Icons.pause
                                                    : Icons.play_arrow,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _getTitle(item),
                                    style: TextStyle(
                                      color: isCurrentTrack
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (!isAppleStyle ||
                                      isMobile ||
                                      visibleColumns.showArtistInline) ...[
                                    const SizedBox(height: 2),
                                    _buildArtistLine(
                                      artists,
                                      isDesktop: isDesktop,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!isMobile && isAppleStyle) ...[
                              // Artist column - only shown when artist column should be visible
                              if (visibleColumns.showArtistColumn)
                                Expanded(
                                  flex: 2,
                                  child: _buildArtistLine(
                                    artists,
                                    isDesktop: isDesktop,
                                  ),
                                ),
                              // Album column - hidden when album is not visible
                              if (visibleColumns.showAlbum)
                                Expanded(
                                  flex: 2,
                                  child:
                                      (isDesktop &&
                                          album != null &&
                                          album.id.isNotEmpty)
                                      ? HoverUnderline(
                                          onTap: () {
                                            _openSharedList(
                                              SharedListType.album,
                                              album.id,
                                              title: album.title,
                                              thumbnailUrl: album.thumbnailUrl,
                                            );
                                          },
                                          onSecondaryTapDown: (details) {
                                            EntityContextMenus.showAlbumMenu(
                                              context,
                                              album: GenericAlbum(
                                                id: album.id,
                                                source: album.source,
                                                title: album.title,
                                                thumbnailUrl:
                                                    album.thumbnailUrl,
                                                artists: album.artists,
                                                label: album.label,
                                                releaseDate: album.releaseDate,
                                                explicit: song.explicit,
                                                durationSecs: 0,
                                              ),
                                              globalPosition:
                                                  details.globalPosition,
                                            );
                                          },
                                          builder: (isHovering) => Text(
                                            _getAlbumTitle(item),
                                            style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 12,
                                              decoration: isHovering
                                                  ? TextDecoration.underline
                                                  : TextDecoration.none,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        )
                                      : Text(
                                          _getAlbumTitle(item),
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                ),
                              // Time column - hidden at smallest width
                              if (visibleColumns.showTime)
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    _formatDuration(_getDuration(item)),
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              SizedBox(
                                width: 48, // Updated width
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Builder(
                                    builder: (buttonContext) => IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                        minHeight: 24,
                                      ),
                                      icon: Icon(
                                        CupertinoIcons.ellipsis,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        _showSongContextMenu(
                                          song,
                                          anchorContext: buttonContext,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              // Spotify style - Album column
                              if (!isMobile &&
                                  widget.type == SharedListType.playlist &&
                                  visibleColumns.showAlbum)
                                Expanded(
                                  flex: 2,
                                  child:
                                      (isDesktop &&
                                          album != null &&
                                          album.id.isNotEmpty)
                                      ? HoverUnderline(
                                          onTap: () {
                                            _openSharedList(
                                              SharedListType.album,
                                              album.id,
                                              title: album.title,
                                              thumbnailUrl: album.thumbnailUrl,
                                            );
                                          },
                                          onSecondaryTapDown: (details) {
                                            _showSongContextMenu(
                                              song,
                                              globalPosition:
                                                  details.globalPosition,
                                            );
                                          },
                                          builder: (isHovering) => Text(
                                            _getAlbumTitle(item),
                                            style: TextStyle(
                                              color: Colors.grey[500],
                                              fontSize: 12,
                                              decoration: isHovering
                                                  ? TextDecoration.underline
                                                  : TextDecoration.none,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        )
                                      : Text(
                                          _getAlbumTitle(item),
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                )
                              else if (!isMobile &&
                                  widget.type != SharedListType.playlist)
                                const SizedBox(width: 80),
                              // Spotify style - Added At column
                              if (!isMobile &&
                                  widget.type == SharedListType.playlist &&
                                  visibleColumns.showAddedAt)
                                SizedBox(
                                  width: 120,
                                  child: Text(
                                    _formatAddedAt(_getAddedAt(item)),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              else if (!isMobile &&
                                  widget.type != SharedListType.playlist)
                                const SizedBox(width: 120),
                              SizedBox(
                                width: 24,
                                child: _buildCacheIndicator(song.id),
                              ),
                              if (isDesktop) ...[
                                AnimatedOpacity(
                                  opacity: isHovering ? 1 : 0,
                                  duration: const Duration(milliseconds: 120),
                                  child: IgnorePointer(
                                    ignoring: !isHovering,
                                    child: SizedBox(
                                      width: 28,
                                      child: LikeButton(
                                        track: song,
                                        iconSize: 16,
                                        padding: const EdgeInsets.all(2),
                                        constraints: const BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              // Spotify style - Duration column
                              if (visibleColumns.showTime)
                                SizedBox(
                                  width: isMobile ? 40 : 80,
                                  child: Text(
                                    _formatDuration(_getDuration(item)),
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                )
                              else if (!isMobile)
                                const SizedBox(width: 80),
                              SizedBox(width: isMobile ? 0 : 12),
                              !isMobile
                                  ? SizedBox(
                                      width: 32,
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Icon(
                                          Icons.graphic_eq,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          size: isMobile ? 16 : 18,
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (bottomSpacer > 0) SizedBox(height: bottomSpacer),
        ],
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCount,
      itemBuilder: (context, idx) {
        final player = context.watch<global_audio_player.WispAudioHandler>();
        final index = _sortedIndices[idx];
        final item = _items[index];
        final isEven = idx % 2 == 0;
        final song = _toGenericSong(item);
        final isCurrentTrack = player.currentTrack?.id == song.id;
        final album = _getAlbum(item);
        final artists = _getArtists(item);
        final visibleColumns = _getVisibleColumns(availableWidth);

        final isHovering = _hoveredSongIds.contains(song.id);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (!isDesktop) return;
            setState(() => _hoveredSongIds.add(song.id));
          },
          onExit: (_) {
            if (!isDesktop) return;
            setState(() => _hoveredSongIds.remove(song.id));
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: isDesktop
                ? (details) {
                    _showSongContextMenu(
                      song,
                      globalPosition: details.globalPosition,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    _showSongContextMenu(song);
                  },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: isDesktop
                    ? null
                    : () {
                        if (isCurrentTrack) {
                          _toggleCurrentTrackPlayback(player);
                        } else {
                          _playQueueAt(idx);
                        }
                      },
                onDoubleTap: isDesktop ? () => _playQueueAt(idx) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isAppleStyle
                        ? Colors.transparent
                        : (isEven
                              ? Colors.transparent
                              : Colors.black.withValues(alpha: 0.15)),
                    borderRadius: isAppleStyle
                        ? BorderRadius.zero
                        : BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (isDesktop && !isAppleStyle) ...[
                        SizedBox(
                          width: 40,
                          child: isHovering
                              ? IconButton(
                                  icon: Icon(
                                    isCurrentTrack && player.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    if (isCurrentTrack) {
                                      _toggleCurrentTrackPlayback(player);
                                    } else {
                                      _playQueueAt(idx);
                                    }
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                )
                              : Text(
                                  '${idx + 1}',
                                  style: TextStyle(color: Colors.grey[400]),
                                  textAlign: TextAlign.center,
                                ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  color: Colors.grey[900],
                                  child: CachedNetworkImage(
                                    imageUrl: _getThumbnail(item),
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                    ),
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[800]),
                                  ),
                                ),
                              ),
                              if (isDesktop && isAppleStyle) ...[
                                AnimatedOpacity(
                                  opacity: isHovering ? 1 : 0,
                                  duration: const Duration(milliseconds: 120),
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                  ),
                                ),
                                if (isHovering)
                                  Positioned.fill(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          if (isCurrentTrack) {
                                            _toggleCurrentTrackPlayback(player);
                                          } else {
                                            _playQueueAt(idx);
                                          }
                                        },
                                        child: Icon(
                                          isCurrentTrack && player.isPlaying
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _getTitle(item),
                              style: TextStyle(
                                color: isCurrentTrack
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!isAppleStyle ||
                                isMobile ||
                                visibleColumns.showArtistInline) ...[
                              const SizedBox(height: 2),
                              _buildArtistLine(artists, isDesktop: isDesktop),
                            ],
                          ],
                        ),
                      ),
                      if (!isMobile && isAppleStyle) ...[
                        // Artist column - only shown when artist column should be visible
                        if (visibleColumns.showArtistColumn)
                          Expanded(
                            flex: 2,
                            child: _buildArtistLine(
                              artists,
                              isDesktop: isDesktop,
                            ),
                          ),
                        // Album column - hidden when album is not visible
                        if (visibleColumns.showAlbum)
                          Expanded(
                            flex: 2,
                            child:
                                (isDesktop &&
                                    album != null &&
                                    album.id.isNotEmpty)
                                ? HoverUnderline(
                                    onTap: () {
                                      _openSharedList(
                                        SharedListType.album,
                                        album.id,
                                        title: album.title,
                                        thumbnailUrl: album.thumbnailUrl,
                                      );
                                    },
                                    onSecondaryTapDown: (details) {
                                      EntityContextMenus.showAlbumMenu(
                                        context,
                                        album: GenericAlbum(
                                          id: album.id,
                                          source: album.source,
                                          title: album.title,
                                          thumbnailUrl: album.thumbnailUrl,
                                          artists: album.artists,
                                          label: album.label,
                                          releaseDate: album.releaseDate,
                                          explicit: song.explicit,
                                          durationSecs: 0,
                                        ),
                                        globalPosition: details.globalPosition,
                                      );
                                    },
                                    builder: (isHovering) => Text(
                                      _getAlbumTitle(item),
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                        decoration: isHovering
                                            ? TextDecoration.underline
                                            : TextDecoration.none,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                : Text(
                                    _getAlbumTitle(item),
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                        // Time column - hidden at smallest width
                        if (visibleColumns.showTime)
                          SizedBox(
                            width: 70,
                            child: Text(
                              _formatDuration(_getDuration(item)),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        SizedBox(
                          width: 24,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Builder(
                              builder: (buttonContext) => IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                                icon: Icon(
                                  CupertinoIcons.ellipsis,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _showSongContextMenu(
                                    song,
                                    anchorContext: buttonContext,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        // Spotify style - Album column
                        if (!isMobile &&
                            widget.type == SharedListType.playlist &&
                            visibleColumns.showAlbum)
                          Expanded(
                            flex: 2,
                            child:
                                (isDesktop &&
                                    album != null &&
                                    album.id.isNotEmpty)
                                ? HoverUnderline(
                                    onTap: () {
                                      _openSharedList(
                                        SharedListType.album,
                                        album.id,
                                        title: album.title,
                                        thumbnailUrl: album.thumbnailUrl,
                                      );
                                    },
                                    onSecondaryTapDown: (details) {
                                      EntityContextMenus.showAlbumMenu(
                                        context,
                                        album: GenericAlbum(
                                          id: album.id,
                                          source: album.source,
                                          title: album.title,
                                          thumbnailUrl: album.thumbnailUrl,
                                          artists: album.artists,
                                          label: album.label,
                                          releaseDate: album.releaseDate,
                                          explicit: song.explicit,
                                          durationSecs: 0,
                                        ),
                                        globalPosition: details.globalPosition,
                                      );
                                    },
                                    builder: (isHovering) => Text(
                                      _getAlbumTitle(item),
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                        decoration: isHovering
                                            ? TextDecoration.underline
                                            : TextDecoration.none,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : Text(
                                    _getAlbumTitle(item),
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                          )
                        else if (!isMobile &&
                            widget.type != SharedListType.playlist)
                          const SizedBox(width: 80),
                        // Spotify style - Added At column
                        if (!isMobile &&
                            widget.type == SharedListType.playlist &&
                            visibleColumns.showAddedAt)
                          SizedBox(
                            width: 120,
                            child: Text(
                              _formatAddedAt(_getAddedAt(item)),
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else if (!isMobile &&
                            widget.type != SharedListType.playlist)
                          const SizedBox(width: 120),
                        SizedBox(
                          width: 24,
                          child: _buildCacheIndicator(song.id),
                        ),
                        if (isDesktop) ...[
                          AnimatedOpacity(
                            opacity: isHovering ? 1 : 0,
                            duration: const Duration(milliseconds: 120),
                            child: IgnorePointer(
                              ignoring: !isHovering,
                              child: SizedBox(
                                width: 28,
                                child: LikeButton(
                                  track: song,
                                  iconSize: 16,
                                  padding: const EdgeInsets.all(2),
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Spotify style - Duration column
                        if (visibleColumns.showTime)
                          SizedBox(
                            width: isMobile ? 40 : 80,
                            child: Text(
                              _formatDuration(_getDuration(item)),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          )
                        else if (!isMobile)
                          const SizedBox(width: 80),
                        SizedBox(width: isMobile ? 0 : 12),
                        !isMobile
                            ? SizedBox(
                                width: 32,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Icon(
                                    Icons.graphic_eq,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    size: isMobile ? 16 : 18,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecommendedSection({
    required bool isMobile,
    _ListVisualStyle visualStyle = _ListVisualStyle.spotify,
  }) {
    if (!_shouldShowRecommendations()) {
      return const SizedBox.shrink();
    }

    final isAppleStyle = visualStyle == _ListVisualStyle.apple;
    final songs = _recommendedSongs;
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 0 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: isMobile
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: isMobile
                        ? const EdgeInsets.fromLTRB(8, 12, 0, 8)
                        : EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recommended',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "based on what's in this playlist",
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isMobile)
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: IconButton(
                        onPressed: _isLoadingRecommendations
                            ? null
                            : _refreshRecommendations,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 34,
                        ),
                        icon: _isLoadingRecommendations
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Refresh recommendations',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: isMobile ? 0 : 4),
          if (_recommendationsError != null && songs.isEmpty)
            Padding(
              padding: isMobile
                  ? const EdgeInsets.fromLTRB(0, 0, 0, 8)
                  : const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                _recommendationsError!,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
          if (_isLoadingRecommendations && songs.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: CircularProgressIndicator(),
              ),
            )
          else if (songs.isEmpty)
            Padding(
              padding: isMobile
                  ? const EdgeInsets.only(top: 8, bottom: 8)
                  : const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text(
                'No recommendations available right now.',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            )
          else
            ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: songs.length,
              separatorBuilder: (context, index) =>
                  SizedBox(height: isMobile ? 2 : 6),
              itemBuilder: (context, index) {
                final item = songs[index];
                return _buildRecommendedSongRow(
                  item: item,
                  index: index,
                  isMobile: isMobile,
                  isDesktop: isDesktop,
                  isAppleStyle: isAppleStyle,
                );
              },
            ),
          if (isMobile)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: OutlinedButton(
                  onPressed: _isLoadingRecommendations
                      ? null
                      : _refreshRecommendations,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white70,
                  ),
                  child: _isLoadingRecommendations
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Refresh'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecommendedSongRow({
    required PlaylistItem item,
    required int index,
    required bool isMobile,
    required bool isDesktop,
    required bool isAppleStyle,
  }) {
    final song = _toGenericSong(item);
    final isAdding = _addingRecommendationTrackIDs.contains(item.id);
    final isAdded = _addedRecommendationTrackIDs.contains(item.id);
    final album = item.album;

    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final isCurrentTrack = player.currentTrack?.id == song.id;
        final isHovering = _hoveredSongIds.contains(song.id);

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (!isDesktop) return;
            setState(() => _hoveredSongIds.add(song.id));
          },
          onExit: (_) {
            if (!isDesktop) return;
            setState(() => _hoveredSongIds.remove(song.id));
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: isDesktop
                ? (details) {
                    _showSongContextMenu(
                      song,
                      globalPosition: details.globalPosition,
                    );
                  }
                : null,
            onLongPress: isDesktop ? null : () => _showSongContextMenu(song),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                mouseCursor: SystemMouseCursors.click,
                onTap: () => _playRecommendedAt(index),
                onDoubleTap: isDesktop ? () => _playRecommendedAt(index) : null,
                child: Container(
                  padding: isMobile
                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                      : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  color: Colors.grey[900],
                                  child: CachedNetworkImage(
                                    imageUrl: _getThumbnail(item),
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) => Icon(
                                      Icons.music_note,
                                      color: Colors.grey[700],
                                    ),
                                    placeholder: (context, url) =>
                                        Container(color: Colors.grey[800]),
                                  ),
                                ),
                              ),
                              AnimatedOpacity(
                                opacity: isHovering ? 1 : 0,
                                duration: const Duration(milliseconds: 120),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.45),
                                ),
                              ),
                              if (isHovering)
                                Positioned.fill(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        unawaited(
                                          _toggleRecommendedTrackPlayback(
                                            player,
                                            index,
                                          ),
                                        );
                                      },
                                      child: Icon(
                                        isCurrentTrack && player.isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
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
                        flex: 4,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrentTrack
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _buildRecommendedArtistLine(
                              item.artists,
                              isDesktop: isDesktop,
                            ),
                          ],
                        ),
                      ),
                      // On mobile we hide the album column and replace the Add button
                      if (!isMobile) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: isMobile ? 2 : 3,
                          child:
                              (isDesktop &&
                                  album != null &&
                                  album.id.isNotEmpty)
                              ? HoverUnderline(
                                  onTap: () {
                                    _openSharedList(
                                      SharedListType.album,
                                      album.id,
                                      title: album.title,
                                      thumbnailUrl: album.thumbnailUrl,
                                    );
                                  },
                                  onSecondaryTapDown: (details) {
                                    EntityContextMenus.showAlbumMenu(
                                      context,
                                      album: GenericAlbum(
                                        id: album.id,
                                        source: album.source,
                                        title: album.title,
                                        thumbnailUrl: album.thumbnailUrl,
                                        artists: album.artists,
                                        label: album.label,
                                        releaseDate: album.releaseDate,
                                        explicit: song.explicit,
                                        durationSecs: 0,
                                      ),
                                      globalPosition: details.globalPosition,
                                    );
                                  },
                                  builder: (isAlbumHovering) => Text(
                                    album.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                      decoration: isAlbumHovering
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    ),
                                  ),
                                )
                              : Text(
                                  album?.title ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                      ],

                      SizedBox(
                        width: isMobile ? 44 : 74,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: isMobile
                              ? (isAdding
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : OutlinedButton(
                                        onPressed: (isAdding || isAdded)
                                            ? null
                                            : () => _addRecommendedTrack(item),
                                        style: OutlinedButton.styleFrom(
                                          shape: const CircleBorder(),
                                          side: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                          padding: const EdgeInsets.all(8),
                                          minimumSize: const Size(36, 36),
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor:
                                              Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.5),
                                          disabledForegroundColor:
                                              Colors.white70,
                                        ),
                                        child: isAdded
                                            ? const Icon(Icons.check, size: 18)
                                            : const Icon(Icons.add, size: 18),
                                      ))
                              : FilledButton(
                                  onPressed: (isAdding || isAdded)
                                      ? null
                                      : () => _addRecommendedTrack(item),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(54, 34),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    enabledMouseCursor:
                                        SystemMouseCursors.click,
                                    disabledMouseCursor:
                                        SystemMouseCursors.basic,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.35),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.18),
                                    disabledForegroundColor: Colors.white70,
                                    elevation: 0,
                                  ),
                                  child: isAdding
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(isAdded ? 'Added' : 'Add'),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecommendedArtistLine(
    List<GenericSimpleArtist> artists, {
    required bool isDesktop,
  }) {
    if (artists.isEmpty) {
      return Text(
        'Unknown artist',
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    if (!isDesktop) {
      return Text(
        artists.map((a) => a.name).join(', '),
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Wrap(
      children: [
        for (int i = 0; i < artists.length; i++) ...[
          HoverUnderline(
            onTap: () => _openArtist(artists[i]),
            onSecondaryTapDown: (details) {
              EntityContextMenus.showArtistMenu(
                context,
                artist: artists[i],
                globalPosition: details.globalPosition,
              );
            },
            builder: (isHovering) => Text(
              artists[i].name,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                decoration: isHovering
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (i < artists.length - 1)
            Text(', ', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ],
    );
  }

  String _getThumbnail(_ListItem item) {
    if (item is GenericSong) return item.thumbnailUrl;
    if (item is PlaylistItem) return item.thumbnailUrl;
    return '';
  }

  Widget _buildArtistLine(
    List<GenericSimpleArtist> artists, {
    required bool isDesktop,
  }) {
    if (artists.isEmpty) {
      return Text(
        artists.map((a) => a.name).join(', '),
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Wrap(
      children: [
        for (int i = 0; i < artists.length; i++) ...[
          HoverUnderline(
            onTap: () => _openArtist(artists[i]),
            onSecondaryTapDown: (details) {
              EntityContextMenus.showArtistMenu(
                context,
                artist: artists[i],
                globalPosition: details.globalPosition,
              );
            },
            builder: (isHovering) => Text(
              artists[i].name,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                decoration: isHovering
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (i < artists.length - 1)
            Text(', ', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ],
    );
  }
}

class _SpotifyListDetailRenderer extends StatelessWidget {
  final _SharedListDetailViewState view;
  final String title;
  final String? subtitle;
  final GenericSimpleUser? subtitleUser;
  final String imageUrl;
  final String? subtitleImageUrl;
  final int total;
  final bool isDesktop;
  final String? description;

  const _SpotifyListDetailRenderer({
    required this.view,
    required this.title,
    required this.subtitle,
    required this.subtitleUser,
    required this.imageUrl,
    required this.subtitleImageUrl,
    required this.total,
    required this.isDesktop,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = !isDesktop;
    final padding = isMobile ? 12.0 : 24.0;

    if (isMobile) {
      view._scheduleStickyBarUpdate(view._mobileScrollController);
      return Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                CustomScrollView(
                  controller: view._mobileScrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Container(
                        key: view._headerKey,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            padding,
                            padding,
                            padding,
                            0,
                          ),
                          child: view._buildMobileHeader(
                            title,
                            subtitle,
                            subtitleUser,
                            imageUrl,
                            total,
                            description,
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Container(
                        key: view._mobileActionsKey,
                        padding: EdgeInsets.symmetric(
                          horizontal: padding / 2,
                          vertical: 4,
                        ),
                        color: const Color(0xFF121212),
                        child: view._buildMobileActionsRow(),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.zero,
                      sliver: SliverToBoxAdapter(
                        child: LayoutBuilder(
                          builder: (layoutContext, constraints) {
                            return view._buildSongList(
                              isMobile: true,
                              availableWidth: constraints.maxWidth,
                            );
                          },
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                        child: view._buildRecommendedSection(isMobile: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    view._scheduleStickyBarUpdate(view._desktopScrollController);
    final stickyHeaderColor = view._stickyBarColor;
    final stickyHeaderColorHSL = HSLColor.fromColor(stickyHeaderColor);
    final actionsRowColor = 
      stickyHeaderColorHSL.withLightness(
        stickyHeaderColorHSL.lightness * 0.5
      ).toColor();

    final contentSurfaceColor = Theme.of(context).colorScheme.surface;
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.2, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.82),
                  Colors.black.withValues(alpha: 0.36),
                  Colors.black.withValues(alpha: 0.82),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: view._desktopScrollController,
                  padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
                  children: [
                    Container(
                      key: view._headerKey,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: stickyHeaderColor,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Column(
                        children: [
                          view._buildHeader(
                            title,
                            subtitle,
                            subtitleUser,
                            subtitleImageUrl,
                            imageUrl,
                            total,
                            description,
                          ),
                          const SizedBox(height: 12),
                          view._buildActionsRow(
                            isDesktop,
                            backgroundGradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0, 1],
                              colors: [actionsRowColor, contentSurfaceColor],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: contentSurfaceColor,
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: LayoutBuilder(
                          builder: (layoutContext, constraints) {
                            final availableWidth = constraints.maxWidth;
                            return Column(
                              children: [
                                view._buildListHeaderContent(
                                  availableWidth: availableWidth,
                                ),
                                const SizedBox(height: 6),
                                view._buildSongList(
                                  isMobile: false,
                                  availableWidth: availableWidth,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: view._buildRecommendedSection(
                                    isMobile: false,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: view._buildStickyNowPlayingBar(
              title: title,
              isDesktop: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppleMusicListDetailRenderer extends StatelessWidget {
  final _SharedListDetailViewState view;
  final String title;
  final String? subtitle;
  final GenericSimpleUser? subtitleUser;
  final String imageUrl;
  final int total;
  final bool isDesktop;
  final String? description;
  final String? subtitleImageUrl;

  const _AppleMusicListDetailRenderer({
    required this.view,
    required this.title,
    required this.subtitle,
    required this.subtitleUser,
    required this.imageUrl,
    required this.subtitleImageUrl,
    required this.total,
    required this.isDesktop,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktop(context);
    }
    return _buildMobile(context);
  }

  Widget _buildHeaderArtwork(BuildContext context) {
    final isLiked =
        view.widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(view.widget.id);

    if (isLiked) {
      return Container(color: Colors.grey[900], child: const LikedSongsArt());
    }

    if (imageUrl.isNotEmpty) {
      if (view._isLocalImagePath(imageUrl)) {
        return Image.file(
          File(imageUrl.replaceFirst('file://', '')),
          fit: BoxFit.cover,
          errorBuilder: (context, url, error) =>
              Container(color: Colors.grey[900]),
        );
      } else {
        return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey[900]),
          errorWidget: (context, url, error) =>
              Container(color: Colors.grey[900]),
        );
      }
    }

    return Container(
      color: Colors.grey[900],
      child: Icon(
        view.widget.type == SharedListType.playlist
            ? Icons.playlist_play
            : Icons.album,
        color: Colors.grey[600],
        size: 64,
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final descriptionText = description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;
    final expandedHeight =
        MediaQuery.of(context).size.width - MediaQuery.of(context).padding.top;
    final contentSurfaceColor = Theme.of(context).colorScheme.surface;
    final backgroundProgress = view._scrollBackgroundProgress(
      view._mobileScrollController,
    );
    final backgroundScale = 1 + (backgroundProgress * 0.10);
    view._setMobileHeaderExtent(expandedHeight);
    view._scheduleStickyBarUpdate(view._mobileScrollController);

    return Stack(
      children: [
        Positioned.fill(child: Container(color: contentSurfaceColor)),
        CustomScrollView(
          controller: view._mobileScrollController,
          slivers: [
            SliverAppBar(
              key: view._headerKey,
              backgroundColor: contentSurfaceColor,
              clipBehavior: Clip.none,
              pinned: true,
              expandedHeight: expandedHeight,
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: AnimatedOpacity(
                opacity: view._showStickyBar ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: view._showStickyBar
                    ? Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              actions: [
                if (view._showStickyBar)
                  view._buildStickyPlayAction(
                    useAppleStyle: true,
                    protrude: true,
                  )
                else ...[
                  IconButton(
                    icon: const Icon(CupertinoIcons.arrow_down_to_line),
                    onPressed: view._isLoading ? null : view._downloadAll,
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.ellipsis_vertical),
                    onPressed: view._showListContextMenu,
                  ),
                ],
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.scale(
                      scale: backgroundScale,
                      child: _buildHeaderArtwork(context),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                            Colors.black,
                          ],
                          stops: const [0.0, 0.25, 0.75, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 12,
                      child: _buildMobileMeta(),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Container(
                  key: view._mobileActionsKey,
                  child: _buildMobilePlaybackRow(),
                ),
              ),
            ),
            if (hasDescription)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                  child: buildParsedText(
                    context,
                    descriptionText,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    linkStyle: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: LayoutBuilder(
                builder: (layoutContext, constraints) {
                  return view._buildSongList(
                    isMobile: true,
                    visualStyle: _ListVisualStyle.apple,
                    availableWidth: constraints.maxWidth,
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                child: view._buildRecommendedSection(
                  isMobile: true,
                  visualStyle: _ListVisualStyle.apple,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final descriptionText = description?.trim();
    final hasDescription =
        descriptionText != null && descriptionText.isNotEmpty;
    final contentSurfaceColor = Theme.of(context).colorScheme.surface;

    view._scheduleStickyBarUpdate(view._desktopScrollController);
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: contentSurfaceColor,
          ),
        ),
        SafeArea(
          bottom: false,
          child: ListView(
            controller: view._desktopScrollController,
            padding: const EdgeInsets.fromLTRB(30, 30, 30, 18),
            children: [
              LayoutBuilder(
                builder: (headerContext, headerConstraints) {
                  final availableWidth = headerConstraints.maxWidth;
                  return Container(
                    key: view._headerKey,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 210,
                          height: 210,
                          child: _buildArtwork(context),
                        ),
                        const SizedBox(width: 22),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$total items • ${view._formatDuration(view._totalDurationSecs())}',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              if ((subtitle != null && subtitle!.isNotEmpty) ||
                                  subtitleImageUrl != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (subtitleImageUrl != null) ...[
                                      MouseRegion(
                                        cursor: subtitleUser == null
                                            ? SystemMouseCursors.basic
                                            : SystemMouseCursors.click,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          onTap: subtitleUser == null
                                              ? null
                                              : () => view._openUser(
                                                  subtitleUser!,
                                                ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child:
                                                view._isLocalImagePath(
                                                  subtitleImageUrl!,
                                                )
                                                ? Image.file(
                                                    File(
                                                      subtitleImageUrl!
                                                          .replaceFirst(
                                                            'file://',
                                                            '',
                                                          ),
                                                    ),
                                                    width: 24,
                                                    height: 24,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (context, url, error) =>
                                                            Container(
                                                              width: 24,
                                                              height: 24,
                                                              color: Colors
                                                                  .grey[700],
                                                            ),
                                                  )
                                                : CachedNetworkImage(
                                                    imageUrl: subtitleImageUrl!,
                                                    width: 24,
                                                    height: 24,
                                                    fit: BoxFit.cover,
                                                    errorWidget:
                                                        (context, url, error) =>
                                                            Container(
                                                              width: 24,
                                                              height: 24,
                                                              color: Colors
                                                                  .grey[700],
                                                            ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (subtitle != null &&
                                        subtitle!.isNotEmpty)
                                      subtitleUser == null
                                          ? Text(
                                              subtitle!,
                                              style: TextStyle(
                                                color: Colors.grey[300],
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            )
                                          : HoverUnderline(
                                              onTap: () =>
                                                  view._openUser(subtitleUser!),
                                              builder: (isHovering) => Text(
                                                subtitle!,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  decoration: isHovering
                                                      ? TextDecoration.underline
                                                      : TextDecoration.none,
                                                ),
                                              ),
                                            ),
                                  ],
                                ),
                              ],
                              if (hasDescription) ...[
                                const SizedBox(height: 4),
                                buildParsedText(
                                  context,
                                  descriptionText,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  linkStyle: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 16),
                              _buildDesktopPlaybackRow(
                                availableWidth: availableWidth,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              LayoutBuilder(
                builder: (layoutContext, constraints) {
                  final availableWidth = constraints.maxWidth;
                  return Column(
                    children: [
                      const SizedBox(height: 26),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: view._buildListHeaderContent(
                          visualStyle: _ListVisualStyle.apple,
                          availableWidth: availableWidth,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          layoutContext,
                        ).copyWith(scrollbars: false),
                        child: view._buildSongList(
                          isMobile: false,
                          visualStyle: _ListVisualStyle.apple,
                          availableWidth: availableWidth,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          layoutContext,
                        ).copyWith(scrollbars: false),
                        child: view._buildRecommendedSection(
                          isMobile: false,
                          visualStyle: _ListVisualStyle.apple,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: view._buildStickyNowPlayingBar(
              title: title,
              isDesktop: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArtwork(BuildContext context) {
    final isLiked =
        view.widget.type == SharedListType.playlist &&
        isLikedSongsPlaylistId(view.widget.id);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: Colors.grey[900],
        child: isLiked
            ? const LikedSongsArt()
            : (imageUrl.isNotEmpty
                  ? (view._isLocalImagePath(imageUrl)
                        ? Image.file(
                            File(imageUrl.replaceFirst('file://', '')),
                            fit: BoxFit.cover,
                            errorBuilder: (context, url, error) => Icon(
                              view.widget.type == SharedListType.playlist
                                  ? Icons.playlist_play
                                  : Icons.album,
                              color: Colors.grey[600],
                              size: 64,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: Colors.grey[800]),
                            errorWidget: (context, url, error) => Icon(
                              view.widget.type == SharedListType.playlist
                                  ? Icons.playlist_play
                                  : Icons.album,
                              color: Colors.grey[600],
                              size: 64,
                            ),
                          ))
                  : Icon(
                      view.widget.type == SharedListType.playlist
                          ? Icons.playlist_play
                          : Icons.album,
                      color: Colors.grey[600],
                      size: 64,
                    )),
      ),
    );
  }

  Widget _buildMobileMeta() {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          subtitleUser == null
              ? Text(
                  subtitle!,
                  style: TextStyle(color: Colors.grey[300], fontSize: 24),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                )
              : InkWell(
                  onTap: () => view._openUser(subtitleUser!),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
        ],
        const SizedBox(height: 4),
        Text(
          '$total songs • ${view._formatDuration(view._totalDurationSecs())}',
          style: TextStyle(color: Colors.grey[500], fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildMobilePlaybackRow() {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final isPlayingList =
            view._isCurrentListPlaying(player) && player.isPlaying;
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: view._items.isEmpty
                    ? null
                    : () {
                        if (view._isCurrentListPlaying(player)) {
                          view._toggleCurrentTrackPlayback(player);
                        } else {
                          view._playFromStart();
                        }
                      },
                icon: Icon(
                  isPlayingList
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  size: 20,
                ),
                label: Text(
                  isPlayingList ? 'Pause' : 'Play',
                  style: const TextStyle(fontSize: 20),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: FilledButton.icon(
                onPressed: view._items.isEmpty
                    ? null
                    : () {
                        if (view._isCurrentListPlaying(player)) {
                          view._toggleListShuffle(player);
                        } else {
                          view._playFromStart(shuffle: true);
                        }
                      },
                icon: const Icon(CupertinoIcons.shuffle, size: 20),
                label: const Text('Shuffle', style: TextStyle(fontSize: 20)),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDesktopPlaybackRow({required double availableWidth}) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final isPlayingList =
            view._isCurrentListPlaying(player) && player.isPlaying;
        final useCompactControls = availableWidth < 625;

        Widget buildPlaybackButton({
          required VoidCallback? onPressed,
          required IconData icon,
          required String label,
          required bool isPrimary,
        }) {
          if (useCompactControls) {
            return FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Icon(icon, size: 20),
            );
          }

          return FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: FilledButton.styleFrom(
              enabledMouseCursor: SystemMouseCursors.click,
              disabledMouseCursor: SystemMouseCursors.basic,
              minimumSize: const Size(112, 40),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                buildPlaybackButton(
                  onPressed: view._items.isEmpty
                      ? null
                      : () {
                          if (view._isCurrentListPlaying(player)) {
                            view._toggleCurrentTrackPlayback(player);
                          } else {
                            view._playFromStart();
                          }
                        },
                  icon: isPlayingList
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  label: isPlayingList ? 'Pause' : 'Play',
                  isPrimary: true,
                ),
                SizedBox(width: useCompactControls ? 6 : 10),
                buildPlaybackButton(
                  onPressed: view._items.isEmpty
                      ? null
                      : () {
                          if (view._isCurrentListPlaying(player)) {
                            view._toggleListShuffle(player);
                          } else {
                            view._playFromStart(shuffle: true);
                          }
                        },
                  icon: CupertinoIcons.shuffle,
                  label: 'Shuffle',
                  isPrimary: false,
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    CupertinoIcons.share,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: view._showShareDialog,
                ),
                IconButton(
                  icon: Icon(
                    CupertinoIcons.pencil,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: view._showEditDialog,
                ),
                IconButton(
                  icon: Icon(
                    CupertinoIcons.arrow_down_to_line,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: view._isLoading ? null : view._downloadAll,
                ),
                Builder(
                  builder: (buttonContext) => IconButton(
                    icon: Icon(
                      CupertinoIcons.ellipsis,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () =>
                        view._showListContextMenu(anchorContext: buttonContext),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
