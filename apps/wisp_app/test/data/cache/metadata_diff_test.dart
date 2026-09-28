// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/cache/metadata_diff.dart';
import 'package:wisp/data/models/metadata_models.dart';

void main() {
  group('MetadataDiff Tests', () {
    final artistA = GenericSimpleArtist(
      id: 'art1',
      source: 'spotify',
      name: 'Artist A',
      thumbnailUrl: 'https://img/artA',
    );
    final artistB = GenericSimpleArtist(
      id: 'art2',
      source: 'spotify',
      name: 'Artist B',
      thumbnailUrl: 'https://img/artB',
    );

    final song1 = GenericSong(
      id: 'song1',
      source: 'spotify',
      title: 'Track One',
      artists: [artistA],
      thumbnailUrl: 'https://img/1',
      explicit: false,
      durationSecs: 180,
    );

    final item1 = PlaylistItem(
      id: 'song1',
      source: 'spotify',
      title: 'Track One',
      artists: [artistA],
      thumbnailUrl: 'https://img/1',
      explicit: false,
      durationSecs: 180,
      addedAt: DateTime(2024, 1, 1),
      trackNumber: 1,
    );

    final item2 = PlaylistItem(
      id: 'song2',
      source: 'spotify',
      title: 'Track Two',
      artists: [artistB],
      thumbnailUrl: 'https://img/2',
      explicit: false,
      durationSecs: 200,
      addedAt: DateTime(2024, 1, 1),
      trackNumber: 2,
    );

    final user = GenericSimpleUser(
      id: 'user1',
      source: 'spotify',
      displayName: 'User One',
    );

    test('Playlist diff detection works accurately', () {
      final playlist1 = GenericPlaylist(
        id: 'pl1',
        source: 'spotify',
        title: 'Chill Vibes',
        description: 'Great beats',
        thumbnailUrl: 'https://img/pl',
        author: user,
        durationSecs: 380,
        total: 2,
        hasMore: false,
        songs: [item1, item2],
      );

      final playlist1Clone = GenericPlaylist(
        id: 'pl1',
        source: 'spotify',
        title: 'Chill Vibes',
        description: 'Great beats',
        thumbnailUrl: 'https://img/pl',
        author: user,
        durationSecs: 380,
        total: 2,
        hasMore: false,
        songs: [item1, item2],
      );

      // Identical or equal content
      expect(MetadataDiff.hasPlaylistChanged(playlist1, playlist1Clone), isFalse);

      // Title changed
      final titleChanged = GenericPlaylist(
        id: 'pl1',
        source: 'spotify',
        title: 'Chill Vibes Updated',
        description: 'Great beats',
        thumbnailUrl: 'https://img/pl',
        author: user,
        durationSecs: 380,
        total: 2,
        hasMore: false,
        songs: [item1, item2],
      );
      expect(MetadataDiff.hasPlaylistChanged(playlist1, titleChanged), isTrue);

      // Track added
      final trackAdded = GenericPlaylist(
        id: 'pl1',
        source: 'spotify',
        title: 'Chill Vibes',
        description: 'Great beats',
        thumbnailUrl: 'https://img/pl',
        author: user,
        durationSecs: 560,
        total: 3,
        hasMore: false,
        songs: [item1, item2, item1],
      );
      expect(MetadataDiff.hasPlaylistChanged(playlist1, trackAdded), isTrue);

      // Tracks reordered
      final tracksReordered = GenericPlaylist(
        id: 'pl1',
        source: 'spotify',
        title: 'Chill Vibes',
        description: 'Great beats',
        thumbnailUrl: 'https://img/pl',
        author: user,
        durationSecs: 380,
        total: 2,
        hasMore: false,
        songs: [item2, item1],
      );
      expect(MetadataDiff.hasPlaylistChanged(playlist1, tracksReordered), isTrue);
    });

    test('Album diff detection works accurately', () {
      final album1 = GenericAlbum(
        id: 'alb1',
        source: 'spotify',
        title: 'First Album',
        thumbnailUrl: 'https://img/alb',
        artists: [artistA],
        label: 'Label',
        releaseDate: DateTime(2024, 1, 1),
        explicit: false,
        durationSecs: 180,
        songs: [song1],
      );

      final album1Clone = GenericAlbum(
        id: 'alb1',
        source: 'spotify',
        title: 'First Album',
        thumbnailUrl: 'https://img/alb',
        artists: [artistA],
        label: 'Label',
        releaseDate: DateTime(2024, 1, 1),
        explicit: false,
        durationSecs: 180,
        songs: [song1],
      );

      expect(MetadataDiff.hasAlbumChanged(album1, album1Clone), isFalse);

      final albumChanged = GenericAlbum(
        id: 'alb1',
        source: 'spotify',
        title: 'First Album Deluxe',
        thumbnailUrl: 'https://img/alb',
        artists: [artistA],
        label: 'Label',
        releaseDate: DateTime(2024, 1, 1),
        explicit: false,
        durationSecs: 180,
        songs: [song1],
      );
      expect(MetadataDiff.hasAlbumChanged(album1, albumChanged), isTrue);
    });

    test('Artist diff detection works accurately', () {
      final artistEntity = GenericArtist(
        id: 'art1',
        source: 'spotify',
        name: 'Artist A',
        thumbnailUrl: 'https://img/art',
        followers: 1000,
        topSongs: [song1],
        albums: [],
      );

      final artistEntityClone = GenericArtist(
        id: 'art1',
        source: 'spotify',
        name: 'Artist A',
        thumbnailUrl: 'https://img/art',
        followers: 1000,
        topSongs: [song1],
        albums: [],
      );

      expect(MetadataDiff.hasArtistChanged(artistEntity, artistEntityClone), isFalse);

      final nameChanged = GenericArtist(
        id: 'art1',
        source: 'spotify',
        name: 'Artist A Renamed',
        thumbnailUrl: 'https://img/art',
        followers: 1000,
        topSongs: [song1],
        albums: [],
      );
      expect(MetadataDiff.hasArtistChanged(artistEntity, nameChanged), isTrue);
    });
  });
}
