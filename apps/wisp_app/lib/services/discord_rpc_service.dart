/// Discord RPC service wrapper (desktop only)
library;

import 'dart:io' show Platform;

import 'package:wisp/services/rpc/discord_rpc_api.dart';
import 'package:wisp/services/rpc/types.dart';

import '../models/metadata_models.dart';

class DiscordRpcService {
  DiscordRpcService._();

  static final DiscordRpcService instance = DiscordRpcService._();

  static const String _clientId = '1467666801369288923';

  static const String _fallbackCoverUrl =
      'https://raw.githubusercontent.com/wizeshi/wisp/refs/heads/master/assets/wisp.png';

  // Discord asset keys for play/pause icons.
  static const String _playIconKey = 'play_arrow';
  static const String _pauseIconKey = 'pause';

  bool _initialized = false;

  bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  Future<void> initialize() async {
    if (!_isDesktop || _initialized) return;
    try {
      await DiscordRpcApi.instance.initialize(_clientId);
      await DiscordRpcApi.instance.connect();
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  // Uses a JSON object to generate a Wisp URL for the given element.
  // Type can be "track", "album", "playlist" or "artist".
  String getWispUrlForElement(String type, Map<String, dynamic> element) {
    // check if element has source and id properties
    if (element.containsKey('source') && element.containsKey('id')) {
      final parsedSource = SongSource.fromJson(element['source']);
      final parsedID = element['id'] as String;

      String source = '';

      switch (parsedSource) {
        case SongSource.spotify:
        case SongSource.spotifyInternal:
          source = 'spotify';
          break;
        case SongSource.youtube:
          source = 'youtube';
          break;
        default:
          throw ArgumentError('Unsupported source: $parsedSource');
      }

      final id = parsedID.startsWith("spotify:") ? parsedID.split(":")[2] : parsedID;

      return 'wisp://play/$type/$id?source=$source';
    } else {
      throw ArgumentError('Element must have source and id properties');
    }
  }

  Future<void> updatePresence({
    required GenericSong track,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    String? contextId,
  }) async {
    if (!_isDesktop || !_initialized) return;

    final artistNames = track.artists.map((a) => a.name).join(', ');
    final albumName = track.album?.title ?? 'Unknown';
    final coverUrl = track.thumbnailUrl.isNotEmpty
        ? track.thumbnailUrl
        : _fallbackCoverUrl;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final positionMs = position.inMilliseconds;
    final durationMs = duration.inMilliseconds;
    final startMs = nowMs - positionMs;
    final endMs = durationMs > 0 ? startMs + durationMs : null;

    final assets = RPCAssets(
      largeImage: coverUrl,
      largeText: 'From $albumName',
      smallImage: isPlaying ? _pauseIconKey : _playIconKey,
    );

    String trackID = track.id.startsWith("spotify:") ? track.id.split(":")[2] : track.id;

    String trackURL = '';

    switch (track.source) {
      case SongSource.spotify:
      case SongSource.spotifyInternal:
        trackURL = 'https://open.spotify.com/track/${trackID}';
        break;
      case SongSource.youtube:
        trackURL = 'https://www.youtube.com/watch?v=${trackID}';
        break;
      case _:
        break;
    }

    String trackSource = "";
    switch (track.source) {
      case SongSource.spotify:
      case SongSource.spotifyInternal:
        trackSource = "Spotify";
        break;
      case SongSource.youtube:
        trackSource = "YouTube";
        break;
      case _:
        trackSource = "Unknown";
        break;
    }

    final listenOriginButton = RPCButton(
      label: 'Listen on $trackSource',
      url: trackURL,
    );

    final wispTrackUrl = getWispUrlForElement("track", track.toJson());

    final listenAppButton = RPCButton(
      label: 'Listen on Wisp',
      url: wispTrackUrl,
    );

    RPCButton playlistButton = listenOriginButton;

    if (contextId != null) {
      if (track.album != null && track.album!.id == contextId) {
        // It's an album
        final albumURL = getWispUrlForElement("album", track.album!.toJson());
        playlistButton = RPCButton(
          label: 'View Album',
          url: albumURL,
        );
      } else {
        // It's a playlist
        final playlistURL = getWispUrlForElement("playlist", {
          'source': track.source.toJson(),
          'id': contextId,
        });
        playlistButton = RPCButton(
          label: 'View Playlist',
          url: playlistURL,
        );
      }
    }

    final activity = RPCActivity(
      type: ActivityType.listening,
      details: track.title,
      state: artistNames,
      assets: assets,
      statusDisplayType: ActivityStatusDisplayType.state,
      buttons: [listenAppButton, playlistButton],
      timestamps: isPlaying && endMs != null
          ? RPCTimestamps(start: startMs, end: endMs)
          : isPlaying
            ? RPCTimestamps(start: startMs)
            : null,
    );

    await DiscordRpcApi.instance.setActivity(activity: activity);
  }

  Future<void> clearPresence() async {
    if (!_isDesktop || !_initialized) return;
    try {
      await DiscordRpcApi.instance.clearActivity();
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (!_isDesktop || !_initialized) return;
    try {
      await DiscordRpcApi.instance.clearActivity();
      await DiscordRpcApi.instance.disconnect();
    } catch (_) {}
    _initialized = false;
  }
}
