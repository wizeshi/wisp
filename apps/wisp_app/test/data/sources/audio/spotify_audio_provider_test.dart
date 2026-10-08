// Copyright © 2026 wizeshi

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp/data/cache/audio/audio_storage_service.dart';
import 'package:wisp/data/sources/providers/ap_key_resolver.dart';
import 'package:wisp/data/sources/providers/jumo_crypto_utils.dart';
import 'package:wisp/services/audio/streaming_server.dart';

void main() {
  group('ShannonCipher Tests', () {
    test('ShannonCipher encryption and decryption roundtrip', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i * 7 & 0xFF));
      final cipherEnc = ShannonCipher(key);
      final cipherDec = ShannonCipher(key);

      final plaintext = utf8.encode('Hello, Spotify AP Shannon protocol testing!');
      final buf = Uint8List.fromList(plaintext);

      cipherEnc.nonceU32(1);
      cipherEnc.encrypt(buf);

      // Ciphertext should not match plaintext
      expect(buf, isNot(equals(plaintext)));

      cipherDec.nonceU32(1);
      cipherDec.decrypt(buf);

      // Decrypted should match original plaintext
      expect(buf, equals(plaintext));
    });

    test('ShannonCipher MAC generation consistency', () {
      final key = Uint8List.fromList(List.generate(32, (i) => (i * 13 + 3) & 0xFF));
      final cipher1 = ShannonCipher(key);
      final cipher2 = ShannonCipher(key);

      final msg = Uint8List.fromList(utf8.encode('Packet authentication check'));
      final msg1 = Uint8List.fromList(msg);
      final msg2 = Uint8List.fromList(msg);

      cipher1.nonceU32(42);
      cipher1.encrypt(msg1);
      final mac1 = cipher1.finish(4);

      cipher2.nonceU32(42);
      cipher2.encrypt(msg2);
      final mac2 = cipher2.finish(4);

      expect(mac1, equals(mac2));
      expect(mac1.length, equals(4));
    });

    test('ShannonCipher chunked decryption (header then payload) matches all-at-once', () {
      final key = Uint8List.fromList(List.generate(32, (i) => (i * 17 + 5) & 0xFF));
      final encCipher = ShannonCipher(key);
      final decAllCipher = ShannonCipher(key);
      final decChunkedCipher = ShannonCipher(key);

      // 3 bytes header + 17 bytes payload (non-multiple of 4)
      final rawPacket = Uint8List.fromList([
        0xab, 0x00, 0x11, // 3 bytes header
        ...List.generate(17, (i) => (i * 3 + 1) & 0xFF), // 17 bytes payload
      ]);

      final toEncrypt = Uint8List.fromList(rawPacket);
      encCipher.nonceU32(0);
      encCipher.encrypt(toEncrypt);
      final encMac = encCipher.finish(4);

      // Decrypt all at once
      final decAll = Uint8List.fromList(toEncrypt);
      decAllCipher.nonceU32(0);
      decAllCipher.decrypt(decAll);
      final decAllMac = decAllCipher.finish(4);
      expect(decAll, equals(rawPacket));
      expect(decAllMac, equals(encMac));

      // Decrypt in chunks: 3 bytes header, then 17 bytes payload
      final chunkHeader = Uint8List.fromList(toEncrypt.sublist(0, 3));
      final chunkPayload = Uint8List.fromList(toEncrypt.sublist(3));

      decChunkedCipher.nonceU32(0);
      decChunkedCipher.decrypt(chunkHeader);
      decChunkedCipher.decrypt(chunkPayload);
      final decChunkedMac = decChunkedCipher.finish(4);

      expect(chunkHeader, equals(rawPacket.sublist(0, 3)));
      expect(chunkPayload, equals(rawPacket.sublist(3)));
      expect(decChunkedMac, equals(encMac));
    });
  });

  group('Spotify Audio Decryption Tests', () {
    test('AES-128-CTR decrypts audio chunks and removes Spotify 167-byte header', () {
      final keyHex = '0123456789abcdef0123456789abcdef';
      final ivHex = '72e067fbddcbcf77ebe8bc643f630d93';
      const skipBytes = 167;

      final keyBytes = JumoCryptoUtils.hexToBytes(keyHex);
      final ivBytes = JumoCryptoUtils.hexToBytes(ivHex);

      // Simulate a Spotify audio file: 167 bytes of proprietary header followed by 'OggS'
      final oggMagic = utf8.encode('OggS');
      final payload = Uint8List(skipBytes + oggMagic.length + 100);
      for (var i = 0; i < skipBytes; i++) {
        payload[i] = 0xAA;
      }
      payload.setRange(skipBytes, skipBytes + oggMagic.length, oggMagic);

      // Encrypt payload to simulate CDN file
      final encryptCipher = CTRStreamCipher(AESEngine());
      encryptCipher.init(true, ParametersWithIV(KeyParameter(keyBytes), ivBytes));
      final encryptedCdnBytes = encryptCipher.process(payload);

      // Decrypt using AudioStreamingProxy logic
      final decryptCipher = CTRStreamCipher(AESEngine());
      decryptCipher.init(false, ParametersWithIV(KeyParameter(keyBytes), ivBytes));

      final decrypted = decryptCipher.process(encryptedCdnBytes);
      expect(decrypted.length, equals(payload.length));

      // Discard the 167 bytes header prefix
      final strippedAudio = decrypted.sublist(skipBytes);

      // Output must begin with 'OggS' container header
      expect(strippedAudio.sublist(0, 4), equals(oggMagic));
    });

    test('AudioStreamingProxy serves cached decrypted files with HTTP 206 Partial Content for Range requests', () async {
      final proxy = AudioStreamingProxy.instance;
      await proxy.start();

      final tempDir = Directory.systemTemp.createTempSync('wisp_proxy_test_');
      final audioDir = Directory('${tempDir.path}/audio_cache')..createSync(recursive: true);
      final testAudioFile = File('${audioDir.path}/cached_track.ogg');
      final dummyAudioBytes = utf8.encode('OggS_test_audio_payload_content_for_range_checking!');
      testAudioFile.writeAsBytesSync(dummyAudioBytes);

      final storage = AudioStorageService.instance;
      storage.resetForTesting();
      SharedPreferences.setMockInitialValues({});
      await storage.initialize(
        supportDirectory: tempDir,
        cacheDirectory: tempDir,
      );

      final cipherData = {
        'cipher': {
          'algorithm': 'aes-128-ctr',
          'format': 'ogg',
          'keyHex': '0123456789abcdef0123456789abcdef',
          'ivHex': '72e067fbddcbcf77ebe8bc643f630d93',
          'skipBytes': 0,
        }
      };

      final proxyUrl = proxy.buildProxyUrl(
        trackId: 'range_test_track',
        videoId: 'spotify_range_vid',
        trackTitle: 'Range Track',
        artistName: 'Range Artist',
        targetUrl: 'https://example.com/audio',
        customData: cipherData,
      );

      // Also register entry so storage.getCachedPath finds it
      final tempPart = File('${tempDir.path}/temp.part')..writeAsBytesSync(dummyAudioBytes);
      await storage.registerCompletedDownload(
        trackId: 'range_test_track',
        videoId: 'spotify_range_vid',
        tempPartPath: tempPart.path,
        finalFilePath: testAudioFile.path,
        trackTitle: 'Range Track',
        artistName: 'Range Artist',
        isUserDownload: false,
      );

      final dio = Dio();
      final res = await dio.get<List<int>>(
        proxyUrl,
        options: Options(
          headers: {'range': 'bytes=0-3'},
          responseType: ResponseType.bytes,
          validateStatus: (s) => true,
        ),
      );

      expect(res.statusCode, equals(206));
      expect(res.headers.value('content-range'), equals('bytes 0-3/${dummyAudioBytes.length}'));
      expect(utf8.decode(res.data!), equals('OggS'));

      await proxy.stop();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  File resolveProviderFile(String relPath) {
    final f1 = File(relPath);
    if (f1.existsSync()) return f1;
    final f2 = File('../../$relPath');
    if (f2.existsSync()) return f2;
    return f1;
  }

  group('Spotify Audio Provider Manifest & Spec Tests', () {
    test('manifest.json conforms to audio provider specification', () {
      final manifestFile = resolveProviderFile('providers/audio/spotify/manifest.json');
      expect(manifestFile.existsSync(), isTrue, reason: 'manifest.json must exist');

      final json = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      expect(json['id'], equals('spotify'));
      expect(json['name'], equals('Spotify'));
      expect(json['type'], equals('audio'));
      expect(json['entry'], equals('index.js'));
      expect(json['priority'], equals(85));
      expect(json['service'], equals('spotify'));
      expect(json['dependencies'], contains('auth/spotify'));
      expect(json['supportedQualities'], containsAll(['standard', 'high']));
    });

    test('icon.svg and index.js exist in provider directory', () {
      final iconFile = resolveProviderFile('providers/audio/spotify/icon.svg');
      final indexFile = resolveProviderFile('providers/audio/spotify/index.js');
      expect(iconFile.existsSync(), isTrue);
      expect(indexFile.existsSync(), isTrue);

      final indexContent = indexFile.readAsStringSync();
      expect(indexContent.contains('searchAudio'), isTrue);
      expect(indexContent.contains('getStreamUrl'), isTrue);
      expect(indexContent.contains('isPremium'), isTrue);
      expect(indexContent.contains('wisp.audio.resolveKey'), isTrue);
      expect(indexContent.contains('72e067fbddcbcf77ebe8bc643f630d93'), isTrue);
    });
  });
}

