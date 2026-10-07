// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/metadata_cache.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/models/metadata_provider.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/data/sources/providers/js_provider_bridge.dart';
import 'package:wisp/data/sources/providers/service_session_manager.dart';
import 'package:wisp/features/library/state/library_folders.dart';

/// Modular metadata provider powered by QuickJS / JSC sandboxed runtime.
/// Intercepts all requests with [MetadataCacheStore] for robust L1 memory & L2 disk caching.
class JsMetadataSource extends MetadataProvider {
  @override
  final String providerId;
  final String serviceId;
  final String? customScript;
  final String? scriptPath;
  final String _name;
  final String _displayName;
  final String _description;
  final String _logoURL;
  final String _iconURL;
  final bool? _supportsAuth;
  final Set<MetadataCapability> _capabilities;

  final MetadataCacheStore _cache = MetadataCacheStore.instance;
  final ServiceSessionManager _sessionManager = ServiceSessionManager.instance;

  JavascriptRuntime? _runtime;
  bool _isInitialized = false;
  bool _failedInit = false;
  int _reqCounter = 0;
  final Map<int, Completer<dynamic>> _pendingRequests = {};

  final Set<String> _likedTrackIds = {};
  bool _likedTracksLoaded = false;
  int? _likedTracksTotalCount;

  bool _auth = false;
  String? _cachedUserId;
  String? _cachedUserDisplayName;

  @override
  String get name => _name;

  @override
  String get displayName => _displayName;

  @override
  String get description => _description;

  @override
  String get logoURL => _logoURL;

  @override
  String get iconURL => _iconURL;

  @override
  bool get supportsAuth => _supportsAuth ?? true;

  @override
  Set<MetadataCapability> get capabilities => _capabilities;

  @override
  bool get isAuthenticated => _auth;

  @override
  String? get userId => _cachedUserId;

  @override
  String? get userDisplayName => _cachedUserDisplayName;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  bool get isLoading => _isLoading;

  void setLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners();
    }
  }

  @override
  String? get errorMessage => _errorMessage;

  @override
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  int? get likedTracksTotalCount => _likedTracksTotalCount;
  bool get hasLoadedLikedTracks => _likedTracksLoaded;

  @override
  bool isTrackLiked(String trackId) {
    if (trackId.isEmpty) return false;
    return _likedTrackIds.contains(trackId) ||
        _likedTrackIds.contains(_cleanId(trackId));
  }

  @override
  void setLikedTracksFromItems(List<PlaylistItem> items) {
    _likedTrackIds.clear();
    for (final item in items) {
      if (item.id.isNotEmpty) {
        _likedTrackIds.add(item.id);
        _likedTrackIds.add(_cleanId(item.id));
      }
    }
    _likedTracksTotalCount = items.length;
    _likedTracksLoaded = true;
    notifyListeners();
  }

  JsMetadataSource({
    required this.providerId,
    String? serviceId,
    String? name,
    String? displayName,
    String? description,
    String? logoURL,
    String? iconURL,
    bool? supportsAuth,
    Set<MetadataCapability>? capabilities,
    this.customScript,
    this.scriptPath,
  }) : serviceId = serviceId ?? providerId,
       _name = name ?? providerId,
       _displayName = displayName ?? name ?? providerId,
       _description =
           description ?? 'Modular metadata provider powered by QuickJS.',
       _logoURL = logoURL ?? '',
       _iconURL = iconURL ?? '',
       _supportsAuth = supportsAuth ?? true,
       _capabilities = capabilities ??
           (providerId == 'spotify'
               ? MetadataCapability.values.toSet()
               : const {MetadataCapability.search}) {
    _sessionManager.addListener(this.serviceId, (newSession) {
      _updateStateFromSession(newSession);
    });
    _initSessionState();
  }

  Future<void> _initSessionState() async {
    final session = await _sessionManager.getSession(serviceId);
    _updateStateFromSession(session);
    unawaited(initialize());
  }

  void _updateStateFromSession(Map<String, dynamic>? session) {
    final hadAuth = _auth;
    if (session == null || session.isEmpty) {
      _auth = false;
      _cachedUserId = null;
      _cachedUserDisplayName = null;
    } else {
      final isAuthFlag = session['isAuthenticated'] as bool?;
      final hasCookies =
          session['cookies'] is Map && (session['cookies'] as Map).isNotEmpty;
      final hasCookie =
          session['cookie'] is String &&
          (session['cookie'] as String).isNotEmpty;
      final hasToken =
          session['token'] != null || session['accessToken'] != null;
      _auth =
          isAuthFlag ??
          (hasCookies || hasCookie || hasToken || session['userId'] != null);
      if (_auth) {
        _cachedUserId = session['userId'] as String? ?? _cachedUserId;
        _cachedUserDisplayName =
            session['displayName'] as String? ?? _cachedUserDisplayName;
      } else {
        _cachedUserId = null;
        _cachedUserDisplayName = null;
      }
    }

    if (hadAuth != _auth) {
      notifyListeners();
    }
  }

  String _cleanId(String id) {
    if (id.contains(':')) {
      return id.split(':').last;
    }
    return id;
  }

  /// Initialize the JS runtime and load provider scripts.
  Future<void> initialize() async {
    if (_isInitialized || _failedInit) return;
    try {
      final script = customScript ?? await _loadProviderScript();
      if (script == null || script.isEmpty) {
        logger.w('[JsMetadataSource/$providerId] Provider script not found');
        return;
      }

      final runtime = getJavascriptRuntime();

      // Setup standard bridges
      JsProviderBridge.setupBridge(
        runtime,
        providerId: providerId,
        providerName: displayName,
        serviceId: serviceId,
      );

      // Result callback channel
      runtime.onMessage('wisp_metadata_result', (dynamic args) {
        try {
          final map = args is String
              ? jsonDecode(args) as Map<String, dynamic>
              : (args as Map).cast<String, dynamic>();
          final reqId = map['reqId'] as int?;
          if (reqId != null) {
            final completer = _pendingRequests.remove(reqId);
            if (completer != null && !completer.isCompleted) {
              if (map.containsKey('error') && map['error'] != null) {
                completer.completeError(Exception(map['error']));
              } else {
                completer.complete(map['result']);
              }
            }
          }
        } catch (e) {
          logger.e(
            '[JsMetadataSource/$providerId] Error in wisp_metadata_result: $e',
          );
        }
        return '';
      });

      // Invoker polyfill
      const invokerPolyfill = '''
        globalThis.__wisp_invoke_metadata = function(reqId, method, argsJson) {
          try {
            var args = typeof argsJson === 'string' ? JSON.parse(argsJson) : (argsJson || []);
            var fn = globalThis[method];
            if (!fn && globalThis.__wisp_metadata_provider) {
              fn = globalThis.__wisp_metadata_provider[method];
            }
            if (typeof fn !== 'function') {
              sendMessage('wisp_metadata_result', JSON.stringify({
                reqId: reqId,
                error: 'Method ' + method + ' is not a function'
              }));
              return;
            }
            Promise.resolve(fn.apply(null, args)).then(function(result) {
              sendMessage('wisp_metadata_result', JSON.stringify({
                reqId: reqId,
                result: result === undefined ? null : result
              }));
            }).catch(function(err) {
              sendMessage('wisp_metadata_result', JSON.stringify({
                reqId: reqId,
                error: String(err)
              }));
            });
          } catch (e) {
            sendMessage('wisp_metadata_result', JSON.stringify({
              reqId: reqId,
              error: String(e)
            }));
          }
        };
      ''';
      runtime.evaluate(invokerPolyfill);
      runtime.enableHandlePromises();

      // Wrap and evaluate provider script
      final wrapped =
          '''
        var exports = {};
        var module = { exports: exports };
        (function(exports, module) {
          $script
        })(exports, module);
        if (module.exports && typeof module.exports === 'object') {
          globalThis.__wisp_metadata_provider = module.exports;
          for (var k in module.exports) {
            if (typeof module.exports[k] === 'function') {
              globalThis[k] = module.exports[k];
            }
          }
        }
      ''';
      final evalRes = runtime.evaluate(wrapped);
      if (evalRes.isError) {
        logger.e(
          '[JsMetadataSource/$providerId] Script eval error: ${evalRes.stringResult}',
        );
        _failedInit = true;
        return;
      }

      _drainMicrotasks(runtime);
      _runtime = runtime;
      _isInitialized = true;
      logger.i(
        '[JsMetadataSource/$providerId] Successfully initialized JS metadata provider',
      );
    } catch (e) {
      _failedInit = true;
      logger.e('[JsMetadataSource/$providerId] Initialization error: $e');
    }
  }

  void _drainMicrotasks(JavascriptRuntime runtime) {
    try {
      while (runtime.executePendingJob() > 0) {}
    } catch (e) {
      logger.d('[JsMetadataSource] Microtask drainage: $e');
    }
  }

  Future<String?> _loadProviderScript() async {
    if (scriptPath != null) {
      final f = File(scriptPath!);
      if (f.existsSync()) return await f.readAsString();
    }

    // 1. Check local repository development paths
    final devPaths = [
      p.join(
        Directory.current.path,
        'providers',
        'metadata',
        providerId,
        'index.js',
      ),
      p.join(
        Directory.current.path,
        '..',
        '..',
        'providers',
        'metadata',
        providerId,
        'index.js',
      ),
      p.join(
        Directory.current.path,
        '..',
        'providers',
        'metadata',
        providerId,
        'index.js',
      ),
    ];
    for (final path in devPaths) {
      final f = File(path);
      if (f.existsSync()) {
        return await f.readAsString();
      }
    }

    // 2. Check application support directory
    try {
      final supportDir = await getApplicationSupportDirectory();
      final userFile = File(
        p.join(
          supportDir.path,
          'providers',
          'metadata',
          providerId,
          'index.js',
        ),
      );
      if (userFile.existsSync()) {
        return await userFile.readAsString();
      }
    } catch (_) {}

    return null;
  }

  Future<dynamic> _invoke(
    String method, [
    List<dynamic> args = const [],
  ]) async {
    if (!_isInitialized && !_failedInit) {
      await initialize();
    }
    final runtime = _runtime;
    if (runtime == null) {
      throw StateError('[JsMetadataSource] JS runtime not available');
    }

    final reqId = ++_reqCounter;
    final completer = Completer<dynamic>();
    _pendingRequests[reqId] = completer;

    final argsJson = jsonEncode(args);
    final call =
        'globalThis.__wisp_invoke_metadata($reqId, ${jsonEncode(method)}, ${jsonEncode(argsJson)});';
    final res = runtime.evaluate(call);
    if (res.isError) {
      _pendingRequests.remove(reqId);
      throw Exception('JS invoke error: ${res.stringResult}');
    }
    _drainMicrotasks(runtime);

    return await completer.future.timeout(const Duration(seconds: 25));
  }

  // ---------------------------------------------------------------------------
  // Caching Interceptors
  // ---------------------------------------------------------------------------

  Future<T> _getWithCache<T>({
    required String type,
    required String id,
    String? pageKey,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
    Duration? ttl,
    required Future<dynamic> Function() fetcher,
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    if (policy != MetadataFetchPolicy.refreshAlways) {
      final cached = await _cache.readEntry(
        provider: providerId,
        type: type,
        id: id,
        pageKey: pageKey,
      );
      if (cached != null) {
        if (policy == MetadataFetchPolicy.cacheFirst || !cached.isExpired) {
          return fromJson(cached.payload);
        }
      }
    }

    try {
      final raw = await fetcher();
      if (raw == null) {
        throw Exception('Provider returned null for $type $id');
      }
      final map = raw is Map<String, dynamic>
          ? raw
          : (raw as Map).cast<String, dynamic>();
      final item = fromJson(map);

      await _cache.writeEntry(
        provider: providerId,
        type: type,
        id: id,
        pageKey: pageKey,
        payload: toJson(item),
        ttl: ttl,
      );
      return item;
    } catch (e) {
      // Fallback on cached entry even if expired when offline
      final cached = await _cache.readEntry(
        provider: providerId,
        type: type,
        id: id,
        pageKey: pageKey,
      );
      if (cached != null) {
        logger.w(
          '[JsMetadataSource/$providerId] Fetch failed ($e), serving cached $type $id',
        );
        return fromJson(cached.payload);
      }
      rethrow;
    }
  }

  Future<List<T>> _getListWithCache<T>({
    required String type,
    required String id,
    String? pageKey,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
    Duration? ttl,
    required Future<dynamic> Function() fetcher,
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    if (policy != MetadataFetchPolicy.refreshAlways) {
      final cached = await _cache.readEntry(
        provider: providerId,
        type: type,
        id: id,
        pageKey: pageKey,
      );
      if (cached != null) {
        if (policy == MetadataFetchPolicy.cacheFirst || !cached.isExpired) {
          final items = cached.payload['items'] as List?;
          if (items != null) {
            final parsed = items
                .whereType<Map<String, dynamic>>()
                .map(fromJson)
                .toList();
            if (type.startsWith('saved_tracks') &&
                parsed.isNotEmpty &&
                parsed.any((it) => it is PlaylistItem && it.id.isEmpty)) {
              // Discard corrupted cache containing empty track IDs
            } else {
              return parsed;
            }
          }
        }
      }
    }

    try {
      final raw = await fetcher();
      final list = (raw as List?) ?? const [];
      final items = list
          .map((m) => fromJson((m as Map).cast<String, dynamic>()))
          .toList();

      await _cache.writeEntry(
        provider: providerId,
        type: type,
        id: id,
        pageKey: pageKey,
        payload: {'items': items.map(toJson).toList()},
        ttl: ttl,
      );
      return items;
    } catch (e) {
      final cached = await _cache.readEntry(
        provider: providerId,
        type: type,
        id: id,
        pageKey: pageKey,
      );
      if (cached != null) {
        final items = cached.payload['items'] as List?;
        if (items != null) {
          logger.w(
            '[JsMetadataSource/$providerId] List fetch failed ($e), serving cached $type',
          );
          final parsed = items.whereType<Map<String, dynamic>>().map(fromJson).toList();
          if (type.startsWith('saved_tracks') &&
              parsed.isNotEmpty &&
              parsed.any((it) => it is PlaylistItem && it.id.isEmpty)) {
            return const [];
          }
          return parsed;
        }
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // MetadataProvider Implementation
  // ---------------------------------------------------------------------------

  @override
  Future<void> login(BuildContext context) async {
    try {
      final auth = AuthSourceManager.instance.getAuthSource(serviceId);
      if (auth != null) {
        await auth.login();
      } else {
        await _invoke('login');
      }
      final session = await _sessionManager.getSession(serviceId);
      _updateStateFromSession(session);
      await fetchUserProfile();
    } catch (e) {
      logger.e('[JsMetadataSource/$providerId] Login error: $e');
    }
  }

  @override
  Future<void> logout() async {
    try {
      final auth = AuthSourceManager.instance.getAuthSource(serviceId);
      if (auth != null) {
        await auth.logout();
      } else {
        await _invoke('logout');
        await _sessionManager.clearSession(serviceId);
      }
      _likedTrackIds.clear();
      _likedTracksLoaded = false;
      _updateStateFromSession(null);
    } catch (e) {
      logger.e('[JsMetadataSource/$providerId] Logout error: $e');
    }
  }

  @override
  Future<GenericSong> getTrackInfo(
    String trackId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = _cleanId(trackId);
    return _getWithCache<GenericSong>(
      type: 'track',
      id: cleanId,
      policy: policy,
      fetcher: () => _invoke('getTrack', [cleanId]),
      toJson: (s) => s.toJson(),
      fromJson: GenericSong.fromJson,
    );
  }

  @override
  Future<GenericSong?> getCachedTrackInfo(String trackId) async {
    final cleanId = _cleanId(trackId);
    final cached = await _cache.readEntry(
      provider: providerId,
      type: 'track',
      id: cleanId,
    );
    return cached != null ? GenericSong.fromJson(cached.payload) : null;
  }

  @override
  Future<GenericAlbum> getAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = _cleanId(albumId);
    final pageKey = 'offset_${offset}_limit_$limit';
    return _getWithCache<GenericAlbum>(
      type: 'album',
      id: cleanId,
      pageKey: pageKey,
      policy: policy,
      fetcher: () => _invoke('getAlbum', [
        cleanId,
        {'offset': offset, 'limit': limit},
      ]),
      toJson: (a) => a.toJson(),
      fromJson: GenericAlbum.fromJson,
    );
  }

  @override
  Future<GenericAlbum?> getCachedAlbumInfo(
    String albumId, {
    int offset = 0,
    int limit = 50,
  }) async {
    final cleanId = _cleanId(albumId);
    final pageKey = 'offset_${offset}_limit_$limit';
    final cached = await _cache.readEntry(
      provider: providerId,
      type: 'album',
      id: cleanId,
      pageKey: pageKey,
    );
    return cached != null ? GenericAlbum.fromJson(cached.payload) : null;
  }

  @override
  Future<List<GenericSong>> getMoreAlbumTracks(
    String albumId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = _cleanId(albumId);
    final res = await _invoke('getMoreAlbumTracks', [
      cleanId,
      {'offset': offset, 'limit': limit},
    ]);
    final list = (res as List?) ?? const [];
    return list
        .map((m) => GenericSong.fromJson((m as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<GenericPlaylist> getPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = _cleanId(playlistId);
    final pageKey = 'offset_${offset}_limit_$limit';
    return _getWithCache<GenericPlaylist>(
      type: 'playlist',
      id: cleanId,
      pageKey: pageKey,
      policy: policy,
      fetcher: () => _invoke('getPlaylist', [
        cleanId,
        {'offset': offset, 'limit': limit},
      ]),
      toJson: (p) => p.toJson(),
      fromJson: GenericPlaylist.fromJson,
    );
  }

  @override
  Future<GenericPlaylist?> getCachedPlaylistInfo(
    String playlistId, {
    int offset = 0,
    int limit = 50,
  }) async {
    final cleanId = _cleanId(playlistId);
    final pageKey = 'offset_${offset}_limit_$limit';
    final cached = await _cache.readEntry(
      provider: providerId,
      type: 'playlist',
      id: cleanId,
      pageKey: pageKey,
    );
    return cached != null ? GenericPlaylist.fromJson(cached.payload) : null;
  }

  @override
  Future<List<PlaylistItem>> getMorePlaylistTracks(
    String playlistId, {
    required int offset,
    int limit = 50,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = _cleanId(playlistId);
    final res = await _invoke('getMorePlaylistTracks', [
      cleanId,
      {'offset': offset, 'limit': limit},
    ]);
    final list = (res as List?) ?? const [];
    return list
        .map((m) => PlaylistItem.fromJson((m as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<GenericArtist> getArtistInfo(
    String artistId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = _cleanId(artistId);
    return _getWithCache<GenericArtist>(
      type: 'artist',
      id: cleanId,
      policy: policy,
      fetcher: () => _invoke('getArtist', [cleanId]),
      toJson: (a) => a.toJson(),
      fromJson: GenericArtist.fromJson,
    );
  }

  @override
  Future<GenericArtist?> getCachedArtistInfo(String artistId) async {
    final cleanId = _cleanId(artistId);
    final cached = await _cache.readEntry(
      provider: providerId,
      type: 'artist',
      id: cleanId,
    );
    return cached != null ? GenericArtist.fromJson(cached.payload) : null;
  }

  @override
  Future<SearchResults> search(
    String query, {
    int limit = 20,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cacheId = 'query_${query}_limit_${limit}_offset_$offset';
    return _getWithCache<SearchResults>(
      type: 'search_all',
      id: cacheId,
      policy: policy,
      ttl: const Duration(hours: 2),
      fetcher: () => _invoke('search', [
        query,
        {'limit': limit, 'offset': offset},
      ]),
      toJson: (s) => s.toJson(),
      fromJson: SearchResults.fromJson,
    );
  }

  final Map<String, String?> _canvasMemoryCache = {};

  @override
  Future<String?> getCanvasUrl(String trackId) async {
    final cleanId = _cleanId(trackId);
    if (_canvasMemoryCache.containsKey(cleanId)) {
      return _canvasMemoryCache[cleanId];
    }

    final cached = await _cache.readEntry(
      provider: providerId,
      type: 'canvas',
      id: cleanId,
    );
    if (cached != null && !cached.isExpired) {
      final raw = cached.payload['url'] as String?;
      final url = (raw != null && raw.isNotEmpty) ? raw : null;
      _canvasMemoryCache[cleanId] = url;
      return url;
    }

    try {
      final res = await _invoke('getCanvasUrl', [cleanId]);
      final url = res as String?;
      final resolved = (url != null && url.isNotEmpty) ? url : null;
      _canvasMemoryCache[cleanId] = resolved;
      if (_canvasMemoryCache.length > 200) {
        _canvasMemoryCache.remove(_canvasMemoryCache.keys.first);
      }
      await _cache.writeEntry(
        provider: providerId,
        type: 'canvas',
        id: cleanId,
        payload: {'url': resolved ?? ''},
        ttl: const Duration(days: 7),
      );
      return resolved;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getTrackCanvasUrl(String trackId) => getCanvasUrl(trackId);

  @override
  Future<GenericHome> getUserHome({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    return _getWithCache<GenericHome>(
      type: 'home',
      id: 'home',
      policy: policy,
      ttl: const Duration(hours: 4),
      fetcher: () => _invoke('getUserHome', [{}]),
      toJson: (h) => h.toJson(),
      fromJson: GenericHome.fromJson,
    );
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
          (a) => GenericSimpleArtist(
            id: a.id,
            source: a.source,
            name: a.name,
            thumbnailUrl: a.thumbnailUrl,
          ),
        )
        .toList();
    if (offset >= items.length) return [];
    return items.take(limit).toList();
  }

  int get offset => 0;

  @override
  Future<List<PlaylistItem>> getUserSavedTracks({
    int limit = 50,
    int offset = 0,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final pageKey = 'offset_${offset}_limit_$limit';
    return _getListWithCache<PlaylistItem>(
      type: 'saved_tracks',
      id: 'saved_tracks',
      pageKey: pageKey,
      policy: policy,
      ttl: const Duration(days: 1),
      fetcher: () => _invoke('getUserSavedTracks', [
        {'offset': offset, 'limit': limit},
      ]),
      toJson: (p) => p.toJson(),
      fromJson: PlaylistItem.fromJson,
    );
  }

  @override
  Future<List<PlaylistItem>> getUserSavedTracksAll({
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    return _getListWithCache<PlaylistItem>(
      type: 'saved_tracks_all',
      id: 'all',
      policy: policy,
      ttl: const Duration(days: 1),
      fetcher: () => _invoke('getUserSavedTracksAll'),
      toJson: (p) => p.toJson(),
      fromJson: PlaylistItem.fromJson,
    );
  }

  @override
  Future<List<PlaylistItem>?> getCachedSavedTracksAll() async {
    final cached = await _cache.readEntry(
      provider: providerId,
      type: 'saved_tracks_all',
      id: 'all',
    );
    if (cached != null) {
      final items = cached.payload['items'] as List?;
      if (items != null) {
        final parsed = items
            .whereType<Map<String, dynamic>>()
            .map(PlaylistItem.fromJson)
            .toList();
        if (parsed.isNotEmpty && parsed.any((it) => it.id.isEmpty)) {
          return null;
        }
        return parsed;
      }
    }
    return null;
  }

  @override
  Future<void> refreshSavedTracksAll() async {
    await getUserSavedTracksAll(policy: MetadataFetchPolicy.refreshAlways);
  }

  Future<GenericLibrary> getUserLibrary({
    LibrarySortMode sortMode = LibrarySortMode.recent,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    String modeStr = 'recent';
    switch (sortMode) {
      case LibrarySortMode.alphabetical:
        modeStr = 'alphabetical';
        break;
      case LibrarySortMode.recentlyAdded:
        modeStr = 'recentlyAdded';
        break;
      case LibrarySortMode.recent:
        modeStr = 'recent';
        break;
    }

    return _getWithCache<GenericLibrary>(
      type: 'library',
      id: 'user_library_$modeStr',
      policy: policy,
      ttl: const Duration(hours: 6),
      fetcher: () => _invoke('getUserLibrary', [
        {'sortMode': modeStr},
      ]),
      toJson: (l) => l.toJson(),
      fromJson: GenericLibrary.fromJson,
    );
  }

  Future<GenericLibrary?> fetchUserLibrarySorted({
    required LibrarySortMode sortMode,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshAlways,
  }) async {
    return getUserLibrary(sortMode: sortMode, policy: policy);
  }

  @override
  Future<void> fetchUserProfile() async {
    try {
      final res = await _invoke('getUserProfile');
      if (res is Map) {
        _cachedUserId = res['id'] as String?;
        _cachedUserDisplayName = res['displayName'] as String?;
        notifyListeners();
      }
    } catch (e) {
      logger.w('[JsMetadataSource/$providerId] fetchUserProfile error: $e');
    }
  }

  @override
  Future<List<GenericSong>> getUserTopTracks({
    int limit = 20,
    String timeRange = 'short_term',
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      final res = await _invoke('getUserTopTracks', [limit, timeRange]);
      if (res is List) {
        return res
            .whereType<Map>()
            .map((m) => GenericSong.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  @override
  Future<List<GenericSimpleArtist>> getUserTopArtists({
    int limit = 20,
    String timeRange = 'short_term',
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    try {
      final res = await _invoke('getUserTopArtists', [limit, timeRange]);
      if (res is List) {
        return res
            .whereType<Map>()
            .map((m) => GenericSimpleArtist.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  @override
  Future<void> likeTrack(GenericSong track) async {
    final cleanId = _cleanId(track.id);
    await _invoke('likeTrack', [cleanId]);
    _likedTrackIds.add(cleanId);
    notifyListeners();
  }

  @override
  Future<void> unlikeTrack(GenericSong track) async {
    final cleanId = _cleanId(track.id);
    await _invoke('unlikeTrack', [cleanId]);
    _likedTrackIds.remove(cleanId);
    notifyListeners();
  }

  @override
  Future<void> toggleTrackLike(GenericSong track) async {
    final cleanId = _cleanId(track.id);
    if (_likedTrackIds.contains(cleanId)) {
      await unlikeTrack(track);
    } else {
      await likeTrack(track);
    }
  }

  @override
  Future<void> ensureLikedTracksLoaded() async {
    if (_likedTracksLoaded) return;
    try {
      final cached = await getUserSavedTracks(
        limit: 50,
        offset: 0,
        policy: MetadataFetchPolicy.cacheFirst,
      );
      setLikedTracksFromItems(cached);
    } catch (_) {
      _likedTracksLoaded = true;
      notifyListeners();
    }
  }

  @override
  Future<String> createPlaylist({
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    final id = await _invoke('createPlaylist', [
      {'name': name, 'description': description ?? '', 'isPublic': isPublic},
    ]);
    return id.toString();
  }

  @override
  Future<void> renamePlaylist(String playlistId, String name) async {
    await _invoke('renamePlaylist', [playlistId, name]);
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await _invoke('deletePlaylist', [playlistId]);
  }

  @override
  Future<void> addTracksToPlaylist(
    String playlistId,
    List<String> trackIds,
  ) async {
    await _invoke('addTracksToPlaylist', [playlistId, trackIds]);
  }

  Future<void> removeTracksFromPlaylist(
    String playlistId,
    List<String> trackIds,
  ) async {
    await _invoke('removeTracksFromPlaylist', [playlistId, trackIds]);
  }

  @override
  Future<List<PlaylistItem>?> getSimilarTracks(String trackId) async {
    try {
      final res = await _invoke('getSimilarTracks', [trackId]);
      if (res is List) {
        return res
            .whereType<Map>()
            .map((m) => PlaylistItem.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
      return null;
    } catch (e) {
      logger.w(
        '[JsMetadataSource/$providerId] getSimilarTracks failed for $trackId',
        error: e,
      );
      return null;
    }
  }

  @override
  Future<void> addPlaylistToFolder({
    required String playlistId,
    required String folderId,
  }) async {
    await _invoke('addPlaylistToFolder', [playlistId, folderId]);
  }

  @override
  Future<void> removePlaylistFromFolder({required String playlistId}) async {
    await _invoke('removePlaylistFromFolder', [playlistId]);
  }

  @override
  Future<List<String>> getTrackGenres(String trackId) async {
    try {
      final cleanId = _cleanId(trackId);
      final res = await _invoke('getTrackGenres', [cleanId]);
      if (res is List) {
        return res.whereType<String>().toList();
      }
      return const [];
    } catch (e) {
      logger.w('[JsMetadataSource/$providerId] getTrackGenres failed: $e');
      return const [];
    }
  }

  @override
  Future<void> saveAlbum(String albumId) async {
    final cleanId = _cleanId(albumId);
    await _invoke('saveAlbum', [cleanId]);
  }

  @override
  Future<void> unsaveAlbum(String albumId) async {
    final cleanId = _cleanId(albumId);
    await _invoke('unsaveAlbum', [cleanId]);
  }

  @override
  Future<void> followArtist(String artistId) async {
    final cleanId = _cleanId(artistId);
    await _invoke('followArtist', [cleanId]);
  }

  @override
  Future<void> unfollowArtist(String artistId) async {
    final cleanId = _cleanId(artistId);
    await _invoke('unfollowArtist', [cleanId]);
  }

  Future<GenericArtist> getNpvArtistInfo(
    String artistId,
    String trackId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    return getArtistInfo(artistId, policy: policy);
  }

  Future<void> checkAuthState() async {
    await initialize();
  }

  @override
  Future<GenericUser> getUserProfile(
    String userId, {
    int playlistLimit = 10,
    int artistLimit = 10,
    int episodeLimit = 10,
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = _cleanId(userId);
    return _getWithCache<GenericUser>(
      type: 'user_profile',
      id: cleanId,
      policy: policy,
      ttl: const Duration(hours: 4),
      fetcher: () => _invoke('getUserProfileView', [
        cleanId,
        {
          'playlistLimit': playlistLimit,
          'artistLimit': artistLimit,
          'episodeLimit': episodeLimit,
        },
      ]),
      toJson: (u) => u.toJson(),
      fromJson: GenericUser.fromJson,
    );
  }

  @override
  Future<List<GenericSimpleUser>> getUserFollowers(
    String userId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = _cleanId(userId);
    return _getListWithCache<GenericSimpleUser>(
      type: 'user_followers',
      id: cleanId,
      policy: policy,
      ttl: const Duration(hours: 4),
      fetcher: () => _invoke('getUserFollowers', [cleanId]),
      toJson: (u) => u.toJson(),
      fromJson: GenericSimpleUser.fromJson,
    );
  }

  @override
  Future<List<GenericSimpleUser>> getUserFollowing(
    String userId, {
    MetadataFetchPolicy policy = MetadataFetchPolicy.refreshIfExpired,
  }) async {
    final cleanId = _cleanId(userId);
    return _getListWithCache<GenericSimpleUser>(
      type: 'user_following',
      id: cleanId,
      policy: policy,
      ttl: const Duration(hours: 4),
      fetcher: () => _invoke('getUserFollowing', [cleanId]),
      toJson: (u) => u.toJson(),
      fromJson: GenericSimpleUser.fromJson,
    );
  }

  @override
  Future<List<PlaylistItem>> getRecommended(
    String playlistId,
    List<String> skippedTrackIDs, {
    int numResults = 20,
  }) async {
    final cleanId = _cleanId(playlistId);
    final res = await _invoke('getRecommended', [
      cleanId,
      skippedTrackIDs,
      numResults,
    ]);
    if (res is List) {
      return res
          .whereType<Map>()
          .map((m) => PlaylistItem.fromJson(m.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  @override
  Future<String?> getTrackIsrc(String trackId) async {
    final cleanId = _cleanId(trackId);
    try {
      final res = await _invoke('getTrackIsrc', [cleanId]);
      if (res is String && res.trim().isNotEmpty) {
        return res.trim();
      }
    } catch (e) {
      logger.w('[JsMetadataSource/$providerId] getTrackIsrc failed: $e');
    }
    return null;
  }

  Future<void> reportItemPlayed({
    required String itemId,
    required String itemType,
  }) async {
    // Stub preserved for interface compatibility
  }

  @override
  Map<String, dynamic> dumpJson() {
    return {
      'name': name,
      'providerId': providerId,
      'serviceId': serviceId,
      'isAuthenticated': isAuthenticated,
      'userId': userId,
      'userDisplayName': userDisplayName,
      'isInitialized': _isInitialized,
    };
  }

  @override
  void dispose() {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pendingRequests.clear();
    _runtime?.dispose();
    _runtime = null;
    super.dispose();
  }
}
