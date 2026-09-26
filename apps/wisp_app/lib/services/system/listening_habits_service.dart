// Copyright © 2026 wizeshi

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:wisp/data/models/metadata_models.dart';
import 'package:wisp/data/sources/spotify/spotify_internal.dart';
import 'package:wisp/core/utils/json.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/services/notifications/desktop_notification_center.dart';

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
  final int durationSecs;
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
    this.durationSecs = 0,
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
        'durationSecs': durationSecs,
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
      durationSecs: json['durationSecs'] as int? ??
          json['duration_secs'] as int? ??
          0,
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
  final List<_TasteIngestionBatch> _ingestionQueue = [];
  bool _isProcessingQueue = false;
  static int _nextNotificationId = 70000;
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

  Set<String> get allUniqueArtists {
    final set = <String>{};
    for (final record in _history) {
      for (final artist in record.artistNames) {
        final trimmed = artist.trim();
        if (trimmed.isNotEmpty) {
          set.add(trimmed);
        }
      }
    }
    return set;
  }

  Set<String> getGenresForArtist(String artistName) {
    final set = <String>{};
    final artistLower = artistName.trim().toLowerCase();
    for (final record in _history) {
      final matches = record.artistNames.any(
        (a) => a.trim().toLowerCase() == artistLower,
      );
      if (matches) {
        for (final genre in record.genres) {
          final trimmed = genre.trim().toLowerCase();
          if (trimmed.isNotEmpty) {
            set.add(trimmed);
          }
        }
      }
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
  /// - [artistName]: optional artist name filter.
  List<GenericSong> getTracksMatchingTag({
    List<String> keywords = const [],
    List<String> requiredLanguages = const [],
    int? minYear,
    int? maxYear,
    String? artistName,
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

      // 0. Artist constraint (if specified)
      if (artistName != null && artistName.trim().isNotEmpty) {
        final target = artistName.trim().toLowerCase();
        final matchesArtist = record.artistNames.any(
          (a) => a.trim().toLowerCase() == target,
        );
        if (!matchesArtist) continue;
      }

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
          durationSecs: record.durationSecs,
        ),
      );
    }

    return List.unmodifiable(result);
  }

  void updateRecordThumbnail({
    required String trackId,
    required String thumbnailUrl,
    String? albumThumbnailUrl,
    int? durationSecs,
  }) {
    if (thumbnailUrl.isEmpty && (durationSecs == null || durationSecs <= 0)) {
      return;
    }
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
        final needsThumb =
            thumbnailUrl.isNotEmpty &&
            (r.thumbnailUrl == null || r.thumbnailUrl!.isEmpty);
        final needsDuration =
            r.durationSecs == 0 && durationSecs != null && durationSecs > 0;
        if (needsThumb || needsDuration) {
          _history[i] = TrackListeningRecord(
            trackId: r.trackId,
            title: r.title,
            artistNames: r.artistNames,
            artistIds: r.artistIds,
            thumbnailUrl: needsThumb ? thumbnailUrl : r.thumbnailUrl,
            albumName: r.albumName,
            albumId: r.albumId,
            releaseDate: r.releaseDate,
            releaseYear: r.releaseYear,
            genres: r.genres,
            languages: r.languages,
            durationSecs: needsDuration ? durationSecs : r.durationSecs,
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

  /// Automatically backfills missing thumbnails and duration for previously listened tracks in the background.
  Future<void> backfillMissingThumbnails() async {
    final spotify = _spotifyProvider;
    if (spotify == null) return;

    bool changed = false;
    for (int i = 0; i < _history.length; i++) {
      final r = _history[i];
      final needsThumb = r.thumbnailUrl == null || r.thumbnailUrl!.isEmpty;
      final needsDuration = r.durationSecs == 0;
      if (needsThumb || needsDuration) {
        try {
          final cleanId = r.trackId.startsWith('spotify:track:')
              ? r.trackId.split(':').last
              : r.trackId;
          final info = await spotify.getTrackInfo(cleanId);
          final updatedThumb = info.thumbnailUrl.isNotEmpty
              ? info.thumbnailUrl
              : r.thumbnailUrl;
          final updatedDuration =
              info.durationSecs > 0 ? info.durationSecs : r.durationSecs;
          _history[i] = TrackListeningRecord(
            trackId: r.trackId,
            title: r.title,
            artistNames: r.artistNames,
            artistIds: r.artistIds,
            thumbnailUrl: updatedThumb,
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
            durationSecs: updatedDuration,
            completedAt: r.completedAt,
          );
          changed = true;
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
        durationSecs: track.durationSecs,
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

  /// Queues a collection of tracks (from a playlist or album) to be ingested into listening habits.
  ///
  /// Requests for track metadata and genres are rate-limited (~2.8 to 3.3 per second) to prevent
  /// 429 rate limit responses, and a persistent progress item is displayed in the notification center.
  Future<void> enqueueTasteIngestion(
    List<GenericSong> tracks, {
    String? sourceTitle,
  }) async {
    if (tracks.isEmpty) return;
    await initialize();

    final seen = <String>{};
    final uniqueTracks = <GenericSong>[];
    for (final t in tracks) {
      final clean = t.id.startsWith('spotify:track:')
          ? t.id.split(':').last
          : t.id;
      if (clean.isNotEmpty && seen.add(clean)) {
        uniqueTracks.add(t);
      }
    }

    if (uniqueTracks.isEmpty) return;

    final notifId = _nextNotificationId++;
    final title = (sourceTitle != null && sourceTitle.isNotEmpty)
        ? sourceTitle
        : 'playlist';

    DesktopNotificationCenter.instance.showProgress(
      id: notifId,
      title: 'Adding ${uniqueTracks.length} songs to your tastes...',
      body: '0 of ${uniqueTracks.length} processed',
      progress: 0,
      maxProgress: uniqueTracks.length,
    );

    _ingestionQueue.add(
      _TasteIngestionBatch(
        notificationId: notifId,
        sourceTitle: title,
        tracks: uniqueTracks,
      ),
    );

    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_ingestionQueue.isNotEmpty) {
        final batch = _ingestionQueue.removeAt(0);
        await _processBatch(batch);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _processBatch(_TasteIngestionBatch batch) async {
    final total = batch.tracks.length;
    var processed = 0;
    var unsavedChanges = 0;
    final spotify = _spotifyProvider;

    for (final track in batch.tracks) {
      final cleanTrackId = track.id.startsWith('spotify:track:')
          ? track.id.split(':').last
          : track.id;

      // Check if already in history with genres
      final existingIndex = _history.indexWhere((r) {
        final rClean = r.trackId.startsWith('spotify:track:')
            ? r.trackId.split(':').last
            : r.trackId;
        return rClean == cleanTrackId;
      });

      if (existingIndex >= 0 && _history[existingIndex].genres.isNotEmpty) {
        processed++;
        DesktopNotificationCenter.instance.showProgress(
          id: batch.notificationId,
          title: 'Adding $total songs to your tastes...',
          body: '$processed of $total processed • ${_history[existingIndex].title}',
          progress: processed,
          maxProgress: total,
        );
        continue;
      }

      GenericSong? info;
      List<String> genres = const [];

      if (spotify != null) {
        // 1. Fetch full track info
        try {
          info = await spotify.getTrackInfo(cleanTrackId);
        } catch (e) {
          logger.w('[ListeningHabits] Ingestion getTrackInfo failed for $cleanTrackId: $e');
        }

        // 2. Fetch track genres
        try {
          genres = await spotify.getTrackGenres(cleanTrackId);
        } catch (e) {
          logger.w('[ListeningHabits] Ingestion getTrackGenres failed for $cleanTrackId: $e');
        }
      }

      final resolvedTitle = (info != null && info.title.isNotEmpty) ? info.title : track.title;
      final resolvedArtists = (info != null && info.artists.isNotEmpty) ? info.artists : track.artists;
      final resolvedThumbnail = (info != null && info.thumbnailUrl.isNotEmpty)
          ? info.thumbnailUrl
          : track.thumbnailUrl;
      final resolvedAlbum = info?.album ?? track.album;
      final resolvedLanguages = (info?.languages != null && info!.languages!.isNotEmpty)
          ? info.languages!
          : (track.languages ?? const []);
      final releaseDate = resolvedAlbum?.releaseDate;
      final releaseYear = (releaseDate != null && releaseDate.year > 0)
          ? releaseDate.year
          : null;

      final record = TrackListeningRecord(
        trackId: track.id,
        title: resolvedTitle,
        artistNames: resolvedArtists.map((a) => a.name).toList(),
        artistIds: resolvedArtists.map((a) => a.id).toList(),
        thumbnailUrl: resolvedThumbnail,
        albumName: resolvedAlbum?.title,
        albumId: resolvedAlbum?.id,
        releaseDate: releaseDate,
        releaseYear: releaseYear,
        genres: genres.isNotEmpty
            ? genres
            : (existingIndex >= 0 ? _history[existingIndex].genres : const []),
        languages: resolvedLanguages,
        completedAt: DateTime.now(),
      );

      if (existingIndex >= 0) {
        _history[existingIndex] = record;
      } else {
        _history.add(record);
      }
      unsavedChanges++;
      processed++;

      // Periodically persist every 5 tracks
      if (unsavedChanges >= 5) {
        await _saveHistory();
        notifyListeners();
        unsavedChanges = 0;
      }

      DesktopNotificationCenter.instance.showProgress(
        id: batch.notificationId,
        title: 'Adding $total songs to your tastes...',
        body: '$processed of $total processed • $resolvedTitle',
        progress: processed,
        maxProgress: total,
      );

      // Rate limit delay: ~350ms (~2.8 requests/sec) to avoid 429
      await Future.delayed(const Duration(milliseconds: 350));
    }

    if (unsavedChanges > 0) {
      await _saveHistory();
      notifyListeners();
    }

    DesktopNotificationCenter.instance.showComplete(
      id: batch.notificationId,
      title: 'Added $total songs to your tastes',
      body: 'Finished updating your listening habits from ${batch.sourceTitle}',
    );
  }
}

class _TasteIngestionBatch {
  final int notificationId;
  final String sourceTitle;
  final List<GenericSong> tracks;

  _TasteIngestionBatch({
    required this.notificationId,
    required this.sourceTitle,
    required this.tracks,
  });
}

