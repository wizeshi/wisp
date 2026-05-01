import 'package:flutter/foundation.dart';

import '../../models/metadata_models.dart';
import '../wisp_audio_handler.dart';
import 'playback_transport.dart';

class PlaybackCoordinator extends ChangeNotifier {
  WispAudioHandler? _audioHandler;
  PlaybackTransport? _transport;

  void _notifyFromSource() {
    notifyListeners();
  }

  WispAudioHandler? get audioHandler => _audioHandler;
  PlaybackTransport? get transport => _transport;

  bool get isLinked => _transport?.isLinked ?? false;
  bool get isHost => _transport?.isHost ?? false;
  bool get isTarget => _transport?.isTarget ?? false;
  bool get useLinkedPlaybackState => isLinked && isHost;

  bool get effectiveIsPlaying {
    if (useLinkedPlaybackState) {
      return _transport?.linkedIsPlaying ?? false;
    }
    return _audioHandler?.isPlaying ?? false;
  }

  Duration get effectiveInterpolatedPosition {
    if (useLinkedPlaybackState) {
      return _transport?.linkedInterpolatedPosition ?? Duration.zero;
    }
    return _audioHandler?.interpolatedPosition ?? Duration.zero;
  }

  Duration get effectiveThrottledPosition {
    if (useLinkedPlaybackState) {
      return _transport?.linkedInterpolatedPosition ?? Duration.zero;
    }
    return _audioHandler?.throttledPosition ?? Duration.zero;
  }

  void bindAudioHandler(WispAudioHandler audioHandler) {
    if (identical(_audioHandler, audioHandler)) return;
    _audioHandler?.removeListener(_notifyFromSource);
    _audioHandler = audioHandler;
    _audioHandler?.addListener(_notifyFromSource);
    notifyListeners();
  }

  void bindTransport(PlaybackTransport transport) {
    if (identical(_transport, transport)) return;
    _transport?.removeListener(_notifyFromSource);
    _transport = transport;
    _transport?.addListener(_notifyFromSource);
    notifyListeners();
  }

  @override
  void dispose() {
    _audioHandler?.removeListener(_notifyFromSource);
    _transport?.removeListener(_notifyFromSource);
    super.dispose();
  }

  Future<void> play() async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendPlayCommand();
      return;
    }

    if (audio.currentTrack != null) {
      await audio.play();
    } else if (audio.queueTracks.isNotEmpty) {
      await audio.playTrack(audio.queueTracks.first);
    }
  }

  Future<void> pause() async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendPauseCommand();
      return;
    }

    await audio.pause();
  }

  Future<void> seek(Duration position) async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendSeekCommand(position);
      return;
    }

    await audio.seek(position);
  }

  Future<void> skipNext() async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendSkipNextCommand();
      return;
    }

    await audio.skipNext();
  }

  Future<void> skipPrevious() async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendSkipPreviousCommand();
      return;
    }

    await audio.skipPrevious();
  }

  Future<void> toggleShuffle() async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendToggleShuffleCommand();
      return;
    }

    audio.toggleShuffle();
  }

  Future<void> toggleRepeat() async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendToggleRepeatCommand();
      return;
    }

    audio.toggleRepeat();
  }

  Future<void> playQueueIndex(int index) async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendPlayQueueIndexCommand(index);
      return;
    }

    if (index < 0 || index >= audio.queueTracks.length) return;
    await audio.playTrack(audio.queueTracks[index], addToQueue: false);
  }

  Future<void> removeFromQueue(int index) async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendRemoveFromQueueCommand(index);
      return;
    }

    audio.removeFromQueue(index);
  }

  Future<void> clearQueue() async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendClearQueueCommand();
      return;
    }

    audio.clearQueue();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendReorderQueueCommand(oldIndex, newIndex);
      return;
    }

    audio.reorderQueue(oldIndex, newIndex);
  }

  Future<void> setQueue(
    List<GenericSong> tracks, {
    int startIndex = 0,
    bool play = true,
    String? contextType,
    String? contextName,
    String? contextID,
    SongSource? contextSource,
    bool shuffleEnabled = false,
    List<GenericSong>? originalQueue,
  }) async {
    final audio = _audioHandler;
    if (audio == null) return;

    final transport = _transport;
    if (transport?.isLinked ?? false) {
      await transport!.sendSetQueueCommand(
        tracks,
        startIndex: startIndex,
        play: play,
        contextType: contextType,
        contextName: contextName,
        contextID: contextID,
        contextSource: contextSource,
        shuffleEnabled: shuffleEnabled,
        originalQueue: originalQueue,
      );
      return;
    }

    await audio.setQueue(
      tracks,
      startIndex: startIndex,
      play: play,
      contextType: contextType,
      contextName: contextName,
      contextID: contextID,
      contextSource: contextSource,
      shuffleEnabled: shuffleEnabled,
      originalQueue: originalQueue,
    );
  }
}
