class InnerTubeSearchResult {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final String? thumbnailUrl;
  final String type; // 'track', 'album', 'artist', 'playlist'

  const InnerTubeSearchResult({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.duration,
    this.thumbnailUrl,
    required this.type,
  });

  factory InnerTubeSearchResult.fromJson(Map<String, dynamic> json) {
    final durSec = json['durationSeconds'] as num?;
    return InnerTubeSearchResult(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      duration: durSec != null ? Duration(seconds: durSec.toInt()) : null,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      type: json['type'] as String? ?? 'track',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'durationSeconds': duration?.inSeconds,
        'thumbnailUrl': thumbnailUrl,
        'type': type,
      };
}

class InnerTubeTrack {
  final String videoId;
  final String title;
  final String author;
  final String? authorId;
  final Duration duration;
  final String? description;
  final String? thumbnailUrl;
  final bool hasLyrics;
  final bool isSabrAvailable;

  const InnerTubeTrack({
    required this.videoId,
    required this.title,
    required this.author,
    this.authorId,
    required this.duration,
    this.description,
    this.thumbnailUrl,
    this.hasLyrics = false,
    this.isSabrAvailable = false,
  });

  factory InnerTubeTrack.fromJson(Map<String, dynamic> json) {
    final durSec = json['durationSeconds'] as num? ?? 0;
    return InnerTubeTrack(
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      authorId: json['authorId'] as String?,
      duration: Duration(seconds: durSec.toInt()),
      description: json['description'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      hasLyrics: json['hasLyrics'] as bool? ?? false,
      isSabrAvailable: json['isSabrAvailable'] as bool? ?? false,
    );
  }
}

class InnerTubeAlbumTrack {
  final String videoId;
  final String title;
  final String artist;
  final Duration duration;
  final int index;

  const InnerTubeAlbumTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.duration,
    required this.index,
  });

  factory InnerTubeAlbumTrack.fromJson(Map<String, dynamic> json) {
    final durSec = json['durationSeconds'] as num? ?? 0;
    return InnerTubeAlbumTrack(
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      duration: Duration(seconds: durSec.toInt()),
      index: (json['index'] as num? ?? 1).toInt(),
    );
  }
}

class InnerTubeAlbum {
  final String browseId;
  final String title;
  final String artist;
  final String? artistId;
  final String? year;
  final String? thumbnailUrl;
  final int trackCount;
  final List<InnerTubeAlbumTrack> tracks;

  const InnerTubeAlbum({
    required this.browseId,
    required this.title,
    required this.artist,
    this.artistId,
    this.year,
    this.thumbnailUrl,
    required this.trackCount,
    this.tracks = const [],
  });

  factory InnerTubeAlbum.fromJson(Map<String, dynamic> json) {
    final tracksList = (json['tracks'] as List?)
            ?.map((e) => InnerTubeAlbumTrack.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    return InnerTubeAlbum(
      browseId: json['browseId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      artistId: json['artistId'] as String?,
      year: json['year'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      trackCount: (json['trackCount'] as num? ?? tracksList.length).toInt(),
      tracks: tracksList,
    );
  }
}

class InnerTubeArtist {
  final String browseId;
  final String name;
  final String? bio;
  final String? avatarUrl;
  final List<InnerTubeSearchResult> topTracks;
  final List<InnerTubeSearchResult> albums;
  final List<InnerTubeSearchResult> singles;

  const InnerTubeArtist({
    required this.browseId,
    required this.name,
    this.bio,
    this.avatarUrl,
    this.topTracks = const [],
    this.albums = const [],
    this.singles = const [],
  });

  factory InnerTubeArtist.fromJson(Map<String, dynamic> json) {
    List<InnerTubeSearchResult> parseItems(String key) =>
        (json[key] as List?)
            ?.map((e) => InnerTubeSearchResult.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

    return InnerTubeArtist(
      browseId: json['browseId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      bio: json['bio'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      topTracks: parseItems('topTracks'),
      albums: parseItems('albums'),
      singles: parseItems('singles'),
    );
  }
}

class InnerTubePlaylist {
  final String browseId;
  final String title;
  final String? author;
  final String? description;
  final int trackCount;
  final String? thumbnailUrl;
  final List<InnerTubeSearchResult> tracks;

  const InnerTubePlaylist({
    required this.browseId,
    required this.title,
    this.author,
    this.description,
    required this.trackCount,
    this.thumbnailUrl,
    this.tracks = const [],
  });

  factory InnerTubePlaylist.fromJson(Map<String, dynamic> json) {
    final items = (json['tracks'] as List?)
            ?.map((e) => InnerTubeSearchResult.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    return InnerTubePlaylist(
      browseId: json['browseId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String?,
      description: json['description'] as String?,
      trackCount: (json['trackCount'] as num? ?? items.length).toInt(),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      tracks: items,
    );
  }
}

class InnerTubeAuthStatus {
  final bool authenticated;
  final String? userDisplayName;
  final String? userId;
  final String? email;

  const InnerTubeAuthStatus({
    required this.authenticated,
    this.userDisplayName,
    this.userId,
    this.email,
  });

  factory InnerTubeAuthStatus.fromJson(Map<String, dynamic> json) {
    return InnerTubeAuthStatus(
      authenticated: json['authenticated'] as bool? ?? false,
      userDisplayName: json['userDisplayName'] as String?,
      userId: json['userId'] as String?,
      email: json['email'] as String?,
    );
  }
}
