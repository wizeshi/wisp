// Copyright © 2026 wizeshi

library;

import 'package:flutter/material.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/cache/metadata_cache.dart';

abstract class MetadataProvider extends ChangeNotifier {
  String get name => 'base';
  String get displayName => 'Base Metadata Provider';
  String get description => 'Base metadata provider. Not implemented.';
  String get logoURL => 'about:blank';
  String get iconURL => 'about:blank';
  String get providerId => name.toLowerCase();

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

  /// Get track information by ID
  Future<GenericSong> getTrackInfo(
    String trackId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => throw UnimplementedError('getTrackInfo not supported by $name');

  Future<GenericSong?> getCachedTrackInfo(String trackId) async => null;

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

  Future<void> deletePlaylist(String playlistId) async {}

  Future<void> addTracksToPlaylist(String playlistId, List<String> trackIds) async {}

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

  /// Get user's top tracks
  Future<List<GenericSong>> getUserTopTracks({
    int limit = 20,
    String timeRange = 'short_term',
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

  /// Get current user's profile
  Future<void> fetchUserProfile() async {}

  /// Get user's top artists
  Future<List<GenericSimpleArtist>> getUserTopArtists({
    int limit = 20,
    String timeRange = 'short_term',
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async => const [];

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

  Map<String, dynamic> dumpJson() => {
    'name': name,
    'displayName': displayName,
    'providerId': providerId,
  };
}
