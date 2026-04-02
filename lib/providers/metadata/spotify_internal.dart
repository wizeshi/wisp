// New implementation of the Spotify provider.
// This one uses Spotify's internal API, since the SDK is unusable as of March 9th, 2026.
// This one is more flexible, faster and more reliable than the old one,
// but it also requires more work to implement.
// This one requires the user to log in to their Spotify account in-app (through a webview),
// instead of opening the browser, which is a bit of a hassle, but we need it to
// get the proper cookies, to then fetch tokens to access the internal API.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/material.dart';
import 'package:wisp/models/metadata_models.dart';
import 'package:wisp/models/metadata_provider.dart';
import 'package:wisp/providers/preferences/preferences_provider.dart';
import 'package:wisp/services/metadata_cache.dart';
import 'package:wisp/services/spotify/spotify_audio_key_session_manager.dart';
import 'package:wisp/widgets/spotify_webview.dart';
import 'package:wisp/services/credentials.dart';
import 'package:wisp/utils/logger.dart';
import 'package:wisp/models/spotify_internal_converters.dart';

class SpotifyInternalProvider extends MetadataProvider {
  @override
  String get name => 'Spotify (Internal)';

  final CredentialsService _credentialsService = CredentialsService();
  final MetadataCacheStore _metadataCache = MetadataCacheStore.instance;
  static const String _metadataProvider = "spotify_internal";

  String? _bearerToken;
  String? _clientToken;
  String? _userId;
  String? _userDisplayName;

  final Set<String> _likedTrackIds = {};
  bool _likedTracksLoaded = false;
  int? _likedTracksTotalCount;
  bool _isRefreshingLikedTracks = false;
  final Map<String, String?> _canvasUrlCache = {};

  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;
  Future<void>? _authInitInFlight;
  DateTime? _lastAuthInitAttemptAt;
  bool _lastAuthInitFailed = false;
  int _startupAuthRetryCount = 0;
  bool _startupAuthRetryScheduled = false;

  static const Duration _authInitCooldown = Duration(seconds: 45);
  static const Duration _authInitFailureCooldown = Duration(seconds: 4);
  static const Duration _tokenRequestTimeout = Duration(seconds: 12);
  static const int _tokenRequestMaxAttempts = 2;
  static const int _maxStartupAuthRetries = 2;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get userId => _userId;

  @override
  String? get userDisplayName => _userDisplayName;

  int? get likedTracksTotalCount => _likedTracksTotalCount;

  @override
  bool isTrackLiked(String trackId) => _likedTrackIds.contains(trackId);

  SpotifyInternalProvider() {
    _initializeAuthState();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  Future<void> ensureLikedTracksLoaded() async {
    if (_likedTracksLoaded) return;

    final cached = await _getCachedSavedTracksPage(limit: 50, offset: 0);
    if (cached != null) {
      _setLikedTracksFromItems(cached);
      unawaited(_refreshLikedTracksPage0());
      return;
    }

    try {
      final fresh = await getUserSavedTracks(
        limit: 50,
        offset: 0,
        policy: MetadataFetchPolicy.refreshIfExpired,
      );
      _setLikedTracksFromItems(fresh);
      unawaited(_refreshLikedTracksPage0());
    } catch (_) {
      _likedTracksLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _refreshLikedTracksPage0() async {
    if (_isRefreshingLikedTracks) return;
    _isRefreshingLikedTracks = true;
    try {
      final fresh = await getUserSavedTracks(
        limit: 50,
        offset: 0,
        policy: MetadataFetchPolicy.refreshAlways,
      );
      if (fresh.isNotEmpty) {
        _setLikedTracksFromItems(fresh);
      }
    } catch (_) {
      // Silent refresh; cached data remains.
    } finally {
      _isRefreshingLikedTracks = false;
    }
  }

  @override
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

  @override
  Future<void> login(BuildContext context) async {
    _setLoading(true);
    clearError();

    try {
      final result = await Navigator.of(context).push<Map<String, String>>(
        MaterialPageRoute(
          builder: (_) => const SpotifyWebview(
            initialUrl: 'https://accounts.spotify.com/en/login',
          ),
          fullscreenDialog: true,
        ),
      );

      if (result != null && result.isNotEmpty) {
        await _credentialsService.saveSpotifyCookies(result);

        final fullCookieString = result.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
        // We are re-purposing the lyrics cookie storage for the full cookie string for now.
        await _credentialsService.saveSpotifyLyricsCookie(fullCookieString);

        // Acquire access + client tokens using saved cookies
        final cookie = await _credentialsService.getSpotifyLyricsCookie();
        if (cookie != null && cookie.isNotEmpty) {
          try {
            await _acquireTokensFromCookie(cookie);
            await _syncAudioSessionContext(cookie: cookie);
          } catch (e) {
            logger.w('[Metadata/Spotify-Internal] Token exchange failed: $e');
          }
        }
      } else {
        throw StateError(
          '[Metadata/Spotify-Internal] User cancelled or no cookies found',
        );
      }

      _isAuthenticated = true;
      logger.d("[Metadata/Spotify-Internal] Login successful, authenticated.");
      _setLoading(false);
    } catch (e) {
      _errorMessage = '[Metadata/Spotify-Internal] Login failed: $e';
      logger.d(_errorMessage);
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  @override
  Future<void> logout() async {
    _setLoading(true);
    clearError();

    try {
      await _credentialsService.clearSpotifyCookies();
      await SpotifyAudioKeySessionManager.instance.clear();
      _isAuthenticated = false;
      _bearerToken = null;
      _clientToken = null;
    } catch (e) {
      _errorMessage = '[Metadata/Spotify-Internal] Logout failed: $e';
      logger.d(_errorMessage);
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  /// Initialize authentication state on startup
  Future<void> _initializeAuthState({bool force = false}) async {
    if (!force &&
        _isAuthenticated &&
        _bearerToken != null &&
        _clientToken != null) {
      return;
    }

    final inflight = _authInitInFlight;
    if (inflight != null) {
      await inflight;
      return;
    }

    final now = DateTime.now();
    if (!force && _lastAuthInitAttemptAt != null) {
      final sinceLastAttempt = now.difference(_lastAuthInitAttemptAt!);
      final cooldown = _lastAuthInitFailed
          ? _authInitFailureCooldown
          : _authInitCooldown;
      if (sinceLastAttempt < cooldown) {
        logger.d(
          '[Metadata/Spotify-Internal] Skipping auth re-init (cooldown: ${cooldown.inSeconds}s).',
        );
        return;
      }
    }

    _lastAuthInitAttemptAt = now;
    final future = _initializeAuthStateInternal();
    _authInitInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_authInitInFlight, future)) {
        _authInitInFlight = null;
      }
    }
  }

  Future<void> _initializeAuthStateInternal() async {
    try {
      logger.d('[Metadata/Spotify-Internal] Initializing auth state...');
      final cookie = await _credentialsService.getSpotifyLyricsCookie();

      if (cookie != null && cookie.isNotEmpty) {
        try {
          await _acquireTokensFromCookie(cookie);
          await _syncAudioSessionContext(cookie: cookie);
          logger.d(
            '[Metadata/Spotify-Internal] Token exchange successful, user is authenticated.',
          );
          _isAuthenticated = true;
          _lastAuthInitFailed = false;
          _startupAuthRetryCount = 0;
          _startupAuthRetryScheduled = false;
        } catch (e) {
          logger.w(
            '[Metadata/Spotify-Internal] Token refresh failed on startup',
            error: e,
          );
          _isAuthenticated = false;
          _bearerToken = null;
          _clientToken = null;
          _lastAuthInitFailed = true;
          _scheduleStartupAuthRetry(e);
        }
      } else {
        _isAuthenticated = false;
        _lastAuthInitFailed = true;
      }

      logger.d(
        '[Metadata/Spotify-Internal] Initial auth state: $_isAuthenticated',
      );
      if (_isAuthenticated) {
        await ensureLikedTracksLoaded();
      }
      notifyListeners();
    } catch (e) {
      logger.e(
        '[Metadata/Spotify-Internal] Failed to initialize auth state',
        error: e,
      );
      _errorMessage =
          '[Metadata/Spotify-Internal] Failed to initialize auth state: $e';
      _lastAuthInitFailed = true;
      notifyListeners();
    }
  }

  bool _isTransientAuthError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('timeoutexception') ||
        message.contains('future not completed') ||
        message.contains('socketexception') ||
        message.contains('client token request failed');
  }

  void _scheduleStartupAuthRetry(Object error) {
    if (!_isTransientAuthError(error)) {
      return;
    }

    if (_startupAuthRetryScheduled ||
        _startupAuthRetryCount >= _maxStartupAuthRetries ||
        _isAuthenticated) {
      return;
    }

    _startupAuthRetryScheduled = true;
    final attemptNumber = _startupAuthRetryCount + 1;
    final retryDelay = Duration(seconds: 2 * attemptNumber);

    logger.d(
      '[Metadata/Spotify-Internal] Scheduling startup auth retry $attemptNumber/$_maxStartupAuthRetries in ${retryDelay.inSeconds}s.',
    );

    unawaited(
      Future<void>.delayed(retryDelay, () async {
        _startupAuthRetryScheduled = false;
        if (_isAuthenticated) {
          return;
        }
        _startupAuthRetryCount = attemptNumber;
        await _initializeAuthState(force: true);
      }),
    );
  }

  /// Publicly accessible method to re-check auth state
  Future<void> checkAuthState() async {
    logger.d('[Metadata/Spotify-Internal] Re-checking auth state...');
    await _initializeAuthState(force: false);
  }

  Future<void> _acquireTokensFromCookie(String cookie) async {
    final accessJson = await _requestAccessToken(cookie);
    final accessToken = accessJson['accessToken'] as String?;
    final clientId = accessJson['clientId'] as String?;

    DateTime expiresAt = DateTime.now().add(Duration(seconds: 3600));
    if (accessJson['accessTokenExpirationTimestampMs'] != null) {
      final ms = accessJson['accessTokenExpirationTimestampMs'] as int;
      expiresAt = DateTime.fromMillisecondsSinceEpoch(ms);
    } else if (accessJson['expiresIn'] != null) {
      expiresAt = DateTime.now().add(
        Duration(seconds: accessJson['expiresIn'] as int),
      );
    }

    if (accessToken == null || clientId == null) {
      throw StateError(
        '[Metadata/Spotify-Internal] Invalid access token response',
      );
    }

    _bearerToken = accessToken;

    final deviceId = _randomHex(32);
    final clientTokenPayload = {
      'client_data': {
        'client_id': clientId,
        'client_version': _spotifyAppVersion,
        'js_sdk_data': {
          'device_brand': 'unknown',
          'device_id': deviceId,
          'device_model': 'unknown',
          'device_type': 'computer',
          'os': 'windows',
          'os_version': 'NT 10.0',
        },
      },
    };

    http.Response? clientTokenResponse;
    Object? lastClientTokenError;

    for (var attempt = 1; attempt <= _tokenRequestMaxAttempts; attempt++) {
      final client = _createSpotifyHttpClient();
      try {
        clientTokenResponse = await client
            .post(
              Uri.parse(_spotifyClientTokenUrl),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(clientTokenPayload),
            )
            .timeout(_tokenRequestTimeout);
        break;
      } on TimeoutException catch (error) {
        lastClientTokenError = error;
      } on SocketException catch (error) {
        lastClientTokenError = error;
      } on http.ClientException catch (error) {
        lastClientTokenError = error;
      } finally {
        client.close();
      }

      if (attempt < _tokenRequestMaxAttempts) {
        await Future.delayed(const Duration(milliseconds: 350));
      }
    }

    if (clientTokenResponse == null) {
      throw StateError(
        '[Metadata/Spotify-Internal] Spotify client token request failed after $_tokenRequestMaxAttempts attempts: $lastClientTokenError',
      );
    }

    if (clientTokenResponse.statusCode != 200) {
      throw StateError(
        '[Metadata/Spotify-Internal] Spotify client token request failed: ${clientTokenResponse.statusCode}',
      );
    }

    final clientJson =
        jsonDecode(clientTokenResponse.body) as Map<String, dynamic>;
    final responseType = clientJson['response_type'] as String?;
    if (responseType == 'RESPONSE_GRANTED_TOKEN_RESPONSE') {
      final grantedToken =
          (clientJson['granted_token'] as Map<String, dynamic>?)?['token']
              as String?;
      _clientToken = grantedToken;
    }

    await _syncAudioSessionContext(cookie: cookie);

    final token = SpotifyToken(
      accessToken: _bearerToken ?? '',
      refreshToken: '',
      expiresAt: expiresAt,
    );
    await _credentialsService.saveSpotifyToken(token);
  }

  Future<void> _ensureTokens() async {
    if (_bearerToken != null && _clientToken != null) return;
    final cookie = await _credentialsService.getSpotifyLyricsCookie();
    if (cookie == null || cookie.isEmpty) {
      throw StateError(
        '[Metadata/Spotify-Internal] Not logged in. No Spotify cookie found.',
      );
    }
    await _acquireTokensFromCookie(cookie);
  }

  Future<void> _syncAudioSessionContext({required String cookie}) async {
    final spotifyAudioEnabled =
        await PreferencesProvider.isAudioSpotifyEnabled();
    if (!spotifyAudioEnabled) {
      await SpotifyAudioKeySessionManager.instance.clear();
      return;
    }

    await SpotifyAudioKeySessionManager.instance.updateAuthContext(
      bearerToken: _bearerToken,
      clientToken: _clientToken,
      cookie: cookie,
    );
  }

  Map<String, String> _buildInternalHeaders({String? cookieHeader}) {
    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken ?? '',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }
    return headers;
  }

  Future<void> _ensureUserProfile() async {
    if (_userId != null && _userId!.isNotEmpty) return;
    final cached = await _readCacheEntry(type: 'profile', id: 'me');
    if (cached != null && !cached.isExpired) {
      final cachedUser = cached.payload['userId'] as String?;
      final cachedName = cached.payload['displayName'] as String?;
      if (cachedUser != null && cachedUser.isNotEmpty) {
        _userId = cachedUser;
        _userDisplayName = cachedName;
        return;
      }
    }
    await _ensureTokens();
    final response = await _makeWebApiRequestWithBody('/me', method: 'GET');
    if (response.statusCode != 200) {
      throw Exception(
        '[Metadata/Spotify-Internal] Failed to fetch user profile: '
        '${response.statusCode} ${response.body}',
      );
    }
    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
    _userId = jsonResponse['id'] as String?;
    _userDisplayName = jsonResponse['display_name'] as String?;
    if (_userId != null && _userId!.isNotEmpty) {
      await _writeCacheEntry(
        type: 'profile',
        id: 'me',
        payload: {'userId': _userId, 'displayName': _userDisplayName},
      );
    }
  }

  String _playlistIdFromUri(String uri) {
    final parts = uri.split(':');
    return parts.isNotEmpty ? parts.last : uri;
  }

  Future<http.Response> _postWithRetry(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    const maxRetries = 3;
    var retryCount = 0;
    var backoffSeconds = 2;

    while (true) {
      final client = _createSpotifyHttpClient();
      try {
        final response = await client.post(url, headers: headers, body: body);

        if (response.statusCode == 429 ||
            (response.statusCode >= 500 && response.statusCode <= 504)) {
          if (retryCount >= maxRetries) {
            return response;
          }

          retryCount++;
          var waitTime = backoffSeconds;

          final retryAfter = response.headers['retry-after'];
          if (retryAfter != null) {
            waitTime = int.tryParse(retryAfter) ?? backoffSeconds;
          }

          logger.w(
            '[Metadata/Spotify-Internal] Got ${response.statusCode} for $url, retrying in $waitTime seconds (Attempt $retryCount of $maxRetries)',
          );
          await Future.delayed(Duration(seconds: waitTime));

          backoffSeconds *= 2;
          continue;
        }

        return response;
      } finally {
        client.close();
      }
    }
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

  Future<http.Response> _makeWebApiRequestWithBody(
    String path, {
    required String method,
    String? body,
  }) async {
    final url = Uri.parse('https://api.spotify.com/v1$path');
    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
    };

    final client = _createSpotifyHttpClient();
    try {
      if (method == 'PUT') {
        return await client.put(url, headers: headers, body: body);
      }
      if (method == 'DELETE') {
        return await client.delete(url, headers: headers, body: body);
      }
      if (method == 'POST') {
        return await client.post(url, headers: headers, body: body);
      }
      return await client.get(url, headers: headers);
    } finally {
      client.close();
    }
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
        pageKey: pageKey,
        payload: {'items': fresh.map(itemToJson).toList()},
      );
      return fresh;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  String _getLocalTimeZone() {
    final name = DateTime.now().timeZoneName;
    if (name.isNotEmpty) return name;
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  String _hashKey(String input) {
    return sha1.convert(utf8.encode(input)).toString();
  }

  Future<GenericHome> getUserHome({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (!_isAuthenticated) {
      throw StateError(
        '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
      );
    }

    if (_bearerToken == null || _clientToken == null) {
      final cookie = await _credentialsService.getSpotifyLyricsCookie();
      if (cookie == null || cookie.isEmpty) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not logged in. No Spotify cookie found.',
        );
      }
      await _acquireTokensFromCookie(cookie);
    }

    final cached = await _readCacheEntry(type: 'home', id: 'home');
    if (policy == MetadataFetchPolicy.cacheFirst && cached != null) {
      return spotifyInternalHomeToGeneric(cached.payload);
    }
    if (policy == MetadataFetchPolicy.refreshIfExpired &&
        cached != null &&
        !cached.isExpired) {
      return spotifyInternalHomeToGeneric(cached.payload);
    }

    const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
    final cookieMap = await _credentialsService.getSpotifyCookies();
    final spT = cookieMap?['sp_t'];
    final timezone = _getLocalTimeZone();

    final variables = <String, dynamic>{
      'homeEndUserIntegration': 'INTEGRATION_WEB_PLAYER',
      'timeZone': timezone,
      'sp_t': spT ?? '',
      'facet': '',
      'sectionItemsLimit': 10,
    };

    final body = {
      'operationName': 'home',
      'variables': variables,
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash':
              '66aedae92842f23d5254ba3371f4f7def0bf00342d0cbe3fea3de198d9414a60',
        },
      },
    };

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken!,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    final response = await _postWithRetry(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '[Metadata/Spotify-Internal] Failed to fetch home: '
        '${response.statusCode} ${response.body}',
      );
    }

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

    await _writeCacheEntry(type: 'home', id: 'home', payload: jsonResponse);

    return spotifyInternalHomeToGeneric(jsonResponse);
  }

  @override
  Future<List<GenericPlaylist>> getUserPlaylists({
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final library = await getUserLibrary(policy: policy);
    final items = library.saved_playlists;
    if (offset >= items.length) return [];
    final end = (offset + limit) > items.length ? items.length : offset + limit;
    return items.sublist(offset, end);
  }

  @override
  Future<List<GenericAlbum>> getUserAlbums({
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final library = await getUserLibrary(policy: policy);
    final items = library.saved_albums;
    if (offset >= items.length) return [];
    final end = (offset + limit) > items.length ? items.length : offset + limit;
    return items.sublist(offset, end);
  }

  @override
  Future<List<GenericSimpleArtist>> getUserFollowedArtists({
    int limit = 20,
    String? after,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final library = await getUserLibrary(policy: policy);
    final items = library.saved_artists
        .map(
          (artist) => GenericSimpleArtist(
            id: artist.id,
            source: artist.source,
            name: artist.name,
            thumbnailUrl: artist.thumbnailUrl,
          ),
        )
        .toList();

    var start = 0;
    if (after != null && after.isNotEmpty) {
      final index = items.indexWhere((artist) => artist.id == after);
      if (index != -1) start = index + 1;
    }

    if (start >= items.length) return [];
    final end = (start + limit) > items.length ? items.length : start + limit;
    return items.sublist(start, end);
  }

  @override
  Future<GenericPlaylist> getPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final pageKey = 'offset_${offset}_limit_$limit';
    return _getWithCache(
      type: 'playlist',
      id: playlistId,
      pageKey: pageKey,
      policy: policy,
      fetcher: () async {
        if (!_isAuthenticated) {
          throw StateError(
            '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
          );
        }

        if (_bearerToken == null || _clientToken == null) {
          final cookie = await _credentialsService.getSpotifyLyricsCookie();
          if (cookie == null || cookie.isEmpty) {
            throw StateError(
              '[Metadata/Spotify-Internal] Not logged in. No Spotify cookie found.',
            );
          }
          await _acquireTokensFromCookie(cookie);
        }

        const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
        final headers = {
          'Authorization': 'Bearer $_bearerToken',
          'client-token': _clientToken!,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': _spotifyUserAgent,
          'Origin': 'https://open.spotify.com',
          'Referer': 'https://open.spotify.com/',
          'app-platform': 'WebPlayer',
          'spotify-app-version': _spotifyAppVersion,
          'Accept-Language': 'en',
        };

        final variables = {
          "uri": "spotify:playlist:$playlistId",
          "offset": offset,
          "limit": limit,
          "enableWatchFeedEntrypoint": true,
        };

        final body = {
          "variables": variables,
          "operationName": "fetchPlaylist",
          "extensions": {
            "persistedQuery": {
              "version": 1,
              "sha256Hash":
                  "346811f856fb0b7e4f6c59f8ebea78dd081c6e2fb01b77c954b26259d5fc6763",
            },
          },
        };

        final response = await _postWithRetry(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(body),
        );

        if (response.statusCode != 200) {
          throw Exception(
            '[Metadata/Spotify-Internal] Failed to fetch playlist info: '
            '${response.statusCode} ${response.body}',
          );
        }

        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        if (jsonResponse['errors'] is List &&
            (jsonResponse['errors'] as List).isNotEmpty) {
          throw Exception(
            '[Metadata/Spotify-Internal] Playlist query returned errors: '
            '${jsonResponse['errors']}',
          );
        }

        return spotifyInternalFullPlaylistToGeneric(
          jsonResponse,
          offset: offset,
          limit: limit,
        );
      },
      toJson: (playlist) => playlist.toJson(),
      fromJson: GenericPlaylist.fromJson,
    );
  }

  @override
  Future<List<PlaylistItem>> getMorePlaylistTracks(
    String playlistId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final playlist = await getPlaylistInfo(
      playlistId,
      offset: offset,
      limit: limit,
      policy: policy,
    );
    return playlist.songs ?? const <PlaylistItem>[];
  }

  @override
  Future<GenericAlbum> getAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
    String locale = "",
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final pageKey = 'offset_${offset}_limit_$limit';
    return _getWithCache(
      type: 'album',
      id: albumId,
      pageKey: pageKey,
      policy: policy,
      fetcher: () async {
        if (!_isAuthenticated) {
          throw StateError(
            '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
          );
        }

        if (_bearerToken == null || _clientToken == null) {
          final cookie = await _credentialsService.getSpotifyLyricsCookie();
          if (cookie == null || cookie.isEmpty) {
            throw StateError(
              '[Metadata/Spotify-Internal] Not logged in. No Spotify cookie found.',
            );
          }
          await _acquireTokensFromCookie(cookie);
        }

        const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
        final body = {
          "variables": {
            "uri": "spotify:album:$albumId",
            "locale": locale,
            "offset": offset,
            "limit": limit,
          },
          "operationName": "getAlbum",
          "extensions": {
            "persistedQuery": {
              "version": 1,
              "sha256Hash":
                  "b9bfabef66ed756e5e13f68a942deb60bd4125ec1f1be8cc42769dc0259b4b10",
            },
          },
        };

        final response = await _postWithRetry(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $_bearerToken',
            'client-token': _clientToken!,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': _spotifyUserAgent,
            'Origin': 'https://open.spotify.com',
            'Referer': 'https://open.spotify.com/',
            'app-platform': 'WebPlayer',
            'spotify-app-version': _spotifyAppVersion,
            'Accept-Language': 'en',
          },
          body: jsonEncode(body),
        );

        if (response.statusCode != 200) {
          throw Exception(
            '[Metadata/Spotify-Internal] Failed to fetch album info: ${response.statusCode} ${response.body}',
          );
        }

        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        return spotifyInternalFullAlbumToGeneric(
          jsonResponse,
          offset: offset,
          limit: limit,
        );
      },
      toJson: (album) => album.toJson(),
      fromJson: GenericAlbum.fromJson,
    );
  }

  @override
  Future<List<GenericSong>> getMoreAlbumTracks(
    String albumId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final album = await getAlbumInfo(
      albumId,
      offset: offset,
      limit: limit,
      policy: policy,
    );
    return album.songs ?? const <GenericSong>[];
  }

  @override
  Future<GenericArtist> getArtistInfo(
    String artistId, {
    String locale = "",
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    return _getWithCache(
      type: 'artist',
      id: artistId,
      policy: policy,
      fetcher: () async {
        if (!_isAuthenticated) {
          throw StateError('Not authenticated. Please log in.');
        }

        if (_bearerToken == null || _clientToken == null) {
          final cookie = await _credentialsService.getSpotifyLyricsCookie();
          if (cookie == null || cookie.isEmpty) {
            throw StateError('Not logged in. No Spotify cookie found.');
          }
          await _acquireTokensFromCookie(cookie);
        }

        if (artistId.startsWith("spotify:artist:")) {
          artistId = artistId.split(":").last;
        }

        logger.d(
          "[Metadata/Spotify-Internal] Getting artist info for $artistId",
        );

        const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
        final body = {
          "variables": {
            "uri": "spotify:artist:$artistId",
            "locale": "intl-pt",
            "preReleaseV2": false,
          },
          "operationName": "queryArtistOverview",
          "extensions": {
            "persistedQuery": {
              "version": 1,
              "sha256Hash":
                  "5b9e64f43843fa3a9b6a98543600299b0a2cbbbccfdcdcef2402eb9c1017ca4c",
            },
          },
        };

        logger.d(
          "[Metadata/Spotify-Internal] Sending request to Spotify internal API for artist $artistId",
        );

        logger.d(
          "[Metadata/Spotify-Internal] Bearer Token Length: ${_bearerToken?.length ?? 0}",
        );

        final response = await _postWithRetry(
          Uri.parse(url),
          headers: {
            'Accept-Language': 'en',
            'App-Platform': 'WebPlayer',
            'Authorization': 'Bearer $_bearerToken',
            'Client-Token': _clientToken!,
            'Content-Type': 'application/json;charset=UTF-8',
            'Accept': 'application/json',
            'User-Agent': _spotifyUserAgent,
            'Origin': 'https://open.spotify.com',
            'Referer': 'https://open.spotify.com/',
            // For some reason, this endpoint requires this app version,
            // which 1. is different from the one used in other endpoints
            // and 2. doesn't follow Spotify's usual versioning scheme
            'Spotify-App-Version': "896000000",
          },
          body: jsonEncode(body),
        );

        if (response.statusCode != 200) {
          throw Exception(
            '[Metadata/Spotify-Internal] Failed to fetch artist info: ${response.statusCode} ${response.body}',
          );
        }

        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        final genericArtist = spotifyInternalFullArtistToGeneric(jsonResponse);

        logger.d("[Metadata/Spotify-Internal] Got artist info for $artistId");

        return genericArtist;
      },
      toJson: (artist) => artist.toJson(),
      fromJson: GenericArtist.fromJson,
    );
  }

  Future<GenericArtist> getNpvArtistInfo(
    String artistId,
    String trackId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final normalizedArtistId = artistId.startsWith('spotify:artist:')
        ? artistId.split(':').last
        : artistId;
    final normalizedTrackId = trackId.startsWith('spotify:track:')
        ? trackId.split(':').last
        : trackId;

    return _getWithCache(
      type: 'artist_npv',
      id: '$normalizedArtistId:$normalizedTrackId',
      policy: policy,
      fetcher: () async {
        if (!_isAuthenticated) {
          throw StateError('Not authenticated. Please log in.');
        }

        if (_bearerToken == null || _clientToken == null) {
          final cookie = await _credentialsService.getSpotifyLyricsCookie();
          if (cookie == null || cookie.isEmpty) {
            throw StateError('Not logged in. No Spotify cookie found.');
          }
          await _acquireTokensFromCookie(cookie);
        }

        logger.d(
          '[Metadata/Spotify-Internal] Getting NPV artist info for '
          '$normalizedArtistId with track $normalizedTrackId',
        );

        const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
        final body = {
          'variables': {
            'artistUri': 'spotify:artist:$normalizedArtistId',
            'trackUri': 'spotify:track:$normalizedTrackId',
            'contributorsLimit': 10,
            'contributorsOffset': 0,
            'enableRelatedVideos': true,
            'enableRelatedAudioTracks': true,
          },
          'operationName': 'queryNpvArtist',
          'extensions': {
            'persistedQuery': {
              'version': 1,
              'sha256Hash':
                  '047c9c225967d41a763949a4db3f0493e901c9f8689a6537408aabf9beffc177',
            },
          },
        };

        final response = await _postWithRetry(
          Uri.parse(url),
          headers: {
            'Accept-Language': 'en',
            'App-Platform': 'WebPlayer',
            'Authorization': 'Bearer $_bearerToken',
            'Client-Token': _clientToken!,
            'Content-Type': 'application/json;charset=UTF-8',
            'Accept': 'application/json',
            'User-Agent': _spotifyUserAgent,
            'Origin': 'https://open.spotify.com',
            'Referer': 'https://open.spotify.com/',
            'Spotify-App-Version': _spotifyAppVersion,
          },
          body: jsonEncode(body),
        );

        if (response.statusCode != 200) {
          throw Exception(
            '[Metadata/Spotify-Internal] Failed to fetch NPV artist info: '
            '${response.statusCode} ${response.body}',
          );
        }

        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        final genericArtist = spotifyInternalFullArtistToGeneric(jsonResponse);

        logger.d(
          '[Metadata/Spotify-Internal] Got NPV artist info for '
          '$normalizedArtistId',
        );

        return genericArtist;
      },
      toJson: (artist) => artist.toJson(),
      fromJson: GenericArtist.fromJson,
    );
  }

  @override
  Future<List<PlaylistItem>> getUserSavedTracks({
    int limit = 50,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    if (!_isAuthenticated) {
      throw StateError(
        '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
      );
    }

    if (_bearerToken == null || _clientToken == null) {
      final cookie = await _credentialsService.getSpotifyLyricsCookie();
      if (cookie == null || cookie.isEmpty) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not logged in. No Spotify cookie found.',
        );
      }
      await _acquireTokensFromCookie(cookie);
    }

    final pageKey = 'offset_${offset}_limit_$limit';
    final cached = await _readCacheEntry(
      type: 'saved_tracks',
      id: 'saved_tracks',
      pageKey: pageKey,
    );

    if (policy == MetadataFetchPolicy.cacheFirst && cached != null) {
      final items = cached.payload['items'] as List?;
      if (items != null) {
        return items
            .whereType<Map<String, dynamic>>()
            .map(PlaylistItem.fromJson)
            .toList();
      }
    }

    if (policy == MetadataFetchPolicy.refreshIfExpired &&
        cached != null &&
        !cached.isExpired) {
      final items = cached.payload['items'] as List?;
      if (items != null) {
        return items
            .whereType<Map<String, dynamic>>()
            .map(PlaylistItem.fromJson)
            .toList();
      }
    }

    const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
    final body = {
      'variables': {'offset': offset, 'limit': limit},
      'operationName': 'fetchLibraryTracks',
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash':
              '087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240',
        },
      },
    };

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken!,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    final response = await _postWithRetry(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '[Metadata/Spotify-Internal] Failed to fetch saved tracks: '
        '${response.statusCode} ${response.body}',
      );
    }

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
    final tracks =
        jsonResponse['data']?['me']?['library']?['tracks']
            as Map<String, dynamic>?;
    final items = tracks?['items'] as List? ?? [];

    final pageItems = items
        .asMap()
        .entries
        .map((entry) {
          return spotifyInternalLibraryTrackToPlaylistItem(
            entry.value as Map<String, dynamic>,
            offset + entry.key + 1,
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList();

    final totalCount = tracks?['totalCount'] as int?;
    if (totalCount != null) {
      _likedTracksTotalCount = totalCount;
    } else if (offset == 0 && pageItems.length < limit) {
      _likedTracksTotalCount = pageItems.length;
    }

    await _writeCacheEntry(
      type: 'saved_tracks',
      id: 'saved_tracks',
      pageKey: pageKey,
      payload: {'items': pageItems.map((item) => item.toJson()).toList()},
    );

    return pageItems;
  }

  @override
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
            final pageItems = await getUserSavedTracks(
              limit: limit,
              offset: offset,
              policy: MetadataFetchPolicy.refreshAlways,
            );
            if (pageItems.isEmpty) break;
            all.addAll(pageItems);
            if (pageItems.length < limit) break;
            offset += pageItems.length;
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

  Future<Map<String, bool>> getCuratedStatus(List<String> trackIds) async {
    if (!_isAuthenticated) {
      throw StateError(
        '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
      );
    }

    if (_bearerToken == null || _clientToken == null) {
      final cookie = await _credentialsService.getSpotifyLyricsCookie();
      if (cookie == null || cookie.isEmpty) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not logged in. No Spotify cookie found.',
        );
      }
      await _acquireTokensFromCookie(cookie);
    }

    final normalized = trackIds
        .where((id) => id.trim().isNotEmpty)
        .map((id) => id.startsWith('spotify:track:') ? id : 'spotify:track:$id')
        .toSet()
        .toList();

    if (normalized.isEmpty) return {};

    final cacheId = _hashKey(normalized.join('|'));
    return _getWithCache<Map<String, bool>>(
      type: 'curated',
      id: cacheId,
      policy: MetadataFetchPolicy.refreshIfExpired,
      fetcher: () async {
        const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
        final body = {
          'variables': {'uris': normalized},
          'operationName': 'isCurated',
          'extensions': {
            'persistedQuery': {
              'version': 1,
              'sha256Hash':
                  'e4ed1f91a2cc5415befedb85acf8671dc1a4bf3ca1a5b945a6386101a22e28a6',
            },
          },
        };

        final headers = {
          'Authorization': 'Bearer $_bearerToken',
          'client-token': _clientToken!,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': _spotifyUserAgent,
          'Origin': 'https://open.spotify.com',
          'Referer': 'https://open.spotify.com/',
          'app-platform': 'WebPlayer',
          'spotify-app-version': _spotifyAppVersion,
          'Accept-Language': 'en',
        };

        final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
        if (cookieHeader != null && cookieHeader.isNotEmpty) {
          headers['Cookie'] = cookieHeader;
        }

        final response = await _postWithRetry(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(body),
        );

        if (response.statusCode != 200) {
          throw Exception(
            '[Metadata/Spotify-Internal] Failed to check curations: '
            '${response.statusCode} ${response.body}',
          );
        }

        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
        final lookup = jsonResponse['data']?['lookup'] as List? ?? [];

        final result = <String, bool>{};
        for (var i = 0; i < lookup.length; i++) {
          final entry = lookup[i] as Map<String, dynamic>?;
          final data = entry?['data'] as Map<String, dynamic>?;
          final curated = data?['isCurated'] as bool? ?? false;
          final id = normalized[i].split(':').last;
          result[id] = curated;
        }

        return result;
      },
      toJson: (value) => {'items': value},
      fromJson: (json) {
        final items = json['items'] as Map? ?? {};
        return items.map(
          (key, value) => MapEntry(key as String, value as bool? ?? false),
        );
      },
    );
  }

  Future<String?> getCanvasUrl(String trackId) async {
    if (!_isAuthenticated) {
      throw StateError(
        '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
      );
    }

    if (_bearerToken == null || _clientToken == null) {
      final cookie = await _credentialsService.getSpotifyLyricsCookie();
      if (cookie == null || cookie.isEmpty) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not logged in. No Spotify cookie found.',
        );
      }
      await _acquireTokensFromCookie(cookie);
    }

    final normalizedId = trackId.startsWith('spotify:track:')
        ? trackId.split(':').last
        : trackId;
    if (_canvasUrlCache.containsKey(normalizedId)) {
      return _canvasUrlCache[normalizedId];
    }

    final cached = await _readCacheEntry(type: 'canvas', id: normalizedId);
    if (cached != null) {
      final cachedUrl = cached.payload['url'] as String?;
      _canvasUrlCache[normalizedId] = cachedUrl;
      if (!cached.isExpired) {
        return cachedUrl;
      }
    }

    final uri = trackId.startsWith('spotify:track:')
        ? trackId
        : 'spotify:track:$trackId';

    const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
    final body = {
      'variables': {'trackUri': uri},
      'operationName': 'canvas',
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash':
              '575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f',
        },
      },
    };

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken!,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    try {
      final response = await _postWithRetry(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '[Metadata/Spotify-Internal] Failed to fetch canvas: '
          '${response.statusCode} ${response.body}',
        );
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final trackUnion =
          jsonResponse['data']?['trackUnion'] as Map<String, dynamic>?;
      final canvas = trackUnion?['canvas'] as Map<String, dynamic>?;
      final canvasUrl = canvas?['url'] as String?;
      _canvasUrlCache[normalizedId] = canvasUrl;
      await _writeCacheEntry(
        type: 'canvas',
        id: normalizedId,
        payload: {'url': canvasUrl},
      );
      return canvasUrl;
    } catch (e) {
      if (cached != null) {
        return cached.payload['url'] as String?;
      }
      rethrow;
    }
  }

  @override
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

  Future<void> _ensureWritingAllowed() async {
    if (!await PreferencesProvider.isWritingAllowed()) {
      throw StateError('Spotify writing is disabled in Preferences.');
    }
  }

  Future<bool> _isWritingAllowed() async {
    return PreferencesProvider.isWritingAllowed();
  }

  Future<void> _mutateLibrary({
    required String operationName,
    required List<String> uris,
  }) async {
    if (uris.isEmpty) return;
    await _ensureWritingAllowed();
    if (!_isAuthenticated) {
      throw StateError(
        '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
      );
    }
    await _ensureTokens();
    if (_bearerToken == null || _clientToken == null) {
      throw StateError('[Metadata/Spotify-Internal] Missing Spotify tokens');
    }

    const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
    final body = {
      'variables': {'libraryItemUris': uris},
      'operationName': operationName,
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash':
              '7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d',
        },
      },
    };

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken!,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    final response = await _postWithRetry(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '[Metadata/Spotify-Internal] Failed library update: '
        '${response.statusCode} ${response.body}',
      );
    }
  }

  @override
  Future<void> refreshSavedTracksAll() async {
    try {
      const limit = 50;
      var offset = 0;
      int? expectedTotal;
      final cachedAll = await getCachedSavedTracksAll() ?? <PlaylistItem>[];
      final merged = <PlaylistItem>[];

      while (true) {
        final pageItems = await getUserSavedTracks(
          limit: limit,
          offset: offset,
          policy: MetadataFetchPolicy.refreshAlways,
        );
        if (pageItems.isEmpty) break;

        final cachedPage = await _getCachedSavedTracksPage(
          limit: limit,
          offset: offset,
        );
        final pageMatches = _savedTracksPageMatches(pageItems, cachedPage);

        merged.addAll(pageItems);
        expectedTotal ??= _likedTracksTotalCount;

        if (pageMatches) {
          final tailStart = offset + pageItems.length;
          final canUseCachedTail =
              expectedTotal != null && cachedAll.length >= expectedTotal;
          if (canUseCachedTail && tailStart < cachedAll.length) {
            merged.addAll(cachedAll.sublist(tailStart));
            break;
          }
        }

        if (expectedTotal != null && merged.length >= expectedTotal) {
          break;
        }

        if (pageItems.length < limit) break;
        offset += pageItems.length;
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

  /// Search for tracks, artists, albums, and playlists
  @override
  Future<SearchResults> search(
    String query, {
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cacheId = 'v2_query_${query}_limit_${limit}_offset_$offset';
    return _getWithCache<SearchResults>(
      type: 'search_all',
      id: cacheId,
      policy: policy,
      fetcher: () async {
        final response = await _searchInternal(
          query,
          limit: limit,
          offset: offset,
        );
        final tracks = spotifyInternalSearchTracks(response);
        final artists = spotifyInternalSearchArtists(response);
        final albums = spotifyInternalSearchAlbums(response);
        final playlists = spotifyInternalSearchPlaylists(response);
        final topResult = spotifyInternalSearchBestMatch(response);
        return SearchResults(
          tracks: tracks,
          artists: artists,
          albums: albums,
          playlists: playlists,
          bestMatch: topResult ??
              (tracks.isNotEmpty ? SearchBestMatch.track(tracks.first) : null),
        );
      },
      toJson: (results) => results.toJson(),
      fromJson: SearchResults.fromJson,
    );
  }

  Future<Map<String, dynamic>> _searchInternal(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    if (!_isAuthenticated) {
      throw StateError(
        '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
      );
    }

    if (_bearerToken == null || _clientToken == null) {
      final cookie = await _credentialsService.getSpotifyLyricsCookie();
      if (cookie == null || cookie.isEmpty) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not logged in. No Spotify cookie found.',
        );
      }
      await _acquireTokensFromCookie(cookie);
    }

    const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
    final body = {
      'variables': {
        'searchTerm': query,
        'offset': offset,
        'limit': limit,
        'numberOfTopResults': 5,
        'includeAudiobooks': true,
        'includeArtistHasConcertsField': false,
        'includePreReleases': true,
        'includeAuthors': false,
      },
      'operationName': 'searchDesktop',
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash':
              '3c9d3f60dac5dea3876b6db3f534192b1c1d90032c4233c1bbaba526db41eb31',
        },
      },
    };

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken!,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    final response = await _postWithRetry(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '[Metadata/Spotify-Internal] Failed to search: '
        '${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<void> toggleTrackLike(GenericSong track) async {
    if (track.source != SongSource.spotifyInternal &&
        track.source != SongSource.spotify)
      return;
    if (!await _isWritingAllowed()) return;
    if (isTrackLiked(track.id)) {
      await unlikeTrack(track);
    } else {
      await likeTrack(track);
    }
  }

  @override
  Future<String> createPlaylist({
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    try {
      await _ensureWritingAllowed();
      if (!_isAuthenticated) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
        );
      }
      await _ensureTokens();
      await _ensureUserProfile();
      final userId = _userId;
      if (userId == null || userId.isEmpty) {
        throw StateError('[Metadata/Spotify-Internal] Missing Spotify user ID');
      }

      final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
      final headers = _buildInternalHeaders(cookieHeader: cookieHeader);

      final createBody = {
        'ops': [
          {
            'kind': 'UPDATE_LIST_ATTRIBUTES',
            'updateListAttributes': {
              'newAttributes': {
                'values': {'name': name},
              },
            },
          },
        ],
      };

      final createResponse = await _postWithRetry(
        Uri.parse('https://spclient.wg.spotify.com/playlist/v2/playlist'),
        headers: headers,
        body: jsonEncode(createBody),
      );

      if (createResponse.statusCode != 200) {
        throw Exception(
          '[Metadata/Spotify-Internal] Failed to create playlist: '
          '${createResponse.statusCode} ${createResponse.body}',
        );
      }

      final createJson =
          jsonDecode(createResponse.body) as Map<String, dynamic>;
      final uri = createJson['uri'] as String?;
      if (uri == null || uri.isEmpty) {
        throw Exception('[Metadata/Spotify-Internal] Missing playlist URI');
      }
      final playlistId = _playlistIdFromUri(uri);

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final addBody = {
        'deltas': [
          {
            'ops': [
              {
                'kind': 'ADD',
                'add': {
                  'items': [
                    {
                      'uri': 'spotify:playlist:$playlistId',
                      'attributes': {'timestamp': timestamp},
                    },
                  ],
                  'addFirst': true,
                },
              },
            ],
            'info': {
              'source': {'client': 'WEBPLAYER'},
            },
          },
        ],
      };

      final addResponse = await _postWithRetry(
        Uri.parse(
          'https://spclient.wg.spotify.com/playlist/v2/user/$userId/rootlist/changes',
        ),
        headers: headers,
        body: jsonEncode(addBody),
      );

      if (addResponse.statusCode != 200) {
        throw Exception(
          '[Metadata/Spotify-Internal] Failed to add playlist to library: '
          '${addResponse.statusCode} ${addResponse.body}',
        );
      }

      return playlistId;
    } catch (e) {
      _errorMessage = 'Failed to create playlist: $e';
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> renamePlaylist(String playlistId, String name) async {
    try {
      await _ensureWritingAllowed();
      if (!_isAuthenticated) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
        );
      }
      await _ensureTokens();
      final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
      final headers = _buildInternalHeaders(cookieHeader: cookieHeader);

      final body = {
        'deltas': [
          {
            'ops': [
              {
                'kind': 'UPDATE_LIST_ATTRIBUTES',
                'updateListAttributes': {
                  'newAttributes': {
                    'values': {'name': name},
                  },
                },
              },
            ],
            'info': {
              'source': {'client': 'WEBPLAYER'},
            },
          },
        ],
      };

      final response = await _postWithRetry(
        Uri.parse(
          'https://spclient.wg.spotify.com/playlist/v2/playlist/$playlistId/changes',
        ),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '[Metadata/Spotify-Internal] Failed to rename playlist: '
          '${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      _errorMessage = 'Failed to rename playlist: $e';
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    try {
      await _ensureWritingAllowed();
      if (!_isAuthenticated) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
        );
      }
      await _ensureTokens();
      await _ensureUserProfile();
      final userId = _userId;
      if (userId == null || userId.isEmpty) {
        throw StateError('[Metadata/Spotify-Internal] Missing Spotify user ID');
      }
      final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
      final headers = _buildInternalHeaders(cookieHeader: cookieHeader);

      final body = {
        'deltas': [
          {
            'ops': [
              {
                'kind': 'REM',
                'rem': {
                  'items': [
                    {'uri': 'spotify:playlist:$playlistId'},
                  ],
                  'itemsAsKey': true,
                },
              },
            ],
            'info': {
              'source': {'client': 'WEBPLAYER'},
            },
          },
        ],
      };

      final response = await _postWithRetry(
        Uri.parse(
          'https://spclient.wg.spotify.com/playlist/v2/user/$userId/rootlist/changes',
        ),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '[Metadata/Spotify-Internal] Failed to delete playlist: '
          '${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      _errorMessage = 'Failed to delete playlist: $e';
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> addTracksToPlaylist(
    String playlistId,
    List<String> trackIds,
  ) async {
    if (trackIds.isEmpty) return;
    try {
      await _ensureWritingAllowed();
      if (!_isAuthenticated) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
        );
      }

      await _ensureTokens();
      if (_bearerToken == null || _clientToken == null) {
        throw StateError('[Metadata/Spotify-Internal] Missing Spotify tokens');
      }

      final normalized = trackIds
          .where((id) => id.trim().isNotEmpty)
          .map(
            (id) => id.startsWith('spotify:track:') ? id : 'spotify:track:$id',
          )
          .toList();
      if (normalized.isEmpty) return;

      const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
      final body = {
        'variables': {
          'playlistItemUris': normalized,
          'playlistUri': 'spotify:playlist:$playlistId',
          'newPosition': {'moveType': 'BOTTOM_OF_PLAYLIST', 'fromUid': null},
        },
        'operationName': 'addToPlaylist',
        'extensions': {
          'persistedQuery': {
            'version': 1,
            'sha256Hash':
                '47b2a1234b17748d332dd0431534f22450e9ecbb3d5ddcdacbd83368636a0990',
          },
        },
      };

      final headers = {
        'Authorization': 'Bearer $_bearerToken',
        'client-token': _clientToken!,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': _spotifyUserAgent,
        'Origin': 'https://open.spotify.com',
        'Referer': 'https://open.spotify.com/',
        'app-platform': 'WebPlayer',
        'spotify-app-version': _spotifyAppVersion,
        'Accept-Language': 'en',
      };

      final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        headers['Cookie'] = cookieHeader;
      }

      final response = await _postWithRetry(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '[Metadata/Spotify-Internal] Failed to add tracks: '
          '${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      _errorMessage = 'Failed to add tracks: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeTracksFromPlaylist(
    String playlistId,
    List<String> uids,
  ) async {
    if (uids.isEmpty) return;
    try {
      await _ensureWritingAllowed();
      if (!_isAuthenticated) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
        );
      }

      await _ensureTokens();
      if (_bearerToken == null || _clientToken == null) {
        throw StateError('[Metadata/Spotify-Internal] Missing Spotify tokens');
      }

      const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
      final body = {
        'variables': {
          'playlistUri': 'spotify:playlist:$playlistId',
          'uids': uids,
        },
        'operationName': 'removeFromPlaylist',
        'extensions': {
          'persistedQuery': {
            'version': 1,
            'sha256Hash':
                '47b2a1234b17748d332dd0431534f22450e9ecbb3d5ddcdacbd83368636a0990',
          },
        },
      };

      final headers = {
        'Authorization': 'Bearer $_bearerToken',
        'client-token': _clientToken!,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': _spotifyUserAgent,
        'Origin': 'https://open.spotify.com',
        'Referer': 'https://open.spotify.com/',
        'app-platform': 'WebPlayer',
        'spotify-app-version': _spotifyAppVersion,
        'Accept-Language': 'en',
      };

      final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        headers['Cookie'] = cookieHeader;
      }

      final response = await _postWithRetry(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '[Metadata/Spotify-Internal] Failed to remove tracks: '
          '${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      _errorMessage = 'Failed to remove tracks: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> followArtist(String artistId) async {
    final uri = artistId.startsWith('spotify:artist:')
        ? artistId
        : 'spotify:artist:$artistId';
    await _mutateLibrary(operationName: 'addToLibrary', uris: [uri]);
  }

  Future<void> unfollowArtist(String artistId) async {
    final uri = artistId.startsWith('spotify:artist:')
        ? artistId
        : 'spotify:artist:$artistId';
    await _mutateLibrary(operationName: 'removeFromLibrary', uris: [uri]);
  }

  Future<void> saveAlbum(String albumId) async {
    final uri = albumId.startsWith('spotify:album:')
        ? albumId
        : 'spotify:album:$albumId';
    await _mutateLibrary(operationName: 'addToLibrary', uris: [uri]);
  }

  Future<void> unsaveAlbum(String albumId) async {
    final uri = albumId.startsWith('spotify:album:')
        ? albumId
        : 'spotify:album:$albumId';
    await _mutateLibrary(operationName: 'removeFromLibrary', uris: [uri]);
  }

  @override
  Future<void> fetchUserProfile() async {
    final cached = await _readCacheEntry(type: 'profile', id: 'me');
    if (cached != null && !cached.isExpired) {
      final cachedUser = cached.payload['userId'] as String?;
      final cachedName = cached.payload['displayName'] as String?;
      if (cachedUser != null && cachedUser.isNotEmpty) {
        _userId = cachedUser;
        _userDisplayName = cachedName;
        return;
      }
    }
    if (!_isAuthenticated) {
      throw StateError(
        '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
      );
    }
    await _ensureTokens();
    if (_bearerToken == null || _clientToken == null) {
      throw StateError('[Metadata/Spotify-Internal] Missing Spotify tokens');
    }

    const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
    final body = {
      'variables': {},
      'operationName': 'profileAttributes',
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash':
              '53bcb064f6cd18c23f752bc324a791194d20df612d8e1239c735144ab0399ced',
        },
      },
    };

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken!,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    final response = await _postWithRetry(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '[Metadata/Spotify-Internal] Failed to fetch user profile: '
        '${response.statusCode} ${response.body}',
      );
    }

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
    final profile =
        jsonResponse['data']?['me']?['profile'] as Map<String, dynamic>?;
    final username = profile?['username'] as String?;
    final name = profile?['name'] as String?;
    _userId = username;
    _userDisplayName = name;
    if (_userId != null && _userId!.isNotEmpty) {
      await _writeCacheEntry(
        type: 'profile',
        id: 'me',
        payload: {'userId': _userId, 'displayName': _userDisplayName},
      );
    }
  }

  @override
  Future<void> likeTrack(GenericSong track) async {
    if (track.source != SongSource.spotifyInternal &&
        track.source != SongSource.spotify)
      return;
    if (!await _isWritingAllowed()) return;
    if (_bearerToken == null || _clientToken == null) {
      final cookie = await _credentialsService.getSpotifyLyricsCookie();
      if (cookie == null || cookie.isEmpty) return;
      await _acquireTokensFromCookie(cookie);
    }

    const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
    final body = {
      'variables': {
        'libraryItemUris': ['spotify:track:${track.id}'],
      },
      'operationName': 'addToLibrary',
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash':
              '7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d',
        },
      },
    };

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken!,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    final response = await _postWithRetry(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '[Metadata/Spotify-Internal] Failed to like track: ${response.statusCode} ${response.body}',
      );
    }

    _likedTrackIds.add(track.id);
    await _updateSavedTracksCacheOnLike(track);
    notifyListeners();
  }

  @override
  Future<void> unlikeTrack(GenericSong track) async {
    if (track.source != SongSource.spotifyInternal &&
        track.source != SongSource.spotify)
      return;
    if (!await _isWritingAllowed()) return;
    if (_bearerToken == null || _clientToken == null) {
      final cookie = await _credentialsService.getSpotifyLyricsCookie();
      if (cookie == null || cookie.isEmpty) return;
      await _acquireTokensFromCookie(cookie);
    }

    const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
    final body = {
      'variables': {
        'input': {
          'curations': [
            {
              'contextUri': 'spotify:collection:tracks',
              'curationType': 'UNCURATE',
            },
          ],
          'itemUris': ['spotify:track:${track.id}'],
        },
      },
      'operationName': 'applyCurations',
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash':
              '05b739a3a73091c213385233b9d3ed8a857c2ca29d2eebadb3d04ed12e288697',
        },
      },
    };

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken!,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final cookieHeader = await _credentialsService.getSpotifyLyricsCookie();
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    final response = await _postWithRetry(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '[Metadata/Spotify-Internal] Failed to unlike track: ${response.statusCode} ${response.body}',
      );
    }

    _likedTrackIds.remove(track.id);
    await _updateSavedTracksCacheOnUnlike(track.id);
    notifyListeners();
  }

  PlaylistItem _playlistItemFromSong(GenericSong song) {
    return PlaylistItem(
      id: song.id,
      source: SongSource.spotifyInternal,
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
    final cached = await _getCachedSavedTracksPage(limit: 50, offset: 0);
    if (cached == null) return;
    if (cached.any((item) => item.id == song.id)) return;

    final updated = [_playlistItemFromSong(song), ...cached];
    if (updated.length > 50) {
      updated.removeRange(50, updated.length);
    }

    await _writeCacheEntry(
      type: 'saved_tracks',
      id: 'saved_tracks',
      pageKey: 'offset_0_limit_50',
      payload: {'items': updated.map((item) => item.toJson()).toList()},
    );
  }

  Future<void> _updateSavedTracksCacheOnUnlike(String trackId) async {
    final cached = await _getCachedSavedTracksPage(limit: 50, offset: 0);
    if (cached == null) return;

    final updated = cached.where((item) => item.id != trackId).toList();
    if (updated.length == cached.length) return;

    await _writeCacheEntry(
      type: 'saved_tracks',
      id: 'saved_tracks',
      pageKey: 'offset_0_limit_50',
      payload: {'items': updated.map((item) => item.toJson()).toList()},
    );
  }

  // This one is a little more complex.
  // First, we need a parameter to see if any Spotify folders are expanded.
  // Second, we need the user's Spotify ID, since the endpoint asks it for the folders, in
  // this format:
  // "expandedFolders: [
  //    0: "spotify:user:{userId}:folder:{folderId}"
  // ]"
  Future<GenericLibrary> getUserLibrary({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    return _getWithCache(
      type: 'library',
      id: 'library',
      policy: policy,
      fetcher: () async {
        GenericLibrary library = await _fetchUserLibrary([]);

        final initialAll = library.all_organized ?? [];
        final remoteFolderIds = <String>[];

        for (int i = 0; i < initialAll.length; i++) {
          final item = initialAll[i];
          if (item is Map<String, dynamic>) {
            final t = item['__typename'] as String? ?? item['type'] as String?;
            if (t == 'Folder' || t == 'folder') {
              final uri = item['uri'] as String? ?? item['id'] as String? ?? '';
              final id = uri.isNotEmpty ? uri : (item['id'] as String? ?? '');
              if (id.isNotEmpty) {
                remoteFolderIds.add(id);
              }
            }
          }
        }

        if (remoteFolderIds.isNotEmpty) {
          library = await _fetchUserLibrary(remoteFolderIds);
        }

        final finalAll = library.all_organized ?? [];
        final folderAssignments = <String, String>{};
        final newAllOrganized = <dynamic>[];

        int finalIndex = 0;

        for (final initialItem in initialAll) {
          bool isFolder = false;
          String folderId = '';
          int folderCount = 0;

          if (initialItem is Map<String, dynamic>) {
            final t =
                initialItem['__typename'] as String? ??
                initialItem['type'] as String?;
            if (t == 'Folder' || t == 'folder') {
              isFolder = true;
              final uri =
                  initialItem['uri'] as String? ??
                  initialItem['id'] as String? ??
                  '';
              folderId = uri.isNotEmpty
                  ? uri
                  : (initialItem['id'] as String? ?? '');
              folderCount = initialItem['playlistCount'] as int? ?? 0;
            }
          }

          if (isFolder) {
            newAllOrganized.add(initialItem);

            if (finalIndex < finalAll.length) {
              finalIndex++;
            }

            for (int i = 0; i < folderCount; i++) {
              if (finalIndex < finalAll.length) {
                final finalItem = finalAll[finalIndex];
                newAllOrganized.add(finalItem);

                String itemId = '';
                bool isPlaylist = false;

                if (finalItem is GenericPlaylist) {
                  itemId = finalItem.id;
                  isPlaylist = true;
                } else if (finalItem is GenericAlbum) {
                  itemId = finalItem.id;
                } else if (finalItem is GenericArtist) {
                  itemId = finalItem.id;
                } else if (finalItem is Map<String, dynamic>) {
                  itemId = finalItem['id'] as String? ?? '';
                  final t =
                      finalItem['__typename'] as String? ??
                      finalItem['type'] as String?;
                  if (t == 'Playlist' || t == 'playlist') isPlaylist = true;
                }

                if (isPlaylist && itemId.isNotEmpty && folderId.isNotEmpty) {
                  folderAssignments[itemId] = folderId;
                }
                finalIndex++;
              }
            }
          } else {
            if (finalIndex < finalAll.length) {
              newAllOrganized.add(finalAll[finalIndex]);
              finalIndex++;
            }
          }
        }

        return GenericLibrary(
          saved_albums: library.saved_albums,
          saved_playlists: library.saved_playlists,
          saved_artists: library.saved_artists,
          all_organized: newAllOrganized,
          folderAssignments: folderAssignments,
        );
      },
      toJson: (library) => library.toJson(),
      fromJson: GenericLibrary.fromJson,
    );
  }

  Future<GenericLibrary> _fetchUserLibrary(
    List<String>? expandedFoldersIDs,
  ) async {
    if (!_isAuthenticated) {
      throw StateError(
        '[Metadata/Spotify-Internal] Not authenticated. Please log in.',
      );
    }

    if (_bearerToken == null || _clientToken == null) {
      final cookie = await _credentialsService.getSpotifyLyricsCookie();
      if (cookie == null || cookie.isEmpty) {
        throw StateError(
          '[Metadata/Spotify-Internal] Not logged in. No Spotify cookie found.',
        );
      }
      await _acquireTokensFromCookie(cookie);
    }

    const url = 'https://api-partner.spotify.com/pathfinder/v2/query';
    final body = {
      "variables": {
        "expandedFolders": expandedFoldersIDs ?? [],
        "features": ["LIKED_SONGS"],
        "flatten": false,
        "folderUri": null,
        "includeFoldersWhenFlattening": true,
        "limit": 100,
        "offset": 0,
        "order": null,
        "textFilter": null,
      },
      "operationName": "libraryV3",
      "extensions": {
        "persistedQuery": {
          "version": 1,
          "sha256Hash":
              "9f4da031f81274d572cfedaf6fc57a737c84b43d572952200b2c36aaa8fec1c6",
        },
      },
    };

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'client-token': _clientToken!,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': _spotifyUserAgent,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final response = await _postWithRetry(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '[Metadata/Spotify-Internal] Failed to fetch user library: ${response.statusCode} ${response.body}',
      );
    }

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

    final genericLibrary = spotifyInternalLibraryToGeneric(jsonResponse);

    return genericLibrary;
  }
}

// ----------------- Token acquisition helpers (adapted from lyrics provider) -----------------
const _spotifyWebTokenUrl = 'https://open.spotify.com/api/token';
const _spotifyClientTokenUrl = 'https://clienttoken.spotify.com/v1/clienttoken';
const _spotifyUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
const _spotifyAppVersion = "1.2.87.317.g32ca400d";
const _allowInsecureSpotifyTls = bool.fromEnvironment(
  'WISP_ALLOW_INSECURE_SPOTIFY_TLS',
  defaultValue: true,
);
const _allowInsecureSpotifySecretsTls = bool.fromEnvironment(
  'WISP_ALLOW_INSECURE_SPOTIFY_SECRETS_TLS',
  defaultValue: true,
);
const _secretsUrl =
    'https://git.gay/thereallo/totp-secrets/raw/branch/main/secrets/secrets.json';
const _spotifyNetworkTimeout = Duration(seconds: 12);

Future<Map<String, dynamic>> _requestAccessToken(String cookie) async {
  Future<Map<String, dynamic>> fetchWithTotp(_TotpPayload totpPayload) async {
    final accessTokenUrl = Uri.parse(_spotifyWebTokenUrl).replace(
      queryParameters: {
        'reason': 'init',
        'productType': 'web-player',
        'totp': totpPayload.otp,
        'totpServer': totpPayload.otp,
        'totpVer': totpPayload.version.toString(),
      },
    );

    final client = _createSpotifyHttpClient();
    http.Response accessTokenResponse;
    try {
      accessTokenResponse = await client
          .get(
            accessTokenUrl,
            headers: {
              'Cookie': cookie,
              'User-Agent': _spotifyUserAgent,
              'Accept': 'application/json',
              'Origin': 'https://open.spotify.com',
              'Referer': 'https://open.spotify.com/',
            },
          )
          .timeout(_spotifyNetworkTimeout);
    } finally {
      client.close();
    }

    if (accessTokenResponse.statusCode != 200) {
      final body = accessTokenResponse.body;
      final snippet = body.length > 300 ? body.substring(0, 300) : body;
      throw StateError(
        '[Metadata/Spotify-Internal] Spotify access token request failed: '
        '${accessTokenResponse.statusCode} ${snippet.isEmpty ? '' : snippet}',
      );
    }

    return jsonDecode(accessTokenResponse.body) as Map<String, dynamic>;
  }

  final firstTotp = await _generateTotp();
  try {
    return await fetchWithTotp(firstTotp);
  } catch (e) {
    final message = e.toString();
    if (!message.contains('400')) rethrow;
  }

  final retryTotp = await _generateTotp();
  return fetchWithTotp(retryTotp);
}

Future<_TotpPayload> _generateTotp() async {
  const secretSauce = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  final client = _createHttpClient(
    allowInsecureSpotifySecretsTls: _allowInsecureSpotifySecretsTls,
  );
  http.Response response;
  try {
    response = await client
        .get(Uri.parse(_secretsUrl))
        .timeout(_spotifyNetworkTimeout);
  } finally {
    client.close();
  }
  if (response.statusCode != 200) {
    throw StateError(
      '[Metadata/Spotify-Internal] Failed to fetch TOTP secrets',
    );
  }

  final secrets = jsonDecode(response.body) as List<dynamic>;
  if (secrets.isEmpty) {
    throw StateError(
      '[Metadata/Spotify-Internal] No secrets available for TOTP',
    );
  }

  final mostRecent = secrets.last as Map<String, dynamic>;
  final version = mostRecent['version'] as int? ?? 0;
  final secretValue = mostRecent['secret'] as String? ?? '';
  if (secretValue.isEmpty) {
    throw StateError('[Metadata/Spotify-Internal] Invalid TOTP secret payload');
  }

  final secretArray = secretValue.codeUnits;
  final secretCipherBytes = <int>[];
  for (var i = 0; i < secretArray.length; i++) {
    secretCipherBytes.add(secretArray[i] ^ ((i % 33) + 9));
  }

  final cipherString = secretCipherBytes.join('');
  final cipherBytes = utf8.encode(cipherString);
  final hexBuffer = StringBuffer();
  for (final value in cipherBytes) {
    hexBuffer.write(value.toRadixString(16).padLeft(2, '0'));
  }

  final secretBytes = _cleanBuffer(hexBuffer.toString());
  final base32Secret = _base32FromBytes(secretBytes, secretSauce);

  final otp = _generateTotpCode(base32Secret);
  return _TotpPayload(otp: otp, version: version);
}

Uint8List _cleanBuffer(String hex) {
  final sanitized = hex.replaceAll(' ', '');
  final length = sanitized.length ~/ 2;
  final bytes = Uint8List(length);
  for (var i = 0; i < sanitized.length; i += 2) {
    bytes[i ~/ 2] = int.parse(sanitized.substring(i, i + 2), radix: 16);
  }
  return bytes;
}

String _base32FromBytes(Uint8List bytes, String alphabet) {
  var t = 0;
  var n = 0;
  final buffer = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    n = (n << 8) | bytes[i];
    t += 8;
    while (t >= 5) {
      buffer.write(alphabet[(n >> (t - 5)) & 31]);
      t -= 5;
    }
  }
  if (t > 0) {
    buffer.write(alphabet[(n << (5 - t)) & 31]);
  }
  return buffer.toString();
}

String _generateTotpCode(
  String base32Secret, {
  int digits = 6,
  int interval = 30,
}) {
  final secretBytes = _decodeBase32(base32Secret);
  final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final counter = timestamp ~/ interval;
  final counterBytes = ByteData(8)..setInt64(0, counter);

  final hmac = Hmac(sha1, secretBytes);
  final digest = hmac.convert(counterBytes.buffer.asUint8List()).bytes;
  final offset = digest.last & 0x0f;
  final code =
      ((digest[offset] & 0x7f) << 24) |
      ((digest[offset + 1] & 0xff) << 16) |
      ((digest[offset + 2] & 0xff) << 8) |
      (digest[offset + 3] & 0xff);
  final mod = pow(10, digits).toInt();
  final otp = code % mod;
  return otp.toString().padLeft(digits, '0');
}

Uint8List _decodeBase32(String input) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final normalized = input.replaceAll('=', '').toUpperCase();
  var buffer = 0;
  var bitsLeft = 0;
  final bytes = <int>[];

  for (final char in normalized.codeUnits) {
    final index = alphabet.indexOf(String.fromCharCode(char));
    if (index < 0) continue;
    buffer = (buffer << 5) | index;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      bitsLeft -= 8;
      bytes.add((buffer >> bitsLeft) & 0xff);
    }
  }

  return Uint8List.fromList(bytes);
}

String _randomHex(int length) {
  const hex = '0123456789abcdef';
  final rand = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(hex[rand.nextInt(16)]);
  }
  return buffer.toString();
}

String _normalizeCookie(String cookie) {
  final trimmed = cookie.trim();
  if (trimmed.startsWith('sp_dc=')) return trimmed;
  return 'sp_dc=$trimmed';
}

http.Client _createHttpClient({required bool allowInsecureSpotifySecretsTls}) {
  if (!allowInsecureSpotifySecretsTls) {
    return http.Client();
  }

  final ioClient = HttpClient();
  ioClient.badCertificateCallback = (cert, host, port) {
    return host == 'git.gay';
  };
  return IOClient(ioClient);
}

http.Client _createSpotifyHttpClient() {
  if (!_allowInsecureSpotifyTls) {
    return http.Client();
  }

  final ioClient = HttpClient();
  ioClient.badCertificateCallback = (cert, host, port) {
    return host == 'open.spotify.com' ||
        host == 'clienttoken.spotify.com' ||
        host == 'spclient.wg.spotify.com';
  };
  return IOClient(ioClient);
}

class _TotpPayload {
  final String otp;
  final int version;

  const _TotpPayload({required this.otp, required this.version});
}
