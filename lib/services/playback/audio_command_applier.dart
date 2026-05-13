import '../../models/metadata_models.dart';
import '../connect/connect_models.dart';
import '../wisp_audio_handler.dart';
import 'package:wisp/utils/logger.dart';

class AudioCommandApplier {
  const AudioCommandApplier();

  Future<void> apply({
    required WispAudioHandler audio,
    required String command,
    required Map<String, dynamic> payload,
  }) async {
    switch (command) {
      case 'play':
        if (audio.currentTrack != null) {
          await audio.play();
        } else if (audio.queueTracks.isNotEmpty) {
          final fallbackIndex =
              (audio.currentIndex >= 0 &&
                  audio.currentIndex < audio.queueTracks.length)
              ? audio.currentIndex
              : 0;
          await audio.playTrack(
            audio.queueTracks[fallbackIndex],
            addToQueue: false,
          );
        }
        break;
      case 'pause':
        await audio.pause();
        break;
      case 'seek':
        final positionMs = (payload['position_ms'] as int?) ?? 0;
        await audio.seek(Duration(milliseconds: positionMs));
        break;
      case 'skip_next':
        await audio.skipNext();
        break;
      case 'skip_previous':
        await audio.skipPrevious();
        break;
      case 'toggle_shuffle':
        audio.toggleShuffle();
        break;
      case 'toggle_repeat':
        audio.toggleRepeat();
        break;
      case 'play_queue_index':
        final index = (payload['index'] as int?) ?? -1;
        if (index >= 0 && index < audio.queueTracks.length) {
          await audio.playTrack(audio.queueTracks[index], addToQueue: false);
        }
        break;
      case 'remove_from_queue':
        final index = (payload['index'] as int?) ?? -1;
        audio.removeFromQueue(index);
        break;
      case 'clear_queue':
        audio.clearQueue();
        break;
      case 'reorder_queue':
        final oldIndex = (payload['old_index'] as int?) ?? -1;
        final newIndex = (payload['new_index'] as int?) ?? -1;
        if (oldIndex >= 0 && newIndex >= 0) {
          audio.reorderQueue(oldIndex, newIndex);
        }
        break;
      case 'set_queue':
        final tracksJsonRaw = payload['tracks'];
        final tracksJson = (tracksJsonRaw is List)
            ? tracksJsonRaw.whereType<Map<String, dynamic>>().toList(growable: false)
            : <Map<String, dynamic>>[];

        List<GenericSong> parseSongs(List<Map<String, dynamic>> items, String label) {
          final songs = <GenericSong>[];
          for (var index = 0; index < items.length; index++) {
            final item = items[index];
            try {
              songs.add(GenericSong.fromJson(item));
            } catch (e, st) {
              logger.e(
                '[Handoff] AudioCommandApplier.set_queue: failed to parse $label[$index] keys=${item.keys.toList()}',
                error: e,
                stackTrace: st,
              );
            }
          }
          return songs;
        }

        final tracks = parseSongs(tracksJson, 'tracks');
        final originalQueueJsonRaw = payload['original_queue'];
        final originalQueueJson = (originalQueueJsonRaw is List)
            ? originalQueueJsonRaw.whereType<Map<String, dynamic>>().toList(growable: false)
            : <Map<String, dynamic>>[];
        final originalQueue = parseSongs(originalQueueJson, 'original_queue');
        try {
          await audio.setQueue(
            tracks,
            startIndex: (payload['start_index'] as int?) ?? 0,
            play: (payload['play'] as bool?) ?? true,
            contextType: payload['context_type'] as String?,
            contextName: payload['context_name'] as String?,
            contextID: payload['context_id'] as String?,
            contextSource: SongSource.fromJson(
              payload['context_source'] as String? ?? SongSource.spotify.toJson(),
            ),
            shuffleEnabled: (payload['shuffle_enabled'] as bool?) ?? false,
            originalQueue: originalQueue.isEmpty ? null : originalQueue,
          );
        } catch (e, st) {
          logger.e('[Handoff] AudioCommandApplier.set_queue: failed to apply queue', error: e, stackTrace: st);
          rethrow;
        }
        break;
      default:
        break;
    }
  }

  Future<void> applySnapshot(
    WispAudioHandler audio,
    ConnectPlaybackSnapshot snapshot, {
    bool autoPlay = true,
    bool preserveVolume = false,
  }) async {
    try {
      logger.d(
        '[Handoff] AudioCommandApplier.applySnapshot: applying snapshot from payload queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
      );
      await audio.applyConnectSnapshot(
        snapshot,
        autoPlay: autoPlay,
        preserveVolume: preserveVolume,
      );
      logger.d('[Handoff] AudioCommandApplier.applySnapshot: applied successfully');
    } catch (e, st) {
      logger.e('[Handoff] AudioCommandApplier.applySnapshot failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  ConnectPlaybackSnapshot buildSnapshot(WispAudioHandler audio) {
    return audio.buildConnectSnapshot();
  }
}