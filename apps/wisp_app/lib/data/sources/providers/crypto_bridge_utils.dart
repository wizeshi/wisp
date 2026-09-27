// Copyright © 2026 wizeshi

library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Cryptographic utilities exposed to JavaScript providers.
class CryptoBridgeUtils {
  CryptoBridgeUtils._();

  /// Calculates RFC 6238 TOTP code from a base32 encoded secret.
  static String generateTotp(
    String base32Secret, {
    int digits = 6,
    int interval = 30,
    int? timestampMs,
  }) {
    final secretBytes = decodeBase32(base32Secret);
    final timestamp =
        (timestampMs ?? DateTime.now().millisecondsSinceEpoch) ~/ 1000;
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

  /// Decodes base32 string into raw bytes.
  static Uint8List decodeBase32(String input) {
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

  /// Computes SHA-1 hash of an input string in hexadecimal.
  static String sha1Hex(String input) {
    return sha1.convert(utf8.encode(input)).toString();
  }

  /// Computes SHA-256 hash of an input string in hexadecimal.
  static String sha256Hex(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Computes HMAC-SHA1 of data using given secret key.
  static String hmacSha1Hex(String key, String data) {
    final hmac = Hmac(sha1, utf8.encode(key));
    return hmac.convert(utf8.encode(data)).toString();
  }

  /// Generates a cryptographically secure random hexadecimal string of given length.
  static String randomHex(int length) {
    const hex = '0123456789abcdef';
    final rand = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(hex[rand.nextInt(16)]);
    }
    return buffer.toString();
  }

  /// Creates a standard HTTP client suitable for JS provider bridges.
  static dynamic createBridgeHttpClient() {
    final ioClient = HttpClient();
    ioClient.badCertificateCallback = (cert, host, port) => true;
    return ioClient;
  }
}

