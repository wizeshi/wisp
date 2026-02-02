/// Generic metadata models for multi-source music providers
/// Matches Rust implementation from song_types.rs
library;

enum SongSource {
  local,
  spotify,
  youtube,
  soundcloud;

  String toJson() => name;

  static SongSource fromJson(String json) {
    return SongSource.values.firstWhere(
      (e) => e.name == json,
      orElse: () => SongSource.spotify,
    );
  }
}

class GenericSimpleArtist {
  final String id;
  final SongSource source;
  final String name;
  final String thumbnailUrl;

  GenericSimpleArtist({
    required this.id,
    required this.source,
    required this.name,
    required this.thumbnailUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.toJson(),
        'name': name,
        'thumbnail_url': thumbnailUrl,
      };

  factory GenericSimpleArtist.fromJson(Map<String, dynamic> json) {
    return GenericSimpleArtist(
      id: json['id'] as String,
      source: SongSource.fromJson(json['source'] as String),
      name: json['name'] as String,
      thumbnailUrl: json['thumbnail_url'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenericSimpleArtist &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          source == other.source &&
          name == other.name &&
          thumbnailUrl == other.thumbnailUrl;

  @override
  int get hashCode =>
      id.hashCode ^ source.hashCode ^ name.hashCode ^ thumbnailUrl.hashCode;
}

class GenericSimpleAlbum {
  final String id;
  final SongSource source;
  final String title;
  final String thumbnailUrl;
  final List<GenericSimpleArtist> artists;
  final String label;
  final DateTime releaseDate;

  GenericSimpleAlbum({
    required this.id,
    required this.source,
    required this.title,
    required this.thumbnailUrl,
    required this.artists,
    required this.label,
    required this.releaseDate,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.toJson(),
        'title': title,
        'thumbnail_url': thumbnailUrl,
        'artists': artists.map((a) => a.toJson()).toList(),
        'label': label,
        'release_date': releaseDate.toIso8601String(),
      };

  factory GenericSimpleAlbum.fromJson(Map<String, dynamic> json) {
    return GenericSimpleAlbum(
      id: json['id'] as String,
      source: SongSource.fromJson(json['source'] as String),
      title: json['title'] as String,
      thumbnailUrl: json['thumbnail_url'] as String,
      artists: (json['artists'] as List)
          .map((a) => GenericSimpleArtist.fromJson(a as Map<String, dynamic>))
          .toList(),
      label: json['label'] as String,
      releaseDate: DateTime.parse(json['release_date'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenericSimpleAlbum &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          source == other.source;

  @override
  int get hashCode => id.hashCode ^ source.hashCode;
}

class GenericSong {
  final String id;
  final SongSource source;
  final String title;
  final List<GenericSimpleArtist> artists;
  final String thumbnailUrl;
  final bool explicit;
  final GenericSimpleAlbum? album;
  final int durationSecs;

  GenericSong({
    required this.id,
    required this.source,
    required this.title,
    required this.artists,
    required this.thumbnailUrl,
    required this.explicit,
    this.album,
    required this.durationSecs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.toJson(),
        'title': title,
        'artists': artists.map((a) => a.toJson()).toList(),
        'thumbnail_url': thumbnailUrl,
        'explicit': explicit,
        'album': album?.toJson(),
        'duration_secs': durationSecs,
      };

  factory GenericSong.fromJson(Map<String, dynamic> json) {
    return GenericSong(
      id: json['id'] as String,
      source: SongSource.fromJson(json['source'] as String),
      title: json['title'] as String,
      artists: (json['artists'] as List)
          .map((a) => GenericSimpleArtist.fromJson(a as Map<String, dynamic>))
          .toList(),
      thumbnailUrl: json['thumbnail_url'] as String,
      explicit: json['explicit'] as bool,
      album: json['album'] != null
          ? GenericSimpleAlbum.fromJson(json['album'] as Map<String, dynamic>)
          : null,
      durationSecs: json['duration_secs'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenericSong &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          source == other.source;

  @override
  int get hashCode => id.hashCode ^ source.hashCode;
}

class GenericAlbum {
  final String id;
  final SongSource source;
  final String title;
  final String thumbnailUrl;
  final List<GenericSimpleArtist> artists;
  final String label;
  final DateTime releaseDate;
  final bool explicit;
  final List<GenericSong>? songs;
  final int durationSecs;
  final int? total;
  final bool? hasMore;

  GenericAlbum({
    required this.id,
    required this.source,
    required this.title,
    required this.thumbnailUrl,
    required this.artists,
    required this.label,
    required this.releaseDate,
    required this.explicit,
    this.songs,
    required this.durationSecs,
    this.total,
    this.hasMore,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.toJson(),
        'title': title,
        'thumbnail_url': thumbnailUrl,
        'artists': artists.map((a) => a.toJson()).toList(),
        'label': label,
        'release_date': releaseDate.toIso8601String(),
        'explicit': explicit,
        'songs': songs?.map((s) => s.toJson()).toList(),
        'duration_secs': durationSecs,
        'total': total,
        'has_more': hasMore,
      };

  factory GenericAlbum.fromJson(Map<String, dynamic> json) {
    return GenericAlbum(
      id: json['id'] as String,
      source: SongSource.fromJson(json['source'] as String),
      title: json['title'] as String,
      thumbnailUrl: json['thumbnail_url'] as String,
      artists: (json['artists'] as List)
          .map((a) => GenericSimpleArtist.fromJson(a as Map<String, dynamic>))
          .toList(),
      label: json['label'] as String,
      releaseDate: DateTime.parse(json['release_date'] as String),
      explicit: json['explicit'] as bool,
      songs: json['songs'] != null
          ? (json['songs'] as List)
              .map((s) => GenericSong.fromJson(s as Map<String, dynamic>))
              .toList()
          : null,
      durationSecs: json['duration_secs'] as int,
      total: json['total'] as int?,
      hasMore: json['has_more'] as bool?,
    );
  }
}

class GenericSimpleUser {
  final String id;
  final SongSource source;
  final String displayName;
  final String? avatarUrl;
  final int? followerCount;
  final String? profileUrl;

  GenericSimpleUser({
    required this.id,
    required this.source,
    required this.displayName,
    this.avatarUrl,
    this.followerCount,
    this.profileUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.toJson(),
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'follower_count': followerCount,
        'profile_url': profileUrl,
      };

  factory GenericSimpleUser.fromJson(Map<String, dynamic> json) {
    return GenericSimpleUser(
      id: json['id'] as String,
      source: SongSource.fromJson(json['source'] as String),
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      followerCount: json['follower_count'] as int?,
      profileUrl: json['profile_url'] as String?,
    );
  }
}

class PlaylistItem {
  final String id;
  final SongSource source;
  final String title;
  final List<GenericSimpleArtist> artists;
  final String thumbnailUrl;
  final bool explicit;
  final GenericSimpleAlbum? album;
  final int durationSecs;
  final DateTime addedAt;
  final int trackNumber;

  PlaylistItem({
    required this.id,
    required this.source,
    required this.title,
    required this.artists,
    required this.thumbnailUrl,
    required this.explicit,
    this.album,
    required this.durationSecs,
    required this.addedAt,
    required this.trackNumber,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.toJson(),
        'title': title,
        'artists': artists.map((a) => a.toJson()).toList(),
        'thumbnail_url': thumbnailUrl,
        'explicit': explicit,
        'album': album?.toJson(),
        'duration_secs': durationSecs,
        'added_at': addedAt.toIso8601String(),
        'track_number': trackNumber,
      };

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      id: json['id'] as String,
      source: SongSource.fromJson(json['source'] as String),
      title: json['title'] as String,
      artists: (json['artists'] as List)
          .map((a) => GenericSimpleArtist.fromJson(a as Map<String, dynamic>))
          .toList(),
      thumbnailUrl: json['thumbnail_url'] as String,
      explicit: json['explicit'] as bool,
      album: json['album'] != null
          ? GenericSimpleAlbum.fromJson(json['album'] as Map<String, dynamic>)
          : null,
      durationSecs: json['duration_secs'] as int,
      addedAt: DateTime.parse(json['added_at'] as String),
      trackNumber: json['track_number'] as int,
    );
  }
}

class GenericPlaylist {
  final String id;
  final SongSource source;
  final String title;
  final String thumbnailUrl;
  final GenericSimpleUser author;
  final List<PlaylistItem>? songs;
  final int durationSecs;
  final int? total;
  final bool? hasMore;

  GenericPlaylist({
    required this.id,
    required this.source,
    required this.title,
    required this.thumbnailUrl,
    required this.author,
    this.songs,
    required this.durationSecs,
    this.total,
    this.hasMore,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.toJson(),
        'title': title,
        'thumbnail_url': thumbnailUrl,
        'author': author.toJson(),
        'songs': songs?.map((s) => s.toJson()).toList(),
        'duration_secs': durationSecs,
        'total': total,
        'has_more': hasMore,
      };

  factory GenericPlaylist.fromJson(Map<String, dynamic> json) {
    return GenericPlaylist(
      id: json['id'] as String,
      source: SongSource.fromJson(json['source'] as String),
      title: json['title'] as String,
      thumbnailUrl: json['thumbnail_url'] as String,
      author:
          GenericSimpleUser.fromJson(json['author'] as Map<String, dynamic>),
      songs: json['songs'] != null
          ? (json['songs'] as List)
              .map((s) => PlaylistItem.fromJson(s as Map<String, dynamic>))
              .toList()
          : null,
      durationSecs: json['duration_secs'] as int,
      total: json['total'] as int?,
      hasMore: json['has_more'] as bool?,
    );
  }
}

class GenericArtist {
  final String id;
  final SongSource source;
  final String name;
  final String thumbnailUrl;
  final int monthlyListeners;
  final List<GenericSong> topSongs;
  final List<GenericSimpleAlbum> albums;

  GenericArtist({
    required this.id,
    required this.source,
    required this.name,
    required this.thumbnailUrl,
    required this.monthlyListeners,
    required this.topSongs,
    required this.albums,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.toJson(),
        'name': name,
        'thumbnail_url': thumbnailUrl,
        'monthly_listeners': monthlyListeners,
        'top_songs': topSongs.map((s) => s.toJson()).toList(),
        'albums': albums.map((a) => a.toJson()).toList(),
      };

  factory GenericArtist.fromJson(Map<String, dynamic> json) {
    return GenericArtist(
      id: json['id'] as String,
      source: SongSource.fromJson(json['source'] as String),
      name: json['name'] as String,
      thumbnailUrl: json['thumbnail_url'] as String,
      monthlyListeners: json['monthly_listeners'] as int,
      topSongs: (json['top_songs'] as List)
          .map((s) => GenericSong.fromJson(s as Map<String, dynamic>))
          .toList(),
      albums: (json['albums'] as List)
          .map((a) => GenericSimpleAlbum.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum LyricsProviderType {
  spotify,
  lrclib;

  String get label => name;
}

enum LyricsSyncMode {
  synced,
  unsynced;

  String get label => this == LyricsSyncMode.synced ? 'Synced' : 'Unsynced';
}

class LyricsLine {
  final String content;
  final int startTimeMs;

  const LyricsLine({
    required this.content,
    required this.startTimeMs,
  });
}

class LyricsResult {
  final LyricsProviderType provider;
  final bool synced;
  final List<LyricsLine> lines;

  const LyricsResult({
    required this.provider,
    required this.synced,
    required this.lines,
  });
}
