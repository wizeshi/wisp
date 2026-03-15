library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../utils/logger.dart';
import 'spotify_audio_key_provider.dart';

class SpotifySpclientAudioKeyProvider implements SpotifyAudioKeyProvider {
  const SpotifySpclientAudioKeyProvider();

  @override
  Future<Uint8List?> requestAudioKey({
    required String trackGidHex,
    String? trackBase62Id,
    required String fileIdHex,
    required Uri spclientBaseUri,
    Iterable<Uri>? alternateBaseUris,
    required Map<String, String> requestHeaders,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final base62 = _normalizeTrackBase62(trackBase62Id);
    final trackUri = base62 == null ? null : 'spotify:track:$base62';
    final trackLower = trackGidHex.toLowerCase();
    final trackUpper = trackGidHex.toUpperCase();
    final fileLower = fileIdHex.toLowerCase();
    final fileUpper = fileIdHex.toUpperCase();

    final endpointPaths = <String>{
      '/audio-keys/v1/track/$trackLower/file/$fileLower',
      '/audio-keys/v1/track/$trackUpper/file/$fileUpper',
      '/audio-keys/v1/track/$trackLower/file/$fileLower?product=0&country=from_token',
      '/audio-keys/v1/track/$trackLower?file_id=$fileLower',
      '/audio-keys/v1/$trackLower/$fileLower',
      '/audio-keys/v1/$trackUpper/$fileUpper',
      '/audio-keys/v1?track_id=$trackLower&file_id=$fileLower',
      '/audio-keys/v1?track_id=$trackUpper&file_id=$fileUpper',
      if (base62 != null) ...{
        '/audio-keys/v1/track/$base62/file/$fileLower',
        '/audio-keys/v1/$base62/$fileLower',
        '/audio-keys/v1?track_id=$base62&file_id=$fileLower',
        '/audio-keys/v1?trackId=$base62&fileId=$fileLower',
      },
      if (trackUri != null) ...{
        '/audio-keys/v1?track_uri=${Uri.encodeQueryComponent(trackUri)}&file_id=$fileLower',
        '/audio-keys/v1?trackUri=${Uri.encodeQueryComponent(trackUri)}&fileId=$fileLower',
      },
    }.toList(growable: false);

    final headerProfiles = <Map<String, String>>[
      {
        ...requestHeaders,
        'Accept': 'application/json, text/plain;q=0.9, */*;q=0.8',
      },
      {
        ...requestHeaders,
        if (requestHeaders['client-token'] case final token?) 'Client-Token': token,
        if (requestHeaders['client-token'] case final token?) 'client-token': token,
        'Accept': '*/*',
      },
    ];

    final attempts = <String>[];
    final baseUris = <Uri>{
      spclientBaseUri,
      ...?alternateBaseUris,
    }.toList(growable: false);

    final client = http.Client();
    try {
      for (final baseUri in baseUris) {
        for (final path in endpointPaths) {
          final uri = baseUri.resolve(path);
          for (final headers in headerProfiles) {
            try {
              final response = await client
                  .get(
                    uri,
                    headers: headers,
                  )
                  .timeout(timeout);

              if (response.statusCode != 200) {
                attempts.add('${uri.host}${uri.path} -> ${response.statusCode}');
                continue;
              }

              final key = _extractKeyBytes(response.bodyBytes, response.body);
              if (key != null && key.length == 16) {
                logger.d(
                  '[Spotify/AudioKey] Resolved key via ${uri.host}${uri.path} for file=$fileIdHex',
                );
                return key;
              }

              attempts.add(
                '${uri.host}${uri.path} -> 200 (no key in payload len=${response.bodyBytes.length})',
              );
            } catch (error) {
              attempts.add('${uri.host}${uri.path} -> ${error.runtimeType}');
              continue;
            }
          }
        }
      }
    } finally {
      client.close();
    }

    if (attempts.isNotEmpty) {
      final sample = attempts.take(10).join('; ');
      logger.w(
        '[Spotify/AudioKey] Unable to resolve key for file=$fileIdHex '
        '(trackGid=$trackLower${base62 != null ? ', trackBase62=$base62' : ''}). '
        'Attempts: $sample',
      );
    }

    return null;
  }

  Uint8List? _extractKeyBytes(Uint8List rawBytes, String rawBody) {
    final decodedJson = _tryDecodeJson(rawBody);
    if (decodedJson != null) {
      final fromJson = _extractFromJson(decodedJson);
      if (fromJson != null) return fromJson;
    }

    final fromPlain = _decodeStringToBytes(rawBody.trim());
    if (fromPlain != null) return fromPlain;

    final fromBinary = _extractFromBinary(rawBytes);
    if (fromBinary != null) return fromBinary;

    if (rawBytes.length == 16) return Uint8List.fromList(rawBytes);
    return null;
  }

  Uint8List? _extractFromBinary(Uint8List rawBytes) {
    if (rawBytes.length == 20) {
      return Uint8List.sublistView(rawBytes, 4, 20);
    }

    if (rawBytes.length >= 18) {
      for (var i = 0; i <= rawBytes.length - 18; i++) {
        if (rawBytes[i] == 0x0A && rawBytes[i + 1] == 0x10) {
          return Uint8List.fromList(rawBytes.sublist(i + 2, i + 18));
        }
      }
    }

    if (rawBytes.length >= 16) {
      final start = rawBytes.length - 16;
      final tail = rawBytes.sublist(start);
      final zeroCount = tail.where((b) => b == 0).length;
      if (zeroCount <= 8) {
        return Uint8List.fromList(tail);
      }
    }

    return null;
  }

  dynamic _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _extractFromJson(dynamic value) {
    if (value is Map<String, dynamic>) {
      final candidates = [
        value['audio_key'],
        value['audioKey'],
        value['key'],
        value['data'] is Map<String, dynamic>
            ? (value['data'] as Map<String, dynamic>)['audio_key']
            : null,
        value['data'] is Map<String, dynamic>
            ? (value['data'] as Map<String, dynamic>)['audioKey']
            : null,
        value['data'] is Map<String, dynamic>
            ? (value['data'] as Map<String, dynamic>)['key']
            : null,
      ];

      for (final candidate in candidates) {
        final parsed = _decodeDynamicToBytes(candidate);
        if (parsed != null) return parsed;
      }

      for (final nested in value.values) {
        final parsed = _extractFromJson(nested);
        if (parsed != null) return parsed;
      }
      return null;
    }

    if (value is List) {
      final parsed = _decodeDynamicToBytes(value);
      if (parsed != null) return parsed;

      for (final nested in value) {
        final recursive = _extractFromJson(nested);
        if (recursive != null) return recursive;
      }
    }

    return _decodeDynamicToBytes(value);
  }

  Uint8List? _decodeDynamicToBytes(dynamic value) {
    if (value == null) return null;

    if (value is List) {
      final ints = value.whereType<int>().toList();
      if (ints.length == 16) return Uint8List.fromList(ints);
      return null;
    }

    if (value is String) {
      return _decodeStringToBytes(value.trim());
    }

    return null;
  }

  Uint8List? _decodeStringToBytes(String input) {
    if (input.isEmpty) return null;

    final compact = input.replaceAll(RegExp(r'\s+'), '');

    final hexCandidate = compact.startsWith('0x') ? compact.substring(2) : compact;
    if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hexCandidate)) {
      final out = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        out[i] = int.parse(hexCandidate.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return out;
    }

    try {
      final normalized = compact.padRight(((compact.length + 3) ~/ 4) * 4, '=');
      final decoded = base64Decode(normalized);
      if (decoded.length == 16) return Uint8List.fromList(decoded);
    } catch (_) {}

    return null;
  }

  String? _normalizeTrackBase62(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final direct = RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(trimmed);
    if (direct) return trimmed;

    final uriMatch = RegExp(r'^spotify:track:([A-Za-z0-9]{22})$').firstMatch(trimmed);
    if (uriMatch != null) {
      return uriMatch.group(1);
    }

    return null;
  }
}
