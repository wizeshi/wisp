/// YouTube audio streaming provider using youtube_explode_dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../services/ytdlp_manager.dart';
import '../../utils/logger.dart';

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

class YouTubeProvider {
  final YoutubeExplode _youtube = YoutubeExplode();
  static const _platform = MethodChannel('com.wizeshi.wisp/ytdlp');
  
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
        logger.i('[Audio/YouTube] Loaded ${_videoIdCache.length} cached video IDs');
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
      await prefs.setString('youtube_video_id_cache', json.encode(_videoIdCache));
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
    _videoIdCache = {
      ..._videoIdCache,
      ...map,
    };
    await _saveVideoIdCache();
  }
  
  /// Update YT-DLP binary on Android to latest version
  static Future<void> updateYtDlp({bool throwOnFailure = false}) async {
    if (!Platform.isAndroid) return;
    
    try {
      logger.i('[Audio/YouTube] Updating YT-DLP to latest version...');
      await _platform.invokeMethod('updateYtDlp');
      logger.i('[Audio/YouTube] ✓ YT-DLP updated successfully');
    } catch (e) {
      logger.w('[Audio/YouTube] Failed to update YT-DLP', error: e);
      if (throwOnFailure) {
        throw YouTubeException('Failed to update YT-DLP', e);
      }
    }
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
        final score = _scoreVideo(video, artist: artist, title: title, durationSecs: durationSecs);
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
      logger.i('[Audio/YouTube] Best match: ${bestMatch.title} (score: $bestScore)');
      
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
      if (e.toString().contains('network') || e.toString().contains('connection')) {
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
      }).toList();
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
  
  /// Get audio stream URL for a video ID using YT-DLP (desktop only)
  Future<String> _getStreamUrlViaYtDlp(String videoId) async {
    try {
      final execPath = await YtDlpManager.instance.ensureReady(
        notifyOnFailure: true,
      );
      if (execPath == null) {
        throw YouTubeException('YT-DLP is not available');
      }

      logger.d('[YouTube/YT-DLP] Using $execPath');
      logger.d('[YouTube/YT-DLP] Getting stream URL for video: $videoId');
      
      final result = await Process.run(
        execPath,
        [
          '-f', 'bestaudio[ext=m4a]/bestaudio',
          '--get-url',
          '--no-playlist',
          '--js-runtimes', 'node',
          'https://www.youtube.com/watch?v=$videoId',
        ],
      );
      
      if (result.exitCode != 0) {
        logger.e('[YouTube/YT-DLP] Error: ${result.stderr}');
        throw YouTubeException('YT-DLP failed: ${result.stderr}');
      }
      
      final url = (result.stdout as String).trim();
      logger.d('[YouTube/YT-DLP] ✓ Got stream URL (${url.length} chars):');
      
      // Print URL in 100-character chunks for easy copy-paste
      for (int i = 0; i < url.length; i += 100) {
        final end = (i + 100 < url.length) ? i + 100 : url.length;
        final chunkNum = (i ~/ 100) + 1;
        final totalChunks = (url.length / 100).ceil();
        logger.d('[YouTube/YT-DLP] URL [$chunkNum/$totalChunks]: ${url.substring(i, end)}');
      }
      
      return url;
    } catch (e) {
      logger.e('[YouTube/YT-DLP] Exception', error: e);
      throw YouTubeException('Failed to get stream URL via YT-DLP', e);
    }
  }

  Future<bool> isStreamUrlValid(String url) async {
    try {
      final response = await HttpClient().getUrl(Uri.parse(url)).then((req) => req.close());
      if (response.statusCode == 200) {
        return true;
      } else {
        logger.w('[YouTube] Stream URL returned status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      logger.w('[YouTube] Error checking stream URL validity', error: e);
      return false;
    }
  }

  /// Get audio stream URL for a video ID
  Future<String> getStreamUrl(String videoId) async {
    // On desktop: Try YT-DLP first (handles JS signature decryption)
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        return await _getStreamUrlViaYtDlp(videoId);
      } catch (e) {
        logger.w('[YouTube/YT-DLP] YT-DLP failed, falling back to youtube_explode_dart');
      }
    }
    
    // On Android: First try NewPipeExtractor, then YT-DLP.
    if (Platform.isAndroid) {
      logger.d("[YouTube/NewPipe] Attempting to get stream URL for video ID: $videoId");
      String streamURL = "";

      // Try first with NewPipeExtractor
      try {
        logger.d("[YouTube/NewPipe] Fetching stream URL for video ID: $videoId");
        String url = "https://www.youtube.com/watch?v=$videoId";
        YoutubeVideo video = await VideoExtractor.getStream(url);

        List<AudioOnlyStream> sortedStreams = List.from(video.audioOnlyStreams);
        sortedStreams.sort((a, b) => b.averageBitrate.compareTo(a.averageBitrate));

        String bestAudioUrl = video.audioWithBestAacQuality!.url ?? sortedStreams.first.url ?? "";

        logger.d("[YouTube/NewPipe] ✓ NewPipeExtractor succeeded for video ID: $videoId");

        await isStreamUrlValid(bestAudioUrl).then((isValid) {
          if (!isValid) {
            logger.w("[YouTube/NewPipe] Stream URL is invalid (403/404), falling back to YT-DLP");
            throw YouTubeException('Stream URL is invalid (403/404)');
          }

          streamURL = bestAudioUrl;
        });
      } catch (e) {
        logger.w("[YouTube/NewPipe] NewPipeExtractor failed, falling back to YT-DLP", error: e);
      
        try {
          logger.d('[YouTube/YT-DLP] Using youtubedl-android for video: $videoId');
          final String url =
              await _platform.invokeMethod('getStreamUrl', {'videoId': videoId});
          logger.d('[YouTube/YT-DLP] ✓ Got stream URL via YT-DLP (${url.length} chars)');

          streamURL = url;
        } on MissingPluginException catch (e) {
          logger.w(
            '[YouTube/YT-DLP] YT-DLP channel unavailable, falling back to youtube_explode_dart',
            error: e,
          );
        } on PlatformException catch (e) {
          String errorMsg = e.message ?? 'Unknown platform exception';

          if (errorMsg.contains("Video unavailable")) {
            // This means a previously cached video ID is no longer valid. Remove it from cache.
            logger.w('[YouTube/YT-DLP] Video is unavailable.');

            throw VideoUnavailableException('Video is unavailable', e);
          }
        } catch (e) {
          logger.w(
            '[YouTube/YT-DLP] Android YT-DLP failed, falling back to youtube_explode_dart',
            error: e,
          );
        }
      }

      const chunkSize = 200;
      for (int i = 0; i < streamURL.length; i += chunkSize) {
        final end = (i + chunkSize < streamURL.length) ? i + chunkSize : streamURL.length;
        logger.d(
          '[Audio/YouTube] URL part ${(i ~/ chunkSize) + 1}: ${streamURL.substring(i, end)}',
        );
      }

      await isStreamUrlValid(streamURL).then((isValid) {
        if (!isValid) {
          logger.w("[Audio/YouTube] Stream URL is invalid (403/404), retrying...");
          getStreamUrl(videoId);
        }
      });

      return streamURL;
    }
    
    // Fallback: Try multiple YouTube API clients
    final clientsToTry = [
      YoutubeApiClient.ios,
      YoutubeApiClient.android,
      YoutubeApiClient.androidVr,
    ];
    
    Exception? lastError;
    
    for (final client in clientsToTry) {
      try {
        final clientName = client.payload['context']['client']['clientName'];
        logger.d('[YouTube/YouTubeExplodeDart] Trying $clientName client for video: $videoId');
        
        final manifest = await _youtube.videos.streamsClient.getManifest(
          videoId,
          ytClients: [client],
          requireWatchPage: false,
        );
        
        final audioStreams = manifest.audioOnly.toList()
          ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
        
        if (audioStreams.isEmpty) {
          logger.d('[YouTube/YouTubeExplodeDart] $clientName: No audio streams, trying next...');
          continue;
        }
        
        final preferredStream = audioStreams.firstWhere(
          (s) => s.codec.mimeType.contains('webm') || s.codec.mimeType.contains('opus'),
          orElse: () => audioStreams.first,
        );
        
        final streamUrl = preferredStream.url.toString();
        logger.i('[YouTube/YouTubeExplodeDart] ✓ Success with $clientName - ${preferredStream.container}, ${preferredStream.bitrate}');
        
        return streamUrl;
      } catch (e) {
        logger.w("[YouTube/YouTubeExplodeDart] ${client.payload['context']['client']['clientName']} failed", error: e);
        lastError = e as Exception;
        continue;
      }
    }
    
    logger.e('[Audio/YouTube] ❌ All methods failed');
    throw YouTubeException('Failed to get stream URL', lastError);
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
    if (channelLower.contains('topic') || channelLower.contains('vevo') || channelLower.contains('official')) {
      score += 15.0; // Boosted for official channels
    }
    if (channelLower == artistLower || channelLower.contains(artistLower)) {
      score += 15.0; // Direct artist channel match
    }

    // Close "Title - Artist" match
    if (titleQueryLower.isNotEmpty && titleLower.contains(titleQueryLower)) {
      score += 5.0;
      // Exact match for title or exact 'Artist - Title' format
      if (titleLower == titleQueryLower || titleLower == '$artistLower - $titleQueryLower' || titleLower == '$titleQueryLower - $artistLower') {
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
    return {
      "error": "Provider not implemented"
    };
  }
  
  /// Dispose resources
  void dispose() {
    _youtube.close();
  }
}
