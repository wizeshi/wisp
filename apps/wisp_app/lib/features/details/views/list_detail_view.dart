// Copyright © 2026 wizeshi

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
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/shared/widgets/playback/playback_selectors.dart';
import 'package:wisp/shared/widgets/rows/track_row.dart';
import 'package:wisp/core/utils/text_parser.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/services/system/listening_habits_service.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart' as global_audio_player;
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/core/theme/cover_art_palette_provider.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/shared/widgets/display/hover_underline.dart';
import 'package:wisp/features/shell/widgets/navigation.dart';
import 'package:wisp/shared/widgets/menus/playlist_folder_modals.dart';
import 'package:wisp/shared/widgets/menus/adaptive_context_menu.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/shared/widgets/buttons/like_button.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/sources/youtube/youtube_audio.dart';
import 'package:wisp/core/utils/liked_songs.dart';
import 'package:wisp/shared/widgets/artwork/liked_songs_art.dart';
import 'package:wisp/shared/widgets/display/provider_disabled_state.dart';
import 'package:wisp/shared/widgets/display/smooth_scroll.dart';
part 'renderers/spotify_list_detail_renderer.dart';
part 'renderers/apple_music_list_detail_renderer.dart';
part 'menus/list_detail_context_menus.dart';
part 'components/recommended_tracks_section.dart';
part 'headers/list_detail_headers.dart';
part 'components/track_list_view.dart';

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
  final ValueNotifier<double> _songListTopOffsetNotifier =
      ValueNotifier<double>(0);
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

  Object? _lastRowTapKey;
  DateTime? _lastRowTapTime;

  void _handleRowDoubleClick(Object key, VoidCallback onDoubleClick) {
    final now = DateTime.now();
    if (_lastRowTapKey == key &&
        _lastRowTapTime != null &&
        now.difference(_lastRowTapTime!) <= kDoubleTapTimeout) {
      _lastRowTapKey = null;
      _lastRowTapTime = null;
      onDoubleClick();
    } else {
      _lastRowTapKey = key;
      _lastRowTapTime = now;
    }
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
    _songListTopOffsetNotifier.dispose();
    super.dispose();
  }

  void _handleScroll(ScrollController controller) {
    if (!controller.hasClients) return;
    if (_hoveredSongIds.isNotEmpty) {
      setState(() => _hoveredSongIds.clear());
    }
    _updateStickyBarVisibility(controller); // already setState()-conditional
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

    final fakeColor = HSLColor.fromColor(
      scheme?.primary ?? const Color(0xFF1E1E1E),
    );
    final nextColor = fakeColor
        .withLightness(log(fakeColor.lightness + 1) / log(3))
        .toColor();

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
      if ((listStartOffset - _songListTopOffsetNotifier.value).abs() > 1) {
        _songListTopOffsetNotifier.value = listStartOffset;
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

  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
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
      playbackContext: PlaybackContext(
        type: widget.type == SharedListType.playlist
            ? PlaybackContextType.playlist
            : PlaybackContextType.album,
        id: contextID,
        name: contextName,
        source: contextSource ?? SongSource.spotifyInternal,
      ),
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
      playbackContext: PlaybackContext(
        type: widget.type == SharedListType.playlist
            ? PlaybackContextType.playlist
            : PlaybackContextType.album,
        id: contextID,
        name: contextName,
        source: contextSource ?? SongSource.spotifyInternal,
      ),
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

  /// The [PlaybackContext] this view's own queue is (or would be) built
  /// with â€” "this playlist" / "this album". Passed to every [TrackRow] so
  /// a row only shows itself as current/playing when the queue actually
  /// loaded in the player is *this* one, not some other list that happens
  /// to contain the same song. Mirrors the context built in
  /// [_setQueueAndPlay]; [_isCurrentListPlaying] compares against it via
  /// [PlaybackContext.matches].
  PlaybackContext get _viewContext {
    final contextName = widget.type == SharedListType.playlist
        ? (_playlist?.title ?? '')
        : (_album?.title ?? '');
    final contextSource = widget.type == SharedListType.playlist
        ? _playlist?.source
        : _album?.source;
    return PlaybackContext(
      type: widget.type == SharedListType.playlist
          ? PlaybackContextType.playlist
          : PlaybackContextType.album,
      id: widget.id,
      name: contextName,
      source: contextSource ?? SongSource.spotifyInternal,
    );
  }

  bool _isCurrentListPlaying(global_audio_player.WispAudioHandler player) {
    if (player.currentTrack == null) return false;
    final playerContext = player.playbackContext;
    return playerContext != null && playerContext.matches(_viewContext);
  }

  void _toggleListShuffle(global_audio_player.WispAudioHandler player) {
    if (_isCurrentListPlaying(player)) {
      context.read<PlaybackCoordinator>().toggleShuffle();
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
          message += ' â€¢ ${blockedPolicy + blockedNetworkOnly} blocked';
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
      playbackContext: PlaybackContext(
        type: contextType == 'playlist'
            ? PlaybackContextType.playlist
            : PlaybackContextType.album,
        id: widget.id,
        name: contextName,
        source: contextSource ?? SongSource.spotifyInternal,
      ),
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

    if (style == AppStyle.AppleMusic) {
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
            duration: const Duration(milliseconds: 0),
            reverseDuration: const Duration(milliseconds: 180),
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
    required AppStyle style,
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
      case AppStyle.AppleMusic:
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
      case AppStyle.Original:
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
      case AppStyle.Spotify:
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
}