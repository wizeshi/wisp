import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wisp/services/connect/connect_models.dart';
import 'package:wisp/utils/logger.dart';

class ConnectPairRequest {
  final String fromDeviceId;
  final String fromDeviceName;
  final String fromPlatform;
  final String fromAddress;
  final int controlPort;
  final ConnectLinkMode requestedMode;

  const ConnectPairRequest({
    required this.fromDeviceId,
    required this.fromDeviceName,
    required this.fromPlatform,
    required this.fromAddress,
    required this.controlPort,
    required this.requestedMode,
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

  const ConnectPairResponse({
    required this.accepted,
    required this.fromDeviceId,
    required this.fromDeviceName,
    required this.fromPlatform,
    required this.fromAddress,
    required this.controlPort,
    required this.linkMode,
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

class ConnectPlaybackPulse {
  final String fromDeviceId;
  final String fromAddress;
  final bool isPlaying;
  final int positionMs;

  const ConnectPlaybackPulse({
    required this.fromDeviceId,
    required this.fromAddress,
    required this.isPlaying,
    required this.positionMs,
  });
}

class LanConnectService {
  static const int _discoveryPort = 47110;
  static const int _controlPort = 47111;

  final StreamController<ConnectDevice> _discoveredDeviceController =
      StreamController.broadcast();
  final StreamController<ConnectPairRequest> _pairRequestController =
      StreamController.broadcast();
  final StreamController<ConnectPairResponse> _pairResponseController =
      StreamController.broadcast();
  final StreamController<ConnectSnapshotSync> _snapshotController =
      StreamController.broadcast();
  final StreamController<ConnectCommandIntent> _commandIntentController =
      StreamController.broadcast();
  final StreamController<ConnectCommandApply> _commandApplyController =
      StreamController.broadcast();
  final StreamController<ConnectCommandAck> _commandAckController =
      StreamController.broadcast();
  final StreamController<ConnectUnlinkEvent> _unlinkController =
      StreamController.broadcast();
  final StreamController<ConnectPlaybackPulse> _playbackPulseController =
      StreamController.broadcast();

  Stream<ConnectDevice> get discoveredDeviceStream =>
      _discoveredDeviceController.stream;
  Stream<ConnectPairRequest> get pairRequestStream =>
      _pairRequestController.stream;
  Stream<ConnectPairResponse> get pairResponseStream =>
      _pairResponseController.stream;
  Stream<ConnectSnapshotSync> get snapshotStream => _snapshotController.stream;
  Stream<ConnectCommandIntent> get commandIntentStream =>
      _commandIntentController.stream;
  Stream<ConnectCommandApply> get commandApplyStream =>
      _commandApplyController.stream;
  Stream<ConnectCommandAck> get commandAckStream =>
      _commandAckController.stream;
  Stream<ConnectUnlinkEvent> get unlinkStream => _unlinkController.stream;
  Stream<ConnectPlaybackPulse> get playbackPulseStream =>
      _playbackPulseController.stream;

  RawDatagramSocket? _discoverySocket;
  RawDatagramSocket? _controlSocket;
  Timer? _announceTimer;

  bool _started = false;
  String? _localDeviceId;
  String? _localDeviceName;
  String? _localPlatform;

  Future<void> start({
    required String localDeviceId,
    required String localDeviceName,
    required String localPlatform,
  }) async {
    if (_started) return;

    _localDeviceId = localDeviceId;
    _localDeviceName = localDeviceName;
    _localPlatform = localPlatform;

    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: false,
      );
      _discoverySocket!
        ..broadcastEnabled = true
        ..listen(_onDiscoverySocketEvent);

      _controlSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _controlPort,
        reuseAddress: true,
        reusePort: false,
      );
      _controlSocket!
        ..broadcastEnabled = true
        ..listen(_onControlSocketEvent);

      _announceTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _broadcastDiscovery(),
      );
      _broadcastDiscovery();
      _started = true;
      logger.i('[Connect/LAN] Discovery started on UDP $_discoveryPort');
    } catch (error) {
      logger.e('[Connect/LAN] Failed to start', error: error);
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;

    _discoverySocket?.close();
    _discoverySocket = null;

    _controlSocket?.close();
    _controlSocket = null;

    _started = false;
  }

  Future<void> dispose() async {
    await stop();
    await _discoveredDeviceController.close();
    await _pairRequestController.close();
    await _pairResponseController.close();
    await _snapshotController.close();
    await _commandIntentController.close();
    await _commandApplyController.close();
    await _commandAckController.close();
    await _unlinkController.close();
    await _playbackPulseController.close();
  }

  void requestPair({
    required ConnectDevice target,
    required String fromDeviceId,
    required String fromDeviceName,
    required String fromPlatform,
    required ConnectLinkMode mode,
  }) {
    final address = target.address;
    if (address == null || address.isEmpty) return;

    final payload = {
      'type': 'pair_request',
      'from_device_id': fromDeviceId,
      'from_device_name': fromDeviceName,
      'from_platform': fromPlatform,
      'control_port': _controlPort,
      'requested_mode': mode.toJson(),
      'ts': DateTime.now().toIso8601String(),
    };

    _sendControlDatagram(address, payload);
    logger.d('[Handoff/LAN] -> pair_request to=$address from=$fromDeviceId');
  }

  void respondPair({
    required String targetAddress,
    required bool accepted,
    required String localDeviceId,
    required String localDeviceName,
    required String localPlatform,
    required ConnectLinkMode mode,
  }) {
    final payload = {
      'type': accepted ? 'pair_accept' : 'pair_reject',
      'from_device_id': localDeviceId,
      'from_device_name': localDeviceName,
      'from_platform': localPlatform,
      'control_port': _controlPort,
      'link_mode': mode.toJson(),
      'ts': DateTime.now().toIso8601String(),
    };
    _sendControlDatagram(targetAddress, payload);
    logger.d(
      '[Handoff/LAN] -> ${accepted ? 'pair_accept' : 'pair_reject'} to=$targetAddress from=$localDeviceId',
    );
  }

  void sendSnapshot({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectPlaybackSnapshot snapshot,
  }) {
    final payload = {
      'type': 'snapshot_sync',
      'from_device_id': fromDeviceId,
      'snapshot': snapshot.toJson(),
      'ts': DateTime.now().toIso8601String(),
    };
    _sendControlDatagram(targetAddress, payload);
    logger.d(
      '[Handoff/LAN] -> snapshot_sync to=$targetAddress from=$fromDeviceId queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
    );
  }

  void sendCommandIntent({
    required String targetAddress,
    required String fromDeviceId,
    required String command,
    Map<String, dynamic> payload = const {},
  }) {
    final body = {
      'type': 'command_intent',
      'from_device_id': fromDeviceId,
      'command': command,
      'payload': payload,
      'ts': DateTime.now().toIso8601String(),
    };
    _sendControlDatagram(targetAddress, body);
    logger.d(
      '[Handoff/LAN] -> command_intent to=$targetAddress from=$fromDeviceId cmd=$command payload=$payload',
    );
  }

  void sendCommandApply({
    required String targetAddress,
    required String fromDeviceId,
    required int sequence,
    required String command,
    Map<String, dynamic> payload = const {},
  }) {
    final body = {
      'type': 'command_apply',
      'from_device_id': fromDeviceId,
      'sequence': sequence,
      'command': command,
      'payload': payload,
      'ts': DateTime.now().toIso8601String(),
    };
    _sendControlDatagram(targetAddress, body);
    logger.d(
      '[Handoff/LAN] -> command_apply to=$targetAddress from=$fromDeviceId seq=$sequence cmd=$command payload=$payload',
    );
  }

  void sendCommandAck({
    required String targetAddress,
    required String fromDeviceId,
    required int sequence,
    required bool isPlaying,
    required int positionMs,
    ConnectPlaybackSnapshot? snapshot,
  }) {
    final body = {
      'type': 'command_ack',
      'from_device_id': fromDeviceId,
      'sequence': sequence,
      'is_playing': isPlaying,
      'position_ms': positionMs,
      'snapshot': snapshot?.toJson(),
      'ts': DateTime.now().toIso8601String(),
    };
    _sendControlDatagram(targetAddress, body);
    logger.d(
      '[Handoff/LAN] -> command_ack to=$targetAddress from=$fromDeviceId seq=$sequence playing=$isPlaying posMs=$positionMs',
    );
  }

  void sendUnlink({
    required String targetAddress,
    required String fromDeviceId,
  }) {
    final body = {
      'type': 'unlink',
      'from_device_id': fromDeviceId,
      'ts': DateTime.now().toIso8601String(),
    };
    _sendControlDatagram(targetAddress, body);
    logger.d('[Handoff/LAN] -> unlink to=$targetAddress from=$fromDeviceId');
  }

  void sendPlaybackPulse({
    required String targetAddress,
    required String fromDeviceId,
    required bool isPlaying,
    required int positionMs,
  }) {
    final body = {
      'type': 'playback_pulse',
      'from_device_id': fromDeviceId,
      'is_playing': isPlaying,
      'position_ms': positionMs,
      'ts': DateTime.now().toIso8601String(),
    };
    _sendControlDatagram(targetAddress, body);
    logger.d(
      '[Handoff/LAN] -> playback_pulse to=$targetAddress from=$fromDeviceId playing=$isPlaying posMs=$positionMs',
    );
  }

  void _onDiscoverySocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _discoverySocket?.receive();
    if (datagram == null) return;

    try {
      final message = utf8.decode(datagram.data);
      final jsonMap = json.decode(message) as Map<String, dynamic>;
      if (jsonMap['type'] != 'hello') return;

      final deviceId = (jsonMap['device_id'] as String?) ?? '';
      if (deviceId.isEmpty) return;
      if (_localDeviceId != null && deviceId == _localDeviceId) return;

      final device = ConnectDevice(
        id: deviceId,
        name: (jsonMap['name'] as String?) ?? 'Unknown device',
        platform: (jsonMap['platform'] as String?) ?? 'unknown',
        address: datagram.address.address,
        lastSeenAt: DateTime.now(),
      );

      _discoveredDeviceController.add(device);
      logger.d(
        '[Handoff/LAN] <- hello from=${device.id} name=${device.name} platform=${device.platform} address=${device.address}',
      );
    } catch (_) {}
  }

  void _onControlSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _controlSocket?.receive();
    if (datagram == null) return;

    try {
      final message = utf8.decode(datagram.data);
      final jsonMap = json.decode(message) as Map<String, dynamic>;
      final type = jsonMap['type'] as String?;
      if (type == null) return;

      final fromDeviceId = (jsonMap['from_device_id'] as String?) ?? '';
      if (fromDeviceId.isEmpty) return;
      if (_localDeviceId != null && fromDeviceId == _localDeviceId) return;

      if (type == 'pair_request') {
        final request = ConnectPairRequest(
          fromDeviceId: fromDeviceId,
          fromDeviceName:
              (jsonMap['from_device_name'] as String?) ?? 'Unknown device',
          fromPlatform: (jsonMap['from_platform'] as String?) ?? 'unknown',
          fromAddress: datagram.address.address,
          controlPort: (jsonMap['control_port'] as int?) ?? _controlPort,
          requestedMode: ConnectLinkModeJson.fromJson(
            jsonMap['requested_mode'] as String?,
          ),
        );
        _pairRequestController.add(request);
        logger.d(
          '[Handoff/LAN] <- pair_request from=${request.fromDeviceId} name=${request.fromDeviceName} address=${request.fromAddress}',
        );
        return;
      }

      if (type == 'pair_accept' || type == 'pair_reject') {
        final response = ConnectPairResponse(
          accepted: type == 'pair_accept',
          fromDeviceId: fromDeviceId,
          fromDeviceName:
              (jsonMap['from_device_name'] as String?) ?? 'Unknown device',
          fromPlatform: (jsonMap['from_platform'] as String?) ?? 'unknown',
          fromAddress: datagram.address.address,
          controlPort: (jsonMap['control_port'] as int?) ?? _controlPort,
          linkMode: ConnectLinkModeJson.fromJson(
            jsonMap['link_mode'] as String?,
          ),
        );
        _pairResponseController.add(response);
        logger.d(
          '[Handoff/LAN] <- ${response.accepted ? 'pair_accept' : 'pair_reject'} from=${response.fromDeviceId} name=${response.fromDeviceName} address=${response.fromAddress}',
        );
        return;
      }

      if (type == 'snapshot_sync') {
        final snapshotJson = jsonMap['snapshot'];
        if (snapshotJson is! Map<String, dynamic>) return;
        final snapshot = ConnectPlaybackSnapshot.fromJson(snapshotJson);
        _snapshotController.add(
          ConnectSnapshotSync(
            fromDeviceId: fromDeviceId,
            fromAddress: datagram.address.address,
            snapshot: snapshot,
          ),
        );
        logger.d(
          '[Handoff/LAN] <- snapshot_sync from=$fromDeviceId address=${datagram.address.address} queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
        );
        return;
      }

      if (type == 'command_intent') {
        final command = (jsonMap['command'] as String?) ?? '';
        if (command.isEmpty) return;
        final payload =
            (jsonMap['payload'] as Map<String, dynamic>?) ?? const {};
        _commandIntentController.add(
          ConnectCommandIntent(
            fromDeviceId: fromDeviceId,
            fromAddress: datagram.address.address,
            command: command,
            payload: payload,
          ),
        );
        logger.d(
          '[Handoff/LAN] <- command_intent from=$fromDeviceId address=${datagram.address.address} cmd=$command payload=$payload',
        );
        return;
      }

      if (type == 'command_apply') {
        final command = (jsonMap['command'] as String?) ?? '';
        if (command.isEmpty) return;
        final payload =
            (jsonMap['payload'] as Map<String, dynamic>?) ?? const {};
        final sequence = (jsonMap['sequence'] as int?) ?? 0;
        _commandApplyController.add(
          ConnectCommandApply(
            fromDeviceId: fromDeviceId,
            fromAddress: datagram.address.address,
            sequence: sequence,
            command: command,
            payload: payload,
          ),
        );
        logger.d(
          '[Handoff/LAN] <- command_apply from=$fromDeviceId address=${datagram.address.address} seq=$sequence cmd=$command payload=$payload',
        );
        return;
      }

      if (type == 'command_ack') {
        final sequence = (jsonMap['sequence'] as int?) ?? 0;
        final isPlaying = (jsonMap['is_playing'] as bool?) ?? false;
        final positionMs = (jsonMap['position_ms'] as int?) ?? 0;
        ConnectPlaybackSnapshot? snapshot;
        final snapshotJson = jsonMap['snapshot'];
        if (snapshotJson is Map<String, dynamic>) {
          snapshot = ConnectPlaybackSnapshot.fromJson(snapshotJson);
        }
        _commandAckController.add(
          ConnectCommandAck(
            fromDeviceId: fromDeviceId,
            fromAddress: datagram.address.address,
            sequence: sequence,
            isPlaying: isPlaying,
            positionMs: positionMs,
            snapshot: snapshot,
          ),
        );
        logger.d(
          '[Handoff/LAN] <- command_ack from=$fromDeviceId address=${datagram.address.address} seq=$sequence playing=$isPlaying posMs=$positionMs snapshot=${snapshot != null}',
        );
        return;
      }

      if (type == 'unlink') {
        _unlinkController.add(
          ConnectUnlinkEvent(
            fromDeviceId: fromDeviceId,
            fromAddress: datagram.address.address,
          ),
        );
        logger.d(
          '[Handoff/LAN] <- unlink from=$fromDeviceId address=${datagram.address.address}',
        );
        return;
      }

      if (type == 'playback_pulse') {
        final isPlaying = (jsonMap['is_playing'] as bool?) ?? false;
        final positionMs = (jsonMap['position_ms'] as int?) ?? 0;
        _playbackPulseController.add(
          ConnectPlaybackPulse(
            fromDeviceId: fromDeviceId,
            fromAddress: datagram.address.address,
            isPlaying: isPlaying,
            positionMs: positionMs,
          ),
        );
        logger.d(
          '[Handoff/LAN] <- playback_pulse from=$fromDeviceId address=${datagram.address.address} playing=$isPlaying posMs=$positionMs',
        );
      }
    } catch (error) {
      logger.w('[Handoff/LAN] Failed to parse control datagram', error: error);
    }
  }

  void _broadcastDiscovery() {
    final socket = _discoverySocket;
    final localDeviceId = _localDeviceId;
    final localDeviceName = _localDeviceName;
    final localPlatform = _localPlatform;
    if (socket == null ||
        localDeviceId == null ||
        localDeviceName == null ||
        localPlatform == null) {
      return;
    }

    final payload = {
      'type': 'hello',
      'device_id': localDeviceId,
      'name': localDeviceName,
      'platform': localPlatform,
      'control_port': _controlPort,
      'ts': DateTime.now().toIso8601String(),
    };

    final data = utf8.encode(json.encode(payload));
    try {
      socket.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
    } catch (_) {}
  }

  void _sendControlDatagram(String address, Map<String, dynamic> payload) {
    final socket = _controlSocket;
    if (socket == null) return;
    try {
      socket.send(
        utf8.encode(json.encode(payload)),
        InternetAddress(address),
        _controlPort,
      );
    } catch (error) {
      logger.w('[Connect/LAN] Failed to send control datagram', error: error);
    }
  }
}
