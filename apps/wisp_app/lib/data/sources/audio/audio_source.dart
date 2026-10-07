// Copyright © 2026 wizeshi

library;

import 'package:wisp/data/cache/audio/audio_mapping_store.dart';

/// Target audio stream quality tiers.
enum AudioQuality {
  standard('Standard (128-192 kbps)'),
  high('High (256-320 kbps)'),
  lossless('Lossless CD (16-bit / 44.1 kHz)'),
  hiRes('Hi-Res Lossless (24-bit / 96-192 kHz)'),
  auto('Auto / Best Available');

  final String label;
  const AudioQuality(this.label);

  static AudioQuality fromString(String? value) {
    if (value == null) return AudioQuality.auto;
    return AudioQuality.values.firstWhere(
      (q) => q.name.toLowerCase() == value.toLowerCase(),
      orElse: () => AudioQuality.auto,
    );
  }
}

/// Standardized search query passed to audio providers to resolve stream candidates.
class AudioSearchQuery {
  final String title;
  final List<String> artists;
  final String? album;
  final int? durationSecs;
  final String? isrc;
  final String? trackId;
  final String? metadataSource;

  AudioSearchQuery({
    required this.title,
    required this.artists,
    this.album,
    this.durationSecs,
    this.isrc,
    this.trackId,
    this.metadataSource,
  });

  String get artistNames => artists.join(', ');

  String get canonicalKey => AudioMappingStore.canonicalKey(
        title: title,
        artists: artists,
      );
}

/// A matched audio track candidate returned by an audio provider.
class AudioTrackCandidate {
  final String mediaId;
  final String providerId;
  final String title;
  final String artist;
  final String? album;
  final Duration duration;
  final String? thumbnailUrl;
  final String? qualityLabel;
  final double score;

  AudioTrackCandidate({
    required this.mediaId,
    required this.providerId,
    required this.title,
    required this.artist,
    this.album,
    required this.duration,
    this.thumbnailUrl,
    this.qualityLabel,
    this.score = 0.0,
  });
}

/// Configuration for decrypting segmented audio streams.
class SegmentCipherConfig {
  final String algorithm; // e.g. 'aes-ctr'
  final String keyHex;
  final String ivMode; // e.g. 'mp4-uuid'
  final Map<String, dynamic>? extra;

  SegmentCipherConfig({
    required this.algorithm,
    required this.keyHex,
    this.ivMode = 'mp4-uuid',
    this.extra,
  });

  factory SegmentCipherConfig.fromMap(Map<String, dynamic> map) {
    return SegmentCipherConfig(
      algorithm: map['algorithm']?.toString() ?? 'aes-ctr',
      keyHex: map['keyHex']?.toString() ?? map['key']?.toString() ?? '',
      ivMode: map['ivMode']?.toString() ?? 'mp4-uuid',
      extra: (map['extra'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toMap() => {
        'algorithm': algorithm,
        'keyHex': keyHex,
        'ivMode': ivMode,
        if (extra != null) 'extra': extra,
      };
}

/// Specification for audio streams delivered as discrete chunked segments (e.g. HLS/DASH/MP4-atoms).
class SegmentedAudioDescriptor {
  final String initSegmentUrl;
  final String segmentUrlTemplate;
  final int segmentCount;
  final String container;
  final SegmentCipherConfig? cipher;

  SegmentedAudioDescriptor({
    required this.initSegmentUrl,
    required this.segmentUrlTemplate,
    required this.segmentCount,
    this.container = 'flac',
    this.cipher,
  });

  factory SegmentedAudioDescriptor.fromMap(Map<String, dynamic> map) {
    return SegmentedAudioDescriptor(
      initSegmentUrl: map['initSegmentUrl']?.toString() ?? map['initUrl']?.toString() ?? '',
      segmentUrlTemplate: map['segmentUrlTemplate']?.toString() ?? map['segmentTemplate']?.toString() ?? '',
      segmentCount: (map['segmentCount'] as num?)?.toInt() ?? (map['nSegments'] as num?)?.toInt() ?? 0,
      container: map['container']?.toString() ?? 'flac',
      cipher: map['cipher'] is Map
          ? SegmentCipherConfig.fromMap((map['cipher'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'initSegmentUrl': initSegmentUrl,
        'segmentUrlTemplate': segmentUrlTemplate,
        'segmentCount': segmentCount,
        'container': container,
        if (cipher != null) 'cipher': cipher!.toMap(),
      };
}

/// The resolved playback stream URL, headers, and format details.
class AudioStreamResult {
  final String url;
  final Map<String, String>? headers;
  final String? format;
  final int? bitrate;
  final int? sampleRate;
  final int? bitDepth;
  final DateTime? expiresAt;
  final SegmentedAudioDescriptor? segmented;
  final Map<String, dynamic>? customData;

  AudioStreamResult({
    required this.url,
    this.headers,
    this.format,
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
    this.expiresAt,
    this.segmented,
    this.customData,
  });

  bool get isSegmented => segmented != null;
}

/// Base interface for modular audio streaming providers.
abstract class AudioSource {
  /// Unique identifier (e.g. 'youtube', 'qobuz', 'soundcloud').
  String get id;

  /// User-facing display name.
  String get name;

  /// Optional description.
  String? get description => null;

  /// Whether this source is compiled into the app or dynamically loaded via JS.
  bool get isBuiltIn => false;

  /// Default priority weight (higher number = tried first in cascade).
  int get priority => 0;

  /// Audio qualities delivered by this provider.
  Set<AudioQuality> get supportedQualities => {
        AudioQuality.standard,
        AudioQuality.high,
      };

  /// Initialize resources, background daemons, or runtimes.
  Future<void> initialize() async {}

  /// Search catalog for candidate audio tracks matching the query.
  Future<List<AudioTrackCandidate>> searchAudio(AudioSearchQuery query);

  /// Resolves the playable direct audio stream URL and necessary request headers.
  Future<AudioStreamResult> getStreamUrl(
    String mediaId, {
    AudioQuality? preferredQuality,
  });

  /// Dispose resources.
  void dispose() {}
}

