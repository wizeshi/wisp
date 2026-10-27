// Copyright © 2026 wizeshi

/// YouTube metadata provider
library;

import 'package:flutter/material.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/models/metadata_provider.dart';
import 'package:wisp/data/sources/providers/auth_webview_dialog.dart';
import 'package:wisp/data/sources/providers/service_session_manager.dart';
import 'package:wisp/data/sources/youtube/youtube_converters.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp_innertubex_manager/wisp_innertubex_manager.dart';
import 'youtube_audio.dart';

class YouTubeMetadataProvider extends MetadataProvider {
  final MetadataCacheStore _metadataCache = MetadataCacheStore.instance;
  final YouTubeProvider _youtube = YouTubeProvider();

  static const String _metadataProvider = 'youtube';

  bool _isAuthenticated = false;
  String? _userDisplayName;
  String? _userId;

  YouTubeMetadataProvider() {
    restoreSession();
  }

  @override
  String get name => 'youtube';

  @override
  String get displayName => 'YouTube';

  @override
  String get providerId => 'youtube';

  @override
  String get description => 'YouTube metadata provider powered by InnerTubeX.';

  @override
  String get logoURL =>
      'https://upload.wikimedia.org/wikipedia/commons/2/20/YouTube_2024.svg';

  @override
  String get iconURL =>
      'https://upload.wikimedia.org/wikipedia/commons/f/fd/YouTube_full-color_icon_%282024%29.svg';

  @override
  Set<MetadataCapability> get capabilities => const {
    MetadataCapability.search,
    MetadataCapability.library,
  };

  @override
  bool get supportsAuth => true;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get userDisplayName => _userDisplayName;

  @override
  String? get userId => _userId;

  Future<void> restoreSession() async {
    try {
      final session = await ServiceSessionManager.instance.getSession('youtube');
      if (session != null && session['cookies'] is Map) {
        final cookies = Map<String, String>.from(session['cookies'] as Map);
        final authStatus = await WispInnerTubeXMetadataExtractor.instance.setSessionCookies(cookies);
        _isAuthenticated = authStatus.authenticated;
        _userDisplayName = authStatus.userDisplayName;
        _userId = authStatus.userId;
        notifyListeners();
      }
    } catch (e) {
      logger.d('[YouTubeMetadataProvider] Session restore skipped: $e');
    }
  }

  @override
  Future<void> login(BuildContext context) async {
    try {
      final result = await Navigator.of(context).push<Map<String, dynamic>?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const AuthWebviewDialog(
            initialUrl: 'https://music.youtube.com',
            title: 'YouTube Music Login',
            targetCookies: ['SAPISID'],
          ),
        ),
      );

      if (result != null && result['cookies'] != null) {
        final cookies = Map<String, String>.from(result['cookies'] as Map);
        await ServiceSessionManager.instance.setSession('youtube', {'cookies': cookies});
        final authStatus = await WispInnerTubeXMetadataExtractor.instance.setSessionCookies(cookies);
        _isAuthenticated = authStatus.authenticated;
        _userDisplayName = authStatus.userDisplayName;
        _userId = authStatus.userId;
        notifyListeners();
        logger.i('[YouTubeMetadataProvider] Successfully logged into YouTube Music');
      }
    } catch (e) {
      logger.e('[YouTubeMetadataProvider] Login failed', error: e);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await WispInnerTubeXMetadataExtractor.instance.clearSession();
      await ServiceSessionManager.instance.clearSession('youtube');
      _isAuthenticated = false;
      _userDisplayName = null;
      _userId = null;
      notifyListeners();
      logger.i('[YouTubeMetadataProvider] Logged out of YouTube Music');
    } catch (e) {
      logger.e('[YouTubeMetadataProvider] Logout failed', error: e);
    }
  }

  @override
  Future<String?> getShareUrl({
    required String type,
    required String id,
  }) async {
    final cleanId = id.contains(':') ? id.split(':').last : id;
    final t = type.toLowerCase();
    if (t == 'track') return 'https://www.youtube.com/watch?v=$cleanId';
    if (t == 'playlist') return 'https://www.youtube.com/playlist?list=$cleanId';
    return null;
  }

  @override
  Future<GenericSong> getTrackInfo(
    String trackId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = trackId.contains(':') ? trackId.split(':').last : trackId;
    final cached = await getCachedTrackInfo(cleanId);
    if (policy == MetadataFetchPolicy.cacheFirst && cached != null) {
      return cached;
    }

    try {
      final track = await WispInnerTubeXMetadataExtractor.instance.getTrackInfo(cleanId);
      final song = innerTubeTrackToGenericSong(track);
      await _writeCacheEntry(
        type: 'track',
        id: cleanId,
        payload: song.toJson(),
      );
      return song;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  @override
  Future<GenericSong?> getCachedTrackInfo(String trackId) async {
    final cleanId = trackId.contains(':') ? trackId.split(':').last : trackId;
    final entry = await _readCacheEntry(type: 'track', id: cleanId);
    if (entry != null && entry.payload.isNotEmpty) {
      return GenericSong.fromJson(entry.payload);
    }
    return null;
  }

  @override
  Future<SearchResults> search(
    String query, {
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cacheId = _cacheKeyForQuery('$query:all:$limit');
    final entry = await _readCacheEntry(type: 'search_all', id: cacheId);
    if (policy == MetadataFetchPolicy.cacheFirst && entry != null && !entry.isExpired) {
      return SearchResults.fromJson(entry.payload);
    }

    try {
      final results = await WispInnerTubeXMetadataExtractor.instance.search(query, limit: limit);
      final tracks = <GenericSong>[];
      final artists = <GenericSimpleArtist>[];
      final albums = <GenericAlbum>[];
      final playlists = <GenericPlaylist>[];

      for (final r in results) {
        switch (r.type) {
          case 'artist':
            artists.add(GenericSimpleArtist(
              id: r.id,
              source: 'youtube',
              name: r.title,
              thumbnailUrl: r.thumbnailUrl ?? '',
            ));
            break;
          case 'album':
            albums.add(GenericAlbum(
              id: r.id,
              source: 'youtube',
              title: r.title,
              thumbnailUrl: r.thumbnailUrl ?? '',
              artists: [
                GenericSimpleArtist(
                  id: 'yt_artist_${r.artist ?? "unknown"}',
                  source: 'youtube',
                  name: r.artist ?? 'YouTube',
                  thumbnailUrl: r.thumbnailUrl ?? '',
                )
              ],
              label: '',
              releaseDate: DateTime(2020),
              explicit: false,
              durationSecs: r.duration?.inSeconds ?? 0,
            ));
            break;
          case 'playlist':
            final authorName = r.artist ?? 'YouTube';
            playlists.add(GenericPlaylist(
              id: r.id,
              source: 'youtube',
              title: r.title,
              author: GenericSimpleUser(
                id: 'yt_user_$authorName',
                source: 'youtube',
                displayName: authorName,
              ),
              thumbnailUrl: r.thumbnailUrl ?? '',
              durationSecs: 0,
            ));
            break;
          case 'track':
          default:
            tracks.add(innerTubeSearchResultToGenericSong(r));
            break;
        }
      }

      if (tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty) {
        final legacyTracks = await searchTracks(query, limit: limit, policy: policy);
        return SearchResults(
          tracks: legacyTracks,
          artists: const [],
          albums: const [],
          playlists: const [],
          bestMatch: legacyTracks.isNotEmpty ? SearchBestMatch.track(legacyTracks.first) : null,
        );
      }

      final searchResults = SearchResults(
        tracks: tracks,
        artists: artists,
        albums: albums,
        playlists: playlists,
        bestMatch: tracks.isNotEmpty ? SearchBestMatch.track(tracks.first) : null,
      );

      await _writeCacheEntry(
        type: 'search_all',
        id: cacheId,
        payload: searchResults.toJson(),
      );

      return searchResults;
    } catch (_) {
      final fallbackTracks = await searchTracks(query, limit: limit, policy: policy);
      return SearchResults(
        tracks: fallbackTracks,
        artists: const [],
        albums: const [],
        playlists: const [],
        bestMatch: fallbackTracks.isNotEmpty ? SearchBestMatch.track(fallbackTracks.first) : null,
      );
    }
  }

  @override
  Future<GenericAlbum> getAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = albumId.contains(':') ? albumId.split(':').last : albumId;
    final cached = await getCachedAlbumInfo(cleanId);
    if (policy == MetadataFetchPolicy.cacheFirst && cached != null) {
      return cached;
    }

    try {
      final album = await WispInnerTubeXMetadataExtractor.instance.getAlbumInfo(cleanId);
      final generic = innerTubeAlbumToGenericAlbum(album);
      await _writeCacheEntry(type: 'album', id: cleanId, payload: generic.toJson());
      return generic;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  @override
  Future<GenericAlbum?> getCachedAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
  }) async {
    final cleanId = albumId.contains(':') ? albumId.split(':').last : albumId;
    final entry = await _readCacheEntry(type: 'album', id: cleanId);
    if (entry != null && entry.payload.isNotEmpty) {
      return GenericAlbum.fromJson(entry.payload);
    }
    return null;
  }

  @override
  Future<GenericArtist> getArtistInfo(
    String artistId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = artistId.contains(':') ? artistId.split(':').last : artistId;
    final cached = await getCachedArtistInfo(cleanId);
    if (policy == MetadataFetchPolicy.cacheFirst && cached != null) {
      return cached;
    }

    try {
      final artist = await WispInnerTubeXMetadataExtractor.instance.getArtistInfo(cleanId);
      final generic = innerTubeArtistToGenericArtist(artist);
      await _writeCacheEntry(type: 'artist', id: cleanId, payload: generic.toJson());
      return generic;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  @override
  Future<GenericArtist?> getCachedArtistInfo(String artistId) async {
    final cleanId = artistId.contains(':') ? artistId.split(':').last : artistId;
    final entry = await _readCacheEntry(type: 'artist', id: cleanId);
    if (entry != null && entry.payload.isNotEmpty) {
      return GenericArtist.fromJson(entry.payload);
    }
    return null;
  }

  @override
  Future<GenericPlaylist> getPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = playlistId.contains(':') ? playlistId.split(':').last : playlistId;
    final cached = await getCachedPlaylistInfo(cleanId);
    if (policy == MetadataFetchPolicy.cacheFirst && cached != null) {
      return cached;
    }

    try {
      final playlist = await WispInnerTubeXMetadataExtractor.instance.getPlaylistInfo(cleanId);
      final generic = innerTubePlaylistToGenericPlaylist(playlist);
      await _writeCacheEntry(type: 'playlist', id: cleanId, payload: generic.toJson());
      return generic;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  @override
  Future<GenericPlaylist?> getCachedPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
  }) async {
    final cleanId = playlistId.contains(':') ? playlistId.split(':').last : playlistId;
    final entry = await _readCacheEntry(type: 'playlist', id: cleanId);
    if (entry != null && entry.payload.isNotEmpty) {
      return GenericPlaylist.fromJson(entry.payload);
    }
    return null;
  }

  @override
  Future<List<PlaylistItem>> getUserSavedTracks({
    int limit = 50,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    return _getListWithCache<PlaylistItem>(
      type: 'user_saved_tracks',
      id: 'saved_tracks',
      policy: policy,
      fetcher: () async {
        final liked = await WispInnerTubeXMetadataExtractor.instance.getLikedTracks();
        return liked.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return PlaylistItem(
            id: item.id,
            source: 'youtube',
            title: item.title,
            artists: [
              GenericSimpleArtist(
                id: 'yt_artist_${item.artist ?? "unknown"}',
                source: 'youtube',
                name: item.artist ?? 'YouTube',
                thumbnailUrl: item.thumbnailUrl ?? '',
              ),
            ],
            thumbnailUrl: item.thumbnailUrl ?? '',
            explicit: false,
            album: null,
            durationSecs: item.duration?.inSeconds ?? 0,
            addedAt: DateTime.now(),
            trackNumber: idx + 1,
          );
        }).toList();
      },
      itemToJson: (item) => item.toJson(),
      itemFromJson: PlaylistItem.fromJson,
    );
  }

  Future<MetadataCacheEntry?> _readCacheEntry({
    required String type,
    required String id,
  }) {
    return _metadataCache.readEntry(
      provider: _metadataProvider,
      type: type,
      id: id,
    );
  }

  Future<void> _writeCacheEntry({
    required String type,
    required String id,
    required Map<String, dynamic> payload,
  }) {
    return _metadataCache.writeEntry(
      provider: _metadataProvider,
      type: type,
      id: id,
      payload: payload,
    );
  }

  Future<List<T>> _getListWithCache<T>({
    required String type,
    required String id,
    required MetadataFetchPolicy policy,
    required Future<List<T>> Function() fetcher,
    required Map<String, dynamic> Function(T) itemToJson,
    required T Function(Map<String, dynamic>) itemFromJson,
  }) async {
    MetadataCacheEntry? entry;
    List<T>? cached;
    try {
      entry = await _readCacheEntry(type: type, id: id);
      final items = entry?.payload['items'] as List?;
      if (items != null) {
        cached = items
            .whereType<Map<String, dynamic>>()
            .map(itemFromJson)
            .toList();
      }
    } catch (_) {
      cached = null;
    }

    final isExpired = entry?.isExpired ?? true;
    if (cached != null) {
      if (policy == MetadataFetchPolicy.cacheFirst) {
        return cached;
      }
      if (policy == MetadataFetchPolicy.refreshIfExpired && !isExpired) {
        return cached;
      }
      if (policy == MetadataFetchPolicy.refreshAlways) {
        try {
          final fresh = await fetcher();
          await _writeCacheEntry(
            type: type,
            id: id,
            payload: {'items': fresh.map(itemToJson).toList()},
          );
          return fresh;
        } catch (_) {
          return cached;
        }
      }
    }

    try {
      final fresh = await fetcher();
      await _writeCacheEntry(
        type: type,
        id: id,
        payload: {'items': fresh.map(itemToJson).toList()},
      );
      return fresh;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  String _cacheKeyForQuery(String query) {
    final normalized = query.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return normalized.isEmpty ? 'empty' : normalized;
  }

  Future<List<GenericSong>> searchTracks(
    String query, {
    int limit = 10,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cacheId = _cacheKeyForQuery(query);
    return _getListWithCache<GenericSong>(
      type: 'search_tracks',
      id: cacheId,
      policy: policy,
      fetcher: () async {
        final results = await _youtube.searchYouTubeTracks(query, limit: limit);
        return results.map(youtubeResultToGenericSong).toList();
      },
      itemToJson: (item) => item.toJson(),
      itemFromJson: GenericSong.fromJson,
    );
  }
}
