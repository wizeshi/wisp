// Copyright © 2026 wizeshi

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/lyrics/lyrics_source.dart';

class MockLyricsSource extends LyricsSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final int priority;
  @override
  final Set<LyricsSyncMode> supportedSyncModes;

  final Future<LyricsResult?> Function(GenericSong song, LyricsSyncMode mode)?
      onGetLyrics;

  MockLyricsSource({
    required this.id,
    required this.name,
    required this.priority,
    required this.supportedSyncModes,
    this.onGetLyrics,
  });

  @override
  Future<LyricsResult?> getLyrics(GenericSong song, LyricsSyncMode mode) async {
    if (onGetLyrics != null) {
      return await onGetLyrics!(song, mode);
    }
    return null;
  }
}

void main() {
  group('Lyrics Priority & Sync Cascade Tests', () {
    final testSong = GenericSong(
      id: 'test_song_1',
      title: 'Never Gonna Give You Up',
      artists: [
        GenericSimpleArtist(
          id: '1',
          name: 'Rick Astley',
          source: 'spotify',
          thumbnailUrl: '',
        ),
      ],
      source: 'spotify',
      thumbnailUrl: '',
      durationSecs: 213,
      explicit: false,
    );

    test('Sources sort strictly by priority for each sync mode', () {
      final appleMusic = MockLyricsSource(
        id: 'apple_music',
        name: 'Apple Music',
        priority: 100,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
      );
      final spotify = MockLyricsSource(
        id: 'spotify',
        name: 'Spotify',
        priority: 60,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
      );
      final betterLyrics = MockLyricsSource(
        id: 'betterlyrics',
        name: 'BetterLyrics',
        priority: 70,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
      );
      final lrclib = MockLyricsSource(
        id: 'lrclib',
        name: 'LRCLIB',
        priority: 50,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
      );

      final allSources = [betterLyrics, lrclib, appleMusic, spotify];

      List<MockLyricsSource> forMode(LyricsSyncMode mode) {
        final list = allSources
            .where((s) => s.supportedSyncModes.contains(mode))
            .toList();
        list.sort((a, b) => b.priority.compareTo(a.priority));
        return list;
      }

      // Word mode: only Apple Music (100) and BetterLyrics (70)
      final wordSources = forMode(LyricsSyncMode.word);
      expect(wordSources.map((s) => s.id).toList(), ['apple_music', 'betterlyrics']);

      // Line mode: Apple Music (100) -> BetterLyrics (70) -> Spotify (60) -> LRCLIB (50)
      final lineSources = forMode(LyricsSyncMode.line);
      expect(lineSources.map((s) => s.id).toList(), [
        'apple_music',
        'betterlyrics',
        'spotify',
        'lrclib',
      ]);

      // Unsynced mode: Apple Music (100) -> BetterLyrics (70) -> Spotify (60) -> LRCLIB (50)
      final unsyncedSources = forMode(LyricsSyncMode.unsynced);
      expect(unsyncedSources.map((s) => s.id).toList(), [
        'apple_music',
        'betterlyrics',
        'spotify',
        'lrclib',
      ]);
    });

    test(
        'Cascade Waterfall: Apple Music returns line-synced, but BetterLyrics returns word-synced -> BetterLyrics Word wins',
        () async {
      final appleMusic = MockLyricsSource(
        id: 'apple_music',
        name: 'Apple Music',
        priority: 100,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
        onGetLyrics: (song, mode) async {
          // Apple Music only has line-synced for this song
          return const LyricsResult(
            provider: LyricsProviderType.custom,
            customProviderName: 'Apple Music',
            syncMode: LyricsSyncMode.line,
            lines: [LyricsLine(content: 'Never gonna give you up', startTimeMs: 1000)],
          );
        },
      );

      final betterLyrics = MockLyricsSource(
        id: 'betterlyrics',
        name: 'BetterLyrics',
        priority: 70,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
        onGetLyrics: (song, mode) async {
          // BetterLyrics has full word-synced!
          return const LyricsResult(
            provider: LyricsProviderType.betterlyrics,
            syncMode: LyricsSyncMode.word,
            lines: [
              LyricsLine(
                content: 'Never gonna give you up',
                startTimeMs: 1000,
                words: [
                  LyricsWord(content: 'Never', startTimeMs: 1000, endTimeMs: 1200),
                  LyricsWord(content: 'gonna', startTimeMs: 1200, endTimeMs: 1400),
                  LyricsWord(content: 'give', startTimeMs: 1400, endTimeMs: 1600),
                  LyricsWord(content: 'you', startTimeMs: 1600, endTimeMs: 1700),
                  LyricsWord(content: 'up', startTimeMs: 1700, endTimeMs: 1900),
                ],
              ),
            ],
          );
        },
      );

      final spotify = MockLyricsSource(
        id: 'spotify',
        name: 'Spotify',
        priority: 60,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.spotify,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'Never gonna give you up', startTimeMs: 1000)],
        ),
      );

      final lrclib = MockLyricsSource(
        id: 'lrclib',
        name: 'LRCLIB',
        priority: 50,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.lrclib,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'Never gonna give you up', startTimeMs: 1000)],
        ),
      );

      final allSources = [appleMusic, betterLyrics, spotify, lrclib];

      // Execute cascade simulation
      final Map<String, LyricsResult> sessionResults = {};
      LyricsResult? winner;

      // Tier 1: Word-synced
      final wordSources = allSources
          .where((s) => s.supportedSyncModes.contains(LyricsSyncMode.word))
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));

      for (final s in wordSources) {
        final res = await s.getLyrics(testSong, LyricsSyncMode.word);
        if (res != null) {
          sessionResults[s.id] = res;
          if (res.isWordSynced) {
            winner = res;
            break;
          }
        }
      }

      expect(winner, isNotNull);
      expect(winner!.provider, LyricsProviderType.betterlyrics);
      expect(winner.isWordSynced, isTrue);
      // Apple Music line-synced was stashed in sessionResults
      expect(sessionResults['apple_music']?.isLineSynced, isTrue);
    });

    test(
        'Cascade Waterfall: No word lyrics anywhere -> Apple Music line-synced wins over Spotify, BetterLyrics, and LRCLIB',
        () async {
      final appleMusic = MockLyricsSource(
        id: 'apple_music',
        name: 'Apple Music',
        priority: 100,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.custom,
          customProviderName: 'Apple Music',
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'Apple line', startTimeMs: 1000)],
        ),
      );

      final spotify = MockLyricsSource(
        id: 'spotify',
        name: 'Spotify',
        priority: 60,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.spotify,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'Spotify line', startTimeMs: 1000)],
        ),
      );

      final betterLyrics = MockLyricsSource(
        id: 'betterlyrics',
        name: 'BetterLyrics',
        priority: 70,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.betterlyrics,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'BetterLyrics line', startTimeMs: 1000)],
        ),
      );

      final lrclib = MockLyricsSource(
        id: 'lrclib',
        name: 'LRCLIB',
        priority: 50,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.lrclib,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'LRCLIB line', startTimeMs: 1000)],
        ),
      );

      final allSources = [appleMusic, spotify, betterLyrics, lrclib];
      final Map<String, LyricsResult> sessionResults = {};
      LyricsResult? winner;

      // Tier 1: Word-synced
      final wordSources = allSources
          .where((s) => s.supportedSyncModes.contains(LyricsSyncMode.word))
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));

      for (final s in wordSources) {
        final res = await s.getLyrics(testSong, LyricsSyncMode.word);
        if (res != null) {
          sessionResults[s.id] = res;
          if (res.isWordSynced) {
            winner = res;
            break;
          }
        }
      }

      expect(winner, isNull); // Neither had word-synced lyrics

      // Tier 2: Line-synced
      final lineSources = allSources
          .where((s) => s.supportedSyncModes.contains(LyricsSyncMode.line))
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));

      for (final s in lineSources) {
        LyricsResult? res = sessionResults[s.id];
        res ??= await s.getLyrics(testSong, LyricsSyncMode.line);
        if (res != null && res.isLineSynced) {
          winner = res;
          break;
        }
      }

      expect(winner, isNotNull);
      expect(winner!.providerLabel, 'Apple Music');
      expect(winner.isLineSynced, isTrue);
    });

    test(
        'Cascade Waterfall: Apple Music fails, BetterLyrics line-synced (priority 70) wins over Spotify (60) and LRCLIB (50)',
        () async {
      final appleMusic = MockLyricsSource(
        id: 'apple_music',
        name: 'Apple Music',
        priority: 100,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
        onGetLyrics: (song, mode) async => null, // fails / not found
      );

      final spotify = MockLyricsSource(
        id: 'spotify',
        name: 'Spotify',
        priority: 60,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.spotify,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'Spotify line', startTimeMs: 1000)],
        ),
      );

      final betterLyrics = MockLyricsSource(
        id: 'betterlyrics',
        name: 'BetterLyrics',
        priority: 70,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.betterlyrics,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'BetterLyrics line', startTimeMs: 1000)],
        ),
      );

      final lrclib = MockLyricsSource(
        id: 'lrclib',
        name: 'LRCLIB',
        priority: 50,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.lrclib,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'LRCLIB line', startTimeMs: 1000)],
        ),
      );

      final allSources = [appleMusic, spotify, betterLyrics, lrclib];
      final Map<String, LyricsResult> sessionResults = {};
      LyricsResult? winner;

      // Tier 1: Word-synced
      final wordSources = allSources
          .where((s) => s.supportedSyncModes.contains(LyricsSyncMode.word))
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));

      for (final s in wordSources) {
        final res = await s.getLyrics(testSong, LyricsSyncMode.word);
        if (res != null) {
          sessionResults[s.id] = res;
          if (res.isWordSynced) {
            winner = res;
            break;
          }
        }
      }

      // Tier 2: Line-synced
      final lineSources = allSources
          .where((s) => s.supportedSyncModes.contains(LyricsSyncMode.line))
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));

      for (final s in lineSources) {
        LyricsResult? res = sessionResults[s.id];
        res ??= await s.getLyrics(testSong, LyricsSyncMode.line);
        if (res != null && res.isLineSynced) {
          winner = res;
          break;
        }
      }

      expect(winner, isNotNull);
      expect(winner!.provider, LyricsProviderType.betterlyrics);
      expect(winner.isLineSynced, isTrue);
    });

    test(
        'Cascade Waterfall: Apple Music and BetterLyrics fail, Spotify line-synced (priority 60) wins over LRCLIB (50)',
        () async {
      final appleMusic = MockLyricsSource(
        id: 'apple_music',
        name: 'Apple Music',
        priority: 100,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
        onGetLyrics: (song, mode) async => null,
      );

      final betterLyrics = MockLyricsSource(
        id: 'betterlyrics',
        name: 'BetterLyrics',
        priority: 70,
        supportedSyncModes: {
          LyricsSyncMode.word,
          LyricsSyncMode.line,
          LyricsSyncMode.unsynced,
        },
        onGetLyrics: (song, mode) async => null, // fails / not found
      );

      final spotify = MockLyricsSource(
        id: 'spotify',
        name: 'Spotify',
        priority: 60,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.spotify,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'Spotify line', startTimeMs: 1000)],
        ),
      );

      final lrclib = MockLyricsSource(
        id: 'lrclib',
        name: 'LRCLIB',
        priority: 50,
        supportedSyncModes: {LyricsSyncMode.line, LyricsSyncMode.unsynced},
        onGetLyrics: (song, mode) async => const LyricsResult(
          provider: LyricsProviderType.lrclib,
          syncMode: LyricsSyncMode.line,
          lines: [LyricsLine(content: 'LRCLIB line', startTimeMs: 1000)],
        ),
      );

      final allSources = [appleMusic, spotify, betterLyrics, lrclib];
      final Map<String, LyricsResult> sessionResults = {};
      LyricsResult? winner;

      // Tier 1: Word-synced
      final wordSources = allSources
          .where((s) => s.supportedSyncModes.contains(LyricsSyncMode.word))
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));

      for (final s in wordSources) {
        final res = await s.getLyrics(testSong, LyricsSyncMode.word);
        if (res != null) {
          sessionResults[s.id] = res;
          if (res.isWordSynced) {
            winner = res;
            break;
          }
        }
      }

      // Tier 2: Line-synced
      final lineSources = allSources
          .where((s) => s.supportedSyncModes.contains(LyricsSyncMode.line))
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));

      for (final s in lineSources) {
        LyricsResult? res = sessionResults[s.id];
        res ??= await s.getLyrics(testSong, LyricsSyncMode.line);
        if (res != null && res.isLineSynced) {
          winner = res;
          break;
        }
      }

      expect(winner, isNotNull);
      expect(winner!.provider, LyricsProviderType.spotify);
      expect(winner.isLineSynced, isTrue);
    });
  });
}
