// Copyright © 2026 wizeshi

import 'dart:convert';

import 'package:flutter/foundation.dart';

class JsonUtils {
  /// Threshold in characters (~50KB) above which JSON parsing is offloaded to a background isolate.
  static const int _isolateThreshold = 50000;

  /// Decodes JSON data, offloading large payloads to an isolate while parsing small payloads synchronously for speed.
  static Future<dynamic> decode(String source) async {
    if (source.length < _isolateThreshold) {
      return jsonDecode(source);
    }
    return compute(jsonDecode, source);
  }
}
