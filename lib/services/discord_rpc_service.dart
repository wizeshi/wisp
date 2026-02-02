/// Discord RPC service wrapper (desktop only)
library;

import 'dart:io' show Platform;
import 'package:flutter_discord_rpc/flutter_discord_rpc.dart';
import 'package:media_kit/generated/libmpv/bindings.dart';

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
      await FlutterDiscordRPC.initialize(_clientId);
      await FlutterDiscordRPC.instance.connect();
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<void> updatePresence({
    required GenericSong track,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
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
      smallImage: isPlaying ? _playIconKey : _pauseIconKey,
    );

    final activity = RPCActivity(
      activityType: ActivityType.listening,
      details: track.title,
      state: artistNames,
      assets: assets,
        timestamps: isPlaying && endMs != null
          ? RPCTimestamps(start: startMs, end: endMs)
          : isPlaying
            ? RPCTimestamps(start: startMs)
            : null,
    );

    await FlutterDiscordRPC.instance.setActivity(activity: activity);
  }

  Future<void> clearPresence() async {
    if (!_isDesktop || !_initialized) return;
    try {
      await FlutterDiscordRPC.instance.clearActivity();
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (!_isDesktop || !_initialized) return;
    try {
      await FlutterDiscordRPC.instance.clearActivity();
      await FlutterDiscordRPC.instance.disconnect();
    } catch (_) {}
    _initialized = false;
  }
}
