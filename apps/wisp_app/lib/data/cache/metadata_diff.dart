// Copyright © 2026 wizeshi

/// Deep structural diff comparison utilities for metadata entities
library;

import 'package:wisp/data/models/metadata_models.dart';

class MetadataDiff {
  MetadataDiff._();

  /// Compares two [GenericPlaylist] objects for UI-meaningful differences.
  static bool hasPlaylistChanged(GenericPlaylist? a, GenericPlaylist? b) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;

    if (a.id != b.id ||
        a.title != b.title ||
        a.description != b.description ||
        a.thumbnailUrl != b.thumbnailUrl ||
        a.durationSecs != b.durationSecs ||
        a.total != b.total ||
        a.hasMore != b.hasMore ||
        a.author.displayName != b.author.displayName ||
        a.author.avatarUrl != b.author.avatarUrl) {
      return true;
    }

    return hasPlaylistItemListChanged(a.songs, b.songs);
  }

  /// Compares two lists of [PlaylistItem]s.
  static bool hasPlaylistItemListChanged(
    List<PlaylistItem>? a,
    List<PlaylistItem>? b,
  ) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;
    if (a.length != b.length) return true;

    for (int i = 0; i < a.length; i++) {
      final s1 = a[i];
      final s2 = b[i];
      if (identical(s1, s2)) continue;

      if (s1.id != s2.id ||
          s1.uid != s2.uid ||
          s1.source != s2.source ||
          s1.title != s2.title ||
          s1.durationSecs != s2.durationSecs ||
          s1.thumbnailUrl != s2.thumbnailUrl ||
          s1.explicit != s2.explicit ||
          s1.trackNumber != s2.trackNumber ||
          s1.addedAt != s2.addedAt ||
          s1.album?.id != s2.album?.id ||
          s1.album?.title != s2.album?.title) {
        return true;
      }

      if (s1.artists.length != s2.artists.length) return true;
      for (int j = 0; j < s1.artists.length; j++) {
        if (identical(s1.artists[j], s2.artists[j])) continue;
        if (s1.artists[j].id != s2.artists[j].id ||
            s1.artists[j].name != s2.artists[j].name) {
          return true;
        }
      }
    }

    return false;
  }

  /// Compares two [GenericAlbum] objects.
  static bool hasAlbumChanged(GenericAlbum? a, GenericAlbum? b) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;

    if (a.id != b.id ||
        a.title != b.title ||
        a.thumbnailUrl != b.thumbnailUrl ||
        a.label != b.label ||
        a.releaseDate != b.releaseDate ||
        a.explicit != b.explicit ||
        a.durationSecs != b.durationSecs ||
        a.total != b.total ||
        a.hasMore != b.hasMore) {
      return true;
    }

    if (a.artists.length != b.artists.length) return true;
    for (int i = 0; i < a.artists.length; i++) {
      if (identical(a.artists[i], b.artists[i])) continue;
      if (a.artists[i].id != b.artists[i].id ||
          a.artists[i].name != b.artists[i].name) {
        return true;
      }
    }

    return hasSongListChanged(a.songs, b.songs);
  }

  /// Compares two lists of [GenericSong]s.
  static bool hasSongListChanged(List<GenericSong>? a, List<GenericSong>? b) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;
    if (a.length != b.length) return true;

    for (int i = 0; i < a.length; i++) {
      final s1 = a[i];
      final s2 = b[i];
      if (identical(s1, s2)) continue;

      if (s1.id != s2.id ||
          s1.source != s2.source ||
          s1.title != s2.title ||
          s1.durationSecs != s2.durationSecs ||
          s1.thumbnailUrl != s2.thumbnailUrl ||
          s1.explicit != s2.explicit ||
          s1.album?.id != s2.album?.id ||
          s1.album?.title != s2.album?.title) {
        return true;
      }

      if (s1.artists.length != s2.artists.length) return true;
      for (int j = 0; j < s1.artists.length; j++) {
        if (identical(s1.artists[j], s2.artists[j])) continue;
        if (s1.artists[j].id != s2.artists[j].id ||
            s1.artists[j].name != s2.artists[j].name) {
          return true;
        }
      }
    }

    return false;
  }

  /// Compares two [GenericArtist] objects.
  static bool hasArtistChanged(GenericArtist? a, GenericArtist? b) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;

    if (a.id != b.id ||
        a.name != b.name ||
        a.thumbnailUrl != b.thumbnailUrl ||
        a.description != b.description ||
        a.followers != b.followers ||
        a.monthlyListeners != b.monthlyListeners) {
      return true;
    }

    if (hasSongListChanged(a.topSongs, b.topSongs)) return true;

    if (a.albums.length != b.albums.length) return true;
    for (int i = 0; i < a.albums.length; i++) {
      if (identical(a.albums[i], b.albums[i])) continue;
      if (a.albums[i].id != b.albums[i].id ||
          a.albums[i].title != b.albums[i].title ||
          a.albums[i].thumbnailUrl != b.albums[i].thumbnailUrl) {
        return true;
      }
    }

    return false;
  }

  /// Compares two [GenericUser] objects.
  static bool hasUserChanged(GenericUser? a, GenericUser? b) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;

    if (a.id != b.id ||
        a.displayName != b.displayName ||
        a.avatarUrl != b.avatarUrl ||
        a.followerCount != b.followerCount ||
        a.followingCount != b.followingCount ||
        a.publicPlaylists.length != b.publicPlaylists.length) {
      return true;
    }

    for (int i = 0; i < a.publicPlaylists.length; i++) {
      if (identical(a.publicPlaylists[i], b.publicPlaylists[i])) continue;
      if (a.publicPlaylists[i].id != b.publicPlaylists[i].id ||
          a.publicPlaylists[i].title != b.publicPlaylists[i].title) {
        return true;
      }
    }

    return false;
  }
}
