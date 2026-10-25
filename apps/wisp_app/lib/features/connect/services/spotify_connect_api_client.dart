// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/features/connect/services/spotify_connect_models.dart';
import 'package:wisp/features/connect/services/spotify_web_player_service.dart';

class SpotifyConnectApiClient {
  static final SpotifyConnectApiClient instance = SpotifyConnectApiClient._();
  SpotifyConnectApiClient._();

  static const String _spclientConnectBase = 'https://spclient.wg.spotify.com/connect-state/v1';

  bool get isRateLimited => false;
  int get rateLimitSecondsRemaining => 0;

  Future<String?> _getAccessToken({bool forceRefresh = false}) async {
    try {
      final tokens = await AuthSourceManager.instance.getTokens(
        'spotify',
        forceRefresh: forceRefresh,
      );
      if (tokens == null) return null;
      return tokens['accessToken'] as String? ?? tokens['access_token'] as String?;
    } catch (e) {
      logger.w('[SpotifyConnect/API] Failed to get Spotify access token: $e');
      return null;
    }
  }

  String? get _localDeviceId => SpotifyWebPlayerService.instance.deviceId;
  String? get _connectionId => SpotifyWebPlayerService.instance.connectionId;

  Map<String, String> _buildHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_connectionId != null && _connectionId!.isNotEmpty)
          'X-Spotify-Connection-Id': _connectionId!,
      };

  /// Fetches the list of all available Spotify Connect devices on the user's account
  /// via Spotify's internal Connect-State protocol (bypassing public API rate limits).
  Future<List<SpotifyConnectDevice>> fetchDevices() async {
    return await SpotifyWebPlayerService.instance.refreshDevices();
  }

  /// Transfers playback to a target Spotify Connect device using Connect-State transfer.
  Future<bool> transferPlayback(String deviceId, {bool play = true}) async {
    final fromId = _localDeviceId;
    if (fromId == null) return false;
    try {
      final token = await _getAccessToken();
      if (token == null) return false;

      final uri = Uri.parse('$_spclientConnectBase/connect/transfer/from/$fromId/to/$deviceId');
      final body = jsonEncode({
        'transfer_options': {
          'restore_paused': play ? 'restore' : 'pause',
        },
      });

      final res = await http.post(uri, headers: _buildHeaders(token), body: body);
      if (res.statusCode == 200 || res.statusCode == 204) {
        logger.i('[SpotifyConnect/API] Successfully transferred playback to $deviceId');
        return true;
      }
      logger.w('[SpotifyConnect/API] Transfer status ${res.statusCode}: ${res.body}');
      return false;
    } catch (e) {
      logger.w('[SpotifyConnect/API] transferPlayback failed: $e');
      return false;
    }
  }

  /// Sends a player command (pause, resume, skip_next, skip_prev, seek_to) to a target device.
  Future<bool> _sendPlayerCommand(String? deviceId, String endpoint, {Map<String, dynamic>? extra}) async {
    final fromId = _localDeviceId;
    if (fromId == null || deviceId == null) return false;
    try {
      final token = await _getAccessToken();
      if (token == null) return false;

      final uri = Uri.parse('$_spclientConnectBase/player/command/from/$fromId/to/$deviceId');
      final body = jsonEncode({
        'command': {
          'endpoint': endpoint,
          ...?extra,
        },
      });

      final res = await http.post(uri, headers: _buildHeaders(token), body: body);
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      logger.w('[SpotifyConnect/API] Command $endpoint failed: $e');
      return false;
    }
  }

  /// Resumes playback on the active Spotify Connect device.
  Future<bool> resume({String? deviceId}) async {
    return _sendPlayerCommand(deviceId, 'resume');
  }

  /// Pauses playback on the active Spotify Connect device.
  Future<bool> pause({String? deviceId}) async {
    return _sendPlayerCommand(deviceId, 'pause');
  }

  /// Skips to the next track on the active Spotify Connect device.
  Future<bool> next({String? deviceId}) async {
    return _sendPlayerCommand(deviceId, 'skip_next');
  }

  /// Skips to the previous track on the active Spotify Connect device.
  Future<bool> previous({String? deviceId}) async {
    return _sendPlayerCommand(deviceId, 'skip_prev');
  }

  /// Seeks to a specific playback position in milliseconds.
  Future<bool> seek(Duration position, {String? deviceId}) async {
    return _sendPlayerCommand(
      deviceId,
      'seek_to',
      extra: {'value': position.inMilliseconds},
    );
  }

  /// Sets volume percentage (0..100) on the target device via Connect-State.
  Future<bool> setVolume(int volumePercent, {String? deviceId}) async {
    final fromId = _localDeviceId;
    if (fromId == null || deviceId == null) return false;
    try {
      final token = await _getAccessToken();
      if (token == null) return false;

      final uri = Uri.parse('$_spclientConnectBase/connect/volume/from/$fromId/to/$deviceId');
      final gaiaVol = ((volumePercent.clamp(0, 100) / 100.0) * 65535).round();
      final body = jsonEncode({'volume': gaiaVol});

      final res = await http.put(uri, headers: _buildHeaders(token), body: body);
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      logger.w('[SpotifyConnect/API] setVolume failed: $e');
      return false;
    }
  }

  /// Starts playback of specific Spotify track URIs on a target device.
  Future<bool> playUris({
    String? deviceId,
    required List<String> uris,
    int offsetIndex = 0,
    int positionMs = 0,
  }) async {
    if (uris.isEmpty) return false;
    final targetUri = uris[offsetIndex.clamp(0, uris.length - 1)];
    return _sendPlayerCommand(
      deviceId,
      'play',
      extra: {
        'play_origin': {'feature_identifier': 'connect'},
        'options': {'override_restrictions': true},
        'context': {'url': 'context:$targetUri'},
      },
    );
  }

  /// Fetches current playback state.
  Future<Map<String, dynamic>?> fetchCurrentPlayback() async {
    return null;
  }
}
