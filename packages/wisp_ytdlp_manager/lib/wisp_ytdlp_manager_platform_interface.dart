import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'wisp_ytdlp_manager_method_channel.dart';

abstract class WispYtdlpManagerPlatform extends PlatformInterface {
  /// Constructs a WispYtdlpManagerPlatform.
  WispYtdlpManagerPlatform() : super(token: _token);

  static final Object _token = Object();

  static WispYtdlpManagerPlatform _instance = MethodChannelWispYtdlpManager();

  /// The default instance of [WispYtdlpManagerPlatform] to use.
  ///
  /// Defaults to [MethodChannelWispYtdlpManager].
  static WispYtdlpManagerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [WispYtdlpManagerPlatform] when
  /// they register themselves.
  static set instance(WispYtdlpManagerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
