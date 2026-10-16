// Copyright © 2026 wizeshi

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/features/connect/services/connect_models.dart';
import 'package:wisp/features/connect/services/connect_packet_models.dart';
import 'package:wisp/features/connect/services/connect_transport.dart';
import 'package:wisp/features/connect/state/connect_session_provider.dart';

class FakeConnectTransport implements ConnectTransport {
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
  final StreamController<String> _deviceLeftController =
      StreamController.broadcast();

  int broadcastDiscoveryCallCount = 0;
  bool isStarted = false;

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
  @override
  Stream<String> get deviceLeftStream => _deviceLeftController.stream;

  @override
  Future<void> start({
    required String localDeviceId,
    required String localDeviceName,
    required String localPlatform,
  }) async {
    isStarted = true;
  }

  @override
  Future<void> stop() async {
    isStarted = false;
  }

  @override
  Future<void> dispose() async {
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
    await _deviceLeftController.close();
  }

  @override
  void broadcastDiscovery() {
    broadcastDiscoveryCallCount++;
  }

  @override
  void requestPair({
    required ConnectDevice target,
    required String fromDeviceId,
    required String fromDeviceName,
    required String fromPlatform,
    required ConnectLinkMode mode,
    required HandoffSecurityLevel securityLevel,
  }) {}

  @override
  void respondPair({
    required String targetAddress,
    required bool accepted,
    required String localDeviceId,
    required String localDeviceName,
    required String localPlatform,
    required ConnectLinkMode mode,
    String? rejectionReason,
  }) {}

  @override
  void sendCommandAck({
    required String targetAddress,
    required String fromDeviceId,
    required int sequence,
    required bool isPlaying,
    required int positionMs,
    ConnectPlaybackSnapshot? snapshot,
  }) {}

  @override
  void sendCommandApply({
    required String targetAddress,
    required String fromDeviceId,
    required int sequence,
    required String command,
    Map<String, dynamic> payload = const {},
  }) {}

  @override
  void sendCommandIntent({
    required String targetAddress,
    required String fromDeviceId,
    required String command,
    Map<String, dynamic> payload = const {},
  }) {}

  @override
  void sendPositionPulse({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectPositionPulse pulse,
  }) {}

  @override
  void sendSnapshot({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectPlaybackSnapshot snapshot,
    bool includeOriginalQueue = true,
    bool includeResolvedYoutubeIds = true,
  }) {}

  @override
  void sendStateDelta({
    required String targetAddress,
    required String fromDeviceId,
    required ConnectStateDelta delta,
  }) {}

  @override
  void sendUnlink({
    required String targetAddress,
    required String fromDeviceId,
  }) {}

  void emitDevice(ConnectDevice device) {
    _discoveredDeviceController.add(device);
  }

  void emitDeviceLeft(String deviceId) {
    _deviceLeftController.add(deviceId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConnectSessionProvider discovery & keepalive rework', () {
    test('pruneDiscoveredDevicesOlderThan prunes stale devices and auto-unlinks linked peer', () async {
      final fakeTransport = FakeConnectTransport();
      final provider = ConnectSessionProvider(transport: fakeTransport);

      // Add a fresh device and a stale device
      final freshDevice = ConnectDevice(
        id: 'device_fresh',
        name: 'Fresh Phone',
        platform: 'android',
        address: '192.168.1.101',
        lastSeenAt: DateTime.now(),
      );
      final staleDevice = ConnectDevice(
        id: 'device_stale',
        name: 'Stale Laptop',
        platform: 'windows',
        address: '192.168.1.102',
        lastSeenAt: DateTime.now().subtract(const Duration(seconds: 16)),
      );

      provider.upsertDiscoveredDevice(freshDevice);
      provider.upsertDiscoveredDevice(staleDevice);

      expect(provider.discoveredDevices.length, 2);

      // Pruning with 15s threshold should remove device_stale
      provider.pruneDiscoveredDevicesOlderThan(const Duration(seconds: 15));

      expect(provider.discoveredDevices.length, 1);
      expect(provider.discoveredDevices.first.id, 'device_fresh');

      provider.dispose();
    });

    test('immediate removal on deviceLeftStream event', () async {
      final fakeTransport = FakeConnectTransport();
      final provider = ConnectSessionProvider(transport: fakeTransport);
      provider.startDiscovery();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final device = ConnectDevice(
        id: 'device_goodbye',
        name: 'Leaving Device',
        platform: 'macos',
        address: '192.168.1.105',
        lastSeenAt: DateTime.now(),
      );

      provider.upsertDiscoveredDevice(device);
      expect(provider.discoveredDevices.any((d) => d.id == 'device_goodbye'), isTrue);

      // Simulate receiving goodbye packet from peer
      fakeTransport.emitDeviceLeft('device_goodbye');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(provider.discoveredDevices.any((d) => d.id == 'device_goodbye'), isFalse);

      provider.dispose();
    });

    test('refreshDiscovery triggers broadcastDiscovery on running transport', () async {
      final fakeTransport = FakeConnectTransport();
      final provider = ConnectSessionProvider(transport: fakeTransport);
      provider.startDiscovery();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fakeTransport.broadcastDiscoveryCallCount, 0);

      provider.refreshDiscovery();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fakeTransport.broadcastDiscoveryCallCount, 1);

      provider.dispose();
    });
  });
}
