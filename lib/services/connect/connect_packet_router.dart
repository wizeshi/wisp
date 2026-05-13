import 'dart:convert';

import 'connect_models.dart';
import 'connect_packet_models.dart';
import '../playback/audio_packet_router.dart';
import 'package:wisp/utils/logger.dart';

class ConnectPacketEnvelope {
  static const String protocol = 'wisp.connect/1';

  final String packetType;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> metadata;

  const ConnectPacketEnvelope({
    required this.packetType,
    this.payload = const <String, dynamic>{},
    this.metadata = const <String, dynamic>{},
  });

  factory ConnectPacketEnvelope.fromJson(Map<String, dynamic> json) {
    if (json['protocol'] == protocol &&
        json['packet'] is String &&
        json['payload'] is Map<String, dynamic>) {
      return ConnectPacketEnvelope(
        packetType: json['packet'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        metadata: Map<String, dynamic>.from(
          (json['meta'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
        ),
      );
    }
    throw const FormatException('Invalid connect packet envelope');
  }

  Map<String, dynamic> toJson() {
    return {
      'protocol': protocol,
      'packet': packetType,
      'payload': payload,
      if (metadata.isNotEmpty) 'meta': metadata,
    };
  }

  String encode() => json.encode(toJson());
}

class ConnectPacketRouter {
  const ConnectPacketRouter();
  static const AudioPacketRouter _audioPacketRouter = AudioPacketRouter();

  void route({
    required ConnectPacketEnvelope packet,
    required String localDeviceId,
    required String sourceAddress,
    required void Function(ConnectPairRequest request) onPairRequest,
    required void Function(ConnectPairResponse response) onPairResponse,
    required void Function(ConnectSnapshotSync sync) onSnapshotSync,
    required void Function(ConnectCommandIntent intent) onCommandIntent,
    required void Function(ConnectCommandApply apply) onCommandApply,
    required void Function(ConnectCommandAck ack) onCommandAck,
    required void Function(ConnectUnlinkEvent event) onUnlink,
    required void Function(ConnectStateDeltaSync deltasync) onStateDelta,
    required void Function(ConnectPositionPulseSync pulsesync) onPositionPulse,
  }) {
    final fromDeviceId = _string(packet.payload['from_device_id']);
    if (fromDeviceId.isEmpty || fromDeviceId == localDeviceId) {
      logger.e(
        '[Connect/Router] DROPPED ${packet.packetType}: self-packet or empty fromDevice',
      );
      return;
    }

    final packetType = packet.packetType;
    final packetNamespace = _packetNamespace(packetType);
    final packetName = _packetName(packetType);

    switch (packetNamespace) {
      case 'handoff':
        _routeHandoffPacket(
          packetName: packetName,
          fromDeviceId: fromDeviceId,
          sourceAddress: sourceAddress,
          payload: packet.payload,
          onPairRequest: onPairRequest,
          onPairResponse: onPairResponse,
          onUnlink: onUnlink,
        );
        return;
      case 'audio':
      case 'playback':
        _audioPacketRouter.route(
          packetName: packetName,
          fromDeviceId: fromDeviceId,
          sourceAddress: sourceAddress,
          payload: packet.payload,
          onSnapshotSync: onSnapshotSync,
          onCommandIntent: onCommandIntent,
          onCommandApply: onCommandApply,
          onCommandAck: onCommandAck,
          onUnlink: onUnlink,
          onStateDelta: onStateDelta,
          onPositionPulse: onPositionPulse,
        );
        return;
    }
  }

  void _routeHandoffPacket({
    required String packetName,
    required String fromDeviceId,
    required String sourceAddress,
    required Map<String, dynamic> payload,
    required void Function(ConnectPairRequest request) onPairRequest,
    required void Function(ConnectPairResponse response) onPairResponse,
    required void Function(ConnectUnlinkEvent event) onUnlink,
  }) {
    switch (packetName) {
      case 'pair_request':
        onPairRequest(
          ConnectPairRequest(
            fromDeviceId: fromDeviceId,
            fromDeviceName: _string(
              payload['from_device_name'],
              fallback: 'Unknown device',
            ),
            fromPlatform: _string(payload['from_platform'], fallback: 'unknown'),
            fromAddress: sourceAddress,
            controlPort: _int(payload['control_port'], fallback: 47111),
            requestedMode: ConnectLinkModeJson.fromJson(
              _string(payload['requested_mode']),
            ),
            securityLevel: HandoffSecurityLevelJson.fromJson(
              _string(payload['security_level']),
            ),
          ),
        );
        return;
      case 'pair_accept':
      case 'pair_reject':
        onPairResponse(
          ConnectPairResponse(
            accepted: packetName == 'pair_accept',
            fromDeviceId: fromDeviceId,
            fromDeviceName: _string(
              payload['from_device_name'],
              fallback: 'Unknown device',
            ),
            fromPlatform: _string(payload['from_platform'], fallback: 'unknown'),
            fromAddress: sourceAddress,
            controlPort: _int(payload['control_port'], fallback: 47111),
            linkMode: ConnectLinkModeJson.fromJson(
              _string(payload['link_mode']),
            ),
            rejectionReason: payload['rejection_reason'] as String?,
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

  String _packetNamespace(String packetType) {
    final dotIndex = packetType.indexOf('.');
    if (dotIndex <= 0) {
      if (packetType == 'pair_request' ||
          packetType == 'pair_accept' ||
          packetType == 'pair_reject') {
        return 'handoff';
      }
      return 'playback';
    }
    return packetType.substring(0, dotIndex);
  }

  String _packetName(String packetType) {
    final dotIndex = packetType.indexOf('.');
    if (dotIndex < 0) return packetType;
    return packetType.substring(dotIndex + 1);
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
}