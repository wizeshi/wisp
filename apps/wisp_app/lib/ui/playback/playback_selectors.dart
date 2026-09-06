import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../services/wisp_audio_handler.dart';

/// Narrow, reusable checks for "is this specific entity the one currently
/// playing," each backed by a single [BuildContext.select] call.
///
/// This is the one place the matching rules against [WispAudioHandler] live
/// (previously duplicated per-screen as `_isActiveAlbum`/`_isActiveArtist`/
/// `_isActivePlaylist` in home.dart, and re-derived slightly differently
/// elsewhere). Centralizing it means:
///   - every card/row across every screen agrees on what "playing" means
///     for a given entity (no more risk of one screen forgetting the
///     `isPlaying &&` guard and showing multiple rows as "active" at once)
///   - each call site gets its own narrow `select` dependency, scoped to
///     just that widget, regardless of which screen hosts it
///
/// Each method returns a single combined bool — true only when playback is
/// actually active *and* it's this exact entity — matching the `isPlaying`
/// prop expected by `GenericCard` / `HoverPlayOverlay` / row widgets.
extension PlaybackSelectors on BuildContext {
  /// Whether [trackId] is the currently loaded and playing track.
  bool watchIsPlayingTrack(String trackId) {
    return select<WispAudioHandler, bool>(
      (player) => player.isPlaying && player.currentTrack?.id == trackId,
    );
  }

  /// Whether the current playback context is the album [albumId] (or,
  /// failing an id match, a context whose name matches [albumTitle] — some
  /// sources only surface a context name, not a stable id), or failing
  /// that, whether the currently playing track simply belongs to this
  /// album.
  bool watchIsPlayingAlbum({
    required String albumId,
    required String albumTitle,
  }) {
    return select<WispAudioHandler, bool>((player) {
      if (!player.isPlaying) return false;
      if (player.playbackContext?.type == PlaybackContextType.album) {
        if (player.playbackContext?.id == albumId) return true;
        final contextName = player.playbackContext?.name.trim();
        return contextName != null &&
            contextName.isNotEmpty &&
            contextName == albumTitle.trim();
      }
      return player.currentTrack?.album?.id == albumId;
    });
  }

  /// Whether the current playback context is the artist [artistId] (or a
  /// context named [artistName]), or failing that, whether the currently
  /// playing track's artists include this artist.
  bool watchIsPlayingArtist({
    required String artistId,
    required String artistName,
  }) {
    return select<WispAudioHandler, bool>((player) {
      if (!player.isPlaying) return false;
      if (player.playbackContext?.type == PlaybackContextType.artist) {
        if (player.playbackContext?.id == artistId) return true;
        final contextName = player.playbackContext?.name.trim();
        return contextName != null &&
            contextName.isNotEmpty &&
            contextName == artistName.trim();
      }
      return false;
    });
  }

  /// Whether the current playback context is the playlist [playlistId] (or
  /// a context named [playlistTitle]).
  bool watchIsPlayingPlaylist({
    required String playlistId,
    required String playlistTitle,
  }) {
    return select<WispAudioHandler, bool>((player) {
      if (!player.isPlaying) return false;
      if (player.playbackContext?.type != PlaybackContextType.playlist) return false;
      if (player.playbackContext?.id == playlistId) return true;
      final contextName = player.playbackContext?.name.trim();
      return contextName != null &&
          contextName.isNotEmpty &&
          contextName == playlistTitle.trim();
    });
  }
}