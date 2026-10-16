// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/cache/metadata_diff.dart';
import 'package:wisp/data/models/metadata_models.dart';

void main() {
  group('ListDetailView and LibraryState playlist synchronization', () {
    final user = GenericSimpleUser(
      id: 'author_1',
      source: 'spotify',
      displayName: 'Tester',
    );

    final track1 = PlaylistItem(
      id: 'song1',
      source: 'spotify',
      title: 'Track One',
      artists: [
        GenericSimpleArtist(
          id: 'art1',
          source: 'spotify',
          name: 'Artist A',
          thumbnailUrl: '',
        ),
      ],
      thumbnailUrl: '',
      explicit: false,
      durationSecs: 200,
      addedAt: DateTime(2025, 1, 1),
      trackNumber: 1,
    );

    test('GenericPlaylist correctly decodes null songs when tracks are omitted', () {
      final jsonWithoutSongs = {
        'id': 'pl_1',
        'source': 'spotify',
        'title': 'My Playlist',
        'description': 'A cool playlist',
        'thumbnail_url': 'https://example.com/cover.jpg',
        'author': user.toJson(),
        'duration_secs': 0,
        'total': 10,
        'has_more': true,
        'is_pinned': false,
      };

      final playlist = GenericPlaylist.fromJson(jsonWithoutSongs);
      expect(playlist.songs, isNull);
    });

    test('GenericAlbum correctly decodes null songs when tracks are omitted', () {
      final jsonWithoutSongs = {
        'id': 'alb_1',
        'source': 'spotify',
        'title': 'My Album',
        'thumbnail_url': 'https://example.com/album.jpg',
        'artists': [
          {'id': 'art1', 'source': 'spotify', 'name': 'Artist A', 'thumbnail_url': ''}
        ],
        'label': 'Test Label',
        'release_date': DateTime(2025, 1, 1).toIso8601String(),
        'explicit': false,
        'duration_secs': 0,
        'total': 12,
        'has_more': true,
      };

      final album = GenericAlbum.fromJson(jsonWithoutSongs);
      expect(album.songs, isNull);
    });

    test('Loaded playlist tracks are preserved when library update has null or empty songs', () {
      // 1. Initial state: playlist loaded with 1 track
      GenericPlaylist playlist = GenericPlaylist(
        id: 'pl_1',
        source: 'spotify',
        title: 'Original Title',
        thumbnailUrl: '',
        author: user,
        durationSecs: 200,
        total: 1,
        songs: [track1],
        isPinned: false,
      );

      // 2. LibraryState emits update with updated metadata but null songs
      final libraryUpdateNullSongs = GenericPlaylist(
        id: 'pl_1',
        source: 'spotify',
        title: 'Renamed Title',
        thumbnailUrl: '',
        author: user,
        durationSecs: 0,
        total: 1,
        songs: null,
        isPinned: true,
      );

      // Mirror the guarded logic in SharedListDetailView._libraryListener
      final updatedSongs = libraryUpdateNullSongs.songs;
      final hasIncomingTracks = updatedSongs != null && updatedSongs.isNotEmpty;
      if (hasIncomingTracks) {
        playlist = playlist.copyWith(
          title: libraryUpdateNullSongs.title,
          isPinned: libraryUpdateNullSongs.isPinned,
          songs: updatedSongs,
        );
      } else {
        playlist = playlist.copyWith(
          title: libraryUpdateNullSongs.title,
          isPinned: libraryUpdateNullSongs.isPinned,
        );
      }

      // Title & pinned updated, but songs preserved!
      expect(playlist.title, equals('Renamed Title'));
      expect(playlist.isPinned, isTrue);
      expect(playlist.songs, isNotNull);
      expect(playlist.songs!.length, equals(1));
      expect(playlist.songs!.first.id, equals('song1'));

      // 3. LibraryState emits update with empty songs list
      final libraryUpdateEmptySongs = GenericPlaylist(
        id: 'pl_1',
        source: 'spotify',
        title: 'Renamed Again',
        thumbnailUrl: '',
        author: user,
        durationSecs: 0,
        total: 1,
        songs: const [],
        isPinned: true,
      );

      final updatedSongs2 = libraryUpdateEmptySongs.songs;
      final hasIncomingTracks2 = updatedSongs2 != null && updatedSongs2.isNotEmpty;
      if (hasIncomingTracks2) {
        playlist = playlist.copyWith(
          title: libraryUpdateEmptySongs.title,
          songs: updatedSongs2,
        );
      } else {
        playlist = playlist.copyWith(
          title: libraryUpdateEmptySongs.title,
        );
      }

      // Title updated, songs still preserved!
      expect(playlist.title, equals('Renamed Again'));
      expect(playlist.songs, isNotNull);
      expect(playlist.songs!.length, equals(1));
      expect(playlist.songs!.first.id, equals('song1'));
    });

    test('Playlist tracks update when non-empty tracks are explicitly provided by LibraryState', () {
      GenericPlaylist playlist = GenericPlaylist(
        id: 'pl_1',
        source: 'spotify',
        title: 'My Playlist',
        thumbnailUrl: '',
        author: user,
        durationSecs: 200,
        total: 1,
        songs: [track1],
      );

      final track2 = PlaylistItem(
        id: 'song2',
        source: 'spotify',
        title: 'Track Two',
        artists: track1.artists,
        thumbnailUrl: '',
        explicit: false,
        durationSecs: 180,
        addedAt: DateTime(2025, 1, 2),
        trackNumber: 2,
      );

      final libraryUpdateWithSongs = GenericPlaylist(
        id: 'pl_1',
        source: 'spotify',
        title: 'My Playlist',
        thumbnailUrl: '',
        author: user,
        durationSecs: 380,
        total: 2,
        songs: [track1, track2],
      );

      final updatedSongs = libraryUpdateWithSongs.songs;
      final hasIncomingTracks = updatedSongs != null && updatedSongs.isNotEmpty;
      if (hasIncomingTracks) {
        if (MetadataDiff.hasPlaylistItemListChanged(playlist.songs, updatedSongs)) {
          playlist = playlist.copyWith(
            songs: updatedSongs,
            total: libraryUpdateWithSongs.total,
          );
        }
      }

      expect(playlist.songs!.length, equals(2));
      expect(playlist.songs![1].id, equals('song2'));
    });
  });
}
