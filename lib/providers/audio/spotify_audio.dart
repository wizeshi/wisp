library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../models/metadata_models.dart';
import '../../services/credentials.dart';
import '../../services/spotify/spotify_access_point_resolver.dart';
import '../../services/spotify/spotify_audio_key_provider.dart';
import '../../services/spotify/spotify_composite_audio_key_provider.dart';
import '../../services/spotify/spotify_cdn_url.dart';
import '../../services/spotify/spotify_session_audio_key_provider.dart';
import '../../services/spotify/spotify_spclient_audio_key_provider.dart';
import '../../utils/logger.dart';

class SpotifyResolvedStream {
  final String resolvedId;
  final String streamUrl;
  final List<String> fallbackStreamUrls;
  final Map<String, String> requestHeaders;
  final DateTime? expiresAt;
  final bool isPreview;
  final bool mayRequireDecryption;
  final bool hasAudioKey;
  final Uint8List? audioKey;

  const SpotifyResolvedStream({
    required this.resolvedId,
    required this.streamUrl,
    required this.fallbackStreamUrls,
    required this.requestHeaders,
    required this.expiresAt,
    required this.isPreview,
    required this.mayRequireDecryption,
    required this.hasAudioKey,
    required this.audioKey,
  });
}

class _SpotifyTrackFile {
  final String fileIdHex;
  final String format;

  const _SpotifyTrackFile({required this.fileIdHex, required this.format});
}

class _SpotifyTrackManifest {
  final String trackGidHex;
  final List<_SpotifyTrackFile> files;
  final List<String> originalAudioUuids;

  const _SpotifyTrackManifest({
    required this.trackGidHex,
    required this.files,
    required this.originalAudioUuids,
  });
}

class SpotifyAudioProvider {
  final CredentialsService _credentialsService;
  final SpotifyAccessPointResolver _accessPointResolver;
  final SpotifyAudioKeyProvider _audioKeyProvider;

  String? _bearerToken;
  DateTime? _bearerTokenExpiresAt;
  String? _clientToken;

  SpotifyServiceAccessPoints? _accessPoints;

  final Map<String, SpotifyResolvedStream> _streamCache = {};
  final Map<String, Uint8List> _audioKeyCache = {};

  static const String _spotifyWebTokenUrl = 'https://open.spotify.com/api/token';
  static const String _spotifyClientTokenUrl =
      'https://clienttoken.spotify.com/v1/clienttoken';
    static const String _spotifySecretsUrl =
      'https://git.gay/thereallo/totp-secrets/raw/branch/main/secrets/secrets.json';
  static const String _spotifyUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';
    static const String _spotifyAppVersion = '1.2.85.300.gd6e199b8';

  SpotifyAudioProvider({
    CredentialsService? credentialsService,
    SpotifyAccessPointResolver? accessPointResolver,
    SpotifyAudioKeyProvider? audioKeyProvider,
  }) : _credentialsService = credentialsService ?? CredentialsService(),
       _accessPointResolver = accessPointResolver ?? const SpotifyAccessPointResolver(),
       _audioKeyProvider =
         audioKeyProvider ??
             const SpotifyCompositeAudioKeyProvider(
               providers: [
                 SpotifySessionAudioKeyProvider(),
                 SpotifySpclientAudioKeyProvider(),
               ],
             );

  Future<SpotifyResolvedStream?> resolveStream(GenericSong track) async {
    var stage = 'start';
    logger.d(
      '[Spotify/Audio] resolveStream start trackId=${track.id} source=${track.source}',
    );

    if (track.source != SongSource.spotify &&
        track.source != SongSource.spotifyInternal) {
      logger.d('[Spotify/Audio] resolveStream skipped (non-spotify source)');
      return null;
    }

    final cached = _streamCache[track.id];
    if (cached != null) {
      final exp = cached.expiresAt;
      if (exp == null || DateTime.now().isBefore(exp)) {
        logger.d('[Spotify/Audio] resolveStream cache hit for ${track.id}');
        return cached;
      }
      logger.d('[Spotify/Audio] resolveStream cache expired for ${track.id}');
      _streamCache.remove(track.id);
    }

    final normalizedTrackId = _normalizeTrackId(track.id);
    if (normalizedTrackId == null) {
      logger.w('[Spotify/Audio] Invalid Spotify track id: ${track.id}');
      return null;
    }

    try {
      stage = 'ensure_tokens';
      await _ensureTokens();
      logger.d(
        '[Spotify/Audio] Tokens ready bearer=${_bearerToken != null} client=${_clientToken != null}',
      );

      stage = 'resolve_access_points';
      final accessPoints = _accessPoints ?? await _accessPointResolver.resolve();
      _accessPoints = accessPoints;
      logger.d(
        '[Spotify/Audio] AP resolved spclient=${accessPoints.spclient.authority}',
      );

      stage = 'track_id_to_gid';
      final trackGidHex = _trackIdToGidHex(normalizedTrackId);
      if (trackGidHex != null) {
        logger.d('[Spotify/Audio] Track gid resolved gid=$trackGidHex');

        stage = 'fetch_track_manifest';
        final manifest = await _fetchTrackManifest(
          accessPoints.spclientBaseUri,
          trackGidHex,
          normalizedTrackId,
        );
        logger.d(
          '[Spotify/Audio] Manifest resolved files=${manifest.files.length} '
          'originalAudioUuids=${manifest.originalAudioUuids.length}',
        );

        stage = 'select_best_file';
        final selected = _selectBestFile(manifest.files);
        if (selected != null) {
          logger.d(
            '[Spotify/Audio] Selected file format=${selected.format} fileId=${selected.fileIdHex}',
          );
        } else {
          logger.w('[Spotify/Audio] No playable file selected from manifest');
        }

        if (selected != null) {
          stage = 'storage_resolve_once';
          logger.d(
            '[Spotify/Audio] Single storage-resolve attempt fileId=${selected.fileIdHex} '
            'format=${selected.format}',
          );
          final resolved = await _resolveFromStorageId(
            trackGidHex: trackGidHex,
            trackBase62Id: normalizedTrackId,
            spclientBaseUri: accessPoints.spclientBaseUri,
            alternateAudioKeyBaseUris: [accessPoints.accesspointBaseUri],
            fileIdHex: selected.fileIdHex,
            selectedFormat: selected.format,
            trackIdForLog: track.id,
          );
          if (resolved != null) {
            _streamCache[track.id] = resolved;
            return resolved;
          }
        }
      } else {
        logger.w('[Spotify/Audio] Failed to convert track id to gid: $normalizedTrackId');
      }

      stage = 'preview_fallback';
      final preview = await _resolvePreviewUrl(normalizedTrackId);
      if (preview != null && preview.isNotEmpty) {
        final resolved = SpotifyResolvedStream(
          resolvedId: 'preview_$normalizedTrackId',
          streamUrl: preview,
          fallbackStreamUrls: const [],
          requestHeaders: const {'User-Agent': _spotifyUserAgent},
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
          isPreview: true,
          mayRequireDecryption: false,
          hasAudioKey: false,
          audioKey: null,
        );
        _streamCache[track.id] = resolved;
        logger.i('[Spotify/Audio] Falling back to preview URL for ${track.id}');
        return resolved;
      }

      logger.w('[Spotify/Audio] No Spotify stream URL resolved (including preview) for ${track.id}');

      return null;
    } catch (error) {
      logger.w(
        '[Spotify/Audio] Failed to resolve Spotify stream URL at stage=$stage for track=${track.id}',
        error: error,
      );
      return null;
    }
  }

  Future<void> _ensureTokens() async {
    final expiresAt = _bearerTokenExpiresAt;
    if (_bearerToken != null &&
        _clientToken != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 1)))) {
      return;
    }

    final cookie = await _credentialsService.getSpotifyLyricsCookie();
    if (cookie == null || cookie.isEmpty) {
      throw StateError('[Spotify/Audio] Missing Spotify cookie. Please login first.');
    }

    final accessJson = await _requestAccessToken(cookie);
    final accessToken = accessJson['accessToken'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('[Spotify/Audio] Access token response missing accessToken.');
    }

    final clientId = accessJson['clientId'] as String?;
    if (clientId == null || clientId.isEmpty) {
      throw StateError('[Spotify/Audio] Access token response missing clientId.');
    }

    DateTime expiresAtLocal = DateTime.now().add(const Duration(minutes: 45));
    if (accessJson['accessTokenExpirationTimestampMs'] is int) {
      final ts = accessJson['accessTokenExpirationTimestampMs'] as int;
      expiresAtLocal = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (accessJson['expiresIn'] is int) {
      final secs = accessJson['expiresIn'] as int;
      expiresAtLocal = DateTime.now().add(Duration(seconds: secs));
    }

    final clientToken = await _requestClientToken(clientId);
    _bearerToken = accessToken;
    _bearerTokenExpiresAt = expiresAtLocal;
    _clientToken = clientToken;
  }

  Future<Uint8List?> _requestAudioKey(
    String trackGidHex,
    String? trackBase62Id,
    String fileIdHex,
    Uri spclientBaseUri,
    Iterable<Uri>? alternateBaseUris,
  ) async {
    final cacheKey = '${trackGidHex.toLowerCase()}:${fileIdHex.toLowerCase()}';
    final cached = _audioKeyCache[cacheKey];
    if (cached != null && cached.length == 16) {
      return Uint8List.fromList(cached);
    }

    final key = await _audioKeyProvider.requestAudioKey(
      trackGidHex: trackGidHex,
      trackBase62Id: trackBase62Id,
      fileIdHex: fileIdHex,
      spclientBaseUri: spclientBaseUri,
      alternateBaseUris: alternateBaseUris,
      requestHeaders: _buildSpclientHeaders(),
      timeout: const Duration(milliseconds: 1500),
    );

    if (key != null && key.length == 16) {
      _audioKeyCache[cacheKey] = Uint8List.fromList(key);
    }

    return key;
  }

  Future<_SpotifyTrackManifest> _fetchTrackManifest(
    Uri spclientBase,
    String trackGidHex,
    String trackId,
  ) async {
    final protoManifest = await _fetchTrackManifestFromExtendedMetadata(
      spclientBase,
      trackGidHex,
      trackId,
    );
    if (protoManifest != null && protoManifest.files.isNotEmpty) {
      logger.d(
        '[Spotify/Audio] TRACK_V4 resolved files=${protoManifest.files.length} '
        'uuids=${protoManifest.originalAudioUuids.length}',
      );
      for (final file in protoManifest.files) {
        logger.d(
          '[Spotify/Audio] TRACK_V4 file format=${file.format} fileId=${file.fileIdHex}',
        );
      }
      return protoManifest;
    }

    final paths = [
      '/metadata/4/track/$trackGidHex',
      '/metadata/4/track/$trackGidHex?market=from_token',
    ];

    Object? lastError;
    var seenPayload = false;
    final collectedFiles = <_SpotifyTrackFile>[
      if (protoManifest != null) ...protoManifest.files,
    ];
    final collectedUuids = <String>[
      if (protoManifest != null) ...protoManifest.originalAudioUuids,
    ];
    for (final path in paths) {
      final uri = spclientBase.resolve(path);
      try {
        final response = await _sendSpclientGet(uri);
        logger.d('[Spotify/Audio] Manifest request ${uri.path} -> ${response.statusCode}');
        if (response.statusCode != 200) {
          continue;
        }

        final payload = _decodeJsonPayload(response.body);
        if (payload == null) {
          continue;
        }
        seenPayload = true;

        final files = _extractAudioFiles(payload);
        final uuids = _extractOriginalAudioUuids(payload);
        logger.d(
          '[Spotify/Audio] Manifest path ${uri.path} parsed files=${files.length} uuids=${uuids.length}',
        );

        if (files.isNotEmpty) {
          collectedFiles.addAll(files);
        }
        if (uuids.isNotEmpty) {
          collectedUuids.addAll(uuids);
        }

        if (files.isNotEmpty) {
          logger.d('[Spotify/Audio] Manifest path ${uri.path} yielded ${files.length} files');
          return _SpotifyTrackManifest(
            trackGidHex: trackGidHex,
            files: files,
            originalAudioUuids: uuids,
          );
        }
        logger.w('[Spotify/Audio] Manifest path ${uri.path} had empty files list');
      } catch (error) {
        logger.w('[Spotify/Audio] Manifest request failed for ${uri.path}', error: error);
        lastError = error;
      }
    }

    if (seenPayload) {
      return _SpotifyTrackManifest(
        trackGidHex: trackGidHex,
        files: collectedFiles,
        originalAudioUuids: collectedUuids,
      );
    }

    if (lastError != null) {
      throw StateError('[Spotify/Audio] Failed to fetch manifest: $lastError');
    }
    return _SpotifyTrackManifest(
      trackGidHex: trackGidHex,
      files: const [],
      originalAudioUuids: const [],
    );
  }

  Future<_SpotifyTrackManifest?> _fetchTrackManifestFromExtendedMetadata(
    Uri spclientBase,
    String trackGidHex,
    String trackId,
  ) async {
    final uri = spclientBase.resolve('/extended-metadata/v0/extended-metadata');
    final requestBody = _buildTrackV4MetadataRequest(trackId);

    try {
      final response = await _requestWithTlsFallback(
        hostForLog: uri.host,
        request: (client) => client.post(
          uri,
          headers: {
            ..._buildSpclientHeaders(accept: 'application/x-protobuf'),
            'Content-Type': 'application/x-protobuf',
          },
          body: requestBody,
        ),
      );

      logger.d(
        '[Spotify/Audio] TRACK_V4 request ${uri.path} -> ${response.statusCode}',
      );
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }

      final parsed = _parseTrackV4MetadataResponse(
        response.bodyBytes,
        trackGidHex,
      );
      if (parsed.files.isEmpty && parsed.originalAudioUuids.isEmpty) {
        logger.w('[Spotify/Audio] TRACK_V4 response parsed but yielded no files');
      }
      return parsed;
    } catch (error) {
      logger.w('[Spotify/Audio] TRACK_V4 request failed', error: error);
      return null;
    }
  }

  Uint8List _buildTrackV4MetadataRequest(String trackId) {
    final trackUri = 'spotify:track:$trackId';
    final extensionQuery = <int>[];
    extensionQuery.addAll(_encodeProtoVarintField(1, 10));

    final entityRequest = <int>[];
    entityRequest.addAll(_encodeProtoBytesField(1, utf8.encode(trackUri)));
    entityRequest.addAll(_encodeProtoBytesField(2, extensionQuery));

    final batchedRequest = <int>[];
    batchedRequest.addAll(_encodeProtoBytesField(2, entityRequest));
    return Uint8List.fromList(batchedRequest);
  }

  _SpotifyTrackManifest _parseTrackV4MetadataResponse(
    Uint8List responseBytes,
    String trackGidHex,
  ) {
    final files = <_SpotifyTrackFile>[];
    final originalAudioUuids = <String>[];

    _walkProtoFields(responseBytes, (fieldNumber, wireType, value) {
      if (fieldNumber != 2 || wireType != 2 || value is! Uint8List) {
        return;
      }
      _parseEntityExtensionDataArray(value, files, originalAudioUuids);
    });

    final dedupFiles = <String, _SpotifyTrackFile>{};
    for (final file in files) {
      dedupFiles[file.fileIdHex] = file;
    }

    final dedupUuids = <String, bool>{};
    for (final uuid in originalAudioUuids) {
      dedupUuids[uuid.toLowerCase()] = true;
    }

    return _SpotifyTrackManifest(
      trackGidHex: trackGidHex,
      files: dedupFiles.values.toList(growable: false),
      originalAudioUuids: dedupUuids.keys.toList(growable: false),
    );
  }

  void _parseEntityExtensionDataArray(
    Uint8List bytes,
    List<_SpotifyTrackFile> files,
    List<String> originalAudioUuids,
  ) {
    var extensionKind = 0;
    final extensionDataEntries = <Uint8List>[];

    _walkProtoFields(bytes, (fieldNumber, wireType, value) {
      if (fieldNumber == 2 && wireType == 0 && value is int) {
        extensionKind = value;
      } else if (fieldNumber == 3 && wireType == 2 && value is Uint8List) {
        extensionDataEntries.add(value);
      }
    });

    if (extensionKind != 10) {
      return;
    }

    for (final entry in extensionDataEntries) {
      _parseEntityExtensionData(entry, files, originalAudioUuids);
    }
  }

  void _parseEntityExtensionData(
    Uint8List bytes,
    List<_SpotifyTrackFile> files,
    List<String> originalAudioUuids,
  ) {
    _walkProtoFields(bytes, (fieldNumber, wireType, value) {
      if (fieldNumber != 3 || wireType != 2 || value is! Uint8List) {
        return;
      }
      _parseAnyMessage(value, files, originalAudioUuids);
    });
  }

  void _parseAnyMessage(
    Uint8List bytes,
    List<_SpotifyTrackFile> files,
    List<String> originalAudioUuids,
  ) {
    _walkProtoFields(bytes, (fieldNumber, wireType, value) {
      if (fieldNumber != 2 || wireType != 2 || value is! Uint8List) {
        return;
      }
      _parseTrackMessage(value, files, originalAudioUuids);
    });
  }

  void _parseTrackMessage(
    Uint8List bytes,
    List<_SpotifyTrackFile> files,
    List<String> originalAudioUuids,
  ) {
    _walkProtoFields(bytes, (fieldNumber, wireType, value) {
      if (wireType != 2 || value is! Uint8List) {
        return;
      }

      if (fieldNumber == 12) {
        final parsed = _parseTrackAudioFile(value);
        if (parsed != null) {
          files.add(parsed);
        }
      } else if (fieldNumber == 24) {
        final uuidHex = _parseAudioUuid(value);
        if (uuidHex != null) {
          originalAudioUuids.add(uuidHex);
        }
      }
    });
  }

  _SpotifyTrackFile? _parseTrackAudioFile(Uint8List bytes) {
    String? fileIdHex;
    int? formatCode;

    _walkProtoFields(bytes, (fieldNumber, wireType, value) {
      if (fieldNumber == 1 && wireType == 2 && value is Uint8List) {
        if (value.length == 16 || value.length == 20) {
          fileIdHex = _bytesToHex(value);
        }
      } else if (fieldNumber == 2 && wireType == 0 && value is int) {
        formatCode = value;
      }
    });

    if (fileIdHex == null) {
      return null;
    }

    final format =
        _spotifyFormatName(formatCode ?? -1) ??
        (formatCode != null ? 'FORMAT_$formatCode' : 'UNKNOWN_AUDIO');

    return _SpotifyTrackFile(fileIdHex: fileIdHex!, format: format);
  }

  String? _parseAudioUuid(Uint8List bytes) {
    String? uuidHex;
    _walkProtoFields(bytes, (fieldNumber, wireType, value) {
      if (fieldNumber == 1 && wireType == 2 && value is Uint8List) {
        if (value.length == 16 || value.length == 20) {
          uuidHex = _bytesToHex(value);
        }
      }
    });
    return uuidHex;
  }

  List<int> _encodeProtoVarintField(int fieldNumber, int value) {
    final out = <int>[];
    out.addAll(_encodeProtoVarint((fieldNumber << 3) | 0));
    out.addAll(_encodeProtoVarint(value));
    return out;
  }

  List<int> _encodeProtoBytesField(int fieldNumber, List<int> bytes) {
    final out = <int>[];
    out.addAll(_encodeProtoVarint((fieldNumber << 3) | 2));
    out.addAll(_encodeProtoVarint(bytes.length));
    out.addAll(bytes);
    return out;
  }

  List<int> _encodeProtoVarint(int value) {
    final out = <int>[];
    var remaining = value;
    while (remaining >= 0x80) {
      out.add((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    out.add(remaining & 0x7f);
    return out;
  }

  void _walkProtoFields(
    Uint8List bytes,
    void Function(int fieldNumber, int wireType, Object value) onField,
  ) {
    var offset = 0;
    while (offset < bytes.length) {
      final keyRead = _readProtoVarint(bytes, offset);
      if (keyRead == null) {
        return;
      }
      offset = keyRead.nextOffset;

      final fieldNumber = keyRead.value >> 3;
      final wireType = keyRead.value & 0x07;
      switch (wireType) {
        case 0:
          final varintRead = _readProtoVarint(bytes, offset);
          if (varintRead == null) return;
          offset = varintRead.nextOffset;
          onField(fieldNumber, wireType, varintRead.value);
          break;
        case 1:
          if (offset + 8 > bytes.length) return;
          offset += 8;
          break;
        case 2:
          final lenRead = _readProtoVarint(bytes, offset);
          if (lenRead == null) return;
          offset = lenRead.nextOffset;
          final length = lenRead.value;
          if (length < 0 || offset + length > bytes.length) {
            return;
          }
          final chunk = Uint8List.sublistView(bytes, offset, offset + length);
          offset += length;
          onField(fieldNumber, wireType, chunk);
          break;
        case 5:
          if (offset + 4 > bytes.length) return;
          offset += 4;
          break;
        default:
          return;
      }
    }
  }

  _ProtoVarintRead? _readProtoVarint(Uint8List bytes, int startOffset) {
    var shift = 0;
    var result = 0;
    var offset = startOffset;

    while (offset < bytes.length && shift <= 63) {
      final byte = bytes[offset];
      result |= (byte & 0x7f) << shift;
      offset++;
      if ((byte & 0x80) == 0) {
        return _ProtoVarintRead(value: result, nextOffset: offset);
      }
      shift += 7;
    }

    return null;
  }

  Future<List<SpotifyCdnUrl>> _resolveStorageUrls(
    Uri spclientBase,
    String fileIdHex,
  ) async {
    final uri = spclientBase.resolve('/storage-resolve/files/audio/interactive/$fileIdHex');
    final response = await _sendSpclientGet(uri);
    logger.d('[Spotify/Audio] Storage resolve ${uri.path} -> ${response.statusCode}');
    if (response.statusCode != 200) {
      return const [];
    }

    logger.d('[Spotify/Audio] Storage resolve response size=${response.bodyBytes.length}');

    final urls = <SpotifyCdnUrl>[];

    final payload = _decodeJsonPayload(response.body);
    if (payload != null) {
      final dynamic list = payload['cdnurl'] ?? payload['cdnUrl'] ?? payload['urls'];
      if (list is List) {
        for (final item in list) {
          final raw = item is String
              ? item
              : item is Map<String, dynamic>
                  ? (item['url'] as String?)
                  : null;
          final parsed = _tryParseCdnUrl(raw);
          if (parsed != null) {
            urls.add(parsed);
          }
        }
      }
    }

    if (urls.isEmpty) {
      final rawUrls = _extractRawUrlsFromStoragePayload(response.bodyBytes);
      for (final raw in rawUrls) {
        final parsed = _tryParseCdnUrl(raw);
        if (parsed != null) {
          urls.add(parsed);
        }
      }
    }

    logger.d('[Spotify/Audio] Storage resolve parsed urls=${urls.length} path=${uri.path}');
    return urls;
  }

  SpotifyCdnUrl? _tryParseCdnUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.trim().replaceAll('\uFFFD', '');
    final match = RegExp(
      r"https?://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+",
    ).firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final candidate = match.group(0);
    if (candidate == null || candidate.isEmpty) {
      return null;
    }

    final parsed = Uri.tryParse(candidate);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      return null;
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      return null;
    }
    return SpotifyCdnUrl.fromUri(parsed);
  }

  List<String> _extractRawUrlsFromStoragePayload(Uint8List bodyBytes) {
    final decodedUtf8 = utf8.decode(bodyBytes, allowMalformed: true);
    final decodedLatin1 = latin1.decode(bodyBytes, allowInvalid: true);
    final matches = <String, bool>{};

    void collect(String text) {
      final starts = RegExp(r'https?://').allMatches(text).map((m) => m.start).toList();
      if (starts.isEmpty) return;

      for (var i = 0; i < starts.length; i++) {
        final start = starts[i];
        final end = i + 1 < starts.length ? starts[i + 1] : text.length;
        var candidate = text.substring(start, end);
        candidate = candidate.replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), '');
        final stop = RegExp(r'[\s<>"\\\x00-\x1F\x7F]');
        final stopMatch = stop.firstMatch(candidate);
        if (stopMatch != null) {
          candidate = candidate.substring(0, stopMatch.start);
        }
        candidate = candidate.trim();
        if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
          matches[candidate] = true;
        }
      }
    }

    collect(decodedUtf8);
    collect(decodedLatin1);
    return matches.keys.toList(growable: false);
  }

  Future<http.Response> _sendSpclientGet(Uri uri) async {
    return _requestWithTlsFallback(
      hostForLog: uri.host,
      request: (client) => client.get(
        uri,
        headers: _buildSpclientHeaders(),
      ),
    );
  }

  Map<String, String> _buildSpclientHeaders({String accept = 'application/json'}) {
    return {
      'Authorization': 'Bearer ${_bearerToken ?? ''}',
      'client-token': _clientToken ?? '',
      'Accept': accept,
      'User-Agent': _spotifyUserAgent,
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'Accept-Language': 'en',
    };
  }

  Map<String, dynamic>? _decodeJsonPayload(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  List<_SpotifyTrackFile> _extractAudioFiles(Map<String, dynamic> payload) {
    final out = <_SpotifyTrackFile>[];

    void collect(
      dynamic node,
      int depth, {
      String? parentKey,
      bool inAudioFileList = false,
    }) {
      if (depth > 8 || node == null) return;

      if (node is Map<String, dynamic>) {
        final format = _extractFormat(node);
        final hasAudioFormat = _isAudioFormat(format);
        final allowGenericId = inAudioFileList || hasAudioFormat;
        final fileIdHex = _extractFileIdHex(
          node,
          allowGenericId: allowGenericId,
        );

        final shouldUse =
            fileIdHex != null &&
            !_isImageLikeKey(parentKey) &&
            (hasAudioFormat || (inAudioFileList && format == null));
        if (shouldUse) {
          out.add(
            _SpotifyTrackFile(
              fileIdHex: fileIdHex,
              format: format ?? 'UNKNOWN_AUDIO',
            ),
          );
        }

        for (final entry in node.entries) {
          final nextInAudioFileList =
              inAudioFileList || _isAudioFileListKey(entry.key);
          collect(
            entry.value,
            depth + 1,
            parentKey: entry.key,
            inAudioFileList: nextInAudioFileList,
          );
        }
        return;
      }

      if (node is List) {
        for (final item in node) {
          collect(
            item,
            depth + 1,
            parentKey: parentKey,
            inAudioFileList: inAudioFileList,
          );
        }
      }
    }

    collect(payload, 0);

    final dedup = <String, _SpotifyTrackFile>{};
    for (final file in out) {
      dedup[file.fileIdHex] = file;
    }
    return dedup.values.toList();
  }

  String? _extractFileIdHex(Map<String, dynamic> map, {bool allowGenericId = false}) {
    final raw = map['file_id'] ??
        map['fileId'] ??
        (allowGenericId ? map['id'] : null) ??
        (allowGenericId ? map['file'] : null);
    if (raw == null) return null;

    if (raw is String) {
      final value = raw.trim();
      if (_isHex(value)) {
        return value.toLowerCase();
      }
      final maybeB64 = _decodeBase64ToHex(value);
      return maybeB64;
    }

    if (raw is List) {
      final bytes = raw.whereType<int>().toList();
      if (bytes.length == 16 || bytes.length == 20) {
        return _bytesToHex(bytes);
      }
    }

    if (raw is Map<String, dynamic>) {
      final bytes = raw['bytes'];
      if (bytes is List) {
        final list = bytes.whereType<int>().toList();
        if (list.length == 16 || list.length == 20) {
          return _bytesToHex(list);
        }
      }
    }

    return null;
  }

  String? _extractFormat(Map<String, dynamic> map) {
    final value = map['format'] ?? map['codec'] ?? map['type'];
    if (value is String && value.isNotEmpty) {
      final asInt = int.tryParse(value);
      if (asInt != null) {
        return _spotifyFormatName(asInt);
      }
      return value;
    }
    if (value is int) {
      return _spotifyFormatName(value);
    }
    return null;
  }

  String? _spotifyFormatName(int value) {
    switch (value) {
      case 0:
        return 'OGG_VORBIS_96';
      case 1:
        return 'OGG_VORBIS_160';
      case 2:
        return 'OGG_VORBIS_320';
      case 3:
        return 'MP3_256';
      case 4:
        return 'MP3_320';
      case 5:
        return 'MP3_160';
      case 6:
        return 'MP3_96';
      case 7:
        return 'MP3_160_ENC';
      case 8:
        return 'AAC_24';
      case 9:
        return 'AAC_48';
      case 10:
        return 'AAC_160';
      case 11:
        return 'AAC_320';
      case 12:
        return 'MP4_128';
      case 16:
        return 'FLAC_FLAC';
      case 18:
        return 'XHE_AAC_24';
      case 19:
        return 'XHE_AAC_16';
      case 20:
        return 'XHE_AAC_12';
      case 22:
        return 'FLAC_FLAC_24BIT';
      default:
        return null;
    }
  }

  bool _isAudioFormat(String? format) {
    if (format == null || format.isEmpty) return false;
    final upper = format.toUpperCase();
    if (upper.contains('IMAGE') ||
        upper.contains('COVER') ||
        upper.contains('JPEG') ||
        upper.contains('JPG') ||
        upper.contains('PNG') ||
        upper.contains('WEBP') ||
        upper.contains('GIF') ||
        upper.contains('VIDEO')) {
      return false;
    }

    return upper.contains('OGG') ||
        upper.contains('VORBIS') ||
        upper.contains('MP3') ||
        upper.contains('AAC') ||
        upper.contains('MP4') ||
        upper.contains('FLAC') ||
        upper.contains('XHE');
  }

  bool _isAudioFileListKey(String key) {
    final lower = key.toLowerCase();
    return lower == 'file' ||
        lower == 'files' ||
        lower == 'audio' ||
        lower == 'audios' ||
        lower == 'audiofile' ||
        lower == 'audiofiles' ||
        lower == 'audio_file' ||
        lower == 'audio_files' ||
        lower == 'preview' ||
        lower == 'previews';
  }

  bool _isImageLikeKey(String? key) {
    if (key == null || key.isEmpty) return false;
    final lower = key.toLowerCase();
    return lower.contains('image') ||
        lower.contains('cover') ||
        lower.contains('art') ||
        lower.contains('picture') ||
        lower.contains('thumbnail') ||
        lower.contains('avatar');
  }

  List<String> _extractOriginalAudioUuids(Map<String, dynamic> payload) {
    final out = <String>[];

    void collect(dynamic node) {
      if (node == null) return;

      if (node is Map<String, dynamic>) {
        final originalAudio = node['original_audio'];
        if (originalAudio is Map<String, dynamic>) {
          final uuid = originalAudio['uuid'];
          if (uuid is String && uuid.isNotEmpty) {
            out.add(uuid.toLowerCase());
          }
        }

        final directUuid = node['uuid'];
        final format = node['format'];
        if (directUuid is String &&
            directUuid.isNotEmpty &&
            format is String &&
            format.toUpperCase().contains('AUDIO')) {
          out.add(directUuid.toLowerCase());
        }

        for (final value in node.values) {
          collect(value);
        }
        return;
      }

      if (node is List) {
        for (final item in node) {
          collect(item);
        }
      }
    }

    collect(payload);
    final dedup = <String, bool>{};
    for (final uuid in out) {
      dedup[uuid] = true;
    }
    return dedup.keys.toList(growable: false);
  }

  _SpotifyTrackFile? _selectBestFile(List<_SpotifyTrackFile> files) {
    if (files.isEmpty) return null;

    const priorities = [
      'OGG_VORBIS_320',
      'AAC_320',
      'MP4_256',
      'OGG_VORBIS_160',
      'AAC_160',
      'MP4_128',
      'OGG_VORBIS_96',
      'MP3_96',
    ];

    int score(_SpotifyTrackFile file) {
      final upper = file.format.toUpperCase();
      for (var index = 0; index < priorities.length; index++) {
        if (upper.contains(priorities[index])) {
          return priorities.length - index;
        }
      }
      if (upper.contains('320')) return 5;
      if (upper.contains('256')) return 4;
      if (upper.contains('160')) return 3;
      if (upper.contains('128')) return 2;
      if (upper.contains('96')) return 1;
      return 0;
    }

    files.sort((a, b) => score(b).compareTo(score(a)));
    return files.first;
  }

  SpotifyCdnUrl? _pickBestCdnUrl(List<SpotifyCdnUrl> urls) {
    if (urls.isEmpty) return null;
    final alive = urls.where((url) => !url.isExpired).toList();
    if (alive.isNotEmpty) {
      alive.sort((a, b) {
        final aExp = a.expiresAt;
        final bExp = b.expiresAt;
        if (aExp == null && bExp == null) return 0;
        if (aExp == null) return 1;
        if (bExp == null) return -1;
        return bExp.compareTo(aExp);
      });
      return alive.first;
    }
    return urls.first;
  }

  Future<SpotifyResolvedStream?> _resolveFromStorageId({
    required String trackGidHex,
    String? trackBase62Id,
    required Uri spclientBaseUri,
    Iterable<Uri>? alternateAudioKeyBaseUris,
    required String fileIdHex,
    required String selectedFormat,
    required String trackIdForLog,
  }) async {
    final cdnUrls = await _resolveStorageUrls(
      spclientBaseUri,
      fileIdHex,
    );
    logger.d('[Spotify/Audio] Single resolve fileId=$fileIdHex storage urls=${cdnUrls.length}');
    if (cdnUrls.isEmpty) {
      return null;
    }

    final picked = _pickBestCdnUrl(cdnUrls);
    if (picked == null) {
      logger.w('[Spotify/Audio] Single resolve had no pickable CDN URL for fileId=$fileIdHex');
      return null;
    }

    final audioKey = await _requestAudioKey(
      trackGidHex,
      trackBase62Id,
      fileIdHex,
      spclientBaseUri,
      alternateAudioKeyBaseUris,
    );

    final resolved = SpotifyResolvedStream(
      resolvedId: fileIdHex,
      streamUrl: picked.uri.toString(),
      fallbackStreamUrls: cdnUrls
          .map((entry) => entry.uri.toString())
          .where((entry) => entry != picked.uri.toString())
          .toList(growable: false),
      requestHeaders: const {
        'User-Agent': _spotifyUserAgent,
      },
      expiresAt: picked.expiresAt,
      isPreview: false,
      mayRequireDecryption: true,
      hasAudioKey: audioKey != null,
      audioKey: audioKey,
    );

    logger.i(
      '[Spotify/Audio] Resolved CDN URL for $trackIdForLog '
      'format=$selectedFormat fileId=$fileIdHex',
    );
    if (audioKey == null) {
      logger.w(
        '[Spotify/Audio] No audio key for $trackIdForLog and fileId=$fileIdHex; '
        'stream may fail decode if encrypted.',
      );
    }

    logger.d("Stream URLs for $trackIdForLog fileId=$fileIdHex: ${[picked.uri.toString(), ...resolved.fallbackStreamUrls].join(', ')}");
    return resolved;
  }

  Future<Map<String, dynamic>> _requestAccessToken(String cookie) async {
    final normalizedCookie = _normalizeCookieForRequest(cookie);

    Future<Map<String, dynamic>> fetchWithTotp(_TotpPayload totpPayload) async {
    final url = Uri.parse(_spotifyWebTokenUrl).replace(
      queryParameters: {
        'reason': 'init',
        'productType': 'web-player',
        'totp': totpPayload.otp,
        'totpServer': totpPayload.otp,
        'totpVer': totpPayload.version.toString(),
      },
    );

    final response = await _requestWithTlsFallback(
      hostForLog: url.host,
      request: (client) => client.get(
        url,
        headers: {
          'Cookie': normalizedCookie,
          'User-Agent': _spotifyUserAgent,
          'Accept': 'application/json',
          'Origin': 'https://open.spotify.com',
          'Referer': 'https://open.spotify.com/',
        },
      ),
    );
    if (response.statusCode != 200) {
      throw StateError(
        '[Spotify/Audio] Access token request failed: ${response.statusCode}',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw StateError('[Spotify/Audio] Invalid token response payload');
    }
    return body;
    }

    final firstTotp = await _generateTotp();
    try {
      return await fetchWithTotp(firstTotp);
    } catch (error) {
      final text = error.toString();
      if (!text.contains('400')) rethrow;
    }

    final retryTotp = await _generateTotp();
    return fetchWithTotp(retryTotp);
  }

  Future<_TotpPayload> _generateTotp() async {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

    final response = await _requestSecretsWithTlsFallback(
      request: (client) => client.get(Uri.parse(_spotifySecretsUrl)),
    );
    if (response.statusCode != 200) {
      throw StateError('[Spotify/Audio] Failed to fetch TOTP secrets');
    }

    final secrets = jsonDecode(response.body) as List<dynamic>;
    if (secrets.isEmpty) {
      throw StateError('[Spotify/Audio] No TOTP secrets available');
    }

    final latest = secrets.last as Map<String, dynamic>;
    final version = latest['version'] as int? ?? 0;
    final secretValue = latest['secret'] as String? ?? '';
    if (secretValue.isEmpty) {
      throw StateError('[Spotify/Audio] Invalid TOTP secret payload');
    }

    final secretArray = secretValue.codeUnits;
    final secretCipherBytes = <int>[];
    for (var i = 0; i < secretArray.length; i++) {
      secretCipherBytes.add(secretArray[i] ^ ((i % 33) + 9));
    }

    final cipherString = secretCipherBytes.join('');
    final cipherBytes = utf8.encode(cipherString);
    final hexBuffer = StringBuffer();
    for (final value in cipherBytes) {
      hexBuffer.write(value.toRadixString(16).padLeft(2, '0'));
    }

    final secretBytes = _hexToBytes(hexBuffer.toString());
    final base32Secret = _base32FromBytes(secretBytes, alphabet);
    final otp = _generateTotpCode(base32Secret);

    return _TotpPayload(otp: otp, version: version);
  }

  Future<String> _requestClientToken(String clientId) async {
    final payload = {
      'client_data': {
        'client_id': clientId,
        'client_version': _spotifyAppVersion,
        'js_sdk_data': {
          'device_brand': 'unknown',
          'device_model': 'unknown',
          'device_type': 'computer',
          'os': 'windows',
          'os_version': 'NT 10.0',
          'device_id': _randomHex(32),
        },
      },
    };

    final response = await _requestWithTlsFallback(
      hostForLog: Uri.parse(_spotifyClientTokenUrl).host,
      request: (client) => client.post(
        Uri.parse(_spotifyClientTokenUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      ),
    );
    if (response.statusCode != 200) {
      throw StateError(
        '[Spotify/Audio] Client token request failed: ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('[Spotify/Audio] Invalid client token response payload');
    }

    final responseType = decoded['response_type'] as String?;
    if (responseType != 'RESPONSE_GRANTED_TOKEN_RESPONSE') {
      throw StateError(
        '[Spotify/Audio] Unsupported client token challenge: $responseType',
      );
    }

    final granted = decoded['granted_token'] as Map<String, dynamic>?;
    final token = granted?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('[Spotify/Audio] Missing granted client token.');
    }
    return token;
  }

  Future<String?> _resolvePreviewUrl(String trackId) async {
    final bearer = _bearerToken;
    if (bearer == null || bearer.isEmpty) {
      throw StateError('[Spotify/Audio] Missing access token.');
    }

    final response = await _requestWithTlsFallback(
      hostForLog: 'api.spotify.com',
      request: (client) => client.get(
        Uri.parse('https://api.spotify.com/v1/tracks/$trackId'),
        headers: {
          'Authorization': 'Bearer $bearer',
          'Accept': 'application/json',
          'User-Agent': _spotifyUserAgent,
        },
      ),
    );
    if (response.statusCode != 200) {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final previewUrl = decoded['preview_url'];
    if (previewUrl is String && previewUrl.isNotEmpty) {
      return previewUrl;
    }
    return null;
  }

  String? _normalizeTrackId(String raw) {
    if (raw.isEmpty) return null;
    if (raw.startsWith('spotify:track:')) {
      final id = raw.substring('spotify:track:'.length);
      return id.isEmpty ? null : id;
    }
    if (raw.contains(':')) {
      final pieces = raw.split(':');
      if (pieces.length >= 3 && pieces[1] == 'track') {
        return pieces.last;
      }
      return null;
    }
    if (raw.length < 16) return null;
    return raw;
  }

  String? _trackIdToGidHex(String trackId) {
    if (trackId.length == 32 && _isHex(trackId)) {
      return trackId.toLowerCase();
    }

    const alphabet =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (trackId.length != 22) {
      return null;
    }

    BigInt value = BigInt.zero;
    for (final rune in trackId.runes) {
      final char = String.fromCharCode(rune);
      final index = alphabet.indexOf(char);
      if (index < 0) return null;
      value = value * BigInt.from(62) + BigInt.from(index);
    }

    final hex = value.toRadixString(16).padLeft(32, '0');
    return hex.length == 32 ? hex : null;
  }

  bool _isHex(String value) {
    return RegExp(r'^[0-9a-fA-F]{32,40}$').hasMatch(value);
  }

  String? _decodeBase64ToHex(String value) {
    try {
      final normalized = value.padRight(((value.length + 3) ~/ 4) * 4, '=');
      final bytes = base64Decode(normalized);
      if (bytes.length != 16 && bytes.length != 20) {
        return null;
      }
      return _bytesToHex(bytes);
    } catch (_) {
      return null;
    }
  }

  String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString().toLowerCase();
  }

  String _randomHex(int length) {
    const alphabet = '0123456789abcdef';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < length; index++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  String _normalizeCookieForRequest(String cookie) {
    final trimmed = cookie.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.contains('=') || trimmed.contains(';')) {
      return trimmed;
    }
    return 'sp_dc=$trimmed';
  }

  Uint8List _hexToBytes(String hex) {
    final sanitized = hex.replaceAll(' ', '');
    final out = Uint8List(sanitized.length ~/ 2);
    for (var i = 0; i < sanitized.length; i += 2) {
      out[i ~/ 2] = int.parse(sanitized.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  String _base32FromBytes(Uint8List bytes, String alphabet) {
    var t = 0;
    var n = 0;
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      n = (n << 8) | bytes[i];
      t += 8;
      while (t >= 5) {
        buffer.write(alphabet[(n >> (t - 5)) & 31]);
        t -= 5;
      }
    }
    if (t > 0) {
      buffer.write(alphabet[(n << (5 - t)) & 31]);
    }
    return buffer.toString();
  }

  Uint8List _decodeBase32(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final normalized = input.replaceAll('=', '').toUpperCase();
    var buffer = 0;
    var bitsLeft = 0;
    final bytes = <int>[];

    for (final char in normalized.codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(char));
      if (index < 0) continue;
      buffer = (buffer << 5) | index;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        bytes.add((buffer >> bitsLeft) & 0xff);
      }
    }

    return Uint8List.fromList(bytes);
  }

  String _generateTotpCode(String base32Secret, {int digits = 6, int interval = 30}) {
    final secretBytes = _decodeBase32(base32Secret);
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final counter = timestamp ~/ interval;
    final counterBytes = ByteData(8)..setInt64(0, counter);

    final hmac = Hmac(sha1, secretBytes);
    final digest = hmac.convert(counterBytes.buffer.asUint8List()).bytes;
    final offset = digest.last & 0x0f;
    final code =
        ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);
    final mod = pow(10, digits).toInt();
    final otp = code % mod;
    return otp.toString().padLeft(digits, '0');
  }

  Future<http.Response> _requestWithTlsFallback({
    required String hostForLog,
    required Future<http.Response> Function(http.Client client) request,
  }) async {
    try {
      return await _requestWithClient(request, forceInsecure: false);
    } catch (error) {
      if (!_isCertificateHandshakeError(error)) {
        rethrow;
      }

      logger.w(
        '[Spotify/Audio] TLS certificate validation failed for $hostForLog; '
        'retrying with scoped insecure fallback.',
      );
      return _requestWithClient(request, forceInsecure: true);
    }
  }

  Future<http.Response> _requestWithClient(
    Future<http.Response> Function(http.Client client) request, {
    required bool forceInsecure,
  }) async {
    final client = _createSpotifyHttpClient(forceInsecure: forceInsecure);
    try {
      return await request(client);
    } finally {
      client.close();
    }
  }

  Future<http.Response> _requestSecretsWithTlsFallback({
    required Future<http.Response> Function(http.Client client) request,
  }) async {
    try {
      return await _requestWithSecretsClient(request, forceInsecure: false);
    } catch (error) {
      if (!_isCertificateHandshakeError(error)) {
        rethrow;
      }
      logger.w(
        '[Spotify/Audio] TLS certificate validation failed for git.gay; '
        'retrying with scoped insecure fallback.',
      );
      return _requestWithSecretsClient(request, forceInsecure: true);
    }
  }

  Future<http.Response> _requestWithSecretsClient(
    Future<http.Response> Function(http.Client client) request, {
    required bool forceInsecure,
  }) async {
    final client = _createSpotifySecretsHttpClient(forceInsecure: forceInsecure);
    try {
      return await request(client);
    } finally {
      client.close();
    }
  }

  bool _isCertificateHandshakeError(Object error) {
    if (error is HandshakeException) return true;
    final text = error.toString().toUpperCase();
    return text.contains('CERTIFICATE_VERIFY_FAILED') ||
        text.contains('UNABLE TO GET LOCAL ISSUER CERTIFICATE');
  }
}

class _TotpPayload {
  final String otp;
  final int version;

  const _TotpPayload({required this.otp, required this.version});
}

class _ProtoVarintRead {
  final int value;
  final int nextOffset;

  const _ProtoVarintRead({required this.value, required this.nextOffset});
}

http.Client _createSpotifyHttpClient({bool forceInsecure = false}) {
  const allowInsecureSpotifyTls = bool.fromEnvironment(
    'WISP_ALLOW_INSECURE_SPOTIFY_TLS',
    defaultValue: false,
  );

  if (!forceInsecure && !allowInsecureSpotifyTls) {
    return http.Client();
  }

  final ioClient = HttpClient();
  ioClient.badCertificateCallback = (cert, host, port) {
    return host == 'open.spotify.com' ||
        host == 'clienttoken.spotify.com' ||
        host == 'api.spotify.com' ||
        host == 'spclient.wg.spotify.com' ||
        host.endsWith('.spotify.com');
  };
  return IOClient(ioClient);
}

http.Client _createSpotifySecretsHttpClient({bool forceInsecure = false}) {
  const allowInsecureSpotifySecretsTls = bool.fromEnvironment(
    'WISP_ALLOW_INSECURE_SPOTIFY_SECRETS_TLS',
    defaultValue: false,
  );

  if (!forceInsecure && !allowInsecureSpotifySecretsTls) {
    return http.Client();
  }

  final ioClient = HttpClient();
  ioClient.badCertificateCallback = (cert, host, port) {
    return host == 'git.gay';
  };
  return IOClient(ioClient);
}
