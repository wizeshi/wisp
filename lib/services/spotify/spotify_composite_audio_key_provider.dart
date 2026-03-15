library;

import 'dart:typed_data';

import 'spotify_audio_key_provider.dart';

class SpotifyCompositeAudioKeyProvider implements SpotifyAudioKeyProvider {
  final List<SpotifyAudioKeyProvider> providers;

  const SpotifyCompositeAudioKeyProvider({required this.providers});

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
    for (final provider in providers) {
      final key = await provider.requestAudioKey(
        trackGidHex: trackGidHex,
        trackBase62Id: trackBase62Id,
        fileIdHex: fileIdHex,
        spclientBaseUri: spclientBaseUri,
        alternateBaseUris: alternateBaseUris,
        requestHeaders: requestHeaders,
        timeout: timeout,
      );
      if (key != null && key.length == 16) {
        return key;
      }
    }
    return null;
  }
}
