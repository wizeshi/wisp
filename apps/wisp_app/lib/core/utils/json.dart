import 'dart:convert';

import 'package:flutter/foundation.dart';

class JsonUtils {
  /// A simple function to decode JSON data in a separate isolate to avoid blocking the main thread.
  static Future<dynamic> decode(String source) async {
    final jsonList = await compute(jsonDecode, source);
    return jsonList;
  }
}
