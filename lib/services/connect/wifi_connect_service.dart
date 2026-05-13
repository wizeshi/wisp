import 'package:wisp/services/connect/connect_models.dart';
import 'package:wisp/services/connect/connect_packet_models.dart';
import 'package:wisp/services/connect/connect_transport.dart';
import 'package:wisp/services/connect/lan_connect_service.dart';

/// A simple Wi-Fi backend stub that currently delegates to the LAN backend.
/// This exists so a second backend can be registered behind the same interface.
class WifiConnectService implements ConnectTransport {
  final LanConnectService _inner = LanConnectService();

  @override
  Stream<ConnectDevice> get discoveredDeviceStream => _inner.discoveredDeviceStream;

  @override
  Stream<ConnectPairRequest> get pairRequestStream => _inner.pairRequestStream;

  @override
  Stream<ConnectPairResponse> get pairResponseStream => _inner.pairResponseStream;

  @override
  Stream<ConnectSnapshotSync> get snapshotStream => _inner.snapshotStream;

  @override
  Stream<ConnectStateDeltaSync> get stateDeltaStream => _inner.stateDeltaStream;

  @override
  Stream<ConnectPositionPulseSync> get positionPulseStream => _inner.positionPulseStream;

  @override
  Stream<ConnectCommandIntent> get commandIntentStream => _inner.commandIntentStream;

  @override
  Stream<ConnectCommandApply> get commandApplyStream => _inner.commandApplyStream;

  @override
  Stream<ConnectCommandAck> get commandAckStream => _inner.commandAckStream;

  @override
  Stream<ConnectUnlinkEvent> get unlinkStream => _inner.unlinkStream;

  @override
  Future<void> start({required String localDeviceId, required String localDeviceName, required String localPlatform}) =>
      _inner.start(localDeviceId: localDeviceId, localDeviceName: localDeviceName, localPlatform: localPlatform);

  @override
  Future<void> stop() => _inner.stop();

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  void requestPair({required ConnectDevice target, required String fromDeviceId, required String fromDeviceName, required String fromPlatform, required ConnectLinkMode mode, required HandoffSecurityLevel securityLevel}) =>
      _inner.requestPair(target: target, fromDeviceId: fromDeviceId, fromDeviceName: fromDeviceName, fromPlatform: fromPlatform, mode: mode, securityLevel: securityLevel);

  @override
  void respondPair({required String targetAddress, required bool accepted, required String localDeviceId, required String localDeviceName, required String localPlatform, required ConnectLinkMode mode, String? rejectionReason}) =>
      _inner.respondPair(targetAddress: targetAddress, accepted: accepted, localDeviceId: localDeviceId, localDeviceName: localDeviceName, localPlatform: localPlatform, mode: mode, rejectionReason: rejectionReason);

  @override
    void sendSnapshot({
        required String targetAddress,
        required String fromDeviceId,
        required ConnectPlaybackSnapshot snapshot,
        bool includeOriginalQueue = true,
        bool includeResolvedYoutubeIds = true,
    }) =>
            _inner.sendSnapshot(
                targetAddress: targetAddress,
                fromDeviceId: fromDeviceId,
                snapshot: snapshot,
                includeOriginalQueue: includeOriginalQueue,
                includeResolvedYoutubeIds: includeResolvedYoutubeIds,
            );

  @override
  void sendStateDelta({required String targetAddress, required String fromDeviceId, required ConnectStateDelta delta}) =>
      _inner.sendStateDelta(targetAddress: targetAddress, fromDeviceId: fromDeviceId, delta: delta);

  @override
  void sendPositionPulse({required String targetAddress, required String fromDeviceId, required ConnectPositionPulse pulse}) =>
      _inner.sendPositionPulse(targetAddress: targetAddress, fromDeviceId: fromDeviceId, pulse: pulse);

  @override
  void sendCommandIntent({required String targetAddress, required String fromDeviceId, required String command, Map<String, dynamic> payload = const {}}) =>
      _inner.sendCommandIntent(targetAddress: targetAddress, fromDeviceId: fromDeviceId, command: command, payload: payload);

  @override
  void sendCommandApply({required String targetAddress, required String fromDeviceId, required int sequence, required String command, Map<String, dynamic> payload = const {}}) =>
      _inner.sendCommandApply(targetAddress: targetAddress, fromDeviceId: fromDeviceId, sequence: sequence, command: command, payload: payload);

  @override
  void sendCommandAck({required String targetAddress, required String fromDeviceId, required int sequence, required bool isPlaying, required int positionMs, ConnectPlaybackSnapshot? snapshot}) =>
      _inner.sendCommandAck(targetAddress: targetAddress, fromDeviceId: fromDeviceId, sequence: sequence, isPlaying: isPlaying, positionMs: positionMs, snapshot: snapshot);

  @override
  void sendUnlink({required String targetAddress, required String fromDeviceId}) =>
      _inner.sendUnlink(targetAddress: targetAddress, fromDeviceId: fromDeviceId);
}
