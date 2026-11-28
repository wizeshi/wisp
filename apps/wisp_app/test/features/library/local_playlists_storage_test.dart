import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/data/models/local_playlist.dart';
import 'package:wisp/features/library/state/local_playlists.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wisp_local_playlists_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('migrates legacy SharedPreferences tracklists to JSON files and removes prefs keys', () async {
    final now = DateTime(2026, 6, 15, 12);
    final legacyActive = LocalPlaylist(
      id: 'local_1',
      title: 'My Mix',
      authorName: 'You',
      tracks: const [],
      createdAt: now,
      updatedAt: now,
    );
    final legacyTrashed = LocalPlaylist(
      id: 'local_2',
      title: 'Old Mix',
      authorName: 'You',
      tracks: const [],
      createdAt: now,
      updatedAt: now,
    );

    SharedPreferences.setMockInitialValues({
      'local_playlists': json.encode([legacyActive.toJson()]),
      'local_playlists_trash': json.encode([legacyTrashed.toJson()]),
    });

    final state = LocalPlaylistState(storageDirectory: tempDir);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(state.playlists.map((p) => p.id), ['local_1']);
    expect(state.trashedPlaylists.map((p) => p.id), ['local_2']);

    final playlistsFile = File('${tempDir.path}/local_playlists.json');
    final trashFile = File('${tempDir.path}/local_playlists_trash.json');
    expect(playlistsFile.existsSync(), isTrue);
    expect(trashFile.existsSync(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('local_playlists'), isFalse);
    expect(prefs.containsKey('local_playlists_trash'), isFalse);

    // Clear SharedPreferences and verify fresh instance loads from the JSON files
    SharedPreferences.setMockInitialValues({});
    final reloaded = LocalPlaylistState(storageDirectory: tempDir);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(reloaded.playlists.map((p) => p.id), ['local_1']);
    expect(reloaded.trashedPlaylists.map((p) => p.id), ['local_2']);
  });
}
