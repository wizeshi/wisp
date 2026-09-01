import 'package:wisp/models/metadata_models.dart';

enum ConnectPhase {
  idle,
  discovering,
  pairing,
  linkedSyncing,
  linkedPlaying,
  unlinking,
  localResumed,
  error,
}

enum ConnectRole { none, host, target }

enum ConnectLinkMode { fullHandoff, controlOnly }

enum HandoffSecurityLevel { keyExchange, pinBased }

extension HandoffSecurityLevelJson on HandoffSecurityLevel {
  String toJson() {
    switch (this) {
      case HandoffSecurityLevel.keyExchange:
        return 'key_exchange';
      case HandoffSecurityLevel.pinBased:
        return 'pin_based';
    }
  }

  static HandoffSecurityLevel fromJson(String? value) {
    switch (value) {
      case 'pin_based':
        return HandoffSecurityLevel.pinBased;
      case 'key_exchange':
      default:
        return HandoffSecurityLevel.keyExchange;
    }
  }

  String get label {
    switch (this) {
      case HandoffSecurityLevel.keyExchange:
        return 'Key-Exchange';
      case HandoffSecurityLevel.pinBased:
        return 'PIN-based';
    }
  }
}

enum ConnectOutputKind {
  local,
  wired,
  bluetooth,
  handoffDesktop,
  handoffMobile,
}

extension ConnectOutputKindUi on ConnectOutputKind {
  bool get isExternal => this != ConnectOutputKind.local;

  String get label {
    switch (this) {
      case ConnectOutputKind.local:
        return 'This device';
      case ConnectOutputKind.wired:
        return 'Wired connection';
      case ConnectOutputKind.bluetooth:
        return 'Bluetooth audio';
      case ConnectOutputKind.handoffDesktop:
        return 'Handoff - Desktop';
      case ConnectOutputKind.handoffMobile:
        return 'Handoff - Mobile';
    }
  }
}

extension ConnectLinkModeJson on ConnectLinkMode {
  String toJson() {
    switch (this) {
      case ConnectLinkMode.controlOnly:
        return 'control_only';
      case ConnectLinkMode.fullHandoff:
        return 'full_handoff';
    }
  }

  static ConnectLinkMode fromJson(String? value) {
    switch (value) {
      case 'control_only':
        return ConnectLinkMode.controlOnly;
      case 'full_handoff':
      default:
        return ConnectLinkMode.fullHandoff;
    }
  }
}

class ConnectDevice {
  final String id;
  final String name;
  final String platform;
  final String? address;
  final DateTime lastSeenAt;

  const ConnectDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastSeenAt,
    this.address,
  });

  ConnectDevice copyWith({
    String? id,
    String? name,
    String? platform,
    String? address,
    DateTime? lastSeenAt,
  }) {
    return ConnectDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      address: address ?? this.address,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'address': address,
    'last_seen_at': lastSeenAt.toIso8601String(),
  };

  factory ConnectDevice.fromJson(Map<String, dynamic> json) {
    return ConnectDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      platform: json['platform'] as String,
      address: json['address'] as String?,
      lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
    );
  }
}

class TrustedDevice {
  final String id;
  final String name;
  final String platform;
  final DateTime trustedAt;
  final DateTime lastConnectionAt;

  const TrustedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.trustedAt,
    required this.lastConnectionAt,
  });

  TrustedDevice copyWith({
    String? id,
    String? name,
    String? platform,
    DateTime? trustedAt,
    DateTime? lastConnectionAt,
  }) {
    return TrustedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      trustedAt: trustedAt ?? this.trustedAt,
      lastConnectionAt: lastConnectionAt ?? this.lastConnectionAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'trusted_at': trustedAt.toIso8601String(),
    'last_connection_at': lastConnectionAt.toIso8601String(),
  };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) {
    return TrustedDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      platform: json['platform'] as String,
      trustedAt: DateTime.parse(json['trusted_at'] as String),
      lastConnectionAt: DateTime.parse(json['last_connection_at'] as String),
    );
  }
}

class ConnectOutputDevice {
  final ConnectOutputKind kind;
  final String? name;

  const ConnectOutputDevice({required this.kind, this.name});
}

class ConnectPlaybackSnapshot {
  final List<GenericSong> queue;
  final List<GenericSong> originalQueue;
  final int currentIndex;
  final int positionMs;
  final int? durationMs;
  final bool isPlaying;
  final bool shuffleEnabled;
  final String repeatMode;
  final String? contextType;
  final String? contextName;
  final String? contextId;
  final SongSource? contextSource;
  final double? volume;
  final Map<String, String> resolvedYoutubeIds;

  const ConnectPlaybackSnapshot({
    required this.queue,
    required this.originalQueue,
    required this.currentIndex,
    required this.positionMs,
    this.durationMs,
    required this.isPlaying,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.resolvedYoutubeIds,
    this.contextType,
    this.contextName,
    this.contextId,
    this.contextSource,
    this.volume,
  });

  Map<String, dynamic> toJson() => {
    'queue': queue.map((t) => t.toJson()).toList(),
    'original_queue': originalQueue.map((t) => t.toJson()).toList(),
    'current_index': currentIndex,
    'position_ms': positionMs,
    'duration_ms': durationMs,
    'is_playing': isPlaying,
    'shuffle_enabled': shuffleEnabled,
    'repeat_mode': repeatMode,
    'context_type': contextType,
    'context_name': contextName,
    'context_id': contextId,
    'context_source': contextSource?.toJson(),
    'volume': volume,
    'resolved_youtube_ids': resolvedYoutubeIds,
  };

  factory ConnectPlaybackSnapshot.fromJson(Map<String, dynamic> json) {
    final queueJson = (json['queue'] as List<dynamic>? ?? const []);
    final originalQueueJson =
        (json['original_queue'] as List<dynamic>? ?? const []);
    final resolvedIdsJson =
        (json['resolved_youtube_ids'] as Map<String, dynamic>? ?? const {});

    return ConnectPlaybackSnapshot(
      queue: queueJson
          .map((item) => GenericSong.fromJson(item as Map<String, dynamic>))
          .toList(),
      originalQueue: originalQueueJson
          .map((item) => GenericSong.fromJson(item as Map<String, dynamic>))
          .toList(),
      currentIndex: (json['current_index'] as int?) ?? -1,
      positionMs: (json['position_ms'] as int?) ?? 0,
        durationMs: (json['duration_ms'] as int?) ??
          (json['duration_ms'] as num?)?.toInt(),
      isPlaying: (json['is_playing'] as bool?) ?? false,
      shuffleEnabled: (json['shuffle_enabled'] as bool?) ?? false,
      repeatMode: (json['repeat_mode'] as String?) ?? 'RepeatMode.off',
      contextType: json['context_type'] as String?,
      contextName: json['context_name'] as String?,
      contextId: json['context_id'] as String?,
      contextSource: json['context_source'] != null
          ? SongSource.fromJson(json['context_source'] as String)
          : null,
      volume: (json['volume'] as num?)?.toDouble(),
      resolvedYoutubeIds: resolvedIdsJson.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }
}

class ConnectCommandEnvelope {
  final String id;
  final String command;
  final Map<String, dynamic> payload;
  final String originDeviceId;
  final int sequence;
  final DateTime issuedAt;

  const ConnectCommandEnvelope({
    required this.id,
    required this.command,
    required this.payload,
    required this.originDeviceId,
    required this.sequence,
    required this.issuedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'command': command,
    'payload': payload,
    'origin_device_id': originDeviceId,
    'sequence': sequence,
    'issued_at': issuedAt.toIso8601String(),
  };

  factory ConnectCommandEnvelope.fromJson(Map<String, dynamic> json) {
    return ConnectCommandEnvelope(
      id: json['id'] as String,
      command: json['command'] as String,
      payload: (json['payload'] as Map<String, dynamic>? ?? const {}),
      originDeviceId: json['origin_device_id'] as String,
      sequence: (json['sequence'] as int?) ?? 0,
      issuedAt: DateTime.parse(json['issued_at'] as String),
    );
  }
}

/// Delta state update: contains only changed fields.
/// Used for transient updates to avoid full snapshot resync.
class ConnectStateDelta {
  final String deviceId; // Sender device ID for tie-breaker
  final int seq; // Sequence number for ordering
  final int ts; // Sender timestamp in milliseconds (for last-writer-wins)
  
  // Optional delta fields (present if changed)
  final int? positionMs;
  final int? currentIndex;
  final bool? isPlaying;
  final bool? shuffleEnabled;
  final String? repeatMode;
  final int? durationMs;
  final List<GenericSong>? queue; // Full queue if changed; use snapshot for size changes
  final double? volume;

  const ConnectStateDelta({
    required this.deviceId,
    required this.seq,
    required this.ts,
    this.positionMs,
    this.currentIndex,
    this.isPlaying,
    this.shuffleEnabled,
    this.repeatMode,
    this.durationMs,
    this.queue,
    this.volume,
  });

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'seq': seq,
    'ts': ts,
    if (positionMs != null) 'position_ms': positionMs,
    if (currentIndex != null) 'current_index': currentIndex,
    if (isPlaying != null) 'is_playing': isPlaying,
    if (shuffleEnabled != null) 'shuffle_enabled': shuffleEnabled,
    if (repeatMode != null) 'repeat_mode': repeatMode,
    if (durationMs != null) 'duration_ms': durationMs,
    if (queue != null) 'queue': queue!.map((t) => t.toJson()).toList(),
    if (volume != null) 'volume': volume,
  };

  factory ConnectStateDelta.fromJson(Map<String, dynamic> json) {
    final queueJson = (json['queue'] as List<dynamic>?);
    return ConnectStateDelta(
      deviceId: json['device_id'] as String? ?? '',
      seq: (json['seq'] as int?) ?? 0,
      ts: (json['ts'] as int?) ?? 0,
      positionMs: json['position_ms'] as int?,
      currentIndex: json['current_index'] as int?,
      isPlaying: json['is_playing'] as bool?,
      shuffleEnabled: json['shuffle_enabled'] as bool?,
      repeatMode: json['repeat_mode'] as String?,
      durationMs: json['duration_ms'] as int?,
      queue: queueJson
          ?.map((item) => GenericSong.fromJson(item as Map<String, dynamic>))
          .toList(),
      volume: (json['volume'] as num?)?.toDouble(),
    );
  }
}

/// Position pulse: periodic heartbeat from Target to Host for position sync.
/// Sent every 500ms while playing to keep Host's UI interpolation accurate.
class ConnectPositionPulse {
  final String deviceId; // Sender device ID
  final int seq; // Sequence number
  final int ts; // Sender timestamp in milliseconds
  final int positionMs; // Current playback position
  final int? bufferedMs; // Optional: buffered/pre-fetched amount

  const ConnectPositionPulse({
    required this.deviceId,
    required this.seq,
    required this.ts,
    required this.positionMs,
    this.bufferedMs,
  });

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'seq': seq,
    'ts': ts,
    'position_ms': positionMs,
    if (bufferedMs != null) 'buffered_ms': bufferedMs,
  };

  factory ConnectPositionPulse.fromJson(Map<String, dynamic> json) {
    return ConnectPositionPulse(
      deviceId: json['device_id'] as String? ?? '',
      seq: (json['seq'] as int?) ?? 0,
      ts: (json['ts'] as int?) ?? 0,
      positionMs: (json['position_ms'] as int?) ?? 0,
      bufferedMs: json['buffered_ms'] as int?,
    );
  }
}
