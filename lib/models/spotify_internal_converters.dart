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

// Normalize heterogeneous image source shapes returned by Spotify
List<Map<String, dynamic>> _normalizeImageSources(dynamic sources) {
  if (sources == null) return [];
  final list = (sources is List) ? sources : [];
  return list.whereType<Map>().map((m) {
    var url = m['url'] ?? m['imageId'] ?? '';
    // Convert short image ids (e.g. spotify image ids) into full CDN URLs
    if (url is String && url.isNotEmpty && !url.startsWith('http')) {
      if (url.startsWith('spotify:')) {
        final parts = url.split(':');
        if (parts.length >= 3) {
          final type = parts[1];
          final id = parts[2];
          if (type == 'mosaic') {
            url = 'https://mosaic.scdn.co/640/$id';
          } else {
            url = 'https://i.scdn.co/image/$id';
          }
        } else {
          url = 'https://i.scdn.co/image/${parts.last}';
        }
      } else {
        url = 'https://i.scdn.co/image/$url';
      }
    }
    final height = (m['height'] ?? m['maxHeight'] ?? 0) as int?;
    final width = (m['width'] ?? m['maxWidth'] ?? 0) as int?;
    return {
      'height': height ?? 0,
      'width': width ?? 0,
      'url': url as String? ?? '',
    };
  }).toList();
}

// Robustly extract image/source lists from various Spotify response wrappers
List<Map<String, dynamic>> _extractImageSources(dynamic obj) {
  if (obj == null) return [];
  // Direct list of sources or images
  if (obj is List) {
    if (obj.isNotEmpty &&
        obj.first is Map &&
        (obj.first as Map).containsKey('sources')) {
      return _normalizeImageSources((obj.first as Map)['sources']);
    }
    return _normalizeImageSources(obj);
  }

  if (obj is Map<String, dynamic>) {
    final candidates = [
      obj['sources'],
      obj['images'],
      obj['image']?['sources'],
      obj['image']?['data']?['sources'],
      if (obj['items'] is List && (obj['items'] as List).isNotEmpty)
        (obj['items'] as List)[0]['sources'],
      if (obj['images']?['items'] is List &&
          (obj['images']?['items'] as List).isNotEmpty)
        (obj['images']?['items'] as List)[0]['sources'],
      obj['coverArt']?['sources'],
      obj['avatar']?['sources'],
      obj['visualIdentity']?['squareCoverImage']?['image']?['data']?['sources'],
      obj['visuals']?['avatarImage']?['sources'],
      obj['visuals']?['avatarImage']?['image']?['data']?['sources'],
    ];

    for (final c in candidates) {
      final norm = _normalizeImageSources(c);
      if (norm.isNotEmpty) return norm;
    }
  }

  return [];
}

String? _extractPlaylistDescription(Map<String, dynamic> playlist) {
  final raw = playlist['description'];
  if (raw is String) return raw;
  if (raw is Map<String, dynamic>) {
    return raw['text'] as String? ??
        raw['body'] as String? ??
        raw['plainText'] as String?;
  }

  final details = playlist['details'] as Map<String, dynamic>?;
  final detailDescription = details?['description'];
  if (detailDescription is String) return detailDescription;
  if (detailDescription is Map<String, dynamic>) {
    return detailDescription['text'] as String? ??
        detailDescription['body'] as String? ??
        detailDescription['plainText'] as String?;
  }

  return null;
}

/// Convert Spotify artist JSON to GenericSimpleArtist
GenericSimpleArtist spotifyInternalArtistToGeneric(
  Map<String, dynamic> artist,
) {
  artist = (artist['data']?['artistUnion'] ?? artist) as Map<String, dynamic>;

  final thumbSources = _extractImageSources(artist);
  final uri = artist['uri'] as String? ?? '';
  final id = uri.isNotEmpty
      ? uri.split(':').last
      : artist['id'] as String? ?? '';

  return GenericSimpleArtist(
    id: id,
    source: SongSource.spotifyInternal,
    name: artist['profile']?['name'] as String? ?? 'Unknown Artist',
    thumbnailUrl: _getLargestImage(thumbSources),
  );
}

/// Convert Spotify simplified album JSON to GenericSimpleAlbum
GenericSimpleAlbum spotifyInternalSimplifiedAlbumToGeneric(
  Map<String, dynamic> album,
) {
  final artists =
      (album['artists']?['items'] as List?)
          ?.map(
            (a) => spotifyInternalArtistToGeneric(a as Map<String, dynamic>),
          )
          .toList() ??
      [];

  final thumbSources = _extractImageSources(album);
  final uri = album['uri'] as String? ?? '';
  final id = uri.isNotEmpty
      ? uri.split(':').last
      : album['id'] as String? ?? '';

  DateTime releaseDate;
  final dateMap = album['date'] as Map<String, dynamic>?;
  if (dateMap?['isoString'] != null) {
    releaseDate =
        DateTime.tryParse(dateMap!['isoString'] as String) ?? DateTime.now();
  } else if (dateMap?['year'] != null) {
    releaseDate = DateTime(dateMap!['year'] as int);
  } else {
    releaseDate =
        DateTime.tryParse(album['release_date'] as String? ?? '') ??
        DateTime.now();
  }

  return GenericSimpleAlbum(
    id: id,
    source: SongSource.spotifyInternal,
    title: album['name'] as String? ?? 'Unknown Album',
    thumbnailUrl: _getLargestImage(thumbSources),
    artists: artists,
    label: album['label'] as String? ?? '',
    releaseDate: releaseDate,
  );
}

/// Convert Spotify track JSON to GenericSong
GenericSong spotifyInternalTrackToGeneric(Map<String, dynamic> track) {
  List<GenericSimpleArtist> artists = [];
  if (track['artists'] is Map && track['artists']['items'] is List) {
    artists = (track['artists']['items'] as List)
        .map((a) => spotifyInternalArtistToGeneric(a as Map<String, dynamic>))
        .toList();
  } else if (track['artists'] is List) {
    artists = (track['artists'] as List)
        .map((a) => spotifyInternalArtistToGeneric(a as Map<String, dynamic>))
        .toList();
  }

  GenericSimpleAlbum? album;
  if (track['album'] != null) {
    album = spotifyInternalSimplifiedAlbumToGeneric(
      track['album'] as Map<String, dynamic>,
    );
  } else if (track['albumOfTrack'] != null) {
    album = spotifyInternalSimplifiedAlbumToGeneric(
      track['albumOfTrack'] as Map<String, dynamic>,
    );
  }

  final uri = track['uri'] as String? ?? '';
  final id = uri.isNotEmpty
      ? uri.split(':').last
      : track['id'] as String? ?? '';
  final isExplicit = track['contentRating']?['label'] == 'EXPLICIT';
  final durationMs =
      (track['duration']?['totalMilliseconds'] as int?) ??
      (track['duration_ms'] as int? ?? 0);

  return GenericSong(
    id: id,
    source: SongSource.spotifyInternal,
    title: track['name'] as String? ?? 'Unknown Track',
    artists: artists,
    thumbnailUrl: album?.thumbnailUrl ?? '',
    explicit: isExplicit,
    album: album,
    durationSecs: (durationMs / 1000).round(),
  );
}

/// Convert Spotify full album JSON to GenericAlbum with pagination support
GenericAlbum spotifyInternalFullAlbumToGeneric(
  Map<String, dynamic> album, {
  int? offset,
  int? limit,
}) {
  album = (album['data']?['albumUnion'] ?? album) as Map<String, dynamic>;

  final artists =
      (album['artists']?['items'] as List?)
          ?.map(
            (a) => spotifyInternalArtistToGeneric(a as Map<String, dynamic>),
          )
          .toList() ??
      [];

  final tracksData = album['tracksV2'] as Map<String, dynamic>?;
  final trackItems = tracksData?['items'] as List?;

  List<GenericSong>? songs;
  if (trackItems != null) {
    songs = trackItems.map((item) {
      final track =
          (item as Map<String, dynamic>)['track'] as Map<String, dynamic>;
      // Add album reference to each track
      final trackWithAlbum = Map<String, dynamic>.from(track);
      trackWithAlbum['album'] = {
        'uri': album['uri'],
        'name': album['name'],
        'coverArt': album['coverArt'],
        'artists': album['artists'],
        'label': album['label'],
        'date': album['date'],
      };
      return spotifyInternalTrackToGeneric(trackWithAlbum);
    }).toList();
  }

  final totalTracks = tracksData?['totalCount'] as int? ?? songs?.length ?? 0;
  final hasMore = offset != null && limit != null
      ? (offset + limit) < totalTracks
      : false;

  // Calculate total duration
  int durationSecs = 0;
  if (songs != null) {
    durationSecs = songs.fold(0, (sum, song) => sum + song.durationSecs);
  }

  final thumbSources = _extractImageSources(album);

  final uri = album['uri'] as String? ?? '';
  final id = uri.isNotEmpty
      ? uri.split(':').last
      : album['id'] as String? ?? '';

  DateTime releaseDate;
  final dateMap = album['date'] as Map<String, dynamic>?;
  if (dateMap?['isoString'] != null) {
    releaseDate =
        DateTime.tryParse(dateMap!['isoString'] as String) ?? DateTime.now();
  } else if (dateMap?['year'] != null) {
    releaseDate = DateTime(dateMap!['year'] as int);
  } else {
    releaseDate =
        DateTime.tryParse(album['release_date'] as String? ?? '') ??
        DateTime.now();
  }

  return GenericAlbum(
    id: id,
    source: SongSource.spotifyInternal,
    title: album['name'] as String? ?? 'Unknown Album',
    thumbnailUrl: _getLargestImage(thumbSources),
    artists: artists,
    label: album['label'] as String? ?? '',
    releaseDate: releaseDate,
    explicit: album['explicit'] as bool? ?? false,
    songs: songs,
    durationSecs: durationSecs,
    total: totalTracks,
    hasMore: hasMore,
  );
}

/// Convert Spotify playlist owner to GenericSimpleUser
GenericSimpleUser spotifyInternalOwnerToGeneric(Map<String, dynamic> owner) {
  // owner may be wrapped in a `data` key (ownerV2 -> { data: { ... } })
  final o = (owner['data'] as Map<String, dynamic>?) ?? owner;
  final avatarSources = _extractImageSources(o);
  final profile = o['profile'] as Map<String, dynamic>?;
  final displayName =
      (o['name'] as String?) ??
      (profile?['name'] as String?) ??
      (o['display_name'] as String?) ??
      (o['username'] as String?) ??
      (o['id'] as String?) ??
      'Unknown User';
  final rawId =
      (o['uri'] as String?) ??
      (profile?['uri'] as String?) ??
      (o['id'] as String?) ??
      '';

  return GenericSimpleUser(
    id: rawId
        .toString()
        .split(':')
        .last,
    source: SongSource.spotifyInternal,
    displayName: displayName,
    avatarUrl: _getLargestImage(avatarSources),
    followerCount: o['followers']?['total'] as int?,
    profileUrl: o['external_urls']?['spotify'] as String?,
  );
}

/// Convert Spotify playlist track item to PlaylistItem
PlaylistItem spotifyInternalPlaylistTrackToPlaylistItem(
  Map<String, dynamic> item,
  int trackNumber,
) {
  final uid = item['uid'] as String?;
  final track = item['track'] as Map<String, dynamic>?;
  if (track == null) {
    // Handle null track (deleted/unavailable tracks)
    return PlaylistItem(
      id: '',
      uid: uid,
      source: SongSource.spotifyInternal,
      title: 'Unavailable Track',
      artists: [],
      thumbnailUrl: '',
      explicit: false,
      album: null,
      durationSecs: 0,
      addedAt:
          DateTime.tryParse(item['added_at'] as String? ?? '') ??
          DateTime.now(),
      trackNumber: trackNumber,
    );
  }

  final artists =
      (track['artists'] as List?)
          ?.map(
            (a) => spotifyInternalArtistToGeneric(a as Map<String, dynamic>),
          )
          .toList() ??
      [];

  GenericSimpleAlbum? album;
  if (track['album'] != null) {
    album = spotifyInternalSimplifiedAlbumToGeneric(
      track['album'] as Map<String, dynamic>,
    );
  }

  return PlaylistItem(
    id: track['id'] as String? ?? '',
    uid: uid,
    source: SongSource.spotifyInternal,
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

/// Convert Spotify saved track item to PlaylistItem
PlaylistItem spotifyInternalSavedTrackToPlaylistItem(
  Map<String, dynamic> item,
  int trackNumber,
) {
  final uid = item['uid'] as String?;
  final track = item['track'] as Map<String, dynamic>?;
  if (track == null) {
    return PlaylistItem(
      id: '',
      uid: uid,
      source: SongSource.spotifyInternal,
      title: 'Unavailable Track',
      artists: [],
      thumbnailUrl: '',
      explicit: false,
      album: null,
      durationSecs: 0,
      addedAt:
          DateTime.tryParse(item['added_at'] as String? ?? '') ??
          DateTime.now(),
      trackNumber: trackNumber,
    );
  }

  final artists =
      (track['artists'] as List?)
          ?.map(
            (a) => spotifyInternalArtistToGeneric(a as Map<String, dynamic>),
          )
          .toList() ??
      [];
  final album = track['album'] != null
      ? spotifyInternalSimplifiedAlbumToGeneric(
          track['album'] as Map<String, dynamic>,
        )
      : null;

  return PlaylistItem(
    id: track['id'] as String? ?? '',
    uid: uid,
    source: SongSource.spotifyInternal,
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

/// Convert Spotify internal library track response to PlaylistItem
PlaylistItem spotifyInternalLibraryTrackToPlaylistItem(
  Map<String, dynamic> item,
  int trackNumber,
) {
  final uid = item['uid'] as String?;
  final trackWrapper = item['track'] as Map<String, dynamic>?;
  if (trackWrapper == null) {
    return PlaylistItem(
      id: '',
      uid: uid,
      source: SongSource.spotifyInternal,
      title: 'Unavailable Track',
      artists: [],
      thumbnailUrl: '',
      explicit: false,
      album: null,
      durationSecs: 0,
      addedAt:
          DateTime.tryParse(item['addedAt']?['isoString'] as String? ?? '') ??
          DateTime.now(),
      trackNumber: trackNumber,
    );
  }

  final trackData =
      (trackWrapper['data'] as Map<String, dynamic>?) ?? trackWrapper;
  final trackUri =
      trackWrapper['_uri'] as String? ?? trackData['uri'] as String? ?? '';
  final id = trackUri.isNotEmpty
      ? trackUri.split(':').last
      : trackData['id'] as String? ?? '';

  final artists =
      (trackData['artists']?['items'] as List?)
          ?.map(
            (a) => spotifyInternalArtistToGeneric(a as Map<String, dynamic>),
          )
          .toList() ??
      [];

  final albumData =
      trackData['albumOfTrack'] as Map<String, dynamic>? ??
      trackData['album'] as Map<String, dynamic>?;
  final album = albumData != null
      ? spotifyInternalSimplifiedAlbumToGeneric(albumData)
      : null;

  final durationMs =
      (trackData['duration']?['totalMilliseconds'] as int?) ??
      (trackData['duration_ms'] as int? ?? 0);
  final explicit = trackData['contentRating']?['label'] == 'EXPLICIT';

  return PlaylistItem(
    id: id,
    uid: uid,
    source: SongSource.spotifyInternal,
    title: trackData['name'] as String? ?? 'Unknown Track',
    artists: artists,
    thumbnailUrl: album?.thumbnailUrl ?? '',
    explicit: explicit,
    album: album,
    durationSecs: (durationMs / 1000).round(),
    addedAt:
        DateTime.tryParse(item['addedAt']?['isoString'] as String? ?? '') ??
        DateTime.now(),
    trackNumber: trackNumber,
  );
}

// Convert playlist `itemV3` (EntityResponseWrapper) or fallback `itemV2` into PlaylistItem
PlaylistItem spotifyInternalPlaylistItemV3ToPlaylistItem(
  Map<String, dynamic> item,
  int trackNumber,
) {
  final uid =
      item['uid'] as String? ??
      (item['itemV2'] as Map<String, dynamic>?)?['uid'] as String? ??
      (item['itemV3'] as Map<String, dynamic>?)?['uid'] as String?;
  final v3data =
      (item['itemV3'] as Map<String, dynamic>?)?['data']
          as Map<String, dynamic>?;
  final v2data =
      (item['itemV2'] as Map<String, dynamic>?)?['data']
          as Map<String, dynamic>?;
  final sourceData = v3data ?? v2data;

  if (sourceData == null) {
    return PlaylistItem(
      id: '',
      uid: uid,
      source: SongSource.spotifyInternal,
      title: 'Unavailable Track',
      artists: [],
      thumbnailUrl: '',
      explicit: false,
      album: null,
      durationSecs: 0,
      addedAt:
          DateTime.tryParse(item['addedAt']?['isoString'] as String? ?? '') ??
          DateTime.now(),
      trackNumber: trackNumber,
    );
  }

  final identity = sourceData['identityTrait'] as Map<String, dynamic>?;
  final title =
      identity?['name'] as String? ??
      sourceData['name'] as String? ??
      'Unknown Track';
  final id = sourceData['uri'] as String? ?? (v2data?['uri'] as String? ?? '');

  final durationSeconds =
      (sourceData['consumptionExperienceTrait']?['duration']?['seconds']
          as int?) ??
      ((v2data?['trackDuration']?['totalMilliseconds'] as int?) != null
          ? ((v2data!['trackDuration']['totalMilliseconds'] as int) / 1000)
                .round()
          : 0);

  // Artists
  List<GenericSimpleArtist> artists = [];
  final contributors = identity?['contributors']?['items'] as List?;
  if (contributors != null) {
    artists = contributors.map((c) {
      final cm = c as Map<String, dynamic>;
      final name = cm['name'] as String? ?? '';
      final uri = cm['uri'] as String? ?? '';
      final aid = uri.split(':').isNotEmpty ? uri.split(':').last : uri;
      return GenericSimpleArtist(
        id: aid,
        source: SongSource.spotifyInternal,
        name: name,
        thumbnailUrl: '',
      );
    }).toList();
  } else if (v2data?['artists']?['items'] is List) {
    artists = (v2data!['artists']['items'] as List)
        .map((a) => spotifyInternalArtistToGeneric(a as Map<String, dynamic>))
        .toList();
  }

  // Images: prefer v3 visualIdentityTrait sources, fallback to v2 album coverArt
  dynamic imageSources =
      identity?['visualIdentityTrait']?['squareCoverImage']?['image']?['data']?['sources'] ??
      identity?['visualIdentityTrait']?['sixteenByNineCoverImage']?['image']?['data']?['sources'] ??
      v2data?['albumOfTrack']?['coverArt']?['sources'];
  final normSources = _normalizeImageSources(imageSources);
  final thumbnail = _getLargestImage(normSources);

  // Album
  GenericSimpleAlbum? album;
  if (v2data != null && v2data['albumOfTrack'] != null) {
    album = spotifyInternalSimplifiedAlbumToGeneric(
      v2data['albumOfTrack'] as Map<String, dynamic>,
    );
  } else if (identity?['contentHierarchyParent'] != null) {
    final parent = identity!['contentHierarchyParent'] as Map<String, dynamic>;
    album = GenericSimpleAlbum(
      id: parent['uri'] as String? ?? '',
      source: SongSource.spotifyInternal,
      title: parent['identityTrait']?['name'] as String? ?? '',
      thumbnailUrl: thumbnail,
      artists: artists,
      label: '',
      releaseDate:
          DateTime.tryParse(
            parent['publishingMetadataTrait']?['firstPublishedAt']?['isoString']
                    as String? ??
                '',
          ) ??
          DateTime.now(),
    );
  }

  return PlaylistItem(
    id: id,
    uid: uid,
    source: SongSource.spotifyInternal,
    title: title,
    artists: artists,
    thumbnailUrl: thumbnail,
    explicit: false,
    album: album,
    durationSecs: durationSeconds,
    addedAt:
        DateTime.tryParse(item['addedAt']?['isoString'] as String? ?? '') ??
        DateTime.now(),
    trackNumber: trackNumber,
  );
}

/// Convert Spotify full playlist JSON to GenericPlaylist with pagination support
GenericPlaylist spotifyInternalFullPlaylistToGeneric(
  Map<String, dynamic> playlist, {
  int? offset,
  int? limit,
}) {
  // Accept multiple wrapped shapes and normalize down to a Playlist-like map.
  // Examples seen in different endpoints:
  // - data.playlistV2
  // - PlaylistResponseWrapper -> data -> Playlist
  // - item -> content -> data
  Map<String, dynamic> normalized = playlist;

  bool changed = true;
  while (changed) {
    changed = false;

    if (normalized['data'] is Map &&
        (normalized['data'] as Map).containsKey('playlistV2')) {
      normalized =
          (normalized['data'] as Map<String, dynamic>)['playlistV2']
              as Map<String, dynamic>;
      changed = true;
      continue;
    }

    if (normalized['playlistV2'] is Map<String, dynamic>) {
      normalized = normalized['playlistV2'] as Map<String, dynamic>;
      changed = true;
      continue;
    }

    if (normalized['content'] is Map<String, dynamic>) {
      final content = normalized['content'] as Map<String, dynamic>;
      if (content['data'] is Map<String, dynamic>) {
        normalized = content['data'] as Map<String, dynamic>;
        changed = true;
        continue;
      }
    }

    if (normalized['item'] is Map<String, dynamic>) {
      normalized = normalized['item'] as Map<String, dynamic>;
      changed = true;
      continue;
    }

    if (normalized['data'] is Map<String, dynamic>) {
      final data = normalized['data'] as Map<String, dynamic>;
      final typename = data['__typename'] as String? ?? '';
      if (typename == 'Playlist' || typename.endsWith('ResponseWrapper')) {
        normalized = data;
        changed = true;
        continue;
      }
    }
  }

  playlist = normalized;

  final memberOwnerPayload =
      (((playlist['members'] as Map<String, dynamic>?)?['items'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(
                (entry) =>
                    (entry['user'] as Map<String, dynamic>?) ??
                    const <String, dynamic>{},
              )
              .firstWhere(
                (entry) => entry.isNotEmpty,
                orElse: () => const <String, dynamic>{},
              )) ??
      const <String, dynamic>{};

  final addedByPayload =
      (((playlist['content'] as Map<String, dynamic>?)?['items'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(
                (entry) =>
                    (entry['addedBy'] as Map<String, dynamic>?) ??
                    const <String, dynamic>{},
              )
              .firstWhere(
                (entry) => entry.isNotEmpty,
                orElse: () => const <String, dynamic>{},
              )) ??
      const <String, dynamic>{};

  final ownerPayload = <Map<String, dynamic>>[
    (playlist['ownerV2'] as Map<String, dynamic>?) ??
        const <String, dynamic>{},
    (playlist['owner'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    (playlist['createdByV2'] as Map<String, dynamic>?) ??
        const <String, dynamic>{},
    (playlist['creator'] as Map<String, dynamic>?) ??
        const <String, dynamic>{},
    memberOwnerPayload,
    addedByPayload,
  ].firstWhere(
    (entry) => entry.isNotEmpty,
    orElse: () => const <String, dynamic>{},
  );

  final owner = spotifyInternalOwnerToGeneric(ownerPayload);

  final content = playlist['content'] as Map<String, dynamic>?;
  final trackItems = content?['items'] as List?;

  List<PlaylistItem>? songs;
  if (trackItems != null) {
    songs = trackItems
        .asMap()
        .entries
        .map(
          (entry) => spotifyInternalPlaylistItemV3ToPlaylistItem(
            entry.value as Map<String, dynamic>,
            (offset ?? 0) + entry.key + 1,
          ),
        )
        .where((item) => item.id.isNotEmpty) // Filter out unavailable tracks
        .toList();
  }

  final totalTracks = content?['totalCount'] as int? ?? songs?.length ?? 0;
  final hasMore = offset != null && limit != null
      ? (offset + limit) < totalTracks
      : false;

  // Calculate total duration
  int durationSecs = 0;
  if (songs != null) {
    durationSecs = songs.fold(0, (sum, song) => sum + song.durationSecs);
  }

  final uri = playlist['uri'] as String? ?? playlist['_uri'] as String? ?? '';
  final id = uri.isNotEmpty
      ? uri.split(':').last
      : playlist['id'] as String? ?? '';

  return GenericPlaylist(
    id: id,
    source: SongSource.spotifyInternal,
    title: playlist['name'] as String? ?? 'Unknown Playlist',
    description: _extractPlaylistDescription(playlist),
    thumbnailUrl: _getLargestImage(_extractImageSources(playlist)),
    author: owner,
    songs: songs,
    durationSecs: durationSecs,
    total: totalTracks,
    hasMore: hasMore,
  );
}

/// Convert Spotify full artist JSON to GenericArtist
GenericArtist spotifyInternalFullArtistToGeneric(Map<String, dynamic> artist) {
  artist = (artist['data']?['artistUnion'] ?? artist) as Map<String, dynamic>;

  final topTracksList =
      (artist['discography']?['topTracks']?['items'] as List?)
          ?.map(
            (t) => spotifyInternalTrackToGeneric(
              (t as Map<String, dynamic>)['track'] ?? t,
            ),
          )
          .toList() ??
      [];

  GenericSimpleAlbum extractAlbum(dynamic a) {
    final item = a as Map<String, dynamic>;
    if (item['releases'] != null &&
        item['releases']['items'] is List &&
        (item['releases']['items'] as List).isNotEmpty) {
      return spotifyInternalSimplifiedAlbumToGeneric(
        (item['releases']['items'] as List)[0] as Map<String, dynamic>,
      );
    }
    return spotifyInternalSimplifiedAlbumToGeneric(item);
  }

  final popularReleases =
      (artist['discography']?['popularReleasesAlbums']?['items'] as List?)
          ?.map(extractAlbum)
          .toList() ??
      [];

  var albums =
      (artist['discography']?['albums']?['items'] as List?)
          ?.map(extractAlbum)
          .toList() ??
      [];

  if (albums.isEmpty && popularReleases.isNotEmpty) {
    albums = popularReleases;
  } else if (popularReleases.isNotEmpty) {
    // Add popular releases at the beginning if they are not already in the list
    final albumIds = albums.map((a) => a.id).toSet();
    final toAdd = popularReleases
        .where((a) => !albumIds.contains(a.id))
        .toList();
    albums.insertAll(0, toAdd);
  }

  final thumbSources = _extractImageSources(artist);
  final bioText =
      artist['profile']?['biography']?['text'] as String? ??
      artist['profile']?['biography']?['body'] as String? ??
      artist['profile']?['about'] as String? ??
      artist['description'] as String?;

  final uri = artist['uri'] as String? ?? '';
  final id = uri.isNotEmpty
      ? uri.split(':').last
      : artist['id'] as String? ?? '';

  return GenericArtist(
    id: id,
    source: SongSource.spotifyInternal,
    name: artist['profile']?['name'] as String? ?? 'Unknown Artist',
    thumbnailUrl: _getLargestImage(thumbSources),
    description: bioText,
    monthlyListeners: artist['stats']?['monthlyListeners'] as int? ?? 0,
    followers: artist['stats']?['followers'] as int? ?? 0,
    topSongs: topTracksList,
    albums: albums,
  );
}

GenericLibrary spotifyInternalLibraryToGeneric(Map<String, dynamic> library) {
  library = library['data']['me']['libraryV3'] as Map<String, dynamic>;

  final libraryItems = (library['items'] as List)
      .map((e) => e as Map<String, dynamic>)
      .toList();
  if (libraryItems.isNotEmpty) {
    // First element corresponds to 'Liked Songs' — remove it (handled specially)
    libraryItems.removeAt(0);
  }

  final allOrdered = [];
  final albums = List<GenericAlbum>.empty(growable: true);
  final playlists = List<GenericPlaylist>.empty(growable: true);
  final artists = List<GenericArtist>.empty(growable: true);

  for (var item in libraryItems) {
    item = item['item'] as Map<String, dynamic>;
    final typename = item['data']?['__typename'] as String? ?? '';

    switch (typename) {
      case 'Album':
        allOrdered.add(
          spotifyInternalSimplifiedAlbumToGeneric(
            item['data'] as Map<String, dynamic>,
          ),
        );
        albums.add(
          spotifyInternalFullAlbumToGeneric(
            item['data'] as Map<String, dynamic>,
          ),
        );
        break;
      case 'Playlist':
        allOrdered.add(
          spotifyInternalFullPlaylistToGeneric(
            item['data'] as Map<String, dynamic>,
          ),
        );
        playlists.add(
          spotifyInternalFullPlaylistToGeneric(
            item['data'] as Map<String, dynamic>,
          ),
        );
        break;
      case 'Folder':
        // Represent folder entries as a simple map so callers can detect and import them
        final folder = item['data'] as Map<String, dynamic>;
        final folderMap = {
          '__typename': 'Folder',
          'uri': folder['uri'] as String? ?? folder['_uri'] as String? ?? '',
          'id':
              (folder['uri'] as String? ?? folder['_uri'] as String? ?? '')
                  .toString()
                  .split(':')
                  .isNotEmpty
              ? ((folder['uri'] as String? ?? folder['_uri'] as String?)!
                    .toString())
              : '',
          'name': folder['name'] as String? ?? '',
          'playlistCount': folder['playlistCount'] as int? ?? 0,
        };
        allOrdered.add(folderMap);
        break;
      case 'Artist':
        allOrdered.add(
          spotifyInternalArtistToGeneric(item['data'] as Map<String, dynamic>),
        );
        artists.add(
          spotifyInternalFullArtistToGeneric(
            item['data'] as Map<String, dynamic>,
          ),
        );
        break;
      default:
        break;
    }
  }
  return GenericLibrary(
    all_organized: allOrdered,
    saved_albums: albums,
    saved_playlists: playlists,
    saved_artists: artists,
  );
}

String _extractHomeSectionTitle(Map<String, dynamic> section) {
  final data = section['data'] as Map<String, dynamic>? ?? {};
  final title = data['title'];
  if (title is String) return title;
  if (title is Map) {
    return title['transformedLabel'] as String? ??
        title['translatedBaseText'] as String? ??
        '';
  }
  final headerEntity = data['headerEntity'] as Map<String, dynamic>? ?? {};
  final headerTitle = headerEntity['title'];
  if (headerTitle is String) return headerTitle;
  if (headerTitle is Map) {
    return headerTitle['transformedLabel'] as String? ??
        headerTitle['translatedBaseText'] as String? ??
        '';
  }
  return data['name'] as String? ?? '';
}

dynamic _convertHomeSectionItem(Map<String, dynamic> item) {
  final content = item['content'] as Map<String, dynamic>? ?? {};
  final contentType = content['__typename'] as String? ?? '';
  final data = (content['data'] as Map<String, dynamic>?) ?? content;

  Map<String, dynamic> normalizeData() {
    if (data.containsKey('data') && data['data'] is Map<String, dynamic>) {
      return data['data'] as Map<String, dynamic>;
    }
    return data;
  }

  switch (contentType) {
    case 'PlaylistResponseWrapper':
      return spotifyInternalFullPlaylistToGeneric(normalizeData());
    case 'AlbumResponseWrapper':
      return spotifyInternalFullAlbumToGeneric(normalizeData());
    case 'ArtistResponseWrapper':
      return spotifyInternalArtistToGeneric(normalizeData());
    case 'TrackResponseWrapper':
      return spotifyInternalTrackToGeneric(normalizeData());
    default:
      break;
  }

  final typename = data['__typename'] as String? ?? '';
  switch (typename) {
    case 'Playlist':
      return spotifyInternalFullPlaylistToGeneric(data);
    case 'Album':
      return spotifyInternalFullAlbumToGeneric(data);
    case 'Artist':
      return spotifyInternalArtistToGeneric(data);
    case 'Track':
      return spotifyInternalTrackToGeneric(data);
    default:
      return null;
  }
}

GenericHome spotifyInternalHomeToGeneric(Map<String, dynamic> response) {
  final home =
      (response['data']?['home'] as Map<String, dynamic>?) ??
      response['home'] as Map<String, dynamic>? ??
      response;

  final sectionItems =
      home['sectionContainer']?['sections']?['items'] as List? ?? [];
  final sections = <String, List<dynamic>>{};

  for (final raw in sectionItems) {
    if (raw is! Map<String, dynamic>) continue;
    final title = _extractHomeSectionTitle(raw);
    final items = (raw['sectionItems']?['items'] as List?) ?? [];
    final converted = items
        .whereType<Map<String, dynamic>>()
        .map(_convertHomeSectionItem)
        .where((item) => item != null)
        .cast<dynamic>()
        .toList();

    if (converted.isEmpty) continue;
    final key = title.isNotEmpty ? title : 'Section ${sections.length + 1}';
    sections[key] = converted;
  }

  return GenericHome(sections: sections);
}

Map<String, dynamic> _extractSearchRoot(Map<String, dynamic> response) {
  return (response['data']?['searchV2'] as Map<String, dynamic>?) ??
      (response['searchV2'] as Map<String, dynamic>?) ??
      response;
}

List<GenericSong> spotifyInternalSearchTracks(Map<String, dynamic> response) {
  final root = _extractSearchRoot(response);
  final items =
      (root['tracksV2']?['items'] as List?) ??
      (root['tracks']?['items'] as List?) ??
      const [];
  return items.whereType<Map<String, dynamic>>().map((item) {
    final wrapper = item['item'] as Map<String, dynamic>? ?? item;
    final data = wrapper['data'] as Map<String, dynamic>? ?? wrapper;
    return spotifyInternalTrackToGeneric(data);
  }).toList();
}

List<GenericSimpleArtist> spotifyInternalSearchArtists(
  Map<String, dynamic> response,
) {
  final root = _extractSearchRoot(response);
  final items =
      (root['artists']?['items'] as List?) ??
      (root['artistsV2']?['items'] as List?) ??
      const [];
  return items.whereType<Map<String, dynamic>>().map((item) {
    final data = item['data'] as Map<String, dynamic>? ?? item;
    return spotifyInternalArtistToGeneric(data);
  }).toList();
}

List<GenericAlbum> spotifyInternalSearchAlbums(Map<String, dynamic> response) {
  final root = _extractSearchRoot(response);
  final items =
      (root['albumsV2']?['items'] as List?) ??
      (root['albums']?['items'] as List?) ??
      const [];
  return items.whereType<Map<String, dynamic>>().map((item) {
    final data = item['data'] as Map<String, dynamic>? ?? item;
    return spotifyInternalFullAlbumToGeneric(data);
  }).toList();
}

List<GenericPlaylist> spotifyInternalSearchPlaylists(
  Map<String, dynamic> response,
) {
  final root = _extractSearchRoot(response);
  final items =
      (root['playlists']?['items'] as List?) ??
      (root['playlistsV2']?['items'] as List?) ??
      const [];
  return items.whereType<Map<String, dynamic>>().map((item) {
    final data = item['data'] as Map<String, dynamic>? ?? item;
    return spotifyInternalFullPlaylistToGeneric(data);
  }).toList();
}
