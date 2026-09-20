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
  ///
  /// Deliberately does *not* check playback context — it answers "is this
  /// song, anywhere, the one making sound," which is what a mini-player or
  /// a global "now playing" indicator wants. A row embedded in a specific
  /// playlist/album/artist/search view almost always wants
  /// [watchIsCurrentTrackHere] / [watchIsPlayingTrackHere] instead, or it
  /// will show the same song as "playing" in every list that happens to
  /// contain it.
  bool watchIsPlayingTrack(String trackId) {
    return select<WispAudioHandler, bool>(
      (player) => player.isPlaying && player.currentTrack?.id == trackId,
    );
  }

  /// Whether [trackId] is the current track *and* the current playback
  /// context matches [viewContext] — i.e. the queue actually loaded is the
  /// one this row's own view (this playlist, this album, this artist, this
  /// search) would build, not just some other queue that happens to
  /// contain the same song.
  ///
  /// Pass the [PlaybackContext] the calling view's queue is (or would be)
  /// built with; pass `null` for a view with no stable context of its own
  /// (the row will then never report itself as current there). Matching
  /// prefers `id` when both sides have one and falls back to `name`,
  /// mirroring [watchIsPlayingAlbum] / [watchIsPlayingArtist] /
  /// [watchIsPlayingPlaylist] above — this is the same rule, just scoped to
  /// a single track row instead of a whole entity card.
  bool watchIsCurrentTrackHere({
    required String trackId,
    required PlaybackContext? viewContext,
  }) {
    if (viewContext == null) return false;
    return select<WispAudioHandler, bool>((player) {
      if (player.currentTrack?.id != trackId) return false;
      final playerContext = player.playbackContext;
      return playerContext != null && playerContext.matches(viewContext);
    });
  }

  /// [watchIsCurrentTrackHere] narrowed to also require that playback is
  /// actually active, not just loaded-and-paused. Use this to drive a
  /// play/pause icon or waveform; use [watchIsCurrentTrackHere] to drive
  /// "highlight this row as the current one" styling that should still
  /// apply while paused.
  bool watchIsPlayingTrackHere({
    required String trackId,
    required PlaybackContext? viewContext,
  }) {
    return watchIsCurrentTrackHere(
          trackId: trackId,
          viewContext: viewContext,
        ) &&
        select<WispAudioHandler, bool>((player) => player.isPlaying);
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
      if (player.playbackContext?.type != PlaybackContextType.playlist) {
        return false;
      }
      if (player.playbackContext?.id == playlistId) return true;
      final contextName = player.playbackContext?.name.trim();
      return contextName != null &&
          contextName.isNotEmpty &&
          contextName == playlistTitle.trim();
    });
  }
}
