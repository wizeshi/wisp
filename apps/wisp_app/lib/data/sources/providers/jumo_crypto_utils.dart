// Copyright © 2026 wizeshi

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class JumoCryptoUtils {
  JumoCryptoUtils._();

  static final ECDomainParameters _p256Params = () {
    final domain = ECCurve_secp256r1();
    return ECDomainParametersImpl(
      'secp256r1',
      domain.curve,
      domain.G,
      domain.n,
      domain.h,
      domain.seed,
    );
  }();

  /// Generates a P-256 keypair and returns base64url-encoded components.
  static Map<String, String> generateP256KeyPair() {
    final keyGen = ECKeyGenerator();
    final secureRandom = FortunaRandom();
    final rand = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      seed[i] = rand.nextInt(256);
    }
    secureRandom.seed(KeyParameter(seed));

    final genParams = ECKeyGeneratorParameters(_p256Params);
    keyGen.init(ParametersWithRandom(genParams, secureRandom));

    final pair = keyGen.generateKeyPair();
    final priv = pair.privateKey;
    final pub = pair.publicKey;

    // 65-byte uncompressed public key: 0x04 || X || Y
    final pubBytes = pub.Q!.getEncoded(false);
    final pubB64Url = _bytesToBase64Url(pubBytes);
    // 32-byte big-endian private key
    final privHex = priv.d!.toRadixString(16).padLeft(64, '0');

    return {
      'publicKey': pubB64Url,
      'privateKeyHex': privHex,
    };
  }

  /// Derives the ECDH shared secret (32-byte X coordinate).
  static Uint8List deriveSharedSecretX(String clientPrivHex, String serverPubKeyB64Url) {
    final clientD = BigInt.parse(clientPrivHex, radix: 16);
    final serverPubBytes = _base64UrlToBytes(serverPubKeyB64Url);
    final serverPoint = _p256Params.curve.decodePoint(serverPubBytes);

    // Compute shared point = clientD * serverPoint
    final sharedPoint = serverPoint! * clientD;
    final xCoord = sharedPoint!.x!.toBigInteger()!;
    final xHex = xCoord.toRadixString(16).padLeft(64, '0');
    return _hexToBytes(xHex);
  }

  /// Derives AES-GCM key using HKDF-SHA256 (salt: 'jumo-response-v1', info: 'fetch-json').
  static Uint8List deriveAesGcmKey(Uint8List sharedSecretX, {String saltStr = 'jumo-response-v1', String infoStr = 'fetch-json'}) {
    final hkdf = HKDFKeyDerivator(SHA256Digest());
    final salt = Uint8List.fromList(utf8.encode(saltStr));
    final info = Uint8List.fromList(utf8.encode(infoStr));
    hkdf.init(HkdfParameters(sharedSecretX, 32, salt, info));
    return hkdf.process(Uint8List(0));
  }

  /// Decrypts AES-GCM ciphertext with tag.
  static Uint8List decryptAesGcm({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List ciphertextWithTag,
    required Uint8List aad,
  }) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(key), 128, iv, aad);
    cipher.init(false, params);
    return cipher.process(ciphertextWithTag);
  }

  /// AES-CTR decryption for individual Qobuz audio frames.
  static Uint8List decryptAesCtr({
    required Uint8List key,
    required Uint8List counter16,
    required Uint8List ciphertext,
  }) {
    final cipher = CTRStreamCipher(AESEngine());
    cipher.init(false, ParametersWithIV(KeyParameter(key), counter16));
    final out = Uint8List(ciphertext.length);
    cipher.processBytes(ciphertext, 0, ciphertext.length, out, 0);
    return out;
  }

  /// Parses Qobuz Segment 0 initialization MP4/UUID atom to extract the FLAC header
  /// and the table of audio segment byte lengths and sample counts.
  static QobuzSegment0Info parseSegment0(Uint8List seg0Bytes) {
    final xeMagic = _hexToBytes('c7c75df0fdd951e98fc22971e4acf8d2');
    final view = ByteData.sublistView(seg0Bytes);

    for (final atom in _parseAtoms(seg0Bytes)) {
      if (atom.type != 'uuid' || atom.start + 24 > atom.end) continue;
      if (!_matchesBytes(seg0Bytes, xeMagic, atom.start + 8)) continue;

      final payload = seg0Bytes.sublist(atom.start + 24, atom.end);
      if (payload.length < 28) throw Exception('Truncated Qobuz segment 0 uuid payload');

      final headerLen = view.getUint16(atom.start + 24 + 26, Endian.big);
      final headerBytes = (headerLen > 0 && 28 + headerLen <= payload.length)
          ? payload.sublist(28, 28 + headerLen)
          : payload.sublist(28);

      var tableOffset = 28 + headerLen;
      final table = <QobuzSegmentTableEntry>[];

      if (tableOffset + 1 <= payload.length) {
        final extra = payload[tableOffset];
        tableOffset += 1 + extra;
        if (tableOffset + 2 <= payload.length) {
          final count = view.getUint16(atom.start + 24 + tableOffset, Endian.big);
          tableOffset += 2;
          for (var i = 0; i < count && tableOffset + 8 <= payload.length; i++) {
            final byteLen = view.getUint32(atom.start + 24 + tableOffset, Endian.big);
            final samples = view.getUint32(atom.start + 24 + tableOffset + 4, Endian.big);
            tableOffset += 8;
            table.add(QobuzSegmentTableEntry(byteLength: byteLen, sampleCount: samples));
          }
        }
      }

      // Check for FLAC magic 'fLaC' in candidate header
      final flacIndex = _findPattern(headerBytes, [102, 76, 97, 67]);
      if (flacIndex >= 0 && flacIndex + 42 <= headerBytes.length) {
        final flacHeader = Uint8List.fromList(headerBytes.sublist(flacIndex, flacIndex + 42));
        // Set last metadata block flag on block type byte
        flacHeader[4] |= 0x80;
        return QobuzSegment0Info(kind: 'flac', header: flacHeader, table: table);
      }

      return QobuzSegment0Info(kind: 'mp4', header: seg0Bytes, table: table);
    }

    throw Exception('No valid Qobuz initialization atom found in segment 0');
  }

  /// Parses and decrypts a Qobuz audio segment (s >= 1).
  static Uint8List decryptSegmentAudio({
    required Uint8List segmentBytes,
    required Uint8List contentKey,
  }) {
    final yeMagic = _hexToBytes('3b42129256f35f75923663b69a1f52b2');
    final view = ByteData.sublistView(segmentBytes);

    int uuidStart = -1;
    for (final atom in _parseAtoms(segmentBytes)) {
      if (atom.type == 'uuid' && atom.start + 24 <= atom.end && _matchesBytes(segmentBytes, yeMagic, atom.start + 8)) {
        uuidStart = atom.start;
        break;
      }
    }

    if (uuidStart < 0) {
      throw Exception('Qobuz segment UUID atom not found');
    }

    final base = uuidStart + 24;
    final dataOffset = view.getUint32(base + 4, Endian.big);
    final ivLen = segmentBytes[base + 8];
    final count = (segmentBytes[base + 9] << 16) | (segmentBytes[base + 10] << 8) | segmentBytes[base + 11];

    final dataStart = uuidStart + dataOffset;
    var entryOffset = base + 12;
    final entrySize = 8 + ivLen;

    final decryptedFrames = <Uint8List>[];
    var totalDecryptedBytes = 0;
    var cursor = dataStart;

    final cipher = CTRStreamCipher(AESEngine());

    for (var i = 0; i < count; i++) {
      if (entryOffset + entrySize > segmentBytes.length) {
        throw Exception('Truncated segment frame entries');
      }
      final size = view.getUint32(entryOffset, Endian.big);
      final flags = view.getUint16(entryOffset + 6, Endian.big);
      final ivSlice = segmentBytes.sublist(entryOffset + 8, entryOffset + 8 + ivLen);
      entryOffset += entrySize;

      if (cursor + size > segmentBytes.length) {
        throw Exception('Frame overruns segment data');
      }

      final frameCiphertext = segmentBytes.sublist(cursor, cursor + size);
      cursor += size;

      if (flags == 0) {
        decryptedFrames.add(frameCiphertext);
        totalDecryptedBytes += frameCiphertext.length;
      } else {
        final counter = Uint8List(16);
        final copyLen = ivSlice.length < 8 ? ivSlice.length : 8;
        counter.setRange(0, copyLen, ivSlice);

        cipher.init(false, ParametersWithIV(KeyParameter(contentKey), counter));
        final framePlaintext = Uint8List(frameCiphertext.length);
        cipher.processBytes(frameCiphertext, 0, frameCiphertext.length, framePlaintext, 0);

        decryptedFrames.add(framePlaintext);
        totalDecryptedBytes += framePlaintext.length;
      }
    }

    final result = Uint8List(totalDecryptedBytes);
    var pos = 0;
    for (final frame in decryptedFrames) {
      result.setRange(pos, pos + frame.length, frame);
      pos += frame.length;
    }
    return result;
  }

  static Iterable<_Mp4Atom> _parseAtoms(Uint8List bytes) sync* {
    final view = ByteData.sublistView(bytes);
    var offset = 0;
    while (offset + 8 <= bytes.length) {
      var size = view.getUint32(offset, Endian.big);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (size == 1) {
        size = bytes.length - offset;
      }
      if (size < 8 || offset + size > bytes.length) return;
      yield _Mp4Atom(type: type, start: offset, end: offset + size);
      offset += size;
    }
  }

  static bool _matchesBytes(Uint8List buf, Uint8List target, int offset) {
    if (buf.length < offset + target.length) return false;
    for (var i = 0; i < target.length; i++) {
      if (buf[offset + i] != target[i]) return false;
    }
    return true;
  }

  static int _findPattern(Uint8List buf, List<int> pattern) {
    for (var i = 0; i <= buf.length - pattern.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (buf[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  static String _bytesToBase64Url(Uint8List bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Uint8List _base64UrlToBytes(String str) {
    var b64 = str.replaceAll('-', '+').replaceAll('_', '/');
    while (b64.length % 4 != 0) {
      b64 += '=';
    }
    return base64Decode(b64);
  }

  static Uint8List hexToBytes(String hex) => _hexToBytes(hex);

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}

class _Mp4Atom {
  final String type;
  final int start;
  final int end;
  _Mp4Atom({required this.type, required this.start, required this.end});
}

class QobuzSegmentTableEntry {
  final int byteLength;
  final int sampleCount;
  QobuzSegmentTableEntry({required this.byteLength, required this.sampleCount});
}

class QobuzSegment0Info {
  final String kind;
  final Uint8List header;
  final List<QobuzSegmentTableEntry> table;
  QobuzSegment0Info({required this.kind, required this.header, required this.table});
}

