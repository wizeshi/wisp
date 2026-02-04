/// YouTube metadata converters
library;

import '../providers/audio/youtube.dart';
import 'metadata_models.dart';

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