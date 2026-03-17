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

class ConnectPlaybackSnapshot {
  final List<GenericSong> queue;
  final List<GenericSong> originalQueue;
  final int currentIndex;
  final int positionMs;
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
