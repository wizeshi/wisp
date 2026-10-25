// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:wisp/core/utils/liked_songs.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/cache_manager.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/models/library_folder.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/services/system/connectivity_service.dart';

/// Lightweight, flattened representation of a playlist's track membership:
/// `{ id: "playlistId", source: "source", tracks: trackIDsList }`.
/// Avoids retaining thousands of full [PlaylistItem] / [GenericSong] objects in RAM.
class LightweightPlaylistTracks {
  final String id;
  final String source;
  final List<String> tracks;
  final Map<String, String> trackUids;

  const LightweightPlaylistTracks({
    required this.id,
    required this.source,
    required this.tracks,
    this.trackUids = const {},
  });

  factory LightweightPlaylistTracks.fromItems({
    required String id,
    required String source,
    required Iterable<PlaylistItem> items,
  }) {
    final trackIds = <String>[];
    final uids = <String, String>{};
    for (final item in items) {
      if (item.id.isEmpty) continue;
      final clean = cleanTrackId(item.id);
      trackIds.add(clean);
      final uid = item.uid;
      if (uid != null && uid.isNotEmpty) {
        uids[clean] = uid;
      }
    }
    return LightweightPlaylistTracks(
      id: id,
      source: source,
      tracks: List.unmodifiable(trackIds),
      trackUids: Map.unmodifiable(uids),
    );
  }

  bool containsTrack(String trackId) {
    if (trackId.isEmpty) return false;
    final clean = cleanTrackId(trackId);
    return tracks.contains(clean) || tracks.contains(trackId);
  }

  String? uidForTrack(String trackId) {
    final clean = cleanTrackId(trackId);
    return trackUids[clean] ?? trackUids[trackId];
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'source': source,
    'tracks': tracks,
  };

  static String cleanTrackId(String id) =>
      id.contains(':') ? id.split(':').last : id;
}

class LibraryState extends ChangeNotifier {
  List<GenericPlaylist> _remotePlaylists = [];
  List<GenericPlaylist> _localPlaylists = [];
  Set<String> _hiddenRemotePlaylistIds = {};
  List<GenericAlbum> _albums = [];
  List<GenericSimpleArtist> _artists = [];
  List<dynamic>? _allOrganized;
  final Map<String, LightweightPlaylistTracks> _playlistTrackIndex = {};

  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isFetchingData = false;
  bool _wasAuthenticated = false;
  bool _hasInitialLoaded = false;

  MetadataManager? _metadataManager;
  LibraryFolderState? _folderState;
  VoidCallback? _authListener;

  List<GenericPlaylist> get playlists => _mergePlaylists();
  List<GenericAlbum> get albums => _albums;
  List<GenericSimpleArtist> get artists => _artists;
  List<dynamic>? get allOrganized => _allOrganized;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;

  void bind({
    required MetadataManager metadataManager,
    required LocalPlaylistState localPlaylistState,
    required LibraryFolderState folderState,
  }) {
    _folderState = folderState;
    setLocalPlaylists(localPlaylistState.genericPlaylists);
    setHiddenRemotePlaylistIds(localPlaylistState.hiddenProviderPlaylistIds);

    if (_metadataManager != metadataManager) {
      if (_authListener != null) {
        _metadataManager?.removeListener(_authListener!);
      }
      _metadataManager = metadataManager;
      _wasAuthenticated = metadataManager.isAuthenticated;
      _authListener = _handleAuthChange;
      metadataManager.addListener(_authListener!);

      if (metadataManager.isAuthenticated && !_hasInitialLoaded) {
        _hasInitialLoaded = true;
        Future.microtask(() => loadLibrary());
      }
    } else if (metadataManager.isAuthenticated && !_hasInitialLoaded) {
      _hasInitialLoaded = true;
      Future.microtask(() => loadLibrary());
    }
  }

  void _handleAuthChange() {
    final manager = _metadataManager;
    if (manager == null) return;
    final isAuthenticated = manager.isAuthenticated;
    if (isAuthenticated && !_wasAuthenticated) {
      _wasAuthenticated = true;
      _hasInitialLoaded = true;
      loadLibrary();
    } else if (!isAuthenticated && _wasAuthenticated) {
      _wasAuthenticated = false;
      _hasInitialLoaded = false;
      clear();
    }
  }

  Future<void> refresh() {
    return loadLibrary(policy: MetadataFetchPolicy.refreshAlways);
  }

  Future<void> loadLibrary({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (_isFetchingData) return;
    final manager = _metadataManager;
    if (manager == null) return;

    if (!manager.hasEnabledProviders ||
        !manager.hasCapability(MetadataCapability.library)) {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
      return;
    }

    _isFetchingData = true;
    final hasData = _remotePlaylists.isNotEmpty ||
        _albums.isNotEmpty ||
        _artists.isNotEmpty;

    if (!hasData) {
      _isLoading = true;
    } else {
      _isRefreshing = true;
    }
    notifyListeners();

    try {
      if (!manager.isAuthenticated) {
        await manager.checkAuthState();
      }

      if (!manager.isAuthenticated) {
        clear();
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
        return;
      }

      // Quick offline/cache-first check if state is currently empty
      if (!hasData) {
        try {
          final cachedLib = await manager.getUserLibrary(
            policy: MetadataFetchPolicy.cacheFirst,
          );
          if (cachedLib != null) {
            final initialLikedPlaylist = buildLikedSongsPlaylist(
              userDisplayName: manager.userDisplayName,
              total: manager.likedTracksTotalCount,
            );
            final intPlaylists = cachedLib.saved_playlists;
            final plWithLiked = [
              initialLikedPlaylist,
              ...intPlaylists
                  .where((p) => p.id != likedSongsPlaylistId)
                  .map(_indexAndStripSongs),
            ];
            _remotePlaylists = plWithLiked;
            _albums = cachedLib.saved_albums;
            _artists = cachedLib.saved_artists
                .map(
                  (a) => GenericSimpleArtist(
                    id: a.id,
                    source: a.source,
                    name: a.name,
                    thumbnailUrl: a.thumbnailUrl,
                  ),
                )
                .toList();
            _allOrganized = [
              initialLikedPlaylist,
              ...cachedLib.all_organized?.map(
                    (item) => item is GenericPlaylist
                        ? _indexAndStripSongs(item)
                        : item,
                  ) ??
                  [],
            ];
            _isLoading = false;
            notifyListeners();
          }
        } catch (_) {}
      }

      final isOnline = await ConnectivityService.instance.checkOnline();
      if (!isOnline) {
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
        return;
      }

      await manager.fetchUserProfile();

      List<PlaylistItem> cachedLiked = const [];
      if (policy == MetadataFetchPolicy.refreshAlways) {
        cachedLiked = await manager.getUserSavedTracks(
          limit: 50,
          offset: 0,
          policy: policy,
        );
        manager.setLikedTracksFromItems(cachedLiked);
      } else {
        cachedLiked = await manager.getUserSavedTracks(
          limit: 50,
          offset: 0,
          policy: MetadataFetchPolicy.refreshIfExpired,
        );
        if (cachedLiked.isNotEmpty) {
          manager.setLikedTracksFromItems(cachedLiked);
        }
      }

      final likedPlaylist = buildLikedSongsPlaylist(
        userDisplayName: manager.userDisplayName,
        total: manager.likedTracksTotalCount ?? cachedLiked.length,
      );

      final userLibrary = await manager.getUserLibrary(
            policy: MetadataFetchPolicy.refreshAlways,
          ) ??
          const GenericLibrary(
            saved_albums: [],
            saved_playlists: [],
            saved_artists: [],
          );

      final folderState = _folderState;
      if (folderState != null) {
        try {
          final all = userLibrary.all_organized;
          if (all != null && all.isNotEmpty) {
            final remoteFolders = <PlaylistFolder>[];
            for (final e in all) {
              if (e is Map<String, dynamic>) {
                final t = e['__typename'] as String? ?? e['type'] as String?;
                if (t == 'Folder' || t == 'folder') {
                  final uri = e['uri'] as String? ?? e['id'] as String? ?? '';
                  final id = uri.isNotEmpty ? uri : (e['id'] as String? ?? '');
                  final name = e['name'] as String? ?? '';
                  final isPinned = e['is_pinned'] as bool? ?? false;
                  remoteFolders.add(
                    PlaylistFolder(
                      id: id,
                      title: name,
                      isPinned: isPinned,
                      createdAt: DateTime.now(),
                    ),
                  );
                }
              }
            }
            if (remoteFolders.isNotEmpty) {
              await folderState.importRemoteFolders(remoteFolders);
            }
          }

          if (userLibrary.folderAssignments != null) {
            final remotePlaylistIds =
                userLibrary.saved_playlists.map((p) => p.id).toSet();
            await folderState.syncRemoteAssignments(
              remoteAssignments: userLibrary.folderAssignments!,
              remotePlaylistIds: remotePlaylistIds,
            );
          }
        } catch (e) {
          logger.w('[LibraryState] Failed to process remote folders: $e');
        }
      }

      final internalPlaylists = userLibrary.saved_playlists;
      final playlistsWithLiked = [
        likedPlaylist,
        ...internalPlaylists
            .where((p) => p.id != likedSongsPlaylistId)
            .map(_indexAndStripSongs),
      ];

      final allWithLiked = [
        likedPlaylist,
        ...userLibrary.all_organized?.map(
              (item) =>
                  item is GenericPlaylist ? _indexAndStripSongs(item) : item,
            ) ??
            [],
      ];

      _remotePlaylists = playlistsWithLiked;
      _albums = userLibrary.saved_albums;
      _artists = userLibrary.saved_artists
          .map(
            (a) => GenericSimpleArtist(
              id: a.id,
              source: a.source,
              name: a.name,
              thumbnailUrl: a.thumbnailUrl,
            ),
          )
          .toList();
      _allOrganized = allWithLiked;

      folderState?.syncPlaylists(playlists);
    } catch (e) {
      logger.e('[LibraryState] Failed to load library data', error: e);
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      _isFetchingData = false;
      notifyListeners();
      unawaited(_hydrateEditablePlaylistTracks());
    }
  }

  bool isArtistFollowed(String artistId) {
    return _artists.any((artist) => artist.id == artistId);
  }

  bool isAlbumSaved(String albumId) {
    return _albums.any((album) => album.id == albumId);
  }

  void setLibrary({
    required List<GenericPlaylist> playlists,
    required List<GenericAlbum> albums,
    required List<GenericSimpleArtist> artists,
    List<dynamic>? allOrganized,
  }) {
    _remotePlaylists = playlists.map(_indexAndStripSongs).toList();
    _albums = albums;
    _artists = artists;
    _allOrganized = allOrganized
        ?.map((item) => item is GenericPlaylist ? _indexAndStripSongs(item) : item)
        .toList();
    notifyListeners();
  }

  void setLocalPlaylists(List<GenericPlaylist> playlists) {
    _localPlaylists = playlists;
    notifyListeners();
  }

  void setHiddenRemotePlaylistIds(Set<String> ids) {
    _hiddenRemotePlaylistIds = ids;
    notifyListeners();
  }

  void addArtist(GenericSimpleArtist artist) {
    if (isArtistFollowed(artist.id)) return;
    _artists = [..._artists, artist];
    notifyListeners();
  }

  void removeArtist(String artistId) {
    final next = _artists.where((artist) => artist.id != artistId).toList();
    if (next.length == _artists.length) return;
    _artists = next;
    notifyListeners();
  }

  void addAlbum(GenericAlbum album) {
    if (isAlbumSaved(album.id)) return;
    _albums = [..._albums, album];
    notifyListeners();
  }

  void removeAlbum(String albumId) {
    final next = _albums.where((album) => album.id != albumId).toList();
    if (next.length == _albums.length) return;
    _albums = next;
    notifyListeners();
  }

  void removePlaylist(String playlistId) {
    _playlistTrackIndex.remove(playlistId);
    _remotePlaylists =
        _remotePlaylists.where((p) => p.id != playlistId).toList();
    if (_allOrganized != null) {
      _allOrganized = _allOrganized!.where((item) {
        if (item is GenericPlaylist && item.id == playlistId) return false;
        if (item is Map<String, dynamic> &&
            (item['id'] == playlistId ||
                item['uri']?.toString().contains(playlistId) == true)) {
          return false;
        }
        return true;
      }).toList();
    }
    notifyListeners();
  }

  /// Returns the flattened track ID index for [playlistId], if hydrated.
  LightweightPlaylistTracks? getPlaylistTrackIndex(String playlistId) {
    return _playlistTrackIndex[playlistId];
  }

  /// Strips heavy [PlaylistItem] lists from [playlist] while indexing its track IDs.
  GenericPlaylist _indexAndStripSongs(GenericPlaylist playlist) {
    final songs = playlist.songs;
    if (songs != null && songs.isNotEmpty) {
      _playlistTrackIndex[playlist.id] = LightweightPlaylistTracks.fromItems(
        id: playlist.id,
        source: playlist.source,
        items: songs,
      );
    }
    if (songs == null) return playlist;
    return GenericPlaylist(
      id: playlist.id,
      source: playlist.source,
      title: playlist.title,
      description: playlist.description,
      thumbnailUrl: playlist.thumbnailUrl,
      author: playlist.author,
      songs: null,
      durationSecs: playlist.durationSecs,
      total: playlist.total ?? songs.length,
      hasMore: playlist.hasMore,
      isPinned: playlist.isPinned,
    );
  }

  void updatePlaylistSongs(String playlistId, List<PlaylistItem> songs) {
    bool changed = false;
    final previousCount = _playlistTrackIndex[playlistId]?.tracks.length;
    final rIdx = _remotePlaylists.indexWhere((p) => p.id == playlistId);
    final source = rIdx != -1 ? _remotePlaylists[rIdx].source : 'spotify';
    _playlistTrackIndex[playlistId] = LightweightPlaylistTracks.fromItems(
      id: playlistId,
      source: source,
      items: songs,
    );

    if (rIdx != -1) {
      final old = _remotePlaylists[rIdx];
      final oldCount = previousCount ?? old.songs?.length ?? songs.length;
      final diff = songs.length - oldCount;
      final newTotal = max(0, (old.total ?? songs.length) + diff);
      _remotePlaylists[rIdx] = _indexAndStripSongs(
        old.copyWith(total: newTotal),
      );
      changed = true;
    }
    final all = _allOrganized;
    if (all != null) {
      for (var i = 0; i < all.length; i++) {
        final item = all[i];
        if (item is GenericPlaylist && item.id == playlistId) {
          final oldCount = previousCount ?? item.songs?.length ?? songs.length;
          final diff = songs.length - oldCount;
          final newTotal = max(0, (item.total ?? songs.length) + diff);
          all[i] = _indexAndStripSongs(item.copyWith(total: newTotal));
          changed = true;
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void addTrackIdToPlaylist(
    String playlistId,
    String trackId, {
    String? source,
    String? uid,
  }) {
    final clean = LightweightPlaylistTracks.cleanTrackId(trackId);
    final existing = _playlistTrackIndex[playlistId];
    if (existing != null && existing.containsTrack(clean)) return;

    final nextTracks = <String>[...?existing?.tracks, clean];
    final nextUids = <String, String>{...?existing?.trackUids};
    if (uid != null && uid.isNotEmpty) {
      nextUids[clean] = uid;
    }
    _playlistTrackIndex[playlistId] = LightweightPlaylistTracks(
      id: playlistId,
      source: source ?? existing?.source ?? 'spotify',
      tracks: List.unmodifiable(nextTracks),
      trackUids: Map.unmodifiable(nextUids),
    );
    _adjustPlaylistTotal(playlistId, 1);
  }

  void removeTrackIdFromPlaylist(String playlistId, String trackId) {
    final clean = LightweightPlaylistTracks.cleanTrackId(trackId);
    final existing = _playlistTrackIndex[playlistId];
    if (existing == null || !existing.containsTrack(clean)) return;

    final nextTracks = existing.tracks
        .where((id) => id != clean && id != trackId)
        .toList(growable: false);
    final nextUids = Map<String, String>.from(existing.trackUids)
      ..remove(clean)
      ..remove(trackId);
    _playlistTrackIndex[playlistId] = LightweightPlaylistTracks(
      id: playlistId,
      source: existing.source,
      tracks: nextTracks,
      trackUids: Map.unmodifiable(nextUids),
    );
    _adjustPlaylistTotal(playlistId, -1);
  }

  void _adjustPlaylistTotal(String playlistId, int delta) {
    bool changed = false;
    final rIdx = _remotePlaylists.indexWhere((p) => p.id == playlistId);
    if (rIdx != -1) {
      final old = _remotePlaylists[rIdx];
      final currentCount = _playlistTrackIndex[playlistId]?.tracks.length ?? 0;
      final newTotal = max(0, (old.total ?? currentCount) + delta);
      _remotePlaylists[rIdx] = old.copyWith(total: newTotal);
      changed = true;
    }
    final all = _allOrganized;
    if (all != null) {
      for (var i = 0; i < all.length; i++) {
        final item = all[i];
        if (item is GenericPlaylist && item.id == playlistId) {
          final currentCount =
              _playlistTrackIndex[playlistId]?.tracks.length ?? 0;
          final newTotal = max(0, (item.total ?? currentCount) + delta);
          all[i] = item.copyWith(total: newTotal);
          changed = true;
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void _updatePlaylistInState(GenericPlaylist updated) {
    final stripped = _indexAndStripSongs(updated);
    bool changed = false;
    final rIdx = _remotePlaylists.indexWhere((p) => p.id == stripped.id);
    if (rIdx != -1) {
      _remotePlaylists[rIdx] = stripped;
      changed = true;
    }
    final all = _allOrganized;
    if (all != null) {
      for (var i = 0; i < all.length; i++) {
        final item = all[i];
        if (item is GenericPlaylist && item.id == stripped.id) {
          all[i] = stripped;
          changed = true;
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> _hydrateEditablePlaylistTracks() async {
    final manager = _metadataManager;
    if (manager == null || !manager.isAuthenticated) return;
    final userDisplayName = manager.userDisplayName?.trim().toLowerCase() ?? '';
    final userId = manager.userId?.trim().toLowerCase() ?? '';
    if (userDisplayName.isEmpty && userId.isEmpty) return;

    final editable = _remotePlaylists.where((p) {
      if (isLikedSongsPlaylistId(p.id)) return false;
      final authorName = p.author.displayName.trim().toLowerCase();
      final authorId = p.author.id.trim().toLowerCase();
      return (userDisplayName.isNotEmpty && authorName == userDisplayName) ||
          (userId.isNotEmpty && authorId == userId);
    }).toList();

    for (final pl in editable) {
      final existingIndex = _playlistTrackIndex[pl.id];
      if (existingIndex != null && existingIndex.tracks.isNotEmpty) continue;
      if (pl.songs != null && pl.songs!.isNotEmpty) {
        _updatePlaylistInState(pl);
        continue;
      }
      try {
        final cached =
            await manager.getCachedFullPlaylist(pl.id, source: pl.source);
        if (cached != null &&
            cached.songs != null &&
            cached.songs!.isNotEmpty) {
          _updatePlaylistInState(cached);
          MetadataCacheStore.instance.evictL1Entity(
            provider: pl.source,
            type: 'full_playlist',
            id: pl.id,
          );
          continue;
        }

        final fetched = await manager.getPlaylistInfo(
          pl.id,
          source: pl.source,
          limit: 100,
          policy: MetadataFetchPolicy.refreshIfExpired,
        );
        if (fetched.songs != null && fetched.songs!.isNotEmpty) {
          _updatePlaylistInState(fetched);
          MetadataCacheStore.instance.evictL1Entity(
            provider: pl.source,
            type: 'playlist',
            id: pl.id,
          );
        }
      } catch (e) {
        logger.d(
          '[LibraryState] Background hydration skipped for ${pl.title}: $e',
        );
      }
    }

    pruneUnusedPlaylists();
  }

  /// Prunes non-library playlists and albums from L1 memory cache and strips
  /// any lingering full song lists on library playlists.
  void pruneUnusedPlaylists({Set<String> activeIds = const {}}) {
    final libraryPlaylistIds = _remotePlaylists.map((p) => p.id).toSet();
    final libraryAlbumIds = _albums.map((a) => a.id).toSet();
    _playlistTrackIndex.removeWhere(
      (id, _) => !libraryPlaylistIds.contains(id) && !activeIds.contains(id),
    );
    MetadataCacheStore.instance.pruneNonLibraryFromL1(
      libraryPlaylistIds: libraryPlaylistIds,
      libraryAlbumIds: libraryAlbumIds,
      activeIds: activeIds,
    );
    AudioCacheManager.instance.pruneInactiveDownloadNotifiers();
  }

  /// Toggle or set playlist pinned state. Optimistically updates locally and
  /// calls Spotify API, reverting on failure.
  Future<bool> togglePlaylistPin(
    GenericPlaylist playlist, {
    bool? pinned,
  }) async {
    final manager = _metadataManager;
    final targetPinned = pinned ?? !playlist.isPinned;
    if (targetPinned == playlist.isPinned) return true;

    final plIndex = _remotePlaylists.indexWhere((p) => p.id == playlist.id);
    if (plIndex >= 0) {
      _remotePlaylists[plIndex] =
          _remotePlaylists[plIndex].copyWith(isPinned: targetPinned);
    }

    if (_allOrganized != null) {
      for (var i = 0; i < _allOrganized!.length; i++) {
        final item = _allOrganized![i];
        if (item is GenericPlaylist && item.id == playlist.id) {
          _allOrganized![i] = item.copyWith(isPinned: targetPinned);
        } else if (item is Map<String, dynamic> &&
            (item['id'] == playlist.id ||
                item['uri']?.toString().contains(playlist.id) == true)) {
          final updated = Map<String, dynamic>.from(item);
          updated['is_pinned'] = targetPinned;
          _allOrganized![i] = updated;
        }
      }
    }

    notifyListeners();

    if (manager != null && manager.isAuthenticated) {
      try {
        final uri = playlist.id.startsWith('spotify:')
            ? playlist.id
            : 'spotify:playlist:${playlist.id}';
        if (targetPinned) {
          await manager.pinLibraryItem(uri: uri);
        } else {
          await manager.unpinLibraryItem(uri: uri);
        }
      } catch (_) {
        if (plIndex >= 0) {
          _remotePlaylists[plIndex] =
              _remotePlaylists[plIndex].copyWith(isPinned: playlist.isPinned);
        }
        if (_allOrganized != null) {
          for (var i = 0; i < _allOrganized!.length; i++) {
            final item = _allOrganized![i];
            if (item is GenericPlaylist && item.id == playlist.id) {
              _allOrganized![i] = item.copyWith(isPinned: playlist.isPinned);
            }
          }
        }
        notifyListeners();
        return false;
      }
    }

    return true;
  }

  void clear() {
    _remotePlaylists = [];
    _localPlaylists = [];
    _albums = [];
    _artists = [];
    _allOrganized = null;
    _playlistTrackIndex.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_authListener != null) {
      _metadataManager?.removeListener(_authListener!);
      _authListener = null;
    }
    super.dispose();
  }

  List<GenericPlaylist> _mergePlaylists() {
    if (_localPlaylists.isEmpty) {
      if (_hiddenRemotePlaylistIds.isEmpty) return _remotePlaylists;
      return _remotePlaylists
          .where((p) => !_hiddenRemotePlaylistIds.contains(p.id))
          .toList();
    }
    final localById = {
      for (final playlist in _localPlaylists) playlist.id: playlist,
    };
    final merged = <GenericPlaylist>[];
    final seen = <String>{};

    for (final playlist in _remotePlaylists) {
      if (_hiddenRemotePlaylistIds.contains(playlist.id)) {
        continue;
      }
      final local = localById[playlist.id];
      merged.add(local ?? playlist);
      seen.add(playlist.id);
    }

    for (final playlist in _localPlaylists) {
      if (!seen.contains(playlist.id)) {
        merged.add(playlist);
      }
    }

    return merged;
  }
}
