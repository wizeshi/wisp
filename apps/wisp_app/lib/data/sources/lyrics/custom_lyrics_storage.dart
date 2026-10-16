// Copyright © 2026 wizeshi

library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wisp/core/utils/logger.dart';
import 'package:wisp/data/models/metadata_models.dart';
import 'ttml_parser.dart';

class _CustomLyricsMeta {
  final String trackId;
  final String title;
  final String artist;
  final String titleArtistKey;
  final String ttmlFileName;
  final String jsonFileName;
  final DateTime importedAt;

  const _CustomLyricsMeta({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.titleArtistKey,
    required this.ttmlFileName,
    required this.jsonFileName,
    required this.importedAt,
  });

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'titleArtistKey': titleArtistKey,
        'ttmlFileName': ttmlFileName,
        'jsonFileName': jsonFileName,
        'importedAt': importedAt.toIso8601String(),
      };

  factory _CustomLyricsMeta.fromJson(Map<String, dynamic> json) {
    return _CustomLyricsMeta(
      trackId: json['trackId'] as String,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      titleArtistKey: json['titleArtistKey'] as String? ?? '',
      ttmlFileName: json['ttmlFileName'] as String,
      jsonFileName: json['jsonFileName'] as String,
      importedAt: DateTime.tryParse(json['importedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Service managing persistent locally imported custom lyrics.
class CustomLyricsStorage {
  CustomLyricsStorage._();

  static final CustomLyricsStorage instance = CustomLyricsStorage._();

  Directory? _storageDir;
  bool _initialized = false;
  bool _initializing = false;

  final Map<String, _CustomLyricsMeta> _byTrackId = {};
  final Map<String, _CustomLyricsMeta> _byTitleArtist = {};

  static String normalizeKey(String title, [String? artist]) {
    final cleanTitle =
        title.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final cleanArtist =
        (artist ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    return '$cleanTitle|$cleanArtist';
  }

  static String sanitizeFileName(String id) {
    return id.replaceAll(RegExp(r'[^\w\-_.]'), '_');
  }

  /// Ensures storage directory and index are loaded into memory.
  Future<void> initialize() async {
    if (_initialized) return;
    if (_initializing) {
      while (_initializing) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      return;
    }

    _initializing = true;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory('${supportDir.path}/custom_lyrics');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _storageDir = dir;

      final indexFile = File('${dir.path}/index.json');
      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is List) {
            _byTrackId.clear();
            _byTitleArtist.clear();
            for (final item in decoded) {
              if (item is Map) {
                final meta = _CustomLyricsMeta.fromJson(
                  item.cast<String, dynamic>(),
                );
                _byTrackId[meta.trackId] = meta;
                if (meta.titleArtistKey.isNotEmpty) {
                  _byTitleArtist[meta.titleArtistKey] = meta;
                }
              }
            }
          }
        }
      }
      _initialized = true;
      logger.i(
        '[CustomLyricsStorage] Initialized at ${dir.path} with ${_byTrackId.length} entries',
      );
    } catch (e, stack) {
      logger.e(
        '[CustomLyricsStorage] Failed to initialize: $e',
        error: e,
        stackTrace: stack,
      );
    } finally {
      _initializing = false;
    }
  }

  /// Instant, synchronous check if custom lyrics are available for [song].
  bool hasCustomLyricsSync(GenericSong song) {
    if (_byTrackId.containsKey(song.id)) return true;
    final primaryArtist =
        song.artists.isNotEmpty ? song.artists.first.name : null;
    final key = normalizeKey(song.title, primaryArtist);
    return _byTitleArtist.containsKey(key);
  }

  /// Asynchronous check ensuring storage is initialized.
  Future<bool> hasCustomLyrics(GenericSong song) async {
    await initialize();
    return hasCustomLyricsSync(song);
  }

  /// Saves a custom TTML file locally and links it to [song].
  ///
  /// Throws [FormatException] if the TTML content cannot be parsed.
  Future<LyricsResult> saveCustomLyrics({
    required GenericSong song,
    required String ttmlContent,
  }) async {
    await initialize();
    final dir = _storageDir;
    if (dir == null) {
      throw const FileSystemException('Custom lyrics storage directory unavailable');
    }

    // Parse and validate TTML content first
    final parsed = TtmlParser.parse(ttmlContent);

    final primaryArtist =
        song.artists.isNotEmpty ? song.artists.first.name : '';
    final titleArtistKey = normalizeKey(song.title, primaryArtist);
    final fileBase = sanitizeFileName(song.id.isNotEmpty ? song.id : titleArtistKey);

    final ttmlFileName = '$fileBase.ttml';
    final jsonFileName = '$fileBase.json';

    // 1. Save raw TTML file
    final ttmlFile = File('${dir.path}/$ttmlFileName');
    await ttmlFile.writeAsString(ttmlContent, flush: true);

    // 2. Save pre-parsed WLF JSON
    final jsonFile = File('${dir.path}/$jsonFileName');
    await jsonFile.writeAsString(
      jsonEncode(parsed.toWlfJson()),
      flush: true,
    );

    // 3. Update index
    final meta = _CustomLyricsMeta(
      trackId: song.id,
      title: song.title,
      artist: primaryArtist,
      titleArtistKey: titleArtistKey,
      ttmlFileName: ttmlFileName,
      jsonFileName: jsonFileName,
      importedAt: DateTime.now(),
    );

    _byTrackId[song.id] = meta;
    if (titleArtistKey.isNotEmpty) {
      _byTitleArtist[titleArtistKey] = meta;
    }

    await _saveIndex();
    logger.i(
      '[CustomLyricsStorage] Saved custom lyrics for "${song.title}" (${parsed.lines.length} lines, sync: ${parsed.syncMode.name})',
    );

    return parsed;
  }

  /// Retrieves custom lyrics for [song], matching by ID first with title + artist fallback.
  Future<LyricsResult?> getCustomLyrics(GenericSong song) async {
    await initialize();
    final meta = _findMeta(song);
    if (meta == null) return null;

    final dir = _storageDir;
    if (dir == null) return null;

    try {
      // 1. Try reading the fast WLF JSON
      final jsonFile = File('${dir.path}/${meta.jsonFileName}');
      if (await jsonFile.exists()) {
        final content = await jsonFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          return LyricsResult.fromWlfJson(decoded);
        }
      }

      // 2. Fall back to re-parsing the raw TTML file
      final ttmlFile = File('${dir.path}/${meta.ttmlFileName}');
      if (await ttmlFile.exists()) {
        final ttml = await ttmlFile.readAsString();
        final parsed = TtmlParser.parse(ttml);
        // Resave JSON cache
        await jsonFile.writeAsString(jsonEncode(parsed.toWlfJson()));
        return parsed;
      }
    } catch (e, stack) {
      logger.e(
        '[CustomLyricsStorage] Failed to read custom lyrics for "${song.title}": $e',
        error: e,
        stackTrace: stack,
      );
    }
    return null;
  }

  /// Removes custom lyrics for [song] and deletes local files.
  Future<bool> removeCustomLyrics(GenericSong song) async {
    await initialize();
    final meta = _findMeta(song);
    if (meta == null) return false;

    final dir = _storageDir;
    if (dir != null) {
      try {
        final ttmlFile = File('${dir.path}/${meta.ttmlFileName}');
        if (await ttmlFile.exists()) await ttmlFile.delete();

        final jsonFile = File('${dir.path}/${meta.jsonFileName}');
        if (await jsonFile.exists()) await jsonFile.delete();
      } catch (e) {
        logger.w('[CustomLyricsStorage] Error deleting files for "${song.title}": $e');
      }
    }

    _byTrackId.remove(meta.trackId);
    _byTitleArtist.remove(meta.titleArtistKey);
    await _saveIndex();

    logger.i('[CustomLyricsStorage] Removed custom lyrics for "${song.title}"');
    return true;
  }

  _CustomLyricsMeta? _findMeta(GenericSong song) {
    if (_byTrackId.containsKey(song.id)) {
      return _byTrackId[song.id];
    }
    final primaryArtist =
        song.artists.isNotEmpty ? song.artists.first.name : null;
    final key = normalizeKey(song.title, primaryArtist);
    return _byTitleArtist[key];
  }

  Future<void> _saveIndex() async {
    final dir = _storageDir;
    if (dir == null) return;
    try {
      final indexFile = File('${dir.path}/index.json');
      // Deduplicate entries by ttmlFileName
      final uniqueEntries = <String, _CustomLyricsMeta>{};
      for (final m in _byTrackId.values) {
        uniqueEntries[m.ttmlFileName] = m;
      }
      for (final m in _byTitleArtist.values) {
        uniqueEntries[m.ttmlFileName] = m;
      }

      final payload = uniqueEntries.values.map((m) => m.toJson()).toList();
      await indexFile.writeAsString(jsonEncode(payload), flush: true);
    } catch (e) {
      logger.e('[CustomLyricsStorage] Failed to write index.json: $e', error: e);
    }
  }
}

