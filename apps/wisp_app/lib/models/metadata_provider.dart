// Copyright © 2026 wizeshi

library;

import 'package:flutter/material.dart';
import 'package:wisp/models/metadata_models.dart';
import 'package:wisp/services/metadata_cache.dart';

abstract class MetadataProvider extends ChangeNotifier {
  String get name => "base";
  String get displayName => "Base Metadata Provider";
  String get description => "Base metadata provider. Not implemented.";
  String get logoURL => "about:blank";
  String get iconURL => "about:blank";

  // State
  final _isAuthenticated = false;
  final _isLoading = false;
  String? _errorMessage;
  String? _userDisplayName;
  String? _userId;
  
  // Getters
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get userDisplayName => _userDisplayName;
  String? get userId => _userId;

  bool isTrackLiked(String trackId) => false;

  Future<void> ensureLikedTracksLoaded();

  void setLikedTracksFromItems(List<PlaylistItem> items);

  Future<void> toggleTrackLike(GenericSong track);

  Future<void> likeTrack(GenericSong track);

  Future<void> unlikeTrack(GenericSong track);

  MetadataProvider();

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Start OAuth login flow
  Future<void> login(BuildContext context);

  /// Logout and clear token
  Future<void> logout();

  /// Get track information by ID
  Future<GenericSong> getTrackInfo(
    String trackId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  Future<GenericSong?> getCachedTrackInfo(String trackId);

  /// Get album information with pagination support
  Future<GenericAlbum> getAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  Future<GenericAlbum?> getCachedAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
  }) ;

  /// Get playlist information with pagination support
  Future<GenericPlaylist> getPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  Future<GenericPlaylist?> getCachedPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
  });

  /// Get full artist information (top tracks + albums)
  Future<GenericArtist> getArtistInfo(
    String artistId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  Future<GenericArtist?> getCachedArtistInfo(String artistId);

  /// Fetch additional tracks for an album (for pagination)
  Future<List<GenericSong>> getMoreAlbumTracks(
    String albumId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  /// Fetch additional tracks for a playlist (for pagination)
  Future<List<PlaylistItem>> getMorePlaylistTracks(
    String playlistId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  /// Get user's saved playlists
  Future<List<GenericPlaylist>> getUserPlaylists({
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  /// Get user's saved tracks (liked songs)
  Future<List<PlaylistItem>> getUserSavedTracks({
    int limit = 50,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  Future<List<PlaylistItem>> getUserSavedTracksAll({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  Future<List<PlaylistItem>?> getCachedSavedTracksAll();

  Future<void> refreshSavedTracksAll();

  Future<String> createPlaylist({
    required String name,
    String? description,
    bool isPublic = false,
  });

  Future<void> renamePlaylist(String playlistId, String name);

  Future<void> deletePlaylist(String playlistId);

  Future<void> addTracksToPlaylist(
    String playlistId,
    List<String> trackIds,
  );

  /// Get user's saved albums
  Future<List<GenericAlbum>> getUserAlbums({
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  /// Get user's followed artists
  Future<List<GenericSimpleArtist>> getUserFollowedArtists({
    int limit = 20,
    String? after,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  /// Get user's top tracks
  Future<List<GenericSong>> getUserTopTracks({
    int limit = 20,
    String timeRange = 'short_term', // short_term, medium_term, long_term
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  /// Get current user's profile
  Future<void> fetchUserProfile();

  /// Get user's top artists
  Future<List<GenericSimpleArtist>> getUserTopArtists({
    int limit = 20,
    String timeRange = 'short_term', // short_term, medium_term, long_term
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  /// Search for tracks, artists, albums, and playlists
  Future<SearchResults> search(
    String query, {
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  });

  Map<String, dynamic> dumpJson();
}

