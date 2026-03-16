/// YouTube audio streaming provider using youtube_explode_dart
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
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
        logger.i('[YouTube] Loaded ${_videoIdCache.length} cached video IDs');
      }
      _cacheLoaded = true;
    } catch (e) {
      logger.e('[YouTube] Error loading video ID cache', error: e);
      _cacheLoaded = true;
    }
  }
  
  /// Save video ID cache to SharedPreferences
  static Future<void> _saveVideoIdCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('youtube_video_id_cache', json.encode(_videoIdCache));
    } catch (e) {
      logger.e('[YouTube] Error saving video ID cache', error: e);
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
  
  /// Update yt-dlp binary on Android to latest version
  static Future<void> updateYtDlp() async {
    if (!Platform.isAndroid) return;
    
    try {
      logger.i('[YouTube] Updating yt-dlp to latest version...');
      await _platform.invokeMethod('updateYtDlp');
      logger.i('[YouTube] ✓ yt-dlp updated successfully');
    } catch (e) {
      logger.w('[YouTube] Failed to update yt-dlp', error: e);
      // Don't throw - continue with existing version
    }
  }
  
  /// Search YouTube for a track by artist and title
  /// Returns the best matching result based on filtering criteria
  Future<YouTubeResult?> searchYouTube(String artist, String title) async {
    try {
      final query = '$artist - $title';
      logger.d('[YouTube] Searching for: $query');
      
      final searchResults = await _youtube.search.search(query);
      
      if (searchResults.isEmpty) {
        logger.w('[YouTube] No results found for: $query');
        throw SearchFailedException('No results found for "$query"');
      }
      
      // Filter and score results
      final scoredResults = <MapEntry<Video, double>>[];
      
      for (final result in searchResults) {
        final video = result;
        final score = _scoreVideo(video, artist: artist, title: title);
        if (score == null) {
          logger.d('[YouTube] Excluded: ${video.title} (unwanted terms)');
          continue;
        }
        scoredResults.add(MapEntry(video, score));
      }
      
      if (scoredResults.isEmpty) {
        logger.w('[YouTube] All results filtered out');
        throw SearchFailedException('No suitable results found for "$query"');
      }
      
      // Sort by score (highest first)
      scoredResults.sort((a, b) => b.value.compareTo(a.value));
      
      final bestMatch = scoredResults.first.key;
      final bestScore = scoredResults.first.value;
      logger.i('[YouTube] Best match: ${bestMatch.title} (score: $bestScore)');
      
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
      
      logger.e('[YouTube] Search error', error: e);
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
  }) async {
    try {
      logger.d('[YouTube] Searching tracks for: $query');

      final searchResults = await _youtube.search.search(query);
      if (searchResults.isEmpty) return [];

      final scoredResults = <MapEntry<Video, double>>[];
      for (final result in searchResults) {
        final video = result;
        final score = _scoreVideo(video, artist: '', title: query);
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
      logger.e('[YouTube] Search error', error: e);
      if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        throw NetworkException('Network error during search', e);
      }
      throw SearchFailedException('Failed to search YouTube', e);
    }
  }
  
  /// Get audio stream URL for a video ID using yt-dlp (desktop only)
  Future<String> _getStreamUrlViaYtDlp(String videoId) async {
    try {
      final execPath = await YtDlpManager.instance.ensureReady(
        notifyOnFailure: true,
      );
      if (execPath == null) {
        throw YouTubeException('yt-dlp is not available');
      }

      logger.d('[yt-dlp] Using $execPath');
      logger.d('[yt-dlp] Getting stream URL for video: $videoId');
      
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
        logger.e('[yt-dlp] Error: ${result.stderr}');
        throw YouTubeException('yt-dlp failed: ${result.stderr}');
      }
      
      final url = (result.stdout as String).trim();
      logger.d('[yt-dlp] ✓ Got stream URL (${url.length} chars):');
      
      // Print URL in 100-character chunks for easy copy-paste
      for (int i = 0; i < url.length; i += 100) {
        final end = (i + 100 < url.length) ? i + 100 : url.length;
        final chunkNum = (i ~/ 100) + 1;
        final totalChunks = (url.length / 100).ceil();
        logger.d('[yt-dlp] URL [$chunkNum/$totalChunks]: ${url.substring(i, end)}');
      }
      
      return url;
    } catch (e) {
      logger.e('[yt-dlp] Exception', error: e);
      throw YouTubeException('Failed to get stream URL via yt-dlp', e);
    }
  }

  /// Get audio stream URL for a video ID
  Future<String> getStreamUrl(String videoId) async {
    // On desktop: Try yt-dlp first (handles JS signature decryption)
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        return await _getStreamUrlViaYtDlp(videoId);
      } catch (e) {
        logger.w('[YouTube] yt-dlp failed, falling back to youtube_explode_dart');
      }
    }
    
    // On Android: Use youtubedl-android via platform channel
    if (Platform.isAndroid) {
      try {
        logger.d('[YouTube] Using youtubedl-android for video: $videoId');
        final String url =
            await _platform.invokeMethod('getStreamUrl', {'videoId': videoId});
        logger.d('[YouTube] Dart side URL length: ${url.length}');

        // Print URL in chunks to avoid truncation
        const chunkSize = 200;
        for (int i = 0; i < url.length; i += chunkSize) {
          final end = (i + chunkSize < url.length) ? i + chunkSize : url.length;
          logger.d(
            '[YouTube] URL part ${(i ~/ chunkSize) + 1}: ${url.substring(i, end)}',
          );
        }

        return url;
      } on MissingPluginException catch (e) {
        logger.w(
          '[YouTube] ytdlp channel unavailable, falling back to youtube_explode_dart',
          error: e,
        );
      } catch (e) {
        logger.w(
          '[YouTube] Android yt-dlp failed, falling back to youtube_explode_dart',
          error: e,
        );
      }
    }
    
    // Fallback: Try multiple YouTube API clients
    final clientsToTry = [
      YoutubeApiClient.ios,
      YoutubeApiClient.android,
      YoutubeApiClient.tvSimplyEmbedded,
      YoutubeApiClient.androidVr,
    ];
    
    Exception? lastError;
    
    for (final client in clientsToTry) {
      try {
        final clientName = client.payload['context']['client']['clientName'];
        logger.d('[YouTube] Trying $clientName client for video: $videoId');
        
        final manifest = await _youtube.videos.streamsClient.getManifest(
          videoId,
          ytClients: [client],
          requireWatchPage: false,
        );
        
        final audioStreams = manifest.audioOnly.toList()
          ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
        
        if (audioStreams.isEmpty) {
          logger.d('[YouTube] $clientName: No audio streams, trying next...');
          continue;
        }
        
        final preferredStream = audioStreams.firstWhere(
          (s) => s.codec.mimeType.contains('webm') || s.codec.mimeType.contains('opus'),
          orElse: () => audioStreams.first,
        );
        
        final streamUrl = preferredStream.url.toString();
        logger.i('[YouTube] ✓ Success with $clientName - ${preferredStream.container}, ${preferredStream.bitrate}');
        
        return streamUrl;
      } catch (e) {
        logger.w("[YouTube] ${client.payload['context']['client']['clientName']} failed", error: e);
        lastError = e as Exception;
        continue;
      }
    }
    
    logger.e('[YouTube] ❌ All methods failed');
    throw YouTubeException('Failed to get stream URL', lastError);
  }
  
  /// Check if title contains excluded terms
  bool _containsExcludedTerms(String title) {
    const excludedTerms = [
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
      '8D',
      'edit',
    ];
    
    return excludedTerms.any((term) => title.contains(term));
  }

  double? _scoreVideo(
    Video video, {
    required String artist,
    required String title,
  }) {
    double score = 0.0;

    final titleLower = video.title.toLowerCase();
    final channelLower = video.author.toLowerCase();
    final artistLower = artist.trim().toLowerCase();
    final titleQueryLower = title.trim().toLowerCase();

    if (_containsExcludedTerms(titleLower)) {
      return null;
    }

    if (titleLower.contains('audio')) score += 5.0;
    if (titleLower.contains('official audio')) score += 10.0;
    if (titleLower.contains('official')) score += 3.0;
    if (channelLower.contains('topic') || channelLower.contains('vevo')) {
      score += 7.0;
    }

    if (titleQueryLower.isNotEmpty && titleLower.contains(titleQueryLower)) {
      score += 5.0;
    }
    if (artistLower.isNotEmpty && titleLower.contains(artistLower)) {
      score += 5.0;
    }

    if (titleLower.contains(' - ')) score += 3.0;

    return score;
  }
  
  /// Dispose resources
  void dispose() {
    _youtube.close();
  }
}
