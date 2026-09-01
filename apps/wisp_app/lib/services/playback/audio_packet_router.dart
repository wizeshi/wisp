import '../connect/connect_packet_models.dart';
import '../connect/connect_models.dart';

class AudioPacketRouter {
  const AudioPacketRouter();

  void route({
    required String packetName,
    required String fromDeviceId,
    required String sourceAddress,
    required Map<String, dynamic> payload,
    required void Function(ConnectSnapshotSync sync) onSnapshotSync,
    required void Function(ConnectCommandIntent intent) onCommandIntent,
    required void Function(ConnectCommandApply apply) onCommandApply,
    required void Function(ConnectCommandAck ack) onCommandAck,
    required void Function(ConnectUnlinkEvent event) onUnlink,
    required void Function(ConnectStateDeltaSync deltasync) onStateDelta,
    required void Function(ConnectPositionPulseSync pulsesync) onPositionPulse,
  }) {
    switch (packetName) {
      case 'snapshot_sync':
        final snapshotJson = payload['snapshot'];
        if (snapshotJson is Map<String, dynamic>) {
          onSnapshotSync(
            ConnectSnapshotSync(
              fromDeviceId: fromDeviceId,
              fromAddress: sourceAddress,
              snapshot: ConnectPlaybackSnapshot.fromJson(snapshotJson),
            ),
          );
        }
        return;
      case 'state_delta':
        final deltaJson = payload['delta'];
        if (deltaJson is Map<String, dynamic>) {
          onStateDelta(
            ConnectStateDeltaSync(
              fromDeviceId: fromDeviceId,
              fromAddress: sourceAddress,
              delta: ConnectStateDelta.fromJson(deltaJson),
            ),
          );
        }
        return;
      case 'position_pulse':
        final pulseJson = payload['pulse'];
        if (pulseJson is Map<String, dynamic>) {
          onPositionPulse(
            ConnectPositionPulseSync(
              fromDeviceId: fromDeviceId,
              fromAddress: sourceAddress,
              pulse: ConnectPositionPulse.fromJson(pulseJson),
            ),
          );
        }
        return;
      case 'command_intent':
        onCommandIntent(
          ConnectCommandIntent(
            fromDeviceId: fromDeviceId,
            fromAddress: sourceAddress,
            command: _string(payload['command']),
            payload: _map(payload['payload']),
          ),
        );
        return;
      case 'command_apply':
        onCommandApply(
          ConnectCommandApply(
            fromDeviceId: fromDeviceId,
            fromAddress: sourceAddress,
            sequence: _int(payload['sequence']),
            command: _string(payload['command']),
            payload: _map(payload['payload']),
          ),
        );
        return;
      case 'command_ack':
        final snapshotJson = payload['snapshot'];
        ConnectPlaybackSnapshot? snapshot;
        if (snapshotJson is Map<String, dynamic>) {
          snapshot = ConnectPlaybackSnapshot.fromJson(snapshotJson);
        }
        onCommandAck(
          ConnectCommandAck(
            fromDeviceId: fromDeviceId,
            fromAddress: sourceAddress,
            sequence: _int(payload['sequence']),
            isPlaying: _bool(payload['is_playing']),
            positionMs: _int(payload['position_ms']),
            snapshot: snapshot,
          ),
        );
        return;
      case 'unlink':
        onUnlink(
          ConnectUnlinkEvent(
            fromDeviceId: fromDeviceId,
            fromAddress: sourceAddress,
          ),
        );
        return;
    }
  }

  String _string(Object? value, {String fallback = ''}) {
    final next = value?.toString().trim() ?? '';
    return next.isEmpty ? fallback : next;
  }

  int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return fallback;
  }

  bool _bool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    return fallback;
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }
}