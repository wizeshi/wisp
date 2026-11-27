// Copyright © 2026 wizeshi

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/playback/services/playback_coordinator.dart';
import 'package:wisp/features/playback/services/playback_transport.dart';
import 'package:wisp/services/audio/wisp_audio_handler.dart';

class _FakePlaybackTransport extends ChangeNotifier
    implements PlaybackTransport {
  final ValueNotifier<Duration> linkedPos = ValueNotifier<Duration>(
    Duration.zero,
  );
  bool linked = true;
  bool host = true;
  bool playing = false;

  @override
  bool get isLinked => linked;

  @override
  bool get isHost => host;

  @override
  bool get isTarget => false;

  @override
  bool get linkedIsPlaying => playing;

  @override
  Duration get linkedInterpolatedPosition => linkedPos.value;

  @override
  ValueListenable<Duration> get linkedPositionListenable => linkedPos;

  void emitStateChange() => notifyListeners();

  @override
  Future<void> sendClearQueueCommand() async {}

  @override
  Future<void> sendPauseCommand() async {}

  @override
  Future<void> sendPlayCommand() async {}

  @override
  Future<void> sendPlayQueueIndexCommand(int index) async {}

  @override
  Future<void> sendRemoveFromQueueCommand(int index) async {}

  @override
  Future<void> sendReorderQueueCommand(int oldIndex, int newIndex) async {}

  @override
  Future<void> sendSeekCommand(Duration position) async {}

  @override
  Future<void> sendSetQueueCommand(
    List<GenericSong> tracks, {
    int startIndex = 0,
    bool play = true,
    PlaybackContext? playbackContext,
    bool shuffleEnabled = false,
    List<GenericSong>? originalQueue,
  }) async {}

  @override
  Future<void> sendSkipNextCommand() async {}

  @override
  Future<void> sendSkipPreviousCommand() async {}

  @override
  Future<void> sendToggleRepeatCommand() async {}

  @override
  Future<void> sendToggleShuffleCommand() async {}

  @override
  void dispose() {
    linkedPos.dispose();
    super.dispose();
  }
}

void main() {
  group('PlaybackCoordinator position decoupling', () {
    test(
      'position ticks update effectivePositionListenable without notifyListeners',
      () {
        final coordinator = PlaybackCoordinator();
        final transport = _FakePlaybackTransport();

        var coordinatorNotifications = 0;
        var positionNotifications = 0;
        coordinator.addListener(() => coordinatorNotifications++);
        coordinator.effectivePositionListenable.addListener(
          () => positionNotifications++,
        );

        coordinator.bindTransport(transport);
        expect(coordinatorNotifications, equals(1));

        // Routine linked position updates must NOT notify PlaybackCoordinator.
        transport.linkedPos.value = const Duration(seconds: 5);
        expect(
          coordinator.effectivePositionListenable.value,
          equals(const Duration(seconds: 5)),
        );
        expect(positionNotifications, equals(1));
        expect(coordinatorNotifications, equals(1));

        transport.linkedPos.value = const Duration(seconds: 12);
        expect(
          coordinator.effectivePositionListenable.value,
          equals(const Duration(seconds: 12)),
        );
        expect(positionNotifications, equals(2));
        expect(coordinatorNotifications, equals(1));

        // Play/pause/track state changes still notify PlaybackCoordinator and sync position.
        transport.playing = true;
        transport.linkedPos.value = const Duration(seconds: 20);
        transport.emitStateChange();
        expect(coordinatorNotifications, equals(2));
        expect(
          coordinator.effectivePositionListenable.value,
          equals(const Duration(seconds: 20)),
        );

        coordinator.dispose();
        transport.dispose();
      },
    );
  });
}
