import 'package:flutter/foundation.dart';

import '../../models/metadata_models.dart';

abstract class PlaybackTransport implements Listenable {
  bool get isLinked;
  bool get isHost;
  bool get isTarget;
  bool get linkedIsPlaying;
  Duration get linkedInterpolatedPosition;

  Future<void> sendPlayCommand();
  Future<void> sendPauseCommand();
  Future<void> sendSeekCommand(Duration position);
  Future<void> sendSkipNextCommand();
  Future<void> sendSkipPreviousCommand();
  Future<void> sendToggleShuffleCommand();
  Future<void> sendToggleRepeatCommand();
  Future<void> sendPlayQueueIndexCommand(int index);
  Future<void> sendRemoveFromQueueCommand(int index);
  Future<void> sendClearQueueCommand();
  Future<void> sendReorderQueueCommand(int oldIndex, int newIndex);
  Future<void> sendSetQueueCommand(
    List<GenericSong> tracks, {
    int startIndex,
    bool play,
    String? contextType,
    String? contextName,
    String? contextID,
    SongSource? contextSource,
    bool shuffleEnabled,
    List<GenericSong>? originalQueue,
  });
}
