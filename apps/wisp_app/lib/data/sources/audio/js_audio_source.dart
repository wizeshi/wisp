// Copyright © 2026 wizeshi

library;

import 'dart:async';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/sources/audio/audio_source.dart';
import 'package:wisp/data/sources/providers/shared_js_runtime.dart';

/// A modular audio source running inside the shared sandboxed JavaScript runtime.
class JsAudioSource extends AudioSource {
  @override
  final String id;

  @override
  final String name;

  @override
  final String? description;

  @override
  final bool isBuiltIn;

  @override
  final Set<AudioQuality> supportedQualities;

  @override
  final int priority;

  final String? serviceId;
  final String script;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  JsAudioSource({
    required this.id,
    required this.name,
    this.description,
    this.isBuiltIn = false,
    this.supportedQualities = const {
      AudioQuality.standard,
      AudioQuality.high,
    },
    this.priority = 0,
    this.serviceId,
    required this.script,
  });

  @override
  Future<void> initialize() async {
    // Eager runtime creation is replaced with lazy evaluation in SharedJsRuntime.
    _isInitialized = true;
  }

  Future<void> _ensureLoaded() async {
    await SharedJsRuntime.instance.loadProvider(
      id: id,
      name: name,
      script: script,
      serviceId: serviceId,
      type: 'audio',
    );
  }


  @override
  Future<List<AudioTrackCandidate>> searchAudio(AudioSearchQuery query) async {
    await _ensureLoaded();

    final queryMap = {
      'title': query.title,
      'artists': query.artists,
      'artist': query.artistNames,
      'album': query.album,
      'durationSecs': query.durationSecs,
      'isrc': query.isrc,
      'trackId': query.trackId,
      'metadataSource': query.metadataSource,
    };

    try {
      final raw = await SharedJsRuntime.instance.searchAudio(id, queryMap);
      final rawList = raw is List ? raw : [];
      return rawList
          .whereType<Map>()
          .map((item) {
            final m = item.cast<String, dynamic>();
            final durationMs = (m['durationMs'] as num?)?.toInt();
            final durationSecs = (m['durationSecs'] as num?)?.toInt() ??
                (durationMs != null ? durationMs ~/ 1000 : 0);
            return AudioTrackCandidate(
              mediaId: m['id']?.toString() ?? m['mediaId']?.toString() ?? '',
              providerId: id,
              title: m['title']?.toString() ?? '',
              artist: m['artist']?.toString() ?? '',
              album: m['album']?.toString(),
              duration: Duration(seconds: durationSecs),
              thumbnailUrl: m['thumbnailUrl']?.toString() ?? m['thumbnail_url']?.toString(),
              qualityLabel: m['quality']?.toString() ?? m['qualityLabel']?.toString(),
              score: (m['score'] as num?)?.toDouble() ?? 0.0,
            );
          })
          .where((c) => c.mediaId.isNotEmpty)
          .toList();
    } catch (e) {
      logger.w('[JsAudioSource/$id] Search error: $e');
      return [];
    }
  }

  @override
  Future<AudioStreamResult> getStreamUrl(
    String mediaId, {
    AudioQuality? preferredQuality,
  }) async {
    await _ensureLoaded();

    final optionsMap = {
      'preferredQuality': preferredQuality?.name ?? AudioQuality.auto.name,
    };

    try {
      final raw = await SharedJsRuntime.instance.getStreamUrl(id, mediaId, optionsMap);
      if (raw is Map) {
        final res = raw.cast<String, dynamic>();
        final headers = (res['headers'] as Map?)?.cast<String, String>();
        DateTime? expiresAt;
        if (res['expiresAt'] != null) {
          expiresAt = DateTime.tryParse(res['expiresAt'].toString());
        }
        final segmentedMap = res['segmented'] as Map?;
        final segmented = segmentedMap != null
            ? SegmentedAudioDescriptor.fromMap(segmentedMap.cast<String, dynamic>())
            : null;
        return AudioStreamResult(
          url: res['url']?.toString() ?? '',
          headers: headers,
          format: res['format']?.toString(),
          bitrate: (res['bitrate'] as num?)?.toInt(),
          sampleRate: (res['sampleRate'] as num?)?.toInt(),
          bitDepth: (res['bitDepth'] as num?)?.toInt(),
          expiresAt: expiresAt,
          segmented: segmented,
          customData: (res['customData'] as Map?)?.cast<String, dynamic>(),
        );
      }
      throw Exception('No stream result returned from provider $id');
    } catch (e) {
      logger.e('[JsAudioSource/$id] Stream resolution error: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    SharedJsRuntime.instance.unloadProvider(id, type: 'audio');
    _isInitialized = false;
  }
}

