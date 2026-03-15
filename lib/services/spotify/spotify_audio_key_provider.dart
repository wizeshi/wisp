library;

import 'dart:typed_data';

/// Contract for obtaining Spotify track decryption keys via a session channel.
///
/// Librespot fetches audio keys over the AP/session channel using track+file ids.
/// This abstraction lets us plug in a Dart implementation later without changing
/// playback and stream resolution layers.
abstract class SpotifyAudioKeyProvider {
  Future<Uint8List?> requestAudioKey({
    required String trackGidHex,
    String? trackBase62Id,
    required String fileIdHex,
    required Uri spclientBaseUri,
    Iterable<Uri>? alternateBaseUris,
    required Map<String, String> requestHeaders,
    Duration timeout = const Duration(milliseconds: 1500),
  });
}

/// Default no-op provider until AP/session key exchange is implemented.
class NoopSpotifyAudioKeyProvider implements SpotifyAudioKeyProvider {
  const NoopSpotifyAudioKeyProvider();

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
    return null;
  }
}

