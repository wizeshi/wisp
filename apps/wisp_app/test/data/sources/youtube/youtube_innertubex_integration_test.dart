import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/sources/youtube/youtube_audio.dart';
import 'package:wisp/data/sources/youtube/youtube_metadata.dart';
import 'package:wisp/data/sources/youtube/youtube_converters.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp_innertubex_manager/wisp_innertubex_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YouTube InnerTubeX Integration Tests', () {
    test('preferredEngineOrder has InnerTubeX in correct priority', () {
      final provider = YouTubeProvider();
      expect(provider.preferredEngineOrder, [
        YouTubeEngine.YouTubeKit,
        YouTubeEngine.NewPipeExtractor,
        YouTubeEngine.InnerTubeX,
        YouTubeEngine.YT_DLP,
        YouTubeEngine.YoutubeExplode,
      ]);
    });

    test('YouTubeMetadataProvider has InnerTubeX capabilities and auth support', () {
      final meta = YouTubeMetadataProvider();
      expect(meta.name, 'youtube');
      expect(meta.displayName, 'YouTube');
      expect(meta.supportsAuth, true);
      expect(meta.supports(MetadataCapability.search), true);
      expect(meta.supports(MetadataCapability.library), true);
    });

    test('converters accurately map InnerTubeTrack to GenericSong', () {
      const track = InnerTubeTrack(
        videoId: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        author: 'Rick Astley',
        authorId: 'UCuAXFkgsw1L7xaCfnd5JJOw',
        duration: Duration(seconds: 213),
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );

      final song = innerTubeTrackToGenericSong(track);
      expect(song.id, 'dQw4w9WgXcQ');
      expect(song.source, 'youtube');
      expect(song.title, 'Never Gonna Give You Up');
      expect(song.artists.first.name, 'Rick Astley');
      expect(song.artists.first.id, 'UCuAXFkgsw1L7xaCfnd5JJOw');
      expect(song.durationSecs, 213);
      expect(song.thumbnailUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    });

    test('converters accurately map InnerTubeAlbum to GenericAlbum', () {
      const album = InnerTubeAlbum(
        browseId: 'MPREb_test',
        title: 'Test Album',
        artist: 'Test Artist',
        year: '2023',
        trackCount: 1,
        tracks: [
          InnerTubeAlbumTrack(
            videoId: 'v1',
            title: 'Song 1',
            artist: 'Test Artist',
            duration: Duration(seconds: 180),
            index: 1,
          ),
        ],
      );

      final generic = innerTubeAlbumToGenericAlbum(album);
      expect(generic.id, 'MPREb_test');
      expect(generic.source, 'youtube');
      expect(generic.title, 'Test Album');
      expect(generic.artists.first.name, 'Test Artist');
      expect(generic.songs?.length, 1);
      expect(generic.songs?.first.id, 'v1');
      expect(generic.durationSecs, 180);
    });

    test('converters accurately map InnerTubeArtist to GenericArtist', () {
      const artist = InnerTubeArtist(
        browseId: 'UCtest',
        name: 'Artist Name',
        topTracks: [
          InnerTubeSearchResult(
            id: 's1',
            title: 'Top Track',
            artist: 'Artist Name',
            type: 'track',
          ),
        ],
      );

      final generic = innerTubeArtistToGenericArtist(artist);
      expect(generic.id, 'UCtest');
      expect(generic.source, 'youtube');
      expect(generic.name, 'Artist Name');
      expect(generic.topSongs.length, 1);
      expect(generic.topSongs.first.id, 's1');
    });

    test('converters accurately map InnerTubePlaylist to GenericPlaylist', () {
      const playlist = InnerTubePlaylist(
        browseId: 'VLtest',
        title: 'My Playlist',
        author: 'User',
        trackCount: 1,
        tracks: [
          InnerTubeSearchResult(
            id: 'p1',
            title: 'Playlist Track',
            artist: 'Artist',
            duration: Duration(seconds: 200),
            type: 'track',
          ),
        ],
      );

      final generic = innerTubePlaylistToGenericPlaylist(playlist);
      expect(generic.id, 'VLtest');
      expect(generic.source, 'youtube');
      expect(generic.title, 'My Playlist');
      expect(generic.author.displayName, 'User');
      expect(generic.total, 1);
      expect(generic.songs?.length, 1);
      expect(generic.songs?.first.id, 'p1');
      expect(generic.durationSecs, 200);
    });

    test('parseCookieString parses both header format and multi-line formats', () {
      const headerCookie = 'SAPISID=test_sapi; SID=test_sid; LOGIN_INFO=test_login';
      final parsedHeader = YouTubeMetadataProvider.parseCookieString(headerCookie);
      expect(parsedHeader['SAPISID'], 'test_sapi');
      expect(parsedHeader['SID'], 'test_sid');
      expect(parsedHeader['LOGIN_INFO'], 'test_login');

      const multilineCookie = '''
SAPISID: test_sapi_2
SID: test_sid_2
LOGIN_INFO: test_login_2
''';
      final parsedMultiline = YouTubeMetadataProvider.parseCookieString(multilineCookie);
      expect(parsedMultiline['SAPISID'], 'test_sapi_2');
      expect(parsedMultiline['SID'], 'test_sid_2');
      expect(parsedMultiline['LOGIN_INFO'], 'test_login_2');
    });
  });
}

