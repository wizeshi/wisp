import 'dart:async';

import 'package:wisp/services/connect/connect_models.dart';
import 'package:wisp/services/connect/connect_packet_models.dart';

abstract class ConnectTransport {
  Stream<ConnectDevice> get discoveredDeviceStream;
  Stream<ConnectPairRequest> get pairRequestStream;
  Stream<ConnectPairResponse> get pairResponseStream;
  Stream<ConnectSnapshotSync> get snapshotStream;
  Stream<ConnectStateDeltaSync> get stateDeltaStream;
  Stream<ConnectPositionPulseSync> get positionPulseStream;
  Stream<ConnectCommandIntent> get commandIntentStream;
  Stream<ConnectCommandApply> get commandApplyStream;
  Stream<ConnectCommandAck> get commandAckStream;
  Stream<ConnectUnlinkEvent> get unlinkStream;
  

  Future<void> start({
    required String localDeviceId,
    required String localDeviceName,
    required String localPlatform,
  });

  Future<void> stop();

  Future<void> dispose();

  void requestPair({
    required ConnectDevice target,
    required String fromDeviceId,
    required String fromDeviceName,
    required String fromPlatform,
    required ConnectLinkMode mode,
    required HandoffSecurityLevel securityLevel,
  });

  void respondPair({
    required String targetAddress,
    required bool accepted,
    required String localDeviceId,
    required String localDeviceName,
    required String localPlatform,
    required ConnectLinkMode mode,
    String? rejectionReason,
  });

  void sendSnapshot({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectPlaybackSnapshot snapshot,
    bool includeOriginalQueue = true,
    bool includeResolvedYoutubeIds = true,
  });

  void sendStateDelta({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectStateDelta delta,
  });

  void sendPositionPulse({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectPositionPulse pulse,
  });

  void sendCommandIntent({
    required String targetAddress,
    required String fromDeviceId,
    required String command,
    Map<String, dynamic> payload = const {},
  });

  void sendCommandApply({
    required String targetAddress,
    required String fromDeviceId,
    required int sequence,
    required String command,
    Map<String, dynamic> payload = const {},
  });

  void sendCommandAck({
    required String targetAddress,
    required String fromDeviceId,
    required int sequence,
    required bool isPlaying,
    required int positionMs,
    ConnectPlaybackSnapshot? snapshot,
  });

  void sendUnlink({
    required String targetAddress,
    required String fromDeviceId,
  });
  
}
