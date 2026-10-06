// Copyright © 2026 wizeshi

library;

import 'package:flutter/widgets.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/models/metadata_provider.dart';
import 'package:wisp/data/sources/metadata/js_metadata_source.dart';
import 'package:wisp/data/sources/metadata/metadata_source_manager.dart';
import 'package:wisp/features/library/state/library_folders.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';
import 'package:wisp/core/utils/liked_songs.dart';

/// Central manager orchestrating catalog, search, and detail metadata operations
/// across multiple built-in and dynamic metadata providers.
class MetadataManager extends ChangeNotifier {
  final Map<String, MetadataProvider> _providers = {};
  PreferencesProvider? _preferences;

  MetadataManager({
    MetadataProvider? spotifyProvider,
    MetadataProvider? youtubeProvider,
    PreferencesProvider? preferences,
  }) {
    if (spotifyProvider != null) {
      registerProvider(spotifyProvider);
    }
    if (youtubeProvider != null) {
      registerProvider(youtubeProvider);
    }
    if (preferences != null) {
      bindPreferences(preferences);
    }

    _syncFromSourceManager();
    MetadataSourceManager.instance.addListener(_onSourceManagerChanged);
  }

  void bindPreferences(PreferencesProvider preferences) {
    if (_preferences == preferences) return;
    _preferences?.removeListener(_onPreferencesChanged);
    _preferences = preferences;
    _preferences?.addListener(_onPreferencesChanged);
    notifyListeners();
  }

  void _onPreferencesChanged() {
    notifyListeners();
  }

  void _onSourceManagerChanged() {
    _syncFromSourceManager();
    notifyListeners();
  }

  void _syncFromSourceManager() {
    final activeSources = MetadataSourceManager.instance.sources;
    for (final entry in activeSources.entries) {
      final key = entry.key.toLowerCase();
      if (!_providers.containsKey(key) || _providers[key] is JsMetadataSource) {
        _providers[key] = entry.value;
      }
    }
    _providers.removeWhere((key, provider) {
      if (provider is JsMetadataSource && !activeSources.containsKey(key)) {
        logger.i('[MetadataManager] Pruned uninstalled provider: $key');
        return true;
      }
      return false;
    });
  }

  /// Register or update a metadata provider.
  void registerProvider(MetadataProvider provider, {bool override = true}) {
    final key = provider.providerId.toLowerCase();
    if (!override && _providers.containsKey(key)) {
      return;
    }
    _providers[key] = provider;
    logger.i('[MetadataManager] Registered provider: $key (${provider.displayName})');
    notifyListeners();
  }

  /// Unregister a metadata provider by ID.
  void unregisterProvider(String providerId) {
    final key = providerId.toLowerCase();
    if (_providers.remove(key) != null) {
      logger.i('[MetadataManager] Unregistered provider: $key');
      notifyListeners();
    }
  }

  /// All registered providers regardless of preferences.
  List<MetadataProvider> get allProviders => List.unmodifiable(_providers.values);

  /// Providers currently enabled according to user preferences,
  /// ordered by custom user priority (or default priority).
  List<MetadataProvider> get availableProviders {
    final prefs = _preferences;
    final enabled = _providers.values.where((p) {
      if (prefs == null) return true;
      return prefs.isProviderEnabled(p.providerId, type: 'metadata');
    }).toList();

    final customOrder = prefs?.getProviderOrder('metadata') ?? const [];
    enabled.sort((a, b) {
      final aId = a.providerId.toLowerCase();
      final bId = b.providerId.toLowerCase();
      final aIdx = customOrder.indexOf(aId);
      final bIdx = customOrder.indexOf(bId);
      if (aIdx != -1 && bIdx != -1) {
        return aIdx.compareTo(bIdx);
      }
      if (aIdx != -1) return -1;
      if (bIdx != -1) return 1;

      final aPrio = a is JsMetadataSource ? 100 : 50;
      final bPrio = b is JsMetadataSource ? 100 : 50;
      return bPrio.compareTo(aPrio);
    });

    return List.unmodifiable(enabled);
  }

  /// Whether any metadata provider is currently enabled.
  bool get hasEnabledProviders => availableProviders.isNotEmpty;

  /// Checks if a provider is enabled.
  bool isProviderEnabled(String providerId) {
    return availableProviders.any(
      (p) => p.providerId.toLowerCase() == providerId.toLowerCase(),
    );
  }

  /// Resolve provider by ID, name, or display name (case-insensitive).
  MetadataProvider? getProvider(String idOrName) {
    final key = idOrName.trim().toLowerCase();
    final normalizedKey = key == 'spotifyinternal' ? 'spotify' : key;
    if (_providers.containsKey(normalizedKey)) {
      return _providers[normalizedKey];
    }
    for (final p in _providers.values) {
      if (p.providerId.toLowerCase() == normalizedKey ||
          p.name.toLowerCase() == normalizedKey ||
          p.displayName.toLowerCase() == normalizedKey) {
        return p;
      }
    }
    return null;
  }

  /// Resolve provider for a specific source string.
  MetadataProvider? getProviderForSource(String source) {
    return getProvider(source);
  }

  /// Active default catalog provider (top of priority order).
  MetadataProvider? get activeCatalogProvider {
    final available = availableProviders;
    return available.isNotEmpty ? available.first : null;
  }

  /// Whether the specified or active catalog provider supports a capability.
  bool hasCapability(
    MetadataCapability capability, {
    String? providerId,
    String? source,
  }) {
    MetadataProvider? provider;
    if (providerId != null || source != null) {
      if (providerId != null) {
        provider = getProvider(providerId);
      }
      if (provider == null && source != null) {
        provider = getProviderForSource(source);
      }
    } else {
      provider = activeCatalogProvider;
    }
    return provider?.supports(capability) ?? false;
  }

  /// All enabled providers that support a specific capability.
  List<MetadataProvider> getProvidersWithCapability(MetadataCapability capability) {
    return availableProviders.where((p) => p.supports(capability)).toList();
  }

  /// Authentication & state proxies for the active provider
  bool get isAuthenticated => activeCatalogProvider?.isAuthenticated ?? false;
  bool get isLoading => activeCatalogProvider?.isLoading ?? false;
  String? get userDisplayName => activeCatalogProvider?.userDisplayName;
  String? get userId => activeCatalogProvider?.userId;
  int? get likedTracksTotalCount => (activeCatalogProvider as dynamic)?.likedTracksTotalCount as int?;
  bool get hasLoadedLikedTracks => (activeCatalogProvider as dynamic)?.hasLoadedLikedTracks as bool? ?? false;

  void setLikedTracksFromItems(List<PlaylistItem> items) {
    activeCatalogProvider?.setLikedTracksFromItems(items);
  }

  Future<void> ensureLikedTracksLoaded({String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    await provider.ensureLikedTracksLoaded();
  }

  Future<void> checkAuthState() async {
    await activeCatalogProvider?.fetchUserProfile();
  }

  Future<void> login(BuildContext context) async {
    await activeCatalogProvider?.login(context);
    notifyListeners();
  }

  Future<void> logout() async {
    await activeCatalogProvider?.logout();
    notifyListeners();
  }

  /// Internal helper to resolve the targeted or default provider.
  MetadataProvider _resolveProvider({String? providerId, String? source}) {
    if (providerId != null) {
      final p = getProvider(providerId);
      if (p != null) return p;
    }
    if (source != null) {
      final p = getProviderForSource(source);
      if (p != null) return p;
    }
    final active = activeCatalogProvider;
    if (active != null) return active;
    if (availableProviders.isNotEmpty) return availableProviders.first;
    if (_providers.isNotEmpty) return _providers.values.first;
    throw StateError('No metadata provider registered or available.');
  }

  // ---------------------------------------------------------------------------
  // Search & Catalog Operations
  // ---------------------------------------------------------------------------

  /// Search across a specified provider or the active default provider.
  Future<SearchResults> search(
    String query, {
    String? providerId,
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId);
    return provider.search(query, limit: limit, offset: offset, policy: policy);
  }

  /// Search across all available providers concurrently and aggregate by provider ID.
  Future<Map<String, SearchResults>> searchAll(
    String query, {
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final providers = availableProviders;
    final futures = providers.map((p) async {
      try {
        final res = await p.search(query, limit: limit, offset: offset, policy: policy);
        return MapEntry(p.providerId, res);
      } catch (e) {
        logger.w('[MetadataManager] Search failed for ${p.providerId}: $e');
        return MapEntry(
          p.providerId,
          SearchResults(
            tracks: const [],
            artists: const [],
            albums: const [],
            playlists: const [],
          ),
        );
      }
    });

    final entries = await Future.wait(futures);
    return Map.fromEntries(entries);
  }

  /// Get track info by ID from the specified or resolved provider.
  Future<GenericSong> getTrackInfo(
    String trackId, {
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getTrackInfo(trackId, policy: policy);
  }

  /// Get cached track info if present.
  Future<GenericSong?> getCachedTrackInfo(
    String trackId, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getCachedTrackInfo(trackId);
  }

  /// Get album info by ID.
  Future<GenericAlbum> getAlbumInfo(
    String albumId, {
    String? providerId,
    String? source,
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getAlbumInfo(albumId, offset: offset, limit: limit, policy: policy);
  }

  /// Get playlist info by ID.
  Future<GenericPlaylist> getPlaylistInfo(
    String playlistId, {
    String? providerId,
    String? source,
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (isLikedSongsPlaylistId(playlistId)) {
      final cached = await getCachedLikedSongs(providerId: providerId, source: source);
      if (cached != null && cached.isNotEmpty && offset == 0 && policy != MetadataFetchPolicy.refreshAlways) {
        return GenericPlaylist(
          id: playlistId,
          source: source ?? 'spotify',
          title: 'Liked Songs',
          thumbnailUrl: '',
          author: GenericSimpleUser(
            id: 'liked_songs_user',
            source: source ?? 'spotify',
            displayName: userDisplayName ?? 'You',
          ),
          songs: cached.take(limit).toList(),
          durationSecs: 0,
          total: likedTracksTotalCount ?? cached.length,
          hasMore: cached.length > limit,
        );
      }
      final savedSongs = await getUserSavedTracks(
        limit: limit,
        offset: offset,
        providerId: providerId,
        source: source,
        policy: policy,
      );
      return GenericPlaylist(
        id: playlistId,
        source: source ?? 'spotify',
        title: 'Liked Songs',
        thumbnailUrl: '',
        author: GenericSimpleUser(
          id: 'liked_songs_user',
          source: source ?? 'spotify',
          displayName: userDisplayName ?? 'You',
        ),
        songs: savedSongs,
        durationSecs: 0,
        total: likedTracksTotalCount,
        hasMore: (likedTracksTotalCount != null && (offset + limit) < likedTracksTotalCount!),
      );
    }
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getPlaylistInfo(playlistId, offset: offset, limit: limit, policy: policy);
  }

  /// Get cached full playlist (all tracks) if present in store.
  Future<GenericPlaylist?> getCachedFullPlaylist(
    String playlistId, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    final entry = await MetadataCacheStore.instance.readEntry(
      provider: provider.providerId,
      type: 'full_playlist',
      id: playlistId,
    );
    if (entry != null) {
      try {
        return GenericPlaylist.fromJson(entry.payload);
      } catch (e) {
        logger.w('[MetadataManager] Failed to decode cached full playlist: $e');
      }
    }
    return provider.getCachedPlaylistInfo(playlistId);
  }

  /// Write full playlist to cache store.
  Future<void> cacheFullPlaylist(
    GenericPlaylist playlist, {
    String? providerId,
  }) async {
    final pid = providerId ?? playlist.source;
    await MetadataCacheStore.instance.writeEntry(
      provider: pid,
      type: 'full_playlist',
      id: playlist.id,
      payload: playlist.toJson(),
      ttl: const Duration(days: 7),
    );
  }

  /// Fetch full playlist across all track pages and cache the assembled result.
  Future<GenericPlaylist> fetchFullPlaylistWithTracks(
    String playlistId, {
    String? providerId,
    String? source,
  }) async {
    if (isLikedSongsPlaylistId(playlistId)) {
      final savedSongs = await fetchLikedSongs(providerId: providerId, source: source);
      return GenericPlaylist(
        id: playlistId,
        source: source ?? 'spotify',
        title: 'Liked Songs',
        thumbnailUrl: '',
        author: GenericSimpleUser(
          id: 'liked_songs_user',
          source: source ?? 'spotify',
          displayName: userDisplayName ?? 'You',
        ),
        songs: savedSongs,
        durationSecs: savedSongs.fold(0, (acc, s) => acc + s.durationSecs),
        total: savedSongs.length,
        hasMore: false,
      );
    }

    final provider = _resolveProvider(providerId: providerId, source: source);
    const fetchLimit = 50;
    final playlist = await provider.getPlaylistInfo(
      playlistId,
      offset: 0,
      limit: fetchLimit,
      policy: MetadataFetchPolicy.refreshAlways,
    );
    final items = <PlaylistItem>[...?(playlist.songs)];

    int offset = items.length;
    while (offset < (playlist.total ?? 0)) {
      final morePlaylist = await provider.getPlaylistInfo(
        playlistId,
        offset: offset,
        limit: fetchLimit,
        policy: MetadataFetchPolicy.refreshIfExpired,
      );
      final more = morePlaylist.songs ?? const <PlaylistItem>[];
      if (more.isEmpty) break;
      items.addAll(more);
      offset = items.length;
      if (more.length < fetchLimit || morePlaylist.hasMore == false) break;
    }

    final full = GenericPlaylist(
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

    await cacheFullPlaylist(full, providerId: provider.providerId);
    return full;
  }

  /// Get cached full album (all tracks) if present in store.
  Future<GenericAlbum?> getCachedFullAlbum(
    String albumId, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    final entry = await MetadataCacheStore.instance.readEntry(
      provider: provider.providerId,
      type: 'full_album',
      id: albumId,
    );
    if (entry != null) {
      try {
        return GenericAlbum.fromJson(entry.payload);
      } catch (e) {
        logger.w('[MetadataManager] Failed to decode cached full album: $e');
      }
    }
    return provider.getCachedAlbumInfo(albumId);
  }

  /// Write full album to cache store.
  Future<void> cacheFullAlbum(
    GenericAlbum album, {
    String? providerId,
  }) async {
    final pid = providerId ?? album.source;
    await MetadataCacheStore.instance.writeEntry(
      provider: pid,
      type: 'full_album',
      id: album.id,
      payload: album.toJson(),
      ttl: const Duration(days: 7),
    );
  }

  /// Fetch full album across all track pages and cache the assembled result.
  Future<GenericAlbum> fetchFullAlbumWithTracks(
    String albumId, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    final album = await provider.getAlbumInfo(
      albumId,
      offset: 0,
      limit: 50,
      policy: MetadataFetchPolicy.refreshAlways,
    );
    final items = <GenericSong>[...?(album.songs)];

    int offset = items.length;
    while (album.hasMore == true && offset < (album.total ?? 0)) {
      final moreAlbum = await provider.getAlbumInfo(
        albumId,
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

    final full = GenericAlbum(
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

    await cacheFullAlbum(full, providerId: provider.providerId);
    return full;
  }

  /// Get cached liked songs if present in store.
  Future<List<PlaylistItem>?> getCachedLikedSongs({
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    final entry = await MetadataCacheStore.instance.readEntry(
      provider: provider.providerId,
      type: 'saved_tracks_all',
      id: 'all',
    );
    if (entry != null) {
      final items = entry.payload['items'] as List?;
      if (items != null) {
        final parsed = items
            .whereType<Map<String, dynamic>>()
            .map(PlaylistItem.fromJson)
            .toList();
        if (parsed.isNotEmpty && parsed.any((s) => s.id.isEmpty)) {
          return null;
        }
        return parsed;
      }
    }
    return provider.getCachedSavedTracksAll();
  }

  /// Write liked songs to cache store.
  Future<void> cacheLikedSongs(
    List<PlaylistItem> songs, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    await MetadataCacheStore.instance.writeEntry(
      provider: provider.providerId,
      type: 'saved_tracks_all',
      id: 'all',
      payload: {'items': songs.map((s) => s.toJson()).toList()},
      ttl: const Duration(days: 7),
    );
  }

  /// Fetch all user saved tracks and update local liked songs cache.
  Future<List<PlaylistItem>> fetchLikedSongs({
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    const limit = 50;
    final items = <PlaylistItem>[];

    final freshFirst = await provider.getUserSavedTracks(
      limit: limit,
      offset: 0,
      policy: MetadataFetchPolicy.refreshAlways,
    );
    items.addAll(freshFirst);

    var offset = items.length;
    while (true) {
      final page = await provider.getUserSavedTracks(
        limit: limit,
        offset: offset,
        policy: MetadataFetchPolicy.refreshIfExpired,
      );
      if (page.isEmpty) break;
      items.addAll(page);
      offset = items.length;
      if (page.length < limit) break;
    }

    setLikedTracksFromItems(items);
    await cacheLikedSongs(items, providerId: provider.providerId);
    return items;
  }

  /// Get cached artist details if present.
  Future<GenericArtist?> getCachedArtist(
    String artistId, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    final entry = await MetadataCacheStore.instance.readEntry(
      provider: provider.providerId,
      type: 'artist',
      id: artistId,
    );
    if (entry != null) {
      try {
        return GenericArtist.fromJson(entry.payload);
      } catch (e) {
        logger.w('[MetadataManager] Failed to decode cached artist: $e');
      }
    }
    return provider.getCachedArtistInfo(artistId);
  }

  /// Write artist to cache store.
  Future<void> cacheArtist(
    GenericArtist artist, {
    String? providerId,
  }) async {
    final pid = providerId ?? artist.source;
    await MetadataCacheStore.instance.writeEntry(
      provider: pid,
      type: 'artist',
      id: artist.id,
      payload: artist.toJson(),
      ttl: const Duration(days: 7),
    );
  }

  /// Fetch artist and cache result.
  Future<GenericArtist> fetchArtist(
    String artistId, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    final artist = await provider.getArtistInfo(
      artistId,
      policy: MetadataFetchPolicy.refreshAlways,
    );
    await cacheArtist(artist, providerId: provider.providerId);
    return artist;
  }

  /// Get cached user profile if present.
  Future<GenericUser?> getCachedUserProfile(
    String userId, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    final entry = await MetadataCacheStore.instance.readEntry(
      provider: provider.providerId,
      type: 'user_profile',
      id: userId,
    );
    if (entry != null) {
      try {
        return GenericUser.fromJson(entry.payload);
      } catch (e) {
        logger.w('[MetadataManager] Failed to decode cached user profile: $e');
      }
    }
    return null;
  }

  /// Write user profile to cache store.
  Future<void> cacheUserProfile(
    GenericUser user, {
    String? providerId,
  }) async {
    final pid = providerId ?? user.source;
    await MetadataCacheStore.instance.writeEntry(
      provider: pid,
      type: 'user_profile',
      id: user.id,
      payload: user.toJson(),
      ttl: const Duration(days: 7),
    );
  }

  /// Fetch full user profile and cache result.
  Future<GenericUser> fetchUserProfileDetails(
    String userId, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    final user = await provider.getUserProfile(
      userId,
      policy: MetadataFetchPolicy.refreshAlways,
    );
    if (user != null) {
      await cacheUserProfile(user, providerId: provider.providerId);
      return user;
    }
    throw Exception('Failed to fetch user profile for $userId');
  }

  /// Get artist info by ID.
  Future<GenericArtist> getArtistInfo(
    String artistId, {
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getArtistInfo(artistId, policy: policy);
  }

  final Map<String, Future<String?>> _canvasFutureCache = {};

  /// Get canvas background video URL for track.
  Future<String?> getCanvasUrl(String trackId, {String? providerId, String? source}) {
    final provider = _resolveProvider(providerId: providerId, source: source);
    final cacheKey = '${provider.providerId}:$trackId';
    final existing = _canvasFutureCache[cacheKey];
    if (existing != null) {
      return existing;
    }
    if (_canvasFutureCache.length > 200) {
      _canvasFutureCache.remove(_canvasFutureCache.keys.first);
    }
    final future = provider.getCanvasUrl(trackId);
    _canvasFutureCache[cacheKey] = future;
    return future;
  }

  /// Get similar tracks (track radio / autoplay).
  Future<List<PlaylistItem>?> getSimilarTracks(
    String trackId, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getSimilarTracks(trackId);
  }

  /// Get user home feed sections.
  Future<GenericHome?> getUserHome({
    String? providerId,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId);
    return provider.getUserHome(policy: policy);
  }

  /// Get recommended tracks for playlist.
  Future<List<PlaylistItem>> getRecommended(
    String playlistId,
    List<String> skippedTrackIDs, {
    int numResults = 20,
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getRecommended(playlistId, skippedTrackIDs, numResults: numResults);
  }

  /// Save / unsave album in user library.
  Future<void> saveAlbum(String albumId, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.saveAlbum(albumId);
  }

  Future<void> unsaveAlbum(String albumId, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.unsaveAlbum(albumId);
  }

  /// Follow / unfollow artist in user library.
  Future<void> followArtist(String artistId, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.followArtist(artistId);
  }

  Future<void> unfollowArtist(String artistId, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.unfollowArtist(artistId);
  }

  /// Like status and mutations.
  bool isTrackLiked(String trackId, {String? providerId, String? source}) {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.isTrackLiked(trackId);
  }

  Future<void> toggleTrackLike(GenericSong track, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source ?? track.source);
    await provider.toggleTrackLike(track);
    notifyListeners();
  }

  Future<void> likeTrack(GenericSong track, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source ?? track.source);
    await provider.likeTrack(track);
    notifyListeners();
  }

  Future<void> unlikeTrack(GenericSong track, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source ?? track.source);
    await provider.unlikeTrack(track);
    notifyListeners();
  }

  /// User saved tracks (Liked Songs)
  Future<List<PlaylistItem>> getUserSavedTracks({
    int limit = 50,
    int offset = 0,
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getUserSavedTracks(limit: limit, offset: offset, policy: policy);
  }

  Future<List<PlaylistItem>> getUserSavedTracksAll({
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getUserSavedTracksAll(policy: policy);
  }

  Future<void> refreshSavedTracksAll({String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.refreshSavedTracksAll();
  }

  /// User Library & Playlists
  Future<List<GenericPlaylist>> getUserPlaylists({
    int limit = 20,
    int offset = 0,
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getUserPlaylists(limit: limit, offset: offset, policy: policy);
  }

  Future<GenericLibrary?> getUserLibrary({
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    if (provider is JsMetadataSource) {
      return provider.getUserLibrary(policy: policy);
    }
    final playlists = await provider.getUserPlaylists(policy: policy);
    final albums = await provider.getUserAlbums(policy: policy);
    final artists = await provider.getUserFollowedArtists(policy: policy);
    return GenericLibrary(
      saved_albums: albums,
      saved_playlists: playlists,
      saved_artists: artists
          .map((a) => GenericArtist(
                id: a.id,
                name: a.name,
                source: a.source,
                thumbnailUrl: a.thumbnailUrl,
                followers: 0,
                topSongs: const [],
                albums: const [],
              ))
          .toList(),
    );
  }

  Future<List<GenericAlbum>> getUserAlbums({
    int limit = 20,
    int offset = 0,
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getUserAlbums(limit: limit, offset: offset, policy: policy);
  }

  Future<List<GenericSimpleArtist>> getUserFollowedArtists({
    int limit = 20,
    String? after,
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getUserFollowedArtists(limit: limit, after: after, policy: policy);
  }

  Future<void> fetchUserProfile({String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.fetchUserProfile();
  }

  Future<GenericUser?> getUserProfile(
    String userId, {
    int playlistLimit = 10,
    int artistLimit = 10,
    int episodeLimit = 10,
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getUserProfile(
      userId,
      playlistLimit: playlistLimit,
      artistLimit: artistLimit,
      episodeLimit: episodeLimit,
      policy: policy,
    );
  }

  Future<List<GenericSimpleUser>> getUserFollowers(
    String userId, {
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getUserFollowers(userId, policy: policy);
  }

  Future<List<GenericSimpleUser>> getUserFollowing(
    String userId, {
    String? providerId,
    String? source,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getUserFollowing(userId, policy: policy);
  }

  Future<String> createPlaylist({
    required String name,
    String? description,
    bool isPublic = false,
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.createPlaylist(name: name, description: description, isPublic: isPublic);
  }

  Future<void> addTracksToPlaylist(
    String playlistId,
    List<String> trackIds, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.addTracksToPlaylist(playlistId, trackIds);
  }

  Future<void> addPlaylistToFolder({
    required String playlistId,
    required String folderId,
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.addPlaylistToFolder(playlistId: playlistId, folderId: folderId);
  }

  Future<void> removePlaylistFromFolder({
    required String playlistId,
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.removePlaylistFromFolder(playlistId: playlistId);
  }

  Future<List<String>> getTrackGenres(String trackId, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    return provider.getTrackGenres(trackId);
  }

  Future<dynamic> getNpvArtistInfo(String artistId, String trackId, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    if (provider is JsMetadataSource) {
      return provider.getNpvArtistInfo(artistId, trackId);
    }
    return provider.getArtistInfo(artistId);
  }

  Future<void> renamePlaylist(String playlistId, String name, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    await provider.renamePlaylist(playlistId, name);
  }

  Future<void> deletePlaylist(String playlistId, {String? providerId, String? source}) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    await provider.deletePlaylist(playlistId);
  }

  Future<void> removeTracksFromPlaylist(
    String playlistId,
    List<String> trackIds, {
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    if (provider is JsMetadataSource) {
      await provider.removeTracksFromPlaylist(playlistId, trackIds);
    }
  }


  Future<GenericLibrary?> fetchUserLibrarySorted({
    required LibrarySortMode sortMode,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshAlways,
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    if (provider is JsMetadataSource) {
      return provider.fetchUserLibrarySorted(sortMode: sortMode, policy: policy);
    }
    return null;
  }

  Future<void> reportItemPlayed({
    required String itemId,
    required String itemType,
    String? providerId,
    String? source,
  }) async {
    final provider = _resolveProvider(providerId: providerId, source: source);
    if (provider is JsMetadataSource) {
      await provider.reportItemPlayed(itemId: itemId, itemType: itemType);
    }
  }

  @override
  void dispose() {
    _preferences?.removeListener(_onPreferencesChanged);
    MetadataSourceManager.instance.removeListener(_onSourceManagerChanged);
    super.dispose();
  }
}
