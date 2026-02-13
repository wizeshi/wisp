/// Spotify lyrics provider using internal API + TOTP
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
import '../../utils/logger.dart';

const _spotifyWebTokenUrl = 'https://open.spotify.com/api/token';
const _spotifyClientTokenUrl = 'https://clienttoken.spotify.com/v1/clienttoken';
const _spotifyLyricsBaseUrl =
    'https://spclient.wg.spotify.com/color-lyrics/v2/track';
const _spotifyUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';
const _spotifyAppVersion = '1.2.83.373.ge7c77344';
const _allowInsecureSpotifyTls = bool.fromEnvironment(
  'WISP_ALLOW_INSECURE_SPOTIFY_TLS',
  defaultValue: true,
);
const _allowInsecureSpotifySecretsTls = bool.fromEnvironment(
  'WISP_ALLOW_INSECURE_SPOTIFY_SECRETS_TLS',
  defaultValue: true,
);

// Hosts TOTP secrets
const _secretsUrl =
    'https://git.gay/thereallo/totp-secrets/raw/branch/main/secrets/secrets.json';

class SpotifyLyricsProvider {
  final CredentialsService _credentialsService = CredentialsService();
  Future<void>? _initFuture;
  String? _clientToken;
  String? _accessToken;

  Future<void> _ensureInitialized() {
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    try {
      logger.i("Initializing Spotify lyrics provider...");

      logger.i("Fetching Spotify lyrics cookie...");

      final cookie = await _credentialsService.getSpotifyLyricsCookie();
      if (cookie == null || cookie.isEmpty) {
        throw StateError('Spotify lyrics cookie (sp_dc) not configured');
      }

      logger.i("Got Spotify cookie, requesting access token...");

      final accessJson = await _requestAccessToken(cookie);
      final accessToken = accessJson['accessToken'] as String?;
      final clientId = accessJson['clientId'] as String?;
      if (accessToken == null || clientId == null) {
        throw StateError('Invalid access token response');
      }

      logger.i("Access token obtained, requesting client token...");

      _accessToken = accessToken;

      final deviceId = _randomHex(32);
      final clientTokenPayload = {
        'client_data': {
          'client_id': clientId,
          'client_version': _spotifyAppVersion,
          'js_sdk_data': {
            'device_brand': 'unknown',
            'device_id': deviceId,
            'device_model': 'unknown',
            'device_type': 'computer',
            'os': 'windows',
            'os_version': 'NT 10.0',
          },
        },
      };

      final client = _createSpotifyHttpClient();
      http.Response clientTokenResponse;
      try {
        clientTokenResponse = await client.post(
          Uri.parse(_spotifyClientTokenUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(clientTokenPayload),
        );
      } finally {
        client.close();
      }

      if (clientTokenResponse.statusCode != 200) {
        throw StateError(
          'Spotify client token request failed: '
          '${clientTokenResponse.statusCode}',
        );
      }

      logger.i(
        "Client token obtained, Spotify lyrics provider initialized successfully",
      );

      final clientJson =
          jsonDecode(clientTokenResponse.body) as Map<String, dynamic>;
      final responseType = clientJson['response_type'] as String?;
      if (responseType == 'RESPONSE_GRANTED_TOKEN_RESPONSE') {
        final grantedToken =
            (clientJson['granted_token'] as Map<String, dynamic>?)?['token']
                as String?;
        _clientToken = grantedToken;
      }

      if (_clientToken == null || _clientToken!.isEmpty) {
        throw StateError('Invalid client token response');
      }
    } catch (e, stackTrace) {
      _initFuture = null;
      logger.e(
        'Failed to initialize Spotify lyrics provider',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<LyricsResult?> getLyrics(String trackId) async {
    try {
      await _ensureInitialized();
    } catch (_) {
      return null;
    }

    if (_accessToken == null || _clientToken == null) return null;

    final normalizedId = _normalizeTrackId(trackId);
    if (normalizedId.isEmpty) return null;

    final url = Uri.parse('$_spotifyLyricsBaseUrl/$normalizedId').replace(
      queryParameters: {
        'format': 'json',
        'vocalRemoval': 'false',
        'market': 'from_token',
      },
    );

    final client = _createSpotifyHttpClient();
    http.Response response;
    try {
      response = await client.get(
        url,
        headers: {
          'App-Platform': 'WebPlayer',
          'Accept': 'application/json',
          'Authorization': 'Bearer $_accessToken',
          'Client-Token': _clientToken!,
          'User-Agent': _spotifyUserAgent,
          'Spotify-App-Version': _spotifyAppVersion,
        },
      );
    } finally {
      client.close();
    }

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      logger.w('Spotify lyrics request failed: ${response.statusCode}');
      return null;
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final lyrics = json['lyrics'] as Map<String, dynamic>?;
      if (lyrics == null) return null;
      final syncType = lyrics['syncType'] as String? ?? 'LINE_UNSYNCED';
      final linesJson = lyrics['lines'] as List? ?? const [];
      final lines = linesJson
          .whereType<Map<String, dynamic>>()
          .map((line) {
            final content = (line['words'] as String?)?.trim() ?? '';
            final startMsRaw = line['startTimeMs'];
            final startTimeMs = startMsRaw is String
                ? int.tryParse(startMsRaw) ?? 0
                : startMsRaw is int
                ? startMsRaw
                : 0;
            return LyricsLine(content: content, startTimeMs: startTimeMs);
          })
          .where((line) => line.content.isNotEmpty)
          .toList();

      return LyricsResult(
        provider: LyricsProviderType.spotify,
        synced: syncType == 'LINE_SYNCED',
        lines: lines,
      );
    } catch (e, stackTrace) {
      logger.e(
        'Failed to parse Spotify lyrics response',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}

class _TotpPayload {
  final String otp;
  final int version;

  const _TotpPayload({required this.otp, required this.version});
}

Future<Map<String, dynamic>> _requestAccessToken(String cookie) async {
  Future<Map<String, dynamic>> fetchWithTotp(_TotpPayload totpPayload) async {
    final accessTokenUrl = Uri.parse(_spotifyWebTokenUrl).replace(
      queryParameters: {
        'reason': 'init',
        'productType': 'web-player',
        'totp': totpPayload.otp,
        'totpServer': totpPayload.otp,
        'totpVer': totpPayload.version.toString(),
      },
    );

    final client = _createSpotifyHttpClient();
    http.Response accessTokenResponse;
    try {
      accessTokenResponse = await client.get(
        accessTokenUrl,
        headers: {
          'Cookie': _normalizeCookie(cookie),
          'User-Agent': _spotifyUserAgent,
          'Accept': 'application/json',
          'Origin': 'https://open.spotify.com',
          'Referer': 'https://open.spotify.com/',
        },
      );
    } finally {
      client.close();
    }

    if (accessTokenResponse.statusCode != 200) {
      final body = accessTokenResponse.body;
      final snippet = body.length > 300 ? body.substring(0, 300) : body;
      throw StateError(
        'Spotify access token request failed: '
        '${accessTokenResponse.statusCode} ${snippet.isEmpty ? '' : snippet}',
      );
    }

    return jsonDecode(accessTokenResponse.body) as Map<String, dynamic>;
  }

  final firstTotp = await _generateTotp();
  try {
    return await fetchWithTotp(firstTotp);
  } catch (e) {
    final message = e.toString();
    if (!message.contains('400')) rethrow;
  }

  final retryTotp = await _generateTotp();
  return fetchWithTotp(retryTotp);
}

Future<_TotpPayload> _generateTotp() async {
  const secretSauce = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  final client = _createHttpClient(
    allowInsecureSpotifySecretsTls: _allowInsecureSpotifySecretsTls,
  );
  http.Response response;
  try {
    response = await client.get(Uri.parse(_secretsUrl));
  } finally {
    client.close();
  }
  if (response.statusCode != 200) {
    throw StateError('Failed to fetch TOTP secrets');
  }

  final secrets = jsonDecode(response.body) as List<dynamic>;
  if (secrets.isEmpty) {
    throw StateError('No secrets available for TOTP');
  }

  final mostRecent = secrets.last as Map<String, dynamic>;
  final version = mostRecent['version'] as int? ?? 0;
  final secretValue = mostRecent['secret'] as String? ?? '';
  if (secretValue.isEmpty) {
    throw StateError('Invalid TOTP secret payload');
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

  final secretBytes = _cleanBuffer(hexBuffer.toString());
  final base32Secret = _base32FromBytes(secretBytes, secretSauce);

  final otp = _generateTotpCode(base32Secret);
  return _TotpPayload(otp: otp, version: version);
}

Uint8List _cleanBuffer(String hex) {
  final sanitized = hex.replaceAll(' ', '');
  final length = sanitized.length ~/ 2;
  final bytes = Uint8List(length);
  for (var i = 0; i < sanitized.length; i += 2) {
    bytes[i ~/ 2] = int.parse(sanitized.substring(i, i + 2), radix: 16);
  }
  return bytes;
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

String _generateTotpCode(
  String base32Secret, {
  int digits = 6,
  int interval = 30,
}) {
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

String _randomHex(int length) {
  const hex = '0123456789abcdef';
  final rand = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(hex[rand.nextInt(16)]);
  }
  return buffer.toString();
}

String _normalizeTrackId(String trackId) {
  var id = trackId.trim();
  if (id.contains('?')) {
    id = id.split('?').first;
  }
  if (id.contains('spotify:')) {
    final parts = id.split(':');
    id = parts.isNotEmpty ? parts.last : id;
  }
  if (id.contains('/')) {
    final uri = Uri.tryParse(id);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      id = uri.pathSegments.last;
    }
  }
  return id.trim();
}

String _normalizeCookie(String cookie) {
  final trimmed = cookie.trim();
  if (trimmed.startsWith('sp_dc=')) return trimmed;
  return 'sp_dc=$trimmed';
}

http.Client _createHttpClient({required bool allowInsecureSpotifySecretsTls}) {
  if (!allowInsecureSpotifySecretsTls) {
    return http.Client();
  }

  final ioClient = HttpClient();
  ioClient.badCertificateCallback = (cert, host, port) {
    return host == 'git.gay';
  };
  return IOClient(ioClient);
}

http.Client _createSpotifyHttpClient() {
  if (!_allowInsecureSpotifyTls) {
    return http.Client();
  }

  final ioClient = HttpClient();
  ioClient.badCertificateCallback = (cert, host, port) {
    return host == 'open.spotify.com' ||
        host == 'clienttoken.spotify.com' ||
        host == 'spclient.wg.spotify.com';
  };
  return IOClient(ioClient);
}
