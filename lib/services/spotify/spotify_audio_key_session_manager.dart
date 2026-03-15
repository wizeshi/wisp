library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../utils/logger.dart';
import '../credentials.dart';
import 'spotify_access_point_resolver.dart';
import 'spotify_ap_session_audio_key_transport.dart';
import 'spotify_session_audio_key_provider.dart';

class SpotifyAudioKeySessionManager {
  SpotifyAudioKeySessionManager._();

  static final SpotifyAudioKeySessionManager instance =
      SpotifyAudioKeySessionManager._();

  final CredentialsService _credentialsService = CredentialsService();
  final SpotifyAccessPointResolver _accessPointResolver =
      const SpotifyAccessPointResolver();

  SpotifyServiceAccessPoints? _accessPoints;
  String? _bearerToken;
  String? _clientToken;
  String? _cookie;

  Future<void> initializeOnStartup() async {
    final cookie = await _credentialsService.getSpotifyLyricsCookie();
    if (cookie == null || cookie.trim().isEmpty) {
      await clear();
      return;
    }

    await initializeWithCookie(cookie);
  }

  Future<void> initializeWithCookie(String cookie) async {
    _cookie = _normalizeCookie(cookie);

    try {
      _accessPoints ??= await _accessPointResolver.resolve();
    } catch (error) {
      logger.w('[Spotify/APSession] Failed to resolve access points', error: error);
    }

    try {
      await _ensureTokensFromCookie(_cookie!);
    } catch (error) {
      logger.w(
        '[Spotify/APSession] Failed to initialize bearer/client token context',
        error: error,
      );
    }

    _registerOrClearTransport();
  }

  Future<void> updateAuthContext({
    required String? bearerToken,
    required String? clientToken,
    String? cookie,
  }) async {
    if (cookie != null && cookie.trim().isNotEmpty) {
      _cookie = _normalizeCookie(cookie);
    }
    if (bearerToken != null && bearerToken.isNotEmpty) {
      _bearerToken = bearerToken;
    }
    if (clientToken != null && clientToken.isNotEmpty) {
      _clientToken = clientToken;
    }

    try {
      _accessPoints ??= await _accessPointResolver.resolve();
    } catch (error) {
      logger.w('[Spotify/APSession] Failed to refresh access points', error: error);
    }

    _registerOrClearTransport();
  }

  Future<void> clear() async {
    _accessPoints = null;
    _bearerToken = null;
    _clientToken = null;
    _cookie = null;
    SpotifySessionAudioKeyProvider.registerGlobalTransport(null);
  }

  void _registerOrClearTransport() {
    final points = _accessPoints;
    if (points == null) {
      SpotifySessionAudioKeyProvider.registerGlobalTransport(null);
      return;
    }

    final headers = <String, String>{
      'User-Agent': _spotifyUserAgent,
      'Accept': '*/*',
      if (_bearerToken != null && _bearerToken!.isNotEmpty)
        'Authorization': 'Bearer $_bearerToken',
      if (_clientToken != null && _clientToken!.isNotEmpty)
        'client-token': _clientToken!,
      if (_cookie != null && _cookie!.isNotEmpty) 'Cookie': _cookie!,
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
      'app-platform': 'WebPlayer',
      'spotify-app-version': _spotifyAppVersion,
      'Accept-Language': 'en',
    };

    final transport = SpotifyHttpApSessionAudioKeyTransport(
      baseUris: [
        points.accesspointBaseUri,
        points.spclientBaseUri,
      ],
      headers: headers,
    );
    SpotifySessionAudioKeyProvider.registerGlobalTransport(transport);
  }

  Future<void> _ensureTokensFromCookie(String cookie) async {
    if (_bearerToken != null && _clientToken != null) {
      return;
    }

    final accessJson = await _requestAccessToken(cookie);
    final accessToken = accessJson['accessToken'] as String?;
    final clientId = accessJson['clientId'] as String?;
    if (accessToken == null || accessToken.isEmpty || clientId == null || clientId.isEmpty) {
      throw StateError('[Spotify/APSession] Access token response missing required fields');
    }

    _bearerToken = accessToken;
    _clientToken ??= await _requestClientToken(clientId);
  }

  Future<Map<String, dynamic>> _requestAccessToken(String cookie) async {
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
            'Cookie': cookie,
            'User-Agent': _spotifyUserAgent,
            'Accept': 'application/json',
            'Origin': 'https://open.spotify.com',
            'Referer': 'https://open.spotify.com/',
          },
        ),
      );

      if (response.statusCode != 200) {
        throw StateError('[Spotify/APSession] Access token request failed: ${response.statusCode}');
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw StateError('[Spotify/APSession] Invalid token response payload');
      }
      return body;
    }

    final first = await _generateTotp();
    try {
      return await fetchWithTotp(first);
    } catch (error) {
      final text = error.toString();
      if (!text.contains('400')) {
        rethrow;
      }
    }

    final retry = await _generateTotp();
    return fetchWithTotp(retry);
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
      throw StateError('[Spotify/APSession] Client token request failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('[Spotify/APSession] Invalid client token response payload');
    }

    final responseType = decoded['response_type'] as String?;
    if (responseType != 'RESPONSE_GRANTED_TOKEN_RESPONSE') {
      throw StateError('[Spotify/APSession] Unsupported client token response type: $responseType');
    }

    final granted = decoded['granted_token'] as Map<String, dynamic>?;
    final token = granted?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('[Spotify/APSession] Missing granted client token');
    }

    return token;
  }

  Future<_TotpPayload> _generateTotp() async {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

    final response = await _requestSecretsWithTlsFallback(
      request: (client) => client.get(Uri.parse(_spotifySecretsUrl)),
    );
    if (response.statusCode != 200) {
      throw StateError('[Spotify/APSession] Failed to fetch TOTP secrets');
    }

    final secrets = jsonDecode(response.body) as List<dynamic>;
    if (secrets.isEmpty) {
      throw StateError('[Spotify/APSession] No TOTP secrets available');
    }

    final latest = secrets.last as Map<String, dynamic>;
    final version = latest['version'] as int? ?? 0;
    final secretValue = latest['secret'] as String? ?? '';
    if (secretValue.isEmpty) {
      throw StateError('[Spotify/APSession] Invalid TOTP secret payload');
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
        '[Spotify/APSession] TLS certificate validation failed for $hostForLog; retrying with scoped insecure fallback.',
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
        '[Spotify/APSession] TLS certificate validation failed for git.gay; retrying with scoped insecure fallback.',
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

  String _normalizeCookie(String cookie) {
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

  String _generateTotpCode(String base32Secret, {
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

  String _randomHex(int length) {
    const alphabet = '0123456789abcdef';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < length; index++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }
}

class _TotpPayload {
  final String otp;
  final int version;

  const _TotpPayload({required this.otp, required this.version});
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

const String _spotifyWebTokenUrl = 'https://open.spotify.com/api/token';
const String _spotifyClientTokenUrl = 'https://clienttoken.spotify.com/v1/clienttoken';
const String _spotifySecretsUrl =
    'https://git.gay/thereallo/totp-secrets/raw/branch/main/secrets/secrets.json';
const String _spotifyUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';
const String _spotifyAppVersion = '1.2.85.300.gd6e199b8';
