// Copyright © 2026 wizeshi

/// Liked Songs helpers
library;

import 'package:wisp/data/models/metadata_models.dart';

const String likedSongsPlaylistId = 'liked_songs';
const String likedSongsTitle = 'Liked Songs';

bool isLikedSongsPlaylistId(String? id) => id == likedSongsPlaylistId;

GenericPlaylist buildLikedSongsPlaylist({String? userDisplayName, int? total}) {
  return GenericPlaylist(
    id: likedSongsPlaylistId,
    source: 'spotify',
    title: likedSongsTitle,
    thumbnailUrl: '',
    author: GenericSimpleUser(
      id: 'liked_songs_user',
      source: 'spotify',
      displayName: userDisplayName ?? 'You',
    ),
    songs: null,
    durationSecs: 0,
    total: total,
    hasMore: false,
  );
}
