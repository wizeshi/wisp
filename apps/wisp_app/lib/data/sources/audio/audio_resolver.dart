// Copyright © 2026 wizeshi

library;

import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/cache/audio/audio_mapping_store.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/audio/audio_source.dart';
import 'package:wisp/data/sources/audio/audio_source_manager.dart';
import 'package:wisp/data/sources/metadata/metadata_source_manager.dart';
import 'package:wisp/features/settings/state/preferences_provider.dart';

/// Successful resolution bundle linking track canonical key to active audio stream.
class AudioResolvedStream {
  final String providerId;
  final String mediaId;
  final AudioStreamResult stream;
  final String canonicalKey;

  AudioResolvedStream({
    required this.providerId,
    required this.mediaId,
    required this.stream,
    required this.canonicalKey,
  });
}

/// Central coordinator for cascading audio track search, resolution, and caching.
class AudioResolver {
  static final AudioResolver instance = AudioResolver._();
  AudioResolver._();

  final AudioSourceManager _sourceManager = AudioSourceManager.instance;
  final AudioMappingStore _mappingStore = AudioMappingStore.instance;

  /// Resolves an audio stream for [track] across registered audio providers.
  ///
  /// Cascade priority:
  /// 1. If a manual override mapping exists for any enabled provider, attempts that first.
  /// 2. If existing mapped providers exist in [AudioMappingStore], attempts them in priority order.
  /// 3. Searches enabled providers in user priority order, selecting the highest-confidence candidate.
  Future<AudioResolvedStream?> resolveTrack(
    GenericSong track, {
    PreferencesProvider? preferences,
    AudioQuality? preferredQuality,
  }) async {
    final artistNames = track.artists.map((a) => a.name).toList();
    final canonicalKey = AudioMappingStore.canonicalKey(
      title: track.title,
      artists: artistNames,
    );

    final effectiveQuality =
        preferredQuality ?? preferences?.preferredAudioQuality ?? AudioQuality.auto;

    final orderedSources = _sourceManager.getOrderedSources(preferences);
    if (orderedSources.isEmpty) {
      logger.w('[AudioResolver] No audio providers currently enabled');
      return null;
    }

    final mappings = _mappingStore.getMappings(canonicalKey);

    // 1. Check for manual overrides first
    final manualOverride = mappings.where((m) => m.manualOverride).firstOrNull;
    if (manualOverride != null) {
      final overrideSource = orderedSources
          .where((s) => s.id == manualOverride.providerID)
          .firstOrNull;
      if (overrideSource != null) {
        try {
          logger.d(
            '[AudioResolver] Resolving manual override: ${overrideSource.id} (${manualOverride.mediaID})',
          );
          final stream = await overrideSource.getStreamUrl(
            manualOverride.mediaID,
            preferredQuality: effectiveQuality,
          );
          return AudioResolvedStream(
            providerId: overrideSource.id,
            mediaId: manualOverride.mediaID,
            stream: stream,
            canonicalKey: canonicalKey,
          );
        } catch (e) {
          logger.w(
            '[AudioResolver] Manual override stream failed for ${overrideSource.id}: $e',
          );
        }
      }
    }

    // Attempt on-demand ISRC retrieval if source has ISRC capability (e.g. Spotify)
    String? trackIsrc;
    if (track.source.toLowerCase() == 'spotify' && track.id.isNotEmpty) {
      try {
        final metaSource = MetadataSourceManager.instance.sources['spotify'];
        if (metaSource != null) {
          trackIsrc = await metaSource.getTrackIsrc(track.id);
          if (trackIsrc != null && trackIsrc.isNotEmpty) {
            logger.d('[AudioResolver] Resolved ISRC on-demand for "${track.title}": $trackIsrc');
          }
        }
      } catch (e) {
        logger.d('[AudioResolver] On-demand ISRC lookup skipped: $e');
      }
    }

    // 2. Cascade through providers according to priority order
    final query = AudioSearchQuery(
      title: track.title,
      artists: artistNames,
      album: track.album?.title,
      durationSecs: track.durationSecs,
      isrc: trackIsrc,
      trackId: track.id,
      metadataSource: track.source,
    );

    for (final source in orderedSources) {
      // Check if we already have a cached mapping for this provider
      final existingMapping = mappings
          .where((m) => m.providerID == source.id)
          .firstOrNull;

      if (existingMapping != null && existingMapping.mediaID.isNotEmpty) {
        try {
          logger.d(
            '[AudioResolver] Using cached mapping for ${source.id} (${existingMapping.mediaID})',
          );
          final stream = await source.getStreamUrl(
            existingMapping.mediaID,
            preferredQuality: effectiveQuality,
          );
          return AudioResolvedStream(
            providerId: source.id,
            mediaId: existingMapping.mediaID,
            stream: stream,
            canonicalKey: canonicalKey,
          );
        } catch (e) {
          logger.w(
            '[AudioResolver] Stream resolution failed for cached ${source.id} item: $e',
          );
          // Fall through to re-search or try next provider
        }
      }

      // Query the provider catalog
      try {
        logger.d('[AudioResolver] Searching ${source.id} for "${track.title}"');
        final candidates = await source.searchAudio(query);
        if (candidates.isEmpty) continue;

        // Choose best candidate (highest score, or first)
        final bestMatch = candidates.first;
        logger.i(
          '[AudioResolver] Matched candidate on ${source.id}: ${bestMatch.title} (${bestMatch.mediaId})',
        );

        final stream = await source.getStreamUrl(
          bestMatch.mediaId,
          preferredQuality: effectiveQuality,
        );

        // Store resolution in canonical store
        await _mappingStore.setMapping(
          canonicalKey,
          AudioMappingItem(
            providerID: source.id,
            mediaID: bestMatch.mediaId,
            manualOverride: false,
          ),
        );

        return AudioResolvedStream(
          providerId: source.id,
          mediaId: bestMatch.mediaId,
          stream: stream,
          canonicalKey: canonicalKey,
        );
      } catch (e) {
        logger.w('[AudioResolver] Provider ${source.id} resolution failed: $e');
        continue;
      }
    }

    logger.w('[AudioResolver] All audio providers failed for "${track.title}"');
    return null;
  }
}

