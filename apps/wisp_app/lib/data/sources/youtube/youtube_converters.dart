// Copyright © 2026 wizeshi

/// YouTube metadata converters
library;

import 'package:wisp/data/sources/youtube/youtube_audio.dart';
import 'package:wisp/data/models/metadata_models.dart';

GenericSong youtubeResultToGenericSong(YouTubeResult result) {
  final artistName = result.channelName.isNotEmpty
      ? result.channelName
      : 'YouTube';
  return GenericSong(
    id: result.videoId,
    source: SongSource.youtube,
    title: result.title,
    artists: [
      GenericSimpleArtist(
        id: 'yt_channel_${result.videoId}',
        source: SongSource.youtube,
        name: artistName,
        thumbnailUrl: result.thumbnailUrl,
      ),
    ],
    thumbnailUrl: result.thumbnailUrl,
    explicit: false,
    album: null,
    durationSecs: result.duration.inSeconds,
  );
}
