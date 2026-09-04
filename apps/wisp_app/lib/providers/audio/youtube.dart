// Copyright © 2026 wizeshi

/// YouTube audio streaming provider using youtube_explode_dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'package:wisp_newpipe_manager/services/android_extractor_delegate.dart';
import 'package:wisp_newpipe_manager/wisp_newpipe_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:wisp_ytdlp_manager/wisp_ytdlp_manager.dart';
import '../../utils/logger.dart';

enum YouTubeEngine {
  // ignore: constant_identifier_names
  YT_DLP,
  // ignore: constant_identifier_names
  NewPipeExtractor,
  // ignore: constant_identifier_names
  YouTubeKit,
  // ignore: constant_identifier_names
  YoutubeExplode,
}

class YouTubeException implements Exception {
  final String message;
  final dynamic originalError;

  YouTubeException(this.message, [this.originalError]);

  @override
  String toString() => 'YouTubeException: $message';
}

class VideoUnavailableException extends YouTubeException {
  VideoUnavailableException(super.message, [super.originalError]);
}

class NetworkException extends YouTubeException {
  NetworkException(super.message, [super.originalError]);
}

class SearchFailedException extends YouTubeException {
  SearchFailedException(super.message, [super.originalError]);
}

class YouTubeResult {
  final String videoId;
  final String title;
  final String channelName;
  final Duration duration;
  final String thumbnailUrl;
  final double score;

  YouTubeResult({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.duration,
    required this.thumbnailUrl,
    this.score = 0,
  });
}

class NativeAndroidNewPipeDelegate implements NewPipeAndroidDelegate {
  @override
  Future<String> getStreamUrl(String videoId, {Duration? timeout}) async {
    final url = 'https://www.youtube.com/watch?v=$videoId';
    final video = await VideoExtractor.getStream(url);

    final List<AudioOnlyStream> sortedStreams = List.from(video.audioOnlyStreams);
    sortedStreams.sort((a, b) => b.averageBitrate.compareTo(a.averageBitrate));

    final bestAudioUrl = video.audioWithBestAacQuality?.url ?? sortedStreams.first.url;
    if (bestAudioUrl == null || bestAudioUrl.isEmpty) {
      throw Exception('No audio streams available');
    }

    return bestAudioUrl;
  }
}

class YouTubeProvider {
  final YoutubeExplode _youtube = YoutubeExplode();
  static const _platform = MethodChannel('com.wizeshi.wisp/youtube');

  List<YouTubeEngine> preferredEngineOrder = [
    YouTubeEngine.YouTubeKit,
    YouTubeEngine.NewPipeExtractor,
    YouTubeEngine.YT_DLP,
    YouTubeEngine.YoutubeExplode,
  ];

  static void setEngineOrder(List<YouTubeEngine> newOrder) {
    YouTubeProvider().preferredEngineOrder = newOrder;
  }

  /// Client identity used for both stream validation and actual playback.
  /// Must stay in sync with the User-Agent used in WispAudioHandler
  /// (_getAudioSource) — a mismatch between the client that resolved the
  /// URL and the client that plays it can cause CDN rejections that look
  /// like silent playback failures rather than a clean 403.
  static String userAgentForPlatform() {
    if (Platform.isAndroid) {
      return 'com.google.android.youtube/19.29.37 (Linux; U; Android 14) gzip';
    }
    if (Platform.isIOS) {
      return 'com.google.ios.youtube/19.29.1 (iPhone; CPU iOS 17_0 like Mac OS X)';
    }
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
  }

  /// Cache for track ID -> YouTube video ID mapping
  static Map<String, String> _videoIdCache = {};
  static bool _cacheLoaded = false;

  /// Load video ID cache from SharedPreferences
  static Future<void> loadVideoIdCache() async {
    if (_cacheLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString('youtube_video_id_cache');
      if (cacheJson != null) {
        final Map<String, dynamic> cacheMap = json.decode(cacheJson);
        _videoIdCache = cacheMap.map((k, v) => MapEntry(k, v.toString()));
        logger.i(
          '[Audio/YouTube] Loaded ${_videoIdCache.length} cached video IDs',
        );
      }
      _cacheLoaded = true;
    } catch (e) {
      logger.e('[Audio/YouTube] Error loading video ID cache', error: e);
      _cacheLoaded = true;
    }
  }

  /// Save video ID cache to SharedPreferences
  static Future<void> _saveVideoIdCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'youtube_video_id_cache',
        json.encode(_videoIdCache),
      );
    } catch (e) {
      logger.e('[Audio/YouTube] Error saving video ID cache', error: e);
    }
  }

  /// Get cached video ID for a track
  static String? getCachedVideoId(String trackId) => _videoIdCache[trackId];

  /// Cache a video ID for a track
  static Future<void> cacheVideoId(String trackId, String videoId) async {
    _videoIdCache[trackId] = videoId;
    await _saveVideoIdCache();
  }

  /// Set a cached video ID for a track (alias for cacheVideoId)
  static Future<void> setCachedVideoId(String trackId, String videoId) async {
    await cacheVideoId(trackId, videoId);
  }

  /// Remove cached video ID for a track
  static Future<void> removeCachedVideoId(String trackId) async {
    _videoIdCache.remove(trackId);
    await _saveVideoIdCache();
  }

  /// Clears the entire video ID cache
  static Future<void> clearVideoIdCache() async {
    _videoIdCache.clear();
    await _saveVideoIdCache();
  }

  /// Returns a copy of the full track -> video ID cache.
  static Map<String, String> getVideoIdCacheSnapshot() {
    return Map<String, String>.from(_videoIdCache);
  }

  /// Merges provided track -> video ID mappings into the cache.
  static Future<void> mergeVideoIdCache(Map<String, String> map) async {
    if (map.isEmpty) return;
    _videoIdCache = {..._videoIdCache, ...map};
    await _saveVideoIdCache();
  }

  /// Search YouTube for a track by artist and title
  /// Returns the best matching result based on filtering criteria
  Future<YouTubeResult?> searchYouTube(
    String artist,
    String title, {
    int? durationSecs,
  }) async {
    try {
      final query = '$artist - $title';
      logger.d('[Audio/YouTube] Searching for: $query');

      final searchResults = await _youtube.search.search(query);

      if (searchResults.isEmpty) {
        logger.w('[Audio/YouTube] No results found for: $query');
        throw SearchFailedException('No results found for "$query"');
      }

      // Filter and score results
      final scoredResults = <MapEntry<Video, double>>[];

      var currentResults = searchResults;

      for (final result in currentResults) {
        final video = result;
        final score = _scoreVideo(
          video,
          artist: artist,
          title: title,
          durationSecs: durationSecs,
        );
        if (score == null) {
          logger.d('[Audio/YouTube] Excluded: ${video.title} (unwanted terms)');
          continue;
        }
        scoredResults.add(MapEntry(video, score));

        // Stop if we found 5 decent scores
        if (scoredResults.where((e) => e.value >= 10.0).length >= 5) {
          break;
        }
      }

      if (scoredResults.isEmpty) {
        logger.w('[Audio/YouTube] All results filtered out');
        throw SearchFailedException('No suitable results found for "$query"');
      }

      // Sort by score (highest first)
      scoredResults.sort((a, b) => b.value.compareTo(a.value));

      final bestMatch = scoredResults.first.key;
      final bestScore = scoredResults.first.value;
      logger.i(
        '[Audio/YouTube] Best match: ${bestMatch.title} (score: $bestScore)',
      );

      return YouTubeResult(
        videoId: bestMatch.id.value,
        title: bestMatch.title,
        channelName: bestMatch.author,
        duration: bestMatch.duration ?? Duration.zero,
        thumbnailUrl: bestMatch.thumbnails.highResUrl,
        score: bestScore,
      );
    } catch (e) {
      if (e is YouTubeException) rethrow;

      logger.e('[Audio/YouTube] Search error', error: e);
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        throw NetworkException('Network error during search', e);
      }
      throw SearchFailedException('Failed to search YouTube', e);
    }
  }

  /// Search YouTube for tracks using a raw query
  /// Returns sorted results using the same scoring rules
  Future<List<YouTubeResult>> searchYouTubeTracks(
    String query, {
    int limit = 10,
    String? artist,
    String? title,
    int? durationSecs,
  }) async {
    try {
      logger.d('[Audio/YouTube] Searching tracks for: $query');

      final searchResults = await _youtube.search.search(query);
      if (searchResults.isEmpty) {
        logger.w('[Audio/YouTube] No results found for: $query');
        return [];
      }

      final videosWithScores = <MapEntry<Video, double>>[];

      for (final video in searchResults) {
        final score = _scoreVideo(
          video,
          artist: artist ?? '',
          title: title ?? query,
          durationSecs: durationSecs,
        );
        videosWithScores.add(MapEntry(video, score ?? 0));
      }

      final videosSortedByScore = videosWithScores..sort((a, b) => b.value.compareTo(a.value));

      return videosSortedByScore.take(limit).map((entry) {
        final video = entry.key;
        return YouTubeResult(
          videoId: video.id.value,
          title: video.title,
          channelName: video.author,
          duration: video.duration ?? Duration.zero,
          thumbnailUrl: video.thumbnails.highResUrl,
          score: entry.value,
        );
      }).toList();
      /* logger.d('[Audio/YouTube] Searching tracks for: $query');

      final searchResults = await _youtube.search.search(query);
      if (searchResults.isEmpty) return [];

      final scoredResults = <MapEntry<Video, double>>[];
      for (final result in searchResults) {
        final video = result;
        final score = _scoreVideo(
          video,
          artist: artist ?? '',
          title: title ?? query,
          durationSecs: durationSecs,
        );
        if (score == null) {
          continue;
        }
        scoredResults.add(MapEntry(video, score));
      }

      if (scoredResults.isEmpty) return [];

      scoredResults.sort((a, b) => b.value.compareTo(a.value));
      return scoredResults.take(limit).map((entry) {
        final video = entry.key;
        return YouTubeResult(
          videoId: video.id.value,
          title: video.title,
          channelName: video.author,
          duration: video.duration ?? Duration.zero,
          thumbnailUrl: video.thumbnails.highResUrl,
          score: entry.value,
        );
      }).toList(); */
    } catch (e) {
      if (e is YouTubeException) rethrow;
      logger.e('[Audio/YouTube] Search error', error: e);
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        throw NetworkException('Network error during search', e);
      }
      throw SearchFailedException('Failed to search YouTube', e);
    }
  }

  Future<bool> isStreamUrlValid(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final effectiveHeaders =
          headers ?? {'User-Agent': userAgentForPlatform()};
      final response = await HttpClient().getUrl(Uri.parse(url)).then((req) {
        effectiveHeaders.forEach((key, value) => req.headers.set(key, value));
        return req.close();
      });
      if (response.statusCode == 200) {
        return true;
      } else {
        logger.w(
          '[YouTube] Stream URL returned status code: ${response.statusCode}',
        );
        return false;
      }
    } catch (e) {
      logger.w('[YouTube] Error checking stream URL validity', error: e);
      return false;
    }
  }

  /// Get audio stream URL for a video ID
  Future<String> getStreamUrl(String videoId) async {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    final isNewPipeDesktopAvaliable =
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    final isYouTubeKitAvailable = Platform.isIOS /* || TODO Platform.isMacOS */;
    final isNewPipeAvailable = Platform.isAndroid || isNewPipeDesktopAvaliable;

    final isYTDLPAvailable =
        Platform.isLinux ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isAndroid;

    for (YouTubeEngine engine in preferredEngineOrder) {
      String streamURL = '';

      switch (engine) {
        case YouTubeEngine.YouTubeKit:
          if (!isYouTubeKitAvailable) {
            break;
          }

          logger.d(
            '[YouTube/YouTubeKit] Attempting to get stream URL for video ID: $videoId',
          );
          try {
            final url = await _getStreamUrlUsingYoutubeKitIOS(videoId);

            const chunkSize = 200;
            for (int i = 0; i < url.length; i += chunkSize) {
              final end = (i + chunkSize < url.length)
                  ? i + chunkSize
                  : url.length;
              logger.d(
                '[YouTube/YouTubeKit] URL part ${(i ~/ chunkSize) + 1}: ${url.substring(i, end)}',
              );
            }

            streamURL = url;
          } catch (e) {
            logger.w('[YouTube/YouTubeKit] YouTubeKit failed.', error: e);
          }

          break;
        case YouTubeEngine.NewPipeExtractor:
          if (!isNewPipeAvailable) {
            break;
          }

          if (isDesktop) {
            try {
              streamURL = await _getStreamUrlUsingNewPipeDesktop(videoId);
            } catch (e) {
              logger.w(
                "[YouTube/NewPipe] NewPipeExtractor (desktop) failed, falling back",
                error: e,
              );
            }
          } else {
            try {
              streamURL = await _getStreamUrlUsingNewPipeAndroid(videoId);
            } catch (e) {
              logger.w(
                "[YouTube/NewPipe] NewPipeExtractor failed, falling back to YT-DLP",
                error: e,
              );
            }
          }

          break;
        case YouTubeEngine.YT_DLP:
          if (!isYTDLPAvailable) {
            break;
          }

          WispYtdlpManager.instance.ensureReady();

          logger.d(
            '[YouTube/YT-DLP] Attempting to get stream URL for video ID: $videoId',
          );
          try {
            final url = await WispYtdlpManager.instance.getStreamUrl(videoId);
            streamURL = url;
            logger.d(
              '[YouTube/YT-DLP] ✓ Got stream URL via YT-DLP (${streamURL.length} chars)',
            );
          } on MissingPluginException catch (e) {
            logger.w('[YouTube/YT-DLP] YT-DLP channel unavailable.', error: e);
          } on PlatformException catch (e) {
            String errorMsg = e.message ?? 'Unknown platform exception';

            if (errorMsg.contains("Video unavailable")) {
              // This means a previously cached video ID is no longer valid. Remove it from cache.
              logger.w('[YouTube/YT-DLP] Video is unavailable.');

              throw VideoUnavailableException('Video is unavailable', e);
            }
          } catch (e) {
            logger.w('[YouTube/YT-DLP] YT-DLP failed.', error: e);
          }

          break;
        case YouTubeEngine.YoutubeExplode:
          try {
            streamURL = await _getStreamUrlUsingYoutubeExplode(videoId);
          } catch (e) {
            logger.w('[YouTube/Explode] Fallback failed', error: e);
          }

          break;
      }

      if (streamURL.isNotEmpty) {
        if (!await isStreamUrlValid(streamURL)) {
          logger.w(
            "[YouTube] Stream URL from $engine is invalid (403/404), trying next engine...",
          );
          continue;
        }
        return streamURL;
      }
    }

    logger.e('[Audio/YouTube] ❌ All methods failed');
    throw YouTubeException('Failed to get stream URL');
  }

  Future<String> _getStreamUrlUsingNewPipeAndroid(String videoID) async {
    String streamURL = "";

    logger.d("[YouTube/NewPipe] Fetching stream URL for video ID: $videoID");
    try {
      final url = await NewPipeManager.instance.getStreamUrl(videoID);

      await isStreamUrlValid(url).then((isValid) {
        if (!isValid) {
          logger.w(
            "[YouTube/NewPipe] Stream URL is invalid (403/404), falling back to YT-DLP",
          );
          throw YouTubeException('Stream URL is invalid (403/404)');
        }
        streamURL = url;
      });

      logger.d(
        "[YouTube/NewPipe] ✓ NewPipeExtractor succeeded for video ID: $videoID",
      );
      logger.d(
        "[YouTube/NewPipe] ✓ Got stream URL via NewPipeExtractor (${streamURL.length} chars)",
      );

      return streamURL;
    } catch (e) {
      logger.w("[YouTube/NewPipe] NewPipeExtractor failed", error: e);
      rethrow;
    }
  }

  Future<String> _getStreamUrlUsingNewPipeDesktop(String videoID) async {
    logger.d(
      "[YouTube/NewPipe] (desktop) Fetching stream URL for video ID: $videoID",
    );

    try {
      final bestAudioUrl = await NewPipeManager.instance.getStreamUrl(videoID);

      if (!await isStreamUrlValid(bestAudioUrl)) {
        logger.w("[YouTube/NewPipe] (desktop) Stream URL is invalid (403/404)");
        throw YouTubeException('Stream URL is invalid (403/404)');
      }

      logger.d(
        "[YouTube/NewPipe] (desktop) ✓ Got stream URL via daemon (${bestAudioUrl.length} chars)",
      );
      return bestAudioUrl;
    } catch (e) {
      logger.w("[YouTube/NewPipe] (desktop) failed", error: e);
      rethrow;
    }
  }

  Future<String> _getStreamUrlUsingYoutubeKitIOS(String videoID) async {
    logger.d("[YouTube/YouTubeKit] Fetching stream URL for video ID: $videoID");
    final String url = await _platform.invokeMethod(
      'getStreamUrlYoutubeKitIOS',
      {'videoId': videoID},
    );
    logger.d(
      '[YouTube/YouTubeKit] ✓ Got stream URL via YouTubeKit (${url.length} chars)',
    );
    return url;
  }

  Future<String> _getStreamUrlUsingYoutubeExplode(String videoId) async {
    try {
      logger.d('[YouTube/Explode] Fetching manifest for video ID: $videoId');
      final manifest = await _youtube.videos.streamsClient.getManifest(
        videoId,
        ytClients: [
          YoutubeApiClient.androidSdkless,
          YoutubeApiClient.ios,
          YoutubeApiClient.safari,
        ],
      );

      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) {
        throw YouTubeException(
          'No audio-only streams available for video: $videoId',
        );
      }

      // Streams are merged across clients, so the single highest-bitrate pick
      // could still belong to a client that 403s. Walk the sorted list and
      // return the first one that actually resolves.
      final sortedStreams = audioStreams.sortByBitrate().reversed.toList();
      for (final stream in sortedStreams) {
        final url = stream.url.toString();
        if (await isStreamUrlValid(url)) {
          logger.d('[YouTube/Explode] ✓ Got stream URL (${url.length} chars)');
          return url;
        }
        logger.w(
          '[YouTube/Explode] Stream candidate returned non-200, trying next',
        );
      }

      throw YouTubeException(
        'All audio-only stream candidates returned non-200 for video: $videoId',
      );
    } catch (e) {
      logger.e('[YouTube/Explode] Failed to get stream URL', error: e);
      throw YouTubeException(
        'Failed to get stream URL via youtube_explode_dart',
        e,
      );
    }
  }

  /// Check if text contains excluded terms unless they are in the query.
  bool _containsExcludedTerms(
    String text,
    String originalQuery,
    List<String> excludedTerms,
  ) {
    final originalQueryLower = originalQuery.toLowerCase();

    return excludedTerms.any((term) {
      if (text.contains(term)) {
        return !originalQueryLower.contains(term);
      }
      return false;
    });
  }

  String _extractDescription(Video video) {
    try {
      final dynamic dynamicVideo = video;
      final description = dynamicVideo.description;
      if (description == null) return '';
      return description.toString().toLowerCase();
    } catch (_) {
      return '';
    }
  }

  int _maxAllowedDurationDiff(int durationSecs) {
    final relativeDiff = (durationSecs * 0.12).round();
    if (relativeDiff < 20) return 20;
    if (relativeDiff > 45) return 45;
    return relativeDiff;
  }

  static const List<String> _excludedTitleTerms = [
    'live',
    'concert',
    'cover',
    'remix',
    'karaoke',
    'instrumental',
    'acoustic',
    'piano version',
    'guitar',
    'reaction',
    'tutorial',
    'lesson',
    'how to',
    '8d',
    'edit',
    'lyrics',
    'lyric',
  ];

  static const List<String> _excludedDescriptionTerms = [
    'live performance',
    'performed live',
    'recorded live',
    'live at',
    'performing at',
    'perform',
  ];

  double? _scoreVideo(
    Video video, {
    required String artist,
    required String title,
    int? durationSecs,
  }) {
    double score = 0.0;

    final titleLower = video.title.toLowerCase();
    final descriptionLower = _extractDescription(video);
    final channelLower = video.author.toLowerCase();
    final artistLower = artist.trim().toLowerCase();
    final titleQueryLower = title.trim().toLowerCase();

    if (_containsExcludedTerms(
      titleLower,
      titleQueryLower,
      _excludedTitleTerms,
    )) {
      return null;
    }

    if (_containsExcludedTerms(
      descriptionLower,
      titleQueryLower,
      _excludedDescriptionTerms,
    )) {
      return null;
    }

    if (titleLower.contains('audio')) score += 5.0;
    if (titleLower.contains('official audio')) score += 10.0;
    if (titleLower.contains('official')) score += 3.0;

    // Official channel check
    if (channelLower.contains('topic') ||
        channelLower.contains('vevo') ||
        channelLower.contains('official')) {
      score += 15.0; // Boosted for official channels
    }
    if (channelLower == artistLower || channelLower.contains(artistLower)) {
      score += 15.0; // Direct artist channel match
    }

    // Close "Title - Artist" match
    if (titleQueryLower.isNotEmpty && titleLower.contains(titleQueryLower)) {
      score += 5.0;
      // Exact match for title or exact 'Artist - Title' format
      if (titleLower == titleQueryLower ||
          titleLower == '$artistLower - $titleQueryLower' ||
          titleLower == '$titleQueryLower - $artistLower') {
        score += 10.0;
      }
    }
    if (artistLower.isNotEmpty && titleLower.contains(artistLower)) {
      score += 5.0;
    }

    if (titleLower.contains(' - ')) score += 3.0;

    // Duration match check
    if (durationSecs != null && video.duration != null) {
      final videoDurationSecs = video.duration!.inSeconds;
      final diff = (videoDurationSecs - durationSecs).abs();
      final maxAllowedDiff = _maxAllowedDurationDiff(durationSecs);
      if (diff > maxAllowedDiff) {
        return null;
      }

      if (diff <= 5) {
        score += 15.0; // Very close duration
      } else if (diff <= 15) {
        score += 8.0; // Reasonably close duration
      } else if (diff <= 30) {
        score += 3.0;
      }
    }

    return score;
  }

  Map<String, dynamic> dumpJson() {
    logger.d("[Audio/YouTube] dumpJson not implemented.");
    return {"error": "Provider not implemented"};
  }

  /// Dispose resources
  void dispose() {
    _youtube.close();
    unawaited(NewPipeManager.instance.dispose());
    unawaited(WispYtdlpManager.instance.dispose());
  }
}
