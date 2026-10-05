// Copyright © 2026 wizeshi

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/core/utils/liked_songs.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/metadata/metadata_manager.dart';
import 'package:wisp/features/library/state/local_playlists.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';

class PlaylistPlaybackHelper {
  /// Starts playback of [playlist] immediately with the initial batch of tracks,
  /// then asynchronously fetches the full playlist and appends any missing
  /// elements to the queue.
  static Future<void> startPlaylistPlayback(
    BuildContext context,
    GenericPlaylist playlist,
  ) async {
    final coordinator = context.read<PlaybackCoordinator>();
    final metadataManager = context.read<MetadataManager>();
    final localPlaylists = context.read<LocalPlaylistState>();

    try {
      // 1. Check if it's a local playlist
      if (!isLikedSongsPlaylistId(playlist.id) &&
          localPlaylists.isLocalPlaylistId(playlist.id)) {
        final localPlaylist = localPlaylists.getGenericPlaylist(playlist.id);
        final items = localPlaylist?.songs ?? [];
        if (items.isEmpty) return;
        final tracks = items
            .map(
              (item) => GenericSong(
                id: item.id,
                source: item.source,
                title: item.title,
                artists: item.artists,
                thumbnailUrl: item.thumbnailUrl,
                explicit: item.explicit,
                album: item.album,
                durationSecs: item.durationSecs,
              ),
            )
            .toList();
        if (tracks.isEmpty) return;
        if (context.mounted) {
          await coordinator.setQueue(
            tracks,
            startIndex: 0,
            play: true,
            playbackContext: PlaybackContext(
              type: PlaybackContextType.playlist,
              name: localPlaylist?.title ?? playlist.title,
              id: playlist.id,
              source: playlist.source,
            ),
          );
        }
        return;
      }

      // 2. Fetch initial batch (first page) for immediate playback
      final initialPlaylist = await metadataManager.getPlaylistInfo(
        playlist.id,
        source: playlist.source,
      );
      final items = initialPlaylist.songs ?? [];
      if (items.isEmpty) return;
      final initialTracks = items
          .map(
            (item) => GenericSong(
              id: item.id,
              source: item.source,
              title: item.title,
              artists: item.artists,
              thumbnailUrl: item.thumbnailUrl,
              explicit: item.explicit,
              album: item.album,
              durationSecs: item.durationSecs,
            ),
          )
          .toList();
      if (initialTracks.isEmpty) return;

      final contextId = initialPlaylist.id;
      if (context.mounted) {
        await coordinator.setQueue(
          initialTracks,
          startIndex: 0,
          play: true,
          playbackContext: PlaybackContext(
            type: PlaybackContextType.playlist,
            name: initialPlaylist.title,
            id: contextId,
            source: initialPlaylist.source,
          ),
        );
      }

      // 3. After beginning playback, request the full playlist in background
      // and append any missing elements to the queue.
      unawaited(() async {
        try {
          final fullPlaylist =
              await metadataManager.fetchFullPlaylistWithTracks(
            playlist.id,
            source: playlist.source,
          );
          final allItems = fullPlaylist.songs ?? [];
          if (allItems.length <= initialTracks.length) return;

          // Verify playback context has not changed
          final audio = coordinator.audioHandler;
          if (audio == null ||
              audio.playbackContext?.type != PlaybackContextType.playlist ||
              audio.playbackContext?.id != contextId) {
            return;
          }

          final missingItems = allItems.sublist(initialTracks.length);
          final missingTracks = missingItems
              .map(
                (item) => GenericSong(
                  id: item.id,
                  source: item.source,
                  title: item.title,
                  artists: item.artists,
                  thumbnailUrl: item.thumbnailUrl,
                  explicit: item.explicit,
                  album: item.album,
                  durationSecs: item.durationSecs,
                ),
              )
              .toList();

          if (missingTracks.isNotEmpty) {
            await coordinator.addTracksToQueue(missingTracks);
          }
        } catch (e) {
          logger.w('[PlaylistPlaybackHelper] Failed to append missing playlist tracks: $e');
        }
      }());
    } catch (e) {
      logger.w('[PlaylistPlaybackHelper] Failed to start playlist playback: $e');
    }
  }

  /// Toggles playlist playback if currently active; otherwise starts playback.
  static Future<void> togglePlaylistPlayback(
    BuildContext context,
    GenericPlaylist playlist,
  ) async {
    final audioHandler = context.read<PlaybackCoordinator>().audioHandler;
    if (audioHandler != null &&
        audioHandler.playbackContext?.type == PlaybackContextType.playlist &&
        audioHandler.playbackContext?.id == playlist.id) {
      if (audioHandler.isPlaying) {
        return audioHandler.pause();
      } else {
        return audioHandler.play();
      }
    } else {
      return startPlaylistPlayback(context, playlist);
    }
  }

  /// Ensures the playlist is playing: resumes if currently paused, or starts playback fresh.
  static Future<void> playPlaylist(
    BuildContext context,
    GenericPlaylist playlist,
  ) async {
    final audioHandler = context.read<PlaybackCoordinator>().audioHandler;
    if (audioHandler != null &&
        audioHandler.playbackContext?.type == PlaybackContextType.playlist &&
        audioHandler.playbackContext?.id == playlist.id) {
      if (!audioHandler.isPlaying) {
        return audioHandler.play();
      }
      return startPlaylistPlayback(context, playlist);
    }
    return startPlaylistPlayback(context, playlist);
  }
}
