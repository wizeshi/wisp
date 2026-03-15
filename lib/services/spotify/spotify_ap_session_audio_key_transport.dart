library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../utils/logger.dart';

enum SpotifyApAudioKeyResponseType {
  aesKey,
  aesKeyError,
  unknown,
}

class SpotifyApAudioKeyRequest {
  final Uint8List trackGid;
  final Uint8List fileId;
  final int sequence;

  const SpotifyApAudioKeyRequest({
    required this.trackGid,
    required this.fileId,
    required this.sequence,
  });

  factory SpotifyApAudioKeyRequest.fromHex({
    required String trackGidHex,
    required String fileIdHex,
    required int sequence,
  }) {
    final trackBytes = _decodeHex(trackGidHex);
    final fileBytes = _decodeHex(fileIdHex);
    if (trackBytes.length != 16) {
      throw ArgumentError.value(trackGidHex, 'trackGidHex', 'must be 16 bytes in hex');
    }
    if (fileBytes.length != 20) {
      throw ArgumentError.value(fileIdHex, 'fileIdHex', 'must be 20 bytes in hex');
    }
    return SpotifyApAudioKeyRequest(
      trackGid: trackBytes,
      fileId: fileBytes,
      sequence: sequence & 0xFFFFFFFF,
    );
  }

  Uint8List toRequestKeyPayload() {
    final out = Uint8List(42);
    out.setRange(0, 20, fileId);
    out.setRange(20, 36, trackGid);

    out[36] = (sequence >> 24) & 0xFF;
    out[37] = (sequence >> 16) & 0xFF;
    out[38] = (sequence >> 8) & 0xFF;
    out[39] = sequence & 0xFF;
    out[40] = 0x00;
    out[41] = 0x00;
    return out;
  }
}

class SpotifyApAudioKeyResponse {
  final SpotifyApAudioKeyResponseType type;
  final Uint8List payload;

  const SpotifyApAudioKeyResponse({
    required this.type,
    required this.payload,
  });

  Uint8List? extractAudioKey() {
    if (type != SpotifyApAudioKeyResponseType.aesKey) return null;

    if (payload.length == 16) {
      return Uint8List.fromList(payload);
    }

    if (payload.length >= 20) {
      final key = payload.sublist(payload.length - 16);
      return Uint8List.fromList(key);
    }

    return null;
  }
}

abstract class SpotifyApSessionAudioKeyTransport {
  Future<SpotifyApAudioKeyResponse?> requestAudioKey({
    required SpotifyApAudioKeyRequest request,
    Duration timeout = const Duration(milliseconds: 1500),
  });
}

class SpotifyHttpApSessionAudioKeyTransport
    implements SpotifyApSessionAudioKeyTransport {
  final List<Uri> baseUris;
  final Map<String, String> headers;
  final http.Client? _client;

  static final Map<String, DateTime> _hostCooldownUntil =
      <String, DateTime>{};

  SpotifyHttpApSessionAudioKeyTransport({
    required Iterable<Uri> baseUris,
    required Map<String, String> headers,
    http.Client? client,
  }) : baseUris = _normalizeBaseUris(baseUris),
       headers = Map<String, String>.unmodifiable(headers),
       _client = client;

  @override
  Future<SpotifyApAudioKeyResponse?> requestAudioKey({
    required SpotifyApAudioKeyRequest request,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    if (baseUris.isEmpty) {
      return null;
    }

    final payload = request.toRequestKeyPayload();
    final attempts = <String>[];

    final ownedClient = _client == null;
    final client = _client ?? http.Client();
    try {
      for (final baseUri in baseUris) {
        if (_isHostOnCooldown(baseUri.host)) {
          attempts.add('${baseUri.host} -> cooldown');
          continue;
        }

        var abortHost = false;
        for (final endpointPath in _endpointPaths) {
          if (abortHost) {
            break;
          }

          final uri = baseUri.resolve(endpointPath);
          try {
            final response = await client
                .post(
                  uri,
                  headers: _buildHeaders(),
                  body: payload,
                )
                .timeout(timeout);

            final parsed = _parseResponse(response);
            if (parsed != null) {
              _markHostHealthy(baseUri.host);
              return parsed;
            }

            attempts.add('${uri.host}${uri.path} -> ${response.statusCode}');
          } catch (error) {
            attempts.add('${uri.host}${uri.path} -> ${error.runtimeType}');

            final isTimeoutLike =
                error is TimeoutException || error is http.ClientException;
            if (isTimeoutLike) {
              _markHostCooldown(baseUri.host);
              abortHost = true;
            }
          }
        }
      }
    } finally {
      if (ownedClient) {
        client.close();
      }
    }

    if (attempts.isNotEmpty) {
      final sample = attempts.take(8).join('; ');
      logger.d('[Spotify/APAudioKey] No AP key response for seq=${request.sequence}. Attempts: $sample');
    }

    return null;
  }

  Map<String, String> _buildHeaders() {
    return {
      ...headers,
      'Accept': '*/*',
      'Content-Type': 'application/octet-stream',
    };
  }

  SpotifyApAudioKeyResponse? _parseResponse(http.Response response) {
    if (response.statusCode == 404 || response.statusCode == 405) {
      return null;
    }

    final bodyBytes = response.bodyBytes;
    final key = _extractAudioKey(bodyBytes, response.body);
    if (response.statusCode >= 200 && response.statusCode < 300 && key != null) {
      return SpotifyApAudioKeyResponse(
        type: SpotifyApAudioKeyResponseType.aesKey,
        payload: key,
      );
    }

    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 429 ||
        response.statusCode >= 500) {
      return SpotifyApAudioKeyResponse(
        type: SpotifyApAudioKeyResponseType.aesKeyError,
        payload: bodyBytes,
      );
    }

    if (_looksLikeErrorBody(response.body)) {
      return SpotifyApAudioKeyResponse(
        type: SpotifyApAudioKeyResponseType.aesKeyError,
        payload: bodyBytes,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300 && bodyBytes.isNotEmpty) {
      return SpotifyApAudioKeyResponse(
        type: SpotifyApAudioKeyResponseType.unknown,
        payload: bodyBytes,
      );
    }

    return null;
  }

  Uint8List? _extractAudioKey(Uint8List bodyBytes, String bodyText) {
    if (bodyBytes.length == 16) {
      return Uint8List.fromList(bodyBytes);
    }

    if (bodyBytes.length == 20) {
      return Uint8List.fromList(bodyBytes.sublist(4, 20));
    }

    if (bodyBytes.length >= 18) {
      for (var i = 0; i <= bodyBytes.length - 18; i++) {
        if (bodyBytes[i] == 0x0A && bodyBytes[i + 1] == 0x10) {
          return Uint8List.fromList(bodyBytes.sublist(i + 2, i + 18));
        }
      }
    }

    final dynamic decoded = _tryDecodeJson(bodyText);
    if (decoded is Map<String, dynamic>) {
      final candidates = [
        decoded['key'],
        decoded['audio_key'],
        decoded['audioKey'],
        decoded['result'] is Map<String, dynamic>
            ? (decoded['result'] as Map<String, dynamic>)['key']
            : null,
      ];
      for (final candidate in candidates) {
        final parsed = _decodeHexLike(candidate);
        if (parsed != null && parsed.length == 16) {
          return parsed;
        }
      }
    }

    final textCandidate = _decodeHexLike(bodyText.trim());
    if (textCandidate != null && textCandidate.length == 16) {
      return textCandidate;
    }

    return null;
  }

  dynamic _tryDecodeJson(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _decodeHexLike(dynamic value) {
    if (value is! String) return null;
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return null;

    final normalized = compact.startsWith('0x') || compact.startsWith('0X')
        ? compact.substring(2)
        : compact;
    if (normalized.length.isOdd) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) return null;

    try {
      return _decodeHex(normalized);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeErrorBody(String body) {
    if (body.isEmpty) return false;
    final lower = body.toLowerCase();
    return lower.contains('error') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        lower.contains('rate limit');
  }

  static List<Uri> _normalizeBaseUris(Iterable<Uri> input) {
    final seen = <String>{};
    final out = <Uri>[];
    for (final uri in input) {
      final normalized = Uri(
        scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : 443,
      );
      final key = normalized.toString();
      if (normalized.host.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      out.add(normalized);
    }
    return out;
  }

  static const List<String> _endpointPaths = [
    '/audio/key/v1',
    '/audio/key/v1/request',
    '/audio-keys/v1/request',
    '/keymaster/v1/audio/key',
    '/keymaster/v1/request',
  ];

  bool _isHostOnCooldown(String host) {
    final until = _hostCooldownUntil[host];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _hostCooldownUntil.remove(host);
      return false;
    }
    return true;
  }

  void _markHostCooldown(String host) {
    _hostCooldownUntil[host] = DateTime.now().add(
      const Duration(minutes: 5),
    );
  }

  void _markHostHealthy(String host) {
    _hostCooldownUntil.remove(host);
  }
}

class NoopSpotifyApSessionAudioKeyTransport
    implements SpotifyApSessionAudioKeyTransport {
  const NoopSpotifyApSessionAudioKeyTransport();

  @override
  Future<SpotifyApAudioKeyResponse?> requestAudioKey({
    required SpotifyApAudioKeyRequest request,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    return null;
  }
}

Uint8List _decodeHex(String hex) {
  final compact = hex.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  final normalized = compact.startsWith('0x') ? compact.substring(2) : compact;

  if (normalized.isEmpty || normalized.length.isOdd) {
    throw ArgumentError.value(hex, 'hex', 'must be non-empty and even-length');
  }
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(normalized)) {
    throw ArgumentError.value(hex, 'hex', 'contains non-hex characters');
  }

  final out = Uint8List(normalized.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
