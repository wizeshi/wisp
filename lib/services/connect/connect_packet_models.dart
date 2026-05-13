import 'connect_models.dart';

class ConnectPairRequest {
  final String fromDeviceId;
  final String fromDeviceName;
  final String fromPlatform;
  final String fromAddress;
  final int controlPort;
  final ConnectLinkMode requestedMode;
  final HandoffSecurityLevel securityLevel;

  const ConnectPairRequest({
    required this.fromDeviceId,
    required this.fromDeviceName,
    required this.fromPlatform,
    required this.fromAddress,
    required this.controlPort,
    required this.requestedMode,
    required this.securityLevel,
  });
}

class ConnectPairResponse {
  final bool accepted;
  final String fromDeviceId;
  final String fromDeviceName;
  final String fromPlatform;
  final String fromAddress;
  final int controlPort;
  final ConnectLinkMode linkMode;
  final String? rejectionReason;

  const ConnectPairResponse({
    required this.accepted,
    required this.fromDeviceId,
    required this.fromDeviceName,
    required this.fromPlatform,
    required this.fromAddress,
    required this.controlPort,
    required this.linkMode,
    this.rejectionReason,
  });
}

class ConnectSnapshotSync {
  final String fromDeviceId;
  final String fromAddress;
  final ConnectPlaybackSnapshot snapshot;

  const ConnectSnapshotSync({
    required this.fromDeviceId,
    required this.fromAddress,
    required this.snapshot,
  });
}

class ConnectCommandIntent {
  final String fromDeviceId;
  final String fromAddress;
  final String command;
  final Map<String, dynamic> payload;

  const ConnectCommandIntent({
    required this.fromDeviceId,
    required this.fromAddress,
    required this.command,
    required this.payload,
  });
}

class ConnectCommandApply {
  final String fromDeviceId;
  final String fromAddress;
  final int sequence;
  final String command;
  final Map<String, dynamic> payload;

  const ConnectCommandApply({
    required this.fromDeviceId,
    required this.fromAddress,
    required this.sequence,
    required this.command,
    required this.payload,
  });
}

class ConnectCommandAck {
  final String fromDeviceId;
  final String fromAddress;
  final int sequence;
  final bool isPlaying;
  final int positionMs;
  final ConnectPlaybackSnapshot? snapshot;

  const ConnectCommandAck({
    required this.fromDeviceId,
    required this.fromAddress,
    required this.sequence,
    required this.isPlaying,
    required this.positionMs,
    this.snapshot,
  });
}

class ConnectUnlinkEvent {
  final String fromDeviceId;
  final String fromAddress;

  const ConnectUnlinkEvent({
    required this.fromDeviceId,
    required this.fromAddress,
  });
}

class ConnectStateDeltaSync {
  final String fromDeviceId;
  final String fromAddress;
  final ConnectStateDelta delta;

  const ConnectStateDeltaSync({
    required this.fromDeviceId,
    required this.fromAddress,
    required this.delta,
  });
}

class ConnectPositionPulseSync {
  final String fromDeviceId;
  final String fromAddress;
  final ConnectPositionPulse pulse;

  const ConnectPositionPulseSync({
    required this.fromDeviceId,
    required this.fromAddress,
    required this.pulse,
  });
}