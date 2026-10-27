import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_innertubex_manager/wisp_innertubex_manager.dart';

void main() {
  group('InnerTubeX Models Test', () {
    test('InnerTubeSearchResult fromJson / toJson', () {
      final json = {
        'id': 'abc1234',
        'title': 'Test Song',
        'artist': 'Test Artist',
        'album': 'Test Album',
        'durationSeconds': 180,
        'thumbnailUrl': 'https://example.com/thumb.jpg',
        'type': 'song',
      };

      final result = InnerTubeSearchResult.fromJson(json);
      expect(result.id, 'abc1234');
      expect(result.title, 'Test Song');
      expect(result.artist, 'Test Artist');
      expect(result.album, 'Test Album');
      expect(result.duration?.inSeconds, 180);
      expect(result.thumbnailUrl, 'https://example.com/thumb.jpg');
      expect(result.type, 'song');
      expect(result.toJson(), json);
    });

    test('InnerTubeTrack fromJson', () {
      final json = {
        'videoId': 'xyz987',
        'title': 'Track Title',
        'author': 'Artist Name',
        'authorId': 'UCartist',
        'durationSeconds': 210,
        'description': 'Track description',
        'thumbnailUrl': 'https://example.com/art.jpg',
        'hasLyrics': true,
        'isSabrAvailable': true,
      };

      final track = InnerTubeTrack.fromJson(json);
      expect(track.videoId, 'xyz987');
      expect(track.title, 'Track Title');
      expect(track.author, 'Artist Name');
      expect(track.authorId, 'UCartist');
      expect(track.duration.inSeconds, 210);
      expect(track.description, 'Track description');
      expect(track.thumbnailUrl, 'https://example.com/art.jpg');
      expect(track.hasLyrics, true);
      expect(track.isSabrAvailable, true);
    });

    test('InnerTubeAlbum fromJson', () {
      final json = {
        'browseId': 'MPREb_album',
        'title': 'Album Title',
        'artist': 'Artist',
        'year': '2024',
        'thumbnailUrl': 'https://example.com/cover.jpg',
        'trackCount': 1,
        'tracks': [
          {
            'videoId': 't1',
            'title': 'Track 1',
            'artist': 'Artist',
            'durationSeconds': 200,
            'index': 1,
          }
        ],
      };

      final album = InnerTubeAlbum.fromJson(json);
      expect(album.browseId, 'MPREb_album');
      expect(album.title, 'Album Title');
      expect(album.artist, 'Artist');
      expect(album.year, '2024');
      expect(album.tracks.length, 1);
      expect(album.tracks.first.videoId, 't1');
    });

    test('InnerTubeArtist fromJson', () {
      final json = {
        'browseId': 'UCartist',
        'name': 'Artist Name',
        'bio': 'Bio info',
        'avatarUrl': 'https://example.com/avatar.jpg',
        'topTracks': [
          {
            'id': 't1',
            'title': 'Top Song',
            'artist': 'Artist Name',
            'durationSeconds': 180,
            'thumbnailUrl': 'https://example.com/thumb.jpg',
            'type': 'track',
          }
        ],
      };

      final artist = InnerTubeArtist.fromJson(json);
      expect(artist.browseId, 'UCartist');
      expect(artist.name, 'Artist Name');
      expect(artist.topTracks.length, 1);
    });

    test('InnerTubePlaylist fromJson', () {
      final json = {
        'browseId': 'VLplaylist',
        'title': 'Playlist Title',
        'author': 'Author Name',
        'trackCount': 0,
        'thumbnailUrl': 'https://example.com/playlist.jpg',
        'tracks': <Map<String, dynamic>>[],
      };

      final playlist = InnerTubePlaylist.fromJson(json);
      expect(playlist.browseId, 'VLplaylist');
      expect(playlist.title, 'Playlist Title');
      expect(playlist.author, 'Author Name');
      expect(playlist.trackCount, 0);
    });

    test('InnerTubeAuthStatus fromJson', () {
      final json = {
        'authenticated': true,
        'userDisplayName': 'Demo User',
        'userId': '12345',
        'email': 'user@example.com',
      };

      final status = InnerTubeAuthStatus.fromJson(json);
      expect(status.authenticated, true);
      expect(status.userDisplayName, 'Demo User');
      expect(status.userId, '12345');
      expect(status.email, 'user@example.com');
    });
  });
}

