// Copyright © 2026 wizeshi

/// Shared playlist/album detail view
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';
import 'package:wisp/core/theme/app_theme.dart';
import 'package:wisp/shared/widgets/rows/track_row.dart';
import 'package:wisp/core/utils/logger.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/services/system/listening_habits_service.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart'
    as global_audio_player;
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/features/library/state/library_state.dart';
import 'package:wisp/shared/widgets/menus/playlist_folder_modals.dart';
import 'package:wisp/shared/widgets/menus/adaptive_context_menu.dart';
import 'package:wisp/shared/widgets/menus/entity_context_menus.dart';
import 'package:wisp/shared/widgets/menus/inspect_dialog.dart';
import 'package:wisp/features/shell/navigation/app_navigation.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/data/cache/metadata_diff.dart';
import 'package:wisp/data/cache/metadata_revalidator.dart';
import 'package:wisp/core/utils/liked_songs.dart';
import 'package:wisp/shared/widgets/display/provider_disabled_state.dart';
import 'package:wisp/shared/widgets/style/generic_button.dart';
import 'package:wisp/shared/widgets/alert/wisp_alert_extensions.dart';
import 'package:wisp/features/navigation/shell/navigation_state.dart';

import 'desktop/spotify.dart';
import 'desktop/apple_music.dart';
import 'desktop/original.dart';
import 'mobile/spotify.dart';
import 'mobile/apple_music.dart';
import 'mobile/original.dart';

enum SharedListType { playlist, album }

enum ListSortMethod { position, title, author, album, addedAt, duration, source }

typedef _ListItem = Object;

class SharedListDetailView extends StatefulWidget {
  final String id;
  final SharedListType type;
  final String? source;
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
    this.source,
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
  bool _isRefreshing = false;
  final MetadataRevalidatorToken _revalidationToken =
      MetadataRevalidatorToken();
  GenericPlaylist? _playlist;
  GenericAlbum? _album;
  List<int> _sortedIndices = [];
  ListSortMethod _sortMethod = ListSortMethod.position;
  bool _ascending = true;
  final ScrollController _desktopScrollController = ScrollController();
  final ScrollController _mobileScrollController = ScrollController();
  VoidCallback? _likedTracksListener;
  VoidCallback? _libraryListener;
  VoidCallback? _localPlaylistListener;
  late final MetadataManager _metadataManager;
  late final LocalPlaylistState _localPlaylists;
  late final LibraryState _libraryState;
  bool _preShuffleEnabled = false;
  List<GenericSong> _preShuffledQueue = [];
  String _searchQuery = '';
  List<PlaylistItem> _recommendedSongs = [];
  final List<String> _skippedRecommendationTrackIDs = [];
  final Set<String> _addedRecommendationTrackIDs = {};
  final Set<String> _addingRecommendationTrackIDs = {};
  bool _isLoadingRecommendations = false;

  @override
  void initState() {
    super.initState();
    _metadataManager = context.read<MetadataManager>();
    _localPlaylists = context.read<LocalPlaylistState>();
    _libraryState = context.read<LibraryState>();
    unawaited(_metadataManager.ensureLikedTracksLoaded());
    if (widget.type == SharedListType.playlist) {
      if (isLikedSongsPlaylistId(widget.id)) {
        _likedTracksListener = () {
          if (!mounted) return;
          setState(_rebuildIndices);
        };
        _metadataManager.addListener(_likedTracksListener!);
      } else {
        _libraryListener = () {
          if (!mounted) return;
          GenericPlaylist? found;
          for (final p in _libraryState.playlists) {
            if (p.id == widget.id) {
              found = p;
              break;
            }
          }
          final updated = found;
          if (updated != null) {
            final updatedSongs = updated.songs;
            final hasIncomingTracks =
                updatedSongs != null && updatedSongs.isNotEmpty;
            final currentSongs = _playlist?.songs;

            if (hasIncomingTracks) {
              if (_playlist == null ||
                  MetadataDiff.hasPlaylistItemListChanged(
                    currentSongs,
                    updatedSongs,
                  )) {
                setState(() {
                  _playlist = (_playlist ?? updated).copyWith(
                    title: updated.title,
                    description: updated.description,
                    thumbnailUrl: updated.thumbnailUrl,
                    isPinned: updated.isPinned,
                    songs: updatedSongs,
                    total: updated.total ?? updatedSongs.length,
                    durationSecs: updatedSongs.fold<int>(
                      0,
                      (acc, s) => acc + s.durationSecs,
                    ),
                  );
                  _rebuildIndices();
                });
              }
            } else if (_playlist != null) {
              // Metadata-only update from library (e.g. pinned state, title)
              // Preserve currently loaded tracks!
              if (_playlist!.title != updated.title ||
                  _playlist!.description != updated.description ||
                  _playlist!.thumbnailUrl != updated.thumbnailUrl ||
                  _playlist!.isPinned != updated.isPinned) {
                setState(() {
                  _playlist = _playlist!.copyWith(
                    title: updated.title,
                    description: updated.description,
                    thumbnailUrl: updated.thumbnailUrl,
                    isPinned: updated.isPinned,
                  );
                });
              }
            }
          }
        };
        _libraryState.addListener(_libraryListener!);

        _localPlaylistListener = () {
          if (!mounted) return;
          final updated = _localPlaylists.getGenericPlaylist(widget.id);
          if (updated != null) {
            if (_playlist == null ||
                MetadataDiff.hasPlaylistItemListChanged(
                  _playlist?.songs,
                  updated.songs,
                )) {
              setState(() {
                _playlist = updated;
                _rebuildIndices();
              });
            }
          }
        };
        _localPlaylists.addListener(_localPlaylistListener!);
      }
    }
    _loadListDetails();
  }

  @override
  void didUpdateWidget(covariant SharedListDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.type != widget.type) {
      _revalidationToken.cancel();
      _clearRecommendationsState();
      setState(() {
        _isLoading = true;
        _playlist = null;
        _album = null;
        _sortedIndices = [];
        _searchQuery = '';
      });
      _loadListDetails();
    }
  }

  Future<void> _toggleSaveAlbum(bool isSaved) async {
    final album = _album;
    if (album == null) return;
    final metadataManager = context.read<MetadataManager>();
    if (!metadataManager.isAuthenticated) {
      if (mounted) {
        context.showWarningAlert('Provider is not connected.');
      }
      return;
    }

    try {
      if (isSaved) {
        await metadataManager.unsaveAlbum(album.id, source: album.source);
        if (mounted) context.read<LibraryState>().removeAlbum(album.id);
      } else {
        await metadataManager.saveAlbum(album.id, source: album.source);
        if (mounted) context.read<LibraryState>().addAlbum(album);
      }
      if (mounted) {
        context.showSuccessAlert(
          isSaved ? 'Album removed from library' : 'Album saved',
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorAlert('Failed to update album: $e');
      }
    }
  }

  @override
  void dispose() {
    _revalidationToken.cancel();
    if (_likedTracksListener != null) {
      _metadataManager.removeListener(_likedTracksListener!);
    }
    if (_libraryListener != null) {
      _libraryState.removeListener(_libraryListener!);
    }
    if (_localPlaylistListener != null) {
      _localPlaylists.removeListener(_localPlaylistListener!);
    }
    _desktopScrollController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadListDetails() async {
    final localPlaylists = _localPlaylists;
    final isLocal = widget.type == SharedListType.playlist &&
        !isLikedSongsPlaylistId(widget.id) &&
        localPlaylists.isLocalPlaylistId(widget.id);

    final metadataManager = _metadataManager;
    if (!isLocal && !metadataManager.hasEnabledProviders) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

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
        if (localEntry?.isLinked == true && localEntry?.linkedId != null) {
          try {
            final providerPlaylist =
                await metadataManager.fetchFullPlaylistWithTracks(
              localEntry!.linkedId!,
              source: localEntry.linkedSource,
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
          } catch (e) {
            logger.w('[ListDetailView] Failed to sync linked playlist: $e');
          }
        }
        return;
      }

      if (isLikedSongsPlaylistId(widget.id)) {
        await MetadataRevalidator.revalidate<List<PlaylistItem>>(
          token: _revalidationToken,
          loadCache: () => metadataManager.getCachedLikedSongs(),
          fetchRemote: () => metadataManager.fetchLikedSongs(),
          hasChanged: (curr, fresh) =>
              MetadataDiff.hasPlaylistItemListChanged(curr, fresh),
          onData: (items, {required fromCache}) {
            if (!mounted) return;
            metadataManager.setLikedTracksFromItems(items);
            _playlist = _buildLikedSongsPlaylist(
              items,
              metadataManager.userDisplayName,
            );
            _rebuildIndices();
            setState(() => _isLoading = false);
          },
          onRefreshing: (refreshing) {
            if (mounted && _isRefreshing != refreshing) {
              setState(() => _isRefreshing = refreshing);
            }
          },
          onError: (e) {
            if (mounted && _playlist == null) {
              context.showErrorAlert('Failed to load liked songs: $e');
            }
          },
        );
        if (mounted && !_revalidationToken.isCancelled) {
          unawaited(_loadRecommendationsIfEligible(forceRefresh: true));
        }
        return;
      }

      // Standard remote playlist
      await MetadataRevalidator.revalidate<GenericPlaylist>(
        token: _revalidationToken,
        loadCache: () => metadataManager.getCachedFullPlaylist(
          widget.id,
          source: widget.source,
        ),
        fetchRemote: () => metadataManager.fetchFullPlaylistWithTracks(
          widget.id,
          source: widget.source,
        ),
        hasChanged: (curr, fresh) =>
            MetadataDiff.hasPlaylistChanged(curr, fresh),
        onData: (playlist, {required fromCache}) {
          if (!mounted) return;
          _playlist = playlist;
          _rebuildIndices();
          setState(() => _isLoading = false);
        },
        onRefreshing: (refreshing) {
          if (mounted && _isRefreshing != refreshing) {
            setState(() => _isRefreshing = refreshing);
          }
        },
        onError: (e) {
          if (mounted && _playlist == null) {
            context.showErrorAlert('Failed to load playlist: $e');
          }
        },
      );
      if (mounted && !_revalidationToken.isCancelled) {
        unawaited(_loadRecommendationsIfEligible(forceRefresh: true));
      }
    } else {
      // Album
      await MetadataRevalidator.revalidate<GenericAlbum>(
        token: _revalidationToken,
        loadCache: () => metadataManager.getCachedFullAlbum(
          widget.id,
          source: widget.source,
        ),
        fetchRemote: () => metadataManager.fetchFullAlbumWithTracks(
          widget.id,
          source: widget.source,
        ),
        hasChanged: (curr, fresh) => MetadataDiff.hasAlbumChanged(curr, fresh),
        onData: (album, {required fromCache}) {
          if (!mounted) return;
          _album = album;
          _rebuildIndices();
          setState(() => _isLoading = false);
        },
        onRefreshing: (refreshing) {
          if (mounted && _isRefreshing != refreshing) {
            setState(() => _isRefreshing = refreshing);
          }
        },
        onError: (e) {
          if (mounted && _album == null) {
            context.showErrorAlert('Failed to load album: $e');
          }
        },
      );
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
      source: 'spotify',
      title: likedSongsTitle,
      thumbnailUrl: '',
      author: GenericSimpleUser(
        id: 'liked_songs_user',
        source: 'spotify',
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
        final metadataManager = context.read<MetadataManager>();
        return items
            .where((item) => metadataManager.isTrackLiked(item.id))
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
        case ListSortMethod.position:
          compare = a.compareTo(b);
          break;
        case ListSortMethod.title:
          compare = _getTitle(items[a]).compareTo(_getTitle(items[b]));
          break;
        case ListSortMethod.author:
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
        case ListSortMethod.album:
          compare = _getAlbumTitle(
            items[a],
          ).compareTo(_getAlbumTitle(items[b]));
          break;
        case ListSortMethod.addedAt:
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
        case ListSortMethod.duration:
          compare = _getDuration(items[a]).compareTo(_getDuration(items[b]));
          break;
        case ListSortMethod.source:
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

  void _sortBy(ListSortMethod method, {bool? ascending}) {
    if (ascending != null) {
      _ascending = ascending;
      _sortMethod = method;
    } else if (method == _sortMethod) {
      if (_ascending) {
        _ascending = false;
      } else {
        _sortMethod = ListSortMethod.position;
        _ascending = true;
      }
    } else {
      _sortMethod = method;
      _ascending = true;
    }
    setState(_rebuildIndices);
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

  int _getDuration(_ListItem item) {
    if (item is GenericSong) return item.durationSecs;
    if (item is PlaylistItem) return item.durationSecs;
    return 0;
  }

  DateTime? _getAddedAt(_ListItem item) {
    if (item is PlaylistItem) return item.addedAt;
    return null;
  }

  String _getSource(_ListItem item) {
    if (item is GenericSong) return item.source;
    if (item is PlaylistItem) return item.source;
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
      source: 'spotify',
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
        source: contextSource ?? 'spotify',
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
        source: contextSource ?? 'spotify',
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
  /// with — "this playlist" / "this album". Passed to every [TrackRow] so
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
      source: contextSource ?? 'spotify',
    );
  }

  bool _isCurrentListActive(global_audio_player.WispAudioHandler player) {
    if (player.currentTrack == null) return false;
    final playerContext = player.playbackContext;
    return playerContext != null && playerContext.matches(_viewContext);
  }

  void _toggleListShuffle(global_audio_player.WispAudioHandler player) {
    if (_isCurrentListActive(player)) {
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
      context.showInfoAlert('All tracks are already cached');
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
          GenericTextButton(
            onPressed: () => Navigator.pop(context, false),
            foregroundColor: Colors.grey[400],
            child: const Text('Cancel'),
          ),
          GenericElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
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

        context.showSuccessAlert(message);
      }
    }
  }

  Future<void> _appendTracksToQueue(
    List<GenericSong> tracks, {
    required String contextType,
    required String contextName,
    String? contextSource,
  }) async {
    if (tracks.isEmpty) return;

    final player = context.read<global_audio_player.WispAudioHandler>();
    final mergedQueue = List<GenericSong>.from(player.queueTracks);
    final seen = mergedQueue
        .map((track) => '${track.source}:${track.id}')
        .toSet();

    var addedCount = 0;
    for (final track in tracks) {
      final key = '${track.source}:${track.id}';
      if (seen.add(key)) {
        mergedQueue.add(track);
        addedCount += 1;
      }
    }

    if (addedCount == 0) {
      context.showInfoAlert('All tracks are already in queue');
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
        source: contextSource ?? 'spotify',
      ),
      shuffleEnabled: player.shuffleEnabled,
      originalQueue: player.shuffleEnabled
          ? List<GenericSong>.from(player.originalQueueTracks)
          : null,
    );

    if (!mounted) return;
    context.showSuccessAlert(
      'Added $addedCount track${addedCount == 1 ? '' : 's'} to queue',
    );
  }



  int _totalDurationSecs() {
    return _items.fold<int>(0, (sum, item) => sum + _getDuration(item));
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

  bool _shouldShowRecommendations() {
    if (!mounted || _revalidationToken.isCancelled) return false;
    if (widget.type != SharedListType.playlist) return false;
    if (isLikedSongsPlaylistId(widget.id)) return false;
    if (_playlist == null) return false;
    if (_playlist!.source == 'local') return false;
    if (_localPlaylists.isLocalPlaylistId(widget.id)) return false;
    final supportsRecs = _metadataManager.hasCapability(
      MetadataCapability.recommendations,
      source: _playlist!.source,
    );
    if (!supportsRecs) return false;
    return _playlist!.id.trim().isNotEmpty;
  }

  void _clearRecommendationsState() {
    _recommendedSongs = [];
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
    if (!mounted || _revalidationToken.isCancelled) return;
    if (!_shouldShowRecommendations()) {
      if (!mounted) {
        _clearRecommendationsState();
        return;
      }
      _safeSetState(_clearRecommendationsState);
      return;
    }

    if (_isLoadingRecommendations) return;
    if (!forceRefresh && _recommendedSongs.isNotEmpty) return;

    final playlistID = _playlist?.id ?? widget.id;
    if (playlistID.trim().isEmpty) return;

    if (markCurrentAsSkipped) {
      _markCurrentRecommendationsAsSkipped();
    }

    if (!mounted || _revalidationToken.isCancelled) return;
    _safeSetState(() {
      _isLoadingRecommendations = true;
    });

    try {
      final recommendations = await _metadataManager.getRecommended(
        playlistID,
        _skippedRecommendationTrackIDs,
        numResults: 20,
        source: _playlist?.source,
      );
      if (!mounted || _revalidationToken.isCancelled) {
        _recommendedSongs = recommendations.take(10).toList();
        _isLoadingRecommendations = false;
        return;
      }
      _safeSetState(() {
        _recommendedSongs = recommendations.take(10).toList();
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      if (!mounted || _revalidationToken.isCancelled) {
        _isLoadingRecommendations = false;
        return;
      }
      _safeSetState(() {
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

  Future<void> _addRecommendedTrack(GenericSong song) async {
    final playlist = _playlist;
    if (playlist == null || song.id.trim().isEmpty) return;
    if (_addingRecommendationTrackIDs.contains(song.id)) return;
    if (_addedRecommendationTrackIDs.contains(song.id)) return;

    final currentSongs = List<PlaylistItem>.from(playlist.songs ?? const []);
    final newPlaylistItem = PlaylistItem(
      id: song.id,
      source: song.source,
      title: song.title,
      artists: song.artists,
      thumbnailUrl: song.thumbnailUrl,
      explicit: song.explicit,
      album: song.album,
      durationSecs: song.durationSecs,
      addedAt: DateTime.now(),
      trackNumber: currentSongs.length + 1,
    );
    currentSongs.add(newPlaylistItem);

    _safeSetState(() {
      _addingRecommendationTrackIDs.add(song.id);
      _playlist = playlist.copyWith(
        songs: currentSongs,
        total: (playlist.total != null)
            ? playlist.total! + 1
            : currentSongs.length,
        durationSecs:
            currentSongs.fold<int>(0, (acc, s) => acc + s.durationSecs),
      );
      _rebuildIndices();
    });

    final local = context.read<LocalPlaylistState>();
    final isLocal = local.isLocalPlaylistId(playlist.id);

    try {
      if (isLocal) {
        await local.addTrackFromSong(playlist.id, song);
      } else {
        await _metadataManager.addTracksToPlaylist(
          playlist.id,
          [song.id],
          source: playlist.source,
        );
        if (mounted) {
          context
              .read<LibraryState>()
              .updatePlaylistSongs(playlist.id, currentSongs);
        }
      }
      if (!mounted) return;
      _safeSetState(() {
        _addingRecommendationTrackIDs.remove(song.id);
        _addedRecommendationTrackIDs.add(song.id);
      });
      context.showSuccessAlert('Added to playlist');
    } catch (e) {
      if (!mounted) return;
      _safeSetState(() {
        _addingRecommendationTrackIDs.remove(song.id);
        _playlist = playlist;
        _rebuildIndices();
      });
      context.showErrorAlert('Failed to add track: $e');
    }
  }

  bool get _isListLiked {
    if (widget.type == SharedListType.playlist) {
      return isLikedSongsPlaylistId(widget.id);
    }
    final library = context.read<LibraryState>();
    return library.isAlbumSaved(widget.id);
  }

  void _toggleTrackLike(GenericSong song) {
    if (_metadataManager.isTrackLiked(song.id)) {
      unawaited(_metadataManager.unlikeTrack(song, source: song.source));
    } else {
      unawaited(_metadataManager.likeTrack(song, source: song.source));
    }
  }

  void _toggleLikeList() {
    if (widget.type == SharedListType.album) {
      final library = context.read<LibraryState>();
      final isSaved = library.isAlbumSaved(widget.id);
      unawaited(_toggleSaveAlbum(isSaved));
    }
  }

  void _handlePlayAll() {
    if (_items.isEmpty) return;
    final player = context.read<global_audio_player.WispAudioHandler>();
    if (_isCurrentListActive(player)) {
      _toggleCurrentTrackPlayback(player);
    } else {
      _playFromStart();
    }
  }

  void _handleShuffle() {
    if (_items.isEmpty) return;
    final player = context.read<global_audio_player.WispAudioHandler>();
    if (_isCurrentListActive(player)) {
      _toggleListShuffle(player);
    } else {
      _playFromStart(shuffle: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localPlaylists = context.watch<LocalPlaylistState>();
    final isLocal = widget.type == SharedListType.playlist &&
        !isLikedSongsPlaylistId(widget.id) &&
        localPlaylists.isLocalPlaylistId(widget.id);

    final metadataManager = context.watch<MetadataManager>();
    if (!isLocal && !metadataManager.hasEnabledProviders) {
      return const ProviderDisabledState(message: 'No metadata provider is enabled.');
    }
    final preferences = context.watch<PreferencesProvider>();
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

    final subtitleArtists = widget.type == SharedListType.album
        ? _album?.artists
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

    final showLoadingSpinner =
        _isLoading && _playlist == null && _album == null;
    Widget content = showLoadingSpinner
        ? const Center(child: CircularProgressIndicator())
        : _buildListContentByStyle(
            style: style,
            title: title,
            subtitle: subtitle,
            subtitleUser: subtitleUser,
            subtitleArtists: subtitleArtists,
            imageUrl: imageUrl,
            subtitleImageUrl: subtitleImageUrl,
            total: total,
            isDesktop: isDesktop,
            description: description,
          );

    final wrappedContent = Stack(
      children: [
        content,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _isRefreshing && !showLoadingSpinner ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: isDesktop ? Colors.transparent : null,
      body: wrappedContent,
    );
  }

  Widget _buildListContentByStyle({
    required AppStyle style,
    required String title,
    required String? subtitle,
    required GenericSimpleUser? subtitleUser,
    required List<GenericSimpleArtist>? subtitleArtists,
    required String? subtitleImageUrl,
    required String imageUrl,
    required int total,
    required bool isDesktop,
    required String? description,
  }) {
    final totalDurationSecs = _totalDurationSecs();
    final isLiked = _isListLiked;
    final showRecs = _shouldShowRecommendations();
    final recSongs = _recommendedSongs.map(_toGenericSong).toList();
    final songsList = _items.map(_toGenericSong).toList();
    final datesAdded = _items.map(_getAddedAt).toList();
    final scrollController =
        isDesktop ? _desktopScrollController : _mobileScrollController;

    switch (style) {
      case AppStyle.Spotify:
        return isDesktop
            ? DesktopSpotifyListView(
                id: widget.id,
                type: widget.type,
                title: title,
                subtitle: subtitle,
                subtitleUser: subtitleUser,
                subtitleArtists: subtitleArtists,
                imageUrl: imageUrl,
                subtitleImageUrl: subtitleImageUrl,
                description: description,
                totalTracks: total,
                totalDurationSecs: totalDurationSecs,
                isLiked: isLiked,
                isLoading: _isLoading,
                viewContext: _viewContext,
                songs: songsList,
                datesAdded: datesAdded,
                sortedIndices: _sortedIndices,
                sortMethod: _sortMethod,
                sortAscending: _ascending,
                showRecommendations: showRecs,
                recommendedSongs: recSongs,
                isLoadingRecommendations: _isLoadingRecommendations,
                addingRecommendationTrackIDs: _addingRecommendationTrackIDs,
                addedRecommendationTrackIDs: _addedRecommendationTrackIDs,
                onPlayAll: _handlePlayAll,
                onShuffle: _handleShuffle,
                onToggleLoop: () => context.read<global_audio_player.WispAudioHandler>().toggleRepeat(),
                onDownloadAll: _downloadAll,
                onToggleLike: _toggleLikeList,
                onContextMenu: (ctx, pos) => _showListContextMenu(anchorContext: ctx, globalPosition: pos),
                onPlayTrack: _playQueueAt,
                onTrackToggleLike: _toggleTrackLike,
                onTrackContextMenu: (ctx, song, pos) => _showSongContextMenu(song, anchorContext: ctx, globalPosition: pos),
                onSort: _sortBy,
                onSearchQueryChanged: _handleSearchChanged,
                onOpenAlbum: _openAlbum,
                onOpenArtist: _openArtist,
                onAddRecommendedTrack: _addRecommendedTrack,
                onRefreshRecommendations: _refreshRecommendations,
                onOpenUser: _openUser,
                scrollController: scrollController,
              )
            : MobileSpotifyListView(
                id: widget.id,
                type: widget.type,
                title: title,
                subtitle: subtitle,
                subtitleUser: subtitleUser,
                imageUrl: imageUrl,
                subtitleImageUrl: subtitleImageUrl,
                description: description,
                totalTracks: total,
                totalDurationSecs: totalDurationSecs,
                isLiked: isLiked,
                isLoading: _isLoading,
                viewContext: _viewContext,
                songs: songsList,
                sortedIndices: _sortedIndices,
                sortMethod: _sortMethod,
                sortAscending: _ascending,
                showRecommendations: showRecs,
                recommendedSongs: recSongs,
                isLoadingRecommendations: _isLoadingRecommendations,
                addingRecommendationTrackIDs: _addingRecommendationTrackIDs,
                addedRecommendationTrackIDs: _addedRecommendationTrackIDs,
                onPlayAll: _handlePlayAll,
                onShuffle: _handleShuffle,
                onToggleLike: _toggleLikeList,
                onContextMenu: (ctx, pos) => _showListContextMenu(anchorContext: ctx, globalPosition: pos),
                onPlayTrack: _playQueueAt,
                onTrackToggleLike: _toggleTrackLike,
                onTrackContextMenu: (ctx, song, pos) => _showSongContextMenu(song, anchorContext: ctx, globalPosition: pos),
                onSort: _sortBy,
                onAddRecommendedTrack: _addRecommendedTrack,
                onRefreshRecommendations: _refreshRecommendations,
                onOpenAlbum: _openAlbum,
                onOpenArtist: _openArtist,
                onOpenUser: _openUser,
                scrollController: scrollController,
              );
      case AppStyle.AppleMusic:
        return isDesktop
            ? DesktopAppleMusicListView(
                id: widget.id,
                type: widget.type,
                title: title,
                subtitle: subtitle,
                subtitleUser: subtitleUser,
                subtitleArtists: subtitleArtists,
                imageUrl: imageUrl,
                subtitleImageUrl: subtitleImageUrl,
                description: description,
                totalTracks: total,
                totalDurationSecs: totalDurationSecs,
                isLiked: isLiked,
                isLoading: _isLoading,
                viewContext: _viewContext,
                songs: songsList,
                datesAdded: datesAdded,
                sortedIndices: _sortedIndices,
                sortMethod: _sortMethod,
                sortAscending: _ascending,
                showRecommendations: showRecs,
                recommendedSongs: recSongs,
                isLoadingRecommendations: _isLoadingRecommendations,
                addingRecommendationTrackIDs: _addingRecommendationTrackIDs,
                addedRecommendationTrackIDs: _addedRecommendationTrackIDs,
                onPlayAll: _handlePlayAll,
                onShuffle: _handleShuffle,
                onToggleLoop: () => context.read<global_audio_player.WispAudioHandler>().toggleRepeat(),
                onDownloadAll: _downloadAll,
                onToggleLike: _toggleLikeList,
                onContextMenu: (ctx, pos) => _showListContextMenu(anchorContext: ctx, globalPosition: pos),
                onPlayTrack: _playQueueAt,
                onTrackToggleLike: _toggleTrackLike,
                onTrackContextMenu: (ctx, song, pos) => _showSongContextMenu(song, anchorContext: ctx, globalPosition: pos),
                onSort: _sortBy,
                onSearchQueryChanged: _handleSearchChanged,
                onOpenAlbum: _openAlbum,
                onOpenArtist: _openArtist,
                onAddRecommendedTrack: _addRecommendedTrack,
                onRefreshRecommendations: _refreshRecommendations,
                onOpenUser: _openUser,
                scrollController: scrollController,
              )
            : MobileAppleMusicListView(
                id: widget.id,
                type: widget.type,
                title: title,
                subtitle: subtitle,
                subtitleUser: subtitleUser,
                imageUrl: imageUrl,
                subtitleImageUrl: subtitleImageUrl,
                description: description,
                totalTracks: total,
                totalDurationSecs: totalDurationSecs,
                isLiked: isLiked,
                isLoading: _isLoading,
                viewContext: _viewContext,
                songs: songsList,
                datesAdded: datesAdded,
                sortedIndices: _sortedIndices,
                sortMethod: _sortMethod,
                sortAscending: _ascending,
                showRecommendations: showRecs,
                recommendedSongs: recSongs,
                isLoadingRecommendations: _isLoadingRecommendations,
                addingRecommendationTrackIDs: _addingRecommendationTrackIDs,
                addedRecommendationTrackIDs: _addedRecommendationTrackIDs,
                onPlayAll: _handlePlayAll,
                onShuffle: _handleShuffle,
                onToggleLoop: () => context.read<global_audio_player.WispAudioHandler>().toggleRepeat(),
                onDownloadAll: _downloadAll,
                onToggleLike: _toggleLikeList,
                onContextMenu: (ctx, pos) => _showListContextMenu(anchorContext: ctx, globalPosition: pos),
                onPlayTrack: _playQueueAt,
                onTrackToggleLike: _toggleTrackLike,
                onTrackContextMenu: (ctx, song, pos) => _showSongContextMenu(song, anchorContext: ctx, globalPosition: pos),
                onSort: _sortBy,
                onSearchQueryChanged: _handleSearchChanged,
                onOpenAlbum: _openAlbum,
                onOpenArtist: _openArtist,
                onAddRecommendedTrack: _addRecommendedTrack,
                onRefreshRecommendations: _refreshRecommendations,
                onOpenUser: _openUser,
                scrollController: scrollController,
              );
      case AppStyle.Original:
        return isDesktop
            ? DesktopOriginalListView(
                id: widget.id,
                type: widget.type,
                title: title,
                subtitle: subtitle,
                subtitleUser: subtitleUser,
                subtitleArtists: subtitleArtists,
                imageUrl: imageUrl,
                subtitleImageUrl: subtitleImageUrl,
                description: description,
                totalTracks: total,
                totalDurationSecs: totalDurationSecs,
                isLiked: isLiked,
                isLoading: _isLoading,
                viewContext: _viewContext,
                songs: songsList,
                datesAdded: datesAdded,
                sortedIndices: _sortedIndices,
                sortMethod: _sortMethod,
                sortAscending: _ascending,
                showRecommendations: showRecs,
                recommendedSongs: recSongs,
                isLoadingRecommendations: _isLoadingRecommendations,
                addingRecommendationTrackIDs: _addingRecommendationTrackIDs,
                addedRecommendationTrackIDs: _addedRecommendationTrackIDs,
                onPlayAll: _handlePlayAll,
                onShuffle: _handleShuffle,
                onToggleLoop: () => context.read<global_audio_player.WispAudioHandler>().toggleRepeat(),
                onDownloadAll: _downloadAll,
                onToggleLike: _toggleLikeList,
                onContextMenu: (ctx, pos) => _showListContextMenu(anchorContext: ctx, globalPosition: pos),
                onPlayTrack: _playQueueAt,
                onTrackToggleLike: _toggleTrackLike,
                onTrackContextMenu: (ctx, song, pos) => _showSongContextMenu(song, anchorContext: ctx, globalPosition: pos),
                onSort: _sortBy,
                onSearchQueryChanged: _handleSearchChanged,
                onAddRecommendedTrack: _addRecommendedTrack,
                onRefreshRecommendations: _refreshRecommendations,
                onOpenAlbum: _openAlbum,
                onOpenArtist: _openArtist,
                onOpenUser: _openUser,
                scrollController: scrollController,
              )
            : MobileOriginalListView(
                id: widget.id,
                type: widget.type,
                title: title,
                subtitle: subtitle,
                subtitleUser: subtitleUser,
                imageUrl: imageUrl,
                subtitleImageUrl: subtitleImageUrl,
                description: description,
                totalTracks: total,
                totalDurationSecs: totalDurationSecs,
                isLiked: isLiked,
                isLoading: _isLoading,
                viewContext: _viewContext,
                songs: songsList,
                sortedIndices: _sortedIndices,
                sortMethod: _sortMethod,
                sortAscending: _ascending,
                showRecommendations: showRecs,
                recommendedSongs: recSongs,
                isLoadingRecommendations: _isLoadingRecommendations,
                addingRecommendationTrackIDs: _addingRecommendationTrackIDs,
                addedRecommendationTrackIDs: _addedRecommendationTrackIDs,
                onPlayAll: _handlePlayAll,
                onShuffle: _handleShuffle,
                onToggleLike: _toggleLikeList,
                onContextMenu: (ctx, pos) => _showListContextMenu(anchorContext: ctx, globalPosition: pos),
                onPlayTrack: _playQueueAt,
                onTrackToggleLike: _toggleTrackLike,
                onTrackContextMenu: (ctx, song, pos) => _showSongContextMenu(song, anchorContext: ctx, globalPosition: pos),
                onSort: _sortBy,
                onAddRecommendedTrack: _addRecommendedTrack,
                onRefreshRecommendations: _refreshRecommendations,
                onOpenAlbum: _openAlbum,
                onOpenArtist: _openArtist,
                onOpenUser: _openUser,
                scrollController: scrollController,
              );
    }
  }

  void _handleSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _rebuildIndices();
    });
  }

  void _openAlbum(GenericSimpleAlbum? album) {
    if (album == null) return;
    AppNavigation.instance.openSharedList(
      context,
      id: album.id,
      type: SharedListType.album,
      initialTitle: album.title,
    );
  }

  void _openArtist(GenericSimpleArtist artist) {
    AppNavigation.instance.openArtist(
      context,
      artistId: artist.id,
      initialArtist: artist,
    );
  }

  Rect? _anchorRectFromContext(BuildContext? anchorContext) {
    if (anchorContext == null) return null;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox;
    final renderObject = anchorContext.findRenderObject();
    if (renderObject is! RenderBox) return null;
    return Rect.fromPoints(
      renderObject.localToGlobal(Offset.zero, ancestor: overlay),
      renderObject.localToGlobal(renderObject.size.bottomRight(Offset.zero), ancestor: overlay),
    );
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
            GenericTextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            GenericFilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;
    context.showInfoAlert('Delete playlist placeholder');
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
          context.showInfoAlert('Download metadata placeholder');
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
          id: 'add-tastes',
          label: 'Add to Tastes',
          icon: Icons.auto_awesome,
          onSelected: (_) async {
            final tracks = listSongs.isNotEmpty ? listSongs : _buildQueueSongs();
            if (tracks.isEmpty) {
              if (!mounted) return;
              context.showWarningAlert('No tracks available in playlist');
              return;
            }
            await ListeningHabitsService.instance.enqueueTasteIngestion(
              tracks,
              sourceTitle: title,
            );
            if (!mounted) return;
            context.showInfoAlert(
              'Adding ${tracks.length} songs to your tastes in the background...',
            );
          },
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
        if (context.read<PreferencesProvider>().debugModeEnabled && _playlist != null)
          ContextMenuAction(
            id: 'inspect-element',
            label: 'Inspect Element',
            icon: Icons.code,
            onSelected: (_) => InspectDialog.show(
              context,
              data: _playlist!.toJson(),
              title: 'Inspect Playlist',
            ),
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
        id: 'add-tastes',
        label: 'Add to Tastes',
        icon: Icons.auto_awesome,
        onSelected: (_) async {
          final tracks = listSongs.isNotEmpty ? listSongs : _buildQueueSongs();
          if (tracks.isEmpty) {
            if (!mounted) return;
            context.showWarningAlert('No tracks available in album');
            return;
          }
          await ListeningHabitsService.instance.enqueueTasteIngestion(
            tracks,
            sourceTitle: title,
          );
          if (!mounted) return;
          context.showInfoAlert(
            'Adding ${tracks.length} songs to your tastes in the background...',
          );
        },
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
      if (context.read<PreferencesProvider>().debugModeEnabled && album != null)
        ContextMenuAction(
          id: 'inspect-element',
          label: 'Inspect Element',
          icon: Icons.code,
          onSelected: (_) => InspectDialog.show(
            context,
            data: album.toJson(),
            title: 'Inspect Album',
          ),
        ),
    ];
  }

  Future<void> _showSongContextMenu(
    GenericSong song, {
    Offset? globalPosition,
    BuildContext? anchorContext,
  }) {
    final isPlaylist =
        widget.type == SharedListType.playlist && !isLikedSongsPlaylistId(widget.id);
    final localPlaylists = context.read<LocalPlaylistState>();
    final metadataManager = context.read<MetadataManager>();
    final isLocal = localPlaylists.isLocalPlaylistId(widget.id);
    final userDisplayName = metadataManager.userDisplayName ?? '';
    final isOwner = isLocal ||
        (userDisplayName.isNotEmpty &&
            _playlist != null &&
            _playlist!.author.displayName.trim().toLowerCase() ==
                userDisplayName.trim().toLowerCase());

    final additionalActions = <ContextMenuAction>[];
    if (isPlaylist && isOwner) {
      additionalActions.add(
        ContextMenuAction(
          id: 'remove-from-current-playlist',
          label: 'Remove from this playlist',
          icon: Icons.playlist_remove,
          destructive: true,
          onSelected: (ctx) async {
            await _removeTrackFromCurrentPlaylist(song);
          },
        ),
      );
    }

    return EntityContextMenus.showTrackMenu(
      context,
      track: song,
      globalPosition: globalPosition,
      anchorRect: _anchorRectFromContext(anchorContext),
      additionalActions: additionalActions,
    );
  }

  Future<void> _removeTrackFromCurrentPlaylist(GenericSong song) async {
    final playlist = _playlist;
    if (playlist == null) return;
    final local = context.read<LocalPlaylistState>();
    final isLocal = local.isLocalPlaylistId(playlist.id);

    final cleanSongId =
        song.id.contains(':') ? song.id.split(':').last : song.id;
    final currentSongs = List<PlaylistItem>.from(playlist.songs ?? const []);

    PlaylistItem? targetItem;
    for (final s in currentSongs) {
      final sClean = s.id.contains(':') ? s.id.split(':').last : s.id;
      if (s.id == song.id || sClean == cleanSongId) {
        targetItem = s;
        break;
      }
    }

    currentSongs.removeWhere((s) {
      final sClean = s.id.contains(':') ? s.id.split(':').last : s.id;
      return s.id == song.id || sClean == cleanSongId;
    });

    // Optimistically update UI immediately
    setState(() {
      _playlist = playlist.copyWith(
        songs: currentSongs,
        total: (playlist.total != null && playlist.total! > 0)
            ? playlist.total! - 1
            : currentSongs.length,
        durationSecs:
            currentSongs.fold<int>(0, (acc, s) => acc + s.durationSecs),
      );
      _rebuildIndices();
    });

    try {
      if (isLocal) {
        await local.removeTrack(playlist.id, song.id);
      } else {
        final targetUid = targetItem?.uid;
        final isUid = targetUid != null &&
            RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(targetUid);
        final trackIdOrUid = isUid ? targetUid : song.id;

        await _metadataManager.removeTracksFromPlaylist(
          playlist.id,
          [trackIdOrUid],
          source: playlist.source,
        );
        if (mounted) {
          context
              .read<LibraryState>()
              .updatePlaylistSongs(playlist.id, currentSongs);
        }
      }
      if (mounted) {
        context.showSuccessAlert('Removed from ${playlist.title}');
      }
    } catch (e) {
      if (mounted) {
        // Revert on error
        setState(() {
          _playlist = playlist;
          _rebuildIndices();
        });
        context.showErrorAlert('Failed to remove track: $e');
      }
    }
  }

  void _showShareDialog() {
    final effectiveSource =
        _playlist?.source ?? _album?.source ?? 'spotify';
    final typePath = widget.type == SharedListType.playlist
        ? 'playlist'
        : 'album';
    EntityContextMenus.copyShareUrl(
      context,
      source: effectiveSource,
      type: typePath,
      id: widget.id,
    );
  }

  void _showEditDialog() {
    if (widget.type == SharedListType.playlist && _playlist != null) {
      PlaylistFolderModals.showRenamePlaylistDialog(context, _playlist!);
      return;
    }
    context.showWarningAlert('Edit not available for this item');
  }
}

class ListDetailView extends StatelessWidget {
  final String id;
  final String type;
  final String? source;

  const ListDetailView({
    super.key,
    required this.id,
    required this.type,
    this.source,
  });

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryState>();
    final navState = context.watch<NavigationState>();
    final listType = type.toLowerCase() == 'album'
        ? SharedListType.album
        : SharedListType.playlist;

    return SharedListDetailView(
      key: ValueKey('$listType-$id'),
      id: id,
      type: listType,
      source: source,
      playlists: library.playlists,
      albums: library.albums,
      artists: library.artists,
      initialLibraryView: navState.selectedLibraryView,
      initialNavIndex: navState.selectedNavIndex,
    );
  }
}
