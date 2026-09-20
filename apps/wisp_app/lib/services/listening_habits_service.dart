// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/metadata_models.dart';
import '../providers/metadata/spotify_internal.dart';
import '../utils/json.dart';
import '../utils/logger.dart';

/// Represents a single recorded track playback completion event.
class TrackListeningRecord {
  final String trackId;
  final String title;
  final List<String> artistNames;
  final List<String> artistIds;
  final String? thumbnailUrl;
  final String? albumName;
  final String? albumId;
  final DateTime? releaseDate;
  final int? releaseYear;
  final List<String> genres;
  final List<String> languages;
  final DateTime completedAt;

  TrackListeningRecord({
    required this.trackId,
    required this.title,
    required this.artistNames,
    required this.artistIds,
    this.thumbnailUrl,
    this.albumName,
    this.albumId,
    this.releaseDate,
    this.releaseYear,
    this.genres = const [],
    this.languages = const [],
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'title': title,
        'artistNames': artistNames,
        'artistIds': artistIds,
        'thumbnailUrl': thumbnailUrl,
        'albumName': albumName,
        'albumId': albumId,
        'releaseDate': releaseDate?.toIso8601String(),
        'releaseYear': releaseYear,
        'genres': genres,
        'languages': languages,
        'completedAt': completedAt.toIso8601String(),
      };

  factory TrackListeningRecord.fromJson(Map<String, dynamic> json) {
    return TrackListeningRecord(
      trackId: json['trackId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artistNames: (json['artistNames'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      artistIds: (json['artistIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      thumbnailUrl: json['thumbnailUrl'] as String?,
      albumName: json['albumName'] as String?,
      albumId: json['albumId'] as String?,
      releaseDate: json['releaseDate'] != null
          ? DateTime.tryParse(json['releaseDate'] as String)
          : null,
      releaseYear: json['releaseYear'] as int?,
      genres: (json['genres'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      languages:
          (json['languages'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Service that persistently tracks listening habits when a user finishes a track.
class ListeningHabitsService extends ChangeNotifier {
  static final ListeningHabitsService instance = ListeningHabitsService._();
  ListeningHabitsService._();

  SpotifyInternalProvider? _spotifyProvider;
  final List<TrackListeningRecord> _history = [];
  bool _initialized = false;
  File? _storeFile;

  List<TrackListeningRecord> get history => List.unmodifiable(_history);

  Set<String> get allUniqueGenres {
    final set = <String>{};
    for (final record in _history) {
      set.addAll(record.genres);
    }
    return set;
  }

  Map<String, int> get genreFrequency {
    final map = <String, int>{};
    for (final record in _history) {
      for (final genre in record.genres) {
        map[genre] = (map[genre] ?? 0) + 1;
      }
    }
    return map;
  }

  /// Minimum number of completed tracks required to unlock the DJ feature.
  static const int minRequiredTracksForDJ = 15;

  /// Returns whether there is enough listening history data to provide DJ recommendations.
  bool get hasEnoughData => _history.length >= minRequiredTracksForDJ;

  /// Returns distinct [GenericSong] objects from history that match criteria.
  ///
  /// Supports:
  /// - [keywords]: genre or tag keywords (e.g. `['rap', 'hip hop']`).
  /// - [requiredLanguages]: ISO language codes or names (e.g. `['pt', 'por']`).
  /// - [minYear] / [maxYear]: decade or release period filtering (e.g. 1980..1989 for 80s).
  List<GenericSong> getTracksMatchingTag({
    List<String> keywords = const [],
    List<String> requiredLanguages = const [],
    int? minYear,
    int? maxYear,
  }) {
    if (_history.isEmpty) return const [];

    final seen = <String>{};
    final result = <GenericSong>[];

    final lowerKeywords = keywords
        .map((k) => k.toLowerCase().trim())
        .where((k) => k.isNotEmpty)
        .toList();

    for (final record in _history.reversed) {
      if (seen.contains(record.trackId)) continue;

      // 1. Language constraint (if specified)
      if (requiredLanguages.isNotEmpty) {
        final matchesLang = record.languages.any((l) {
          final lLower = l.toLowerCase();
          return requiredLanguages.any(
            (req) => lLower.contains(req) || req.contains(lLower),
          );
        });

        // Also check if title or genre contains explicit Portuguese marker like 'tuga'
        final matchesTextMarker = requiredLanguages.any((req) {
          if (req == 'pt' || req == 'por') {
            return record.title.toLowerCase().contains('tuga') ||
                record.genres.any((g) => g.toLowerCase().contains('tuga'));
          }
          return false;
        });

        if (!matchesLang && !matchesTextMarker) continue;
      }

      // 2. Year constraint (if specified)
      if (minYear != null && record.releaseYear != null && record.releaseYear! < minYear) {
        continue;
      }
      if (maxYear != null && record.releaseYear != null && record.releaseYear! > maxYear) {
        continue;
      }

      // 3. Keyword / genre constraint
      bool matchesKeywords = false;
      if (lowerKeywords.isEmpty) {
        matchesKeywords = true;
      } else {
        matchesKeywords = record.genres.any((g) {
          final gLower = g.toLowerCase();
          return lowerKeywords.any(
            (kw) => gLower.contains(kw) || kw.contains(gLower),
          );
        }) || lowerKeywords.any((kw) => record.title.toLowerCase().contains(kw));
      }

      // For decade or language-only filters where genres may not be tagged yet:
      if (!matchesKeywords && (minYear != null || requiredLanguages.isNotEmpty)) {
        if (record.genres.isEmpty) {
          matchesKeywords = true;
        }
      }

      if (!matchesKeywords) continue;

      seen.add(record.trackId);
      result.add(
        GenericSong(
          id: record.trackId,
          source: SongSource.spotify,
          title: record.title,
          artists: record.artistNames
              .asMap()
              .entries
              .map(
                (e) => GenericSimpleArtist(
                  id: record.artistIds.length > e.key
                      ? record.artistIds[e.key]
                      : '',
                  source: SongSource.spotify,
                  name: e.value,
                  thumbnailUrl: '',
                ),
              )
              .toList(),
          thumbnailUrl: record.thumbnailUrl ?? '',
          album: record.albumName != null
              ? GenericSimpleAlbum(
                  id: record.albumId ?? '',
                  source: SongSource.spotify,
                  title: record.albumName!,
                  thumbnailUrl: record.thumbnailUrl ?? '',
                  artists: const [],
                  label: '',
                  releaseDate: record.releaseDate ?? DateTime(record.releaseYear ?? 2000),
                )
              : null,
          explicit: false,
          durationSecs: 0,
        ),
      );
    }

    return List.unmodifiable(result);
  }

  void updateRecordThumbnail({
    required String trackId,
    required String thumbnailUrl,
    String? albumThumbnailUrl,
  }) {
    if (thumbnailUrl.isEmpty) return;
    bool changed = false;
    final cleanId = trackId.startsWith('spotify:track:')
        ? trackId.split(':').last
        : trackId;

    for (int i = 0; i < _history.length; i++) {
      final r = _history[i];
      final rCleanId = r.trackId.startsWith('spotify:track:')
          ? r.trackId.split(':').last
          : r.trackId;

      if (rCleanId == cleanId) {
        if (r.thumbnailUrl == null || r.thumbnailUrl!.isEmpty) {
          _history[i] = TrackListeningRecord(
            trackId: r.trackId,
            title: r.title,
            artistNames: r.artistNames,
            artistIds: r.artistIds,
            thumbnailUrl: thumbnailUrl,
            albumName: r.albumName,
            albumId: r.albumId,
            releaseDate: r.releaseDate,
            releaseYear: r.releaseYear,
            genres: r.genres,
            languages: r.languages,
            completedAt: r.completedAt,
          );
          changed = true;
        }
      }
    }
    if (changed) {
      _saveHistory();
    }
  }

  /// Automatically backfills missing thumbnails for previously listened tracks in the background.
  Future<void> backfillMissingThumbnails() async {
    final spotify = _spotifyProvider;
    if (spotify == null) return;

    bool changed = false;
    for (int i = 0; i < _history.length; i++) {
      final r = _history[i];
      if (r.thumbnailUrl == null || r.thumbnailUrl!.isEmpty) {
        try {
          final cleanId = r.trackId.startsWith('spotify:track:')
              ? r.trackId.split(':').last
              : r.trackId;
          final info = await spotify.getTrackInfo(cleanId);
          if (info.thumbnailUrl.isNotEmpty) {
            _history[i] = TrackListeningRecord(
              trackId: r.trackId,
              title: r.title,
              artistNames: r.artistNames,
              artistIds: r.artistIds,
              thumbnailUrl: info.thumbnailUrl,
              albumName: r.albumName ?? info.album?.title,
              albumId: r.albumId ?? info.album?.id,
              releaseDate: r.releaseDate ?? info.album?.releaseDate,
              releaseYear: r.releaseYear ??
                  (info.album?.releaseDate != null
                      ? info.album!.releaseDate.year
                      : null),
              genres: r.genres,
              languages: r.languages.isNotEmpty
                  ? r.languages
                  : (info.languages ?? const []),
              completedAt: r.completedAt,
            );
            changed = true;
          }
        } catch (e) {
          // Ignore individual fetch errors during backfill
        }
      }
    }
    if (changed) {
      await _saveHistory();
      notifyListeners();
    }
  }

  bool _backfillStarted = false;

  void bindSpotifyProvider(SpotifyInternalProvider provider) {
    _spotifyProvider = provider;
    if (!_backfillStarted) {
      _backfillStarted = true;
      unawaited(backfillMissingThumbnails());
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _storeFile = File('${dir.path}/listening_habits.json');
      if (await _storeFile!.exists()) {
        final content = await _storeFile!.readAsString();
        if (content.trim().isNotEmpty) {
          final data = await JsonUtils.decode(content);
          if (data is List) {
            _history.clear();
            for (final item in data) {
              if (item is Map<String, dynamic>) {
                _history.add(TrackListeningRecord.fromJson(item));
              }
            }
          }
        }
      }
      _initialized = true;
      logger.i('[ListeningHabits] Initialized with ${_history.length} records');
    } catch (e) {
      logger.w('[ListeningHabits] Failed to load history: $e');
    }
  }

  /// Records a completed track playback, fetching genres, languages, and release info.
  Future<void> recordTrackFinished(GenericSong track) async {
    try {
      await initialize();

      final trackId = track.id.startsWith('spotify:track:')
          ? track.id.split(':').last
          : track.id;

      List<String> genres = const [];
      List<String> languages = track.languages ?? const [];
      DateTime? releaseDate = track.album?.releaseDate;

      final spotify = _spotifyProvider;
      if (spotify != null) {
        // 1. Fetch track genres via extended-metadata protobuf
        try {
          genres = await spotify.getTrackGenres(trackId);
        } catch (e) {
          logger.w('[ListeningHabits] Failed to get genres for $trackId: $e');
        }

        // 2. If language is missing or release date is default/unset, fetch full track info
        if (languages.isEmpty || releaseDate == null || releaseDate.year == 0) {
          try {
            final info = await spotify.getTrackInfo(trackId);
            if (info.languages != null && info.languages!.isNotEmpty) {
              languages = info.languages!;
            }
            if (info.album?.releaseDate != null &&
                info.album!.releaseDate.year != 0) {
              releaseDate = info.album!.releaseDate;
            }
          } catch (e) {
            logger.w(
              '[ListeningHabits] Failed to fetch track info for $trackId: $e',
            );
          }
        }
      }

      final releaseYear = (releaseDate != null && releaseDate.year > 0)
          ? releaseDate.year
          : null;

      final record = TrackListeningRecord(
        trackId: track.id,
        title: track.title,
        artistNames: track.artists.map((a) => a.name).toList(),
        artistIds: track.artists.map((a) => a.id).toList(),
        thumbnailUrl: track.thumbnailUrl,
        albumName: track.album?.title,
        albumId: track.album?.id,
        releaseDate: releaseDate,
        releaseYear: releaseYear,
        genres: genres,
        languages: languages,
        completedAt: DateTime.now(),
      );

      _history.add(record);
      logger.i(
        '[ListeningHabits] Track finished: "${record.title}" | '
        'Genres: ${record.genres} | '
        'Languages: ${record.languages} | '
        'Year: ${record.releaseYear}',
      );

      await _saveHistory();
      notifyListeners();
    } catch (e, st) {
      logger.e(
        '[ListeningHabits] Failed to record track finish: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _saveHistory() async {
    final file = _storeFile;
    if (file == null) return;
    try {
      final jsonStr = jsonEncode(_history.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonStr, flush: true);
    } catch (e) {
      logger.w('[ListeningHabits] Failed to save history: $e');
    }
  }
}

