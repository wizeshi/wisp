// Copyright © 2026 wizeshi

library;

import 'package:wisp/data/sources/audio/audio_source.dart';

/// Structured telemetry detailing the resolved audio stream quality and source metadata.
class ActiveTrackQualityInfo {
  /// Provider that delivered this stream (e.g., 'qobuz', 'youtube').
  final String providerId;

  /// User-friendly provider display name.
  final String providerName;

  /// Quality tier requested or classified (e.g. lossless, hiRes, standard).
  final AudioQuality targetQuality;

  /// Concise badge label (e.g. 'Lossless', 'Hi-Res Lossless', 'High', 'Standard').
  final String label;

  /// Container or codec format (e.g. 'FLAC', 'AAC', 'OPUS', 'MP3').
  final String format;

  /// Source audio bit depth (e.g. 16 or 24), if known.
  final int? bitDepth;

  /// Source audio sampling rate in Hz (e.g. 44100, 96000), if known.
  final int? sampleRate;

  /// Nominal bitrate in kbps, if known.
  final int? bitrate;

  const ActiveTrackQualityInfo({
    required this.providerId,
    required this.providerName,
    required this.targetQuality,
    required this.label,
    required this.format,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
  });

  bool get isLossless =>
      (bitDepth != null && bitDepth! >= 16) ||
      format.toUpperCase() == 'FLAC' ||
      targetQuality == AudioQuality.lossless ||
      targetQuality == AudioQuality.hiRes;

  bool get isHiRes =>
      (bitDepth != null && bitDepth! > 16) ||
      (sampleRate != null && sampleRate! > 48000) ||
      targetQuality == AudioQuality.hiRes;

  /// Formatted bit depth and sample rate string for source stream (e.g. "24-bit / 96.0 kHz").
  String get sourceFidelitySpec {
    final parts = <String>[];
    if (bitDepth != null && bitDepth! > 0) {
      parts.add('$bitDepth-bit');
    }
    if (sampleRate != null && sampleRate! > 0) {
      final khz = (sampleRate! / 1000).toStringAsFixed(sampleRate! % 1000 == 0 ? 0 : 1);
      parts.add('$khz kHz');
    }
    return parts.isEmpty ? format.toUpperCase() : parts.join(' / ');
  }
  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'providerName': providerName,
        'targetQuality': targetQuality.name,
        'label': label,
        'format': format,
        if (bitDepth != null) 'bitDepth': bitDepth,
        if (sampleRate != null) 'sampleRate': sampleRate,
        if (bitrate != null) 'bitrate': bitrate,
      };

  factory ActiveTrackQualityInfo.fromJson(Map<String, dynamic> json) =>
      ActiveTrackQualityInfo(
        providerId: json['providerId'] as String? ?? 'cache',
        providerName: json['providerName'] as String? ?? 'Offline Cache',
        targetQuality: AudioQuality.fromString(json['targetQuality'] as String?),
        label: json['label'] as String? ?? 'Standard',
        format: json['format'] as String? ?? 'M4A',
        bitDepth: (json['bitDepth'] as num?)?.toInt(),
        sampleRate: (json['sampleRate'] as num?)?.toInt(),
        bitrate: (json['bitrate'] as num?)?.toInt(),
      );

  factory ActiveTrackQualityInfo.create({
    required String providerId,
    required String providerName,
    required AudioQuality targetQuality,
    String? format,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
  }) {
    final formatStr = (format ??
            (providerId.toLowerCase() == 'qobuz'
                ? 'FLAC'
                : (providerId.toLowerCase() == 'spotify' ? 'OGG' : 'M4A')))
        .toUpperCase();
    final isLossless = (bitDepth != null && bitDepth >= 16) || formatStr == 'FLAC';
    final isHiRes =
        (bitDepth != null && bitDepth > 16) || ((sampleRate ?? 0) > 48000);

    String label;
    if (isHiRes) {
      label = 'Hi-Res Lossless';
    } else if (isLossless) {
      label = 'Lossless';
    } else if (bitrate != null && bitrate >= 256) {
      label = 'High';
    } else {
      label = 'Standard';
    }

    return ActiveTrackQualityInfo(
      providerId: providerId,
      providerName: providerName,
      targetQuality: targetQuality,
      label: label,
      format: formatStr,
      bitDepth: bitDepth,
      sampleRate: sampleRate,
      bitrate: bitrate,
    );
  }

  /// Best-effort inference for legacy cached files that lack recorded quality metadata.
  factory ActiveTrackQualityInfo.inferFromCachedPath({
    required String filePath,
    String? trackId,
    String? videoId,
  }) {
    final lower = filePath.toLowerCase();
    String format = 'M4A';
    int? bitDepth;
    int? sampleRate;
    int? bitrate;
    AudioQuality quality = AudioQuality.standard;

    if (lower.endsWith('.flac')) {
      format = 'FLAC';
      bitDepth = 16;
      sampleRate = 44100;
      quality = AudioQuality.lossless;
    } else if (lower.endsWith('.ogg')) {
      format = 'OGG';
      bitrate = 160;
      quality = AudioQuality.high;
    } else if (lower.endsWith('.mp3')) {
      format = 'MP3';
      bitrate = 320;
      quality = AudioQuality.standard;
    } else if (lower.endsWith('.m4a') || lower.endsWith('.aac')) {
      format = 'AAC';
      bitrate = 128;
      quality = AudioQuality.standard;
    }

    // Infer provider from media identifiers or format
    final idToCheck = (videoId != null && videoId.isNotEmpty)
        ? videoId
        : (trackId ?? '');
    String providerId = 'cache';
    String providerName = 'Offline Cache';

    if (format == 'FLAC') {
      providerId = 'qobuz';
      providerName = 'Qobuz';
    } else if (format == 'OGG') {
      providerId = 'spotify';
      providerName = 'Spotify';
    } else if (format == 'AAC' || format == 'M4A' || idToCheck.length == 11) {
      providerId = 'youtube';
      providerName = 'YouTube';
    } else if (idToCheck.length == 22) {
      providerId = 'spotify';
      providerName = 'Spotify';
    }

    return ActiveTrackQualityInfo.create(
      providerId: providerId,
      providerName: providerName,
      targetQuality: quality,
      format: format,
      bitDepth: bitDepth,
      sampleRate: sampleRate,
      bitrate: bitrate,
    );
  }
}

