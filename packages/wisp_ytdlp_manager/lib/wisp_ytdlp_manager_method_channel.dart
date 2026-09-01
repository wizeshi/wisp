import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wisp_ytdlp_manager_platform_interface.dart';

/// An implementation of [WispYtdlpManagerPlatform] that uses method channels.
class MethodChannelWispYtdlpManager extends WispYtdlpManagerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('wisp_ytdlp_manager');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
