// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/data/models/library_folder.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/features/library/state/library_folders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LibraryFolderState and folderAssignments tests', () {
    test('syncRemoteAssignments maps remote playlists to their respective folders', () async {
      final folderState = LibraryFolderState();
      await folderState.importRemoteFolders([
        PlaylistFolder(
          id: 'spotify:user:test:folder:fdf9854d31e84f14',
          title: 'Moods',
          createdAt: DateTime.now(),
        ),
      ]);

      final playlist1 = GenericPlaylist(
        id: 'pl_1',
        title: 'Study',
        source: 'spotify',
        thumbnailUrl: '',
        durationSecs: 100,
        author: GenericSimpleUser(id: 'author_1', source: 'spotify', displayName: 'Tester'),
      );
      final playlist2 = GenericPlaylist(
        id: 'pl_2',
        title: 'Chill',
        source: 'spotify',
        thumbnailUrl: '',
        durationSecs: 200,
        author: GenericSimpleUser(id: 'author_1', source: 'spotify', displayName: 'Tester'),
      );

      final assignments = {
        'pl_1': 'spotify:user:test:folder:fdf9854d31e84f14',
      };
      final remotePlaylistIds = {'pl_1', 'pl_2'};

      await folderState.syncRemoteAssignments(
        remoteAssignments: assignments,
        remotePlaylistIds: remotePlaylistIds,
      );

      expect(
        folderState.folderIdForPlaylist('pl_1'),
        equals('spotify:user:test:folder:fdf9854d31e84f14'),
      );
      expect(folderState.folderIdForPlaylist('pl_2'), isNull);

      final groups = folderState.buildPlaylistGroups([playlist1, playlist2]);
      expect(groups.folders.length, equals(1));
      expect(groups.folders.first.playlists.length, equals(1));
      expect(groups.folders.first.playlists.first.id, equals('pl_1'));
      expect(groups.unassigned.length, equals(1));
      expect(groups.unassigned.first.id, equals('pl_2'));
    });

    test('GenericLibrary.fromJson correctly decodes folderAssignments', () {
      final json = {
        'saved_albums': [],
        'saved_playlists': [
          {
            'id': 'pl_1',
            'title': 'Test Playlist',
            'source': 'spotify',
            'thumbnail_url': '',
            'duration_secs': 60,
            'is_pinned': true,
            'author': {'id': 'a', 'source': 'spotify', 'display_name': 'Tester'},
          }
        ],
        'saved_artists': [],
        'folderAssignments': {
          'pl_1': 'spotify:user:test:folder:123',
        },
      };

      final lib = GenericLibrary.fromJson(json);
      expect(lib.folderAssignments, isNotNull);
      expect(lib.folderAssignments!['pl_1'], equals('spotify:user:test:folder:123'));
      expect(lib.saved_playlists.first.isPinned, isTrue);
    });

    test('Pinned playlists and folders stay at the top in sorting', () async {
      final folderState = LibraryFolderState();
      final folder1 = PlaylistFolder(
        id: 'f_1',
        title: 'Z Folder',
        isPinned: false,
        createdAt: DateTime.now(),
      );
      final folder2 = PlaylistFolder(
        id: 'f_2',
        title: 'A Folder (Pinned)',
        isPinned: true,
        createdAt: DateTime.now(),
      );
      await folderState.importRemoteFolders([folder1, folder2]);

      final sortedFolders = folderState.sortFolders({});
      expect(sortedFolders.first.id, equals('f_2'));
      expect(sortedFolders.first.isPinned, isTrue);
      expect(sortedFolders.last.id, equals('f_1'));

      final p1 = GenericPlaylist(
        id: 'p_1',
        title: 'A Unpinned Playlist',
        source: 'spotify',
        thumbnailUrl: '',
        durationSecs: 100,
        isPinned: false,
        author: GenericSimpleUser(id: 'u', source: 'spotify', displayName: 'U'),
      );
      final p2 = GenericPlaylist(
        id: 'p_2',
        title: 'Z Pinned Playlist',
        source: 'spotify',
        thumbnailUrl: '',
        durationSecs: 100,
        isPinned: true,
        author: GenericSimpleUser(id: 'u', source: 'spotify', displayName: 'U'),
      );

      final sortedPlaylists = folderState.sortPlaylists([p1, p2]);
      expect(sortedPlaylists.first.id, equals('p_2'));
      expect(sortedPlaylists.first.isPinned, isTrue);
      expect(sortedPlaylists.last.id, equals('p_1'));
    });

    test('toggleFolderPin updates local pinned state and persists', () async {
      final folderState = LibraryFolderState();
      final folder = PlaylistFolder(
        id: 'test_folder_1',
        title: 'My Folder',
        isPinned: false,
        createdAt: DateTime.now(),
      );
      await folderState.importRemoteFolders([folder]);
      expect(folderState.folders.first.isPinned, isFalse);

      await folderState.toggleFolderPin('test_folder_1');
      expect(folderState.folders.first.isPinned, isTrue);

      await folderState.toggleFolderPin('test_folder_1', pinned: false);
      expect(folderState.folders.first.isPinned, isFalse);
    });
  });
}
