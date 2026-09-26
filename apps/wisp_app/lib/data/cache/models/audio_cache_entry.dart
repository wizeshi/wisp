// Copyright © 2026 wizeshi

/// Model representing an audio file stored in cache.
class AudioCacheEntry {
  final String trackId;
  final String videoId;
  final String filePath;
  final int fileSize;
  final String? trackTitle;
  final String? artistName;
  final DateTime downloadDate;
  DateTime lastPlayedDate;

  /// If true, this track was explicitly downloaded by the user for offline listening.
  /// User downloads are protected and NEVER automatically evicted by LRU.
  ///
  /// If false, this track was automatically cached during streaming and is
  /// eligible for LRU eviction when the storage quota is reached.
  bool isUserDownload;

  AudioCacheEntry({
    required this.trackId,
    required this.videoId,
    required this.filePath,
    required this.fileSize,
    this.trackTitle,
    this.artistName,
    required this.downloadDate,
    required this.lastPlayedDate,
    this.isUserDownload = false,
  });

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'videoId': videoId,
    'filePath': filePath,
    'fileSize': fileSize,
    'trackTitle': trackTitle,
    'artistName': artistName,
    'downloadDate': downloadDate.toIso8601String(),
    'lastPlayedDate': lastPlayedDate.toIso8601String(),
    'isUserDownload': isUserDownload,
  };

  factory AudioCacheEntry.fromJson(Map<String, dynamic> json) => AudioCacheEntry(
    trackId: json['trackId'] as String,
    videoId: json['videoId'] as String,
    filePath: json['filePath'] as String,
    fileSize: json['fileSize'] as int,
    trackTitle: json['trackTitle'] as String?,
    artistName: json['artistName'] as String?,
    downloadDate: DateTime.parse(json['downloadDate'] as String),
    lastPlayedDate: DateTime.parse(json['lastPlayedDate'] as String),
    isUserDownload: (json['isUserDownload'] as bool?) ?? false,
  );
}

/// Backwards compatibility alias
typedef CacheEntry = AudioCacheEntry;
