/// Spotify API response to generic model converters
/// Handles conversion from Spotify JSON to generic metadata models
library;

import 'metadata_models.dart';

/// Helper to select the largest image from Spotify's image array
String _getLargestImage(List<dynamic>? images) {
  if (images == null || images.isEmpty) return '';
  
  // Spotify images are typically sorted largest to smallest, but let's be safe
  final sortedImages = List<Map<String, dynamic>>.from(images);
  sortedImages.sort((a, b) {
    final aSize = (a['height'] as int? ?? 0) * (a['width'] as int? ?? 0);
    final bSize = (b['height'] as int? ?? 0) * (b['width'] as int? ?? 0);
    return bSize.compareTo(aSize); // Descending order
  });
  
  return sortedImages.first['url'] as String? ?? '';
}

/// Convert Spotify artist JSON to GenericSimpleArtist
GenericSimpleArtist spotifyArtistToGeneric(Map<String, dynamic> artist) {
  return GenericSimpleArtist(
    id: artist['id'] as String? ?? '',
    source: SongSource.spotify,
    name: artist['name'] as String? ?? 'Unknown Artist',
    thumbnailUrl: _getLargestImage(artist['images'] as List?),
  );
}

/// Convert Spotify simplified album JSON to GenericSimpleAlbum
GenericSimpleAlbum spotifySimplifiedAlbumToGeneric(
    Map<String, dynamic> album) {
  final artists = (album['artists'] as List?)
          ?.map((a) => spotifyArtistToGeneric(a as Map<String, dynamic>))
          .toList() ??
      [];

  return GenericSimpleAlbum(
    id: album['id'] as String? ?? '',
    source: SongSource.spotify,
    title: album['name'] as String? ?? 'Unknown Album',
    thumbnailUrl: _getLargestImage(album['images'] as List?),
    artists: artists,
    label: album['label'] as String? ?? '',
    releaseDate: DateTime.tryParse(album['release_date'] as String? ?? '') ??
        DateTime.now(),
  );
}

/// Convert Spotify track JSON to GenericSong
GenericSong spotifyTrackToGeneric(Map<String, dynamic> track) {
  final artists = (track['artists'] as List?)
          ?.map((a) => spotifyArtistToGeneric(a as Map<String, dynamic>))
          .toList() ??
      [];

  GenericSimpleAlbum? album;
  if (track['album'] != null) {
    album = spotifySimplifiedAlbumToGeneric(
        track['album'] as Map<String, dynamic>);
  }

  return GenericSong(
    id: track['id'] as String? ?? '',
    source: SongSource.spotify,
    title: track['name'] as String? ?? 'Unknown Track',
    artists: artists,
    thumbnailUrl: album?.thumbnailUrl ?? '',
    explicit: track['explicit'] as bool? ?? false,
    album: album,
    durationSecs: ((track['duration_ms'] as int? ?? 0) / 1000).round(),
  );
}

/// Convert Spotify full album JSON to GenericAlbum with pagination support
GenericAlbum spotifyFullAlbumToGeneric(
  Map<String, dynamic> album, {
  int? offset,
  int? limit,
}) {
  final artists = (album['artists'] as List?)
          ?.map((a) => spotifyArtistToGeneric(a as Map<String, dynamic>))
          .toList() ??
      [];

  final tracksData = album['tracks'] as Map<String, dynamic>?;
  final trackItems = tracksData?['items'] as List?;
  
  List<GenericSong>? songs;
  if (trackItems != null) {
    songs = trackItems.map((track) {
      // Add album reference to each track
      final trackWithAlbum = Map<String, dynamic>.from(track as Map<String, dynamic>);
      trackWithAlbum['album'] = {
        'id': album['id'],
        'name': album['name'],
        'images': album['images'],
        'artists': album['artists'],
        'label': album['label'],
        'release_date': album['release_date'],
      };
      return spotifyTrackToGeneric(trackWithAlbum);
    }).toList();
  }

  final totalTracks = tracksData?['total'] as int? ?? songs?.length ?? 0;
  final hasMore = offset != null && limit != null
      ? (offset + limit) < totalTracks
      : false;

  // Calculate total duration
  int durationSecs = 0;
  if (songs != null) {
    durationSecs = songs.fold(0, (sum, song) => sum + song.durationSecs);
  }

  return GenericAlbum(
    id: album['id'] as String? ?? '',
    source: SongSource.spotify,
    title: album['name'] as String? ?? 'Unknown Album',
    thumbnailUrl: _getLargestImage(album['images'] as List?),
    artists: artists,
    label: album['label'] as String? ?? '',
    releaseDate: DateTime.tryParse(album['release_date'] as String? ?? '') ??
        DateTime.now(),
    explicit: album['explicit'] as bool? ?? false,
    songs: songs,
    durationSecs: durationSecs,
    total: totalTracks,
    hasMore: hasMore,
  );
}

/// Convert Spotify playlist owner to GenericSimpleUser
GenericSimpleUser spotifyOwnerToGeneric(Map<String, dynamic> owner) {
  return GenericSimpleUser(
    id: owner['id'] as String? ?? '',
    source: SongSource.spotify,
    displayName: owner['display_name'] as String? ?? 'Unknown User',
    avatarUrl: _getLargestImage(owner['images'] as List?),
    followerCount: owner['followers']?['total'] as int?,
    profileUrl: owner['external_urls']?['spotify'] as String?,
  );
}

/// Convert Spotify playlist track item to PlaylistItem
PlaylistItem spotifyPlaylistTrackToPlaylistItem(
  Map<String, dynamic> item,
  int trackNumber,
) {
  final track = item['track'] as Map<String, dynamic>?;
  if (track == null) {
    // Handle null track (deleted/unavailable tracks)
    return PlaylistItem(
      id: '',
      source: SongSource.spotify,
      title: 'Unavailable Track',
      artists: [],
      thumbnailUrl: '',
      explicit: false,
      album: null,
      durationSecs: 0,
      addedAt: DateTime.tryParse(item['added_at'] as String? ?? '') ??
          DateTime.now(),
      trackNumber: trackNumber,
    );
  }

  final artists = (track['artists'] as List?)
          ?.map((a) => spotifyArtistToGeneric(a as Map<String, dynamic>))
          .toList() ??
      [];

  GenericSimpleAlbum? album;
  if (track['album'] != null) {
    album = spotifySimplifiedAlbumToGeneric(
        track['album'] as Map<String, dynamic>);
  }

  return PlaylistItem(
    id: track['id'] as String? ?? '',
    source: SongSource.spotify,
    title: track['name'] as String? ?? 'Unknown Track',
    artists: artists,
    thumbnailUrl: album?.thumbnailUrl ?? '',
    explicit: track['explicit'] as bool? ?? false,
    album: album,
    durationSecs: ((track['duration_ms'] as int? ?? 0) / 1000).round(),
    addedAt: DateTime.tryParse(item['added_at'] as String? ?? '') ??
        DateTime.now(),
    trackNumber: trackNumber,
  );
}

/// Convert Spotify saved track item to PlaylistItem
PlaylistItem spotifySavedTrackToPlaylistItem(
  Map<String, dynamic> item,
  int trackNumber,
) {
  final track = item['track'] as Map<String, dynamic>?;
  if (track == null) {
    return PlaylistItem(
      id: '',
      source: SongSource.spotify,
      title: 'Unavailable Track',
      artists: [],
      thumbnailUrl: '',
      explicit: false,
      album: null,
      durationSecs: 0,
      addedAt: DateTime.tryParse(item['added_at'] as String? ?? '') ??
          DateTime.now(),
      trackNumber: trackNumber,
    );
  }

  final artists = (track['artists'] as List?)
          ?.map((a) => spotifyArtistToGeneric(a as Map<String, dynamic>))
          .toList() ??
      [];
  final album = track['album'] != null
      ? spotifySimplifiedAlbumToGeneric(track['album'] as Map<String, dynamic>)
      : null;

  return PlaylistItem(
    id: track['id'] as String? ?? '',
    source: SongSource.spotify,
    title: track['name'] as String? ?? 'Unknown Track',
    artists: artists,
    thumbnailUrl: album?.thumbnailUrl ?? '',
    explicit: track['explicit'] as bool? ?? false,
    album: album,
    durationSecs: ((track['duration_ms'] as int? ?? 0) / 1000).round(),
    addedAt:
        DateTime.tryParse(item['added_at'] as String? ?? '') ?? DateTime.now(),
    trackNumber: trackNumber,
  );
}

/// Convert Spotify full playlist JSON to GenericPlaylist with pagination support
GenericPlaylist spotifyFullPlaylistToGeneric(
  Map<String, dynamic> playlist, {
  int? offset,
  int? limit,
}) {
  final owner = spotifyOwnerToGeneric(
      playlist['owner'] as Map<String, dynamic>? ?? {});

  final tracksData = playlist['tracks'] as Map<String, dynamic>?;
  final trackItems = tracksData?['items'] as List?;

  List<PlaylistItem>? songs;
  if (trackItems != null) {
    songs = trackItems
        .asMap()
        .entries
        .map((entry) => spotifyPlaylistTrackToPlaylistItem(
              entry.value as Map<String, dynamic>,
              (offset ?? 0) + entry.key + 1,
            ))
        .where((item) => item.id.isNotEmpty) // Filter out unavailable tracks
        .toList();
  }

  final totalTracks = tracksData?['total'] as int? ?? songs?.length ?? 0;
  final hasMore = offset != null && limit != null
      ? (offset + limit) < totalTracks
      : false;

  // Calculate total duration
  int durationSecs = 0;
  if (songs != null) {
    durationSecs = songs.fold(0, (sum, song) => sum + song.durationSecs);
  }

  return GenericPlaylist(
    id: playlist['id'] as String? ?? '',
    source: SongSource.spotify,
    title: playlist['name'] as String? ?? 'Unknown Playlist',
    thumbnailUrl: _getLargestImage(playlist['images'] as List?),
    author: owner,
    songs: songs,
    durationSecs: durationSecs,
    total: totalTracks,
    hasMore: hasMore,
  );
}

/// Convert Spotify full artist JSON to GenericArtist
GenericArtist spotifyFullArtistToGeneric(
  Map<String, dynamic> artist,
  List<GenericSong> topTracks,
  List<GenericSimpleAlbum> albums,
) {
  return GenericArtist(
    id: artist['id'] as String? ?? '',
    source: SongSource.spotify,
    name: artist['name'] as String? ?? 'Unknown Artist',
    thumbnailUrl: _getLargestImage(artist['images'] as List?),
    followers: artist['followers']?['total'] as int? ?? 0,
    topSongs: topTracks,
    albums: albums,
  );
}
