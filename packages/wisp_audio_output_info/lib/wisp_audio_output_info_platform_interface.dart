import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wisp_audio_output_info/models/types.dart';

import 'wisp_audio_output_info_method_channel.dart';

abstract class WispAudioOutputInfoPlatform extends PlatformInterface {
  WispAudioOutputInfoPlatform() : super(token: _token);

  static final Object _token = Object();

  static WispAudioOutputInfoPlatform _instance =
      MethodChannelWispAudioOutputInfo();

  static WispAudioOutputInfoPlatform get instance => _instance;

  static set instance(WispAudioOutputInfoPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<List<AudioOutputDevice>> get outputDevices {
    throw UnimplementedError(
      'outputDevices has not been implemented.',
    );
  }

  Stream<AudioOutputDevice?> get activeOutputDevice {
    throw UnimplementedError(
      'activeOutputDevice has not been implemented.',
    );
  }

  Future<AudioOutputDevice?> getCurrentOutput() {
    throw UnimplementedError(
      'getCurrentOutput() has not been implemented.',
    );
  }

  Future<List<AudioOutputDevice>> getOutputDevices() {
    throw UnimplementedError(
      'getOutputDevices() has not been implemented.',
    );
  }
}