library;

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../../utils/logger.dart';

class SpotifyAudioDecryptor {
  static final Map<String, String> _fileCacheByKey = {};

  const SpotifyAudioDecryptor();

  Future<String?> downloadAndDecryptToTemp({
    required String cacheKey,
    required String url,
    required Uint8List audioKey,
    Map<String, String>? headers,
  }) async {
    final cached = _fileCacheByKey[cacheKey];
    if (cached != null && await File(cached).exists()) {
      return cached;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      if (headers != null) {
        request.headers.addAll(headers);
      }

      final response = await client.send(request);
      if (response.statusCode != 200 && response.statusCode != 206) {
        logger.w(
          '[Spotify/Decrypt] Download failed status=${response.statusCode} url=$url',
        );
        return null;
      }

      final encryptedBytes = await response.stream.toBytes();
      if (encryptedBytes.isEmpty) {
        logger.w('[Spotify/Decrypt] Empty encrypted payload for $cacheKey');
        return null;
      }

      final decrypted = _decryptCtr(encryptedBytes, audioKey);
      final normalized = _stripContainerPrefixIfNeeded(decrypted);
      final ext = _guessExtension(normalized);

      final tempDir = await getTemporaryDirectory();
      final outDir = Directory('${tempDir.path}/wisp_spotify_decrypt');
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }

      final path = '${outDir.path}/$cacheKey.$ext';
      final outFile = File(path);
      await outFile.writeAsBytes(normalized, flush: true);

      _fileCacheByKey[cacheKey] = path;
      return path;
    } catch (error) {
      logger.w('[Spotify/Decrypt] Failed to decrypt audio for $cacheKey', error: error);
      return null;
    } finally {
      client.close();
    }
  }

  Uint8List _decryptCtr(Uint8List encrypted, Uint8List key) {
    final cipher = SICStreamCipher(AESEngine())
      ..init(
        false,
        ParametersWithIV<KeyParameter>(
          KeyParameter(key),
          Uint8List(16),
        ),
      );
    return cipher.process(encrypted);
  }

  Uint8List _stripContainerPrefixIfNeeded(Uint8List bytes) {
    if (bytes.length < 8) return bytes;
    if (_startsWith(bytes, [0x4F, 0x67, 0x67, 0x53]) ||
        _startsWith(bytes, [0x66, 0x4C, 0x61, 0x43]) ||
        _startsWith(bytes, [0x49, 0x44, 0x33])) {
      return bytes;
    }

    final maxProbe = bytes.length < 512 ? bytes.length : 512;
    for (var i = 1; i + 4 <= maxProbe; i++) {
      if (_matchesAt(bytes, i, [0x4F, 0x67, 0x67, 0x53]) ||
          _matchesAt(bytes, i, [0x66, 0x4C, 0x61, 0x43]) ||
          _matchesAt(bytes, i, [0x49, 0x44, 0x33])) {
        return Uint8List.sublistView(bytes, i);
      }
    }

    return bytes;
  }

  String _guessExtension(Uint8List bytes) {
    if (_startsWith(bytes, [0x4F, 0x67, 0x67, 0x53])) return 'ogg';
    if (_startsWith(bytes, [0x66, 0x4C, 0x61, 0x43])) return 'flac';
    if (_startsWith(bytes, [0x49, 0x44, 0x33])) return 'mp3';
    return 'bin';
  }

  bool _startsWith(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    return _matchesAt(bytes, 0, signature);
  }

  bool _matchesAt(Uint8List bytes, int offset, List<int> signature) {
    if (offset + signature.length > bytes.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }
}
