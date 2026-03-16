import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/services/connect/connect_models.dart';
import 'package:wisp/services/connect/lan_connect_service.dart';
import 'package:wisp/services/wisp_audio_handler.dart';
import 'package:wisp/utils/logger.dart';

class ConnectSessionProvider extends ChangeNotifier {
  static const String _keyLocalDeviceId = 'connect_local_device_id';
  static const String _cmdPlay = 'play';
  static const String _cmdPause = 'pause';
  static const String _cmdSeek = 'seek';
  static const String _cmdSkipNext = 'skip_next';
  static const String _cmdSkipPrevious = 'skip_previous';
  static const String _cmdToggleShuffle = 'toggle_shuffle';
  static const String _cmdToggleRepeat = 'toggle_repeat';

  ConnectPhase _phase = ConnectPhase.idle;
  ConnectPhase get phase => _phase;

  ConnectRole _role = ConnectRole.none;
  ConnectRole get role => _role;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _localDeviceId = '';
  String get localDeviceId => _localDeviceId;

  String _localDeviceName = '';
  String get localDeviceName => _localDeviceName;

  final Map<String, ConnectDevice> _discoveredById = {};
  List<ConnectDevice> get discoveredDevices =>
      _discoveredById.values.toList()
        ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));

  String? _linkedDeviceId;
  String? get linkedDeviceId => _linkedDeviceId;

  int _lastAppliedSequence = -1;
  int get lastAppliedSequence => _lastAppliedSequence;

  int _lastAckedSequence = -1;
  int get lastAckedSequence => _lastAckedSequence;

  Duration _linkedPosition = Duration.zero;
  Duration get linkedPosition => _linkedPosition;
  Duration get linkedInterpolatedPosition {
    final updatedAt = _linkedPositionUpdatedAt;
    if (!_linkedIsPlaying || updatedAt == null) {
      return _linkedPosition;
    }
    final elapsed = DateTime.now().difference(updatedAt);
    if (elapsed.isNegative) {
      return _linkedPosition;
    }
    return _linkedPosition + elapsed;
  }

  bool _linkedIsPlaying = false;
  bool get linkedIsPlaying => _linkedIsPlaying;

  Map<String, String> _sessionResolvedYoutubeIds = {};
  Map<String, String> get sessionResolvedYoutubeIds =>
      Map.unmodifiable(_sessionResolvedYoutubeIds);

  final LanConnectService _lanConnectService = LanConnectService();
  Future<void>? _initFuture;
  StreamSubscription<ConnectDevice>? _deviceSubscription;
  StreamSubscription<ConnectPairRequest>? _pairRequestSubscription;
  StreamSubscription<ConnectPairResponse>? _pairResponseSubscription;
  StreamSubscription<ConnectSnapshotSync>? _snapshotSubscription;
  StreamSubscription<ConnectCommandIntent>? _commandIntentSubscription;
  StreamSubscription<ConnectCommandApply>? _commandApplySubscription;
  StreamSubscription<ConnectCommandAck>? _commandAckSubscription;
  StreamSubscription<ConnectUnlinkEvent>? _unlinkSubscription;
  StreamSubscription<ConnectPlaybackPulse>? _playbackPulseSubscription;
  Timer? _pruneTimer;
  Timer? _targetPulseTimer;
  Timer? _hostInterpolationTimer;
  DateTime? _linkedPositionUpdatedAt;
  ConnectPairRequest? _pendingPairRequest;
  ConnectPairRequest? get pendingPairRequest => _pendingPairRequest;
  String? _pairingTargetDeviceId;
  String? _pairingTargetAddress;
  String? _linkedPeerAddress;
  int _hostCommandSequence = 0;
  WispAudioHandler? _audioHandler;
  bool _discoveryStarted = false;
  bool get discoveryStarted => _discoveryStarted;

  ConnectSessionProvider() {
    _initFuture = _initialize();
    unawaited(
      Future<void>(() async {
        final initFuture = _initFuture;
        if (initFuture != null) {
          await initFuture;
        }
        startDiscovery();
      }),
    );
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_keyLocalDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _generateDeviceId();
      await prefs.setString(_keyLocalDeviceId, deviceId);
    }

    _localDeviceId = deviceId;
    _localDeviceName = await _resolveLocalDeviceName();
    final loweredHost = _localDeviceName.trim().toLowerCase();
    if (loweredHost == 'localhost' || loweredHost == 'localhost.localdomain') {
      if (Platform.isAndroid) {
        _localDeviceName = 'Android device';
      } else if (Platform.isIOS) {
        _localDeviceName = 'iPhone';
      }
    }
    if (_localDeviceName.trim().isEmpty) {
      _localDeviceName = '${Platform.operatingSystem} device';
    }
    logger.d(
      '[Handoff] Initialized local device id=$_localDeviceId name=$_localDeviceName platform=$localPlatform',
    );
    notifyListeners();
  }

  Future<String> _resolveLocalDeviceName() async {
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        final model = info.model.trim();
        if (model.isNotEmpty) return model;
        return 'Android device';
      } catch (error) {
        logger.w(
          '[Handoff] Failed to resolve Android make/model',
          error: error,
        );
      }
    }

    final host = Platform.localHostname.trim();
    if (host.isNotEmpty) return host;
    return '${Platform.operatingSystem} device';
  }

  bool get isLinked => _linkedDeviceId != null;
  bool get isHost => _role == ConnectRole.host;
  bool get isTarget => _role == ConnectRole.target;
  String get localPlatform => Platform.operatingSystem;

  void bindAudioHandler(WispAudioHandler audioHandler) {
    _audioHandler = audioHandler;
  }

  Future<void> requestPlay() async {
    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      if (audio.currentTrack != null) {
        await audio.play();
      } else if (audio.queueTracks.isNotEmpty) {
        await audio.playTrack(audio.queueTracks.first);
      }
      return;
    }

    await _requestCommand(_cmdPlay);
  }

  Future<void> requestPause() async {
    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      await audio.pause();
      return;
    }

    await _requestCommand(_cmdPause);
  }

  Future<void> requestSeek(Duration position) async {
    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      await audio.seek(position);
      return;
    }

    await _requestCommand(
      _cmdSeek,
      payload: {'position_ms': position.inMilliseconds},
    );
  }

  Future<void> requestSkipNext() async {
    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      await audio.skipNext();
      return;
    }

    await _requestCommand(_cmdSkipNext);
  }

  Future<void> requestSkipPrevious() async {
    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      await audio.skipPrevious();
      return;
    }

    await _requestCommand(_cmdSkipPrevious);
  }

  Future<void> requestToggleShuffle() async {
    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      audio.toggleShuffle();
      return;
    }

    await _requestCommand(_cmdToggleShuffle);
  }

  Future<void> requestToggleRepeat() async {
    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      audio.toggleRepeat();
      return;
    }

    await _requestCommand(_cmdToggleRepeat);
  }

  void startDiscovery() {
    unawaited(_startDiscoveryInternal());
  }

  void stopDiscovery() {
    unawaited(_stopDiscoveryInternal());
  }

  void refreshDiscovery() {
    unawaited(_refreshDiscoveryInternal());
  }

  void upsertDiscoveredDevice(ConnectDevice device) {
    _discoveredById[device.id] = device;
    notifyListeners();
  }

  void pruneDiscoveredDevicesOlderThan(Duration maxAge) {
    final now = DateTime.now();
    final idsToRemove = _discoveredById.values
        .where((device) => now.difference(device.lastSeenAt) > maxAge)
        .map((device) => device.id)
        .toList();

    if (idsToRemove.isEmpty) return;
    for (final id in idsToRemove) {
      _discoveredById.remove(id);
    }
    notifyListeners();
  }

  void beginPairing(String deviceId) {
    final target = _discoveredById[deviceId];
    if (target == null) {
      setError('Target device is no longer available.');
      return;
    }

    _clearError();
    _pairingTargetDeviceId = deviceId;
    _pairingTargetAddress = target.address;
    _setPhase(ConnectPhase.pairing);
    logger.d(
      '[Handoff] Begin pairing targetId=$deviceId targetName=${target.name} targetAddress=${target.address}',
    );

    _lanConnectService.requestPair(
      target: target,
      fromDeviceId: _localDeviceId,
      fromDeviceName: _localDeviceName,
      fromPlatform: localPlatform,
    );
  }

  void acceptIncomingPair() {
    final request = _pendingPairRequest;
    if (request == null) return;

    _lanConnectService.respondPair(
      targetAddress: request.fromAddress,
      accepted: true,
      localDeviceId: _localDeviceId,
      localDeviceName: _localDeviceName,
      localPlatform: localPlatform,
    );
    markLinkedSyncingAsTarget(request.fromDeviceId);
    _pairingTargetAddress = request.fromAddress;
    _linkedPeerAddress = request.fromAddress;
    logger.d(
      '[Handoff] Accepted incoming pair from ${request.fromDeviceName} (${request.fromDeviceId}) @ ${request.fromAddress}',
    );
    _pendingPairRequest = null;
    notifyListeners();
  }

  void rejectIncomingPair() {
    final request = _pendingPairRequest;
    if (request == null) return;

    _lanConnectService.respondPair(
      targetAddress: request.fromAddress,
      accepted: false,
      localDeviceId: _localDeviceId,
      localDeviceName: _localDeviceName,
      localPlatform: localPlatform,
    );
    _pendingPairRequest = null;
    _pairingTargetAddress = null;
    _linkedPeerAddress = null;
    _pairingTargetDeviceId = null;
    logger.d('[Handoff] Rejected incoming pair request.');
    if (_phase == ConnectPhase.pairing) {
      _setPhase(ConnectPhase.idle);
    } else {
      notifyListeners();
    }
  }

  void markLinkedSyncingAsHost(String targetDeviceId) {
    _role = ConnectRole.host;
    _linkedDeviceId = targetDeviceId;
    logger.d('[Handoff] Role=host linkedDeviceId=$targetDeviceId');
    _stopTargetPulseTimer();
    _clearError();
    _setPhase(ConnectPhase.linkedSyncing);
  }

  void markLinkedSyncingAsTarget(String hostDeviceId) {
    _role = ConnectRole.target;
    _linkedDeviceId = hostDeviceId;
    logger.d('[Handoff] Role=target linkedDeviceId=$hostDeviceId');
    _ensureTargetPulseTimer();
    _clearError();
    _setPhase(ConnectPhase.linkedSyncing);
  }

  void markLinkedPlaying({
    required bool isPlaying,
    required Duration position,
  }) {
    _setLinkedPlaybackState(isPlaying: isPlaying, position: position);
    logger.d(
      '[Handoff] Linked state isPlaying=$isPlaying positionMs=${position.inMilliseconds}',
    );
    _setPhase(ConnectPhase.linkedPlaying);
  }

  void _setLinkedPlaybackState({
    required bool isPlaying,
    required Duration position,
    bool notify = true,
  }) {
    _linkedIsPlaying = isPlaying;
    _linkedPosition = position;
    _linkedPositionUpdatedAt = DateTime.now();

    if (isHost && isLinked && _linkedIsPlaying) {
      _ensureHostInterpolationTimer();
    } else {
      _stopHostInterpolationTimer();
    }

    if (notify) {
      notifyListeners();
    }
  }

  void applyResolvedYoutubeIds(Map<String, String> resolvedIds) {
    if (resolvedIds.isEmpty) return;
    _sessionResolvedYoutubeIds = {
      ..._sessionResolvedYoutubeIds,
      ...resolvedIds,
    };
    notifyListeners();
  }

  void markCommandApplied(int sequence) {
    if (sequence <= _lastAppliedSequence) return;
    _lastAppliedSequence = sequence;
    notifyListeners();
  }

  void markCommandAcked(int sequence) {
    if (sequence <= _lastAckedSequence) return;
    _lastAckedSequence = sequence;
    notifyListeners();
  }

  void unlink({
    bool localResumed = true,
    Duration resumePosition = Duration.zero,
    bool resumePlaying = false,
    bool notifyPeer = true,
  }) {
    final peerAddress = _linkedPeerAddress ?? _pairingTargetAddress;
    final peerDeviceId = _linkedDeviceId;
    if (notifyPeer &&
        peerAddress != null &&
        peerAddress.isNotEmpty &&
        peerDeviceId != null) {
      _lanConnectService.sendUnlink(
        targetAddress: peerAddress,
        fromDeviceId: _localDeviceId,
      );
      logger.d(
        '[Handoff] Sent unlink to peer id=$peerDeviceId address=$peerAddress',
      );
    }

    logger.d(
      '[Handoff] Unlink localResumed=$localResumed resumePositionMs=${resumePosition.inMilliseconds} resumePlaying=$resumePlaying',
    );
    _setPhase(ConnectPhase.unlinking);
    _linkedDeviceId = null;
    _role = ConnectRole.none;
    _pairingTargetDeviceId = null;
    _pairingTargetAddress = null;
    _linkedPeerAddress = null;
    _pendingPairRequest = null;
    _linkedPosition = resumePosition;
    _linkedIsPlaying = resumePlaying;
    _linkedPositionUpdatedAt = DateTime.now();
    _lastAppliedSequence = -1;
    _lastAckedSequence = -1;
    _stopTargetPulseTimer();
    _stopHostInterpolationTimer();

    if (localResumed) {
      _setPhase(ConnectPhase.localResumed);
    } else {
      _setPhase(ConnectPhase.idle);
    }
  }

  void clearSessionState() {
    _linkedDeviceId = null;
    _role = ConnectRole.none;
    _phase = ConnectPhase.idle;
    _lastAppliedSequence = -1;
    _lastAckedSequence = -1;
    _linkedPosition = Duration.zero;
    _linkedIsPlaying = false;
    _linkedPositionUpdatedAt = null;
    _sessionResolvedYoutubeIds = {};
    _pendingPairRequest = null;
    _pairingTargetDeviceId = null;
    _pairingTargetAddress = null;
    _linkedPeerAddress = null;
    _clearError();
    _stopTargetPulseTimer();
    _stopHostInterpolationTimer();
    notifyListeners();
  }

  void setError(String message) {
    _errorMessage = message;
    _phase = ConnectPhase.error;
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage == null && _phase != ConnectPhase.error) {
      return;
    }
    _errorMessage = null;
    if (_phase == ConnectPhase.error) {
      _phase = isLinked ? ConnectPhase.linkedPlaying : ConnectPhase.idle;
    }
  }

  void _setPhase(ConnectPhase next) {
    if (_phase == next) {
      notifyListeners();
      return;
    }
    _phase = next;
    notifyListeners();
  }

  String _generateDeviceId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    final buffer = StringBuffer('wisp_');
    for (var i = 0; i < 16; i++) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  Future<void> _startDiscoveryInternal() async {
    if (_phase == ConnectPhase.unlinking) return;
    _clearError();

    if (_discoveryStarted) {
      _pruneTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        pruneDiscoveredDevicesOlderThan(const Duration(seconds: 8));
      });
      pruneDiscoveredDevicesOlderThan(const Duration(seconds: 8));
      notifyListeners();
      logger.d('[Handoff] Discovery already running; reusing current session.');
      return;
    }

    final initFuture = _initFuture;
    if (initFuture != null) {
      await initFuture;
    }

    _deviceSubscription ??= _lanConnectService.discoveredDeviceStream.listen(
      upsertDiscoveredDevice,
    );
    _pairRequestSubscription ??= _lanConnectService.pairRequestStream.listen(
      _onPairRequest,
    );
    _pairResponseSubscription ??= _lanConnectService.pairResponseStream.listen(
      _onPairResponse,
    );
    _snapshotSubscription ??= _lanConnectService.snapshotStream.listen(
      _onSnapshotSync,
    );
    _commandIntentSubscription ??= _lanConnectService.commandIntentStream
        .listen(_onCommandIntent);
    _commandApplySubscription ??= _lanConnectService.commandApplyStream.listen(
      _onCommandApply,
    );
    _commandAckSubscription ??= _lanConnectService.commandAckStream.listen(
      _onCommandAck,
    );
    _unlinkSubscription ??= _lanConnectService.unlinkStream.listen(
      _onUnlinkEvent,
    );
    _playbackPulseSubscription ??= _lanConnectService.playbackPulseStream
        .listen(_onPlaybackPulse);

    _pruneTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      pruneDiscoveredDevicesOlderThan(const Duration(seconds: 8));
    });

    try {
      await _lanConnectService.start(
        localDeviceId: _localDeviceId,
        localDeviceName: _localDeviceName,
        localPlatform: localPlatform,
      );
      _discoveryStarted = true;
      logger.d('[Handoff] Discovery started.');
      if (!isLinked && _phase != ConnectPhase.pairing) {
        _setPhase(ConnectPhase.discovering);
      } else {
        notifyListeners();
      }
    } catch (_) {
      setError('Could not start LAN discovery.');
      logger.e('[Handoff] Could not start LAN discovery.');
    }
  }

  Future<void> _stopDiscoveryInternal() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _stopTargetPulseTimer();
    _stopHostInterpolationTimer();

    await _lanConnectService.stop();
    _discoveryStarted = false;
    logger.d('[Handoff] Discovery stopped.');

    if (_phase == ConnectPhase.discovering || _phase == ConnectPhase.pairing) {
      _setPhase(ConnectPhase.idle);
    }
  }

  Future<void> _refreshDiscoveryInternal() async {
    logger.d('[Handoff] Refresh discovery requested.');
    _discoveredById.clear();
    notifyListeners();

    if (_discoveryStarted) {
      await _lanConnectService.stop();
      _discoveryStarted = false;
    }

    await _startDiscoveryInternal();
  }

  void _onPairRequest(ConnectPairRequest request) {
    logger.d(
      '[Handoff] Incoming pair request from ${request.fromDeviceName} (${request.fromDeviceId}) @ ${request.fromAddress}',
    );
    _pendingPairRequest = request;
    _setPhase(ConnectPhase.pairing);
  }

  void _onPairResponse(ConnectPairResponse response) {
    if (_pairingTargetDeviceId == null ||
        response.fromDeviceId != _pairingTargetDeviceId) {
      return;
    }

    if (response.accepted) {
      logger.d(
        '[Handoff] Pair accepted by ${response.fromDeviceName} (${response.fromDeviceId}) @ ${response.fromAddress}',
      );
      markLinkedSyncingAsHost(response.fromDeviceId);
      _pairingTargetAddress = response.fromAddress;
      _linkedPeerAddress = response.fromAddress;
      _sendCurrentSnapshotToTarget(response.fromAddress);
      unawaited(_pauseLocalPlaybackAsHost());
    } else {
      logger.d(
        '[Handoff] Pair rejected by ${response.fromDeviceName} (${response.fromDeviceId})',
      );
      _linkedDeviceId = null;
      _pairingTargetDeviceId = null;
      _pairingTargetAddress = null;
      _linkedPeerAddress = null;
      _setPhase(ConnectPhase.idle);
      setError('Pair request rejected by target device.');
    }
  }

  void _onSnapshotSync(ConnectSnapshotSync sync) {
    if (sync.fromDeviceId == _localDeviceId) return;

    logger.d(
      '[Handoff] Snapshot sync from ${sync.fromDeviceId} @ ${sync.fromAddress} queue=${sync.snapshot.queue.length} index=${sync.snapshot.currentIndex} playing=${sync.snapshot.isPlaying}',
    );

    _linkedPeerAddress = sync.fromAddress;

    _applyIncomingSnapshot(sync);
  }

  void _onCommandIntent(ConnectCommandIntent intent) {
    if (!isHost) return;
    if (_linkedDeviceId == null || intent.fromDeviceId != _linkedDeviceId) {
      return;
    }

    logger.d(
      '[Handoff] Command intent from target ${intent.fromDeviceId}: ${intent.command} payload=${intent.payload}',
    );
    _linkedPeerAddress = intent.fromAddress;
    _issueHostCommand(intent.command, intent.payload);
  }

  void _onCommandApply(ConnectCommandApply apply) {
    if (!isTarget) return;
    if (_linkedDeviceId == null || apply.fromDeviceId != _linkedDeviceId) {
      return;
    }

    logger.d(
      '[Handoff] Command apply from host ${apply.fromDeviceId}: seq=${apply.sequence} cmd=${apply.command} payload=${apply.payload}',
    );
    _linkedPeerAddress = apply.fromAddress;
    _applyCommandAsTarget(apply);
  }

  void _onCommandAck(ConnectCommandAck ack) {
    if (!isHost) return;
    if (_linkedDeviceId == null || ack.fromDeviceId != _linkedDeviceId) {
      return;
    }

    logger.d(
      '[Handoff] Command ack from target ${ack.fromDeviceId}: seq=${ack.sequence} playing=${ack.isPlaying} posMs=${ack.positionMs}',
    );
    _linkedPeerAddress = ack.fromAddress;
    markCommandAcked(ack.sequence);
    _setLinkedPlaybackState(
      isPlaying: ack.isPlaying,
      position: Duration(milliseconds: ack.positionMs),
      notify: false,
    );
    if (ack.snapshot != null) {
      applyResolvedYoutubeIds(ack.snapshot!.resolvedYoutubeIds);
    }
    if (_phase == ConnectPhase.linkedSyncing) {
      _setPhase(ConnectPhase.linkedPlaying);
    } else {
      notifyListeners();
    }
  }

  void _onPlaybackPulse(ConnectPlaybackPulse pulse) {
    if (!isHost) return;
    if (_linkedDeviceId == null || pulse.fromDeviceId != _linkedDeviceId) {
      return;
    }

    _linkedPeerAddress = pulse.fromAddress;
    _setLinkedPlaybackState(
      isPlaying: pulse.isPlaying,
      position: Duration(milliseconds: pulse.positionMs),
    );
    if (_phase == ConnectPhase.linkedSyncing) {
      _setPhase(ConnectPhase.linkedPlaying);
    }
  }

  void _onUnlinkEvent(ConnectUnlinkEvent event) {
    if (_linkedDeviceId == null || event.fromDeviceId != _linkedDeviceId) {
      return;
    }

    final audio = _audioHandler;
    final resumePosition = audio?.throttledPosition ?? _linkedPosition;
    final resumePlaying = audio?.isPlaying ?? _linkedIsPlaying;

    logger.d(
      '[Handoff] Incoming unlink from ${event.fromDeviceId} @ ${event.fromAddress}; applying local disconnect.',
    );
    unlink(
      localResumed: true,
      resumePosition: resumePosition,
      resumePlaying: resumePlaying,
      notifyPeer: false,
    );
  }

  Future<void> _applyIncomingSnapshot(ConnectSnapshotSync sync) async {
    try {
      logger.d(
        '[Handoff] Applying incoming snapshot from ${sync.fromDeviceId}.',
      );
      markLinkedSyncingAsTarget(sync.fromDeviceId);
      applyResolvedYoutubeIds(sync.snapshot.resolvedYoutubeIds);

      final audioHandler = _audioHandler;
      if (audioHandler != null) {
        await audioHandler.applyConnectSnapshot(
          sync.snapshot,
          autoPlay: true,
          preserveVolume: true,
        );
      }

      markLinkedPlaying(
        isPlaying: sync.snapshot.isPlaying,
        position: Duration(milliseconds: sync.snapshot.positionMs),
      );
      _sendTargetPlaybackPulse();
    } catch (_) {
      setError('Failed to apply snapshot from host device.');
      logger.e('[Handoff] Failed to apply incoming snapshot.');
    }
  }

  void _ensureTargetPulseTimer() {
    _targetPulseTimer ??= Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) {
      _sendTargetPlaybackPulse();
    });
  }

  void _stopTargetPulseTimer() {
    _targetPulseTimer?.cancel();
    _targetPulseTimer = null;
  }

  void _ensureHostInterpolationTimer() {
    _hostInterpolationTimer ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        if (!isHost || !isLinked || !_linkedIsPlaying) {
          _stopHostInterpolationTimer();
          return;
        }
        notifyListeners();
      },
    );
  }

  void _stopHostInterpolationTimer() {
    _hostInterpolationTimer?.cancel();
    _hostInterpolationTimer = null;
  }

  void _sendTargetPlaybackPulse() {
    if (!isTarget) return;
    final peerAddress = _linkedPeerAddress ?? _pairingTargetAddress;
    if (peerAddress == null || peerAddress.isEmpty) return;

    final audio = _audioHandler;
    if (audio == null) return;

    final snapshot = audio.buildConnectSnapshot();
    _setLinkedPlaybackState(
      isPlaying: snapshot.isPlaying,
      position: Duration(milliseconds: snapshot.positionMs),
      notify: false,
    );

    _lanConnectService.sendPlaybackPulse(
      targetAddress: peerAddress,
      fromDeviceId: _localDeviceId,
      isPlaying: snapshot.isPlaying,
      positionMs: snapshot.positionMs,
    );
  }

  void _sendCurrentSnapshotToTarget(String? targetAddress) {
    final address = targetAddress ?? _pairingTargetAddress;
    final audioHandler = _audioHandler;
    if (address == null || address.isEmpty || audioHandler == null) {
      return;
    }

    final snapshot = audioHandler.buildConnectSnapshot();
    logger.d(
      '[Handoff] Sending snapshot to target=$address queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
    );
    applyResolvedYoutubeIds(snapshot.resolvedYoutubeIds);
    _lanConnectService.sendSnapshot(
      targetAddress: address,
      fromDeviceId: _localDeviceId,
      snapshot: snapshot,
    );

    markLinkedPlaying(
      isPlaying: snapshot.isPlaying,
      position: Duration(milliseconds: snapshot.positionMs),
    );
  }

  Future<void> _requestCommand(
    String command, {
    Map<String, dynamic> payload = const {},
  }) async {
    if (!isLinked) return;

    logger.d(
      '[Handoff] Request command role=$_role linked=$isLinked cmd=$command payload=$payload peer=$_linkedPeerAddress pairTarget=$_pairingTargetAddress',
    );

    if (isHost) {
      await _issueHostCommand(command, payload);
      return;
    }

    final peerAddress = _linkedPeerAddress;
    if (!isTarget || peerAddress == null || peerAddress.isEmpty) {
      return;
    }

    _lanConnectService.sendCommandIntent(
      targetAddress: peerAddress,
      fromDeviceId: _localDeviceId,
      command: command,
      payload: payload,
    );
  }

  Future<void> _issueHostCommand(
    String command,
    Map<String, dynamic> payload,
  ) async {
    if (!isHost) return;
    final peerAddress = _linkedPeerAddress ?? _pairingTargetAddress;
    if (peerAddress == null || peerAddress.isEmpty) return;

    final sequence = ++_hostCommandSequence;
    logger.d(
      '[Handoff] Host issue seq=$sequence cmd=$command payload=$payload target=$peerAddress',
    );
    markCommandApplied(sequence);
    _lanConnectService.sendCommandApply(
      targetAddress: peerAddress,
      fromDeviceId: _localDeviceId,
      sequence: sequence,
      command: command,
      payload: payload,
    );
  }

  Future<void> _executeCommandOnAudio(
    WispAudioHandler audio,
    String command,
    Map<String, dynamic> payload,
  ) async {
    switch (command) {
      case _cmdPlay:
        if (audio.currentTrack != null) {
          await audio.play();
        } else if (audio.queueTracks.isNotEmpty) {
          await audio.playTrack(audio.queueTracks.first);
        }
        break;
      case _cmdPause:
        await audio.pause();
        break;
      case _cmdSeek:
        final positionMs = (payload['position_ms'] as int?) ?? 0;
        await audio.seek(Duration(milliseconds: positionMs));
        break;
      case _cmdSkipNext:
        await audio.skipNext();
        break;
      case _cmdSkipPrevious:
        await audio.skipPrevious();
        break;
      case _cmdToggleShuffle:
        audio.toggleShuffle();
        break;
      case _cmdToggleRepeat:
        audio.toggleRepeat();
        break;
      default:
        break;
    }
  }

  Future<void> _pauseLocalPlaybackAsHost() async {
    final audio = _audioHandler;
    if (audio == null) return;

    try {
      if (!audio.isPlaying && !audio.isLoading && !audio.isBuffering) {
        return;
      }
      await audio.pause();
      logger.d(
        '[Handoff] Paused local controller playback after linking as host.',
      );
    } catch (_) {
      logger.w(
        '[Handoff] Failed to pause local controller playback after linking as host.',
      );
    }
  }

  Future<void> _applyCommandAsTarget(ConnectCommandApply apply) async {
    final audio = _audioHandler;
    if (audio == null) return;

    try {
      logger.d(
        '[Handoff] Target apply seq=${apply.sequence} cmd=${apply.command} payload=${apply.payload}',
      );
      await _executeCommandOnAudio(audio, apply.command, apply.payload);

      markCommandApplied(apply.sequence);
      final snapshot = audio.buildConnectSnapshot();
      logger.d(
        '[Handoff] Target ack seq=${apply.sequence} playing=${snapshot.isPlaying} posMs=${snapshot.positionMs} to=${apply.fromAddress}',
      );
      _lanConnectService.sendCommandAck(
        targetAddress: apply.fromAddress,
        fromDeviceId: _localDeviceId,
        sequence: apply.sequence,
        isPlaying: snapshot.isPlaying,
        positionMs: snapshot.positionMs,
        snapshot: snapshot,
      );
      markLinkedPlaying(
        isPlaying: snapshot.isPlaying,
        position: Duration(milliseconds: snapshot.positionMs),
      );
      _sendTargetPlaybackPulse();
    } catch (_) {
      setError('Failed to apply remote command.');
      logger.e(
        '[Handoff] Failed to apply remote command seq=${apply.sequence} cmd=${apply.command}',
      );
    }
  }

  @override
  void dispose() {
    _pruneTimer?.cancel();
    _deviceSubscription?.cancel();
    _pairRequestSubscription?.cancel();
    _pairResponseSubscription?.cancel();
    _snapshotSubscription?.cancel();
    _commandIntentSubscription?.cancel();
    _commandApplySubscription?.cancel();
    _commandAckSubscription?.cancel();
    _unlinkSubscription?.cancel();
    _playbackPulseSubscription?.cancel();
    _stopTargetPulseTimer();
    _stopHostInterpolationTimer();
    _lanConnectService.dispose();
    super.dispose();
  }
}
