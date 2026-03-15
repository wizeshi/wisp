library;

import 'dart:typed_data';

import '../../utils/logger.dart';
import 'spotify_ap_session_audio_key_transport.dart';
import 'spotify_audio_key_provider.dart';

class SpotifySessionAudioKeyProvider implements SpotifyAudioKeyProvider {
  final SpotifyApSessionAudioKeyTransport? transport;

  static SpotifyApSessionAudioKeyTransport? _globalTransport;

  const SpotifySessionAudioKeyProvider({this.transport});

  static void registerGlobalTransport(SpotifyApSessionAudioKeyTransport? value) {
    _globalTransport = value;
  }

  static SpotifyApSessionAudioKeyTransport? get globalTransport => _globalTransport;

  static int _sequence = 0;

  static int _nextSequence() {
    final current = _sequence & 0xFFFFFFFF;
    _sequence = (_sequence + 1) & 0xFFFFFFFF;
    return current;
  }

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
    final sessionTransport = transport ?? _globalTransport;
    if (sessionTransport == null) {
      logger.d('[Spotify/AudioKey] Session transport unavailable; skipping AP key request.');
      return null;
    }

    SpotifyApAudioKeyRequest request;
    try {
      request = SpotifyApAudioKeyRequest.fromHex(
        trackGidHex: trackGidHex,
        fileIdHex: fileIdHex,
        sequence: _nextSequence(),
      );
    } catch (error) {
      logger.w(
        '[Spotify/AudioKey] Invalid AP key request ids track=$trackGidHex file=$fileIdHex',
        error: error,
      );
      return null;
    }

    try {
      final response = await sessionTransport.requestAudioKey(
        request: request,
        timeout: timeout > const Duration(milliseconds: 400)
            ? const Duration(milliseconds: 400)
            : timeout,
      );
      if (response == null) {
        return null;
      }

      final key = response.extractAudioKey();
      if (key != null && key.length == 16) {
        logger.d('[Spotify/AudioKey] Resolved key via AP session transport for file=$fileIdHex');
        return key;
      }

      if (response.type == SpotifyApAudioKeyResponseType.aesKeyError) {
        logger.w('[Spotify/AudioKey] AP session returned AES key error for file=$fileIdHex');
      }
    } catch (error) {
      logger.w('[Spotify/AudioKey] AP session key request failed for file=$fileIdHex', error: error);
    }

    return null;
  }
}
