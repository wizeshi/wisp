library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../utils/logger.dart';
import 'spotify_range_audio_source.dart';

class SpotifyDecryptStreamingProxy {
  static final SpotifyDecryptStreamingProxy instance =
      SpotifyDecryptStreamingProxy._();

  SpotifyDecryptStreamingProxy._();

  HttpServer? _server;
  int _port = 0;

  final Map<String, _SpotifyDecryptSession> _sessions = {};

  Future<Uri> registerStream({
    required String cacheKey,
    required String streamUrl,
    required Uint8List audioKey,
    List<String>? fallbackStreamUrls,
    Map<String, String>? headers,
  }) async {
    await _ensureServer();

    final baseUri = Uri.tryParse(streamUrl);
    if (baseUri == null) {
      throw StateError('Invalid Spotify stream URL');
    }

    final token = _tokenFor(cacheKey);
    final streamUris = <Uri>[baseUri];
    if (fallbackStreamUrls != null) {
      for (final raw in fallbackStreamUrls) {
        final parsed = Uri.tryParse(raw);
        if (parsed != null && !streamUris.contains(parsed)) {
          streamUris.add(parsed);
        }
      }
    }

    _sessions[token] = _SpotifyDecryptSession(
      cacheKey: cacheKey,
      streamUris: streamUris,
      headers: headers ?? const {},
      audioKey: audioKey,
      createdAt: DateTime.now(),
    );

    _evictOldSessions();

    return Uri.parse('http://127.0.0.1:$_port/spotify/$token');
  }

  Future<void> _ensureServer() async {
    if (_server != null) return;

    final port = 12000 + Random().nextInt(8000);
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _port = _server!.port;

    unawaited(_serveLoop());
    logger.i('[Spotify/Proxy] Decrypt proxy listening on 127.0.0.1:$_port');
  }

  Future<void> _serveLoop() async {
    final server = _server;
    if (server == null) return;

    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      final segments = request.uri.pathSegments;
      if (segments.length != 2 || segments.first != 'spotify') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final token = segments[1];
      final session = _sessions[token];
      if (session == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      await _ensurePayloadOffset(session);

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final requested = _parseRange(rangeHeader, session.logicalLength);

      if (requested != null && requested.$1 < 0) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        if (session.logicalLength != null) {
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */${session.logicalLength}',
          );
        }
        await request.response.close();
        return;
      }

      final logicalStart = requested?.$1 ?? 0;
      final logicalEndExclusive = requested?.$2;

      if (session.logicalLength != null && logicalStart >= session.logicalLength!) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */${session.logicalLength}',
        );
        await request.response.close();
        return;
      }

      final payloadOffset = session.payloadOffset;
      final encryptedStart = payloadOffset + logicalStart;
      final encryptedEndExclusive = logicalEndExclusive == null
          ? null
          : payloadOffset + logicalEndExclusive;

      final alignedStart = (encryptedStart ~/ 16) * 16;
      final alignedPrefix = encryptedStart - alignedStart;

      final fetcher = SpotifyRangeFetcher(
        cdnUrls: session.streamUris,
        headers: session.headers,
      );

      try {
        final fetched = await fetcher.fetchRange(
          start: alignedStart,
          endExclusive: encryptedEndExclusive,
        );

        final encryptedBytes = await _collectStreamBytes(fetched.stream);
        final decrypted = _decryptRange(
          encryptedBytes: encryptedBytes,
          audioKey: session.audioKey,
          encryptedStart: alignedStart,
        );

        if (alignedPrefix >= decrypted.length) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await request.response.close();
          return;
        }

        var sliced = Uint8List.sublistView(decrypted, alignedPrefix);

        if (logicalEndExclusive != null) {
          final maxLen = logicalEndExclusive - logicalStart;
          if (maxLen >= 0 && maxLen < sliced.length) {
            sliced = Uint8List.sublistView(sliced, 0, maxLen);
          }
        }

        final logicalTotal = session.logicalLength ??
            ((fetched.sourceLength != null)
                ? (fetched.sourceLength! - payloadOffset).clamp(0, 1 << 31)
                : null);

        final response = request.response;
        final isRange = requested != null;

        response.headers.contentType = _contentTypeFor(session.detectedContainer);
        response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

        if (isRange) {
          final endInclusive = logicalStart + sliced.length - 1;
          response.statusCode = HttpStatus.partialContent;
          if (logicalTotal != null) {
            response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $logicalStart-$endInclusive/$logicalTotal',
            );
          }
        } else {
          response.statusCode = HttpStatus.ok;
        }

        response.headers.contentLength = sliced.length;
        response.add(sliced);
        await response.close();
      } finally {
        fetcher.close();
      }
    } catch (error) {
      logger.w('[Spotify/Proxy] Request handling failed', error: error);
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _ensurePayloadOffset(_SpotifyDecryptSession session) async {
    if (session.payloadOffsetResolved) return;

    final fetcher = SpotifyRangeFetcher(
      cdnUrls: session.streamUris,
      headers: session.headers,
    );

    try {
      final probe = await fetcher.fetchRange(start: 0, endExclusive: 1024);
      final bytes = await _collectStreamBytes(probe.stream);
      final decrypted = _decryptRange(
        encryptedBytes: bytes,
        audioKey: session.audioKey,
        encryptedStart: 0,
      );

      session.payloadOffset = _detectPayloadOffset(decrypted);
      session.payloadOffsetResolved = true;
      session.detectedContainer = _detectContainer(
        Uint8List.sublistView(decrypted, session.payloadOffset),
      );

      if (probe.sourceLength != null) {
        final logical = probe.sourceLength! - session.payloadOffset;
        session.logicalLength = logical > 0 ? logical : 0;
      }
    } catch (_) {
      session.payloadOffset = 0;
      session.payloadOffsetResolved = true;
    } finally {
      fetcher.close();
    }
  }

  Uint8List _decryptRange({
    required Uint8List encryptedBytes,
    required Uint8List audioKey,
    required int encryptedStart,
  }) {
    final blockIndex = encryptedStart ~/ 16;
    final iv = _counterToIv(blockIndex);

    final cipher = SICStreamCipher(AESEngine())
      ..init(
        false,
        ParametersWithIV<KeyParameter>(
          KeyParameter(audioKey),
          iv,
        ),
      );

    return cipher.process(encryptedBytes);
  }

  Uint8List _counterToIv(int blockIndex) {
    final out = Uint8List(16);
    var value = BigInt.from(blockIndex);
    for (var i = 15; i >= 0 && value > BigInt.zero; i--) {
      out[i] = (value & BigInt.from(0xFF)).toInt();
      value = value >> 8;
    }
    return out;
  }

  int _detectPayloadOffset(Uint8List bytes) {
    if (_matchesAt(bytes, 0, [0x4F, 0x67, 0x67, 0x53])) return 0;
    final maxProbe = bytes.length < 512 ? bytes.length : 512;
    for (var i = 1; i + 4 <= maxProbe; i++) {
      if (_matchesAt(bytes, i, [0x4F, 0x67, 0x67, 0x53]) ||
          _matchesAt(bytes, i, [0x66, 0x4C, 0x61, 0x43]) ||
          _matchesAt(bytes, i, [0x49, 0x44, 0x33])) {
        return i;
      }
    }
    return 0;
  }

  bool _matchesAt(Uint8List bytes, int offset, List<int> signature) {
    if (offset + signature.length > bytes.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  (int, int?)? _parseRange(String? header, int? logicalTotal) {
    if (header == null || header.isEmpty) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;

    final startRaw = match.group(1) ?? '';
    final endRaw = match.group(2) ?? '';

    // suffix-byte-range-spec: bytes=-N
    if (startRaw.isEmpty && endRaw.isNotEmpty) {
      final suffix = int.tryParse(endRaw);
      if (suffix == null || suffix <= 0) return (-1, null);
      if (logicalTotal == null) {
        // Without total length we cannot resolve suffix accurately.
        return (0, null);
      }
      final start = logicalTotal - suffix;
      final clamped = start < 0 ? 0 : start;
      return (clamped, logicalTotal);
    }

    final start = int.tryParse(startRaw);
    if (start == null || start < 0) return (-1, null);

    if (endRaw.isEmpty) {
      return (start, null);
    }

    final endInclusive = int.tryParse(endRaw);
    if (endInclusive == null || endInclusive < start) return (-1, null);
    return (start, endInclusive + 1);
  }

  ContentType _contentTypeFor(String? container) {
    switch (container) {
      case 'ogg':
        return ContentType('audio', 'ogg');
      case 'flac':
        return ContentType('audio', 'flac');
      case 'mp3':
        return ContentType('audio', 'mpeg');
      default:
        return ContentType.binary;
    }
  }

  String? _detectContainer(Uint8List bytes) {
    if (_matchesAt(bytes, 0, [0x4F, 0x67, 0x67, 0x53])) return 'ogg';
    if (_matchesAt(bytes, 0, [0x66, 0x4C, 0x61, 0x43])) return 'flac';
    if (_matchesAt(bytes, 0, [0x49, 0x44, 0x33])) return 'mp3';
    return null;
  }

  String _tokenFor(String cacheKey) {
    final time = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(1 << 32);
    return '${cacheKey}_${time}_$rand'.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  Future<Uint8List> _collectStreamBytes(Stream<List<int>> stream) async {
    final chunks = <int>[];
    await for (final part in stream) {
      chunks.addAll(part);
    }
    return Uint8List.fromList(chunks);
  }

  void _evictOldSessions() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 30));
    final keys = _sessions.entries
        .where((entry) => entry.value.createdAt.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList();
    for (final key in keys) {
      _sessions.remove(key);
    }

    if (_sessions.length > 128) {
      final entries = _sessions.entries.toList()
        ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
      final toDrop = _sessions.length - 128;
      for (var i = 0; i < toDrop; i++) {
        _sessions.remove(entries[i].key);
      }
    }
  }
}

class _SpotifyDecryptSession {
  final String cacheKey;
  final List<Uri> streamUris;
  final Map<String, String> headers;
  final Uint8List audioKey;
  final DateTime createdAt;

  bool payloadOffsetResolved = false;
  int payloadOffset = 0;
  int? logicalLength;
  String? detectedContainer;

  _SpotifyDecryptSession({
    required this.cacheKey,
    required this.streamUris,
    required this.headers,
    required this.audioKey,
    required this.createdAt,
  });
}
