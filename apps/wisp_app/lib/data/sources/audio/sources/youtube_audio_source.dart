// Copyright © 2026 wizeshi

library;

import 'package:wisp/data/sources/audio/audio_source.dart';
import 'package:wisp/data/sources/youtube/youtube_audio.dart';

/// Built-in YouTube audio source adapter.
class YouTubeAudioSource extends AudioSource {
  final YouTubeProvider _youtube;

  YouTubeAudioSource({YouTubeProvider? provider})
      : _youtube = provider ?? YouTubeProvider();

  @override
  String get id => 'youtube';

  @override
  String get name => 'YouTube';

  @override
  String get description =>
      'Built-in YouTube streaming engine utilizing YT-DLP, NewPipeExtractor, and YoutubeExplode';

  @override
  bool get isBuiltIn => true;

  @override
  int get priority => 50;

  @override
  Set<AudioQuality> get supportedQualities => {
        AudioQuality.standard,
        AudioQuality.high,
      };

  @override
  Future<void> initialize() async {
    await YouTubeProvider.loadVideoIdCache();
  }

  @override
  Future<List<AudioTrackCandidate>> searchAudio(AudioSearchQuery query) async {
    final queryStr = query.artistNames.isNotEmpty
        ? '${query.artistNames} - ${query.title}'
        : query.title;

    final results = await _youtube.searchYouTubeTracks(
      queryStr,
      limit: 15,
      artist: query.artistNames,
      title: query.title,
      durationSecs: query.durationSecs,
    );

    return results.map((r) {
      return AudioTrackCandidate(
        mediaId: r.videoId,
        providerId: id,
        title: r.title,
        artist: r.channelName,
        album: null,
        duration: r.duration,
        thumbnailUrl: r.thumbnailUrl,
        qualityLabel: 'Opus / AAC ~160k',
        score: r.score,
      );
    }).toList();
  }

  @override
  Future<AudioStreamResult> getStreamUrl(
    String mediaId, {
    AudioQuality? preferredQuality,
  }) async {
    final streamUrl = await _youtube.getStreamUrl(mediaId);
    return AudioStreamResult(
      url: streamUrl,
      headers: {'User-Agent': YouTubeProvider.userAgentForPlatform()},
      format: 'm4a',
      bitrate: 160,
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
    );
  }

  @override
  void dispose() {
    _youtube.dispose();
  }
}

