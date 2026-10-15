// Copyright © 2026 wizeshi

library;

import 'package:material_ui/material_ui.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/features/library/state/library_folders.dart';

abstract class MetadataProvider extends ChangeNotifier {
  String get name => 'base';
  String get displayName => 'Base Metadata Provider';
  String get description => 'Base metadata provider. Not implemented.';
  String get logoURL => 'about:blank';
  String get iconURL => 'about:blank';
  String get providerId => name.toLowerCase();

  /// Set of capabilities supported by this metadata provider.
  Set<MetadataCapability> get capabilities => const {MetadataCapability.search};

  /// Check whether this metadata provider supports a given capability.
  bool supports(MetadataCapability capability) => capabilities.contains(capability);

  // State
  final _isAuthenticated = false;
  final _isLoading = false;
  String? _errorMessage;
  String? _userDisplayName;
  String? _userId;

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get supportsAuth => false;
  String? get errorMessage => _errorMessage;
  String? get userDisplayName => _userDisplayName;
  String? get userId => _userId;

  bool isTrackLiked(String trackId) => false;

  Future<void> ensureLikedTracksLoaded() async {}

  void setLikedTracksFromItems(List<PlaylistItem> items) {}

  Future<void> toggleTrackLike(GenericSong track) async {}

  Future<void> likeTrack(GenericSong track) async {}

  Future<void> unlikeTrack(GenericSong track) async {}

  MetadataProvider();

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Start OAuth login flow
  Future<void> login(BuildContext context) async {}

  /// Logout and clear token
  Future<void> logout() async {}

  /// Get shareable URL for an entity (track, album, artist, playlist)
  Future<String?> getShareUrl({
    required String type,
    required String id,
  }) async => null;

  /// Get track information by ID
  Future<GenericSong> getTrackInfo(
    String trackId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => throw UnimplementedError('getTrackInfo not supported by $name');

  Future<GenericSong?> getCachedTrackInfo(String trackId) async => null;

  /// Batch fetch track information preserving input order.
  /// Automatically chunks into 50-track batches and falls back to concurrent [getTrackInfo] calls.
  Future<List<GenericSong>> getTracks(
    List<String> trackIds, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (trackIds.isEmpty) return const [];
    final results = <GenericSong>[];
    const chunkSize = 50;
    for (var i = 0; i < trackIds.length; i += chunkSize) {
      final chunk = trackIds.sublist(
        i,
        i + chunkSize > trackIds.length ? trackIds.length : i + chunkSize,
      );
      final futures = chunk.map((id) => getTrackInfo(id, policy: policy));
      final chunkResults = await Future.wait(
        futures.map((f) => f.then<GenericSong?>((s) => s).catchError((_) => null)),
      );
      for (final song in chunkResults) {
        if (song != null) {
          results.add(song);
        }
      }
    }
    return results;
  }

  /// Batch check which track IDs are liked/saved.
  Future<Map<String, bool>> checkTracksLiked(List<String> trackIds) async {
    final map = <String, bool>{};
    for (final id in trackIds) {
      map[id] = isTrackLiked(id);
    }
    return map;
  }

  /// Get album information with pagination support
  Future<GenericAlbum> getAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => throw UnimplementedError('getAlbumInfo not supported by $name');

  Future<GenericAlbum?> getCachedAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
  }) async => null;

  /// Get playlist information with pagination support
  Future<GenericPlaylist> getPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => throw UnimplementedError('getPlaylistInfo not supported by $name');

  Future<GenericPlaylist?> getCachedPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
  }) async => null;

  /// Get full artist information (top tracks + albums)
  Future<GenericArtist> getArtistInfo(
    String artistId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => throw UnimplementedError('getArtistInfo not supported by $name');

  Future<GenericArtist?> getCachedArtistInfo(String artistId) async => null;

  /// Fetch additional tracks for an album (for pagination)
  Future<List<GenericSong>> getMoreAlbumTracks(
    String albumId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  /// Fetch additional tracks for a playlist (for pagination)
  Future<List<PlaylistItem>> getMorePlaylistTracks(
    String playlistId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  /// Get user's saved playlists
  Future<List<GenericPlaylist>> getUserPlaylists({
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  /// Get user's saved tracks (liked songs)
  Future<List<PlaylistItem>> getUserSavedTracks({
    int limit = 50,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  Future<List<PlaylistItem>> getUserSavedTracksAll({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  Future<List<PlaylistItem>?> getCachedSavedTracksAll() async => null;

  Future<void> refreshSavedTracksAll() async {}

  Future<String> createPlaylist({
    required String name,
    String? description,
    bool isPublic = false,
  }) async => throw UnsupportedError('createPlaylist not supported by $name');

  Future<void> renamePlaylist(String playlistId, String name) async {}

  Future<void> updatePlaylistDetails(
    String playlistId, {
    String? name,
    String? description,
    bool? isPublic,
  }) async {
    if (name != null) {
      await renamePlaylist(playlistId, name);
    }
  }

  Future<void> deletePlaylist(String playlistId) async {}

  Future<void> addTracksToPlaylist(String playlistId, List<String> trackIds) async {}

  Future<void> removeTracksFromPlaylist(String playlistId, List<String> trackIds) async {}

  Future<void> reorderPlaylistTracks(String playlistId, int oldIndex, int newIndex) async {}

  /// Get user's saved albums
  Future<List<GenericAlbum>> getUserAlbums({
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  /// Get user's followed artists
  Future<List<GenericSimpleArtist>> getUserFollowedArtists({
    int limit = 20,
    String? after,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  /// Combined user library containing playlists, albums, and followed artists.
  /// Falls back to aggregating individual library collections.
  Future<GenericLibrary> getUserLibrary({
    LibrarySortMode sortMode = LibrarySortMode.recent,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final playlists = await getUserPlaylists(policy: policy);
    final albums = await getUserAlbums(policy: policy);
    final artists = await getUserFollowedArtists(policy: policy);
    return GenericLibrary(
      saved_albums: albums,
      saved_playlists: playlists,
      saved_artists: artists
          .map(
            (a) => GenericArtist(
              id: a.id,
              source: a.source,
              name: a.name,
              thumbnailUrl: a.thumbnailUrl,
              followers: 0,
              topSongs: const [],
              albums: const [],
            ),
          )
          .toList(),
    );
  }

  Future<GenericLibrary?> fetchUserLibrarySorted({
    required LibrarySortMode sortMode,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshAlways,
  }) async => getUserLibrary(sortMode: sortMode, policy: policy);

  /// Get current user's profile
  Future<void> fetchUserProfile() async {}

  /// Search track specifically by International Standard Recording Code (ISRC)
  Future<GenericSong?> searchByIsrc(
    String isrc, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanIsrc = isrc.trim();
    if (cleanIsrc.isEmpty) return null;
    try {
      final results = await search('isrc:$cleanIsrc', limit: 1, policy: policy);
      if (results.tracks.isNotEmpty) {
        return results.tracks.first;
      }
    } catch (_) {}
    return null;
  }

  /// Match or find equivalent track on this provider using ISRC, title, artist, and duration
  Future<GenericSong?> matchTrack({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
    String? isrc,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (isrc != null && isrc.trim().isNotEmpty) {
      final matchedByIsrc = await searchByIsrc(isrc, policy: policy);
      if (matchedByIsrc != null) return matchedByIsrc;
    }

    try {
      final cleanTitle = title.replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '').trim();
      final query = '$cleanTitle $artist';
      final results = await search(query, limit: 10, policy: policy);
      if (results.tracks.isEmpty) return null;

      GenericSong? bestMatch;
      int bestScore = -1;

      for (final candidate in results.tracks) {
        var score = 0;
        final cTitle = candidate.title.toLowerCase();
        final cArtist = candidate.artists.map((a) => a.name).join(', ').toLowerCase();
        final targetTitle = title.toLowerCase();
        final targetArtist = artist.toLowerCase();

        if (cTitle == targetTitle) {
          score += 50;
        } else if (cTitle.contains(cleanTitle.toLowerCase())) {
          score += 30;
        }

        if (cArtist == targetArtist) {
          score += 40;
        } else if (cArtist.contains(targetArtist) || targetArtist.contains(cArtist)) {
          score += 20;
        }

        if (duration != null) {
          final diff = (duration.inSeconds - candidate.durationSecs).abs();
          if (diff <= 3) {
            score += 20;
          } else if (diff <= 7) {
            score += 10;
          }
        }

        if (score > bestScore) {
          bestScore = score;
          bestMatch = candidate;
        }
      }

      if (bestScore >= 40) {
        return bestMatch;
      }
    } catch (_) {}
    return null;
  }

  /// Search for tracks, artists, albums, and playlists
  Future<SearchResults> search(
    String query, {
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  /// Optional features with default graceful fallbacks
  Future<String?> getCanvasUrl(String trackId) async => null;

  Future<List<PlaylistItem>?> getSimilarTracks(String trackId) async => null;

  Future<GenericHome?> getUserHome({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => null;

  Future<List<PlaylistItem>> getRecommended(
    String playlistId,
    List<String> skippedTrackIDs, {
    int numResults = 20,
  }) async => const [];

  Future<void> saveAlbum(String albumId) async {}

  Future<void> unsaveAlbum(String albumId) async {}

  Future<void> followArtist(String artistId) async {}

  Future<void> unfollowArtist(String artistId) async {}

  Future<void> addPlaylistToFolder({
    required String playlistId,
    required String folderId,
  }) async {}

  Future<void> removePlaylistFromFolder({required String playlistId}) async {}

  Future<void> pinLibraryItem(String uri) async {}

  Future<void> unpinLibraryItem(String uri) async {}

  Future<GenericUser?> getUserProfile(
    String userId, {
    int playlistLimit = 10,
    int artistLimit = 10,
    int episodeLimit = 10,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => null;

  Future<List<GenericSimpleUser>> getUserFollowers(
    String userId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  Future<List<GenericSimpleUser>> getUserFollowing(
    String userId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  Future<List<String>> getTrackGenres(String trackId) async => const [];

  Future<String?> getTrackIsrc(String trackId) async => null;

  Map<String, dynamic> dumpJson() => {
    'name': name,
    'displayName': displayName,
    'providerId': providerId,
  };
}
