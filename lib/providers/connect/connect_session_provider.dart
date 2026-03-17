import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/models/metadata_models.dart';
import 'package:wisp/services/connect/connect_models.dart';
import 'package:wisp/services/connect/lan_connect_service.dart';
import 'package:wisp/services/wisp_audio_handler.dart';
import 'package:wisp/utils/logger.dart';

class ConnectSessionProvider extends ChangeNotifier {
  static const String _keyLocalDeviceId = 'connect_local_device_id';
  static const String _keyTrustedIncomingDeviceIds =
      'connect_trusted_incoming_device_ids';
  static const String _keyPreferredModesByDevice =
      'connect_preferred_modes_by_device';
  static const String _cmdPlay = 'play';
  static const String _cmdPause = 'pause';
  static const String _cmdSeek = 'seek';
  static const String _cmdSkipNext = 'skip_next';
  static const String _cmdSkipPrevious = 'skip_previous';
  static const String _cmdToggleShuffle = 'toggle_shuffle';
  static const String _cmdToggleRepeat = 'toggle_repeat';
  static const String _cmdPlayQueueIndex = 'play_queue_index';
  static const String _cmdRemoveFromQueue = 'remove_from_queue';
  static const String _cmdClearQueue = 'clear_queue';
  static const String _cmdReorderQueue = 'reorder_queue';
  static const String _cmdRequestSnapshot = 'request_snapshot';
  static const String _cmdSetQueue = 'set_queue';

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

  ConnectLinkMode _activeLinkMode = ConnectLinkMode.fullHandoff;
  ConnectLinkMode get activeLinkMode => _activeLinkMode;
  bool get isControlOnlyLinked =>
      isLinked && _activeLinkMode == ConnectLinkMode.controlOnly;

  ConnectLinkMode _nextOutgoingLinkMode = ConnectLinkMode.fullHandoff;
  ConnectLinkMode get nextOutgoingLinkMode => _nextOutgoingLinkMode;

  bool _rememberModeForNextLink = false;
  bool get rememberModeForNextLink => _rememberModeForNextLink;

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
  String? _lastTargetSnapshotTrackId;
  int _lastTargetSnapshotIndex = -1;
  DateTime? _lastTargetSnapshotSentAt;
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
  SharedPreferences? _prefs;
  final Set<String> _trustedIncomingDeviceIds = <String>{};
  final Map<String, ConnectLinkMode> _preferredModesByDevice =
      <String, ConnectLinkMode>{};
  String? _pendingTrustPromptDeviceId;
  String? _pendingTrustPromptDeviceName;
  String? get pendingTrustPromptDeviceId => _pendingTrustPromptDeviceId;
  String? get pendingTrustPromptDeviceName => _pendingTrustPromptDeviceName;
  bool get hasPendingTrustPrompt =>
      _pendingTrustPromptDeviceId != null &&
      _pendingTrustPromptDeviceName != null;

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
    _prefs = prefs;
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

    final trustedIds = prefs.getStringList(_keyTrustedIncomingDeviceIds);
    if (trustedIds != null) {
      _trustedIncomingDeviceIds
        ..clear()
        ..addAll(trustedIds.where((id) => id.trim().isNotEmpty));
    }

    final preferredJson = prefs.getString(_keyPreferredModesByDevice);
    if (preferredJson != null && preferredJson.isNotEmpty) {
      try {
        final decoded = json.decode(preferredJson) as Map<String, dynamic>;
        _preferredModesByDevice
          ..clear()
          ..addEntries(
            decoded.entries.map(
              (entry) => MapEntry(
                entry.key,
                ConnectLinkModeJson.fromJson(entry.value as String?),
              ),
            ),
          );
      } catch (_) {
        _preferredModesByDevice.clear();
      }
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

  Future<void> requestPlayQueueIndex(int index) async {
    final audio = _audioHandler;
    if (audio == null) return;

    if (!isLinked) {
      if (index < 0 || index >= audio.queueTracks.length) return;
      await audio.playTrack(audio.queueTracks[index], addToQueue: false);
      return;
    }

    await _requestCommand(_cmdPlayQueueIndex, payload: {'index': index});
  }

  Future<void> requestRemoveFromQueue(int index) async {
    final audio = _audioHandler;
    if (audio == null) return;

    if (!isLinked) {
      audio.removeFromQueue(index);
      return;
    }

    await _requestCommand(_cmdRemoveFromQueue, payload: {'index': index});
  }

  Future<void> requestClearQueue() async {
    final audio = _audioHandler;
    if (audio == null) return;

    if (!isLinked) {
      audio.clearQueue();
      return;
    }

    await _requestCommand(_cmdClearQueue);
  }

  Future<void> requestReorderQueue(int oldIndex, int newIndex) async {
    final audio = _audioHandler;
    if (audio == null) return;

    if (!isLinked) {
      audio.reorderQueue(oldIndex, newIndex);
      return;
    }

    await _requestCommand(
      _cmdReorderQueue,
      payload: {'old_index': oldIndex, 'new_index': newIndex},
    );
  }

  Future<void> requestSetQueue(
    List<GenericSong> tracks, {
    int startIndex = 0,
    bool play = true,
    String? contextType,
    String? contextName,
    String? contextID,
    SongSource? contextSource,
    bool shuffleEnabled = false,
    List<GenericSong>? originalQueue,
  }) async {
    final audio = _audioHandler;
    if (audio == null) return;

    if (!isLinked) {
      await audio.setQueue(
        tracks,
        startIndex: startIndex,
        play: play,
        contextType: contextType,
        contextName: contextName,
        contextID: contextID,
        contextSource: contextSource,
        shuffleEnabled: shuffleEnabled,
        originalQueue: originalQueue,
      );
      return;
    }

    await _requestCommand(
      _cmdSetQueue,
      payload: {
        'tracks': tracks.map((t) => t.toJson()).toList(growable: false),
        'start_index': startIndex,
        'play': play,
        'context_type': contextType,
        'context_name': contextName,
        'context_id': contextID,
        'context_source': contextSource?.toJson(),
        'shuffle_enabled': shuffleEnabled,
        'original_queue': originalQueue
            ?.map((t) => t.toJson())
            .toList(growable: false),
      },
    );
  }

  void setNextOutgoingLinkMode(ConnectLinkMode mode) {
    if (_nextOutgoingLinkMode == mode) return;
    _nextOutgoingLinkMode = mode;
    notifyListeners();
  }

  void setRememberModeForNextLink(bool remember) {
    if (_rememberModeForNextLink == remember) return;
    _rememberModeForNextLink = remember;
    notifyListeners();
  }

  ConnectLinkMode preferredModeForDevice(String deviceId) {
    return _preferredModesByDevice[deviceId] ?? ConnectLinkMode.fullHandoff;
  }

  bool isTrustedIncomingDevice(String deviceId) {
    return _trustedIncomingDeviceIds.contains(deviceId);
  }

  Future<void> setTrustedIncomingDevice(
    String deviceId, {
    required bool trusted,
  }) async {
    if (deviceId.trim().isEmpty) return;
    if (trusted) {
      _trustedIncomingDeviceIds.add(deviceId);
    } else {
      _trustedIncomingDeviceIds.remove(deviceId);
    }
    await _prefs?.setStringList(
      _keyTrustedIncomingDeviceIds,
      _trustedIncomingDeviceIds.toList(growable: false),
    );
    notifyListeners();
  }

  Future<void> trustPendingIncomingDevice() async {
    final deviceId = _pendingTrustPromptDeviceId;
    if (deviceId == null) return;
    await setTrustedIncomingDevice(deviceId, trusted: true);
    clearPendingTrustPrompt();
  }

  void clearPendingTrustPrompt() {
    if (_pendingTrustPromptDeviceId == null &&
        _pendingTrustPromptDeviceName == null) {
      return;
    }
    _pendingTrustPromptDeviceId = null;
    _pendingTrustPromptDeviceName = null;
    notifyListeners();
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

  void beginPairing(
    String deviceId, {
    ConnectLinkMode? mode,
    bool? rememberForDevice,
  }) {
    final target = _discoveredById[deviceId];
    if (target == null) {
      setError('Target device is no longer available.');
      return;
    }

    final selectedMode = mode ?? preferredModeForDevice(deviceId);
    final shouldRemember = rememberForDevice ?? _rememberModeForNextLink;
    if (shouldRemember) {
      _preferredModesByDevice[deviceId] = selectedMode;
      unawaited(_persistPreferredModesByDevice());
    }

    _clearError();
    _pairingTargetDeviceId = deviceId;
    _pairingTargetAddress = target.address;
    _setPhase(ConnectPhase.pairing);
    logger.d(
      '[Handoff] Begin pairing targetId=$deviceId targetName=${target.name} targetAddress=${target.address} mode=${selectedMode.toJson()}',
    );

    _lanConnectService.requestPair(
      target: target,
      fromDeviceId: _localDeviceId,
      fromDeviceName: _localDeviceName,
      fromPlatform: localPlatform,
      mode: selectedMode,
    );
  }

  void acceptIncomingPair() {
    final request = _pendingPairRequest;
    if (request == null) return;
    _acceptIncomingPairRequest(request, manual: true);
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
      mode: request.requestedMode,
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
    _activeLinkMode = ConnectLinkMode.fullHandoff;
    _pendingPairRequest = null;
    _linkedPosition = resumePosition;
    _linkedIsPlaying = resumePlaying;
    _linkedPositionUpdatedAt = DateTime.now();
    _lastAppliedSequence = -1;
    _lastAckedSequence = -1;
    _lastTargetSnapshotTrackId = null;
    _lastTargetSnapshotIndex = -1;
    _lastTargetSnapshotSentAt = null;
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
    _activeLinkMode = ConnectLinkMode.fullHandoff;
    _lastTargetSnapshotTrackId = null;
    _lastTargetSnapshotIndex = -1;
    _lastTargetSnapshotSentAt = null;
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
      '[Handoff] Incoming pair request from ${request.fromDeviceName} (${request.fromDeviceId}) @ ${request.fromAddress} mode=${request.requestedMode.toJson()}',
    );

    if (isTrustedIncomingDevice(request.fromDeviceId)) {
      logger.d(
        '[Handoff] Auto-accept incoming pair from trusted device=${request.fromDeviceId}',
      );
      _acceptIncomingPairRequest(request, manual: false);
      return;
    }

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
        '[Handoff] Pair accepted by ${response.fromDeviceName} (${response.fromDeviceId}) @ ${response.fromAddress} mode=${response.linkMode.toJson()}',
      );
      _activeLinkMode = response.linkMode;
      markLinkedSyncingAsHost(response.fromDeviceId);
      _pairingTargetAddress = response.fromAddress;
      _linkedPeerAddress = response.fromAddress;
      if (response.linkMode == ConnectLinkMode.fullHandoff) {
        _sendCurrentSnapshotToTarget(response.fromAddress);
      } else {
        unawaited(_requestCommand(_cmdRequestSnapshot));
      }
      unawaited(_pauseLocalPlaybackAsHost());
    } else {
      logger.d(
        '[Handoff] Pair rejected by ${response.fromDeviceName} (${response.fromDeviceId})',
      );
      _linkedDeviceId = null;
      _activeLinkMode = ConnectLinkMode.fullHandoff;
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
    if (isHost) {
      unawaited(_applyIncomingSnapshotAsHost(sync));
      return;
    }

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
      if (isHost && _activeLinkMode == ConnectLinkMode.controlOnly) {
        unawaited(
          _applyIncomingSnapshotAsHost(
            ConnectSnapshotSync(
              fromDeviceId: ack.fromDeviceId,
              fromAddress: ack.fromAddress,
              snapshot: ack.snapshot!,
            ),
          ),
        );
      } else {
        applyResolvedYoutubeIds(ack.snapshot!.resolvedYoutubeIds);
      }
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

  Future<void> _applyIncomingSnapshotAsHost(ConnectSnapshotSync sync) async {
    final audioHandler = _audioHandler;
    if (audioHandler != null) {
      try {
        await audioHandler.applyConnectSnapshot(
          sync.snapshot,
          autoPlay: false,
          preserveVolume: true,
        );
      } catch (_) {}
    }

    applyResolvedYoutubeIds(sync.snapshot.resolvedYoutubeIds);
    markLinkedPlaying(
      isPlaying: sync.snapshot.isPlaying,
      position: Duration(milliseconds: sync.snapshot.positionMs),
    );
    unawaited(_pauseLocalPlaybackAsHost());
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

    final currentTrackId = audio.currentTrack?.id;
    final currentIndex = audio.currentIndex;
    final now = DateTime.now();
    final shouldSendSnapshot =
        currentTrackId != _lastTargetSnapshotTrackId ||
        currentIndex != _lastTargetSnapshotIndex ||
        _lastTargetSnapshotSentAt == null ||
        now.difference(_lastTargetSnapshotSentAt!).inSeconds >= 2;
    if (shouldSendSnapshot) {
      _lastTargetSnapshotTrackId = currentTrackId;
      _lastTargetSnapshotIndex = currentIndex;
      _lastTargetSnapshotSentAt = now;
      _sendCurrentSnapshotToHost(peerAddress);
    }
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
      case _cmdPlayQueueIndex:
        final index = (payload['index'] as int?) ?? -1;
        if (index >= 0 && index < audio.queueTracks.length) {
          await audio.playTrack(audio.queueTracks[index], addToQueue: false);
        }
        break;
      case _cmdRemoveFromQueue:
        final index = (payload['index'] as int?) ?? -1;
        audio.removeFromQueue(index);
        break;
      case _cmdClearQueue:
        audio.clearQueue();
        break;
      case _cmdReorderQueue:
        final oldIndex = (payload['old_index'] as int?) ?? -1;
        final newIndex = (payload['new_index'] as int?) ?? -1;
        if (oldIndex >= 0 && newIndex >= 0) {
          audio.reorderQueue(oldIndex, newIndex);
        }
        break;
      case _cmdSetQueue:
        final tracksJson =
            (payload['tracks'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .toList(growable: false);
        final tracks = tracksJson.map(GenericSong.fromJson).toList();
        final originalQueueJson =
            (payload['original_queue'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .toList(growable: false);
        final originalQueue = originalQueueJson
            .map(GenericSong.fromJson)
            .toList();
        await audio.setQueue(
          tracks,
          startIndex: (payload['start_index'] as int?) ?? 0,
          play: (payload['play'] as bool?) ?? true,
          contextType: payload['context_type'] as String?,
          contextName: payload['context_name'] as String?,
          contextID: payload['context_id'] as String?,
          contextSource: SongSource.fromJson(
            payload['context_source'] as String? ?? SongSource.spotify.toJson(),
          ),
          shuffleEnabled: (payload['shuffle_enabled'] as bool?) ?? false,
          originalQueue: originalQueue.isEmpty ? null : originalQueue,
        );
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
      if (apply.command == _cmdRequestSnapshot) {
        final snapshot = audio.buildConnectSnapshot();
        _lanConnectService.sendCommandAck(
          targetAddress: apply.fromAddress,
          fromDeviceId: _localDeviceId,
          sequence: apply.sequence,
          isPlaying: snapshot.isPlaying,
          positionMs: snapshot.positionMs,
          snapshot: snapshot,
        );
        _lanConnectService.sendSnapshot(
          targetAddress: apply.fromAddress,
          fromDeviceId: _localDeviceId,
          snapshot: snapshot,
        );
        markLinkedPlaying(
          isPlaying: snapshot.isPlaying,
          position: Duration(milliseconds: snapshot.positionMs),
        );
        return;
      }

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

  void _acceptIncomingPairRequest(
    ConnectPairRequest request, {
    required bool manual,
  }) {
    _activeLinkMode = request.requestedMode;
    _lanConnectService.respondPair(
      targetAddress: request.fromAddress,
      accepted: true,
      localDeviceId: _localDeviceId,
      localDeviceName: _localDeviceName,
      localPlatform: localPlatform,
      mode: request.requestedMode,
    );
    markLinkedSyncingAsTarget(request.fromDeviceId);
    _pairingTargetAddress = request.fromAddress;
    _linkedPeerAddress = request.fromAddress;
    logger.d(
      '[Handoff] Accepted incoming pair from ${request.fromDeviceName} (${request.fromDeviceId}) @ ${request.fromAddress} mode=${request.requestedMode.toJson()} manual=$manual',
    );
    _pendingPairRequest = null;

    if (request.requestedMode == ConnectLinkMode.controlOnly) {
      _sendCurrentSnapshotToHost(request.fromAddress);
    }

    if (manual && !isTrustedIncomingDevice(request.fromDeviceId)) {
      _pendingTrustPromptDeviceId = request.fromDeviceId;
      _pendingTrustPromptDeviceName = request.fromDeviceName;
    }
    notifyListeners();
  }

  void _sendCurrentSnapshotToHost(String targetAddress) {
    final audioHandler = _audioHandler;
    if (audioHandler == null) {
      return;
    }
    final snapshot = audioHandler.buildConnectSnapshot();
    _lanConnectService.sendSnapshot(
      targetAddress: targetAddress,
      fromDeviceId: _localDeviceId,
      snapshot: snapshot,
    );
    markLinkedPlaying(
      isPlaying: snapshot.isPlaying,
      position: Duration(milliseconds: snapshot.positionMs),
    );
  }

  Future<void> _persistPreferredModesByDevice() async {
    final serialized = <String, String>{
      for (final entry in _preferredModesByDevice.entries)
        entry.key: entry.value.toJson(),
    };
    await _prefs?.setString(
      _keyPreferredModesByDevice,
      json.encode(serialized),
    );
    notifyListeners();
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
