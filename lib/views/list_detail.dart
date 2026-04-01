/// Shared playlist/album detail view
library;

import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:io' show Platform, File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/metadata_models.dart';
import '../services/wisp_audio_handler.dart' as global_audio_player;
import '../providers/library/library_folders.dart';
import '../providers/metadata/spotify_internal.dart';
import '../providers/library/local_playlists.dart';
import '../providers/connect/connect_session_provider.dart';
import '../providers/preferences/preferences_provider.dart';
import '../providers/library/library_state.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/library_item_context_menu.dart';
import '../widgets/hover_underline.dart';
import '../widgets/navigation.dart';
import '../widgets/playlist_folder_modals.dart';
import '../widgets/like_button.dart';
import '../services/app_navigation.dart';
import '../services/cache_manager.dart';
import '../services/metadata_cache.dart';
import '../providers/navigation_state.dart';
import '../utils/liked_songs.dart';
import '../widgets/liked_songs_art.dart';
import '../widgets/provider_disabled_state.dart';

enum SharedListType { playlist, album }

enum _SortMethod { position, title, author, album, duration, source }

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
  final ScrollController _desktopScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();
  final GlobalKey _songListKey = GlobalKey();
  VoidCallback? _likedTracksListener;
  late final SpotifyInternalProvider _spotifyInternal;

  bool _isLocalImagePath(String path) {
    return path.startsWith('/') || path.startsWith('file://');
  }

  NavigationState get _navState => context.read<NavigationState>();
  LibraryView get _currentLibraryView => _navState.selectedLibraryView;
  int get _currentNavIndex => _navState.selectedNavIndex;
  bool _preShuffleEnabled = false;
  List<GenericSong> _preShuffledQueue = [];
  final Set<String> _hoveredSongIds = {};

  @override
  void initState() {
    super.initState();
    _spotifyInternal = context.read<SpotifyInternalProvider>();
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

  Future<void> _saveLocalPlaylistToSpotify() async {
    final localState = context.read<LocalPlaylistState>();
    final localPlaylist = localState.getById(widget.id);
    if (localPlaylist == null) return;
    if (!context.read<PreferencesProvider>().allowWriting) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Spotify writing is disabled in Preferences.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final spotifyTrackIds = localPlaylist.tracks
        .where(
          (item) =>
              item.source == SongSource.spotify ||
              item.source == SongSource.spotifyInternal,
        )
        .map((item) => item.id)
        .toList();
    if (spotifyTrackIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Spotify tracks to save.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

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

    String? targetId = localPlaylist.linkedSource == SongSource.spotifyInternal
        ? localPlaylist.linkedId
        : null;

    try {
      if (targetId == null || targetId.isEmpty) {
        targetId = await spotifyInternal.createPlaylist(
          name: localPlaylist.title,
        );
        await localState.linkToProvider(
          id: localPlaylist.id,
          provider: SongSource.spotifyInternal,
          providerId: targetId,
        );
      }

      await spotifyInternal.addTracksToPlaylist(targetId, spotifyTrackIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved Spotify tracks to playlist.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save playlist: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _detachLocalPlaylist() {
    final localState = context.read<LocalPlaylistState>();
    localState.detachFromProvider(widget.id);
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
        context.read<LibraryState>().removeAlbum(album.id);
      } else {
        await spotifyInternal.saveAlbum(album.id);
        context.read<LibraryState>().addAlbum(album);
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
    if (mounted) {
      setState(() {});
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
    }
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
          compare = _getAuthor(items[a]).compareTo(_getAuthor(items[b]));
          break;
        case _SortMethod.album:
          compare = _getAlbumTitle(
            items[a],
          ).compareTo(_getAlbumTitle(items[b]));
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

  String? _getUid(_ListItem item) {
    if (item is PlaylistItem) return item.uid;
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

    await context.read<ConnectSessionProvider>().requestSetQueue(
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
      context.read<LibraryFolderState>().markPlaylistPlayed(widget.id);
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

    await context.read<ConnectSessionProvider>().requestSetQueue(
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
      context.read<LibraryFolderState>().markPlaylistPlayed(widget.id);
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

        var message = 'Queued $queued track${queued == 1 ? '' : 's'} for download';
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

  /// Show more options menu
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement share
              },
            ),
            if (widget.type == SharedListType.album)
              Builder(
                builder: (context) {
                  final album = _album;
                  if (album == null) return const SizedBox.shrink();
                  final libraryState = context.watch<LibraryState>();
                  final isSaved = libraryState.isAlbumSaved(album.id);
                  return Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          isSaved ? Icons.bookmark_remove : Icons.bookmark_add,
                          color: Colors.white,
                        ),
                        title: Text(
                          isSaved ? 'Remove from Library' : 'Save to Library',
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _toggleSaveAlbum(isSaved);
                        },
                      ),
                    ],
                  );
                },
              ),
            if (widget.type == SharedListType.playlist)
              Builder(
                builder: (context) {
                  final localState = context.read<LocalPlaylistState>();
                  final localPlaylist = localState.getById(widget.id);
                  if (localPlaylist == null) return const SizedBox.shrink();
                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.cloud_upload,
                          color: Colors.white,
                        ),
                        title: const Text(
                          'Save to Spotify',
                          style: TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _saveLocalPlaylistToSpotify();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.edit, color: Colors.white),
                        title: const Text(
                          'Rename',
                          style: TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          PlaylistFolderModals.showRenamePlaylistDialog(
                            context,
                            _playlist!,
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.image_outlined,
                          color: Colors.white,
                        ),
                        title: const Text(
                          'Change thumbnail',
                          style: TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          PlaylistFolderModals.showChangePlaylistThumbnailDialog(
                            context,
                            _playlist!,
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                        title: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          PlaylistFolderModals.deletePlaylistWithSync(
                            context,
                            widget.id,
                          );
                          if (mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                      ),
                      if (localPlaylist.isLinked)
                        ListTile(
                          leading: const Icon(
                            Icons.link_off,
                            color: Colors.white,
                          ),
                          title: const Text(
                            'Detach from provider',
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _detachLocalPlaylist();
                          },
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showShareDialog() {
    final isSpotify = _playlist?.source == SongSource.spotify ||
        _playlist?.source == SongSource.spotifyInternal ||
        _album?.source == SongSource.spotify ||
        _album?.source == SongSource.spotifyInternal ||
        widget.id.startsWith('spotify:');

    if (isSpotify) {
      final typePath = widget.type == SharedListType.playlist ? 'playlist' : 'album';
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Share not implemented for this source yet')));
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

  void _showDesktopListMenu(BuildContext buttonContext) {
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox;
    final box = buttonContext.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset.zero, ancestor: overlay);
    const menuWidth = 220.0;
    var left = position.dx;
    final maxLeft = overlay.size.width - menuWidth - 8;
    if (left > maxLeft) left = maxLeft;
    if (left < 8) left = 8;

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: position.dy + box.size.height,
              child: Material(
                color: const Color(0xFF282828),
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: menuWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDesktopMenuButton(
                          dialogContext,
                          icon: Icons.download_outlined,
                          label: 'Download All',
                          onTap: _downloadAll,
                        ),
                        if (widget.type == SharedListType.playlist) ...[
                          Builder(
                            builder: (context) {
                              final localState = context
                                  .read<LocalPlaylistState>();
                              final localPlaylist = localState.getById(
                                widget.id,
                              );
                              if (localPlaylist == null) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 4),
                                  _buildDesktopMenuButton(
                                    dialogContext,
                                    icon: Icons.cloud_upload,
                                    label: 'Save to Spotify',
                                    onTap: _saveLocalPlaylistToSpotify,
                                  ),
                                  _buildDesktopMenuButton(
                                    dialogContext,
                                    icon: Icons.edit,
                                    label: 'Rename',
                                    onTap: () {
                                      PlaylistFolderModals.showRenamePlaylistDialog(
                                        context,
                                        _playlist!,
                                      );
                                    },
                                  ),
                                  _buildDesktopMenuButton(
                                    dialogContext,
                                    icon: Icons.image_outlined,
                                    label: 'Change thumbnail',
                                    onTap: () {
                                      PlaylistFolderModals.showChangePlaylistThumbnailDialog(
                                        context,
                                        _playlist!,
                                      );
                                    },
                                  ),
                                  _buildDesktopMenuButton(
                                    dialogContext,
                                    icon: Icons.delete_outline,
                                    label: 'Delete',
                                    onTap: () {
                                      PlaylistFolderModals.deletePlaylistWithSync(
                                        context,
                                        widget.id,
                                      );
                                      if (mounted) {
                                        Navigator.of(context).maybePop();
                                      }
                                    },
                                  ),
                                  if (localPlaylist.isLinked)
                                    _buildDesktopMenuButton(
                                      dialogContext,
                                      icon: Icons.link_off,
                                      label: 'Detach from provider',
                                      onTap: _detachLocalPlaylist,
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 4),
                        _buildDesktopMenuButton(
                          dialogContext,
                          icon: Icons.share,
                          label: 'Share',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Share not implemented yet'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDesktopMenuButton(
    BuildContext dialogContext, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
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

    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _buildListContentByStyle(
            style: style,
            title: title,
            subtitle: subtitle,
            imageUrl: imageUrl,
            subtitleImageUrl: subtitleImageUrl,
            total: total,
            isDesktop: isDesktop,
            description: description,
          );

    if (isDesktop) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: content,
      );
    }

    if (style == 'Apple Music') {
      return Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: _isLoading
            ? AppBar(
                backgroundColor: Colors.transparent,
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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [_buildSortButton()],
      ),
      body: content,
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
        const SizedBox(height: 16),
        // Title and info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.type == SharedListType.playlist
                        ? 'PLAYLIST'
                        : 'ALBUM',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                      letterSpacing: 1.5,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    Text(' • ', style: TextStyle(color: Colors.grey[500])),
                    Expanded(
                      child: Text(
                        subtitle,
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                        overflow: TextOverflow.ellipsis,
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
                const SizedBox(height: 10),
                Text(
                  descriptionText,
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
                onPressed: () => _showMoreOptions(),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 140,
              height: 140,
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
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (hasDescription) const SizedBox(height: 4),
                if (hasDescription)
                  Text(
                    descriptionText,
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (subtitleImageUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 24,
                          height: 24,
                          color: Colors.grey[900],
                          child: _isLocalImagePath(subtitleImageUrl)
                              ? Image.file(
                                  File(subtitleImageUrl.replaceFirst('file://', '')),
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
                      SizedBox(width: 8),
                    ],
                    if (subtitle != null)
                      Flexible(
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                      style: TextStyle(color: Colors.grey[300], fontSize: 14),
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
                      style: TextStyle(color: Colors.grey[300], fontSize: 14),
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

  Widget _buildActionsRow(bool isDesktop) {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
          alignment: Alignment.bottomLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: FilledButton(
                      onPressed: () {
                        if (!_isLoading) {
                          if (_isCurrentListPlaying(player)) {
                            player.togglePlayPause();
                          } else {
                            _playFromStart();
                          }
                        }
                      },
                      style: FilledButton.styleFrom(
                        enabledMouseCursor: SystemMouseCursors.click,
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Icon(
                        _isCurrentListPlaying(player) && player.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () {
                    _toggleListShuffle(player);
                  },
                  icon: Icon(
                    Icons.shuffle,
                    color:
                        (_isCurrentListPlaying(player)
                            ? player.shuffleEnabled
                            : _preShuffleEnabled)
                        ? colorScheme.primary
                        : Colors.grey[300],
                  ),
                ),
                IconButton(
                  onPressed: player.toggleRepeat,
                  icon: Icon(
                    player.repeatMode == global_audio_player.RepeatMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color:
                        player.repeatMode == global_audio_player.RepeatMode.off
                        ? Colors.grey[300]
                        : colorScheme.primary,
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _downloadAll,
                  icon: const Icon(Icons.download, color: Colors.grey),
                ),
                Builder(
                  builder: (buttonContext) {
                    return IconButton(
                      onPressed: () {
                        if (isDesktop) {
                          _showDesktopListMenu(buttonContext);
                        } else {
                          _showMoreOptions();
                        }
                      },
                      icon: const Icon(Icons.more_horiz, color: Colors.grey),
                    );
                  },
                ),
                const SizedBox(width: 12),
                if (_showSearch)
                  SizedBox(
                    width: isDesktop ? 240 : 160,
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
                        fillColor: Colors.black.withOpacity(0.4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
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
                IconButton(
                  onPressed: () => _sortBy(_sortMethod),
                  icon: Icon(
                    _ascending
                        ? Icons.keyboard_double_arrow_up
                        : Icons.keyboard_double_arrow_down,
                    color: Colors.grey[300],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
          style: isSorted ? headerStyle.copyWith(color: Colors.white) : headerStyle,
        ),
        if (sortIcon != null) ...[
          const SizedBox(width: 4),
          sortIcon,
        ],
      ],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap ?? () => _sortBy(method),
        child: content,
      ),
    );
  }

  Widget _buildListHeaderContent({
    _ListVisualStyle visualStyle = _ListVisualStyle.spotify,
  }) {
    final headerStyle = TextStyle(color: Colors.grey[400], fontSize: 12);

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
          const SizedBox(width: 48), // Adjusted space for more context menu room
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: InkWell(
            onTap: () => _sortBy(_SortMethod.position),
            child: Text('#', style: headerStyle, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(width: 8),
        const SizedBox(width: 44),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: InkWell(
            onTap: _handleTitleHeaderTap,
            child: Text(
              _sortMethod == _SortMethod.author ? 'Author' : 'Title',
              style: headerStyle,
            ),
          ),
        ),
        if (widget.type == SharedListType.playlist)
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: () => _sortBy(_SortMethod.album),
              child: Text(
                'Album',
                style: headerStyle,
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          const SizedBox(width: 80),
        if (widget.type == SharedListType.playlist)
          SizedBox(
            width: 120,
            child: Text(
              'Added',
              style: headerStyle,
              textAlign: TextAlign.center,
            ),
          )
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
          child: InkWell(
            onTap: () => _sortBy(_SortMethod.duration),
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.access_time, size: 14, color: Colors.grey)
            )
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 32,
          child: InkWell(
            onTap: () => _sortBy(_SortMethod.source),
            child: Text('', style: headerStyle),
          ),
        ),
      ],
    );
  }

  Widget _buildSongList({
    bool isMobile = false,
    _ListVisualStyle visualStyle = _ListVisualStyle.spotify,
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
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleCount,
            itemBuilder: (context, idx) {
              final player = context
                  .watch<global_audio_player.WispAudioHandler>();
              final rowIndex = startIndex + idx;
              final index = _sortedIndices[rowIndex];
              final item = _items[index];
              final isEven = rowIndex % 2 == 0;
              final song = _toGenericSong(item);
              final isCurrentTrack = player.currentTrack?.id == song.id;
              final album = _getAlbum(item);
              final artists = _getArtists(item);

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
                  onSecondaryTapDown: isDesktop
                      ? (details) {
                          TrackContextMenu.show(
                            context: context,
                            track: song,
                            position: details.globalPosition,
                            playlistId: widget.type == SharedListType.playlist
                                ? widget.id
                                : null,
                            playlistName: widget.type == SharedListType.playlist
                                ? _playlist?.title
                                : null,
                            playlistTrackUid: _getUid(item),
                            playlists: widget.playlists,
                            albums: widget.albums,
                            artists: widget.artists,
                            currentLibraryView: _currentLibraryView,
                            currentNavIndex: _currentNavIndex,
                          );
                        }
                      : null,
                  onLongPress: isDesktop
                      ? null
                      : () {
                          TrackContextMenu.show(
                            context: context,
                            track: song,
                            playlistId: widget.type == SharedListType.playlist
                                ? widget.id
                                : null,
                            playlistName: widget.type == SharedListType.playlist
                                ? _playlist?.title
                                : null,
                            playlistTrackUid: _getUid(item),
                            playlists: widget.playlists,
                            albums: widget.albums,
                            artists: widget.artists,
                            currentLibraryView: _currentLibraryView,
                            currentNavIndex: _currentNavIndex,
                          );
                        },
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: isDesktop
                          ? null
                          : () {
                              if (isCurrentTrack) {
                                if (player.isPlaying) {
                                  player.pause();
                                } else {
                                  player.play();
                                }
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
                          color: isAppleStyle
                              ? Colors.transparent
                              : (isEven
                                    ? Colors.transparent
                                    : Colors.black.withOpacity(0.15)),
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
                                            if (player.isPlaying) {
                                              player.pause();
                                            } else {
                                              player.play();
                                            }
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
                              child: Container(
                                width: 44,
                                height: 44,
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
                                  if (!isAppleStyle) ...[
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
                              Expanded(
                                flex: 2,
                                child: _buildArtistLine(
                                  artists,
                                  isDesktop: isDesktop,
                                ),
                              ),
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
                                          LibraryItemContextMenu.show(
                                            context: context,
                                            item: album,
                                            position: details.globalPosition,
                                            playlists: widget.playlists,
                                            albums: widget.albums,
                                            artists: widget.artists,
                                            currentLibraryView:
                                                _currentLibraryView,
                                            currentNavIndex: _currentNavIndex,
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
                                  child: GestureDetector(
                                    onTapDown: (details) {
                                      TrackContextMenu.show(
                                        context: context,
                                        track: song,
                                        position: details.globalPosition,
                                        playlistId: widget.type == SharedListType.playlist
                                            ? widget.id
                                            : null,
                                        playlistName: widget.type == SharedListType.playlist
                                            ? _playlist?.title
                                            : null,
                                        playlistTrackUid: _getUid(item),
                                        playlists: widget.playlists,
                                        albums: widget.albums,
                                        artists: widget.artists,
                                        currentLibraryView: _currentLibraryView,
                                        currentNavIndex: _currentNavIndex,
                                      );
                                    },
                                    child: Icon(
                                      CupertinoIcons.ellipsis,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              if (!isMobile &&
                                  widget.type == SharedListType.playlist)
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
                                            LibraryItemContextMenu.show(
                                              context: context,
                                              item: album,
                                              position: details.globalPosition,
                                              playlists: widget.playlists,
                                              albums: widget.albums,
                                              artists: widget.artists,
                                              currentLibraryView:
                                                  _currentLibraryView,
                                              currentNavIndex: _currentNavIndex,
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
                              else if (!isMobile)
                                const SizedBox(width: 80),
                              if (!isMobile &&
                                  widget.type == SharedListType.playlist)
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
                              else if (!isMobile)
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
                              ),
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
            onSecondaryTapDown: isDesktop
                ? (details) {
                    TrackContextMenu.show(
                      context: context,
                      track: song,
                      position: details.globalPosition,
                      playlistId: widget.type == SharedListType.playlist
                          ? widget.id
                          : null,
                      playlistName: widget.type == SharedListType.playlist
                          ? _playlist?.title
                          : null,
                      playlistTrackUid: _getUid(item),
                      playlists: widget.playlists,
                      albums: widget.albums,
                      artists: widget.artists,
                      currentLibraryView: _currentLibraryView,
                      currentNavIndex: _currentNavIndex,
                    );
                  }
                : null,
            onLongPress: isDesktop
                ? null
                : () {
                    TrackContextMenu.show(
                      context: context,
                      track: song,
                      playlistId: widget.type == SharedListType.playlist
                          ? widget.id
                          : null,
                      playlistName: widget.type == SharedListType.playlist
                          ? _playlist?.title
                          : null,
                      playlistTrackUid: _getUid(item),
                      playlists: widget.playlists,
                      albums: widget.albums,
                      artists: widget.artists,
                      currentLibraryView: _currentLibraryView,
                      currentNavIndex: _currentNavIndex,
                    );
                  },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: isDesktop
                    ? null
                    : () {
                        if (isCurrentTrack) {
                          if (player.isPlaying) {
                            player.pause();
                          } else {
                            player.play();
                          }
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
                              : Colors.black.withOpacity(0.15)),
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
                                      if (player.isPlaying) {
                                        player.pause();
                                      } else {
                                        player.play();
                                      }
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
                        child: Container(
                          width: 44,
                          height: 44,
                          color: Colors.grey[900],
                          child: CachedNetworkImage(
                            imageUrl: _getThumbnail(item),
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                Icon(Icons.music_note, color: Colors.grey[700]),
                            placeholder: (context, url) =>
                                Container(color: Colors.grey[800]),
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
                            if (!isAppleStyle) ...[
                              const SizedBox(height: 2),
                              _buildArtistLine(artists, isDesktop: isDesktop),
                            ],
                          ],
                        ),
                      ),
                      if (!isMobile && isAppleStyle) ...[
                        Expanded(
                          flex: 2,
                          child: _buildArtistLine(
                            artists,
                            isDesktop: isDesktop,
                          ),
                        ),
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
                                    LibraryItemContextMenu.show(
                                      context: context,
                                      item: album,
                                      position: details.globalPosition,
                                      playlists: widget.playlists,
                                      albums: widget.albums,
                                      artists: widget.artists,
                                      currentLibraryView: _currentLibraryView,
                                      currentNavIndex: _currentNavIndex,
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
                            child: GestureDetector(
                              onTapDown: (details) {
                                TrackContextMenu.show(
                                  context: context,
                                  track: song,
                                  position: details.globalPosition,
                                  playlistId: widget.type == SharedListType.playlist
                                      ? widget.id
                                      : null,
                                  playlistName: widget.type == SharedListType.playlist
                                      ? _playlist?.title
                                      : null,
                                  playlistTrackUid: _getUid(item),
                                  playlists: widget.playlists,
                                  albums: widget.albums,
                                  artists: widget.artists,
                                  currentLibraryView: _currentLibraryView,
                                  currentNavIndex: _currentNavIndex,
                                );
                              },
                              child: Icon(
                                CupertinoIcons.ellipsis,
                                color: Theme.of(context).colorScheme.primary,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        if (!isMobile && widget.type == SharedListType.playlist)
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
                                      LibraryItemContextMenu.show(
                                        context: context,
                                        item: album,
                                        position: details.globalPosition,
                                        playlists: widget.playlists,
                                        albums: widget.albums,
                                        artists: widget.artists,
                                        currentLibraryView: _currentLibraryView,
                                        currentNavIndex: _currentNavIndex,
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
                        else if (!isMobile)
                          const SizedBox(width: 80),
                        if (!isMobile && widget.type == SharedListType.playlist)
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
                        else if (!isMobile)
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
                        ),
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
              LibraryItemContextMenu.show(
                context: context,
                item: artists[i],
                position: details.globalPosition,
                playlists: widget.playlists,
                albums: widget.albums,
                artists: widget.artists,
                currentLibraryView: _currentLibraryView,
                currentNavIndex: _currentNavIndex,
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

class _StickyActionBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyActionBarDelegate({required this.child});

  @override
  double get minExtent => 72.0;

  @override
  double get maxExtent => 72.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_StickyActionBarDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

class _SpotifyListDetailRenderer extends StatelessWidget {
  final _SharedListDetailViewState view;
  final String title;
  final String? subtitle;
  final String imageUrl;
  final String? subtitleImageUrl;
  final int total;
  final bool isDesktop;
  final String? description;

  const _SpotifyListDetailRenderer({
    required this.view,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.subtitleImageUrl,
    required this.total,
    required this.isDesktop,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = !isDesktop;
    final padding = isMobile ? 20.0 : 24.0;

    if (isMobile) {
      return Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: view._mobileScrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
                    child: view._buildMobileHeader(
                      title,
                      subtitle,
                      imageUrl,
                      total,
                      description,
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyActionBarDelegate(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: padding / 2,
                        vertical: padding / 2,
                      ),
                      color: const Color(0xFF121212),
                      child: view._buildMobileActionsRow(),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.zero,
                  sliver: SliverToBoxAdapter(
                    child: view._buildSongList(isMobile: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        if (imageUrl.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Opacity(
                opacity: 0.35,
                child: view._isLocalImagePath(imageUrl)
                    ? Image.file(
                        File(imageUrl.replaceFirst('file://', '')),
                        fit: BoxFit.cover,
                        errorBuilder: (context, url, error) =>
                            Container(color: Colors.grey[900]),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            Container(color: Colors.grey[900]),
                      ),
              ),
            ),
          ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.4),
                  Colors.black.withOpacity(0.9),
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
                  padding: EdgeInsets.all(padding),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          view._buildHeader(
                            title,
                            subtitle,
                            subtitleImageUrl,
                            imageUrl,
                            total,
                            description,
                          ),
                          view._buildActionsRow(isDesktop),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: view._buildListHeaderContent(),
                          ),
                          view._buildSongList(isMobile: false),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
  final String imageUrl;
  final int total;
  final bool isDesktop;
  final String? description;
  final String? subtitleImageUrl;

  const _AppleMusicListDetailRenderer({
    required this.view,
    required this.title,
    required this.subtitle,
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
      return Container(
        color: Colors.grey[900],
        child: const LikedSongsArt(),
      );
    }

    if (imageUrl.isNotEmpty) {
      if (view._isLocalImagePath(imageUrl)) {
        return Image.file(
          File(imageUrl.replaceFirst('file://', '')),
          fit: BoxFit.cover,
          errorBuilder: (context, url, error) => Container(color: Colors.grey[900]),
        );
      } else {
        return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey[900]),
          errorWidget: (context, url, error) => Container(color: Colors.grey[900]),
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

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: Colors.black,
          ),
        ),
        CustomScrollView(
          controller: view._mobileScrollController,
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.black,
              pinned: true,
              expandedHeight: MediaQuery.of(context).size.width - MediaQuery.of(context).padding.top,
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                IconButton(
                  icon: const Icon(CupertinoIcons.arrow_down_to_line),
                  onPressed: view._isLoading ? null : view._downloadAll,
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.ellipsis_vertical),
                  onPressed: view._showMoreOptions,
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildHeaderArtwork(context),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.4),
                            Colors.transparent,
                            Colors.black.withOpacity(0.6),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: _buildMobilePlaybackRow(),
              ),
            ),
            if (hasDescription)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                  child: Text(
                    descriptionText,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: view._buildSongList(
                  isMobile: true,
                  visualStyle: _ListVisualStyle.apple,
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

    return Stack(
      children: [
        if (imageUrl.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Opacity(
                opacity: 0.24,
                child: view._isLocalImagePath(imageUrl)
                    ? Image.file(
                        File(imageUrl.replaceFirst('file://', '')),
                        fit: BoxFit.cover,
                        errorBuilder: (context, url, error) =>
                            Container(color: Colors.black),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            Container(color: Colors.black),
                      ),
              ),
            ),
          ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.45),
                  Colors.black.withOpacity(0.78),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: ListView(
            controller: view._desktopScrollController,
            padding: const EdgeInsets.fromLTRB(30, 30, 30, 18),
            children: [
              Row(
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
                        if ((subtitle != null && subtitle!.isNotEmpty) || subtitleImageUrl != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (subtitleImageUrl != null) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: view._isLocalImagePath(subtitleImageUrl!)
                                      ? Image.file(
                                          File(subtitleImageUrl!.replaceFirst('file://', '')),
                                          width: 24,
                                          height: 24,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, url, error) =>
                                              Container(width: 24, height: 24, color: Colors.grey[700]),
                                        )
                                      : CachedNetworkImage(
                                          imageUrl: subtitleImageUrl!,
                                          width: 24,
                                          height: 24,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) =>
                                              Container(width: 24, height: 24, color: Colors.grey[700]),
                                        ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (subtitle != null && subtitle!.isNotEmpty) 
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ]
                          )
                        ],
                        if (hasDescription) ...[
                          const SizedBox(height: 4),
                          Text(
                            descriptionText,
                            style: TextStyle(color: Colors.grey[400], fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildDesktopPlaybackRow(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
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
                          onPressed: () => view._showDesktopListMenu(buttonContext),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: view._buildListHeaderContent(
                  visualStyle: _ListVisualStyle.apple,
                ),
              ),
              const SizedBox(height: 8),
              view._buildSongList(
                isMobile: false,
                visualStyle: _ListVisualStyle.apple,
              ),
            ],
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
          Text(
            subtitle!,
            style: TextStyle(color: Colors.grey[300], fontSize: 24),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
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
                          player.togglePlayPause();
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
                  style: const TextStyle(
                    fontSize: 20,
                  )
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
                icon: const Icon(
                  CupertinoIcons.shuffle,
                  size: 20,
                ),
                label: const Text(
                  'Shuffle',
                  style: TextStyle(
                    fontSize: 20,
                  )
                  ),
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

  Widget _buildDesktopPlaybackRow() {
    return Consumer<global_audio_player.WispAudioHandler>(
      builder: (context, player, child) {
        final isPlayingList =
            view._isCurrentListPlaying(player) && player.isPlaying;
        return Row(
          children: [
            FilledButton.icon(
              onPressed: view._items.isEmpty
                  ? null
                  : () {
                      if (view._isCurrentListPlaying(player)) {
                        player.togglePlayPause();
                      } else {
                        view._playFromStart();
                      }
                    },
              icon: Icon(
                isPlayingList
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
              ),
              label: Text(isPlayingList ? 'Pause' : 'Play'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(118, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: view._items.isEmpty
                  ? null
                  : () {
                      if (view._isCurrentListPlaying(player)) {
                        view._toggleListShuffle(player);
                      } else {
                        view._playFromStart(shuffle: true);
                      }
                    },
              icon: const Icon(CupertinoIcons.shuffle),
              label: const Text('Shuffle'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(118, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
