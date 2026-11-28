// Copyright © 2026 wizeshi

import 'dart:convert';

import 'package:flutter/foundation.dart';

class JsonUtils {
  /// Threshold in characters (~50KB) above which JSON parsing is offloaded to a background isolate.
  static const int _isolateThreshold = 50000;

  /// Threshold in list items above which JSON encoding is offloaded to a background isolate.
  static const int _encodeIsolateListThreshold = 200;

  /// Decodes JSON data, offloading large payloads to an isolate while parsing small payloads synchronously for speed.
  static Future<dynamic> decode(String source) async {
    if (source.length < _isolateThreshold) {
      return jsonDecode(source);
    }
    return compute(jsonDecode, source);
  }

  /// Encodes JSON data, offloading large lists to an isolate while encoding small payloads synchronously for speed.
  static Future<String> encode(Object? value, {int itemCountHint = 0}) async {
    final effectiveCount =
        itemCountHint > 0 ? itemCountHint : (value is List ? value.length : 0);
    if (effectiveCount < _encodeIsolateListThreshold) {
      return jsonEncode(value);
    }
    return compute(_encodeInIsolate, value);
  }

  static String _encodeInIsolate(Object? value) => jsonEncode(value);
}
