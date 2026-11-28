import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/services/system/listening_habits_service.dart';

GenericSong _makeSong(
  String id, {
  String thumbnailUrl = '',
  int durationSecs = 180,
}) {
  return GenericSong(
    id: id,
    source: 'spotify',
    title: 'Track $id',
    artists: [
      GenericSimpleArtist(
        id: 'artist1',
        source: 'spotify',
        name: 'Artist',
        thumbnailUrl: '',
      ),
    ],
    thumbnailUrl: thumbnailUrl,
    album: null,
    explicit: false,
    durationSecs: durationSecs,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wisp_habits_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('trims loaded history to maxHistoryRecords', () async {
    final total = ListeningHabitsService.maxHistoryRecords + 50;
    final records = List.generate(
      total,
      (i) => TrackListeningRecord(
        trackId: 'track_$i',
        title: 'Title $i',
        artistNames: const ['Artist'],
        artistIds: const ['artist_1'],
        thumbnailUrl: 'https://img.example/$i.jpg',
        durationSecs: 180,
        completedAt: DateTime(2026, 1, 1).add(Duration(seconds: i)),
      ).toJson(),
    );

    final storeFile = File('${tempDir.path}/listening_habits.json');
    await storeFile.writeAsString(jsonEncode(records));

    final service = ListeningHabitsService.forTesting(
      storageDirectory: tempDir,
    );
    await service.initialize();

    expect(service.history.length, ListeningHabitsService.maxHistoryRecords);
    expect(service.history.first.trackId, 'track_50');
    expect(service.history.last.trackId, 'track_${total - 1}');
  });

  test(
    'backfillMissingThumbnails caps per run, deduplicates IDs, and skips previously attempted IDs',
    () async {
      final totalUnique = ListeningHabitsService.maxBackfillPerRun + 10;
      final records = <Map<String, dynamic>>[];
      for (var i = 0; i < totalUnique; i++) {
        // Add each track twice to verify deduplication.
        for (var copy = 0; copy < 2; copy++) {
          records.add(
            TrackListeningRecord(
              trackId: 'spotify:track:t_$i',
              title: 'Song $i',
              artistNames: const ['Artist'],
              artistIds: const ['a1'],
              thumbnailUrl: null,
              durationSecs: 0,
              completedAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
            ).toJson(),
          );
        }
      }

      final storeFile = File('${tempDir.path}/listening_habits.json');
      await storeFile.writeAsString(jsonEncode(records));

      final fetchedIds = <String>[];
      final service = ListeningHabitsService.forTesting(
        storageDirectory: tempDir,
        trackInfoFetcher: (cleanId) async {
          fetchedIds.add(cleanId);
          // Even if metadata returns empty thumbnail/duration, it must not retry forever.
          return _makeSong(cleanId, thumbnailUrl: '', durationSecs: 0);
        },
      );

      await service.initialize();
      await service.backfillMissingThumbnails();

      expect(fetchedIds.length, ListeningHabitsService.maxBackfillPerRun);
      expect(fetchedIds.toSet().length, ListeningHabitsService.maxBackfillPerRun);

      // Next run in the same session only fetches the remaining 10 unattempted IDs.
      fetchedIds.clear();
      await service.backfillMissingThumbnails();
      expect(fetchedIds.length, 10);

      // Re-initializing a fresh instance persists attempted IDs so 0 retries happen on restart.
      final restartedFetchedIds = <String>[];
      final restartedService = ListeningHabitsService.forTesting(
        storageDirectory: tempDir,
        trackInfoFetcher: (cleanId) async {
          restartedFetchedIds.add(cleanId);
          return _makeSong(
            cleanId,
            thumbnailUrl: 'https://img.example/$cleanId.jpg',
            durationSecs: 200,
          );
        },
      );
      await restartedService.initialize();
      await restartedService.backfillMissingThumbnails();
      expect(restartedFetchedIds, isEmpty);
    },
  );
}
