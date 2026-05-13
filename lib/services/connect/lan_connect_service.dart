import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wisp/services/connect/connect_models.dart';
import 'package:wisp/services/connect/connect_packet_models.dart';
import 'package:wisp/services/connect/connect_packet_router.dart';
import 'package:wisp/services/connect/connect_transport.dart';
import 'package:wisp/utils/logger.dart';

class LanConnectService implements ConnectTransport {
  static const int _discoveryPort = 47110;
  static const int _controlPort = 47111;
  static const int _tcpPort = 47112;

  final StreamController<ConnectDevice> _discoveredDeviceController =
      StreamController.broadcast();
  final StreamController<ConnectPairRequest> _pairRequestController =
      StreamController.broadcast();
  final StreamController<ConnectPairResponse> _pairResponseController =
      StreamController.broadcast();
  final StreamController<ConnectSnapshotSync> _snapshotController =
      StreamController.broadcast();
  final StreamController<ConnectStateDeltaSync> _stateDeltaController =
      StreamController.broadcast();
  final StreamController<ConnectPositionPulseSync> _positionPulseController =
      StreamController.broadcast();
  final StreamController<ConnectCommandIntent> _commandIntentController =
      StreamController.broadcast();
  final StreamController<ConnectCommandApply> _commandApplyController =
      StreamController.broadcast();
  final StreamController<ConnectCommandAck> _commandAckController =
      StreamController.broadcast();
  final StreamController<ConnectUnlinkEvent> _unlinkController =
      StreamController.broadcast();
  final ConnectPacketRouter _packetRouter = const ConnectPacketRouter();

    @override
  Stream<ConnectDevice> get discoveredDeviceStream =>
      _discoveredDeviceController.stream;
    @override
  Stream<ConnectPairRequest> get pairRequestStream =>
      _pairRequestController.stream;
    @override
  Stream<ConnectPairResponse> get pairResponseStream =>
      _pairResponseController.stream;
    @override
  Stream<ConnectSnapshotSync> get snapshotStream => _snapshotController.stream;
    @override
  Stream<ConnectStateDeltaSync> get stateDeltaStream =>
      _stateDeltaController.stream;
    @override
  Stream<ConnectPositionPulseSync> get positionPulseStream =>
      _positionPulseController.stream;
    @override
  Stream<ConnectCommandIntent> get commandIntentStream =>
      _commandIntentController.stream;
    @override
  Stream<ConnectCommandApply> get commandApplyStream =>
      _commandApplyController.stream;
    @override
  Stream<ConnectCommandAck> get commandAckStream =>
      _commandAckController.stream;
    @override
  Stream<ConnectUnlinkEvent> get unlinkStream => _unlinkController.stream;
  

  RawDatagramSocket? _discoverySocket;
  RawDatagramSocket? _controlSocket;
  ServerSocket? _tcpServer;
  final Map<String, Socket> _peerTcpConnections = {};
  final Map<String, String> _peerConnectionSourceByAddress = {};
  final Map<String, String> _peerDeviceIdByAddress = {};
  final Map<String, String> _peerAddressByDeviceId = {};
  Timer? _announceTimer;
  final Map<String, DateTime> _lastDiscoveryReplyAt = {};

  static const Duration _discoveryReplyThrottle = Duration(seconds: 10);

  bool _started = false;
  String? _localDeviceId;
  String? _localDeviceName;
  String? _localPlatform;

  @override
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

      logger.i('[Connect/LAN] STARTUP: About to bind TCP server on port $_tcpPort');
      _tcpServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _tcpPort,
      );
      logger.i('[Connect/LAN] STARTUP: TCP server socket bound successfully, address=${_tcpServer?.address}, port=${_tcpServer?.port}');
      
      _tcpServer!.listen(
        _onTcpServerConnection,
        onError: (error) {
          logger.w('[Connect/LAN] TCP server error', error: error);
        },
      );
      logger.i('[Connect/LAN] STARTUP: TCP server listen() callback attached');

      _announceTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _broadcastDiscovery(),
      );
      _broadcastDiscovery();
      _started = true;
      logger.i('[Connect/LAN] Discovery started on UDP $_discoveryPort, TCP server on $_tcpPort');
    } catch (error) {
      logger.e('[Connect/LAN] Failed to start', error: error);
      await stop();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _lastDiscoveryReplyAt.clear();

    _discoverySocket?.close();
    _discoverySocket = null;

    _controlSocket?.close();
    _controlSocket = null;

    // Close TCP server and all peer connections
    await _tcpServer?.close();
    _tcpServer = null;
    for (final socket in _peerTcpConnections.values) {
      await socket.close();
    }
    _peerTcpConnections.clear();

    _started = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _discoveredDeviceController.close();
    await _pairRequestController.close();
    await _pairResponseController.close();
    await _snapshotController.close();
    await _stateDeltaController.close();
    await _positionPulseController.close();
    await _commandIntentController.close();
    await _commandApplyController.close();
    await _commandAckController.close();
    await _unlinkController.close();
    
  }

  @override
  void requestPair({
    required ConnectDevice target,
    required String fromDeviceId,
    required String fromDeviceName,
    required String fromPlatform,
    required ConnectLinkMode mode,
    required HandoffSecurityLevel securityLevel,
  }) {
    final address = target.address;
    if (address == null || address.isEmpty) return;

    _sendControlDatagram(
      address,
      ConnectPacketEnvelope(
        packetType: 'handoff.pair_request',
        payload: {
          'from_device_id': fromDeviceId,
          'from_device_name': fromDeviceName,
          'from_platform': fromPlatform,
          'control_port': _controlPort,
          'requested_mode': mode.toJson(),
          'security_level': securityLevel.toJson(),
        },
        metadata: {'ts': DateTime.now().toIso8601String()},
      ),
    );
    logger.d('[Handoff/LAN] -> pair_request to=$address from=$fromDeviceId');
  }

  @override
  void respondPair({
    required String targetAddress,
    required bool accepted,
    required String localDeviceId,
    required String localDeviceName,
    required String localPlatform,
    required ConnectLinkMode mode,
    String? rejectionReason,
  }) {
    _sendControlDatagram(
      targetAddress,
      ConnectPacketEnvelope(
        packetType: accepted ? 'handoff.pair_accept' : 'handoff.pair_reject',
        payload: {
          'from_device_id': localDeviceId,
          'from_device_name': localDeviceName,
          'from_platform': localPlatform,
          'control_port': _controlPort,
          'link_mode': mode.toJson(),
          if (rejectionReason != null) 'rejection_reason': rejectionReason,
        },
        metadata: {'ts': DateTime.now().toIso8601String()},
      ),
    );
    logger.d(
      '[Handoff/LAN] -> ${accepted ? 'pair_accept' : 'pair_reject'} to=$targetAddress from=$localDeviceId',
    );
    // If accepted, initiate TCP connection to peer for large payload transfers
    if (accepted) {
      _connectToPeer(targetAddress).catchError((error) {
        logger.w('[Connect/LAN] Failed to establish TCP connection to $targetAddress', error: error);
      });
    }
  }

  // TCP Helper Methods

  Future<void> _connectToPeer(String address) async {
    logger.d('[Connect/LAN] _connectToPeer called for $address');
    if (_peerTcpConnections.containsKey(address)) {
      logger.d('[Connect/LAN] _connectToPeer: connection already exists for $address, skipping');
      return;
    }

    try {
      final dest = InternetAddress.tryParse(address);
      if (dest == null) {
        logger.e('[Connect/LAN] _connectToPeer FAIL: Cannot parse address: $address');
        return;
      }
      if (dest.address == '0.0.0.0') {
        logger.e('[Connect/LAN] _connectToPeer FAIL: Cannot connect to 0.0.0.0');
        return;
      }

      logger.d('[Connect/LAN] _connectToPeer: attempting outbound connection to $address:$_tcpPort');
      final socket = await Socket.connect(dest, _tcpPort, timeout: const Duration(seconds: 5));
      _peerTcpConnections[address] = socket;
      
      logger.i('[Connect/LAN] SUCCESS: TCP connection established to $address:$_tcpPort');
      _attachTcpSocket(peerAddress: address, socket: socket, source: 'outbound_connect');
    } catch (error) {
      logger.e('[Connect/LAN] FAIL: Failed to connect TCP to $address after 5s timeout', error: error);
      rethrow;
    }
  }

  void _closePeerConnection(String address) {
    final socket = _peerTcpConnections[address];
    if (socket == null) {
      return;
    }
    _closePeerConnectionForSocket(address, socket);
  }

  void _closePeerConnectionForSocket(String address, Socket socket) {
    final activeSocket = _peerTcpConnections[address];
    if (activeSocket == null) {
      return;
    }
    if (!identical(activeSocket, socket)) {
      logger.d('[Connect/LAN] Skip closing stale socket callback for $address (active socket differs)');
      return;
    }

    _peerTcpConnections.remove(address);
    _peerConnectionSourceByAddress.remove(address);
    socket.close().catchError((error) {
      logger.w('[Connect/LAN] Error closing TCP socket to $address', error: error);
    });
    logger.d('[Connect/LAN] TCP connection closed to $address');
  }

  void _rememberPeerDevice(String address, String? deviceId) {
    final normalized = (deviceId ?? '').trim();
    if (normalized.isEmpty) {
      return;
    }
    _peerDeviceIdByAddress[address] = normalized;
    _peerAddressByDeviceId[normalized] = address;
  }

  bool _shouldKeepIncomingSocket({required String peerAddress}) {
    final localId = (_localDeviceId ?? '').trim();
    final peerId = (_peerDeviceIdByAddress[peerAddress] ?? '').trim();
    if (localId.isEmpty || peerId.isEmpty) {
      // Unknown peer identity: prefer incoming to heal stale outbound channels.
      return true;
    }

    // Deterministic rule: lower device ID keeps outbound, higher keeps inbound.
    final localKeepsOutbound = localId.compareTo(peerId) < 0;
    return !localKeepsOutbound;
  }

  void _attachTcpSocket({
    required String peerAddress,
    required Socket socket,
    required String source,
  }) {
    _peerConnectionSourceByAddress[peerAddress] = source;
    logger.i('[Connect/LAN] STARTUP: Attaching socket.listen() to TCP socket from $peerAddress source=$source');

    // Buffer for incomplete messages
    String buffer = '';

    socket.listen(
      (List<int> data) {
        try {
          final decodedChunk = utf8.decode(data);
          buffer += decodedChunk;
          final lines = buffer.split('\n');
          // Keep last incomplete line in buffer
          buffer = lines.isNotEmpty ? lines.last : '';

          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) {
              continue;
            }

            try {
              final jsonMap = json.decode(line) as Map<String, dynamic>;
              final packet = ConnectPacketEnvelope.fromJson(jsonMap);
              // Route through packet router
              _packetRouter.route(
                packet: packet,
                localDeviceId: _localDeviceId ?? '',
                sourceAddress: peerAddress,
                onPairRequest: _pairRequestController.add,
                onPairResponse: _pairResponseController.add,
                onSnapshotSync: _snapshotController.add,
                onStateDelta: _stateDeltaController.add,
                onPositionPulse: _positionPulseController.add,
                onCommandIntent: _commandIntentController.add,
                onCommandApply: _commandApplyController.add,
                onCommandAck: _commandAckController.add,
                onUnlink: _unlinkController.add,
              );
            } catch (error) {
              logger.e('[Connect/LAN] FAIL: Failed to parse TCP packet from $peerAddress', error: error);
            }
          }
        } catch (error) {
          logger.e('[Connect/LAN] FAIL: Error processing TCP data from $peerAddress', error: error);
        }
      },
      onError: (error) {
        logger.e('[Connect/LAN] FAIL: TCP socket error from $peerAddress error=$error', error: error);
        _closePeerConnectionForSocket(peerAddress, socket);
      },
      onDone: () {
        _closePeerConnectionForSocket(peerAddress, socket);
      },
    );
  }

  void _sendViaTcp(String address, ConnectPacketEnvelope packet) {
    final socket = _peerTcpConnections[address];
    if (socket == null) {
      logger.e('[Connect/LAN] FATAL: No TCP connection to $address, cannot send ${packet.packetType}. Active connections: ${_peerTcpConnections.keys.toList()}');
      throw Exception('TCP connection not established to $address');
    }

    try {
      final encoded = '${packet.encode()}\n';
      final data = utf8.encode(encoded);
      socket.add(data);
      logger.d('[Connect/LAN] -> TCP ${packet.packetType} to=$address len=${data.length}B payload_keys=${packet.payload.keys.toList()}');
    } catch (error) {
      logger.e('[Connect/LAN] Failed to send TCP packet to $address packet=${packet.packetType}', error: error);
      _closePeerConnection(address);
      rethrow;
    }
  }

  Future<void> _onTcpServerConnection(Socket socket) async {
    final peerAddress = socket.remoteAddress.address;
    final peerPort = socket.remotePort;
    final timestamp = DateTime.now().toIso8601String();
    logger.i('[Connect/LAN] STARTUP: _onTcpServerConnection callback fired! timestamp=$timestamp');
    logger.i('[Connect/LAN] TRACE: Incoming TCP connection from $peerAddress:$peerPort at $timestamp');

    // If we already have a connection to this peer, resolve deterministically.
    final existingSocket = _peerTcpConnections[peerAddress];
    if (existingSocket != null && !identical(existingSocket, socket)) {
      final keepIncoming = _shouldKeepIncomingSocket(peerAddress: peerAddress);
      if (!keepIncoming) {
        logger.w('[Connect/LAN] TRACE: Keeping existing TCP connection for $peerAddress (deterministic duplicate resolution), closing incoming at $timestamp');
        socket.close();
        return;
      }
      logger.w('[Connect/LAN] TRACE: Replacing existing TCP connection for $peerAddress with inbound socket (deterministic duplicate resolution) at $timestamp');
      _closePeerConnectionForSocket(peerAddress, existingSocket);
    }

    _peerTcpConnections[peerAddress] = socket;
    logger.i('[Connect/LAN] TRACE: Stored TCP connection from $peerAddress');
    _attachTcpSocket(peerAddress: peerAddress, socket: socket, source: 'inbound_accept');
  }

  // Public Transport API

  @override
  void sendSnapshot({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectPlaybackSnapshot snapshot,
    bool includeOriginalQueue = true,
    bool includeResolvedYoutubeIds = true,
  }) {
    final payloadSnapshot = snapshot.toJson()
      ..removeWhere((key, value) {
        if (key == 'original_queue' && !includeOriginalQueue) {
          return true;
        }
        if (key == 'resolved_youtube_ids' && !includeResolvedYoutubeIds) {
          return true;
        }
        return false;
      });

    final packet = ConnectPacketEnvelope(
      packetType: 'audio.snapshot_sync',
      payload: {
        'from_device_id': fromDeviceId,
        'snapshot': payloadSnapshot,
      },
      metadata: {'ts': DateTime.now().toIso8601String()},
    );
    final encoded = packet.encode();
    final byteLength = utf8.encode(encoded).length;
    
    // Use TCP for large snapshots, UDP for small ones
    const int safeUdpPayload = 40000;
    if (byteLength > safeUdpPayload) {
      logger.d(
        '[Handoff/LAN] snapshot_sync size=${byteLength}B (over UDP limit) using TCP target=$targetAddress queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
      );
      try {
        _sendViaTcp(targetAddress, packet);
        logger.d(
          '[Handoff/LAN] -> snapshot_sync to=$targetAddress via TCP from=$fromDeviceId queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
        );
      } catch (error) {
        logger.e('[Handoff/LAN] Failed to send snapshot via TCP', error: error);
        rethrow;
      }
    } else {
      logger.d(
        '[Handoff/LAN] snapshot_sync size=${byteLength}B target=$targetAddress queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
      );
      _sendControlDatagram(targetAddress, packet);
      logger.d(
        '[Handoff/LAN] -> snapshot_sync to=$targetAddress from=$fromDeviceId queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
      );
    }
  }

  @override
  void sendStateDelta({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectStateDelta delta,
  }) {
    _sendControlDatagram(
      targetAddress,
      ConnectPacketEnvelope(
        packetType: 'audio.state_delta',
        payload: {
          'from_device_id': fromDeviceId,
          'delta': delta.toJson(),
        },
        metadata: {'ts': DateTime.now().toIso8601String()},
      ),
    );
    logger.d(
      '[Handoff/LAN] -> state_delta to=$targetAddress from=$fromDeviceId seq=${delta.seq}',
    );
  }

  @override
  void sendPositionPulse({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectPositionPulse pulse,
  }) {
    _sendControlDatagram(
      targetAddress,
      ConnectPacketEnvelope(
        packetType: 'audio.position_pulse',
        payload: {
          'from_device_id': fromDeviceId,
          'pulse': pulse.toJson(),
        },
        metadata: {'ts': DateTime.now().toIso8601String()},
      ),
    );
    logger.d(
      '[Handoff/LAN] -> position_pulse to=$targetAddress from=$fromDeviceId posMs=${pulse.positionMs}',
    );
  }

  @override
  void sendCommandIntent({
    required String targetAddress,
    required String fromDeviceId,
    required String command,
    Map<String, dynamic> payload = const {},
  }) {
    final packet = ConnectPacketEnvelope(
      packetType: 'audio.command_intent',
      payload: {
        'from_device_id': fromDeviceId,
        'command': command,
        'payload': payload,
      },
      metadata: {'ts': DateTime.now().toIso8601String()},
    );
    final encoded = packet.encode();
    final byteLength = utf8.encode(encoded).length;
    if (command == 'set_queue') {
      logger.d(
        '[Handoff/LAN] command_intent using TCP target=$targetAddress cmd=$command size=${byteLength}B',
      );
      _sendViaTcp(targetAddress, packet);
    } else {
      _sendControlDatagram(targetAddress, packet);
    }
    logger.d(
      '[Handoff/LAN] -> command_intent to=$targetAddress from=$fromDeviceId cmd=$command payload=$payload',
    );
  }

  @override
  void sendCommandApply({
    required String targetAddress,
    required String fromDeviceId,
    required int sequence,
    required String command,
    Map<String, dynamic> payload = const {},
  }) {
    final packet = ConnectPacketEnvelope(
      packetType: 'audio.command_apply',
      payload: {
        'from_device_id': fromDeviceId,
        'sequence': sequence,
        'command': command,
        'payload': payload,
      },
      metadata: {'ts': DateTime.now().toIso8601String()},
    );
    final encoded = packet.encode();
    final byteLength = utf8.encode(encoded).length;
    if (command == 'set_queue') {
      logger.d(
        '[Handoff/LAN] command_apply using TCP target=$targetAddress seq=$sequence cmd=$command size=${byteLength}B',
      );
      _sendViaTcp(targetAddress, packet);
    } else {
      _sendControlDatagram(targetAddress, packet);
    }
    logger.d(
      '[Handoff/LAN] -> command_apply to=$targetAddress from=$fromDeviceId seq=$sequence cmd=$command payload=$payload',
    );
  }

  @override
  void sendCommandAck({
    required String targetAddress,
    required String fromDeviceId,
    required int sequence,
    required bool isPlaying,
    required int positionMs,
    ConnectPlaybackSnapshot? snapshot,
  }) {
    // Try to send ack with embedded snapshot via UDP if it fits
    const int safeUdpPayload = 40000;
    if (snapshot != null) {
      final packetWithSnapshot = ConnectPacketEnvelope(
        packetType: 'audio.command_ack',
        payload: {
          'from_device_id': fromDeviceId,
          'sequence': sequence,
          'is_playing': isPlaying,
          'position_ms': positionMs,
          'snapshot': snapshot.toJson(),
        },
        metadata: {'ts': DateTime.now().toIso8601String()},
      );
      final encoded = packetWithSnapshot.encode();
      final byteLength = utf8.encode(encoded).length;
      if (byteLength <= safeUdpPayload) {
        _sendControlDatagram(targetAddress, packetWithSnapshot);
        logger.d(
          '[Handoff/LAN] -> command_ack to=$targetAddress from=$fromDeviceId seq=$sequence playing=$isPlaying posMs=$positionMs size=${byteLength}B',
        );
        return;
      }

      // Too large for UDP: send lightweight ack via UDP, then snapshot via TCP
      _sendControlDatagram(
        targetAddress,
        ConnectPacketEnvelope(
          packetType: 'audio.command_ack',
          payload: {
            'from_device_id': fromDeviceId,
            'sequence': sequence,
            'is_playing': isPlaying,
            'position_ms': positionMs,
          },
          metadata: {'ts': DateTime.now().toIso8601String()},
        ),
      );
      logger.d(
        '[Handoff/LAN] -> command_ack to=$targetAddress from=$fromDeviceId seq=$sequence playing=$isPlaying posMs=$positionMs (ack only, snapshot follows via TCP)',
      );
      // Send snapshot via TCP
      try {
        sendSnapshot(
          targetAddress: targetAddress,
          fromDeviceId: fromDeviceId,
          snapshot: snapshot,
        );
      } catch (error) {
        logger.w('[Handoff/LAN] Failed to send snapshot after command_ack', error: error);
      }
      return;
    }

    _sendControlDatagram(
      targetAddress,
      ConnectPacketEnvelope(
        packetType: 'audio.command_ack',
        payload: {
          'from_device_id': fromDeviceId,
          'sequence': sequence,
          'is_playing': isPlaying,
          'position_ms': positionMs,
        },
        metadata: {'ts': DateTime.now().toIso8601String()},
      ),
    );
    logger.d(
      '[Handoff/LAN] -> command_ack to=$targetAddress from=$fromDeviceId seq=$sequence playing=$isPlaying posMs=$positionMs',
    );
  }

  @override
  void sendUnlink({
    required String targetAddress,
    required String fromDeviceId,
  }) {
    _sendControlDatagram(
      targetAddress,
      ConnectPacketEnvelope(
        packetType: 'handoff.unlink',
        payload: {'from_device_id': fromDeviceId},
        metadata: {'ts': DateTime.now().toIso8601String()},
      ),
    );
    logger.d('[Handoff/LAN] -> unlink to=$targetAddress from=$fromDeviceId');
    
    // Close TCP connection to this peer
    _closePeerConnection(targetAddress);
  }

  void _onDiscoverySocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _discoverySocket?.receive();
    if (datagram == null) return;

    try {
      final message = utf8.decode(datagram.data);
      final jsonMap = json.decode(message) as Map<String, dynamic>;
      final packet = ConnectPacketEnvelope.fromJson(jsonMap);
      final isHello =
          packet.packetType == 'hello' || packet.packetType == 'connect.hello';
      final isHelloReply = packet.packetType == 'hello_reply' ||
          packet.packetType == 'connect.hello_reply';
      if (!isHello && !isHelloReply) {
        return;
      }

      final payload = packet.payload;
      final deviceId = (payload['device_id'] as String?) ?? '';
      if (deviceId.isEmpty) return;
      if (_localDeviceId != null && deviceId == _localDeviceId) return;

      _rememberPeerDevice(datagram.address.address, deviceId);

      if (isHello) {
        _replyToDiscoveryHello(datagram.address.address, deviceId);
      }

      final device = ConnectDevice(
        id: deviceId,
        name: (payload['name'] as String?) ?? 'Unknown device',
        platform: (payload['platform'] as String?) ?? 'unknown',
        address: datagram.address.address,
        lastSeenAt: DateTime.now(),
      );

      _discoveredDeviceController.add(device);
      logger.d(
        '[Handoff/LAN] <- hello from=${device.id} name=${device.name} platform=${device.platform} address=${device.address}',
      );
    } catch (_) {}
  }

  void _replyToDiscoveryHello(String targetAddress, String deviceId) {
    final localDeviceId = _localDeviceId;
    final localDeviceName = _localDeviceName;
    final localPlatform = _localPlatform;
    if (localDeviceId == null ||
        localDeviceName == null ||
        localPlatform == null) {
      return;
    }

    final now = DateTime.now();
    final replyKey = '$targetAddress|$deviceId';
    final lastReplyAt = _lastDiscoveryReplyAt[replyKey];
    if (lastReplyAt != null &&
        now.difference(lastReplyAt) < _discoveryReplyThrottle) {
      return;
    }
    _lastDiscoveryReplyAt[replyKey] = now;

    final packet = ConnectPacketEnvelope(
      packetType: 'connect.hello_reply',
      payload: {
        'device_id': localDeviceId,
        'name': localDeviceName,
        'platform': localPlatform,
        'control_port': _controlPort,
      },
      metadata: {'ts': now.toIso8601String()},
    );

    final payload = packet.toJson()
      ..addAll({
        'type': 'hello_reply',
        'device_id': localDeviceId,
        'name': localDeviceName,
        'platform': localPlatform,
        'control_port': _controlPort,
        'ts': now.toIso8601String(),
      });

    try {
      final dest = InternetAddress.tryParse(targetAddress);
      if (dest == null) {
        logger.w('[Connect/LAN] Invalid discovery reply address: $targetAddress');
      } else {
        _discoverySocket?.send(
          utf8.encode(json.encode(payload)),
          dest,
          _discoveryPort,
        );
      }
    } catch (error) {
      logger.w('[Connect/LAN] Failed to send discovery reply to $targetAddress', error: error);
    }
  }

  void _onControlSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _controlSocket?.receive();
    if (datagram == null) return;

    try {
      final message = utf8.decode(datagram.data);
      final jsonMap = json.decode(message) as Map<String, dynamic>;
      final packet = ConnectPacketEnvelope.fromJson(jsonMap);
      _rememberPeerDevice(
        datagram.address.address,
        packet.payload['from_device_id'] as String?,
      );
        logger.d('[Connect/LAN] control datagram from=${datagram.address.address} packet=${packet.packetType} from_device_id=${packet.payload['from_device_id'] ?? 'unknown'}');
      _packetRouter.route(
        packet: packet,
        localDeviceId: _localDeviceId ?? '',
        sourceAddress: datagram.address.address,
        onPairRequest: _pairRequestController.add,
        onPairResponse: _pairResponseController.add,
        onSnapshotSync: _snapshotController.add,
        onStateDelta: _stateDeltaController.add,
        onPositionPulse: _positionPulseController.add,
        onCommandIntent: _commandIntentController.add,
        onCommandApply: _commandApplyController.add,
        onCommandAck: _commandAckController.add,
        onUnlink: _unlinkController.add,
      );
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

        final packet = ConnectPacketEnvelope(
          packetType: 'connect.hello',
          payload: {
            'device_id': localDeviceId,
            'name': localDeviceName,
            'platform': localPlatform,
            'control_port': _controlPort,
          },
          metadata: {'ts': DateTime.now().toIso8601String()},
        );
        final payload = packet.toJson()
          ..addAll({
            'type': 'hello',
            'device_id': localDeviceId,
            'name': localDeviceName,
            'platform': localPlatform,
            'control_port': _controlPort,
            'ts': DateTime.now().toIso8601String(),
          });

        final data = utf8.encode(json.encode(payload));
    try {
      socket.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
    } catch (_) {}
  }

  void _sendControlDatagram(String address, ConnectPacketEnvelope packet) {
    final socket = _controlSocket;
    if (socket == null) return;

    final dest = InternetAddress.tryParse(address);
    if (dest == null) {
      logger.w('[Connect/LAN] Refusing to send control datagram to invalid address: $address');
      return;
    }
    if (dest.address == '0.0.0.0') {
      logger.w('[Connect/LAN] Refusing to send control datagram to 0.0.0.0 (likely unknown peer)');
      return;
    }

    final data = utf8.encode(packet.encode());
    try {
      logger.d('[Connect/LAN] sending control datagram to=${dest.address} len=${data.length} packet=${packet.packetType}');
      logger.d('[Connect/LAN] about to call socket.send(len=${data.length}, dest=${dest.address}, port=$_controlPort)');
      socket.send(
        data,
        dest,
        _controlPort,
      );
    } catch (error, st) {
      logger.w('[Connect/LAN] Failed to send control datagram to ${dest.address}', error: error, stackTrace: st);
    }
  }
}
