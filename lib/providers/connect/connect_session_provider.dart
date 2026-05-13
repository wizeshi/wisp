import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/models/metadata_models.dart';
import 'package:wisp/providers/preferences/preferences_provider.dart';
import 'package:wisp/services/connect/connect_packet_models.dart';
import 'package:wisp/services/playback/audio_command_applier.dart';
import 'package:wisp/services/playback/playback_coordinator.dart';
import 'package:wisp/services/playback/playback_transport.dart';
import 'package:wisp/services/connect/connect_models.dart';
import 'package:wisp/services/connect/lan_connect_service.dart';
import 'package:wisp/services/connect/connect_transport.dart';
import 'package:wisp/services/wisp_audio_handler.dart';
import 'package:wisp/utils/logger.dart';

// Structured error codes so the UI can react without brittle string matching.
// Add new codes here as needed.
enum ConnectErrorCode { generic, securityLevelTooLow }

class ConnectSessionProvider extends ChangeNotifier
    implements PlaybackTransport {
  static const String _keyLocalDeviceId = 'connect_local_device_id';
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
  ConnectErrorCode? _errorCode;
  ConnectErrorCode? get errorCode => _errorCode;

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

  String? _linkedPeerName;
  String? get linkedPeerName => _linkedPeerName;

  String? _linkedPeerAddress;
  String? get linkedPeerAddress => _linkedPeerAddress;

  int _lastAppliedSequence = -1;
  int get lastAppliedSequence => _lastAppliedSequence;

  int _lastAckedSequence = -1;
  int get lastAckedSequence => _lastAckedSequence;

  int _nextPositionPulseSeq = 0;

  Duration _linkedPosition = Duration.zero;
  Duration get linkedPosition => _linkedPosition;
  @override
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
  @override
  bool get linkedIsPlaying => _linkedIsPlaying;

  ConnectLinkMode _activeLinkMode = ConnectLinkMode.fullHandoff;
  ConnectLinkMode get activeLinkMode => _activeLinkMode;
  bool get isControlOnlyLinked =>
      isLinked && _activeLinkMode == ConnectLinkMode.controlOnly;

  ConnectLinkMode _nextOutgoingLinkMode = ConnectLinkMode.fullHandoff;
  ConnectLinkMode get nextOutgoingLinkMode => _nextOutgoingLinkMode;

  ConnectOutputKind _activeOutputKind = ConnectOutputKind.local;
  ConnectOutputKind get activeOutputKind => _activeOutputKind;

  String? _activeOutputDeviceName;
  String? get activeOutputDeviceName => _activeOutputDeviceName;

  List<ConnectOutputDevice> _availableOutputDevices = const [];
  List<ConnectOutputDevice> get availableOutputDevices =>
      List.unmodifiable(_availableOutputDevices);

  ConnectOutputKind? _manualOutputKind;
  String? _manualOutputDeviceName;

  bool get hasExternalOutput => _activeOutputKind.isExternal;

  bool _rememberModeForNextLink = false;
  bool get rememberModeForNextLink => _rememberModeForNextLink;

  Map<String, String> _sessionResolvedYoutubeIds = {};
  Map<String, String> get sessionResolvedYoutubeIds =>
      Map.unmodifiable(_sessionResolvedYoutubeIds);

  late final ConnectTransport _transport;
  final AudioCommandApplier _audioCommandApplier = const AudioCommandApplier();
  Future<void>? _initFuture;
  StreamSubscription<ConnectDevice>? _deviceSubscription;
  StreamSubscription<ConnectPairRequest>? _pairRequestSubscription;
  Timer? _pairingTimeoutTimer;
  StreamSubscription<ConnectPairResponse>? _pairResponseSubscription;
  StreamSubscription<ConnectSnapshotSync>? _snapshotSubscription;
  StreamSubscription<ConnectStateDeltaSync>? _stateDeltaSubscription;
  StreamSubscription<ConnectPositionPulseSync>? _positionPulseSubscription;
  StreamSubscription<ConnectCommandIntent>? _commandIntentSubscription;
  StreamSubscription<ConnectCommandApply>? _commandApplySubscription;
  StreamSubscription<ConnectCommandAck>? _commandAckSubscription;
  StreamSubscription<ConnectUnlinkEvent>? _unlinkSubscription;
  // legacy playback pulse subscription removed
  StreamSubscription<Set<AudioDevice>>? _audioDevicesSubscription;
  Timer? _pruneTimer;
  Timer? _targetPulseTimer;
  Timer? _hostInterpolationTimer;
  String? _lastTargetSnapshotTrackId;
  int _lastTargetSnapshotIndex = -1;
  DateTime? _lastTargetSnapshotSentAt;
  int _lastHostDeltaSeq = -1;
  int _lastHostDeltaTs = -1;
  int? _lastHostSnapshotAckSequence;
  int _lastHostSnapshotFingerprint = -1;
  DateTime? _lastHostSnapshotAppliedAt;
  DateTime? _linkedPositionUpdatedAt;
  ConnectPairRequest? _pendingPairRequest;
  ConnectPairRequest? get pendingPairRequest => _pendingPairRequest;
  String? get pairingTargetDeviceId => _pairingTargetDeviceId;
  String? _pairingTargetDeviceId;
  String? _pairingTargetAddress;
  String? _lastRejectedPairingTargetDeviceId;
  int _hostCommandSequence = 0;
  WispAudioHandler? _audioHandler;
  PlaybackCoordinator? _playbackCoordinator;
  bool _discoveryStarted = false;
  bool get discoveryStarted => _discoveryStarted;
  SharedPreferences? _prefs;
  final Map<String, ConnectLinkMode> _preferredModesByDevice =
      <String, ConnectLinkMode>{};
    PreferencesProvider? _preferences;
  String? _pendingTrustPromptDeviceId;
  String? _pendingTrustPromptDeviceName;
    String? _pendingTrustPromptDevicePlatform;
    String? _pendingSecurityWarningMessage;
  String? get pendingTrustPromptDeviceId => _pendingTrustPromptDeviceId;
  String? get pendingTrustPromptDeviceName => _pendingTrustPromptDeviceName;
    String? get pendingTrustPromptDevicePlatform =>
      _pendingTrustPromptDevicePlatform;
    String? get pendingSecurityWarningMessage => _pendingSecurityWarningMessage;
    bool get hasPendingSecurityWarning => _pendingSecurityWarningMessage != null;
  String? get lastRejectedPairingTargetDeviceId =>
      _lastRejectedPairingTargetDeviceId;
  bool get hasPendingTrustPrompt =>
      _pendingTrustPromptDeviceId != null &&
      _pendingTrustPromptDeviceName != null;

  Future<void>? _discoveryStartFuture;

  ConnectSessionProvider({
    PreferencesProvider? preferences,
    ConnectTransport? transport,
  }) {
    _preferences = preferences;
    _transport = transport ?? LanConnectService();
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

  void bindPreferencesProvider(PreferencesProvider preferences) {
    if (identical(_preferences, preferences)) {
      return;
    }
    _preferences = preferences;
    notifyListeners();
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
    await _startOutputRouteMonitoring();
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

  @override
  bool get isLinked => _linkedDeviceId != null;

  @override
  bool get isHost => _role == ConnectRole.host;

  @override
  bool get isTarget => _role == ConnectRole.target;
  String get localPlatform => Platform.operatingSystem;

  void bindAudioHandler(WispAudioHandler audioHandler) {
    _audioHandler = audioHandler;
  }

  void bindPlaybackCoordinator(PlaybackCoordinator playbackCoordinator) {
    _playbackCoordinator = playbackCoordinator;
    playbackCoordinator.bindTransport(this);
  }

  Future<void> requestPlay() async {
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.play();
      return;
    }

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
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.pause();
      return;
    }

    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      await audio.pause();
      return;
    }

    await _requestCommand(_cmdPause);
  }

  Future<void> requestSeek(Duration position) async {
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.seek(position);
      return;
    }

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
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.skipNext();
      return;
    }

    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      await audio.skipNext();
      return;
    }

    await _requestCommand(_cmdSkipNext);
  }

  Future<void> requestSkipPrevious() async {
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.skipPrevious();
      return;
    }

    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      await audio.skipPrevious();
      return;
    }

    await _requestCommand(_cmdSkipPrevious);
  }

  Future<void> requestToggleShuffle() async {
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.toggleShuffle();
      return;
    }

    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      audio.toggleShuffle();
      return;
    }

    await _requestCommand(_cmdToggleShuffle);
  }

  Future<void> requestToggleRepeat() async {
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.toggleRepeat();
      return;
    }

    final audio = _audioHandler;
    if (audio == null) return;
    if (!isLinked) {
      audio.toggleRepeat();
      return;
    }

    await _requestCommand(_cmdToggleRepeat);
  }

  Future<void> requestPlayQueueIndex(int index) async {
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.playQueueIndex(index);
      return;
    }

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
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.removeFromQueue(index);
      return;
    }

    final audio = _audioHandler;
    if (audio == null) return;

    if (!isLinked) {
      audio.removeFromQueue(index);
      return;
    }

    await _requestCommand(_cmdRemoveFromQueue, payload: {'index': index});
  }

  Future<void> requestClearQueue() async {
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.clearQueue();
      return;
    }

    final audio = _audioHandler;
    if (audio == null) return;

    if (!isLinked) {
      audio.clearQueue();
      return;
    }

    await _requestCommand(_cmdClearQueue);
  }

  Future<void> requestReorderQueue(int oldIndex, int newIndex) async {
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.reorderQueue(oldIndex, newIndex);
      return;
    }

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
    final coordinator = _playbackCoordinator;
    if (coordinator != null) {
      await coordinator.setQueue(
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

  Future<void> _sendLinkedCommand(
    String command, {
    Map<String, dynamic> payload = const {},
  }) async {
    if (!isLinked) return;
    await _requestCommand(command, payload: payload);
  }

  @override
  Future<void> sendPlayCommand() => _sendLinkedCommand(_cmdPlay);

  @override
  Future<void> sendPauseCommand() => _sendLinkedCommand(_cmdPause);

  @override
  Future<void> sendSeekCommand(Duration position) => _sendLinkedCommand(
    _cmdSeek,
    payload: {'position_ms': position.inMilliseconds},
  );

  @override
  Future<void> sendSkipNextCommand() => _sendLinkedCommand(_cmdSkipNext);

  @override
  Future<void> sendSkipPreviousCommand() =>
      _sendLinkedCommand(_cmdSkipPrevious);

  @override
  Future<void> sendToggleShuffleCommand() =>
      _sendLinkedCommand(_cmdToggleShuffle);

  @override
  Future<void> sendToggleRepeatCommand() =>
      _sendLinkedCommand(_cmdToggleRepeat);

  @override
  Future<void> sendPlayQueueIndexCommand(int index) =>
      _sendLinkedCommand(_cmdPlayQueueIndex, payload: {'index': index});

  @override
  Future<void> sendRemoveFromQueueCommand(int index) =>
      _sendLinkedCommand(_cmdRemoveFromQueue, payload: {'index': index});

  @override
  Future<void> sendClearQueueCommand() => _sendLinkedCommand(_cmdClearQueue);

  @override
  Future<void> sendReorderQueueCommand(int oldIndex, int newIndex) =>
      _sendLinkedCommand(
        _cmdReorderQueue,
        payload: {'old_index': oldIndex, 'new_index': newIndex},
      );

  @override
  Future<void> sendSetQueueCommand(
    List<GenericSong> tracks, {
    int startIndex = 0,
    bool play = true,
    String? contextType,
    String? contextName,
    String? contextID,
    SongSource? contextSource,
    bool shuffleEnabled = false,
    List<GenericSong>? originalQueue,
  }) => _sendLinkedCommand(
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

  void setNextOutgoingLinkMode(ConnectLinkMode mode) {
    if (_nextOutgoingLinkMode == mode) return;
    _nextOutgoingLinkMode = mode;
    notifyListeners();
  }

  void setActiveOutputDestination(
    ConnectOutputKind kind, {
    String? deviceName,
  }) {
    final nextName = kind == ConnectOutputKind.local ? null : deviceName;
    if (_activeOutputKind == kind && _activeOutputDeviceName == nextName) {
      return;
    }
    _activeOutputKind = kind;
    _activeOutputDeviceName = nextName;
    if (!isLinked) {
      _manualOutputKind = kind;
      _manualOutputDeviceName = nextName;
    }
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

  HandoffSecurityLevel get _localSecurityLevel {
    return _preferences?.handoffSecurityLevel ??
        HandoffSecurityLevel.keyExchange;
  }

  bool isTrustedIncomingDevice(String deviceId) {
    final trustedDevices = _preferences?.trustedDevices ?? const <TrustedDevice>[];
    return trustedDevices.any((device) => device.id == deviceId);
  }

  Future<void> setTrustedIncomingDevice(
    String deviceId, {
    required bool trusted,
    String? name,
    String? platform,
  }) async {
    if (deviceId.trim().isEmpty) return;
    final preferences = _preferences;
    if (preferences == null) {
      return;
    }
    if (trusted) {
      await preferences.upsertTrustedDevice(
        TrustedDevice(
          id: deviceId,
          name: name ?? deviceId,
          platform: platform ?? 'unknown',
          trustedAt: DateTime.now(),
          lastConnectionAt: DateTime.now(),
        ),
      );
    } else {
      await preferences.forgetTrustedDevice(deviceId);
    }
    notifyListeners();
  }

  Future<void> trustPendingIncomingDevice() async {
    final deviceId = _pendingTrustPromptDeviceId;
    if (deviceId == null) return;
    await setTrustedIncomingDevice(
      deviceId,
      trusted: true,
      name: _pendingTrustPromptDeviceName,
      platform: _pendingTrustPromptDevicePlatform,
    );
    clearPendingTrustPrompt();
  }

  void clearPendingTrustPrompt() {
    if (_pendingTrustPromptDeviceId == null &&
        _pendingTrustPromptDeviceName == null) {
      return;
    }
    _pendingTrustPromptDeviceId = null;
    _pendingTrustPromptDeviceName = null;
    _pendingTrustPromptDevicePlatform = null;
    notifyListeners();
  }

  void clearPendingSecurityWarning() {
    if (_pendingSecurityWarningMessage == null) {
      return;
    }
    _pendingSecurityWarningMessage = null;
    notifyListeners();
  }

  Future<void> retryRejectedPairingWithLowerSecurity() async {
    final targetDeviceId = _lastRejectedPairingTargetDeviceId;
    if (targetDeviceId == null) {
      return;
    }
    if (!_discoveredById.containsKey(targetDeviceId)) {
      setError('Target device is no longer available.');
      return;
    }

    final preferences = _preferences;
    if (preferences != null) {
      await preferences.setHandoffSecurityLevel(
        HandoffSecurityLevel.keyExchange,
      );
    }

    beginPairing(
      targetDeviceId,
      mode: preferredModeForDevice(targetDeviceId),
      rememberForDevice: _rememberModeForNextLink,
    );
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

  void refreshOutputDevices() {
    unawaited(_refreshOutputDevicesInternal());
  }

  void refreshConnectMenuData() {
    refreshDiscovery();
    refreshOutputDevices();
  }

  void upsertDiscoveredDevice(ConnectDevice device) {
    _discoveredById[device.id] = device;
    if (_linkedDeviceId == device.id) {
      _linkedPeerName = device.name;
      _linkedPeerAddress = device.address ?? _linkedPeerAddress;
    }
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

    _transport.requestPair(
      target: target,
      fromDeviceId: _localDeviceId,
      fromDeviceName: _localDeviceName,
      fromPlatform: localPlatform,
      mode: selectedMode,
      securityLevel: _localSecurityLevel,
    );

    // Start a 15s timeout for the pairing request; if no response, cancel.
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = Timer(const Duration(seconds: 15), () {
      logger.d('[Handoff] Pairing request timed out for device=$deviceId');
      // Cancel pairing locally and return to idle.
      _pairingTimeoutTimer?.cancel();
      _pairingTimeoutTimer = null;
      _pairingTargetDeviceId = null;
      _pairingTargetAddress = null;
      _linkedPeerName = null;
      _setPhase(ConnectPhase.idle);
      notifyListeners();
    });
  }

  /// Cancel an in-flight pairing request initiated by this device.
  void cancelPairing({bool notifyRemote = true}) {
    if (_pairingTargetDeviceId == null && _pairingTargetAddress == null) {
      return;
    }

    final address = _pairingTargetAddress;
    // Optionally notify the remote device that we cancelled the request.
    if (notifyRemote && address != null && address.isNotEmpty) {
      try {
        _transport.respondPair(
          targetAddress: address,
          accepted: false,
          localDeviceId: _localDeviceId,
          localDeviceName: _localDeviceName,
          localPlatform: localPlatform,
          mode: ConnectLinkMode.fullHandoff,
          rejectionReason: 'cancelled',
        );
      } catch (_) {}
    }

    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _pairingTargetDeviceId = null;
    _pairingTargetAddress = null;
    _linkedPeerName = null;
    _setPhase(ConnectPhase.idle);
    notifyListeners();
  }

  void acceptIncomingPair() {
    final request = _pendingPairRequest;
    if (request == null) return;
    _acceptIncomingPairRequest(request, manual: true);
  }

  void rejectIncomingPair() {
    final request = _pendingPairRequest;
    if (request == null) return;

    _transport.respondPair(
      targetAddress: request.fromAddress,
      accepted: false,
      localDeviceId: _localDeviceId,
      localDeviceName: _localDeviceName,
      localPlatform: localPlatform,
      mode: request.requestedMode,
      rejectionReason: '', // User declined (not a security issue)
    );
    _pendingPairRequest = null;
    _pendingSecurityWarningMessage = null;
    _pairingTargetAddress = null;
    _linkedPeerAddress = null;
    _linkedPeerName = null;
    _pairingTargetDeviceId = null;
    logger.d('[Handoff] Rejected incoming pair request.');
    if (_phase == ConnectPhase.pairing) {
      _setPhase(ConnectPhase.idle);
    } else {
      notifyListeners();
    }
  }

  void markLinkedSyncingAsHost(String targetDeviceId, String targetDeviceName) {
    _role = ConnectRole.host;
    _linkedDeviceId = targetDeviceId;
    _linkedPeerName = targetDeviceName;
    logger.d('[Handoff] Role=host linkedDeviceId=$targetDeviceId');
    _stopTargetPulseTimer();
    _clearError();
    _syncLinkedOutputDestination();
    _audioHandler?.setIsHandoffHost(true);
    _setPhase(ConnectPhase.linkedSyncing);
  }

  void markLinkedSyncingAsTarget(String hostDeviceId, String hostDeviceName) {
    _role = ConnectRole.target;
    _linkedDeviceId = hostDeviceId;
    _linkedPeerName = hostDeviceName;
    logger.d('[Handoff] Role=target linkedDeviceId=$hostDeviceId');
    _ensureTargetPulseTimer();
    _clearError();
    _syncLinkedOutputDestination();
    _audioHandler?.setIsHandoffHost(false);
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
      _transport.sendUnlink(
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
    _audioHandler?.setIsHandoffHost(false);
    _setPhase(ConnectPhase.unlinking);
    _linkedDeviceId = null;
    _linkedPeerName = null;
    _role = ConnectRole.none;
    _pairingTargetDeviceId = null;
    _pairingTargetAddress = null;
    _linkedPeerAddress = null;
    _activeLinkMode = ConnectLinkMode.fullHandoff;
    _pendingPairRequest = null;
    _linkedPosition = resumePosition;
    _linkedIsPlaying = resumePlaying;
    _linkedPositionUpdatedAt = DateTime.now();
    if (!isLinked) {
      _activeOutputKind = ConnectOutputKind.local;
      _activeOutputDeviceName = null;
      _manualOutputKind = null;
      _manualOutputDeviceName = null;
    }
    _lastAppliedSequence = -1;
    _lastAckedSequence = -1;
    _lastTargetSnapshotTrackId = null;
    _lastTargetSnapshotIndex = -1;
    _lastTargetSnapshotSentAt = null;
    _lastHostDeltaSeq = -1;
    _lastHostDeltaTs = -1;
    _lastHostSnapshotAckSequence = null;
    _lastHostSnapshotFingerprint = -1;
    _lastHostSnapshotAppliedAt = null;
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
    _linkedPeerName = null;
    _activeLinkMode = ConnectLinkMode.fullHandoff;
    _lastTargetSnapshotTrackId = null;
    _lastTargetSnapshotIndex = -1;
    _lastTargetSnapshotSentAt = null;
    _lastHostDeltaSeq = -1;
    _lastHostDeltaTs = -1;
    _lastHostSnapshotAckSequence = null;
    _lastHostSnapshotFingerprint = -1;
    _lastHostSnapshotAppliedAt = null;
    _clearError();
    _stopTargetPulseTimer();
    _stopHostInterpolationTimer();
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _activeOutputKind = ConnectOutputKind.local;
    _activeOutputDeviceName = null;
    _activeOutputKind = ConnectOutputKind.local;
    _activeOutputDeviceName = null;
    _manualOutputKind = null;
    _manualOutputDeviceName = null;
    notifyListeners();
  }

  void setError(String message, [ConnectErrorCode? code]) {
    _errorMessage = message;
    _errorCode = code ?? ConnectErrorCode.generic;
    _phase = ConnectPhase.error;
    notifyListeners();
  }

  void clearErrorMessage() {
    _clearError();
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage == null && _phase != ConnectPhase.error) {
      return;
    }
    _errorMessage = null;
    _errorCode = null;
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

    final activeStart = _discoveryStartFuture;
    if (activeStart != null) {
      await activeStart;
      return;
    }

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

    _deviceSubscription ??= _transport.discoveredDeviceStream.listen(
      upsertDiscoveredDevice,
    );
    _pairRequestSubscription ??= _transport.pairRequestStream.listen(
      _onPairRequest,
    );
    _pairResponseSubscription ??= _transport.pairResponseStream.listen(
      _onPairResponse,
    );
    _snapshotSubscription ??= _transport.snapshotStream.listen(
      _onSnapshotSync,
    );
    _stateDeltaSubscription ??= _transport.stateDeltaStream.listen(
      _onStateDelta,
    );
    _positionPulseSubscription ??= _transport.positionPulseStream.listen(
      _onPositionPulse,
    );
    _commandIntentSubscription ??= _transport.commandIntentStream
        .listen(_onCommandIntent);
    _commandApplySubscription ??= _transport.commandApplyStream.listen(
      _onCommandApply,
    );
    _commandAckSubscription ??= _transport.commandAckStream.listen(
      _onCommandAck,
    );
    _unlinkSubscription ??= _transport.unlinkStream.listen(
      _onUnlinkEvent,
    );
    // legacy playback pulse removed

    _pruneTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      pruneDiscoveredDevicesOlderThan(const Duration(seconds: 8));
    });

    final startFuture = _transport.start(
      localDeviceId: _localDeviceId,
      localDeviceName: _localDeviceName,
      localPlatform: localPlatform,
    );
    _discoveryStartFuture = startFuture;
    try {
      await startFuture;
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
    } finally {
      if (identical(_discoveryStartFuture, startFuture)) {
        _discoveryStartFuture = null;
      }
    }
  }

  Future<void> _stopDiscoveryInternal() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _stopTargetPulseTimer();
    _stopHostInterpolationTimer();

    await _transport.stop();
    _discoveryStarted = false;
    _discoveryStartFuture = null;
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
      await _transport.stop();
      _discoveryStarted = false;
      _discoveryStartFuture = null;
    }

    await _startDiscoveryInternal();
  }

  void _onPairRequest(ConnectPairRequest request) {
    logger.d(
      '[Handoff] Incoming pair request from ${request.fromDeviceName} (${request.fromDeviceId}) @ ${request.fromAddress} mode=${request.requestedMode.toJson()}',
    );

    final localSecurity = _localSecurityLevel;
    final remoteSecurity = request.securityLevel;

    // Correct semantic: if the remote device's security is LOWER than our
    // configured local security, reject the incoming pair.
    // Use explicit index comparison but keep tests small and obvious.
    if (remoteSecurity.index > localSecurity.index) {
      logger.d(
        '[Handoff] Rejected incoming pair from ${request.fromDeviceId} due to lower security level ${remoteSecurity.toJson()} < ${localSecurity.toJson()}.',
      );
      _transport.respondPair(
        targetAddress: request.fromAddress,
        accepted: false,
        localDeviceId: _localDeviceId,
        localDeviceName: _localDeviceName,
        localPlatform: localPlatform,
        mode: request.requestedMode,
        rejectionReason: 'security_level_too_low',
      );
      return;
    }

    // If remote security is stronger than our configured level, no warning is
    // necessary. If remote security is weaker (but not rejected), surface a
    // non-blocking warning to the user.
    if (remoteSecurity.index < localSecurity.index) {
      _pendingSecurityWarningMessage =
          'Connection is less secure than your configured level.';
    } else {
      _pendingSecurityWarningMessage = null;
    }

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

    // Cancel any outstanding pairing timeout
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;

    if (response.accepted) {
      logger.d(
        '[Handoff] Pair accepted by ${response.fromDeviceName} (${response.fromDeviceId}) @ ${response.fromAddress} mode=${response.linkMode.toJson()}',
      );
      _activeLinkMode = response.linkMode;
      markLinkedSyncingAsHost(response.fromDeviceId, response.fromDeviceName);
      _pairingTargetAddress = response.fromAddress;
      _linkedPeerAddress = response.fromAddress;
      _linkedPeerName = response.fromDeviceName;
      _syncLinkedOutputDestination();
      
      // For full handoff: Host sends its snapshot to Target
      // For control-only: Target will send its snapshot to Host, so don't send
      if (response.linkMode == ConnectLinkMode.fullHandoff) {
        _sendCurrentSnapshotToTarget(response.fromAddress);
      }
      
      unawaited(_pauseLocalPlaybackAsHost());
    } else {
      logger.d(
        '[Handoff] Pair rejected by ${response.fromDeviceName} (${response.fromDeviceId})',
      );
      _lastRejectedPairingTargetDeviceId = response.fromDeviceId;
      _linkedDeviceId = null;
      _linkedPeerName = null;
      _activeLinkMode = ConnectLinkMode.fullHandoff;
      _pairingTargetDeviceId = null;
      _pairingTargetAddress = null;
      _linkedPeerAddress = null;
      _setPhase(ConnectPhase.idle);
      if (response.rejectionReason == 'security_level_too_low') {
        setError(
          'Target device\'s connection security level is too low. Want to try again with lower, but equal, level security?',
          ConnectErrorCode.securityLevelTooLow,
        );
      } else {
        setError('Pair request rejected by target device.');
      }
    }
  }

  void _onSnapshotSync(ConnectSnapshotSync sync) {
    if (sync.fromDeviceId == _localDeviceId) return;

    logger.d(
      '[Handoff] Snapshot sync from ${sync.fromDeviceId} queue=${sync.snapshot.queue.length} index=${sync.snapshot.currentIndex}',
    );

    _linkedPeerAddress = sync.fromAddress;
    final isHostSnapshot = isHost ||
        (_pairingTargetDeviceId != null &&
            sync.fromDeviceId == _pairingTargetDeviceId &&
            _role != ConnectRole.target);
    if (isHostSnapshot) {
      if (!isHost) {
        markLinkedSyncingAsHost(
          sync.fromDeviceId,
          _discoveredById[sync.fromDeviceId]?.name ?? sync.fromDeviceId,
        );
      }
      if (!_shouldApplyHostSnapshot(sync.snapshot)) {
        logger.d('[Handoff] Ignored duplicate snapshot_sync from target.');
        return;
      }
      unawaited(_applyIncomingSnapshotAsHost(sync));
      return;
    }

    _applyIncomingSnapshot(sync);
  }

  void _onStateDelta(ConnectStateDeltaSync deltasync) {
    if (deltasync.delta.deviceId == _localDeviceId) return;

    _linkedPeerAddress = deltasync.fromAddress;
    if (isHost) {
      if (_linkedDeviceId != null && deltasync.fromDeviceId != _linkedDeviceId) {
        return;
      }

      if (_isStaleHostDelta(deltasync.delta)) {
        logger.d(
          '[Handoff] Ignored stale state delta seq=${deltasync.delta.seq} ts=${deltasync.delta.ts}',
        );
        return;
      }

      // Host receives deltas from Target to update UI.
      final mergedPlaying = deltasync.delta.isPlaying ?? _linkedIsPlaying;
      final mergedPosition = Duration(
        milliseconds: deltasync.delta.positionMs ?? _linkedPosition.inMilliseconds,
      );
      _setLinkedPlaybackState(
        isPlaying: mergedPlaying,
        position: mergedPosition,
        notify: true,
      );

      final audio = _audioHandler;
      if (_activeLinkMode == ConnectLinkMode.controlOnly && audio != null) {
        _applyHostDeltaToPassiveSnapshot(audio, deltasync.delta);
      }
      return;
    }

    // Target should not typically receive deltas; this is for future use
    logger.d('[Handoff] Target received delta (unexpected)');
  }

  void _onPositionPulse(ConnectPositionPulseSync pulsesync) {
    if (pulsesync.pulse.deviceId == _localDeviceId) return;

    _linkedPeerAddress = pulsesync.fromAddress;
    if (!isHost) return; // Only Host processes position pulses from Target

    final pulse = pulsesync.pulse;

    // Update host UI with target's current position for interpolation
    // Apply pulse to linked playback state
    _setLinkedPlaybackState(
      isPlaying: _linkedIsPlaying,
      position: Duration(milliseconds: pulse.positionMs),
      notify: true,
    );

    // Ensure audio handler is in sync with pulse state
    final audio = _audioHandler;
    if (audio != null && _activeLinkMode == ConnectLinkMode.controlOnly) {
      // In control-only, Host should reflect target's position for UI
      notifyListeners();
    }
  }

  void _onCommandIntent(ConnectCommandIntent intent) {
    if (!isHost) return;
    if (_linkedDeviceId == null || intent.fromDeviceId != _linkedDeviceId) {
      return;
    }

    logger.d(
      '[Handoff] Command intent from target ${intent.fromDeviceId}: ${intent.command}',
    );
    _linkedPeerAddress = intent.fromAddress;
    _linkedPeerName ??= _discoveredById[intent.fromDeviceId]?.name;

    // In control-only mode: Target is the authority. Don't re-issue commands.
    // Instead, just acknowledge and update UI state for sync.
    if (_activeLinkMode == ConnectLinkMode.controlOnly) {
      logger.d(
        '[Handoff] Control-only mode: Host received target command ${intent.command} - acknowledging without re-issuing',
      );
      // Request snapshot from target to sync UI
      unawaited(_requestCommand(_cmdRequestSnapshot));
      return;
    }

    // In full handoff mode: Host is the authority. Re-issue the command to target.
    _issueHostCommand(intent.command, intent.payload);
  }

  void _onCommandApply(ConnectCommandApply apply) {
    if (!isTarget) return;
    if (_linkedDeviceId == null || apply.fromDeviceId != _linkedDeviceId) {
      return;
    }

    logger.i(
      '[Handoff] Command apply from host seq=${apply.sequence} cmd=${apply.command}',
    );
    _linkedPeerAddress = apply.fromAddress;
    _linkedPeerName ??= _discoveredById[apply.fromDeviceId]?.name;
    _applyCommandAsTarget(apply);
  }

  void _onCommandAck(ConnectCommandAck ack) {
    if (!isHost) return;
    if (_linkedDeviceId == null || ack.fromDeviceId != _linkedDeviceId) {
      return;
    }

    logger.d(
      '[Handoff] Command ack from target seq=${ack.sequence}',
    );
    _linkedPeerAddress = ack.fromAddress;
    _linkedPeerName ??= _discoveredById[ack.fromDeviceId]?.name;
    markCommandAcked(ack.sequence);
    _setLinkedPlaybackState(
      isPlaying: ack.isPlaying,
      position: Duration(milliseconds: ack.positionMs),
      notify: true,
    );
    if (ack.snapshot != null) {
      logger.d(
        '[Handoff] Command ack has snapshot: queue=${ack.snapshot!.queue.length} index=${ack.snapshot!.currentIndex} playing=${ack.snapshot!.isPlaying}',
      );
      if (isHost && _activeLinkMode == ConnectLinkMode.controlOnly) {
        if (_lastHostSnapshotAckSequence == ack.sequence ||
            !_shouldApplyHostSnapshot(ack.snapshot!, sequence: ack.sequence)) {
          logger.d(
            '[Handoff] Ignored duplicate command_ack snapshot seq=${ack.sequence}.',
          );
          return;
        }
        _lastHostSnapshotAckSequence = ack.sequence;
        logger.d(
          '[Handoff] Applying ack snapshot in control-only mode to sync Host UI',
        );
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

  // legacy playback pulse handler removed; use position_pulse instead

  void _onUnlinkEvent(ConnectUnlinkEvent event) {
    final matchesLinkedPeer = event.fromDeviceId == _linkedDeviceId ||
        event.fromDeviceId == _pairingTargetDeviceId;
    if (!matchesLinkedPeer) {
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

  void _syncLinkedOutputDestination() {
    final linkedId = _linkedDeviceId;
    if (linkedId == null || linkedId.isEmpty) {
      setActiveOutputDestination(ConnectOutputKind.local);
      return;
    }

    final device = _discoveredById[linkedId];
    final name = device?.name ?? _linkedPeerName ?? linkedId;
    final platform = (device?.platform ?? '').trim().toLowerCase();
    final kind = switch (platform) {
      'android' || 'ios' || 'iphone' || 'ipad' =>
        ConnectOutputKind.handoffMobile,
      'linux' || 'macos' || 'windows' => ConnectOutputKind.handoffDesktop,
      _ => ConnectOutputKind.handoffDesktop,
    };
    setActiveOutputDestination(kind, deviceName: name);
  }

  Future<void> _startOutputRouteMonitoring() async {
    try {
      final session = await AudioSession.instance;
      _audioDevicesSubscription ??= session.devicesStream.listen(
        _updateAvailableOutputDevices,
      );
      final devices = await session.getDevices(
        includeInputs: false,
        includeOutputs: true,
      );
      _updateAvailableOutputDevices(devices);
    } catch (error) {
      logger.w('[Handoff] Output route monitoring unavailable.', error: error);
      _availableOutputDevices = [
        ConnectOutputDevice(
          kind: ConnectOutputKind.local,
          name: _localDeviceName,
        ),
      ];
    }
  }

  Future<void> _refreshOutputDevicesInternal() async {
    try {
      final session = await AudioSession.instance;
      final devices = await session.getDevices(
        includeInputs: false,
        includeOutputs: true,
      );
      _updateAvailableOutputDevices(devices);
    } catch (error) {
      logger.w('[Handoff] Failed to refresh output routes.', error: error);
    }
  }

  void _updateAvailableOutputDevices(Set<AudioDevice> devices) {
    final localName = _localDeviceName.trim().isEmpty
        ? 'This Device'
        : _localDeviceName;
    final nextDevices = <ConnectOutputDevice>[
      ConnectOutputDevice(kind: ConnectOutputKind.local, name: localName),
    ];

    for (final device in devices) {
      if (!device.isOutput) continue;
      final kind = _mapAudioDeviceToOutputKind(device);
      if (kind == null) continue;
      final name = device.name.trim().isEmpty
          ? kind.label
          : device.name.trim();
      nextDevices.add(ConnectOutputDevice(kind: kind, name: name));
    }

    final dedupedDevices = <ConnectOutputDevice>[];
    final seen = <String>{};
    for (final device in nextDevices) {
      final key = '${device.kind.name}|${device.name ?? ''}'.toLowerCase();
      if (!seen.add(key)) continue;
      dedupedDevices.add(device);
    }

    final nextPreferredExternal = dedupedDevices.firstWhere(
      (device) => device.kind == ConnectOutputKind.bluetooth,
      orElse: () => dedupedDevices.firstWhere(
        (device) => device.kind == ConnectOutputKind.wired,
        orElse: () => const ConnectOutputDevice(kind: ConnectOutputKind.local),
      ),
    );

    final wasChanged = !_sameOutputDevices(
      _availableOutputDevices,
      dedupedDevices,
    );
    _availableOutputDevices = dedupedDevices;

    var activeChanged = false;
    if (!isLinked) {
      ConnectOutputDevice nextOutput = nextPreferredExternal;
      final manualKind = _manualOutputKind;
      if (manualKind != null) {
        final manualName = _manualOutputDeviceName;
        final manualMatch = dedupedDevices.where((device) {
          if (device.kind != manualKind) {
            return false;
          }
          if (manualKind == ConnectOutputKind.local) {
            return true;
          }
          return (device.name ?? '').trim().toLowerCase() ==
              (manualName ?? '').trim().toLowerCase();
        });
        if (manualMatch.isNotEmpty) {
          nextOutput = manualMatch.first;
        } else {
          _manualOutputKind = null;
          _manualOutputDeviceName = null;
        }
      }

      final nextKind = nextOutput.kind;
      final nextName =
          nextKind == ConnectOutputKind.local ? null : nextOutput.name;
      if (_activeOutputKind != nextKind || _activeOutputDeviceName != nextName) {
        _activeOutputKind = nextKind;
        _activeOutputDeviceName = nextName;
        activeChanged = true;
      }
    }

    if (wasChanged || activeChanged) {
      notifyListeners();
    }
  }

  ConnectOutputKind? _mapAudioDeviceToOutputKind(AudioDevice device) {
    final typeName = '${device.type}'.toLowerCase();
    if (typeName.contains('bluetooth') || typeName.contains('hearingaid')) {
      return ConnectOutputKind.bluetooth;
    }
    if (typeName.contains('wired') ||
        typeName.contains('line') ||
        typeName.contains('aux') ||
        typeName.contains('usb') ||
        typeName.contains('dock')) {
      return ConnectOutputKind.wired;
    }
    return null;
  }

  bool _sameOutputDevices(
    List<ConnectOutputDevice> previous,
    List<ConnectOutputDevice> next,
  ) {
    if (previous.length != next.length) {
      return false;
    }
    for (var i = 0; i < previous.length; i++) {
      if (previous[i].kind != next[i].kind || previous[i].name != next[i].name) {
        return false;
      }
    }
    return true;
  }

  Future<void> _applyIncomingSnapshot(ConnectSnapshotSync sync) async {
    try {
      logger.d(
        '[Handoff] Applying incoming snapshot from ${sync.fromDeviceId}.',
      );
      markLinkedSyncingAsTarget(
        sync.fromDeviceId,
        _discoveredById[sync.fromDeviceId]?.name ?? sync.fromDeviceId,
      );
      applyResolvedYoutubeIds(sync.snapshot.resolvedYoutubeIds);

      final audioHandler = _audioHandler;
      if (audioHandler != null) {
        await _audioCommandApplier.applySnapshot(
          audioHandler,
          sync.snapshot,
          autoPlay: true,
          preserveVolume: true,
        );
        logger.d(
          '[Handoff] _applyIncomingSnapshot: applied snapshot -> audio.currentIndex=${audioHandler.currentIndex} isPlaying=${audioHandler.isPlaying} positionMs=${audioHandler.position.inMilliseconds}',
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
        logger.d(
          '[Handoff] Applying incoming snapshot as host: queue=${sync.snapshot.queue.length} index=${sync.snapshot.currentIndex} isPlaying=${sync.snapshot.isPlaying}',
        );
        audioHandler.applyPassiveConnectSnapshot(sync.snapshot);
        logger.d(
          '[Handoff] Applied snapshot successfully. Audio handler currentIndex=${audioHandler.currentIndex}',
        );
      } catch (e) {
        logger.e(
          '[Handoff] Failed to apply incoming snapshot as host',
          error: e,
        );
      }
    } else {
      logger.w('[Handoff] Audio handler is null, cannot apply snapshot');
    }

    applyResolvedYoutubeIds(sync.snapshot.resolvedYoutubeIds);
    markLinkedPlaying(
      isPlaying: sync.snapshot.isPlaying,
      position: Duration(milliseconds: sync.snapshot.positionMs),
    );
    unawaited(_pauseLocalPlaybackAsHost());
  }

  bool _isStaleHostDelta(ConnectStateDelta delta) {
    if (delta.seq <= _lastHostDeltaSeq) {
      return true;
    }
    if (_lastHostDeltaTs >= 0 && delta.ts > 0 && delta.ts < _lastHostDeltaTs) {
      return true;
    }
    _lastHostDeltaSeq = delta.seq;
    if (delta.ts > 0) {
      _lastHostDeltaTs = delta.ts;
    }
    return false;
  }

  bool _shouldApplyHostSnapshot(
    ConnectPlaybackSnapshot snapshot, {
    int? sequence,
  }) {
    if (sequence != null && _lastHostSnapshotAckSequence == sequence) {
      return false;
    }

    final fingerprint = Object.hash(
      snapshot.queue.length,
      snapshot.currentIndex,
      snapshot.isPlaying,
      snapshot.positionMs,
      snapshot.durationMs,
    );
    final now = DateTime.now();
    final lastAppliedAt = _lastHostSnapshotAppliedAt;
    final appliedRecently =
        lastAppliedAt != null && now.difference(lastAppliedAt).inMilliseconds < 900;

    if (appliedRecently && fingerprint == _lastHostSnapshotFingerprint) {
      return false;
    }

    _lastHostSnapshotFingerprint = fingerprint;
    _lastHostSnapshotAppliedAt = now;
    return true;
  }

  void _applyHostDeltaToPassiveSnapshot(
    WispAudioHandler audio,
    ConnectStateDelta delta,
  ) {
    final base = audio.buildConnectSnapshot();
    final merged = ConnectPlaybackSnapshot(
      queue: delta.queue ?? base.queue,
      originalQueue: base.originalQueue,
      currentIndex: delta.currentIndex ?? base.currentIndex,
      positionMs: delta.positionMs ?? base.positionMs,
      durationMs: delta.durationMs ?? base.durationMs,
      isPlaying: delta.isPlaying ?? base.isPlaying,
      shuffleEnabled: delta.shuffleEnabled ?? base.shuffleEnabled,
      repeatMode: delta.repeatMode ?? base.repeatMode,
      contextType: base.contextType,
      contextName: base.contextName,
      contextId: base.contextId,
      contextSource: base.contextSource,
      volume: delta.volume ?? base.volume,
      resolvedYoutubeIds: base.resolvedYoutubeIds,
    );
    audio.applyPassiveConnectSnapshot(merged);
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
    if (peerAddress == null || peerAddress.isEmpty) {
      logger.w('[Handoff] _sendTargetPlaybackPulse: no valid peer address (linked=$_linkedPeerAddress, pairing=$_pairingTargetAddress)');
      return;
    }

    final audio = _audioHandler;
    if (audio == null) return;

    logger.d('[Handoff] _sendTargetPlaybackPulse to=$peerAddress');
    // Get current position and playing state
    final positionMs = audio.position.inMilliseconds;
    final isPlaying = audio.isPlaying;

    _setLinkedPlaybackState(
      isPlaying: isPlaying,
      position: Duration(milliseconds: positionMs),
      notify: false,
    );

    // Send new format position pulse with seq and ts
    _transport.sendPositionPulse(
      targetAddress: peerAddress,
      fromDeviceId: _localDeviceId,
      pulse: ConnectPositionPulse(
        deviceId: _localDeviceId,
        seq: _nextPositionPulseSeq++,
        ts: DateTime.now().millisecondsSinceEpoch,
        positionMs: positionMs,
      ),
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
    // Use lean parameters to avoid oversized UDP datagrams on target (Windows UDP limit)
    _transport.sendSnapshot(
      targetAddress: address,
      fromDeviceId: _localDeviceId,
      snapshot: snapshot,
      includeOriginalQueue: false,
      includeResolvedYoutubeIds: false,
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

    final payloadSummary = _summarizePayload(command, payload);
    logger.d(
      '[Handoff] Request command role=$_role linked=$isLinked cmd=$command $payloadSummary peer=$_linkedPeerAddress pairTarget=$_pairingTargetAddress',
    );

    if (isHost) {
      await _issueHostCommand(command, payload);
      return;
    }

    final peerAddress = _linkedPeerAddress;
    if (!isTarget || peerAddress == null || peerAddress.isEmpty) {
      return;
    }

    _transport.sendCommandIntent(
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
    final payloadSummary = _summarizePayload(command, payload);
    logger.d(
      '[Handoff] Host issue seq=$sequence cmd=$command $payloadSummary target=$peerAddress',
    );
    markCommandApplied(sequence);
    _transport.sendCommandApply(
      targetAddress: peerAddress,
      fromDeviceId: _localDeviceId,
      sequence: sequence,
      command: command,
      payload: payload,
    );
  }

  String _summarizePayload(String command, Map<String, dynamic> payload) {
    if (payload.isEmpty) return 'payload={}';
    
    switch (command) {
      case 'set_queue':
        final trackCount = (payload['tracks'] is List) 
            ? (payload['tracks'] as List).length 
            : 0;
        return 'payloadSize=set_queue(tracks=$trackCount)';
      case 'seek':
        final posMs = payload['position_ms'];
        return 'payloadSize=seek(posMs=$posMs)';
      default:
        return 'payloadSize=${command}(keys=${payload.keys.length})';
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
    if (audio == null) {
      logger.w('[Handoff] Target cannot apply command: audio handler null');
      return;
    }

    try {
      if (apply.command == _cmdRequestSnapshot) {
        final snapshot = audio.buildConnectSnapshot();
        logger.d(
          '[Handoff] Target responding to snapshot request seq=${apply.sequence}',
        );
        _transport.sendCommandAck(
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
        return;
      }

      var applyFailed = false;
      logger.d(
        '[Handoff] Target apply seq=${apply.sequence} cmd=${apply.command} payload=${apply.payload}',
      );
      try {
        await _audioCommandApplier.apply(
          audio: audio,
          command: apply.command,
          payload: apply.payload,
        );
      } catch (e, st) {
        applyFailed = true;
        setError('Failed to apply remote command.');
        logger.e(
          '[Handoff] Failed to apply remote command seq=${apply.sequence} cmd=${apply.command} error=$e',
          error: e,
          stackTrace: st,
        );
      }

      markCommandApplied(apply.sequence);
      final snapshot = audio.buildConnectSnapshot();
      logger.d(
        '[Handoff] Target ack seq=${apply.sequence} applied=${!applyFailed} playing=${snapshot.isPlaying} posMs=${snapshot.positionMs} to=${apply.fromAddress}',
      );
      // Resolve a safe target address to reply to. Prefer the packet's
      // source address, but fall back to our linked peer or discovered
      // device entry if the source looks invalid (eg. 0.0.0.0).
      String? targetAddr = apply.fromAddress;
      logger.d('[Handoff] Preparing command_ack: packet.fromAddress=${apply.fromAddress} linkedPeer=$_linkedPeerAddress discovered=${_discoveredById[apply.fromDeviceId]?.address} pairingTarget=$_pairingTargetAddress');
      if (targetAddr == null || targetAddr.isEmpty || targetAddr == '0.0.0.0') {
        targetAddr = _linkedPeerAddress;
      }
      if (targetAddr == null || targetAddr.isEmpty || targetAddr == '0.0.0.0') {
        targetAddr = _discoveredById[apply.fromDeviceId]?.address ?? _pairingTargetAddress;
      }

      if (targetAddr == null || targetAddr.isEmpty || targetAddr == '0.0.0.0') {
        logger.w('[Handoff] No valid address to send command_ack for seq=${apply.sequence} to ${apply.fromDeviceId}; resolved targetAddr=$targetAddr');
      } else {
        logger.d('[Handoff] Sending command_ack seq=${apply.sequence} to $targetAddr (fromDevice=${apply.fromDeviceId})');
        _transport.sendCommandAck(
          targetAddress: targetAddr,
          fromDeviceId: _localDeviceId,
          sequence: apply.sequence,
          isPlaying: snapshot.isPlaying,
          positionMs: snapshot.positionMs,
          snapshot: snapshot,
        );
      }
      markLinkedPlaying(
        isPlaying: snapshot.isPlaying,
        position: Duration(milliseconds: snapshot.positionMs),
      );
      _sendTargetPlaybackPulse();
    } catch (e, st) {
      logger.e(
        '[Handoff] Target command ack failed seq=${apply.sequence} cmd=${apply.command}',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _acceptIncomingPairRequest(
    ConnectPairRequest request, {
    required bool manual,
  }) {
    _pendingSecurityWarningMessage = null;
    _activeLinkMode = request.requestedMode;
    _transport.respondPair(
      targetAddress: request.fromAddress,
      accepted: true,
      localDeviceId: _localDeviceId,
      localDeviceName: _localDeviceName,
      localPlatform: localPlatform,
      mode: request.requestedMode,
    );
    markLinkedSyncingAsTarget(request.fromDeviceId, request.fromDeviceName);
    _pairingTargetAddress = request.fromAddress;
    _linkedPeerAddress = request.fromAddress;
    _linkedPeerName = request.fromDeviceName;
    unawaited(
      _preferences?.recordTrustedDeviceConnection(
        id: request.fromDeviceId,
        name: request.fromDeviceName,
        platform: request.fromPlatform,
      ),
    );
    logger.d(
      '[Handoff] Accepted incoming pair from ${request.fromDeviceName} (${request.fromDeviceId}) @ ${request.fromAddress} mode=${request.requestedMode.toJson()} manual=$manual',
    );
    _pendingPairRequest = null;

    // For control-only: Target sends its snapshot to Host for UI sync
    if (request.requestedMode == ConnectLinkMode.controlOnly) {
      _sendCurrentSnapshotToHost(request.fromAddress);
    }

    if (manual && !isTrustedIncomingDevice(request.fromDeviceId)) {
      _pendingTrustPromptDeviceId = request.fromDeviceId;
      _pendingTrustPromptDeviceName = request.fromDeviceName;
      _pendingTrustPromptDevicePlatform = request.fromPlatform;
    }
    notifyListeners();
  }

  void _sendCurrentSnapshotToHost(String targetAddress) {
    final audioHandler = _audioHandler;
    if (audioHandler == null) {
      return;
    }
    final snapshot = audioHandler.buildConnectSnapshot();
    try {
      logger.d(
        '[Handoff] Sending snapshot to host target=$targetAddress queue=${snapshot.queue.length} index=${snapshot.currentIndex} playing=${snapshot.isPlaying}',
      );
      _transport.sendSnapshot(
        targetAddress: targetAddress,
        fromDeviceId: _localDeviceId,
        snapshot: snapshot,
        includeOriginalQueue: false,
        includeResolvedYoutubeIds: false,
      );
      markLinkedPlaying(
        isPlaying: snapshot.isPlaying,
        position: Duration(milliseconds: snapshot.positionMs),
      );
    } catch (error, stackTrace) {
      logger.e(
        '[Handoff] Failed to send initial snapshot to host target=$targetAddress queue=${snapshot.queue.length} index=${snapshot.currentIndex}',
        error: error,
        stackTrace: stackTrace,
      );
      setError('Failed to send initial sync snapshot.');
    }
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
    _stateDeltaSubscription?.cancel();
    _positionPulseSubscription?.cancel();
    _commandIntentSubscription?.cancel();
    _commandApplySubscription?.cancel();
    _commandAckSubscription?.cancel();
    _unlinkSubscription?.cancel();
    // legacy playback pulse subscription removed
    _audioDevicesSubscription?.cancel();
    _stopTargetPulseTimer();
    _stopHostInterpolationTimer();
    _transport.dispose();
    super.dispose();
  }
}
