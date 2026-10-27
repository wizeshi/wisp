// Copyright © 2026 wizeshi

/// YouTube metadata converters
library;

import 'package:wisp/data/sources/youtube/youtube_audio.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp_innertubex_manager/wisp_innertubex_manager.dart';

GenericSong youtubeResultToGenericSong(YouTubeResult result) {
  final artistName = result.channelName.isNotEmpty
      ? result.channelName
      : 'YouTube';
  return GenericSong(
    id: result.videoId,
    source: 'youtube',
    title: result.title,
    artists: [
      GenericSimpleArtist(
        id: 'yt_channel_${result.videoId}',
        source: 'youtube',
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

GenericSong innerTubeSearchResultToGenericSong(InnerTubeSearchResult result) {
  final artistName = result.artist?.isNotEmpty == true
      ? result.artist!
      : 'YouTube';
  return GenericSong(
    id: result.id,
    source: 'youtube',
    title: result.title,
    artists: [
      GenericSimpleArtist(
        id: 'yt_artist_${result.artist ?? "unknown"}',
        source: 'youtube',
        name: artistName,
        thumbnailUrl: result.thumbnailUrl ?? '',
      ),
    ],
    thumbnailUrl: result.thumbnailUrl ?? '',
    explicit: false,
    album: result.album != null && result.album!.isNotEmpty
        ? GenericSimpleAlbum(
            id: 'yt_album_${result.album}',
            source: 'youtube',
            title: result.album!,
            thumbnailUrl: result.thumbnailUrl ?? '',
            artists: [
              GenericSimpleArtist(
                id: 'yt_artist_${result.artist ?? "unknown"}',
                source: 'youtube',
                name: artistName,
                thumbnailUrl: result.thumbnailUrl ?? '',
              ),
            ],
            label: '',
            releaseDate: DateTime(2020),
          )
        : null,
    durationSecs: result.duration?.inSeconds ?? 0,
  );
}

GenericSong innerTubeTrackToGenericSong(InnerTubeTrack track) {
  final artistName = track.author.isNotEmpty ? track.author : 'YouTube';
  return GenericSong(
    id: track.videoId,
    source: 'youtube',
    title: track.title,
    artists: [
      GenericSimpleArtist(
        id: track.authorId ?? 'yt_author_${track.author}',
        source: 'youtube',
        name: artistName,
        thumbnailUrl: track.thumbnailUrl ?? '',
      ),
    ],
    thumbnailUrl: track.thumbnailUrl ?? '',
    explicit: false,
    album: null,
    durationSecs: track.duration.inSeconds,
  );
}

GenericAlbum innerTubeAlbumToGenericAlbum(InnerTubeAlbum album) {
  final artist = GenericSimpleArtist(
    id: album.artistId ?? 'yt_artist_${album.artist}',
    source: 'youtube',
    name: album.artist.isNotEmpty ? album.artist : 'YouTube',
    thumbnailUrl: album.thumbnailUrl ?? '',
  );

  final songs = album.tracks.map((t) {
    return GenericSong(
      id: t.videoId,
      source: 'youtube',
      title: t.title,
      artists: [artist],
      thumbnailUrl: album.thumbnailUrl ?? '',
      explicit: false,
      album: null,
      durationSecs: t.duration.inSeconds,
    );
  }).toList();

  return GenericAlbum(
    id: album.browseId,
    source: 'youtube',
    title: album.title,
    thumbnailUrl: album.thumbnailUrl ?? '',
    artists: [artist],
    label: '',
    releaseDate: DateTime.tryParse(album.year ?? '') ?? DateTime(2020),
    explicit: false,
    durationSecs: songs.fold(0, (acc, s) => acc + s.durationSecs),
    songs: songs,
  );
}

GenericArtist innerTubeArtistToGenericArtist(InnerTubeArtist artist) {
  final allAlbums = [
    ...artist.albums.map((a) {
      return GenericSimpleAlbum(
        id: a.id,
        source: 'youtube',
        title: a.title,
        thumbnailUrl: a.thumbnailUrl ?? '',
        artists: [
          GenericSimpleArtist(
            id: artist.browseId,
            source: 'youtube',
            name: artist.name,
            thumbnailUrl: artist.avatarUrl ?? '',
          ),
        ],
        label: '',
        releaseDate: DateTime(2020),
      );
    }),
    ...artist.singles.map((s) {
      return GenericSimpleAlbum(
        id: s.id,
        source: 'youtube',
        title: s.title,
        thumbnailUrl: s.thumbnailUrl ?? '',
        artists: [
          GenericSimpleArtist(
            id: artist.browseId,
            source: 'youtube',
            name: artist.name,
            thumbnailUrl: artist.avatarUrl ?? '',
          ),
        ],
        label: '',
        releaseDate: DateTime(2020),
      );
    }),
  ];

  return GenericArtist(
    id: artist.browseId,
    source: 'youtube',
    name: artist.name,
    thumbnailUrl: artist.avatarUrl ?? '',
    followers: 0,
    topSongs: artist.topTracks.map(innerTubeSearchResultToGenericSong).toList(),
    albums: allAlbums,
  );
}

GenericPlaylist innerTubePlaylistToGenericPlaylist(InnerTubePlaylist playlist) {
  final playlistItems = playlist.tracks.asMap().entries.map((entry) {
    final idx = entry.key;
    final item = entry.value;
    return PlaylistItem(
      id: item.id,
      source: 'youtube',
      title: item.title,
      artists: [
        GenericSimpleArtist(
          id: 'yt_artist_${item.artist ?? "unknown"}',
          source: 'youtube',
          name: item.artist ?? 'YouTube',
          thumbnailUrl: item.thumbnailUrl ?? '',
        ),
      ],
      thumbnailUrl: item.thumbnailUrl ?? '',
      explicit: false,
      album: null,
      durationSecs: item.duration?.inSeconds ?? 0,
      addedAt: DateTime.now(),
      trackNumber: idx + 1,
    );
  }).toList();

  final authorName = playlist.author ?? 'YouTube';

  return GenericPlaylist(
    id: playlist.browseId,
    source: 'youtube',
    title: playlist.title,
    author: GenericSimpleUser(
      id: 'yt_user_$authorName',
      source: 'youtube',
      displayName: authorName,
    ),
    description: playlist.description,
    thumbnailUrl: playlist.thumbnailUrl ?? '',
    total: playlist.trackCount,
    durationSecs: playlistItems.fold(0, (acc, item) => acc + item.durationSecs),
    songs: playlistItems,
  );
}
