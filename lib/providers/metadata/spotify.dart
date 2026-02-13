/// Spotify authentication and metadata provider
/// Implements OAuth 2.0 Authorization Code flow with auto-refresh
/// Provides methods to fetch track, album, and playlist metadata
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import '../../services/credentials.dart';
import '../../services/metadata_cache.dart';
import '../../models/metadata_models.dart';
import '../../models/spotify_converters.dart';
import 'dart:io' show Platform;
import '../../utils/logger.dart';

// Custom exceptions
class SpotifyAuthException implements Exception {
  final String message;
  SpotifyAuthException(this.message);
  @override
  String toString() => 'Spotify Authentication Error: $message';
}

class SpotifyNetworkException implements Exception {
  final String message;
  SpotifyNetworkException(this.message);
  @override
  String toString() => 'Spotify Network Error: $message';
}

class SpotifyCredentialsException implements Exception {
  final String message;
  SpotifyCredentialsException(this.message);
  @override
  String toString() => 'Spotify Credentials Error: $message';
}

class SpotifyProvider extends ChangeNotifier {
  final CredentialsService _credentialsService = CredentialsService();
  Timer? _tokenRefreshTimer;
  final MetadataCacheStore _metadataCache = MetadataCacheStore.instance;
  static const String _metadataProvider = 'spotify';
  
  // State
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _userDisplayName;
  String? _userId;

  // Spotify API constants
  static const String _baseUrl = 'https://api.spotify.com/v1';
  static const String _authUrl = 'https://accounts.spotify.com/authorize';
  static const String _tokenUrl = 'https://accounts.spotify.com/api/token';
  
  // Redirect URI - use 127.0.0.1 which Spotify accepts as secure
  static const String _redirectUriDesktop = 'http://127.0.0.1:43823';
  static const String _redirectUriMobile = 'wisp-login://auth';
  
  String get _redirectUri {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      return _redirectUriDesktop;
    } else {
      return _redirectUriMobile;
    }
  }
  
  String get _callbackScheme {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      return 'http://127.0.0.1:43823';
    } else {
      return 'wisp-login';
    }
  }
  
  static const List<String> _scopes = [
    'user-library-read',
    'user-library-modify',
    'playlist-read-private',
    'user-follow-read',
    'user-top-read',
  ];

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get userDisplayName => _userDisplayName;
  String? get userId => _userId;

  final Set<String> _likedTrackIds = {};
  bool _likedTracksLoaded = false;

  bool isTrackLiked(String trackId) => _likedTrackIds.contains(trackId);

  Future<void> ensureLikedTracksLoaded() async {
    if (_likedTracksLoaded) return;
    final cached = await getCachedSavedTracksAll();
    if (cached != null) {
      _setLikedTracksFromItems(cached);
      return;
    }
    _likedTracksLoaded = true;
    notifyListeners();
  }

  void setLikedTracksFromItems(List<PlaylistItem> items) {
    _setLikedTracksFromItems(items);
  }

  void _setLikedTracksFromItems(List<PlaylistItem> items) {
    _likedTrackIds
      ..clear()
      ..addAll(items.map((item) => item.id));
    _likedTracksLoaded = true;
    notifyListeners();
  }

  Future<void> toggleTrackLike(GenericSong track) async {
    if (track.source != SongSource.spotify) return;
    if (isTrackLiked(track.id)) {
      await unlikeTrack(track);
    } else {
      await likeTrack(track);
    }
  }

  Future<void> likeTrack(GenericSong track) async {
    if (track.source != SongSource.spotify) return;
    await _makeApiRequestWithBody(
      '/me/tracks?ids=${Uri.encodeQueryComponent(track.id)}',
      method: 'PUT',
    );
    _likedTrackIds.add(track.id);
    await _updateSavedTracksCacheOnLike(track);
    notifyListeners();
  }

  Future<void> unlikeTrack(GenericSong track) async {
    if (track.source != SongSource.spotify) return;
    await _makeApiRequestWithBody(
      '/me/tracks?ids=${Uri.encodeQueryComponent(track.id)}',
      method: 'DELETE',
    );
    _likedTrackIds.remove(track.id);
    await _updateSavedTracksCacheOnUnlike(track.id);
    notifyListeners();
  }

  PlaylistItem _playlistItemFromSong(GenericSong song) {
    return PlaylistItem(
      id: song.id,
      source: song.source,
      title: song.title,
      artists: song.artists,
      thumbnailUrl: song.thumbnailUrl,
      explicit: song.explicit,
      album: song.album,
      durationSecs: song.durationSecs,
      addedAt: DateTime.now(),
      trackNumber: 1,
    );
  }

  Future<void> _updateSavedTracksCacheOnLike(GenericSong song) async {
    final entry =
        await _readCacheEntry(type: 'saved_tracks_all', id: 'all');
    if (entry == null) return;
    final items = entry.payload['items'] as List?;
    if (items == null) return;
    final parsed = items
        .whereType<Map<String, dynamic>>()
        .map(PlaylistItem.fromJson)
        .toList();
    if (parsed.any((item) => item.id == song.id)) return;
    parsed.insert(0, _playlistItemFromSong(song));
    await _writeCacheEntry(
      type: 'saved_tracks_all',
      id: 'all',
      payload: {'items': parsed.map((item) => item.toJson()).toList()},
    );
  }

  Future<void> _updateSavedTracksCacheOnUnlike(String trackId) async {
    final entry =
        await _readCacheEntry(type: 'saved_tracks_all', id: 'all');
    if (entry == null) return;
    final items = entry.payload['items'] as List?;
    if (items == null) return;
    final parsed = items
        .whereType<Map<String, dynamic>>()
        .map(PlaylistItem.fromJson)
        .toList();
    final next = parsed.where((item) => item.id != trackId).toList();
    if (next.length == parsed.length) return;
    await _writeCacheEntry(
      type: 'saved_tracks_all',
      id: 'all',
      payload: {'items': next.map((item) => item.toJson()).toList()},
    );
  }

  Future<MetadataCacheEntry?> _readCacheEntry({
    required String type,
    required String id,
    String? pageKey,
  }) {
    return _metadataCache.readEntry(
      provider: _metadataProvider,
      type: type,
      id: id,
      pageKey: pageKey,
    );
  }

  Future<void> _writeCacheEntry({
    required String type,
    required String id,
    required Map<String, dynamic> payload,
    String? pageKey,
  }) {
    return _metadataCache.writeEntry(
      provider: _metadataProvider,
      type: type,
      id: id,
      pageKey: pageKey,
      payload: payload,
    );
  }

  Future<T> _getWithCache<T>({
    required String type,
    required String id,
    String? pageKey,
    required MetadataFetchPolicy policy,
    required Future<T> Function() fetcher,
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    MetadataCacheEntry? entry;
    T? cached;
    try {
      entry = await _readCacheEntry(type: type, id: id, pageKey: pageKey);
      if (entry != null) {
        cached = fromJson(entry.payload);
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
            pageKey: pageKey,
            payload: toJson(fresh),
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
        pageKey: pageKey,
        payload: toJson(fresh),
      );
      return fresh;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<T>> _getListWithCache<T>({
    required String type,
    required String id,
    String? pageKey,
    required MetadataFetchPolicy policy,
    required Future<List<T>> Function() fetcher,
    required Map<String, dynamic> Function(T) itemToJson,
    required T Function(Map<String, dynamic>) itemFromJson,
  }) async {
    MetadataCacheEntry? entry;
    List<T>? cached;
    try {
      entry = await _readCacheEntry(type: type, id: id, pageKey: pageKey);
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
            pageKey: pageKey,
            payload: {
              'items': fresh.map(itemToJson).toList(),
            },
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
        pageKey: pageKey,
        payload: {
          'items': fresh.map(itemToJson).toList(),
        },
      );
      return fresh;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  SpotifyProvider() {
    _initializeAuthState();
  }

  /// Initialize authentication state on startup
  Future<void> _initializeAuthState() async {
    try {
      logger.d('Spotify: Initializing auth state...');
      final token = await _credentialsService.getSpotifyToken();
      if (token != null) {
        if (token.isExpired) {
          try {
            await _refreshToken();
          } catch (_) {
            // fall through, auth state will be false below
          }
        } else {
          _scheduleTokenRefresh(token);
        }
      }
      _isAuthenticated = await _credentialsService.hasValidSpotifyToken();
      logger.d('Spotify: Initial auth state: $_isAuthenticated');
      if (_isAuthenticated) {
        await ensureLikedTracksLoaded();
        unawaited(refreshSavedTracksAll());
      }
      notifyListeners();
    } catch (e) {
      logger.e('Spotify: Failed to initialize auth state', error: e);
      _errorMessage = 'Failed to initialize auth state: $e';
      notifyListeners();
    }
  }

  /// Publicly accessible method to re-check auth state
  Future<void> checkAuthState() async {
    logger.d('Spotify: Re-checking auth state...');
    await _initializeAuthState();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Start OAuth login flow
  Future<void> login() async {
    _setLoading(true);
    clearError();

    try {
      // Get credentials
      final credentials = await _credentialsService.getSpotifyCredentials();
      if (credentials == null) {
        throw SpotifyCredentialsException(
          'Spotify Client ID and Secret not configured. Please set them in settings.',
        );
      }

      // Build authorization URL
      final authParams = {
        'client_id': credentials.clientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'scope': _scopes.join(' '),
        'show_dialog': 'true',
      };

      logger.d('Spotify: Redirect URI: $_redirectUri');

      final authUri = Uri.parse(_authUrl).replace(
        queryParameters: authParams,
      );

      logger.d('Spotify: Callback Scheme: $_callbackScheme');

      // Open browser for OAuth
      final result = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: _callbackScheme,
      );

      // Extract authorization code from callback
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) {
        throw SpotifyAuthException('No authorization code received');
      }

      // Exchange code for access token
      await _requestToken(code, credentials);

      _isAuthenticated = true;
      _setLoading(false);
    } on SpotifyCredentialsException catch (e) {
      _errorMessage = e.message;
      _setLoading(false);
      rethrow;
    } on SpotifyAuthException catch (e) {
      _errorMessage = e.message;
      _setLoading(false);
      rethrow;
    } catch (e) {
      _errorMessage = 'Login failed: $e';
      _setLoading(false);
      throw SpotifyAuthException('Login failed: $e');
    }
  }

  /// Exchange authorization code for access token
  Future<void> _requestToken(
    String code,
    SpotifyCredentials credentials,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Basic ${base64Encode(
            utf8.encode('${credentials.clientId}:${credentials.clientSecret}'),
          )}',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redirectUri,
        },
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          'Token request failed: ${response.statusCode} ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = SpotifyToken(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        expiresAt: DateTime.now().add(
          Duration(seconds: data['expires_in'] as int),
        ),
      );

      await _credentialsService.saveSpotifyToken(token);
      _scheduleTokenRefresh(token);
    } catch (e) {
      throw SpotifyAuthException('Failed to exchange token: $e');
    }
  }

  /// Refresh access token using refresh token
  Future<void> _refreshToken() async {
    try {
      final credentials = await _credentialsService.getSpotifyCredentials();
      if (credentials == null) {
        throw SpotifyCredentialsException('Credentials not found');
      }

      final token = await _credentialsService.getSpotifyToken();
      if (token == null) {
        throw SpotifyAuthException('No token to refresh');
      }

      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Basic ${base64Encode(
            utf8.encode('${credentials.clientId}:${credentials.clientSecret}'),
          )}',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': token.refreshToken,
        },
      );

      if (response.statusCode != 200) {
        throw SpotifyAuthException(
          'Token refresh failed: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final newToken = SpotifyToken(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String? ?? token.refreshToken,
        expiresAt: DateTime.now().add(
          Duration(seconds: data['expires_in'] as int),
        ),
      );

      await _credentialsService.saveSpotifyToken(newToken);
      _scheduleTokenRefresh(newToken);
      _isAuthenticated = true;
      notifyListeners();
    } catch (e) {
      _isAuthenticated = false;
      notifyListeners();
      throw SpotifyAuthException('Failed to refresh token: $e');
    }
  }

  /// Ensure we have a valid token before making API calls
  Future<String> _ensureValidToken() async {
    final token = await _credentialsService.getSpotifyToken();
    
    if (token == null) {
      throw SpotifyAuthException('Not authenticated. Please login first.');
    }

    if (token.isExpired) {
      await _refreshToken();
      final refreshedToken = await _credentialsService.getSpotifyToken();
      if (refreshedToken == null) {
        throw SpotifyAuthException('Failed to refresh token');
      }
      return refreshedToken.accessToken;
    }

    return token.accessToken;
  }

  /// Logout and clear token
  Future<void> logout() async {
    try {
      _tokenRefreshTimer?.cancel();
      await _credentialsService.clearSpotifyToken();
      _isAuthenticated = false;
      clearError();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Logout failed: $e';
      notifyListeners();
    }
  }

  void _scheduleTokenRefresh(SpotifyToken token) {
    _tokenRefreshTimer?.cancel();
    final now = DateTime.now();
    final refreshAt = token.expiresAt.subtract(const Duration(minutes: 2));
    final delay = refreshAt.difference(now);

    if (delay.isNegative) {
      Timer.run(() async {
        try {
          await _refreshToken();
        } catch (_) {}
      });
      return;
    }

    _tokenRefreshTimer = Timer(delay, () async {
      try {
        await _refreshToken();
      } catch (_) {}
    });
  }

  /// Make authenticated API request
  Future<Map<String, dynamic>> _makeApiRequest(String endpoint) async {
    try {
      logger.d('Spotify: Making API request to: $endpoint');
      final accessToken = await _ensureValidToken();
      logger.d('Spotify: Got access token');
      
      final response = await http.get(
        Uri.parse('$_baseUrl$endpoint'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      logger.d('Spotify: Response status: ${response.statusCode}');

      if (response.statusCode == 401) {
        logger.d('Spotify: Got 401, refreshing token...');
        // Token might be invalid, try refreshing
        await _refreshToken();
        final newAccessToken = await _ensureValidToken();
        
        final retryResponse = await http.get(
          Uri.parse('$_baseUrl$endpoint'),
          headers: {
            'Authorization': 'Bearer $newAccessToken',
            'Content-Type': 'application/json',
          },
        );
        
        logger.d('Spotify: Retry response status: ${retryResponse.statusCode}');
        
        if (retryResponse.statusCode != 200) {
          logger.e('Spotify: Retry failed with ${retryResponse.statusCode}: ${retryResponse.body}');
          throw SpotifyNetworkException(
            'API request failed: ${retryResponse.statusCode}',
          );
        }
        
        return jsonDecode(retryResponse.body) as Map<String, dynamic>;
      }

      if (response.statusCode != 200) {
        logger.e('Spotify: Request failed with ${response.statusCode}: ${response.body}');
        throw SpotifyNetworkException(
          'API request failed: ${response.statusCode} - ${response.body}',
        );
      }

      logger.d('Spotify: Request successful');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      logger.e('Spotify: Exception in _makeApiRequest', error: e);
      if (e is SpotifyAuthException ||
          e is SpotifyNetworkException ||
          e is SpotifyCredentialsException) {
        rethrow;
      }
      throw SpotifyNetworkException('Network request failed: $e');
    }
  }

  Future<Map<String, dynamic>> _makeApiRequestWithBody(
    String endpoint, {
    required String method,
    Map<String, dynamic>? body,
  }) async {
    try {
      logger.d('Spotify: Making API request to: $endpoint ($method)');
      final accessToken = await _ensureValidToken();

      Future<http.Response> send(String token) {
        final uri = Uri.parse('$_baseUrl$endpoint');
        final headers = {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        };
        final payload = body != null ? jsonEncode(body) : null;
        switch (method) {
          case 'POST':
            return http.post(uri, headers: headers, body: payload);
          case 'PUT':
            return http.put(uri, headers: headers, body: payload);
          case 'DELETE':
            return http.delete(uri, headers: headers, body: payload);
          default:
            return http.get(uri, headers: headers);
        }
      }

      var response = await send(accessToken);
      logger.d('Spotify: Response status: ${response.statusCode}');

      if (response.statusCode == 401) {
        logger.d('Spotify: Got 401, refreshing token...');
        await _refreshToken();
        final newAccessToken = await _ensureValidToken();
        response = await send(newAccessToken);
        logger.d('Spotify: Retry response status: ${response.statusCode}');
      }

      if (response.statusCode != 200 &&
          response.statusCode != 201 &&
          response.statusCode != 204) {
        logger.e(
          'Spotify: Request failed with ${response.statusCode}: ${response.body}',
        );
        throw SpotifyNetworkException(
          'API request failed: ${response.statusCode} - ${response.body}',
        );
      }

      if (response.statusCode == 204 || response.body.isEmpty) {
        return <String, dynamic>{};
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      logger.e('Spotify: Exception in _makeApiRequestWithBody', error: e);
      if (e is SpotifyAuthException ||
          e is SpotifyNetworkException ||
          e is SpotifyCredentialsException) {
        rethrow;
      }
      throw SpotifyNetworkException('Network request failed: $e');
    }
  }

  /// Get track information by ID
  Future<GenericSong> getTrackInfo(
    String trackId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      return _getWithCache(
        type: 'track',
        id: trackId,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest('/tracks/$trackId');
          return spotifyTrackToGeneric(data);
        },
        toJson: (track) => track.toJson(),
        fromJson: GenericSong.fromJson,
      );
    } catch (e) {
      _errorMessage = 'Failed to fetch track: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<GenericSong?> getCachedTrackInfo(String trackId) async {
    final entry = await _readCacheEntry(type: 'track', id: trackId);
    if (entry == null) return null;
    try {
      return GenericSong.fromJson(entry.payload);
    } catch (_) {
      return null;
    }
  }

  /// Get album information with pagination support
  Future<GenericAlbum> getAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      final pageKey = 'offset_${offset}_limit_$limit';
      return _getWithCache(
        type: 'album',
        id: albumId,
        pageKey: pageKey,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(
            '/albums/$albumId?limit=$limit&offset=$offset',
          );
          return spotifyFullAlbumToGeneric(data, offset: offset, limit: limit);
        },
        toJson: (album) => album.toJson(),
        fromJson: GenericAlbum.fromJson,
      );
    } catch (e) {
      _errorMessage = 'Failed to fetch album: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<GenericAlbum?> getCachedAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
  }) async {
    final pageKey = 'offset_${offset}_limit_$limit';
    final entry = await _readCacheEntry(
      type: 'album',
      id: albumId,
      pageKey: pageKey,
    );
    if (entry == null) return null;
    try {
      return GenericAlbum.fromJson(entry.payload);
    } catch (_) {
      return null;
    }
  }

  /// Get playlist information with pagination support
  Future<GenericPlaylist> getPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      final pageKey = 'offset_${offset}_limit_$limit';
      return _getWithCache(
        type: 'playlist',
        id: playlistId,
        pageKey: pageKey,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(
            '/playlists/$playlistId?limit=$limit&offset=$offset',
          );
          return spotifyFullPlaylistToGeneric(data, offset: offset, limit: limit);
        },
        toJson: (playlist) => playlist.toJson(),
        fromJson: GenericPlaylist.fromJson,
      );
    } catch (e) {
      _errorMessage = 'Failed to fetch playlist: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<GenericPlaylist?> getCachedPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
  }) async {
    final pageKey = 'offset_${offset}_limit_$limit';
    final entry = await _readCacheEntry(
      type: 'playlist',
      id: playlistId,
      pageKey: pageKey,
    );
    if (entry == null) return null;
    try {
      return GenericPlaylist.fromJson(entry.payload);
    } catch (_) {
      return null;
    }
  }

  /// Get full artist information (top tracks + albums)
  Future<GenericArtist> getArtistInfo(
    String artistId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      return _getWithCache(
        type: 'artist',
        id: artistId,
        policy: policy,
        fetcher: () async {
          final artistData = await _makeApiRequest('/artists/$artistId');
          final topTracksData = await _makeApiRequest(
            '/artists/$artistId/top-tracks?market=from_token',
          );
          final albumsData = await _makeApiRequest(
            '/artists/$artistId/albums?include_groups=album,single&limit=50',
          );

          final topTracks = (topTracksData['tracks'] as List? ?? [])
              .map((track) =>
                  spotifyTrackToGeneric(track as Map<String, dynamic>))
              .toList();

          final albumItems = albumsData['items'] as List? ?? [];
          final uniqueAlbums = <String, GenericSimpleAlbum>{};
          for (final item in albumItems) {
            final album = spotifySimplifiedAlbumToGeneric(
              item as Map<String, dynamic>,
            );
            if (album.id.isNotEmpty) {
              uniqueAlbums[album.id] = album;
            }
          }

          return spotifyFullArtistToGeneric(
            artistData,
            topTracks,
            uniqueAlbums.values.toList(),
          );
        },
        toJson: (artist) => artist.toJson(),
        fromJson: GenericArtist.fromJson,
      );
    } catch (e) {
      _errorMessage = 'Failed to fetch artist: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<GenericArtist?> getCachedArtistInfo(String artistId) async {
    final entry = await _readCacheEntry(type: 'artist', id: artistId);
    if (entry == null) return null;
    try {
      return GenericArtist.fromJson(entry.payload);
    } catch (_) {
      return null;
    }
  }

  /// Fetch additional tracks for an album (for pagination)
  Future<List<GenericSong>> getMoreAlbumTracks(
    String albumId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      final pageKey = 'offset_${offset}_limit_$limit';
      return _getListWithCache(
        type: 'album_tracks',
        id: albumId,
        pageKey: pageKey,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(
            '/albums/$albumId/tracks?limit=$limit&offset=$offset',
          );
          final items = data['items'] as List;
          return items.map((track) {
            return spotifyTrackToGeneric(track as Map<String, dynamic>);
          }).toList();
        },
        itemToJson: (track) => track.toJson(),
        itemFromJson: GenericSong.fromJson,
      );
    } catch (e) {
      _errorMessage = 'Failed to fetch more tracks: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Fetch additional tracks for a playlist (for pagination)
  Future<List<PlaylistItem>> getMorePlaylistTracks(
    String playlistId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      final pageKey = 'offset_${offset}_limit_$limit';
      return _getListWithCache(
        type: 'playlist_tracks',
        id: playlistId,
        pageKey: pageKey,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(
            '/playlists/$playlistId/tracks?limit=$limit&offset=$offset',
          );
          final items = data['items'] as List;
          return items.asMap().entries.map((entry) {
            return spotifyPlaylistTrackToPlaylistItem(
              entry.value as Map<String, dynamic>,
              offset + entry.key + 1,
            );
          }).where((item) => item.id.isNotEmpty).toList();
        },
        itemToJson: (item) => item.toJson(),
        itemFromJson: PlaylistItem.fromJson,
      );
    } catch (e) {
      _errorMessage = 'Failed to fetch more tracks: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Get user's saved playlists
  Future<List<GenericPlaylist>> getUserPlaylists({
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      logger.d('Spotify: Fetching user playlists...');
      final cacheId = 'limit_${limit}_offset_$offset';
      return _getListWithCache(
        type: 'user_playlists',
        id: cacheId,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(
            '/me/playlists?limit=$limit&offset=$offset',
          );
          logger.d('Spotify: Playlists response received');
          final items = data['items'] as List;
          logger.d('Spotify: Found ${items.length} playlists');

          return items.map((item) {
            return spotifyFullPlaylistToGeneric(item as Map<String, dynamic>);
          }).toList();
        },
        itemToJson: (item) => item.toJson(),
        itemFromJson: GenericPlaylist.fromJson,
      );
    } catch (e) {
      logger.e('Spotify: Failed to fetch playlists', error: e);
      _errorMessage = 'Failed to fetch playlists: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Get user's saved tracks (liked songs)
  Future<List<PlaylistItem>> getUserSavedTracks({
    int limit = 50,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      final pageKey = 'offset_${offset}_limit_$limit';
      return _getListWithCache(
        type: 'saved_tracks',
        id: 'saved_tracks',
        pageKey: pageKey,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(
            '/me/tracks?limit=$limit&offset=$offset',
          );
          final items = data['items'] as List;
          return items.asMap().entries.map((entry) {
            return spotifySavedTrackToPlaylistItem(
              entry.value as Map<String, dynamic>,
              offset + entry.key + 1,
            );
          }).where((item) => item.id.isNotEmpty).toList();
        },
        itemToJson: (item) => item.toJson(),
        itemFromJson: PlaylistItem.fromJson,
      );
    } catch (e) {
      _errorMessage = 'Failed to fetch saved tracks: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<List<PlaylistItem>> getUserSavedTracksAll({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      final items = await _getListWithCache(
        type: 'saved_tracks_all',
        id: 'all',
        policy: policy,
        fetcher: () async {
          const limit = 50;
          var offset = 0;
          final all = <PlaylistItem>[];
          while (true) {
            final data = await _makeApiRequest(
              '/me/tracks?limit=$limit&offset=$offset',
            );
            final items = data['items'] as List;
            if (items.isEmpty) break;
            all.addAll(
              items.asMap().entries.map((entry) {
                return spotifySavedTrackToPlaylistItem(
                  entry.value as Map<String, dynamic>,
                  offset + entry.key + 1,
                );
              }).where((item) => item.id.isNotEmpty),
            );
            if (items.length < limit) break;
            offset += items.length;
          }
          return all;
        },
        itemToJson: (item) => item.toJson(),
        itemFromJson: PlaylistItem.fromJson,
      );
      _likedTrackIds
        ..clear()
        ..addAll(items.map((item) => item.id));
      _likedTracksLoaded = true;
      notifyListeners();
      return items;
    } catch (e) {
      _errorMessage = 'Failed to fetch saved tracks: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<List<PlaylistItem>?> getCachedSavedTracksAll() async {
    final entry = await _readCacheEntry(type: 'saved_tracks_all', id: 'all');
    if (entry == null) return null;
    final items = entry.payload['items'] as List?;
    if (items == null) return null;
    try {
      return items
          .whereType<Map<String, dynamic>>()
          .map(PlaylistItem.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<PlaylistItem>?> _getCachedSavedTracksPage({
    required int limit,
    required int offset,
  }) async {
    final pageKey = 'offset_${offset}_limit_$limit';
    final entry = await _readCacheEntry(
      type: 'saved_tracks',
      id: 'saved_tracks',
      pageKey: pageKey,
    );
    if (entry == null) return null;
    final items = entry.payload['items'] as List?;
    if (items == null) return null;
    try {
      return items
          .whereType<Map<String, dynamic>>()
          .map(PlaylistItem.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  bool _savedTracksPageMatches(
    List<PlaylistItem> fresh,
    List<PlaylistItem>? cached,
  ) {
    if (cached == null) return false;
    if (fresh.length != cached.length) return false;
    for (var i = 0; i < fresh.length; i++) {
      if (fresh[i].id != cached[i].id) return false;
    }
    return true;
  }

  Future<void> refreshSavedTracksAll() async {
    try {
      const limit = 50;
      var offset = 0;
      final cachedAll = await getCachedSavedTracksAll() ?? <PlaylistItem>[];
      final merged = <PlaylistItem>[];

      while (true) {
        final data = await _makeApiRequest(
          '/me/tracks?limit=$limit&offset=$offset',
        );
        final items = data['items'] as List;
        if (items.isEmpty) break;

        final pageItems = items.asMap().entries.map((entry) {
          return spotifySavedTrackToPlaylistItem(
            entry.value as Map<String, dynamic>,
            offset + entry.key + 1,
          );
        }).where((item) => item.id.isNotEmpty).toList();

        final cachedPage =
            await _getCachedSavedTracksPage(limit: limit, offset: offset);
        final pageMatches = _savedTracksPageMatches(pageItems, cachedPage);

        await _writeCacheEntry(
          type: 'saved_tracks',
          id: 'saved_tracks',
          pageKey: 'offset_${offset}_limit_$limit',
          payload: {'items': pageItems.map((item) => item.toJson()).toList()},
        );

        merged.addAll(pageItems);

        if (pageMatches) {
          final tailStart = offset + pageItems.length;
          if (tailStart < cachedAll.length) {
            merged.addAll(cachedAll.sublist(tailStart));
          }
          break;
        }

        if (items.length < limit) break;
        offset += items.length;
      }

      if (merged.isNotEmpty) {
        await _writeCacheEntry(
          type: 'saved_tracks_all',
          id: 'all',
          payload: {'items': merged.map((item) => item.toJson()).toList()},
        );
        _likedTrackIds
          ..clear()
          ..addAll(merged.map((item) => item.id));
        _likedTracksLoaded = true;
        notifyListeners();
      }
    } catch (_) {
      // silent refresh
    }
  }

  Future<String> createPlaylist({
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    try {
      final id = _userId;
      if (id == null || id.isEmpty) {
        await fetchUserProfile();
      }
      final userId = _userId;
      if (userId == null || userId.isEmpty) {
        throw SpotifyNetworkException('Missing Spotify user ID');
      }
      final payload = {
        'name': name,
        'public': isPublic,
        if (description != null) 'description': description,
      };
      final data = await _makeApiRequestWithBody(
        '/users/$userId/playlists',
        method: 'POST',
        body: payload,
      );
      return data['id'] as String;
    } catch (e) {
      _errorMessage = 'Failed to create playlist: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    try {
      await _makeApiRequestWithBody(
        '/playlists/$playlistId',
        method: 'PUT',
        body: {'name': name},
      );
    } catch (e) {
      _errorMessage = 'Failed to rename playlist: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    try {
      await _makeApiRequestWithBody(
        '/playlists/$playlistId/followers',
        method: 'DELETE',
      );
    } catch (e) {
      _errorMessage = 'Failed to delete playlist: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addTracksToPlaylist(
    String playlistId,
    List<String> trackIds,
  ) async {
    if (trackIds.isEmpty) return;
    try {
      final uris = trackIds.map((id) => 'spotify:track:$id').toList();
      await _makeApiRequestWithBody(
        '/playlists/$playlistId/tracks',
        method: 'POST',
        body: {'uris': uris},
      );
    } catch (e) {
      _errorMessage = 'Failed to add tracks: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Get user's saved albums
  Future<List<GenericAlbum>> getUserAlbums({
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      logger.d('Spotify: Fetching user albums...');
      final cacheId = 'limit_${limit}_offset_$offset';
      return _getListWithCache(
        type: 'user_albums',
        id: cacheId,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(
            '/me/albums?limit=$limit&offset=$offset',
          );
          logger.d('Spotify: Albums response received');
          final items = data['items'] as List;
          logger.d('Spotify: Found ${items.length} albums');

          return items.map((item) {
            final albumData = item['album'] as Map<String, dynamic>;
            return spotifyFullAlbumToGeneric(albumData);
          }).toList();
        },
        itemToJson: (item) => item.toJson(),
        itemFromJson: GenericAlbum.fromJson,
      );
    } catch (e) {
      logger.e('Spotify: Failed to fetch albums', error: e);
      _errorMessage = 'Failed to fetch albums: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Get user's followed artists
  Future<List<GenericSimpleArtist>> getUserFollowedArtists({
    int limit = 20,
    String? after,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      logger.d('Spotify: Fetching followed artists...');
      String endpoint = '/me/following?type=artist&limit=$limit';
      if (after != null) {
        endpoint += '&after=$after';
      }
      final cacheId = 'limit_${limit}_after_${after ?? ""}';
      return _getListWithCache(
        type: 'user_followed_artists',
        id: cacheId,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(endpoint);
          logger.d('Spotify: Followed artists response received');
          final artists = data['artists']?['items'] as List? ?? [];
          logger.d('Spotify: Found ${artists.length} followed artists');

          return artists.map((artist) {
            return spotifyArtistToGeneric(artist as Map<String, dynamic>);
          }).toList();
        },
        itemToJson: (item) => item.toJson(),
        itemFromJson: GenericSimpleArtist.fromJson,
      );
    } catch (e) {
      logger.e('Spotify: Failed to fetch followed artists', error: e);
      _errorMessage = 'Failed to fetch followed artists: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Get user's top tracks
  Future<List<GenericSong>> getUserTopTracks({
    int limit = 20,
    String timeRange = 'short_term', // short_term, medium_term, long_term
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      logger.d('Spotify: Fetching top tracks...');
      final cacheId = 'limit_${limit}_range_$timeRange';
      return _getListWithCache(
        type: 'user_top_tracks',
        id: cacheId,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(
            '/me/top/tracks?limit=$limit&time_range=$timeRange',
          );
          logger.d('Spotify: Top tracks response received');
          final items = data['items'] as List;
          logger.d('Spotify: Found ${items.length} top tracks');

          return items.map((track) {
            return spotifyTrackToGeneric(track as Map<String, dynamic>);
          }).toList();
        },
        itemToJson: (item) => item.toJson(),
        itemFromJson: GenericSong.fromJson,
      );
    } catch (e) {
      logger.e('Spotify: Failed to fetch top tracks', error: e);
      _errorMessage = 'Failed to fetch top tracks: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Get current user's profile
  Future<void> fetchUserProfile() async {
    try {
      logger.d('Spotify: Fetching user profile...');
      final data = await _makeApiRequest('/me');
      logger.d('Spotify: User profile response received');
      _userDisplayName = data['display_name'] as String?;
      _userId = data['id'] as String?;
      logger.d('Spotify: User display name: $_userDisplayName');
      notifyListeners();
    } catch (e) {
      logger.e('Spotify: Failed to fetch user profile', error: e);
      _errorMessage = 'Failed to fetch user profile: $e';
      notifyListeners();
    }
  }

  /// Get user's top artists
  Future<List<GenericSimpleArtist>> getUserTopArtists({
    int limit = 20,
    String timeRange = 'short_term', // short_term, medium_term, long_term
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      logger.d('Spotify: Fetching top artists...');
      final cacheId = 'limit_${limit}_range_$timeRange';
      return _getListWithCache(
        type: 'user_top_artists',
        id: cacheId,
        policy: policy,
        fetcher: () async {
          final data = await _makeApiRequest(
            '/me/top/artists?limit=$limit&time_range=$timeRange',
          );
          logger.d('Spotify: Top artists response received');
          final items = data['items'] as List;
          logger.d('Spotify: Found ${items.length} top artists');

          return items.map((artist) {
            return spotifyArtistToGeneric(artist as Map<String, dynamic>);
          }).toList();
        },
        itemToJson: (item) => item.toJson(),
        itemFromJson: GenericSimpleArtist.fromJson,
      );
    } catch (e) {
      logger.e('Spotify: Failed to fetch top artists', error: e);
      _errorMessage = 'Failed to fetch top artists: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Search for tracks, artists, albums, or playlists
  Future<List<dynamic>> search(
    String query, {
    required String type, // track, artist, album, playlist
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      final cacheId = 'query_${query}_limit_${limit}_offset_${offset}';
      final cacheType = 'search_$type';
      switch (type) {
        case 'track':
          return _getListWithCache<GenericSong>(
            type: cacheType,
            id: cacheId,
            policy: policy,
            fetcher: () async {
              final encodedQuery = Uri.encodeQueryComponent(query);
              final data = await _makeApiRequest(
                '/search?q=$encodedQuery&type=$type&limit=$limit&offset=$offset',
              );
              final items = data['tracks']?['items'] as List? ?? [];
              return items
                  .where((track) => track != null)
                  .map((track) {
                return spotifyTrackToGeneric(track as Map<String, dynamic>);
              }).toList();
            },
            itemToJson: (item) => item.toJson(),
            itemFromJson: GenericSong.fromJson,
          );
        case 'artist':
          return _getListWithCache<GenericSimpleArtist>(
            type: cacheType,
            id: cacheId,
            policy: policy,
            fetcher: () async {
              final encodedQuery = Uri.encodeQueryComponent(query);
              final data = await _makeApiRequest(
                '/search?q=$encodedQuery&type=$type&limit=$limit&offset=$offset',
              );
              final items = data['artists']?['items'] as List? ?? [];
              return items
                  .where((artist) => artist != null)
                  .map((artist) {
                return spotifyArtistToGeneric(artist as Map<String, dynamic>);
              }).toList();
            },
            itemToJson: (item) => item.toJson(),
            itemFromJson: GenericSimpleArtist.fromJson,
          );
        case 'album':
          return _getListWithCache<GenericAlbum>(
            type: cacheType,
            id: cacheId,
            policy: policy,
            fetcher: () async {
              final encodedQuery = Uri.encodeQueryComponent(query);
              final data = await _makeApiRequest(
                '/search?q=$encodedQuery&type=$type&limit=$limit&offset=$offset',
              );
              final items = data['albums']?['items'] as List? ?? [];
              return items
                  .where((album) => album != null)
                  .map((album) {
                return spotifyFullAlbumToGeneric(album as Map<String, dynamic>);
              }).toList();
            },
            itemToJson: (item) => item.toJson(),
            itemFromJson: GenericAlbum.fromJson,
          );
        case 'playlist':
          return _getListWithCache<GenericPlaylist>(
            type: cacheType,
            id: cacheId,
            policy: policy,
            fetcher: () async {
              final encodedQuery = Uri.encodeQueryComponent(query);
              final data = await _makeApiRequest(
                '/search?q=$encodedQuery&type=$type&limit=$limit&offset=$offset',
              );
              final items = data['playlists']?['items'] as List? ?? [];
              return items
                  .where((playlist) => playlist != null)
                  .map((playlist) {
                return spotifyFullPlaylistToGeneric(
                  playlist as Map<String, dynamic>,
                );
              }).toList();
            },
            itemToJson: (item) => item.toJson(),
            itemFromJson: GenericPlaylist.fromJson,
          );
        default:
          return [];
      }
    } catch (e) {
      _errorMessage = 'Search failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Helper to set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}

