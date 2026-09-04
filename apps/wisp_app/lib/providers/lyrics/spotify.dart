// Copyright © 2026 wizeshi

/// Spotify lyrics provider using internal API + TOTP
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wisp/providers/common/spotify_tokens.dart';
import '../../models/metadata_models.dart';
import '../../services/credentials.dart';
import '../../utils/logger.dart';

const _spotifyLyricsBaseUrl =
    'https://spclient.wg.spotify.com/color-lyrics/v2/track';

class SpotifyLyricsProvider {
  final CredentialsService _credentialsService = CredentialsService();
  Future<void>? _initFuture;
  String? _clientToken;
  String? _accessToken;

  DateTime? _lastTokenRefresh;

  void _log(String message) {
    logger.i("[Lyrics/Spotify] $message");
  }

  Future<void> _ensureInitialized() {
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    _log("Initializing provider...");

    final cookie = await _credentialsService.getSpotifyLyricsCookie();
    if (cookie == null || cookie.isEmpty) {
      throw StateError('Spotify lyrics cookie (sp_dc) not configured');
    }

    try {
      final tokenData = await fetchSpotifyTokens(cookie, _log);
      _accessToken = tokenData.accessToken;
      _clientToken = tokenData.clientToken;
    } catch (e) {
      _log("Failed to fetch Spotify tokens: $e");
      throw StateError('Failed to initialize Spotify lyrics provider');
    }
  }

  Future<void> _refreshTokens() async {
    _log("Trying to refresh tokens...");
    if (_lastTokenRefresh != null &&
      DateTime.now().isBefore(_lastTokenRefresh!.add(const Duration(minutes: 30)))
    ) {
      _log("Tokens are still within validity period (30 minutes), skipping refresh.");
      return;
    }
    _accessToken = null;
    _clientToken = null;
    _lastTokenRefresh = null;
    
    await _initialize();
  }

  Future<LyricsResult?> getLyrics(String trackId) async {
    try {
      await _ensureInitialized();
    } catch (_) {
      return null;
    }

    if (_accessToken == null || _clientToken == null) return null;

    final normalizedId = _normalizeTrackId(trackId);
    if (normalizedId.isEmpty) return null;

    final url = Uri.parse('$_spotifyLyricsBaseUrl/$normalizedId').replace(
      queryParameters: {
        'format': 'json',
        'vocalRemoval': 'false',
        'market': 'from_token',
      },
    );

    final client = createSpotifyHttpClient();
    http.Response response;
    try {
      response = await client.get(
        url,
        headers: {
          'App-Platform': 'WebPlayer',
          'Accept': 'application/json',
          'Authorization': 'Bearer $_accessToken',
          'Client-Token': _clientToken!,
          'User-Agent': spotifyUserAgent,
          'Spotify-App-Version': spotifyAppVersion,
        },
      );
    } finally {
      client.close();
    }

    if (response.statusCode == 401) {
      _log('Request unauthorized, refreshing token...');
      _initFuture = null;
      try {
        await _refreshTokens();
      } catch (_) {
        return null;
      }
      return getLyrics(trackId);
    }

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      _log('Request failed: ${response.statusCode}');
      return null;
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final lyrics = json['lyrics'] as Map<String, dynamic>?;
      if (lyrics == null) return null;
      final syncType = lyrics['syncType'] as String? ?? 'LINE_UNSYNCED';
      final linesJson = lyrics['lines'] as List? ?? const [];
      final lines = linesJson
          .whereType<Map<String, dynamic>>()
          .map((line) {
            final content = (line['words'] as String?)?.trim() ?? '';
            final startMsRaw = line['startTimeMs'];
            final startTimeMs = startMsRaw is String
                ? int.tryParse(startMsRaw) ?? 0
                : startMsRaw is int
                ? startMsRaw
                : 0;
            return LyricsLine(content: content, startTimeMs: startTimeMs);
          })
          .where((line) => line.content.isNotEmpty)
          .toList();

      return LyricsResult(
        provider: LyricsProviderType.spotify,
        syncMode: syncType == 'LINE_SYNCED' ? LyricsSyncMode.line : LyricsSyncMode.unsynced,
        lines: lines,
      );
    } catch (e, stackTrace) {
      _log(
        'Failed to parse response'
        ' for track $trackId: $e\n$stackTrace',
      );
      return null;
    }
  }
}

String _normalizeTrackId(String trackId) {
  var id = trackId.trim();
  if (id.contains('?')) {
    id = id.split('?').first;
  }
  if (id.contains('spotify:')) {
    final parts = id.split(':');
    id = parts.isNotEmpty ? parts.last : id;
  }
  if (id.contains('/')) {
    final uri = Uri.tryParse(id);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      id = uri.pathSegments.last;
    }
  }
  return id.trim();
}
