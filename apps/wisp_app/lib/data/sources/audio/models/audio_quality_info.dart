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
}

