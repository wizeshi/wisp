/// Liked Songs helpers
library;

import '../models/metadata_models.dart';

const String likedSongsPlaylistId = 'liked_songs';
const String likedSongsTitle = 'Liked Songs';

bool isLikedSongsPlaylistId(String? id) => id == likedSongsPlaylistId;

GenericPlaylist buildLikedSongsPlaylist({
  String? userDisplayName,
  int? total,
}) {
  return GenericPlaylist(
    id: likedSongsPlaylistId,
    source: SongSource.spotifyInternal,
    title: likedSongsTitle,
    thumbnailUrl: '',
    author: GenericSimpleUser(
      id: 'liked_songs_user',
      source: SongSource.spotifyInternal,
      displayName: userDisplayName ?? 'You',
    ),
    songs: null,
    durationSecs: 0,
    total: total,
    hasMore: false,
  );
}
