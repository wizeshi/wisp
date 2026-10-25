// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/auth/auth_source_manager.dart';
import 'package:wisp/features/connect/services/spotify_connect_models.dart';

/// Service that publishes Wisp as an official Spotify Web Playback device
/// ("wisp | {deviceName}") with Spotify's spclient backend and dealer WebSocket.
///
/// This accomplishes two key goals:
/// 1. Accurately reports track progress (30s+ threshold) to Spotify so listening
///    habits are synchronized (Recently Played, Wrapped, algorithm recommendations).
/// 2. Allows official Spotify apps (e.g. phone) to see Wisp as an active Connect device
///    and issue remote controls (play/pause/skip/seek/volume).
class SpotifyWebPlayerService extends ChangeNotifier {
  static final SpotifyWebPlayerService instance = SpotifyWebPlayerService._();
  SpotifyWebPlayerService._();

  static const String _keyDeviceId = 'spotify_web_player_device_id';
  static const String _spclientBase = 'https://spclient.wg.spotify.com';
  static const String _sdkVersion = 'harmony:4.67.0-887cfb0c3';

  String? _deviceId;
  String _localDeviceName = 'Unknown';
  bool _isRunning = false;
  WebSocket? _dealerSocket;
  String? _connectionId;
  Timer? _keepAliveTimer;

  // Active track state being reported
  int _volumeLevel = 65535; // 0..65535
  int _seqNum = 0;
  int _previousPositionMs = 0;
  bool _hasReportedThirtySeconds = false;
  Map<String, dynamic>? _lastStateRef;
  String? _currentSpotifyTrackUri;

  // Real-time discovered Spotify Connect devices from Connect-State
  List<SpotifyConnectDevice> _connectDevices = const [];
  List<SpotifyConnectDevice> get connectDevices => List.unmodifiable(_connectDevices);

  // Callbacks for remote commands received from official Spotify apps
  void Function()? onRemotePlay;
  void Function()? onRemotePause;
  void Function()? onRemoteNext;
  void Function()? onRemotePrevious;
  void Function(Duration position)? onRemoteSeek;
  void Function(double volume)? onRemoteVolume;
  void Function(String trackUri)? onRemoteTransfer;
  void Function(GenericSong song, {Duration? seekTo, bool isPaused})? onRemoteSongReceived;
  void Function(List<SpotifyConnectDevice> devices)? onDevicesChanged;

  String? get deviceId => _deviceId;
  String? get connectionId => _connectionId;
  String get publishedName => 'wisp | $_localDeviceName';
  bool get isConnected => _dealerSocket != null && _dealerSocket!.readyState == WebSocket.open;

  /// Initializes device ID and sets published local device name.
  Future<void> initialize({required String localDeviceName}) async {
    _localDeviceName = localDeviceName.trim().isEmpty ? 'Desktop' : localDeviceName.trim();
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_keyDeviceId);
    if (_deviceId == null || _deviceId!.length != 40) {
      final rand = Random.secure();
      final bytes = List<int>.generate(20, (_) => rand.nextInt(256));
      _deviceId = sha1.convert(bytes).toString();
      await prefs.setString(_keyDeviceId, _deviceId!);
    }
  }

  void updateLocalDeviceName(String name) {
    final clean = name.trim();
    if (clean.isNotEmpty && clean != _localDeviceName) {
      _localDeviceName = clean;
      if (_isRunning) {
        unawaited(_registerDevice());
      }
    }
  }

  Future<String?> _getAccessToken({bool forceRefresh = false}) async {
    try {
      final tokens = await AuthSourceManager.instance.getTokens(
        'spotify',
        forceRefresh: forceRefresh,
      );
      if (tokens == null) return null;
      return tokens['accessToken'] as String? ?? tokens['access_token'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getClientToken() async {
    try {
      final tokens = await AuthSourceManager.instance.getTokens('spotify');
      return tokens?['clientToken'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Starts the published Web Player session (connects dealer socket and registers device).
  Future<void> start() async {
    if (_isRunning) return;
    final token = await _getAccessToken();
    if (token == null || token.isEmpty) {
      logger.d('[SpotifyWebPlayer] No Spotify access token found, skipping Web Player startup');
      return;
    }
    _isRunning = true;
    await _connectDealer();
    _startKeepAlive();
  }

  /// Stops the published session and disconnects socket.
  Future<void> stop() async {
    _isRunning = false;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    try {
      await _dealerSocket?.close();
    } catch (_) {}
    _dealerSocket = null;
    _connectionId = null;
  }

  Future<void> _connectDealer() async {
    if (!_isRunning) return;
    try {
      final token = await _getAccessToken();
      if (token == null || token.isEmpty) return;

      final wsUrl = 'wss://dealer.spotify.com/?access_token=${Uri.encodeComponent(token)}';
      _dealerSocket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 10));

      logger.i('[SpotifyWebPlayer] Connected to Spotify Dealer WebSocket');

      _dealerSocket!.listen(
        _handleDealerMessage,
        onError: (err) {
          logger.w('[SpotifyWebPlayer] Dealer error: $err');
          _reconnectDealer();
        },
        onDone: () {
          logger.d('[SpotifyWebPlayer] Dealer connection closed');
          _reconnectDealer();
        },
      );
    } catch (e) {
      logger.w('[SpotifyWebPlayer] Dealer connection failed: $e');
      _reconnectDealer();
    }
  }

  void _reconnectDealer() {
    if (!_isRunning) return;
    _dealerSocket = null;
    Timer(const Duration(seconds: 5), () {
      if (_isRunning && _dealerSocket == null) {
        _connectDealer();
      }
    });
  }

  void _handleDealerMessage(dynamic data) {
    try {
      if (data is! String) return;
      final parsed = jsonDecode(data);
      if (parsed is! Map<String, dynamic>) return;

      final type = parsed['type'] as String?;

      // Auto-reply to dealer pings
      if (type == 'ping') {
        _dealerSocket?.add(jsonEncode({'type': 'pong'}));
        return;
      }

      final headers = parsed['headers'] as Map<String, dynamic>?;
      if (headers != null && headers['Spotify-Connection-Id'] != null) {
        _connectionId = headers['Spotify-Connection-Id'] as String;
        unawaited(_registerDevice());
        unawaited(refreshDevices());
      }

      final uri = parsed['uri'] as String? ?? '';
      final payloads = parsed['payloads'] as List<dynamic>?;

      if (uri.contains('connect-state')) {
        _handleConnectStateMessage(payloads);
      } else if (uri.contains('track-playback') || type == 'message') {
        _handleTrackPlaybackMessage(payloads);
      }
    } catch (e) {
      logger.d('[SpotifyWebPlayer] Parse dealer message ignored: $e');
    }
  }

  void _handleConnectStateMessage(List<dynamic>? payloads) {
    if (payloads == null || payloads.isEmpty) return;
    for (final p in payloads) {
      try {
        final decoded = p is String ? jsonDecode(p) : p;
        if (decoded is! Map<String, dynamic>) continue;
        final cluster = decoded['cluster'] as Map<String, dynamic>?;
        if (cluster != null) {
          _updateClusterDevices(cluster);
        }
      } catch (e) {
        logger.d('[SpotifyWebPlayer] Error parsing cluster: $e');
      }
    }
  }

  void _updateClusterDevices(Map<String, dynamic> cluster) {
    final devicesMap = cluster['devices'] as Map<String, dynamic>? ?? {};
    final activeDeviceId = cluster['active_device_id'] as String?;

    final result = <SpotifyConnectDevice>[];
    devicesMap.forEach((id, val) {
      if (val is Map<String, dynamic>) {
        final devId = val['device_id'] as String? ?? id;
        final name = val['name'] as String? ?? 'Unknown';
        final typeStr = val['device_type'] as String? ?? 'unknown';
        final volume = val['volume'] as num? ?? 0;
        final volumePercent = ((volume / 65535.0) * 100).round().clamp(0, 100);
        final caps = val['capabilities'] as Map<String, dynamic>?;
        final supportsVolume = caps?['disable_volume'] != true;

        result.add(SpotifyConnectDevice(
          id: devId,
          name: name,
          type: SpotifyDeviceType.fromString(typeStr),
          isActive: devId == activeDeviceId,
          isRestricted: false,
          volumePercent: volumePercent,
          supportsVolume: supportsVolume,
        ));
      }
    });

    _connectDevices = result;
    onDevicesChanged?.call(result);
    notifyListeners();
  }

  Future<List<SpotifyConnectDevice>> refreshDevices() async {
    if (_deviceId == null || _connectionId == null) return _connectDevices;
    try {
      final token = await _getAccessToken();
      if (token == null) return _connectDevices;

      final obsUri = Uri.parse('$_spclientBase/connect-state/v1/devices/hobs_$_deviceId');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Spotify-Connection-Id': _connectionId!,
      };

      final body = jsonEncode({
        'member_type': 'CONNECT_STATE',
        'device': {
          'device_info': {
            'capabilities': {
              'can_be_player': false,
              'hidden': true,
              'needs_full_player_state': true,
            },
          },
        },
      });

      final res = await http.put(obsUri, headers: headers, body: body);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final parsed = jsonDecode(res.body) as Map<String, dynamic>;
        final cluster = parsed['cluster'] as Map<String, dynamic>?;
        if (cluster != null) {
          _updateClusterDevices(cluster);
        }
      } else {
        logger.d('[SpotifyWebPlayer] Connect-state observer status: ${res.statusCode}');
      }
    } catch (e) {
      logger.d('[SpotifyWebPlayer] Connect-state observer error: $e');
    }
    return _connectDevices;
  }

  void _handleTrackPlaybackMessage(List<dynamic>? payloads) {
    if (payloads == null || payloads.isEmpty) return;
    for (final payload in payloads) {
      try {
        final decoded = payload is String ? jsonDecode(payload) : payload;
        if (decoded is! Map<String, dynamic>) continue;

        final command = decoded['command'] as Map<String, dynamic>? ?? decoded;
        final commandType = command['type'] as String? ?? '';
        final endpoint = command['endpoint'] as String? ?? '';

        logger.i('[SpotifyWebPlayer] Remote command: type=$commandType, endpoint=$endpoint');

        if (commandType == 'replace_state') {
          final stateMachine = command['state_machine'] as Map<String, dynamic>?;
          final stateRef = command['state_ref'] as Map<String, dynamic>?;
          final seekTo = int.tryParse(command['seek_to']?.toString() ?? '') ?? 0;

          GenericSong? remoteSong;
          String? trackUri;
          int durationMs = 0;

          if (stateMachine != null && stateRef != null) {
            final states = stateMachine['states'] as List<dynamic>?;
            final stateIndex = stateRef['state_index'] as int? ?? 0;
            if (states != null && stateIndex >= 0 && stateIndex < states.length) {
              final state = states[stateIndex] as Map<String, dynamic>?;
              final trackIdx = state?['track'] as int?;
              final tracks = stateMachine['tracks'] as List<dynamic>?;
              if (tracks != null && trackIdx != null && trackIdx >= 0 && trackIdx < tracks.length) {
                final track = tracks[trackIdx] as Map<String, dynamic>?;
                final meta = track?['metadata'] as Map<String, dynamic>?;
                trackUri = meta?['uri'] as String? ?? track?['uri'] as String?;
                final title = meta?['title'] as String? ?? 'Unknown Title';
                final artist = meta?['artist_name'] as String? ?? 'Unknown Artist';
                final album = meta?['album_title'] as String? ?? '';
                final coverUrl = meta?['image_url'] as String? ?? '';
                durationMs = int.tryParse(meta?['duration']?.toString() ?? '') ?? 0;

                if (trackUri != null && trackUri.isNotEmpty) {
                  final cleanId = trackUri.replaceFirst('spotify:track:', '');
                  remoteSong = GenericSong(
                    id: cleanId,
                    source: 'spotify',
                    title: title,
                    artists: [
                      GenericSimpleArtist(
                        id: '',
                        source: 'spotify',
                        name: artist,
                        thumbnailUrl: '',
                      ),
                    ],
                    thumbnailUrl: coverUrl,
                    explicit: false,
                    album: album.isNotEmpty
                        ? GenericSimpleAlbum(
                            id: '',
                            source: 'spotify',
                            title: album,
                            thumbnailUrl: coverUrl,
                            artists: const [],
                            label: '',
                            releaseDate: DateTime.now(),
                          )
                        : null,
                    durationSecs: (durationMs / 1000).round(),
                  );
                }
              }
            }
          }

          final isPaused = stateRef?['paused'] == true;
          logger.i('[SpotifyWebPlayer] Acknowledging replace_state: track=$trackUri, paused=$isPaused, seekTo=${seekTo}ms');

          // Send immediate state confirmation so Spotify app confirms connection and stops showing "connecting..."
          unawaited(_sendStateConfirmation(
            stateRef: stateRef,
            positionMs: seekTo,
            isPaused: isPaused,
            durationMs: durationMs,
          ));

          if (trackUri != null && trackUri.isNotEmpty) {
            _currentSpotifyTrackUri = trackUri;
          }
          if (remoteSong != null) {
            onRemoteSongReceived?.call(remoteSong, seekTo: Duration(milliseconds: seekTo), isPaused: isPaused);
          } else if (trackUri != null && trackUri.isNotEmpty) {
            onRemoteTransfer?.call(trackUri);
          }
        } else if (commandType == 'ping') {
          unawaited(_sendStateConfirmation());
        } else if (endpoint.contains('resume') || commandType == 'resume') {
          onRemotePlay?.call();
          unawaited(_sendStateConfirmation(isPaused: false));
        } else if (endpoint.contains('pause') || commandType == 'pause') {
          onRemotePause?.call();
          unawaited(_sendStateConfirmation(isPaused: true));
        } else if (endpoint.contains('skip_next') || commandType == 'skip_next') {
          onRemoteNext?.call();
        } else if (endpoint.contains('skip_prev') || commandType == 'skip_prev') {
          onRemotePrevious?.call();
        } else if (endpoint.contains('seek_to') || commandType == 'seek_to') {
          final posMs = command['value'] as int? ?? command['position'] as int?;
          if (posMs != null) {
            onRemoteSeek?.call(Duration(milliseconds: posMs));
            unawaited(_sendStateConfirmation(positionMs: posMs));
          }
        } else if (endpoint.contains('set_volume') || commandType == 'set_volume') {
          final volVal = command['value'] as num? ?? command['volume'] as num?;
          if (volVal != null) {
            final double normalized = (volVal.toDouble() / 65535.0).clamp(0.0, 1.0);
            _volumeLevel = volVal.round().clamp(0, 65535);
            onRemoteVolume?.call(normalized);
          }
        }
      } catch (e) {
        logger.w('[SpotifyWebPlayer] Remote command processing error: $e');
      }
    }
  }

  Future<void> _registerDevice() async {
    if (_deviceId == null || _connectionId == null) return;
    try {
      final token = await _getAccessToken();
      if (token == null) return;
      final clientToken = await _getClientToken();

      final regUri = Uri.parse('$_spclientBase/track-playback/v1/devices');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        if (clientToken != null && clientToken.isNotEmpty) 'Client-Token': clientToken,
      };

      final body = jsonEncode({
        'device': {
          'brand': 'SpotifyHarmonyGeneric',
          'capabilities': {
            'change_volume': true,
            'enable_play_token': true,
            'supports_file_media_type': true,
            'play_token_lost_behavior': 'pause',
            'disable_connect': false,
            'audio_podcasts': true,
            'video_playback': false,
            'manifest_formats': [
              'file_ids_mp3',
              'file_urls_mp3',
              'manifest_urls_audio_ad',
            ],
            'supports_preferred_media_type': true,
            'supports_playback_offsets': true,
            'supports_playback_speed': true,
          },
          'device_id': _deviceId,
          'device_type': 'computer',
          'metadata': <String, dynamic>{},
          'model': 'web_player',
          'name': publishedName,
          'platform_identifier': 'web_player',
          'platform_name': 'web_player',
          'is_group': false,
        },
        'connection_id': _connectionId,
        'client_version': _sdkVersion,
        'volume': _volumeLevel,
        'outro_endcontent_snooping': false,
      });

      final res = await http.post(regUri, headers: headers, body: body);
      if (res.statusCode == 200 || res.statusCode == 204) {
        if (res.body.isNotEmpty) {
          try {
            final parsed = jsonDecode(res.body) as Map<String, dynamic>;
            if (parsed['initial_seq_num'] is int) {
              _seqNum = parsed['initial_seq_num'] as int;
            }
          } catch (_) {}
        }
        logger.i('[SpotifyWebPlayer] Successfully published device "$publishedName" on Spotify Connect');
      } else {
        logger.w('[SpotifyWebPlayer] Device registration status: ${res.statusCode}, body: ${res.body}');
      }
    } catch (e) {
      logger.w('[SpotifyWebPlayer] Device registration error: $e');
    }
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_isRunning && _connectionId != null) {
        _registerDevice();
      }
    });
  }

  Future<void> _notifyTrackPlay(String spotifyUri) async {
    if (_deviceId == null || _connectionId == null) return;
    try {
      final token = await _getAccessToken();
      if (token == null) return;

      final uri = Uri.parse('$_spclientBase/connect-state/v1/player/command/from/$_deviceId/to/$_deviceId');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Spotify-Connection-Id': _connectionId!,
      };

      final body = jsonEncode({
        'command': {
          'endpoint': 'play',
          'context': {
            'url': 'context:$spotifyUri',
          },
          'play_origin': {
            'feature_identifier': 'wisp',
          },
        },
      });

      final res = await http.post(uri, headers: headers, body: body);
      logger.i('[SpotifyWebPlayer] Notified track play to Spotify for $spotifyUri: status ${res.statusCode}');
      if (res.statusCode != 200 && res.statusCode != 204) {
        logger.w('[SpotifyWebPlayer] Notify track play response: ${res.body}');
      }
    } catch (e) {
      logger.w('[SpotifyWebPlayer] Failed to notify track play: $e');
    }
  }

  Future<void> _sendStateConfirmation({
    Map<String, dynamic>? stateRef,
    int positionMs = 0,
    bool isPaused = false,
    int durationMs = 0,
  }) async {
    try {
      final token = await _getAccessToken();
      if (token == null || _deviceId == null) return;
      final clientToken = await _getClientToken();

      if (stateRef != null) {
        _lastStateRef = stateRef;
      }

      if (_lastStateRef == null) {
        logger.d('[SpotifyWebPlayer] Cannot send state confirmation: stateRef is null');
        return;
      }

      final stateUri = Uri.parse('$_spclientBase/track-playback/v1/devices/$_deviceId/state');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        if (clientToken != null && clientToken.isNotEmpty) 'Client-Token': clientToken,
      };

      _seqNum++;
      final body = jsonEncode({
        'seq_num': _seqNum,
        'state_ref': _lastStateRef,
        'sub_state': {
          'playback_speed': isPaused ? 0 : 1,
          'position': positionMs,
          'duration': durationMs,
          'media_type': 'AUDIO',
          'bitrate': 160000,
          'audio_quality': 'VERY_HIGH',
          'format': 'file_urls_external',
          'is_video_on': false,
        },
        'previous_position': _previousPositionMs,
        'debug_source': 'modify_current_state',
      });
      _previousPositionMs = positionMs;

      final res = await http.put(stateUri, headers: headers, body: body);
      logger.i('[SpotifyWebPlayer] State confirmation result: ${res.statusCode}');
      if (res.statusCode != 200 && res.statusCode != 204) {
        logger.w('[SpotifyWebPlayer] State confirmation rejected: ${res.body}');
      }
    } catch (e) {
      logger.w('[SpotifyWebPlayer] State confirmation failed: $e');
    }
  }

  /// Reports local track playback progression to Spotify's track-playback state endpoint.
  ///
  /// Calling this continuously while a track is playing allows Spotify to track
  /// listening habits, register the 30-second stream milestone for Wrapped/history,
  /// and inform other devices of current playback progress.
  Future<void> reportPlaybackState({
    required GenericSong track,
    required bool isPlaying,
    required Duration position,
    double volume = 1.0,
  }) async {
    _volumeLevel = (volume.clamp(0.0, 1.0) * 65535).round();

    // Only report for Spotify-sourced tracks
    final isSpotifyTrack = track.source.toLowerCase() == 'spotify' ||
        track.id.startsWith('spotify:track:');

    if (!isSpotifyTrack || _deviceId == null) return;

    final cleanId = track.id.replaceFirst('spotify:track:', '');
    final spotifyUri = 'spotify:track:$cleanId';

    // If starting a new track, notify Spotify Connect to establish state_machine & state_ref
    if (_currentSpotifyTrackUri != spotifyUri) {
      _currentSpotifyTrackUri = spotifyUri;
      _hasReportedThirtySeconds = false;
      _lastStateRef = null;
      _previousPositionMs = 0;
      unawaited(_notifyTrackPlay(spotifyUri));
      return;
    }

    // Skip if state_ref has not yet arrived from Spotify Dealer WebSocket
    if (_lastStateRef == null) {
      return;
    }

    // Track 30-second milestone
    if (position.inSeconds >= 30 && !_hasReportedThirtySeconds) {
      _hasReportedThirtySeconds = true;
      logger.i('[SpotifyWebPlayer] Reached 30s playback threshold for "${track.title}" - reporting stream to Spotify history');
      await _putTrackState(spotifyUri, track, isPlaying: true, position: position);
    } else {
      await _putTrackState(spotifyUri, track, isPlaying: isPlaying, position: position);
    }
  }

  /// Reset 30s milestone on track change
  void onTrackChanged() {
    _hasReportedThirtySeconds = false;
    _previousPositionMs = 0;
    _currentSpotifyTrackUri = null;
    _lastStateRef = null;
  }

  Future<void> _putTrackState(
    String spotifyUri,
    GenericSong track, {
    required bool isPlaying,
    required Duration position,
  }) async {
    if (_lastStateRef == null) return;
    try {
      final token = await _getAccessToken();
      if (token == null || _deviceId == null) return;
      final clientToken = await _getClientToken();

      final stateUri = Uri.parse('$_spclientBase/track-playback/v1/devices/$_deviceId/state');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        if (clientToken != null && clientToken.isNotEmpty) 'Client-Token': clientToken,
      };

      final durationMs = track.durationSecs * 1000;
      _seqNum++;

      final body = jsonEncode({
        'seq_num': _seqNum,
        'state_ref': _lastStateRef,
        'sub_state': {
          'playback_speed': isPlaying ? 1 : 0,
          'position': position.inMilliseconds,
          'duration': durationMs,
          'media_type': 'AUDIO',
          'bitrate': 160000,
          'audio_quality': 'VERY_HIGH',
          'format': 'file_urls_external',
          'is_video_on': false,
        },
        'previous_position': _previousPositionMs,
        'debug_source': 'track_data_finalized',
      });
      _previousPositionMs = position.inMilliseconds;

      final res = await http.put(stateUri, headers: headers, body: body);
      if (res.statusCode != 200 && res.statusCode != 204) {
        logger.w('[SpotifyWebPlayer] Put state status: ${res.statusCode}, body: ${res.body}');
      }
    } catch (_) {}
  }
}
