// Copyright © 2026 wizeshi

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/sources/providers/crypto_bridge_utils.dart';

void main() {
  group('CryptoBridgeUtils Tests', () {
    test('generateTotp matches standard RFC 6238 output', () {
      // Standard RFC 6238 test vectors: Secret = "12345678901234567890" -> Base32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
      const base32Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      // At Unix timestamp 59s:
      final otp1 = CryptoBridgeUtils.generateTotp(base32Secret, timestampMs: 59000);
      expect(otp1, '287082');

      // At Unix timestamp 1111111109s:
      final otp2 = CryptoBridgeUtils.generateTotp(base32Secret, timestampMs: 1111111109000);
      expect(otp2, '081804');
    });

    test('sha1 and sha256 hex tests', () {
      expect(CryptoBridgeUtils.sha1Hex('hello world'), '2aae6c35c94fcfb415dbe95f408b9ce91ee846ed');
      expect(CryptoBridgeUtils.sha256Hex('hello world'), 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9');
    });

    test('randomHex generates correct length', () {
      final hex = CryptoBridgeUtils.randomHex(32);
      expect(hex.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(hex), isTrue);
    });

    test('Spotify secret transformation to base32 produces valid TOTP', () {
      const secretValue = 'TEST_SECRET_VALUE_123';
      const secretSauce = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

      final secretCipherBytes = <int>[];
      for (var i = 0; i < secretValue.length; i++) {
        secretCipherBytes.add(secretValue.codeUnitAt(i) ^ ((i % 33) + 9));
      }
      final cipherString = secretCipherBytes.join('');
      final cipherBytes = utf8.encode(cipherString);

      var t = 0;
      var n = 0;
      final buffer = StringBuffer();
      for (var i = 0; i < cipherBytes.length; i++) {
        n = (n << 8) | cipherBytes[i];
        t += 8;
        while (t >= 5) {
          buffer.write(secretSauce[(n >> (t - 5)) & 31]);
          t -= 5;
        }
      }
      if (t > 0) {
        buffer.write(secretSauce[(n << (5 - t)) & 31]);
      }
      final base32Secret = buffer.toString();

      final otp = CryptoBridgeUtils.generateTotp(base32Secret);
      expect(otp.length, 6);
      expect(int.tryParse(otp), isNotNull);
    });
  });
}
